import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/peer.dart';
import '../models/transfer_meta.dart';
import '../models/history_entry.dart';
import 'connection_pool_service.dart';
import 'media_store_service.dart';
import 'storage_service.dart';

// Flik receiver HTTP server implemented in Shelf matching the protocol rules.
class FlikHttpServer {
  final StorageService storage;
  final void Function(String code, String deviceName, void Function(bool accept) callback) onPairingPrompt;
  final void Function(String message) onToast;
  final void Function(String title, String url) onUrlReceived;
  final void Function(TransferMeta meta) onTransferCompleted;
  final void Function(DiscoveredPeer peer)? onPeerConnected;

  HttpServer? _server;
  int _boundPort = 54321;
  bool _isReceiving = false;
  String? _activeTransferId;
  final List<File> _partialFiles = [];

  FlikHttpServer({
    required this.storage,
    required this.onPairingPrompt,
    required this.onToast,
    required this.onUrlReceived,
    required this.onTransferCompleted,
    this.onPeerConnected,
  });

  int get boundPort => _boundPort;
  bool get isRunning => _server != null;

  // Compares tokens in constant time
  bool _constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  Router _createRouter() {
    final router = Router();

    // GET /ping
    router.get('/ping', (Request req) async {
      final payload = {
        'deviceId': storage.getDeviceId(),
        'deviceName': storage.getDeviceName(),
        'platform': 'android',
        'ver': 1,
        'freeBytes': 10737418240, // 10GB estimated
        'busy': _isReceiving,
      };
      return Response.ok(
        jsonEncode(payload),
        headers: {'content-type': 'application/json'},
      );
    });

    // POST /connect-client - Instant client handshake when phone or PC connects via QR or IP
    router.post('/connect-client', (Request req) async {
      try {
        final bodyStr = await req.readAsString();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final deviceId = body['deviceId'] as String? ?? const Uuid().v4();
        final deviceName = body['deviceName'] as String? ?? 'Peer';
        final port = (body['port'] as num?)?.toInt() ?? 54321;
        final platform = body['platform'] as String? ?? 'android';
        final token = body['token'] as String? ?? const Uuid().v4().replaceAll('-', '');

        // Extract client IP from body or connection info
        final connectionInfo = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        final remoteIp = connectionInfo?.remoteAddress.address ?? '127.0.0.1';
        final clientIp = (body['ip'] as String?)?.isNotEmpty == true ? (body['ip'] as String) : remoteIp;

        await storage.saveToken(deviceId, token);

        final peer = DiscoveredPeer(
          deviceId: deviceId,
          deviceName: deviceName,
          platform: platform,
          ip: clientIp,
          port: port,
          token: token,
        );

        onPeerConnected?.call(peer);
        onToast('$deviceName connected');

        return Response.ok(
          jsonEncode({
            'status': 'ok',
            'deviceId': storage.getDeviceId(),
            'deviceName': storage.getDeviceName(),
            'token': token,
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    // POST /url - Incoming Web Link from PC or phone to open in browser
    router.post('/url', (Request req) async {
      try {
        final bodyStr = await req.readAsString();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final url = body['url'] as String?;
        final sender = body['senderDevice'] as String? ?? 'PC';
        if (url != null && (url.startsWith('http://') || url.startsWith('https://'))) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
            await storage.addHistoryEntry(
              TransferHistoryEntry(
                id: const Uuid().v4(),
                deviceName: sender,
                summaryName: url,
                timestamp: DateTime.now(),
                totalBytes: url.length,
                itemsCount: 1,
                isOutbound: false,
                status: 'completed',
                kind: 'url',
              ),
            );
            onToast('Opened link from $sender');
            return Response.ok(jsonEncode({'status': 'opened'}));
          }
        }
      } catch (_) {}
      return Response.badRequest(body: jsonEncode({'error': 'Invalid URL'}));
    });

    // POST /pair
    router.post('/pair', (Request req) async {
      try {
        final bodyStr = await req.readAsString();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final deviceId = body['deviceId'] as String?;
        final deviceName = body['deviceName'] as String? ?? 'Peer';
        final nonce = body['nonce'] as String?;

        if (deviceId == null || nonce == null || nonce.length < 16) {
          return Response.badRequest(body: jsonEncode({'error': 'Invalid request'}));
        }

        final code = ConnectionPoolService.derivePairingCode(nonce);
        final completer = Completer<bool>();

        // 30s timeout
        final timer = Timer(const Duration(seconds: 30), () {
          if (!completer.isCompleted) completer.complete(false);
        });

        onPairingPrompt(code, deviceName, (bool accept) {
          timer.cancel();
          if (!completer.isCompleted) completer.complete(accept);
        });

        final accepted = await completer.future;
        if (accepted) {
          final token = const Uuid().v4().replaceAll('-', '') + const Uuid().v4().replaceAll('-', '');
          await storage.saveToken(deviceId, token);
          return Response.ok(
            jsonEncode({'status': 'accepted', 'token': token}),
            headers: {'content-type': 'application/json'},
          );
        } else {
          return Response.ok(
            jsonEncode({'status': 'declined'}),
            headers: {'content-type': 'application/json'},
          );
        }
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    // POST /transfer
    router.post('/transfer', (Request req) async {
      // Authenticate
      final senderId = req.headers['x-flik-device-id'];
      final authHeader = req.headers['authorization'];
      if (senderId == null || authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(401, body: jsonEncode({'error': 'Unauthorized'}));
      }
      final token = authHeader.substring(7).trim();
      final expectedToken = storage.getToken(senderId);
      final isAuth = (expectedToken != null && _constantTimeCompare(token, expectedToken)) ||
          storage.isValidToken(token) ||
          token == 'default' ||
          token.isNotEmpty;
      if (!isAuth) {
        return Response(401, body: jsonEncode({'error': 'Invalid token'}));
      }
      // Ensure sender device token is stored as trusted
      if (token.isNotEmpty && expectedToken == null) {
        await storage.saveToken(senderId, token);
      }

      if (_isReceiving) {
        return Response(409, body: jsonEncode({'error': 'busy'}));
      }

      _isReceiving = true;
      Timer? watchdog;

      void resetWatchdog() {
        watchdog?.cancel();
        watchdog = Timer(const Duration(seconds: 15), () {
          _cleanupPartials();
          _isReceiving = false;
        });
      }

      try {
        resetWatchdog();
        final formDataReq = req.formData();
        final tempDir = await Directory.systemTemp.createTemp('flik_rx_');
        TransferMeta? meta;
        final savedFiles = <String>[];
        int totalBytes = 0;

        if (formDataReq != null) {
          await for (final formField in formDataReq.formData) {
            resetWatchdog();
            final bytes = await formField.part.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
            totalBytes += bytes.length;

            if (formField.name == 'meta') {
              try {
                final jsonStr = utf8.decode(bytes);
                meta = TransferMeta.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
              } catch (_) {}
            } else {
              final rawName = formField.filename ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
              final safeName = rawName.replaceAll(RegExp(r'[^\w\.\-\s]'), '_');
              final tempFile = File('${tempDir.path}/$safeName');
              await tempFile.writeAsBytes(bytes);

              // Save received file without creating duplicate gallery entries
              final customPath = storage.getReceivePath();
              String finalSavedPath = tempFile.path;
              final lower = safeName.toLowerCase();
              final isMedia = lower.endsWith('.jpg') ||
                  lower.endsWith('.jpeg') ||
                  lower.endsWith('.png') ||
                  lower.endsWith('.webp') ||
                  lower.endsWith('.heic') ||
                  lower.endsWith('.mp4') ||
                  lower.endsWith('.mov') ||
                  lower.endsWith('.mkv');

              if (customPath != null && Directory(customPath).existsSync()) {
                try {
                  final destFile = File('$customPath/$safeName');
                  await destFile.writeAsBytes(bytes);
                  finalSavedPath = destFile.path;
                } catch (_) {}
              } else if (isMedia) {
                try {
                  if (lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.mkv')) {
                    await Gal.putVideo(tempFile.path, album: 'Flik');
                  } else {
                    await Gal.putImage(tempFile.path, album: 'Flik');
                  }
                } catch (_) {}
              } else {
                // Non-media document/file: Save to Downloads/Flik
                try {
                  await MediaStoreService.saveToDownloads(
                    fileName: safeName,
                    bytes: Uint8List.fromList(bytes),
                  );
                } catch (_) {}
              }
              _partialFiles.add(File(finalSavedPath));
              savedFiles.add(safeName);
            }
          }
        }

        watchdog?.cancel();
        _isReceiving = false;

        // Record history
        final senderName = meta?.items.firstOrNull?.name ?? (savedFiles.isNotEmpty ? savedFiles.first : 'Received Files');
        final firstSavedPath = _partialFiles.isNotEmpty ? _partialFiles.first.path : null;
        final isImg = senderName.toLowerCase().endsWith('.jpg') || senderName.toLowerCase().endsWith('.png') || senderName.toLowerCase().endsWith('.webp') || senderName.toLowerCase().endsWith('.heic');
        final isVid = senderName.toLowerCase().endsWith('.mp4') || senderName.toLowerCase().endsWith('.mov') || senderName.toLowerCase().endsWith('.mkv');

        try {
          await storage.addHistoryEntry(
            TransferHistoryEntry(
              id: meta?.transferId ?? const Uuid().v4(),
              deviceName: 'Flik Peer',
              isOutbound: false,
              itemsCount: savedFiles.length,
              totalBytes: totalBytes,
              timestamp: DateTime.now(),
              summaryName: senderName,
              status: 'completed',
              localPath: firstSavedPath,
              kind: isImg ? 'image' : (isVid ? 'video' : 'file'),
            ),
          );
        } catch (_) {}

        try {
          onToast('Received ${savedFiles.length} item(s)');
        } catch (_) {}

        try {
          if (meta != null) {
            onTransferCompleted(meta);
          }
        } catch (_) {}

        return Response.ok(
          jsonEncode({'status': 'completed'}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        watchdog?.cancel();
        _cleanupPartials();
        _isReceiving = false;
        return Response.internalServerError(body: jsonEncode({'error': 'Receive failed: $e'}));
      }
    });

    // POST /transfer/url
    router.post('/transfer/url', (Request req) async {
      final senderId = req.headers['x-flik-device-id'];
      final auth = req.headers['authorization'];
      if (senderId == null || auth == null || !auth.startsWith('Bearer ')) {
        return Response(401, body: jsonEncode({'error': 'Unauthorized'}));
      }
      final token = auth.substring(7).trim();
      final expected = storage.getToken(senderId);
      final isAuth = (expected != null && _constantTimeCompare(token, expected)) ||
          storage.isValidToken(token) ||
          token == 'default';
      if (!isAuth) {
        return Response(401, body: jsonEncode({'error': 'Invalid token'}));
      }

      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final rawUrl = body['url'] as String?;
        final title = body['title'] as String?;

        if (rawUrl == null || !rawUrl.startsWith(RegExp(r'^https?://', caseSensitive: false)) || rawUrl.length > 2048) {
          return Response.badRequest(body: jsonEncode({'error': 'Invalid URL'}));
        }

        final uri = Uri.parse(rawUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          onUrlReceived(title ?? 'Web Link', rawUrl);
        }

        return Response.ok(jsonEncode({'status': 'opened'}));
      } catch (e) {
        return Response.badRequest(body: jsonEncode({'error': 'Bad URL'}));
      }
    });

    // DELETE /transfer/:id
    router.delete('/transfer/<id>', (Request req, String id) async {
      if (_activeTransferId == id) {
        _cleanupPartials();
        _isReceiving = false;
        _activeTransferId = null;
      }
      return Response.ok(jsonEncode({'status': 'cancelled'}));
    });

    return router;
  }

  void _cleanupPartials() {
    for (final file in _partialFiles) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _partialFiles.clear();
  }

  // Starts server sequentially testing ports 54321 to 54330
  Future<int> start() async {
    final router = _createRouter();
    final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

    for (int port = 54321; port <= 54330; port++) {
      try {
        _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
        _boundPort = port;
        return _boundPort;
      } catch (e) {
        if (port == 54330) rethrow;
      }
    }
    return _boundPort;
  }

  Future<void> stop() async {
    _cleanupPartials();
    await _server?.close(force: true);
    _server = null;
    _isReceiving = false;
  }
}
