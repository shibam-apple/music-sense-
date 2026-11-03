package com.musicsense.music_sense.engine

import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow

/** A value over time: straight lines between (time, value) points. */
class Lane(private val times: DoubleArray, private val values: FloatArray) {
    init {
        require(times.size == values.size && times.isNotEmpty())
    }

    fun at(t: Double): Float {
        if (t <= times[0]) return values[0]
        for (i in 1 until times.size) {
            if (t < times[i]) {
                val f = (t - times[i - 1]) / (times[i] - times[i - 1])
                return (values[i - 1] + (values[i] - values[i - 1]) * f).toFloat()
            }
        }
        return values.last()
    }

    companion object {
        fun constant(v: Float) = Lane(doubleArrayOf(0.0), floatArrayOf(v))
    }
}

/**
 * One transition, as the Beat Sense planner wrote it. Times are seconds
 * in the playing (outgoing) song. The incoming song is locked to it:
 * `incoming = entry + (outgoing - exit) * rate`, so every beat lands
 * together for as long as they overlap.
 */
class TransitionScript(
    val exit: Double,
    val entry: Double,
    val length: Double,
    /** Incoming song's source seconds per outgoing song's source second. */
    val rate: Double,
    /** Key shift for the incoming song, kept after the mix. */
    val semitones: Double,
    /** Real seconds over which the incoming song eases to its own tempo. */
    val rampBack: Double,
    /** "out" and "in" lanes: gain (0-1), low/mid/high (dB), filter (-1..1). */
    val lanes: Map<String, Lane>,
) {
    fun lane(name: String, default: Float) = lanes[name] ?: Lane.constant(default)

    companion object {
        /** Silent pre-roll so the incoming grains are flowing when heard. */
        const val PRE_ROLL = 0.5
    }
}

/** One turntable: a song, its tempo and key, its EQ, filter and volume. */
class Deck(private val outRate: Int) {
    var buffer: PcmBuffer? = null
        private set

    /** Where the next grain starts, in source frames. */
    var position = 0.0
    /** Source seconds per real second (1 = normal speed). */
    var tempo = 1.0
    var semitones = 0.0
    var gainDb = 0f
    var playing = false

    private var rampFrom = 1.0
    private var rampSeconds = 0.0
    private var rampDone = 0.0

    private val stretcher = Stretcher()
    private val eq = arrayOf(ThreeBand(outRate), ThreeBand(outRate))
    private val filters = arrayOf(DjFilter(outRate), DjFilter(outRate))
    val gain = Smoothed(1f, outRate)
    val low = Smoothed(0f, outRate)
    val mid = Smoothed(0f, outRate)
    val high = Smoothed(0f, outRate)
    val filter = Smoothed(0f, outRate)
    private val loudness = Smoothed(1f, outRate, 50f)
    private val grain = FloatArray(Stretcher.HOP * 2)

    val seconds: Double get() = buffer?.let { position / it.sampleRate } ?: 0.0
    val ended: Boolean get() = buffer?.let { it.complete && position >= it.frames } ?: true

    fun load(b: PcmBuffer?, atSeconds: Double) {
        buffer = b
        position = atSeconds * (b?.sampleRate ?: outRate)
        tempo = 1.0
        semitones = 0.0
        rampSeconds = 0.0
        stretcher.reset()
        eq.forEach { it.reset() }
        neutral(snap = true)
        playing = false
    }

    fun seek(seconds: Double) {
        val b = buffer ?: return
        position = seconds * b.sampleRate
        stretcher.reset()
        gain.snap(0f) // fade in from silence: no click
        gain.target = 1f
    }

    fun neutral(snap: Boolean = false) {
        for ((p, v) in listOf(gain to 1f, low to 0f, mid to 0f, high to 0f, filter to 0f)) {
            if (snap) p.snap(v) else p.target = v
        }
    }

    /** Eases the tempo from [from] to 1 over [seconds] of playing. */
    fun rampTempo(from: Double, seconds: Double) {
        tempo = from
        rampFrom = from
        rampSeconds = seconds
        rampDone = 0.0
    }

    private val sourceRate: Int get() = buffer?.sampleRate ?: outRate

    /** Source frames per output frame for reading grains (sets the pitch). */
    private val step: Double
        get() = 2.0.pow(semitones / 12.0) * sourceRate / outRate

    /**
     * Renders one block, adding it into [mix]. With [lockedAt] (seconds in
     * this song) the deck follows another deck instead of its own clock.
     */
    fun render(mix: FloatArray, lockedAt: Double? = null) {
        val b = buffer ?: return
        if (!playing) return
        val start = if (lockedAt != null) lockedAt * b.sampleRate else position
        stretcher.render(b, start, step, grain)
        val blockSeconds = Stretcher.HOP.toDouble() / outRate
        if (lockedAt == null) {
            position = start + Stretcher.HOP * tempo * b.sampleRate / outRate
            if (rampSeconds > 0) {
                rampDone += blockSeconds
                val t = (rampDone / rampSeconds).coerceAtMost(1.0)
                tempo = rampFrom + (1 - rampFrom) * t
                if (t >= 1) rampSeconds = 0.0
            }
        } else {
            position = start + Stretcher.HOP * tempo * b.sampleRate / outRate
        }
        loudness.target = dbToGain(gainDb)
        for (i in 0 until Stretcher.HOP) {
            val g = gain.next() * loudness.next()
            val lo = dbToGain(low.next())
            val mi = dbToGain(mid.next())
            val hi = dbToGain(high.next())
            val f = filter.next()
            for (c in 0..1) {
                var x = grain[i * 2 + c]
                x = eq[c].process(x, lo, mi, hi)
                x = filters[c].process(x, f)
                mix[i * 2 + c] += x * g
            }
        }
    }
}

