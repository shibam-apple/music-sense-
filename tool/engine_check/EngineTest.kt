package com.musicsense.music_sense.engine

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Tests for the Beat Sense audio engine, run on a plain JVM
 * (tool/engine_check.sh): no phone needed.
 */

private var failures = 0

private fun check(name: String, ok: Boolean, detail: String) {
    println("${if (ok) "PASS" else "FAIL"}  $name: $detail")
    if (!ok) failures++
}

private const val OUT = 48000

private fun tone(freq: Double, seconds: Double, rate: Int = 44100, level: Double = 0.5): PcmBuffer {
    val n = (seconds * rate).toInt()
    val data = ShortArray(n * 2)
    for (i in 0 until n) {
        val v = (sin(2 * PI * freq * i / rate) * level * 32767).toInt().toShort()
        data[i * 2] = v
        data[i * 2 + 1] = v
    }
    return PcmBuffer(rate).apply { append(data, n); finish() }
}

/** Short clicks on every beat (a decaying 2 kHz burst, 4 ms). */
private fun clicks(bpm: Double, seconds: Double, rate: Int): PcmBuffer {
    val n = (seconds * rate).toInt()
    val data = ShortArray(n * 2)
    val beat = 60.0 / bpm
    var t = 0.0
    while (t < seconds) {
        val start = (t * rate).toInt()
        for (k in 0 until (0.004 * rate).toInt()) {
            if (start + k >= n) break
            val env = 1 - k / (0.004 * rate)
            val v = (sin(2 * PI * 2000 * k / rate) * env * 0.8 * 32767).toInt().toShort()
            data[(start + k) * 2] = v
            data[(start + k) * 2 + 1] = v
        }
        t += beat
    }
    return PcmBuffer(rate).apply { append(data, n); finish() }
}

private fun noise(seconds: Double, rate: Int): FloatArray {
    val r = java.util.Random(7)
    return FloatArray((seconds * rate).toInt()) { (r.nextGaussian() * 0.2).toFloat() }
}

private fun rms(x: FloatArray, from: Int = 0): Double {
    var s = 0.0
    for (i in from until x.size) s += x[i] * x[i]
    return sqrt(s / (x.size - from))
}

/** Frequency of a tone from its rising zero crossings. */
private fun frequency(left: FloatArray, rate: Int): Double {
    var first = -1.0
    var last = -1.0
    var count = 0
    for (i in 1 until left.size) {
        if (left[i - 1] < 0 && left[i] >= 0) {
            val t = i - 1 + (-left[i - 1] / (left[i] - left[i - 1])).toDouble()
            if (first < 0) first = t else count++
            last = t
        }
    }
    return count / ((last - first) / rate)
}

/** Renders [blocks] mixer blocks; returns the left channel. */
private fun run(mixer: Mixer, blocks: Int): FloatArray {
    val out = FloatArray(Stretcher.HOP * 2)
    val left = FloatArray(blocks * Stretcher.HOP)
    for (b in 0 until blocks) {
        mixer.render(out)
        for (i in 0 until Stretcher.HOP) left[b * Stretcher.HOP + i] = out[i * 2]
    }
    return left
}

private fun mixerWith(buffer: PcmBuffer, at: Double = 0.0): Mixer {
    val m = Mixer(OUT)
    m.post { it.loadMaster(buffer, at) }
    m.post { it.setPlaying(true) }
    return m
}

