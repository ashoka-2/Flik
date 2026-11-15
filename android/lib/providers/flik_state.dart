import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/peer.dart';
import '../models/transfer_item.dart';
import '../models/history_entry.dart';
import '../services/storage_service.dart';
import '../services/connection_pool_service.dart';
import '../services/flik_http_server.dart';
import '../services/flik_http_client.dart';
import '../services/sensor_service.dart';
import '../services/foreground_receiver_service.dart';

class FlikAppState {
  final List<DiscoveredPeer> peers;
  final List<TransferItem> stagedItems;
  final bool isReceiveMode;
  final double compassHeading;
  final String? lockedPeerId;
  final bool isSending;
  final double sendProgress;
  final String? activeToast;
  final Map<String, dynamic>? pendingPairing;

  FlikAppState({
    this.peers = const [],
    this.stagedItems = const [],
    this.isReceiveMode = false,
    this.compassHeading = 0.0,
    this.lockedPeerId,
    this.isSending = false,
    this.sendProgress = 0.0,
    this.activeToast,
    this.pendingPairing,
  });

  FlikAppState copyWith({
    List<DiscoveredPeer>? peers,
    List<TransferItem>? stagedItems,
    bool? isReceiveMode,
    double? compassHeading,
    String? lockedPeerId,
    bool clearLockedPeer = false,
    bool? isSending,
    double? sendProgress,
    String? activeToast,
    bool clearToast = false,
    Map<String, dynamic>? pendingPairing,
    bool clearPairing = false,
  }) {
    return FlikAppState(
      peers: peers ?? this.peers,
      stagedItems: stagedItems ?? this.stagedItems,
      isReceiveMode: isReceiveMode ?? this.isReceiveMode,
      compassHeading: compassHeading ?? this.compassHeading,
      lockedPeerId: clearLockedPeer ? null : (lockedPeerId ?? this.lockedPeerId),
      isSending: isSending ?? this.isSending,
      sendProgress: sendProgress ?? this.sendProgress,
      activeToast: clearToast ? null : (activeToast ?? this.activeToast),
      pendingPairing: clearPairing ? null : (pendingPairing ?? this.pendingPairing),
    );
  }
}

class FlikAppNotifier extends StateNotifier<FlikAppState> {
  final StorageService storage;
  late final ConnectionPoolService connectionPool;
  late final FlikHttpClient client;
  FlikHttpServer? server;
  SensorService? sensorService;
  StreamSubscription? _peersSub;
  Timer? _toastTimer;

  FlikAppNotifier({required this.storage}) : super(FlikAppState()) {
    connectionPool = ConnectionPoolService(storage: storage);
    client = FlikHttpClient(storage: storage);
    _init();
  }

  void _init() {
    _peersSub = connectionPool.peersStream.listen((updatedPeers) {
      _layoutPeersOnRadar(updatedPeers);
    });

    connectionPool.startDiscovery();

    // Start sensors
    sensorService = SensorService(
      onFlick: () => triggerSend(),
      onHeadingChanged: (heading) {
        state = state.copyWith(compassHeading: heading);
      },
    );
    sensorService?.start();
  }

  // Distributes peers along semicircle radar arc: -60, -30, 0, +30, +60 degrees
  void _layoutPeersOnRadar(List<DiscoveredPeer> rawPeers) {
    const fixedAngles = [-60.0, -30.0, 0.0, 30.0, 60.0];
    for (int i = 0; i < rawPeers.length; i++) {
      rawPeers[i].angle = fixedAngles[i % fixedAngles.length];
      rawPeers[i].isLocked = rawPeers[i].deviceId == state.lockedPeerId;
    }
    state = state.copyWith(peers: List.from(rawPeers));
  }

  void stageItems(List<TransferItem> items) {
    final existingIds = state.stagedItems.map((e) => e.id).toSet();
    final newItems = items.where((e) => !existingIds.contains(e.id)).toList();
    state = state.copyWith(stagedItems: [...state.stagedItems, ...newItems]);
  }