/**
 * The mixer: two decks into one output, the playing ("master") deck on
 * its own clock and, during a transition, the other deck locked to it
 * beat for beat. Commands from other threads are queued and applied
 * between blocks, so the audio thread never waits.
 */
class Mixer(val outRate: Int) {
    interface Listener {
        fun onEvent(name: String, master: Int)
    }

    var listener: Listener? = null
    val decks = arrayOf(Deck(outRate), Deck(outRate))

    @Volatile var master = 0
        private set
    @Volatile var playing = false
        private set
    @Volatile var mixing = false
        private set
    /** Seconds into the master and the other song, for the UI. */
    @Volatile var masterSeconds = 0.0
        private set
    @Volatile var otherSeconds = 0.0
        private set

    private var script: TransitionScript? = null
    private var mixStartSent = false
    private var endedSent = false
    private val commands = ConcurrentLinkedQueue<(Mixer) -> Unit>()
    private val limiter = Limiter(outRate)

    val other: Int get() = 1 - master

    fun post(command: (Mixer) -> Unit) {
        commands.add(command)
    }

    // ---- Commands (run on the audio thread via [post]) ----

    fun loadMaster(buffer: PcmBuffer, atSeconds: Double) {
        cancelTransition()
        decks[other].load(null, 0.0)
        decks[master].load(buffer, atSeconds)
        decks[master].playing = playing
        endedSent = false
    }

    fun loadNext(buffer: PcmBuffer) {
        cancelTransition()
        decks[other].load(buffer, 0.0)
    }

    fun setPlaying(on: Boolean) {
        playing = on
        decks[master].playing = on
        if (mixing) decks[other].playing = on
    }

    fun seekMaster(seconds: Double) {
        if (mixing) cancelTransition()
        decks[master].seek(seconds)
        endedSent = false
    }

    fun setTransition(s: TransitionScript?) {
        if (mixing) return // a running mix isn't replaced; finish or cancel it
        script = s
        mixStartSent = false
    }

    fun cancelTransition() {
        script = null
        if (mixing) {
            mixing = false
            decks[other].playing = false
            decks[master].neutral()
        }
        mixStartSent = false
    }

    /** Jumps to the end of a running mix (Next during a mix). */
    fun finishTransition() {
        val s = script ?: return
        if (!mixing) return
        finish(s)
    }

    fun setDeckGain(deck: Int, db: Float) {
        decks[deck].gainDb = db
    }

    fun setMasterTone(semitones: Double) {
        decks[master].semitones = semitones
    }

    // ---- Audio thread ----

    /** Renders one block of [Stretcher.HOP] stereo frames into [out]. */
    fun render(out: FloatArray) {
        while (true) commands.poll()?.invoke(this) ?: break
        out.fill(0f)
        if (!playing) return
        val a = decks[master]
        val b = decks[other]
        val s = script
        val aNow = a.seconds

        if (s != null && b.buffer != null) {
            if (!mixing && aNow >= s.exit - TransitionScript.PRE_ROLL) {
                mixing = true
                b.semitones = s.semitones
                b.tempo = s.rate * a.tempo
                b.playing = true
            }
            if (mixing) {
                for ((p, name) in listOf(
                    a.gain to "outGain", a.low to "outLow", a.mid to "outMid",
                    a.high to "outHigh", a.filter to "outFilter",
                )) p.target = s.lane(name, if (name == "outGain") 1f else 0f).at(aNow)
                for ((p, name) in listOf(
                    b.gain to "inGain", b.low to "inLow", b.mid to "inMid",
                    b.high to "inHigh", b.filter to "inFilter",
                )) p.target = s.lane(name, 0f).at(aNow)
                if (!mixStartSent && aNow >= s.exit) {
                    mixStartSent = true
                    listener?.onEvent("mixStart", master)
                }
            }
        }

        a.render(out)
        if (mixing && s != null) {
            b.render(out, lockedAt = s.entry + (aNow - s.exit) * s.rate)
            if (aNow >= s.exit + s.length || a.ended) finish(s)
        }

        // Keep the sum from clipping.
        for (i in 0 until Stretcher.HOP) {
            val peak = max(abs(out[i * 2]), abs(out[i * 2 + 1]))
            val g = limiter.gainFor(peak)
            out[i * 2] *= g
            out[i * 2 + 1] *= g
        }

        val m = decks[master]
        masterSeconds = m.seconds
        otherSeconds = decks[other].seconds
        if (!mixing && m.ended && !endedSent) {
            endedSent = true
            m.playing = false
            listener?.onEvent("ended", master)
        }
    }

    private fun finish(s: TransitionScript) {
        val a = decks[master]
        val b = decks[other]
        val tempo = s.rate * a.tempo
        a.playing = false
        a.load(null, 0.0)
        b.neutral()
        b.rampTempo(tempo, s.rampBack)
        script = null
        mixing = false
        mixStartSent = false
        endedSent = false
        master = other
        masterSeconds = b.seconds
        listener?.onEvent("mixEnd", master)
    }
}
