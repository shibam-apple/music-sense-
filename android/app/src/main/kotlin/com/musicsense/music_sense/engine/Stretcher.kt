package com.musicsense.music_sense.engine

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt

/**
 * Tempo and key changes for one deck: WSOLA (waveform-similarity
 * overlap-add) on resampled grains.
 *
 * Each block of [HOP] output frames adds one Hann-windowed grain of
 * [GRAIN] frames. The grain is read from the song at a speed of `step`
 * source frames per output frame (that sets the pitch, and absorbs the
 * song's and the device's sample rates); where it starts in the song is
 * given by the caller for every block (that sets the tempo, or locks the
 * deck to another one). Around that start the grain is shifted by up to
 * [TOLERANCE] frames to where it best continues the previous grain, which
 * is what keeps the sound smooth. At normal speed the continuation is
 * exact and the output equals the input.
 */
class Stretcher {
    companion object {
        const val HOP = 512
        const val GRAIN = HOP * 2
        const val TOLERANCE = 96
        private const val DECIMATE = 4

        private val window = FloatArray(GRAIN) { i ->
            (0.5 - 0.5 * cos(2 * PI * i / GRAIN)).toFloat()
        }
    }

    // Tail of the previous grain (its second half), stereo interleaved.
    private val tail = FloatArray(HOP * 2)
    private var prevStart = Double.NaN
    private var prevStep = 1.0
    private val reference = FloatArray(HOP / DECIMATE)
    private val taps = IntArray(HOP / DECIMATE)
    private var scratch = FloatArray(4 * TOLERANCE + GRAIN)

    /** Where the last grain started in the song, in source frames. */
    val lastStart: Double get() = prevStart

    fun reset() {
        tail.fill(0f)
        prevStart = Double.NaN
    }

    /**
     * Writes [HOP] stereo frames into [out] (interleaved) for a grain that
     * should start at [desired] source frames, read at [step] source
     * frames per output frame.
     */
    fun render(source: PcmBuffer, desired: Double, step: Double, out: FloatArray) {
        val start = if (prevStart.isNaN()) desired else bestStart(source, desired, step)
        for (i in 0 until HOP) {
            val p = start + i * step
            val w = window[i]
            out[i * 2] = tail[i * 2] + source.sample(p, 0) * w
            out[i * 2 + 1] = tail[i * 2 + 1] + source.sample(p, 1) * w
        }
        for (i in 0 until HOP) {
            val p = start + (i + HOP) * step
            val w = window[i + HOP]
            tail[i * 2] = source.sample(p, 0) * w
            tail[i * 2 + 1] = source.sample(p, 1) * w
        }
        prevStart = start
        prevStep = step
    }

    /**
     * The start near [desired] whose first half best matches how the
     * previous grain would have continued.
     */
    private fun bestStart(source: PcmBuffer, desired: Double, step: Double): Double {
        val continuation = prevStart + HOP * prevStep
        if (abs(desired - continuation) < 0.5) return continuation
        // A big jump (a seek, a new song): no continuity to keep.
        if (abs(desired - continuation) > TOLERANCE * 8) return desired

        for (j in reference.indices) {
            reference[j] = source.mono(continuation + j * DECIMATE * step)
        }
        // The song around the asked-for start, read once; candidates index
        // into it (nearest frame is plenty for finding the best match).
        val base = desired.roundToInt()
        val frac = desired - base
        val reach = (reference.size * DECIMATE * step).toInt() + 2
        val span = 2 * TOLERANCE + reach
        if (scratch.size < span) scratch = FloatArray(span)
        for (k in 0 until span) scratch[k] = source.mono(base + frac + (k - TOLERANCE))
        for (j in reference.indices) taps[j] = (j * DECIMATE * step).roundToInt()

        var best = desired
        var bestScore = Double.NEGATIVE_INFINITY
        for (offset in -TOLERANCE..TOLERANCE) {
            val origin = offset + TOLERANCE
            var dot = 0.0
            var energy = 1e-9
            for (j in reference.indices) {
                val s = scratch[origin + taps[j]]
                dot += s * reference[j]
                energy += s * s
            }
            // Normalised so loud passages don't win just for being loud;
            // a slight pull towards the asked-for position keeps it locked.
            val score = dot / kotlin.math.sqrt(energy) - abs(offset) * 1e-4
            if (score > bestScore) {
                bestScore = score
                best = base + offset + frac
            }
        }
        return best
    }
}
