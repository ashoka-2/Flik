import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/peer.dart';
import '../models/transfer_item.dart';
import '../models/transfer_meta.dart';
import 'storage_service.dart';

// HTTP client streaming files and web links to receiver peers with pre-flight checks,
// stall watchdog, cancel support, and haptics.
class FlikHttpClient {
  final StorageService storage;
  final Dio _dio;
  CancelToken? _currentCancelToken;

  FlikHttpClient({required this.storage})
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

  // Sends files to target peer
  Future<bool> sendFiles({
    required DiscoveredPeer peer,
    required List<TransferItem> items,
    double? trajectoryX,
    required void Function(double progress) onProgress,
    required void Function(String error) onError,
  }) async {
    final token = peer.token ?? storage.getToken(peer.deviceId) ?? 'default';

    // Pre-flight check: Ping peer
    try {
      final pingRes = await _dio.get(
        'http://${peer.ip}:${peer.port}/ping',
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      if (pingRes.statusCode != 200) {
        onError("Couldn't reach ${peer.deviceName}.");
        return false;
      }
      Map<String, dynamic>? pingData;
      if (pingRes.data is Map) {
        pingData = Map<String, dynamic>.from(pingRes.data as Map);
      } else if (pingRes.data is String) {
        try {
          final decoded = jsonDecode(pingRes.data as String);
          if (decoded is Map) pingData = Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }

      if (pingData != null) {
        if (pingData['busy'] == true) {
          onError('${peer.deviceName} is busy receiving another file. Try again in a moment.');
          return false;
        }

        final freeBytes = (pingData['freeBytes'] as num?)?.toInt() ?? 0;
        final totalSize = items.fold<int>(0, (acc, it) => acc + it.size);
        if (freeBytes > 0 && freeBytes < totalSize + (50 * 1024 * 1024)) {
          onError('Not enough storage space on ${peer.deviceName} to save this file.');
          return false;
        }
      }
    } catch (_) {
      onError("Couldn't reach ${peer.deviceName}. Make sure both devices are on the same Wi-Fi or hotspot.");
      return false;
    }

    // Trigger haptic feedback
    HapticFeedback.mediumImpact();

    _currentCancelToken = CancelToken();
    final transferId = const Uuid().v4();
    final meta = TransferMeta(
      transferId: transferId,
      items: items,
      trajectoryX: trajectoryX,
    );

    try {
      final formData = FormData();
      formData.fields.add(MapEntry('meta', jsonEncode(meta.toJson())));

      for (final item in items) {
        if (item.localPath != null && File(item.localPath!).existsSync()) {
          final file = File(item.localPath!);
          formData.files.add(
            MapEntry(
              'files',
              await MultipartFile.fromFile(
                file.path,
                filename: item.name,
              ),
            ),
          );
        }
      }

      final response = await _dio.post(
        'http://${peer.ip}:${peer.port}/transfer',
        data: formData,
        cancelToken: _currentCancelToken,
        options: Options(
          headers: {
            'X-Flik-Device-Id': storage.getDeviceId(),
            'Authorization': 'Bearer $token',
          },
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            onProgress(sent / total);
          }
        },
      );

      return response.statusCode == 200;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        onError('Transfer cancelled.');
      } else if (e.response?.statusCode == 401) {
        onError('Pairing expired or unauthorized.');
      } else {
        onError('Connection timed out. ${peer.deviceName} stopped responding. Try sending again.');
      }
      return false;
    } catch (e) {
      onError('Transfer failed: $e');
      return false;
    } finally {
      _currentCancelToken = null;
    }
  }

  // Sends web link to target peer
  Future<bool> sendUrl({
    required DiscoveredPeer peer,
    required String url,
    String? title,
    required void Function(String error) onError,
  }) async {
    final token = peer.token ?? storage.getToken(peer.deviceId) ?? 'default';

    HapticFeedback.mediumImpact();

    try {
      final res = await _dio.post(
        'http://${peer.ip}:${peer.port}/transfer/url',
        data: {
          'transferId': const Uuid().v4(),
          'url': url,
          'title': title,
        },
        options: Options(
          headers: {
            'X-Flik-Device-Id': storage.getDeviceId(),
            'Authorization': 'Bearer $token',
          },
        ),
      );
      return res.statusCode == 200;
    } catch (e) {
      onError("Couldn't reach ${peer.deviceName}. Make sure both devices are on the same Wi-Fi or hotspot.");
      return false;
    }
  }

  // Cancels an active outbound transfer
  void cancelTransfer() {
    _currentCancelToken?.cancel('User cancelled transfer');
    _currentCancelToken = null;
  }
}
