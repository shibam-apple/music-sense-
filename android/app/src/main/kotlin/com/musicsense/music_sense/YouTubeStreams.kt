package com.musicsense.music_sense

import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.AgeRestrictedContentException
import org.schabi.newpipe.extractor.exceptions.GeographicRestrictionException
import org.schabi.newpipe.extractor.exceptions.PaidContentException
import org.schabi.newpipe.extractor.exceptions.PrivateContentException
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.exceptions.SignInConfirmNotBotException
import org.schabi.newpipe.extractor.exceptions.YoutubeMusicPremiumContentException
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Plays YouTube Music songs the way NewPipe does: NewPipe Extractor asks
 * YouTube's own app clients for the audio streams (and keeps up with
 * YouTube's changes), then the audio is downloaded to a cache on the
 * phone, so playback, seeking and Beat Sense work like a local file and
 * songs play again offline.
 *
 * Plain JVM code (no Android APIs) so CI can run it as-is.
 */
class YouTubeStreams(cacheRoot: File) {

    /** A readable failure, shown in the app. */
    class Failure(message: String, val kind: String) : Exception(message)

    private val cacheDir = File(cacheRoot, "youtube").apply { mkdirs() }
    private val chunks = Executors.newFixedThreadPool(4)
    private val http = Http()

    init {
        NewPipe.init(http, Localization("en", "US"), ContentCountry("US"))
    }

    private val locks = java.util.concurrent.ConcurrentHashMap<String, Any>()

    /**
     * The cached audio file for [videoId], downloading it first if needed.
     * Different songs download in parallel; the same song only once.
     */
    fun fetch(videoId: String, cookies: String?): Map<String, Any> =
        synchronized(locks.getOrPut(videoId) { Any() }) { fetchLocked(videoId, cookies) }

    private fun fetchLocked(videoId: String, cookies: String?): Map<String, Any> {
        val done = File(cacheDir, "$videoId.audio")
        if (done.length() > 0) {
            done.setLastModified(System.currentTimeMillis())
            return mapOf("path" to done.absolutePath, "cached" to true)
        }
        val stream = pick(info(videoId, cookies))
        val agent = userAgentFor(stream.content)
        val part = File(cacheDir, "$videoId.part")
        val length = stream.itagItem?.contentLength?.takeIf { it > 0 }
            ?: Regex("[?&]clen=(\\d+)").find(stream.content)?.groupValues?.get(1)?.toLong()
            ?: contentLength(stream.content, agent)
        download(stream.content, agent, length, part)
        if (!part.renameTo(done)) throw IOException("Couldn't save the song")
        trim()
        return mapOf(
            "path" to done.absolutePath,
            "cached" to false,
            "format" to (stream.format?.name ?: ""),
            "bitrate" to stream.averageBitrate,
        )
    }

    /** What each step does for [videoId], for the in-app YouTube check. */
    fun diagnose(videoId: String, cookies: String?): String {
        val out = StringBuilder()
        for ((label, c) in listOf("anonymous" to null, "signed in" to cookies)) {
            if (label == "signed in" && c == null) continue
            try {
                http.cookies.set(c)
                val info = StreamInfo.getInfo(ServiceList.YouTube, watchUrl(videoId))
                val audio = info.audioStreams
                out.append("$label: ${audio.size} audio streams")
                val s = pick(info)
                out.append(", ${s.format?.name} ${s.averageBitrate} kbps")
                val agent = userAgentFor(s.content)
                val code = probe(s.content, agent)
                out.append(", download HTTP $code\n")
            } catch (e: Exception) {
                out.append("$label: ${e.javaClass.simpleName}: ${e.message?.take(160)}\n")
            } finally {
                http.cookies.set(null)
            }
        }
        return out.toString().trim()
    }

    private fun watchUrl(id: String) = "https://www.youtube.com/watch?v=$id"

    /**
     * Asks anonymously first; if YouTube wants proof this isn't a bot,
     * asks again with the listener's signed-in session.
     */
    private fun info(videoId: String, cookies: String?): StreamInfo {
        try {
            http.cookies.set(null)
            return StreamInfo.getInfo(ServiceList.YouTube, watchUrl(videoId))
        } catch (e: Exception) {
            val botCheck = e is SignInConfirmNotBotException || e is ReCaptchaException
            if (botCheck && cookies != null) {
                try {
                    http.cookies.set(cookies)
                    return StreamInfo.getInfo(ServiceList.YouTube, watchUrl(videoId))
                } catch (signedIn: Exception) {
                    throw explain(signedIn, true)
                } finally {
                    http.cookies.set(null)
                }
            }
            throw explain(e, cookies != null)
        }
    }

    private fun explain(e: Exception, signedIn: Boolean): Failure = when (e) {
        is SignInConfirmNotBotException, is ReCaptchaException -> Failure(
            if (signedIn) "YouTube is asking this phone to confirm it isn't a bot. Try again in a minute."
            else "YouTube wants you signed in to play this. Sign in on the Account page.",
            "bot",
        )
        is YoutubeMusicPremiumContentException -> Failure("This song needs YouTube Music Premium.", "premium")
        is AgeRestrictedContentException -> Failure("This song is age-restricted on YouTube.", "age")
        is GeographicRestrictionException -> Failure("This song isn't available in your country.", "region")
        is PrivateContentException -> Failure("This song is private on YouTube.", "private")
        is PaidContentException -> Failure("This song is for paying members only.", "paid")
        is IOException -> Failure("Couldn't reach YouTube. Check your connection.", "network")
        else -> Failure("YouTube wouldn't play this song (${e.javaClass.simpleName}).", "other")
    }

