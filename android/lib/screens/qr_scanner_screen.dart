import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/connection_pool_service.dart';
import '../theme/tokens.dart';

// High-speed camera QR code scanner to pair instantly with Flik Windows Connector.
class QrScannerScreen extends StatefulWidget {
  final ConnectionPoolService pool;
  final void Function(String message) onToast;

  const QrScannerScreen({
    super.key,
    required this.pool,
    required this.onToast,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final ip = data['ip'] as String?;
          final port = (data['port'] as num?)?.toInt();
          final deviceName = (data['deviceName'] as String?) ?? 'PC';

          if (ip != null && port != null) {
            _hasScanned = true;
            widget.onToast('Connecting to $deviceName ($ip)...');
            await widget.pool.addManualDevice(ip, port);
            if (mounted) {
              Navigator.pop(context, true);
            }
            return;
          }
        } catch (_) {
          // Ignore non-Flik QR codes during scan
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.6),
        title: const Text('Scan PC QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Viewfinder reticle
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: FlikTokens.accent, width: 2.5),
              borderRadius: BorderRadius.circular(24),
            ),
          ),

          // Bottom instruction pill
          Positioned(
            bottom: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                border: Border.all(color: FlikTokens.line),
              ),
              child: const Text(
                'Point camera at Flik Connector QR on Windows',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