fun main() {
    // 1. At normal speed (same sample rate) the tempo/key shifter passes
    // audio through unchanged, sample for sample.
    run {
        val src = tone(440.0, 2.0, rate = OUT, level = 0.3)
        val stretcher = Stretcher()
        val out = FloatArray(Stretcher.HOP * 2)
        var worst = 0.0
        for (b in 0 until 100) {
            stretcher.render(src, b * Stretcher.HOP.toDouble(), 1.0, out)
            if (b == 0) continue // the very first grain fades in
            for (i in 0 until Stretcher.HOP) {
                val n = b * Stretcher.HOP + i
                worst = maxOf(worst, abs(out[i * 2] - src.at(n.toLong(), 0)).toDouble())
            }
        }
        check("passthrough", worst < 1e-4, "max error ${"%.2e".format(worst)}")

        // The whole deck (shifter, EQ, filter, volume) keeps the level.
        val m = mixerWith(tone(440.0, 4.0, rate = OUT, level = 0.3))
        val left = run(m, 200)
        val level = 20 * log10(rms(left, OUT / 2) / (0.3 / sqrt(2.0)))
        check("deck level", abs(level) < 0.2, "${"%.2f".format(level)} dB")
    }

    // 2. EQ at 0 dB on every band is flat: every frequency at its level.
    run {
        var worst = 0.0
        for (freq in listOf(40.0, 120.0, 250.0, 800.0, 3000.0, 6000.0, 12000.0)) {
            val eq = ThreeBand(OUT)
            val x = FloatArray(OUT) { i -> (sin(2 * PI * freq * i / OUT) * 0.5).toFloat() }
            val y = FloatArray(OUT) { i -> eq.process(x[i], 1f, 1f, 1f) }
            worst = maxOf(worst, abs(20 * log10(rms(y, OUT / 4) / rms(x, OUT / 4))))
        }
        check("eq flat", worst < 0.1, "worst ${"%.3f".format(worst)} dB")
    }

    // 3. Killing the low band removes the bass and keeps the mids.
    run {
        fun through(freq: Double, low: Float): Double {
            val eq = ThreeBand(OUT)
            val y = FloatArray(OUT) { i ->
                eq.process((sin(2 * PI * freq * i / OUT) * 0.5).toFloat(), low, 1f, 1f)
            }
            return rms(y, OUT / 4)
        }
        val bassCut = 20 * log10(through(60.0, 0f) / through(60.0, 1f))
        val midKept = 20 * log10(through(1000.0, 0f) / through(1000.0, 1f))
        check("bass kill", bassCut < -20, "60 Hz ${"%.1f".format(bassCut)} dB")
        check("mids kept", abs(midKept) < 1.5, "1 kHz ${"%.2f".format(midKept)} dB")
    }

    // 4. Faster tempo keeps the pitch (44.1 kHz song on a 48 kHz output).
    run {
        val m = mixerWith(tone(440.0, 6.0))
        m.post { it.decks[0].tempo = 1.06 }
        val left = run(m, 300) // ~3.2 s
        val f = frequency(left.copyOfRange(OUT / 2, left.size), OUT)
        val advanced = m.masterSeconds / (300.0 * Stretcher.HOP / OUT)
        check("tempo keeps pitch", abs(f - 440) < 440 * 0.01, "${"%.1f".format(f)} Hz")
        check("tempo speeds up", abs(advanced - 1.06) < 0.01, "x${"%.3f".format(advanced)}")
    }

    // 5. One semitone up, same tempo.
    run {
        val m = mixerWith(tone(440.0, 6.0))
        m.post { it.setMasterTone(1.0) }
        val left = run(m, 300)
        val f = frequency(left.copyOfRange(OUT / 2, left.size), OUT)
        val want = 440 * 2.0.pow(1 / 12.0)
        val advanced = m.masterSeconds / (300.0 * Stretcher.HOP / OUT)
        check("key shift", abs(f - want) < want * 0.01, "${"%.1f".format(f)} Hz (want ${"%.1f".format(want)})")
        check("key shift keeps tempo", abs(advanced - 1) < 0.01, "x${"%.3f".format(advanced)}")
    }

    // 6. Beat lock: a 124 BPM song (48 kHz) mixed into a 120 BPM one
    // (44.1 kHz). The incoming clicks must land on the outgoing beats.
    run {
        val a = clicks(120.0, 40.0, 44100)
        val b = clicks(124.0, 40.0, 48000)
        val m = Mixer(OUT)
        val events = mutableListOf<String>()
        m.listener = object : Mixer.Listener {
            override fun onEvent(name: String, master: Int) {
                events += "$name:$master"
            }
        }
        val exit = 10.0
        val entry = 10 * 60.0 / 124 // a B beat
        val rate = 120.0 / 124
        // Outgoing muted during the mix so only the incoming clicks are heard.
        val script = TransitionScript(
            exit = exit, entry = entry, length = 8.0, rate = rate,
            semitones = 0.0, rampBack = 4.0,
            lanes = mapOf(
                "outGain" to Lane(doubleArrayOf(exit, exit + 0.01), floatArrayOf(1f, 0f)),
                "inGain" to Lane(doubleArrayOf(exit, exit + 0.01), floatArrayOf(0f, 1f)),
            ),
        )
        m.post { it.loadMaster(a, 0.0) }
        m.post { it.loadNext(b) }
        m.post { it.setTransition(script) }
        m.post { it.setPlaying(true) }
        val blocks = (20.0 * OUT / Stretcher.HOP).toInt()
        val left = run(m, blocks)
        // A plays at normal speed from 0, so output time = A's time.
        val errors = mutableListOf<Double>()
        var i = (exit + 0.3) * OUT
        while (i < (exit + 7.5) * OUT) {
            val n = i.toInt()
            if (abs(left[n]) > 0.2 && abs(left[n - 1]) <= 0.2 && left.copyOfRange(n - 400, n - 1).all { abs(it) < 0.2 }) {
                val t = n.toDouble() / OUT
                val nearest = Math.round(t / 0.5) * 0.5
                errors += abs(t - nearest) * 1000
                i += 0.25 * OUT
            } else {
                i += 1
            }
        }
        val worst = errors.maxOrNull() ?: 999.0
        check(
            "beat lock",
            errors.size >= 12 && worst < 3.0,
            "${errors.size} beats, worst ${"%.2f".format(worst)} ms off",
        )
        check("mix events", events == listOf("mixStart:0", "mixEnd:1"), events.toString())
        check("incoming takes over", m.master == 1 && m.decks[1].playing, "master ${m.master}")
    }

    // 7. Two loud songs together never clip.
    run {
        val m = Mixer(OUT)
        val loud = tone(200.0, 10.0, level = 0.95)
        val also = tone(300.0, 10.0, level = 0.95)
        m.post { it.loadMaster(loud, 0.0) }
        m.post { it.loadNext(also) }
        m.post {
            it.setTransition(
                TransitionScript(
                    exit = 0.6, entry = 0.0, length = 5.0, rate = 1.0, semitones = 0.0,
                    rampBack = 0.0, lanes = mapOf("inGain" to Lane.constant(1f)),
                ),
            )
        }
        m.post { it.setPlaying(true) }
        val left = run(m, 400)
        val peak = left.maxOf { abs(it) }
        check("no clipping", peak <= 0.951f, "peak ${"%.3f".format(peak)}")
    }

    // 8. After a tempo-matched mix the new song eases back to its tempo.
    run {
        val m = Mixer(OUT)
        m.post { it.loadMaster(tone(220.0, 30.0), 0.0) }
        m.post { it.loadNext(tone(330.0, 30.0)) }
        m.post {
            it.setTransition(
                TransitionScript(
                    exit = 1.0, entry = 0.0, length = 1.0, rate = 0.97, semitones = 0.0,
                    rampBack = 2.0, lanes = emptyMap(),
                ),
            )
        }
        m.post { it.setPlaying(true) }
        run(m, (2.2 * OUT / Stretcher.HOP).toInt())
        val during = m.decks[m.master].tempo
        run(m, (2.5 * OUT / Stretcher.HOP).toInt())
        val after = m.decks[m.master].tempo
        check("ramp back", during < 0.999 && abs(after - 1) < 1e-9, "tempo ${"%.3f".format(during)} -> ${"%.3f".format(after)}")
    }

    // 8b. The DJ filter: half-way up it thins out the lows, off it's clean.
    run {
        fun through(freq: Double, knob: Float): Double {
            val f = DjFilter(OUT)
            val y = FloatArray(OUT) { i -> f.process((sin(2 * PI * freq * i / OUT) * 0.5).toFloat(), knob) }
            return 20 * log10(rms(y, OUT / 4) / (0.5 / sqrt(2.0)))
        }
        val thinned = through(100.0, 0.5f)
        val highs = through(5000.0, 0.5f)
        val off = through(100.0, 0f)
        val muffled = through(5000.0, -0.5f)
        check("filter high-pass", thinned < -12 && abs(highs) < 1.5, "100 Hz ${"%.1f".format(thinned)} dB, 5 kHz ${"%.1f".format(highs)} dB")
        check("filter low-pass", muffled < -12, "5 kHz ${"%.1f".format(muffled)} dB")
        check("filter off", abs(off) < 0.01, "${"%.3f".format(off)} dB")
    }

    // 9. Speed: how much of real time one deck pair takes on this machine.
    run {
        val m = Mixer(OUT)
        m.post { it.loadMaster(tone(220.0, 60.0), 0.0) }
        m.post { it.loadNext(tone(330.0, 60.0)) }
        m.post {
            it.setTransition(
                TransitionScript(
                    exit = 0.6, entry = 0.0, length = 50.0, rate = 0.97, semitones = 1.0,
                    rampBack = 0.0, lanes = mapOf("inGain" to Lane.constant(1f)),
                ),
            )
        }
        m.post { it.setPlaying(true) }
        val blocks = (20.0 * OUT / Stretcher.HOP).toInt()
        run(m, 50) // warm up
        val t0 = System.nanoTime()
        run(m, blocks)
        val seconds = (System.nanoTime() - t0) / 1e9
        println("INFO  speed: 20 s of a two-deck mix in ${"%.2f".format(seconds)} s (${"%.0f".format(20 / seconds)}x real time)")
    }

    if (failures > 0) {
        println("$failures check(s) failed")
        kotlin.system.exitProcess(1)
    }
    println("Engine checks OK")
}
