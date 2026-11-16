import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/transfer_item.dart';
import '../providers/flik_state.dart';
import '../theme/tokens.dart';
import '../widgets/radar_view.dart';
import '../widgets/staged_deck_widget.dart';
import '../widgets/error_normalizer_toast.dart';
import 'gallery_tab.dart';
import 'files_tab.dart';
import 'links_tab.dart';
import 'library_tab.dart';
import 'qr_scanner_screen.dart';
import 'receive_screen.dart';
import 'settings_screen.dart';

// Main Flik mobile screen hosting spatial radar, tactile staged deck, tabs, and error toasts.
// Supports resizable / collapsible drawer for viewing all gallery photos full screen,
// and system Share Sheet listener for images, long videos, and browser web links.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentTabIndex = 1; // Default to Gallery tab
  double _radarHeightFactor = 0.32; // Default 32% screen height
  bool _isRadarCollapsed = false;
  StreamSubscription? _mediaStreamSub;

  @override
  void initState() {
    super.initState();
    _initShareHandler();
  }

  void _initShareHandler() async {
    final handler = ShareHandlerPlatform.instance;
    try {
      final initialMedia = await handler.getInitialSharedMedia();
      if (initialMedia != null) {
        _processSharedMedia(initialMedia);
      }
    } catch (e) {
      debugPrint('Initial share media error: $e');
    }

    _mediaStreamSub = handler.sharedMediaStream.listen((SharedMedia media) {
      _processSharedMedia(media);
    });
  }

  void _processSharedMedia(SharedMedia media) async {
    final notifier = ref.read(flikAppProvider.notifier);
    final state = ref.read(flikAppProvider);

    // 1. Process shared Web URL (e.g. from Chrome, Edge, Brave)
    if (media.content != null && media.content!.trim().isNotEmpty) {
      final text = media.content!.trim();
      final uri = Uri.tryParse(text);
      final isUrl = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

      if (isUrl) {
        if (state.peers.isNotEmpty) {
          notifier.showToast('Sending link to ${state.peers.first.deviceName}...');
          await notifier.sendUrl(text, title: 'Shared Link');
        } else {
          notifier.stageItems([
            TransferItem(
              id: const Uuid().v4(),
              name: text,
              size: text.length,
              mime: 'text/uri-list',
              kind: 'file',
              url: text,
            ),
          ]);
          setState(() => _currentTabIndex = 3); // Links tab
          notifier.showToast('Link saved in Links. Connect to PC to open.');
        }
      }
    }

    // 2. Process shared media / files (photos, videos from device gallery)
    if (media.attachments != null && media.attachments!.isNotEmpty) {
      final items = <TransferItem>[];
      for (final att in media.attachments!) {
        if (att != null && att.path.isNotEmpty) {
          final file = File(att.path);
          if (await file.exists()) {
            final fileName = att.path.split(Platform.pathSeparator).last;
            final ext = fileName.split('.').last.toLowerCase();
            final isImg = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'].contains(ext);
            final isVid = ['mp4', 'mkv', 'mov', 'avi', 'webm', '3gp'].contains(ext);
            final kind = isImg ? 'image' : (isVid ? 'video' : 'file');
            final mime = isImg ? 'image/$ext' : (isVid ? 'video/$ext' : 'application/octet-stream');
            final size = await file.length();

            items.add(
              TransferItem(
                id: const Uuid().v4(),
                name: fileName,
                size: size,
                mime: mime,
                kind: kind,
                localPath: att.path,
              ),
            );
          }
        }
      }

      if (items.isNotEmpty) {
        notifier.stageItems(items);
        setState(() => _currentTabIndex = 1); // Gallery tab
        notifier.showToast('Staged ${items.length} item(s) from share. Flick to send!');
      }
    }
  }

  @override
  void dispose() {
    _mediaStreamSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flikAppProvider);
    final notifier = ref.read(flikAppProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double activeRadarHeight = _isRadarCollapsed
                ? 38.0
                : (constraints.maxHeight * _radarHeightFactor).clamp(70.0, constraints.maxHeight * 0.55);

            return Stack(
              children: [
                Column(
                  children: [
                    // Top App Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: FlikTokens.screenMargin, vertical: 10),
                      child: Row(
                        children: [
                          const Text(
                            'Flik',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: FlikTokens.text,
                            ),
                          ),
                          const Spacer(),
                          // Receive Screen Button
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ReceiveScreen()),
                              );
                            },
                            icon: Icon(
                              state.isReceiveMode ? Icons.wifi_tethering : Icons.arrow_downward,
                              size: 15,
                              color: state.isReceiveMode ? Colors.greenAccent : Colors.white,
                            ),
                            label: Text(
                              state.isReceiveMode ? 'Receiving...' : 'Receive',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: state.isReceiveMode ? Colors.greenAccent : Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: state.isReceiveMode
                                  ? Colors.greenAccent.withOpacity(0.15)
                                  : FlikTokens.surface,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              minimumSize: const Size(60, 36),
                              side: BorderSide(
                                color: state.isReceiveMode ? Colors.greenAccent : FlikTokens.line,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // QR Code Scanner Button
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner, color: FlikTokens.accentSoft),
                            tooltip: 'Scan PC QR',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => QrScannerScreen(
                                    pool: notifier.connectionPool,
                                    onToast: (msg) => notifier.showToast(msg),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Settings Button
                          IconButton(
                            icon: const Icon(Icons.settings_outlined, color: FlikTokens.text),
                            tooltip: 'Settings',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SettingsScreen(storage: notifier.storage),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Top Connecting / Radar Area (Collapsible / Resizable)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: activeRadarHeight,
                      child: _isRadarCollapsed
                          ? InkWell(
                              onTap: () => setState(() {
                                _isRadarCollapsed = false;
                                _radarHeightFactor = 0.32;
                              }),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: FlikTokens.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: FlikTokens.line),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.radar,
                                      size: 16,
                                      color: state.peers.isNotEmpty ? Colors.greenAccent : FlikTokens.accentSoft,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        state.peers.isEmpty
                                            ? 'Radar minimized • Tap to expand'
                                            : '${state.peers.first.deviceName} connected • Tap to expand radar',
                                        style: const TextStyle(fontSize: 12, color: FlikTokens.muted),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.keyboard_arrow_down, size: 18, color: FlikTokens.muted),
                                  ],
                                ),
                              ),
                            )
                          : RadarView(
                              peers: state.peers,
                              lockedPeerId: state.lockedPeerId,
                              compassHeading: state.compassHeading,
                              onPeerTap: (peer) => notifier.lockPeer(peer.deviceId),
                              onSendToAll: state.peers.length > 1 ? () => notifier.triggerSend() : null,
                            ),
                    ),

                    // Tactile Staged Deck Area (only visible when items are staged)
                    if (state.stagedItems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: StagedDeckWidget(
                          items: state.stagedItems,
                          isSending: state.isSending,
                          sendProgress: state.sendProgress,
                          onClear: () => notifier.clearStaging(),
                          onSend: () => notifier.triggerSend(),
                          onCancel: () => notifier.cancelTransfer(),
                        ),
                      ),

                    // Draggable / Resizable Divider Handle
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        setState(() {
                          final delta = details.primaryDelta ?? 0;
                          final newH = (_radarHeightFactor * constraints.maxHeight) + delta;
                          _radarHeightFactor = (newH / constraints.maxHeight).clamp(0.05, 0.55);
                          _isRadarCollapsed = _radarHeightFactor <= 0.08;
                        });
                      },
                      onDoubleTap: () {
                        setState(() {
                          _isRadarCollapsed = !_isRadarCollapsed;
                          _radarHeightFactor = _isRadarCollapsed ? 0.05 : 0.32;
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        color: Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: FlikTokens.line.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const Divider(height: 1, color: FlikTokens.line),

                    // Bottom Tab Content (Gallery, Files, Links, Library)
                    Expanded(
                      child: IndexedStack(
                        index: _currentTabIndex,
                        children: [
                          LibraryTab(
                            storage: notifier.storage,
                            onToast: (msg) => notifier.showToast(msg),
                          ),
                          GalleryTab(
                            onStageItems: (items) => notifier.stageItems(items),
                          ),
                          FilesTab(
                            onStageItems: (items) => notifier.stageItems(items),
                          ),
                          LinksTab(
                            onStageItem: (item) => notifier.stageItems([item]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Floating Error Normalizer Toast
                if (state.activeToast != null)
                  ErrorNormalizerToast(message: state.activeToast!),

                // Pairing Confirmation Modal Dialog
                if (state.pendingPairing != null)
                  _buildPairingDialog(context, notifier, state.pendingPairing!),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        backgroundColor: FlikTokens.surface,
        selectedItemColor: FlikTokens.accentSoft,
        unselectedItemColor: FlikTokens.muted,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: 'Gallery'),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Files'),
          BottomNavigationBarItem(icon: Icon(Icons.link), label: 'Links'),
        ],
      ),
    );
  }

  Widget _buildPairingDialog(BuildContext context, FlikAppNotifier notifier, Map<String, dynamic> pairing) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: FlikTokens.surface,
          borderRadius: BorderRadius.circular(FlikTokens.radiusGroup),
          border: Border.all(color: FlikTokens.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Connect with Device?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: FlikTokens.text),
            ),
            const SizedBox(height: 8),
            Text(
              pairing['deviceName'] ?? 'Peer',
              style: const TextStyle(fontSize: 14, color: FlikTokens.muted),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: FlikTokens.raised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: FlikTokens.line),
              ),
              child: Text(
                pairing['code'] ?? '0000',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: FlikTokens.accentSoft,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => notifier.respondPairing(false),
                  child: const Text('Not now'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => notifier.respondPairing(true),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
