package com.musicsense.music_sense

import java.io.File

/**
 * Runs the app's YouTube stream code on a plain JVM: finds a song's audio
 * with NewPipe Extractor and downloads it, as the phone would.
 */
fun main(args: Array<String>) {
    val id = args.firstOrNull() ?: "4D7u5KF7SP8"
    val cache = File(System.getProperty("java.io.tmpdir"), "ms-youtube-check").apply { mkdirs() }
    val streams = YouTubeStreams(cache)
    println("diagnose:\n" + streams.diagnose(id, null))
    val started = System.currentTimeMillis()
    val result = streams.fetch(id, null)
    val file = File(result["path"] as String)
    val head = file.inputStream().use { it.readNBytes(12) }
    val brand = String(head, 4, 4, Charsets.US_ASCII)
    println("fetched ${file.length()} bytes in ${System.currentTimeMillis() - started} ms: $result (box '$brand')")
    check(file.length() > 500_000) { "file too small" }
    check(brand == "ftyp" || head[0] == 0x1A.toByte()) { "not an audio container" }
    println("YouTube stream check OK")
}
