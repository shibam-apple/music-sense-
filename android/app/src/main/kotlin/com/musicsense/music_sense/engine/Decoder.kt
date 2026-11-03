package com.musicsense.music_sense.engine

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Decodes a song (a file, or a content:// MediaStore song) into a
 * [PcmBuffer] on its own thread. [open] returns as soon as the first
 * audio is decoded, so playback starts while the rest is still decoding
 * (far faster than real time).
 */
object Decoder {
    class Opened(val buffer: PcmBuffer, val durationSeconds: Double, val cancel: () -> Unit)

    fun open(context: Context, uri: String, headers: Map<String, String> = emptyMap()): Opened {
        val extractor = MediaExtractor()
        val parsed = Uri.parse(uri)
        when (parsed.scheme) {
            null, "file" -> extractor.setDataSource(parsed.path ?: uri)
            "http", "https" -> extractor.setDataSource(uri, headers)
            else -> extractor.setDataSource(context, parsed, null)
        }
        var track = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                track = i; format = f; break
            }
        }
        if (format == null) {
            extractor.release()
            throw IllegalArgumentException("No audio in this file")
        }
        extractor.selectTrack(track)
        val duration = if (format.containsKey(MediaFormat.KEY_DURATION)) {
            format.getLong(MediaFormat.KEY_DURATION) / 1e6
        } else 0.0

        val ready = CountDownLatch(1)
        var buffer: PcmBuffer? = null
        var failure: Throwable? = null
        val cancelled = AtomicBoolean(false)

        thread(name = "beat-sense-decode", isDaemon = true) {
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            try {
                codec.configure(format, null, null, 0)
                codec.start()
                var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                var float = false
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var stereo = ShortArray(8192 * 2)
                var idle = 0
                while (!cancelled.get()) {
                    if (!inputDone) {
                        val i = codec.dequeueInputBuffer(5_000)
                        if (i >= 0) {
                            val input = codec.getInputBuffer(i)!!
                            val n = extractor.readSampleData(input, 0)
                            if (n < 0) {
                                codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(i, 0, n, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                    val o = codec.dequeueOutputBuffer(info, 5_000)
                    if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val out = codec.outputFormat
                        rate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        float = out.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            out.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                        continue
                    }
                    if (o < 0) {
                        // A decoder that stops answering would otherwise
                        // hang here forever: give up after ~10 s of nothing.
                        if (inputDone && ++idle > 2000) break
                        continue
                    }
                    idle = 0
                    val out = codec.getOutputBuffer(o)!!
                    out.position(info.offset)
                    out.limit(info.offset + info.size)
                    out.order(ByteOrder.nativeOrder())
                    val b = buffer ?: PcmBuffer(rate).also {
                        buffer = it
                        ready.countDown()
                    }
                    val frames = if (float) info.size / 4 / channels else info.size / 2 / channels
                    if (stereo.size < frames * 2) stereo = ShortArray(frames * 2)
                    if (float) {
                        val f = out.asFloatBuffer()
                        for (k in 0 until frames) {
                            val l = f.get(k * channels)
                            val r = if (channels > 1) f.get(k * channels + 1) else l
                            stereo[k * 2] = (l.coerceIn(-1f, 1f) * 32767).toInt().toShort()
                            stereo[k * 2 + 1] = (r.coerceIn(-1f, 1f) * 32767).toInt().toShort()
                        }
                    } else {
                        val s = out.asShortBuffer()
                        for (k in 0 until frames) {
                            val l = s.get(k * channels)
                            stereo[k * 2] = l
                            stereo[k * 2 + 1] = if (channels > 1) s.get(k * channels + 1) else l
                        }
                    }
                    b.append(stereo, frames)
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            } catch (t: Throwable) {
                failure = t
                buffer?.failed = t.message ?: t.javaClass.simpleName
            } finally {
                try { codec.stop() } catch (_: Throwable) {}
                codec.release()
                extractor.release()
                buffer?.finish()
                ready.countDown()
            }
        }

        if (!ready.await(20, TimeUnit.SECONDS)) {
            cancelled.set(true)
            throw IllegalStateException("The song took too long to start decoding")
        }
        val b = buffer ?: throw IllegalStateException(
            "Couldn't decode this song: ${failure?.message ?: "no audio"}",
        )
        return Opened(b, duration) { cancelled.set(true) }
    }
}
