import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/flik_state.dart';
import '../theme/tokens.dart';

// Dedicated Receive Screen: Turns on mDNS beacon, starts HTTP server, and renders a live pairing QR code.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String _localIp = 'Detecting network...';
  int _port = 54321;
  bool _editingName = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    final storage = ref.read(flikAppProvider.notifier).storage;
    _nameController = TextEditingController(text: storage.getDeviceName());

    // Automatically enable Receive Mode if not already active
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(flikAppProvider.notifier);
      final state = ref.read(flikAppProvider);
      if (!state.isReceiveMode) {
        await notifier.toggleReceiveMode();
      }
      _detectLocalIp();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            if (mounted) {
              setState(() {
                _localIp = addr.address;
                final server = ref.read(flikAppProvider.notifier).server;
                if (server != null) {
                  _port = server.boundPort;
                }
              });
            }
            return;
          }
        }
      }
    } catch (_) {}
  }

  void _saveName() {
    final text = _nameController.text.trim();
    if (text.isNotEmpty) {
      final notifier = ref.read(flikAppProvider.notifier);
      notifier.storage.setDeviceName(text);
      setState(() => _editingName = false);
      notifier.showToast('Device renamed to $text');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flikAppProvider);
    final notifier = ref.read(flikAppProvider.notifier);
    final storage = notifier.storage;
    final deviceName = storage.getDeviceName();
    final deviceId = storage.getDeviceId();

    final qrPayload = jsonEncode({
      'ip': _localIp,
      'port': _port,
      'deviceId': deviceId,
      'deviceName': deviceName,
    });

    return Scaffold(
      backgroundColor: FlikTokens.background,
      appBar: AppBar(
        backgroundColor: FlikTokens.surface,
        title: const Text('Receive Mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Open Phone Gallery',
            onPressed: () => Gal.open(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            // Top Primary Toggle: Receive Mode Active Switch
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: state.isReceiveMode ? Colors.greenAccent.withOpacity(0.12) : FlikTokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: state.isReceiveMode ? Colors.greenAccent.withOpacity(0.5) : FlikTokens.line,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: state.isReceiveMode ? Colors.greenAccent : FlikTokens.raised,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        state.isReceiveMode ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                        size: 22,
                        color: state.isReceiveMode ? Colors.black : FlikTokens.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.isReceiveMode ? 'Receive Mode is Active' : 'Receive Mode Paused',
                          style: TextStyle(
                            color: state.isReceiveMode ? Colors.greenAccent : FlikTokens.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          state.isReceiveMode
                              ? 'Listening for incoming transfers'
                              : 'Tap switch to make device visible',
                          style: const TextStyle(color: FlikTokens.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: state.isReceiveMode,
                    activeColor: Colors.greenAccent,
                    onChanged: (_) => notifier.toggleReceiveMode(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Editable Device Name Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: FlikTokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: FlikTokens.line),
              ),
              child: _editingName
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            autofocus: true,
                            style: const TextStyle(color: FlikTokens.text, fontSize: 16, fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _saveName(),
                          ),
                        ),
                        TextButton(
                          onPressed: _saveName,
                          child: const Text('Save'),
                        ),
                      ],
                    )
                  : InkWell(
                      onTap: () => setState(() => _editingName = true),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: FlikTokens.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(Icons.phone_android, size: 20, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  deviceName,
                                  style: const TextStyle(
                                    color: FlikTokens.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Text(
                                  'Tap to rename device',
                                  style: TextStyle(color: FlikTokens.muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.edit, size: 16, color: FlikTokens.muted),
                        ],
                      ),
                    ),
            ),

            const SizedBox(height: 24),

            // Pulsing Status Beacon
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.greenAccent.withOpacity(0.12),
                      border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.wifi_tethering, size: 36, color: Colors.greenAccent),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            const Text(
              'Ready to Receive',
              style: TextStyle(
                color: FlikTokens.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Visible to other phones and PCs on your Wi-Fi or Hotspot.',
              textAlign: TextAlign.center,
              style: TextStyle(color: FlikTokens.muted, fontSize: 13),
            ),

            const SizedBox(height: 24),

            // Pairing QR Code Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: qrPayload,
                    version: QrVersions.auto,
                    size: 190.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF1B1D22),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF1B1D22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan with Flik Camera to Pair',
                    style: TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // IP Address Badge with Copy
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: '$_localIp:$_port'));
                notifier.showToast('Copied $_localIp:$_port');
              },
              borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: FlikTokens.raised,
                  borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                  border: Border.all(color: FlikTokens.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi, size: 14, color: FlikTokens.accentSoft),
                    const SizedBox(width: 8),
                    Text(
                      '$_localIp:$_port',
                      style: const TextStyle(
                        color: FlikTokens.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, size: 12, color: FlikTokens.muted),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Hotspot / Direct Connect Help Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlikTokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: FlikTokens.line),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 24, color: FlikTokens.accentSoft),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phone-to-Phone Tip',
                          style: TextStyle(
                            color: FlikTokens.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'No Wi-Fi router? Turn on Mobile Hotspot on either phone, connect the other phone to it, and transfer at top speed with 0 internet data.',
                          style: TextStyle(color: FlikTokens.muted, fontSize: 11, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
