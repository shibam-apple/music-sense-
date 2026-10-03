package com.musicsense.music_sense

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/** Hosts Flutter; extends AudioServiceActivity for background playback. */
class MainActivity : AudioServiceActivity() {
    private var media: MediaBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        media = MediaBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger, this)
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
        media?.dispose()
        media = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
