package com.musicsense.music_sense

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import java.util.WeakHashMap

/** Hosts Flutter; extends AudioServiceActivity for background playback. */
class MainActivity : AudioServiceActivity() {
    companion object {
        /**
         * One bridge per engine. audio_service reuses its engine when the
         * activity is recreated, so the bridge (its channel and threads)
         * must outlive any one activity.
         */
        private val bridges = WeakHashMap<FlutterEngine, MediaBridge>()
    }

    private var media: MediaBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        media = bridges.getOrPut(flutterEngine) {
            MediaBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        }.also { it.activity = this }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (media?.onPermissionResult(requestCode) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Detach only; the engine (and its bridge) may live on.
        media?.let { if (it.activity === this) it.activity = null }
        media = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
