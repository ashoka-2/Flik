import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bonsoir/bonsoir.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/peer.dart';
import 'media_store_service.dart';
import 'storage_service.dart';

// Discovers local Flik devices using mDNS (Bonsoir) and subnet IP scanning fallback.
class ConnectionPoolService {
  final StorageService storage;
  BonsoirDiscovery? _discovery;
  final Map<String, DiscoveredPeer> _peers = {};
  final StreamController<List<DiscoveredPeer>> _peersController = StreamController.broadcast();
  final Dio _dio = Dio();
  bool _isScanning = false;
  Timer? _hotspotFallbackTimer;

  Stream<List<DiscoveredPeer>> get peersStream => _peersController.stream;
  List<DiscoveredPeer> get currentPeers => _peers.values.toList();

  ConnectionPoolService({required this.storage});

  // Derives 4-digit numeric confirmation code from pairing nonce
  static String derivePairingCode(String nonce) {
    final bytes = utf8.encode(nonce);
    final digest = sha256.convert(bytes);
    final byteData = ByteData.sublistView(Uint8List.fromList(digest.bytes.take(4).toList()));
    final num = byteData.getUint32(0);
    return ((num % 9000) + 1000).toString();
  }

  // Starts discovering peers via mDNS, with 1.5s fallback to parallel subnet scan
  Future<void> startDiscovery() async {
    if (_isScanning) return;
    _isScanning = true;

    await MediaStoreService.acquireMulticastLock();

    try {
      _discovery = BonsoirDiscovery(type: '_flik._tcp');
      await _discovery!.ready;

      _discovery!.eventStream!.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          event.service!.resolve(_discovery!.serviceResolver);
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
          final service = event.service as ResolvedBonsoirService;
          final attributes = service.attributes;
          final deviceId = attributes['deviceId'];
          final myId = storage.getDeviceId();

          if (deviceId != null && deviceId != myId) {
            final peer = DiscoveredPeer(
              deviceId: deviceId,
              deviceName: attributes['deviceName'] ?? service.name,
              platform: attributes['platform'] ?? 'windows',
              ip: service.host ?? '127.0.0.1',
              port: service.port,
              token: storage.getToken(deviceId),
            );
            _peers[deviceId] = peer;
            _peersController.add(_peers.values.toList());
          }
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
          final service = event.service;
          if (service != null) {
            _peers.removeWhere((k, v) => v.deviceName == service.name);
            _peersController.add(_peers.values.toList());
          }
        }
      });

      await _discovery!.start();
    } catch (e) {
      // mDNS initialization issue (hotspot or restricted network)
    }

    // Hotspot Fallback: if mDNS discovers nothing within 1.5s, trigger subnet scan
    _hotspotFallbackTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_peers.isEmpty) {
        scanLocalSubnet();
      }
    });
  }

  // Scans local /24 subnet across Flik ports (54321-54330) in parallel with short timeouts
  Future<void> scanLocalSubnet() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          final subnetPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';

          // Probe common LAN IP ranges in parallel
          final futures = <Future>[];
          for (int host = 1; host <= 254; host++) {
            final targetIp = '$subnetPrefix.$host';
            if (targetIp == addr.address) continue; // Skip self

            futures.add(_probeFlikPort(targetIp));
          }

          await Future.wait(futures);
        }
      }
    } catch (_) {}
  }

  // Probes an IP on standard Flik ports for /ping pre-flight response
  Future<void> _probeFlikPort(String ip) async {
    for (int port = 54321; port <= 54330; port++) {
      try {
        final socket = await Socket.connect(
          ip,
          port,
          timeout: const Duration(milliseconds: 300),
        );
        socket.destroy();

        // Socket is open, ping it
        final ping = await preflightPing(ip, port);
        if (ping != null && ping['deviceId'] != storage.getDeviceId()) {
          final peer = DiscoveredPeer(
            deviceId: ping['deviceId'] as String,
            deviceName: ping['deviceName'] as String? ?? 'PC',
            platform: ping['platform'] as String? ?? 'windows',
            ip: ip,
            port: port,
            token: storage.getToken(ping['deviceId'] as String),
          );
          _peers[peer.deviceId] = peer;
          _peersController.add(_peers.values.toList());
          return;
        }
      } catch (_) {}
    }
  }

  // GET /ping pre-flight check with 800ms timeout
  Future<Map<String, dynamic>?> preflightPing(String ip, int port) async {
    try {
      final res = await _dio.get(
        'http://$ip:$port/ping',
        options: Options(
          receiveTimeout: const Duration(milliseconds: 800),
          sendTimeout: const Duration(milliseconds: 800),
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // Initiates pairing handshake with a peer device
  Future<bool> pairWithPeer(DiscoveredPeer peer, {required void Function(String code) onCodeGenerated}) async {
    final nonce = const Uuid().v4().replaceAll('-', '');
    final code = derivePairingCode(nonce);
    onCodeGenerated(code);

    try {
      final res = await _dio.post(
        'http://${peer.ip}:${peer.port}/pair',
        data: {
          'deviceId': storage.getDeviceId(),
          'deviceName': storage.getDeviceName(),
          'platform': 'android',
          'nonce': nonce,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (res.statusCode == 200 && res.data != null) {
        final data = res.data as Map<String, dynamic>;
        if (data['status'] == 'accepted' && data['token'] != null) {
          final token = data['token'] as String;
          peer.token = token;
          await storage.saveToken(peer.deviceId, token);
          _peersController.add(_peers.values.toList());
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // Adds a device manually by IP and port and registers mutual client handshake
  Future<bool> addManualDevice(String ip, int port) async {
    final ping = await preflightPing(ip, port);
    if (ping != null) {
      final peer = DiscoveredPeer(
        deviceId: ping['deviceId'] as String,
        deviceName: ping['deviceName'] as String? ?? 'Manual Device',
        platform: ping['platform'] as String? ?? 'windows',
        ip: ip,
        port: port,
        token: storage.getToken(ping['deviceId'] as String),
      );

      // Perform instant mutual client handshake so PC knows about this phone and registers token
      try {
        final clientToken = storage.getToken(peer.deviceId) ?? const Uuid().v4().replaceAll('-', '');
        await storage.saveToken(peer.deviceId, clientToken);
        peer.token = clientToken;

        await _dio.post(
          'http://$ip:$port/connect-client',
          data: {
            'deviceId': storage.getDeviceId(),
            'deviceName': storage.getDeviceName(),
            'platform': 'android',
            'port': 54321,
            'token': clientToken,
          },
          options: Options(sendTimeout: const Duration(seconds: 4), receiveTimeout: const Duration(seconds: 4)),
        );
      } catch (_) {}

      _peers[peer.deviceId] = peer;
      _peersController.add(_peers.values.toList());
      return true;
    }
    return false;
  }

  // Stops discovery and releases locks
  Future<void> stop() async {
    _isScanning = false;
    _hotspotFallbackTimer?.cancel();
    try {
      await _discovery?.stop();
    } catch (_) {}
    await MediaStoreService.releaseMulticastLock();
  }
}
