import 'dart:typed_data';
import 'package:flutter/services.dart';

// Invokes native Android Kotlin channel for Scoped Storage (Downloads/Flik) and Wi-Fi Multicast Lock.
class MediaStoreService {
  static const MethodChannel _channel = MethodChannel('flik/media_store');

  // Saves document bytes directly into MediaStore Downloads/Flik on API 29+ or direct path on API <= 28
  static Future<String?> saveToDownloads({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'bytes': bytes,
        'mimeType': mimeType,
      });
      return result;
    } catch (e) {
      // In non-Android or testing environments, fail gracefully
      return null;
    }
  }

  // Acquires Wi-Fi multicast lock for reliable mDNS packet discovery
  static Future<bool> acquireMulticastLock() async {
    try {
      final res = await _channel.invokeMethod<bool>('acquireMulticastLock');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // Releases Wi-Fi multicast lock
  static Future<bool> releaseMulticastLock() async {
    try {
      final res = await _channel.invokeMethod<bool>('releaseMulticastLock');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
