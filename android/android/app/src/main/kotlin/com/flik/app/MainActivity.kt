package com.flik.app

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// MainActivity implementing Scoped Storage MediaStore bridges and Wi-Fi Multicast lock.
class MainActivity : FlutterActivity() {
    private val CHANNEL = "flik/media_store"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Saves documents and general files to Scoped Storage Downloads/Flik
                "saveToDownloads" -> {
                    val fileName = call.argument<String>("fileName")
                    val fileBytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                    if (fileName == null || fileBytes == null) {
                        result.error("INVALID_ARGS", "Missing filename or byte data", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val savedUri = saveFileToDownloads(fileName, fileBytes, mimeType)
                        result.success(savedUri)
                    } catch (e: Exception) {
                        result.error("IO_ERROR", e.localizedMessage, null)
                    }
                }
                // Acquires Wi-Fi multicast lock for reliable mDNS discovery
                "acquireMulticastLock" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        if (multicastLock == null) {
                            multicastLock = wifiManager.createMulticastLock("FlikMdnsMulticastLock").apply {
                                setReferenceCounted(true)
                                acquire()
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.localizedMessage, null)
                    }
                }
                // Releases Wi-Fi multicast lock
                "releaseMulticastLock" -> {
                    try {
                        multicastLock?.let {
                            if (it.isHeld) it.release()
                        }
                        multicastLock = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveFileToDownloads(fileName: String, bytes: ByteArray, mimeType: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Flik")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw IllegalStateException("Could not create MediaStore Downloads entry")

            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            }

            contentValues.clear()
            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
            uri.toString()
        } else {
            val flikDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Flik")
            if (!flikDir.exists()) flikDir.mkdirs()
            val dest = File(flikDir, fileName)
            FileOutputStream(dest).use { it.write(bytes) }
            dest.absolutePath
        }
    }

    override fun onDestroy() {
        multicastLock?.let {
            if (it.isHeld) it.release()
        }
        multicastLock = null
        super.onDestroy()
    }
}
