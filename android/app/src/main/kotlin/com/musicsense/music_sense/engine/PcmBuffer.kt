package com.musicsense.music_sense.engine

/**
 * A song's decoded audio: 16-bit stereo, filled by a decoder thread while
 * the audio thread already plays from it. Stored in fixed-size chunks so
 * the reader never sees an array being reallocated; [frames] is published
 * after each chunk's samples are written.
 */
class PcmBuffer(val sampleRate: Int, maxSeconds: Int = 20 * 60) {
    companion object {
        const val CHUNK_FRAMES = 1 shl 16
        private const val SCALE = 1f / 32768f
    }

    private val chunks = arrayOfNulls<ShortArray>(
        (sampleRate.toLong() * maxSeconds / CHUNK_FRAMES + 1).toInt(),
    )
    private val capacity = chunks.size.toLong() * CHUNK_FRAMES

    /** Frames decoded so far (readable). */
    @Volatile var frames = 0L
        private set

    /** Set once the decoder has reached the end of the song. */
    @Volatile var complete = false
        private set

    /** Set when decoding failed; the song plays as far as it got. */
    @Volatile var failed: String? = null

    val seconds: Double get() = frames.toDouble() / sampleRate

    /** Appends interleaved stereo frames (decoder thread only). */
    fun append(stereo: ShortArray, count: Int) {
        var written = 0
        var at = frames
        while (written < count && at < capacity) {
            val chunk = (at / CHUNK_FRAMES).toInt()
            val offset = (at % CHUNK_FRAMES).toInt()
            val data = chunks[chunk] ?: ShortArray(CHUNK_FRAMES * 2).also { chunks[chunk] = it }
            val n = minOf(count - written, CHUNK_FRAMES - offset)
            System.arraycopy(stereo, written * 2, data, offset * 2, n * 2)
            written += n
            at += n
        }
        frames = at
    }

    fun finish() {
        complete = true
    }

    /** One channel (0 left, 1 right) at a whole frame; 0 outside the song. */
    fun at(frame: Long, channel: Int): Float {
        if (frame < 0 || frame >= frames) return 0f
        val data = chunks[(frame ushr 16).toInt()] ?: return 0f
        return data[((frame and 0xFFFF).toInt() shl 1) + channel] * SCALE
    }

    /** Linear interpolation between frames. */
    fun sample(position: Double, channel: Int): Float {
        val i = Math.floor(position).toLong()
        val f = (position - i).toFloat()
        val a = at(i, channel)
        return if (f == 0f) a else a + (at(i + 1, channel) - a) * f
    }

    /** Mono (both channels averaged), interpolated. */
    fun mono(position: Double): Float = (sample(position, 0) + sample(position, 1)) * 0.5f
}