    /** Plain HTTP audio, AAC (m4a) first for the widest decoder support. */
    private fun pick(info: StreamInfo): AudioStream {
        val direct = info.audioStreams.filter {
            it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && it.content.startsWith("http")
        }
        if (direct.isEmpty()) throw Failure("YouTube offered no playable audio for this song.", "nostream")
        return direct.filter { it.format == MediaFormat.M4A }.maxByOrNull { it.averageBitrate }
            ?: direct.maxBy { it.averageBitrate }
    }

    /** Stream URLs are tied to the client that asked for them. */
    private fun userAgentFor(url: String): String = when {
        YoutubeParsingHelper.isAndroidStreamingUrl(url) -> YoutubeParsingHelper.getAndroidUserAgent(null)
        YoutubeParsingHelper.isIosStreamingUrl(url) -> YoutubeParsingHelper.getIosUserAgent(null)
        YoutubeParsingHelper.isVisionOsStreamingUrl(url) -> YoutubeParsingHelper.getVisionOsUserAgent(null)
        else -> Http.BROWSER
    }

    private fun open(url: String, agent: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            setRequestProperty("User-Agent", agent)
            setRequestProperty("Accept-Encoding", "identity")
        }

    private fun contentLength(url: String, agent: String): Long {
        val c = open("$url&range=0-1", agent)
        try {
            c.inputStream.close()
            val range = c.getHeaderField("Content-Range")
            return range?.substringAfter('/')?.toLongOrNull()
                ?: throw Failure("YouTube didn't say how long this song is.", "nostream")
        } finally {
            c.disconnect()
        }
    }

    private fun probe(url: String, agent: String): Int {
        val c = open("$url&range=0-1023", agent)
        return try { c.responseCode } finally { c.disconnect() }
    }

    /**
     * Downloads in 1 MiB pieces, four at a time, with YouTube's `range`
     * parameter (what its own players use; big single requests get
     * throttled), each piece retried once.
     */
    private fun download(url: String, agent: String, length: Long, into: File) {
        val piece = 1L shl 20
        RandomAccessFile(into, "rw").use { it.setLength(length) }
        val jobs = (0 until length step piece).map { start ->
            val end = minOf(start + piece, length) - 1
            chunks.submit(Callable {
                var attempt = 0
                while (true) {
                    try {
                        fetchPiece(url, agent, start, end, into)
                        return@Callable
                    } catch (e: IOException) {
                        if (++attempt >= 2) throw e
                    }
                }
            })
        }
        try {
            for (job in jobs) job.get(90, TimeUnit.SECONDS)
        } catch (e: Exception) {
            jobs.forEach { it.cancel(true) }
            into.delete()
            val cause = e.cause ?: e
            throw if (cause is Failure) cause
            else Failure("The song stopped downloading from YouTube. Check your connection.", "network")
        }
    }

    private fun fetchPiece(url: String, agent: String, start: Long, end: Long, into: File) {
        val c = open("$url&range=$start-$end", agent)
        try {
            val code = c.responseCode
            if (code == 403) throw Failure("YouTube refused the audio download (403).", "forbidden")
            if (code !in 200..299) throw IOException("HTTP $code")
            val buffer = ByteArray(64 * 1024)
            RandomAccessFile(into, "rw").use { file ->
                file.seek(start)
                var written = 0L
                c.inputStream.use { input ->
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        file.write(buffer, 0, n)
                        written += n
                    }
                }
                if (written < end - start + 1) throw IOException("Short read")
            }
        } finally {
            c.disconnect()
        }
    }

    /** Keeps the cache under 500 MB, dropping the least recently played. */
    @Synchronized
    private fun trim() {
        val files = cacheDir.listFiles { f -> f.name.endsWith(".audio") }?.sortedBy { it.lastModified() }
            ?: return
        var total = files.sumOf { it.length() }
        for (f in files) {
            if (total <= 500L shl 20) break
            total -= f.length()
            f.delete()
        }
    }

    /** NewPipe's HTTP: plain HttpURLConnection, with the session when asked. */
    private class Http : Downloader() {
        companion object {
            const val BROWSER =
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
        }

        /** The session for requests on this thread (null: anonymous). */
        val cookies = ThreadLocal<String?>()

        override fun execute(request: Request): Response {
            val c = URL(request.url()).openConnection() as HttpURLConnection
            try {
                c.connectTimeout = 15_000
                c.readTimeout = 30_000
                c.requestMethod = request.httpMethod()
                c.instanceFollowRedirects = true
                c.setRequestProperty("User-Agent", BROWSER)
                for ((name, values) in request.headers()) {
                    c.setRequestProperty(name, values.joinToString(", "))
                }
                val host = c.url.host
                val session = cookies.get()
                if (session != null && (host.endsWith("youtube.com") || host.endsWith("google.com"))) {
                    c.setRequestProperty("Cookie", session)
                }
                request.dataToSend()?.let { body ->
                    c.doOutput = true
                    c.outputStream.use { it.write(body) }
                }
                val code = c.responseCode
                if (code == 429) throw ReCaptchaException("Rate limited", request.url())
                val body = (if (code >= 400) c.errorStream else c.inputStream)
                    ?.use { it.readBytes().toString(Charsets.UTF_8) } ?: ""
                return Response(
                    code,
                    c.responseMessage,
                    c.headerFields.filterKeys { it != null },
                    body,
                    c.url.toString(),
                )
            } finally {
                c.disconnect()
            }
        }
    }
}
