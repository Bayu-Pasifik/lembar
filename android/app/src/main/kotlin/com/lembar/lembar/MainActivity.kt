package com.lembar.lembar

import android.os.Bundle
import android.util.Log
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        warmUpScanner()
    }

    /**
     * The document scanner plugin silently falls back to a manual-crop scanner when
     * Google's ML Kit scanner is not ready on the very first request. Asking for the
     * scan intent once at startup lets Play services prepare it, and logs the reason
     * if it is not available.
     */
    private fun warmUpScanner() {
        try {
            GmsDocumentScanning.getClient(GmsDocumentScannerOptions.Builder().setPageLimit(1).build())
                .getStartScanIntent(this)
                .addOnSuccessListener { Log.i(TAG, "ML Kit scanner warm-up ok") }
                .addOnFailureListener { Log.w(TAG, "ML Kit scanner warm-up failed", it) }
        } catch (e: Exception) {
            Log.w(TAG, "ML Kit scanner warm-up threw", e)
        }
    }

    private companion object {
        const val TAG = "LembarScanner"
    }
}
