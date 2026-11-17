package com.flik.app

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// MainActivity implementing Scoped Storage MediaStore bridges, Wi-Fi Multicast lock,
// and system-wide Share Sheet intake for URLs (YouTube, Instagram reels, browsers) and files.
class MainActivity : FlutterActivity() {
    private val CHANNEL = "flik/media_store"
    private val SHARE_CHANNEL = "flik/share_intake"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var shareChannel: MethodChannel? = null
    private var pendingSharedData: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingSharedData = extractShareData(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val data = extractShareData(intent)
        if (data != null) {
            if (shareChannel != null) {
                shareChannel?.invokeMethod("onShareReceived", data)
            } else {
                pendingSharedData = data
            }
        }
    }

    private fun extractShareData(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return null

        var text: String? = null
        if (intent.hasExtra(Intent.EXTRA_TEXT)) {
            val extraText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT) ?: intent.getStringExtra(Intent.EXTRA_TEXT)
            text = extraText?.toString()
        }

        if (text == null && intent.clipData != null) {
            val clip = intent.clipData
            if (clip != null && clip.itemCount > 0) {
                for (i in 0 until clip.itemCount) {
                    val item = clip.getItemAt(i)
                    val itemText = item.text?.toString() ?: item.uri?.toString()
                    if (!itemText.isNullOrBlank()) {
                        text = itemText
                        break
                    }
                }
            }
        }

        if (text == null && intent.data != null) {
            text = intent.dataString
        }

        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)

        val filePaths = mutableListOf<String>()
        if (action == Intent.ACTION_SEND) {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            if (uri != null) {
                resolveUriToPath(uri)?.let { filePaths.add(it) }
            }
        } else if (action == Intent.ACTION_SEND_MULTIPLE) {
            val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            uris?.forEach { uri ->
                resolveUriToPath(uri)?.let { filePaths.add(it) }
            }
        }

        if (text.isNullOrBlank() && filePaths.isEmpty()) return null

        return mapOf(
            "text" to text,
            "subject" to subject,
            "files" to filePaths
        )
    }

    private fun resolveUriToPath(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        return try {
            val resolver = applicationContext.contentResolver
            var fileName = "shared_${System.currentTimeMillis()}"
            resolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                if (nameIndex != -1 && cursor.moveToFirst()) {
                    fileName = cursor.getString(nameIndex) ?: fileName
                }
            }
            val cacheFile = File(applicationContext.cacheDir, fileName)
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
            cacheFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Share intake channel for receiving direct shares from Instagram, YouTube, browsers, etc.
        val sChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareChannel = sChannel
        sChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    val data = pendingSharedData
                    pendingSharedData = null
                    result.success(data)
                }
                else -> result.notImplemented()
            }
        }

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
