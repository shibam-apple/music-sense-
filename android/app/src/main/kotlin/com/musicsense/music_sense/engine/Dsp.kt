package com.musicsense.music_sense.engine

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt
import kotlin.math.tan

/** A parameter that glides to its target (one-pole, ~[ms] to settle). */
class Smoothed(initial: Float, sampleRate: Int, ms: Float = 6f) {
    var target = initial
    var value = initial
        private set
    private val k = 1f - exp(-1.0 / (sampleRate * ms / 1000.0)).toFloat()

    fun next(): Float {
        value += (target - value) * k
        return value
    }

    fun snap(v: Float) {
        target = v
        value = v
    }
}

fun dbToGain(db: Float): Float = if (db <= -60f) 0f else 10.0.pow(db / 20.0).toFloat()

/** A second-order section (transposed direct form II). */
class Biquad {
    private var b0 = 1.0; private var b1 = 0.0; private var b2 = 0.0
    private var a1 = 0.0; private var a2 = 0.0
    private var z1 = 0.0; private var z2 = 0.0

    fun lowPass(freq: Double, rate: Int, q: Double = 1 / sqrt(2.0)) = rbj(freq, rate, q, low = true)
    fun highPass(freq: Double, rate: Int, q: Double = 1 / sqrt(2.0)) = rbj(freq, rate, q, low = false)

    private fun rbj(freq: Double, rate: Int, q: Double, low: Boolean): Biquad {
        val w = 2 * PI * freq / rate
        val cos = kotlin.math.cos(w)
        val alpha = kotlin.math.sin(w) / (2 * q)
        val a0 = 1 + alpha
        if (low) {
            b0 = (1 - cos) / 2 / a0; b1 = (1 - cos) / a0; b2 = b0
        } else {
            b0 = (1 + cos) / 2 / a0; b1 = -(1 + cos) / a0; b2 = b0
        }
        a1 = -2 * cos / a0
        a2 = (1 - alpha) / a0
        return this
    }

    fun process(x: Double): Double {
        val y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    fun reset() {
        z1 = 0.0; z2 = 0.0
    }
}

/** A 4th-order Linkwitz-Riley filter: two Butterworth sections. */
private class Lr4(freq: Double, rate: Int, low: Boolean) {
    private val a = if (low) Biquad().lowPass(freq, rate) else Biquad().highPass(freq, rate)
    private val b = if (low) Biquad().lowPass(freq, rate) else Biquad().highPass(freq, rate)

    fun process(x: Double) = b.process(a.process(x))

    fun reset() {
        a.reset(); b.reset()
    }
}

/**
 * A DJ mixer's 3-band EQ on one channel, built like an isolator: a
 * Linkwitz-Riley crossover splits off the lows at [lowHz], then the rest
 * into mids and highs at [highHz]; the lows go through the same second
 * crossover's phase so the three bands add back up flat. A kill (gain 0)
 * removes its band by 24 dB per octave beyond the crossover.
 */
class ThreeBand(rate: Int, lowHz: Double = 250.0, highHz: Double = 3000.0) {
    private val low = Lr4(lowHz, rate, low = true)
    private val rest = Lr4(lowHz, rate, low = false)
    private val mid = Lr4(highHz, rate, low = true)
    private val high = Lr4(highHz, rate, low = false)
    // The lows' share of the second crossover's phase.
    private val alignLow = Lr4(highHz, rate, low = true)
    private val alignHigh = Lr4(highHz, rate, low = false)

    fun process(x: Float, lowGain: Float, midGain: Float, highGain: Float): Float {
        val v = x.toDouble()
        val l = low.process(v)
        val r = rest.process(v)
        val lo = alignLow.process(l) + alignHigh.process(l)
        val m = mid.process(r)
        val h = high.process(r)
        return (lo * lowGain + m * midGain + h * highGain).toFloat()
    }

    fun reset() {
        listOf(low, rest, mid, high, alignLow, alignHigh).forEach { it.reset() }
    }
}

/**
 * The DJ filter knob on one channel: 0 is off; towards +1 a high-pass
 * sweeps up (the song thins out), towards -1 a low-pass sweeps down
 * (it goes muffled). A state-variable filter, stable under fast sweeps.
 */
class DjFilter(private val rate: Int) {
    private var ic1 = 0.0
    private var ic2 = 0.0

    fun process(x: Float, knob: Float): Float {
        if (abs(knob) < 0.01f) {
            // Keep the state following the signal so engaging it is smooth.
            ic1 = 0.0; ic2 = x.toDouble()
            return x
        }
        val cutoff = if (knob > 0) 20.0 * 1000.0.pow(knob.toDouble())
        else 20000.0 * 0.001.pow((-knob).toDouble())
        val g = tan(PI * min(cutoff, rate * 0.45) / rate)
        val k = 1.0 / 0.75 // gentle resonance (Q 0.75)
        val a1 = 1 / (1 + g * (g + k))
        val a2 = g * a1
        val a3 = g * a2
        val v3 = x - ic2
        val v1 = a1 * ic1 + a2 * v3
        val v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        val lowOut = v2
        val highOut = x - k * v1 - v2
        // Fade the effect in over the first part of the knob's travel.
        val wet = min(1f, abs(knob) / 0.1f)
        val y = if (knob > 0) highOut else lowOut
        return (x * (1 - wet) + y * wet).toFloat()
    }
}

/** Keeps the summed decks from clipping: fast attack, slow release. */
class Limiter(rate: Int, private val ceiling: Float = 0.95f) {
    private var envelope = 0f
    private val release = exp(-1.0 / (rate * 0.15)).toFloat()

    fun gainFor(peak: Float): Float {
        envelope = max(peak, envelope * release)
        return if (envelope <= ceiling) 1f else ceiling / envelope
    }
}
