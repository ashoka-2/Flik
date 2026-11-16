import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/connection_pool_service.dart';
import '../theme/tokens.dart';

// High-speed camera QR code scanner with CameraX error recovery and manual IP fallback.
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
    _controller?.dispose();
    _controller = MobileScannerController(
      autoStart: true,
      formats: const [BarcodeFormat.qrCode],
      facing: CameraFacing.back,
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

  void _showManualIpDialog() {
    final ipController = TextEditingController(text: '10.223.187.101');
    final portController = TextEditingController(text: '54321');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlikTokens.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Connect by IP Address', style: TextStyle(color: FlikTokens.text, fontSize: 18, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the Wi-Fi IP address shown on your Windows Flik Connector:',
              style: TextStyle(color: FlikTokens.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              style: const TextStyle(color: FlikTokens.text),
              decoration: InputDecoration(
                labelText: 'IP Address',
                labelStyle: const TextStyle(color: FlikTokens.muted),
                filled: true,
                fillColor: FlikTokens.raised,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              style: const TextStyle(color: FlikTokens.text),
              decoration: InputDecoration(
                labelText: 'Port',
                labelStyle: const TextStyle(color: FlikTokens.muted),
                filled: true,
                fillColor: FlikTokens.raised,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: FlikTokens.muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = ipController.text.trim();
              final port = int.tryParse(portController.text.trim()) ?? 54321;
              if (ip.isNotEmpty) {
                Navigator.pop(ctx);
                widget.onToast('Connecting to $ip:$port...');
                final success = await widget.pool.addManualDevice(ip, port);
                if (success) {
                  widget.onToast('Connected successfully!');
                  if (mounted) Navigator.pop(context, true);
                } else {
                  widget.onToast("Could not reach $ip:$port. Check that both are on the same Wi-Fi.");
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: FlikTokens.accent, foregroundColor: Colors.white),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.6),
        title: const Text('Scan QR Code'),
        actions: [
          TextButton.icon(
            onPressed: _showManualIpDialog,
            icon: const Icon(Icons.edit, size: 16, color: FlikTokens.accentSoft),
            label: const Text('Enter IP', style: TextStyle(color: FlikTokens.accentSoft)),
          ),
          if (_hasPermission && _controller != null) ...[
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _controller?.toggleTorch(),
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
                'Allow camera permission to scan the Flik QR code, or connect directly by entering your PC\'s Wi-Fi IP address.',
                textAlign: TextAlign.center,
                style: TextStyle(color: FlikTokens.muted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _showManualIpDialog,
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: FlikTokens.line)),
                    child: const Text('Enter IP Manually', style: TextStyle(color: FlikTokens.text)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      await openAppSettings();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: FlikTokens.accent, foregroundColor: Colors.white),
                    child: const Text('Allow Permission'),
                  ),
                ],
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
          errorBuilder: (context, error, child) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off, size: 48, color: FlikTokens.muted),
                    const SizedBox(height: 12),
                    Text(
                      'Camera unavailable: ${error.errorCode.name}',
                      style: const TextStyle(color: FlikTokens.muted, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _initScanner,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry Camera'),
                      style: ElevatedButton.styleFrom(backgroundColor: FlikTokens.surface, foregroundColor: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _showManualIpDialog,
                      icon: const Icon(Icons.keyboard, size: 16),
                      label: const Text('Enter PC IP Directly'),
                      style: TextButton.styleFrom(foregroundColor: FlikTokens.accentSoft),
                    ),
                  ],
                ),
              ),
            );
          },
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

        // Bottom instruction pill + manual IP button
        Positioned(
          bottom: 36,
          left: 20,
          right: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                  border: Border.all(color: FlikTokens.line),
                ),
                child: const Text(
                  'Point camera at Flik QR on PC or other phone',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _showManualIpDialog,
                icon: const Icon(Icons.dialpad, size: 16, color: Colors.white),
                label: const Text('Or Enter IP Manually', style: TextStyle(color: Colors.white, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.black45,
                  side: const BorderSide(color: FlikTokens.line),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlikTokens.radiusPill)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
