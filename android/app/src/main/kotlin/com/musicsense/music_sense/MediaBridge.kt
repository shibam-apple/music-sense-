package com.musicsense.music_sense

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Native side of the local library and of Beat Sense analysis:
 * lists songs from MediaStore, loads their artwork, and decodes audio
 * (local or streamed) to mono float PCM for the Dart analyser.
 */
class MediaBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val PERMISSION_REQUEST = 7341
    }

    private var pendingPermission: MethodChannel.Result? = null

    private val channel = MethodChannel(messenger, "music_sense/media")
    private val worker = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestAudioPermission" -> requestAudioPermission(result)
            "queryAudio" -> background(result) { queryAudio() }
            "artwork" -> background(result) {
                artwork(call.argument<Number>("id")!!.toLong(), call.argument<Int>("size") ?: 512)
            }
            "decodePcm" -> background(result) {
                decodePcm(
                    call.argument<String>("uri")!!,
                    call.argument<Map<String, String>>("headers") ?: emptyMap(),
                    call.argument<Int>("sampleRate") ?: 22050,
                    call.argument<Int>("maxSeconds") ?: 900,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun audioPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_AUDIO, Manifest.permission.POST_NOTIFICATIONS)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    private fun hasAudioPermission(): Boolean =
        context.checkSelfPermission(audioPermissions().first()) == PackageManager.PERMISSION_GRANTED

    /** Asks for access to the music library (and notifications on 13+). */
    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "A permission request is already showing", null)
            return
        }
        pendingPermission = result
        activity.requestPermissions(audioPermissions(), PERMISSION_REQUEST)
    }

    /** Forwarded from the activity. */
    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermission?.success(hasAudioPermission())
        pendingPermission = null
        return true
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("media_error", e.message, null) }
            }
        }
    }

    private fun queryAudio(): List<Map<String, Any?>> {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.DATE_ADDED,
        )
        val selection =
            "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} >= 30000"
        val songs = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            collection, projection, selection, null,
            "${MediaStore.Audio.Media.DATE_ADDED} DESC",
        )?.use { c ->
            val id = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val title = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val album = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumId = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val duration = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val track = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val year = c.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            val added = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            while (c.moveToNext()) {
                val songId = c.getLong(id)
                songs.add(
                    mapOf(
                        "id" to songId,
                        "title" to c.getString(title),
                        "artist" to c.getString(artist),
                        "album" to c.getString(album),
                        "albumId" to c.getLong(albumId),
                        "durationMs" to c.getLong(duration),
                        "track" to c.getInt(track),
                        "year" to c.getInt(year),
                        "dateAdded" to c.getLong(added),
                        "uri" to ContentUris.withAppendedId(collection, songId).toString(),
                    )
                )
            }
        }
        return songs
    }

    /** JPEG bytes of the song's cover, or null when it has none. */
    private fun artwork(id: Long, size: Int): ByteArray? {
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return try {
                val bitmap = context.contentResolver.loadThumbnail(uri, Size(size, size), null)
                ByteArrayOutputStream().use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                    out.toByteArray()
                }
            } catch (e: Exception) {
                null
            }
        }
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            retriever.embeddedPicture
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /**
     * Decodes [uri] (content://, file:// or https://) to mono float32 PCM at
     * [targetRate], little-endian, at most [maxSeconds] long.
     */
    private fun decodePcm(
        uri: String,
        headers: Map<String, String>,
        targetRate: Int,
        maxSeconds: Int,
    ): ByteArray {
        val extractor = MediaExtractor()
        val parsed = Uri.parse(uri)
        if (parsed.scheme == "http" || parsed.scheme == "https") {
            extractor.setDataSource(uri, headers)
        } else {
            extractor.setDataSource(context, parsed, null)
        }

        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                trackIndex = i
                format = f
                break
            }
        }
        if (format == null) {
            extractor.release()
            throw IllegalArgumentException("No audio track in $uri")
        }
        extractor.selectTrack(trackIndex)

        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()

        var sourceRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var floatPcm = false
        val resampler = MonoResampler(targetRate)
        val limit = targetRate.toLong() * maxSeconds
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false

        try {
            while (!outputDone && resampler.count < limit) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buffer = codec.getInputBuffer(inIndex)!!
                        val read = extractor.readSampleData(buffer, 0)
                        if (read < 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, read, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val out = codec.outputFormat
                        sourceRate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floatPcm = out.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            out.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    }
                    outIndex >= 0 -> {
                        val buffer = codec.getOutputBuffer(outIndex)!!
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        resampler.push(buffer.order(ByteOrder.nativeOrder()), channels, sourceRate, floatPcm)
                        codec.releaseOutputBuffer(outIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }
        } finally {
            codec.stop()
            codec.release()
            extractor.release()
        }
        return resampler.toBytes()
    }
}

/**
 * Downmixes interleaved PCM to mono and resamples it by averaging each
 * output sample's span of input (a box filter, which also suppresses
 * aliasing well enough for rhythm and key analysis).
 */
private class MonoResampler(private val targetRate: Int) {
    private var out = FloatArray(targetRate * 60)
    var count = 0
        private set

    private var position = 0.0 // input samples into the current output sample
    private var sum = 0.0
    private var taken = 0

    fun push(buffer: ByteBuffer, channels: Int, sourceRate: Int, float: Boolean) {
        val step = sourceRate.toDouble() / targetRate
        if (float) {
            val samples = buffer.asFloatBuffer()
            while (samples.remaining() >= channels) {
                var mono = 0f
                for (c in 0 until channels) mono += samples.get()
                accept(mono / channels, step)
            }
        } else {
            val samples = buffer.asShortBuffer()
            while (samples.remaining() >= channels) {
                var mono = 0f
                for (c in 0 until channels) mono += samples.get() / 32768f
                accept(mono / channels, step)
            }
        }
    }

    private fun accept(sample: Float, step: Double) {
        sum += sample
        taken++
        position += 1.0
        if (position >= step) {
            position -= step
            if (count == out.size) out = out.copyOf(out.size * 2)
            out[count++] = (sum / taken).toFloat()
            sum = 0.0
            taken = 0
        }
    }

    fun toBytes(): ByteArray {
        val bytes = ByteBuffer.allocate(count * 4).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until count) bytes.putFloat(out[i])
        return bytes.array()
    }
}
