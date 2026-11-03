package com.musicsense.music_sense.engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The Beat Sense audio engine on Android: the [Mixer] rendered by a
 * dedicated audio thread into an AudioTrack, with audio focus (pause for
 * calls, duck for notifications) and a pause when headphones come out.
 * Flutter drives it over "music_sense/engine" and hears back on
 * "music_sense/engine/events".
 */
class NativeEngine(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, Mixer.Listener {

    private val rate = AudioTrack.getNativeOutputSampleRate(AudioManager.STREAM_MUSIC)
        .takeIf { it in 8000..192000 } ?: 48000
    private val mixer = Mixer(rate).also { it.listener = this }
    private val methods = MethodChannel(messenger, "music_sense/engine")
    private val events = EventChannel(messenger, "music_sense/engine/events")
    private val main = Handler(Looper.getMainLooper())
    private val loader = Executors.newSingleThreadExecutor()
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var sink: EventChannel.EventSink? = null

    private var masterDecode: Decoder.Opened? = null
    private var nextDecode: Decoder.Opened? = null

    @Volatile private var wantPlaying = false
    @Volatile private var volume = 1f
    private var resumeAfterFocus = false
    private var noisyRegistered = false

    private val track: AudioTrack = run {
        val min = AudioTrack.getMinBufferSize(
            rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_FLOAT,
        )
        AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build(),
            )
            .setBufferSizeInBytes(maxOf(min, Stretcher.HOP * 2 * 4 * 8))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        Thread({ audioLoop() }, "beat-sense-audio").apply { isDaemon = true }.start()
    }

    /** Renders block after block; while paused it only applies commands. */
    private fun audioLoop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        val block = FloatArray(Stretcher.HOP * 2)
        var started = false
        while (true) {
            mixer.render(block)
            if (mixer.playing) {
                if (!started) {
                    track.play()
                    started = true
                }
                val v = volume
                if (v != 1f) for (i in block.indices) block[i] *= v
                track.write(block, 0, block.size, AudioTrack.WRITE_BLOCKING)
            } else {
                if (started) {
                    track.pause()
                    track.flush()
                    started = false
                }
                Thread.sleep(15)
            }
        }
    }

    // ---- Mixer events (audio thread) -> Flutter ----

    override fun onEvent(name: String, master: Int) {
        main.post { sink?.success(mapOf("type" to name, "master" to master)) }
        if (name == "ended") main.post { wantPlaying = false }
    }

    private val tick = object : Runnable {
        override fun run() {
            sink?.success(status())
            main.postDelayed(this, 100)
        }
    }

    private fun status() = mapOf(
        "type" to "tick",
        "master" to mixer.master,
        "position" to mixer.masterSeconds,
        "other" to mixer.otherSeconds,
        "playing" to mixer.playing,
        "mixing" to mixer.mixing,
    )

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        main.removeCallbacks(tick)
        main.post(tick)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        main.removeCallbacks(tick)
    }

    // ---- Flutter -> engine ----

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> result.success(mapOf("sampleRate" to rate))
            "loadMaster" -> load(call, result, master = true)
            "loadNext" -> load(call, result, master = false)
            "play" -> {
                play()
                result.success(null)
            }
            "pause" -> {
                pause()
                result.success(null)
            }
            "seek" -> {
                val s = call.argument<Double>("seconds") ?: 0.0
                mixer.post { it.seekMaster(s) }
                result.success(null)
            }
            "setTransition" -> {
                val script = parseScript(call)
                mixer.post { it.setTransition(script) }
                result.success(null)
            }
            "clearTransition" -> {
                mixer.post { it.cancelTransition() }
                result.success(null)
            }
            "finishTransition" -> {
                mixer.post { it.finishTransition() }
                result.success(null)
            }
            "setGain" -> {
                val db = (call.argument<Double>("db") ?: 0.0).toFloat()
                val next = call.argument<String>("deck") == "next"
                mixer.post { it.setDeckGain(if (next) it.other else it.master, db) }
                result.success(null)
            }
            "setTone" -> {
                val semitones = call.argument<Double>("semitones") ?: 0.0
                mixer.post { it.setMasterTone(semitones) }
                result.success(null)
            }
            "status" -> result.success(status())
            else -> result.notImplemented()
        }
    }

    private fun load(call: MethodCall, result: MethodChannel.Result, master: Boolean) {
        val uri = call.argument<String>("uri")!!
        val at = call.argument<Double>("at") ?: 0.0
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        loader.execute {
            try {
                val opened = Decoder.open(context, uri, headers)
                if (master) {
                    masterDecode?.cancel?.invoke()
                    nextDecode?.cancel?.invoke()
                    masterDecode = opened
                    nextDecode = null
                    mixer.post { it.loadMaster(opened.buffer, at) }
                } else {
                    nextDecode?.cancel?.invoke()
                    nextDecode = opened
                    mixer.post { it.loadNext(opened.buffer) }
                }
                main.post { result.success(mapOf("duration" to opened.durationSeconds)) }
            } catch (e: Throwable) {
                main.post { result.error("decode", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseScript(call: MethodCall): TransitionScript {
        val raw = call.argument<Map<String, List<Double>>>("lanes") ?: emptyMap()
        val lanes = raw.mapValues { (_, flat) ->
            val n = flat.size / 2
            Lane(
                DoubleArray(n) { flat[it * 2] },
                FloatArray(n) { flat[it * 2 + 1].toFloat() },
            )
        }
        return TransitionScript(
            exit = call.argument<Double>("exit")!!,
            entry = call.argument<Double>("entry")!!,
            length = call.argument<Double>("length")!!,
            rate = call.argument<Double>("rate") ?: 1.0,
            semitones = call.argument<Double>("semitones") ?: 0.0,
            rampBack = call.argument<Double>("rampBack") ?: 0.0,
            lanes = lanes,
        )
    }

    // ---- Playing, focus and headphones ----

    private fun play() {
        if (!requestFocus()) return
        wantPlaying = true
        volume = 1f
        mixer.post { it.setPlaying(true) }
        if (!noisyRegistered) {
            val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(noisy, filter)
            }
            noisyRegistered = true
        }
    }

    private fun pause(fromSystem: Boolean = false) {
        wantPlaying = false
        mixer.post { it.setPlaying(false) }
        if (fromSystem) main.post { sink?.success(mapOf("type" to "paused")) }
    }

    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) pause(fromSystem = true)
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeAfterFocus = false
                pause(fromSystem = true)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeAfterFocus = wantPlaying
                pause(fromSystem = true)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> volume = 0.25f
            AudioManager.AUDIOFOCUS_GAIN -> {
                volume = 1f
                if (resumeAfterFocus) {
                    resumeAfterFocus = false
                    play()
                    main.post { sink?.success(mapOf("type" to "resumed")) }
                }
            }
        }
    }

    private val focusRequest: AudioFocusRequest? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
        } else null
    }

    @Suppress("DEPRECATION")
    private fun requestFocus(): Boolean {
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audio.requestAudioFocus(focusRequest!!)
        } else {
            audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        return granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }
}
