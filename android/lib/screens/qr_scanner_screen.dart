import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/connection_pool_service.dart';
import '../theme/tokens.dart';

// High-speed camera QR code scanner with explicit permission handling and instant pairing.
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
  MobileScannerController? _controller;
  bool _hasScanned = false;
  bool _hasPermission = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndInit();
  }

  Future<void> _checkPermissionAndInit() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      _initScanner();
    } else {
      final requested = await Permission.camera.request();
      if (requested.isGranted) {
        _initScanner();
      } else {
        if (mounted) {
          setState(() {
            _hasPermission = false;
            _isChecking = false;
          });
        }
      }
    }
  }

  void _initScanner() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    if (mounted) {
      setState(() {
        _hasPermission = true;
        _isChecking = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
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
            final success = await widget.pool.addManualDevice(ip, port);
            if (success) {
              widget.onToast('Connected to $deviceName');
            }
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
          if (_hasPermission && _controller != null) ...[
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _controller?.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () => _controller?.switchCamera(),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isChecking) {
      return const Center(
        child: CircularProgressIndicator(color: FlikTokens.accentSoft),
      );
    }

    if (!_hasPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 56, color: FlikTokens.muted),
              const SizedBox(height: 16),
              const Text(
                'Camera Access Needed',
                style: TextStyle(color: FlikTokens.text, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Camera permission is required to scan the pairing QR code from the Flik Windows Connector.',
                textAlign: TextAlign.center,
                style: TextStyle(color: FlikTokens.muted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await openAppSettings();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Open App Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlikTokens.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          controller: _controller!,
          onDetect: _onDetect,
        ),

        // Viewfinder reticle
        Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: FlikTokens.accent, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),

        // Bottom instruction pill
        Positioned(
          bottom: 48,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
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
    );
  }
}
