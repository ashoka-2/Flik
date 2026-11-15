import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/flik_state.dart';
import '../theme/tokens.dart';
import '../widgets/radar_view.dart';
import '../widgets/staged_deck_widget.dart';
import '../widgets/error_normalizer_toast.dart';
import 'gallery_tab.dart';
import 'files_tab.dart';
import 'links_tab.dart';
import 'library_tab.dart';
import 'add_device_dialog.dart';
import 'qr_scanner_screen.dart';
import 'receive_screen.dart';

// Main Flik mobile screen hosting spatial radar, tactile staged deck, tabs, and error toasts.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentTabIndex = 1; // Default to Gallery tab

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flikAppProvider);
    final notifier = ref.read(flikAppProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Column(
                  children: [
                    // Top App Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: FlikTokens.screenMargin, vertical: 12),
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
                          // Manual Add Device Button
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: FlikTokens.text),
                            tooltip: 'Add Device by IP',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AddDeviceDialog(pool: notifier.connectionPool),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Center Spatial Radar Arc
                    SizedBox(
                      height: constraints.maxHeight * 0.32,
                      child: RadarView(
                        peers: state.peers,
                        lockedPeerId: state.lockedPeerId,
                        compassHeading: state.compassHeading,
                        onPeerTap: (peer) => notifier.lockPeer(peer.deviceId),
                        onSendToAll: state.peers.length > 1 ? () => notifier.triggerSend() : null,
                      ),
                    ),

                    // Tactile Staged Deck Area
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: StagedDeckWidget(
                        items: state.stagedItems,
                        isSending: state.isSending,
                        sendProgress: state.sendProgress,
                        onClear: () => notifier.clearStaging(),
                        onSend: () => notifier.triggerSend(),
                        onCancel: () => notifier.cancelTransfer(),
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