  void unstageItem(String id) {
    state = state.copyWith(
      stagedItems: state.stagedItems.where((e) => e.id !== id).toList(),
    );
  }

  void clearStaging() {
    state = state.copyWith(stagedItems: []);
  }

  void lockPeer(String deviceId) {
    if (state.lockedPeerId == deviceId) {
      state = state.copyWith(clearLockedPeer: true);
    } else {
      state = state.copyWith(lockedPeerId: deviceId);
    }
    _layoutPeersOnRadar(state.peers);
  }

  Future<void> toggleReceiveMode() async {
    final newMode = !state.isReceiveMode;
    state = state.copyWith(isReceiveMode: newMode);

    if (newMode) {
      await ForegroundReceiverService.start();
      server = FlikHttpServer(
        storage: storage,
        onPairingPrompt: (code, devName, cb) {
          state = state.copyWith(
            pendingPairing: {
              'code': code,
              'deviceName': devName,
              'callback': cb,
            },
          );
        },
        onToast: (msg) => showToast(msg),
        onUrlReceived: (title, url) => showToast('Opened $title'),
        onTransferCompleted: (meta) => showToast('Received transfer'),
      );
      await server?.start();
    } else {
      await server?.stop();
      server = null;
      await ForegroundReceiverService.stop();
    }
  }

  void respondPairing(bool accept) {
    final pending = state.pendingPairing;
    if (pending != null) {
      final cb = pending['callback'] as void Function(bool);
      cb(accept);
      state = state.copyWith(clearPairing: true);
    }
  }

  Future<void> triggerSend({double? trajectoryX}) async {
    if (state.stagedItems.isEmpty || state.isSending) return;
    if (state.peers.isEmpty) {
      showToast('No peers found nearby. Make sure devices are on Wi-Fi.');
      return;
    }

    // Determine target: locked peer or first peer or all peers
    final targetPeers = state.lockedPeerId != null
        ? state.peers.where((p) => p.deviceId == state.lockedPeerId).toList()
        : [state.peers.first];

    if (targetPeers.isEmpty) return;

    state = state.copyWith(isSending: true, sendProgress: 0.0);

    for (final peer in targetPeers) {
      // Pair if not paired yet
      if (peer.token == null && storage.getToken(peer.deviceId) == null) {
        final paired = await connectionPool.pairWithPeer(
          peer,
          onCodeGenerated: (code) => showToast('Pairing with ${peer.deviceName}: code $code'),
        );
        if (!paired) {
          showToast('${peer.deviceName} declined the connection request.');
          state = state.copyWith(isSending: false);
          return;
        }
      }

      final success = await client.sendFiles(
        peer: peer,
        items: state.stagedItems,
        trajectoryX: trajectoryX,
        onProgress: (p) => state = state.copyWith(sendProgress: p),
        onError: (err) => showToast(err),
      );

      if (success) {
        showToast('A little magic, delivered.');
        // Record history
        await storage.addHistoryEntry(
          TransferHistoryEntry(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            deviceName: peer.deviceName,
            isOutbound: true,
            itemsCount: state.stagedItems.length,
            totalBytes: state.stagedItems.fold(0, (sum, i) => sum + i.size),
            timestamp: DateTime.now(),
            summaryName: state.stagedItems.first.name,
            status: 'completed',
          ),
        );
        clearStaging();
      }
    }

    state = state.copyWith(isSending: false, sendProgress: 0.0);
  }

  void cancelTransfer() {
    client.cancelTransfer();
    state = state.copyWith(isSending: false, sendProgress: 0.0);
  }

  void showToast(String message) {
    _toastTimer?.cancel();
    state = state.copyWith(activeToast: message);
    _toastTimer = Timer(const Duration(milliseconds: 3500), () {
      state = state.copyWith(clearToast: true);
    });
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    sensorService?.stop();
    server?.stop();
    _toastTimer?.cancel();
    super.dispose();
  }
}

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Initialize StorageService in main');
});

final flikAppProvider = StateNotifierProvider<FlikAppNotifier, FlikAppState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return FlikAppNotifier(storage: storage);
});
