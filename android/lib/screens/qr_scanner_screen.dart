import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import '../services/connection_pool_service.dart';
import '../theme/tokens.dart';

// QR Code Scanner enabling instant pairing with Flik Connector on PC or another phone.
// Features robust lifecycle management, camera-flip, gallery image scanning, and manual IP input.
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionAndInit() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
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

  void _initScanner() {
    try {
      _controller = MobileScannerController(
        facing: CameraFacing.back,
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.noDuplicates,
        returnImage: false,
      );

      if (mounted) {
        setState(() {
          _hasPermission = true;
          _isChecking = false;
        });
      }
    } catch (e) {
      debugPrint('Scanner init error: $e');
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _retryCamera() async {
    setState(() => _isChecking = true);
    try {
      await _controller?.stop();
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    await Future.delayed(const Duration(milliseconds: 300));
    _initScanner();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        try {
          final payload = jsonDecode(raw) as Map<String, dynamic>;
          final ip = payload['ip'] as String?;
          final port = (payload['port'] as num?)?.toInt() ?? 54321;

          if (ip != null && ip.isNotEmpty) {
            setState(() => _hasScanned = true);
            widget.onToast('Connecting to PC at $ip:$port...');

            final success = await widget.pool.addManualDevice(ip, port);
            if (success) {
              widget.onToast('Connected successfully!');
              if (mounted) {
                Navigator.pop(context, true);
              }
              return;
            } else {
              widget.onToast("Could not reach PC at $ip:$port. Check that both devices are on the same Wi-Fi.");
              setState(() => _hasScanned = false);
            }
          }
        } catch (_) {
          if (raw.startsWith('http://') || raw.startsWith('https://')) {
            final uri = Uri.tryParse(raw);
            if (uri != null && uri.host.isNotEmpty) {
              setState(() => _hasScanned = true);
              widget.onToast('Connecting to ${uri.host}:${uri.port}...');
              final success = await widget.pool.addManualDevice(uri.host, uri.port != 0 ? uri.port : 54321);
              if (success) {
                widget.onToast('Connected successfully!');
                if (mounted) Navigator.pop(context, true);
                return;
              }
            }
          }
        }
      }
    }
  }

  Future<void> _pickQrFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        widget.onToast('Analyzing image for QR code...');
        final barcodeCapture = await _controller?.analyzeImage(path);
        if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
          _onDetect(barcodeCapture);
        } else {
          widget.onToast('No QR code found in selected image.');
        }
      }
    } catch (e) {
      widget.onToast('Could not analyze image: $e');
    }
  }

  void _showManualIpDialog() {
    final defaultIp = widget.pool.currentPeers.isNotEmpty
        ? widget.pool.currentPeers.first.ip
        : '';
    final ipController = TextEditingController(text: defaultIp);
    final portController = TextEditingController(text: '54321');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlikTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlikTokens.radiusGroup),
          side: const BorderSide(color: FlikTokens.line),
        ),
        title: const Text('Enter PC IP Address', style: TextStyle(color: FlikTokens.text, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the local Wi-Fi IP address shown on your Windows Flik Connector screen:',
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
                  widget.onToast("Could not reach $ip:$port. Check that both devices are on the same Wi-Fi.");
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
          IconButton(
            icon: const Icon(Icons.image_search, color: FlikTokens.accentSoft),
            tooltip: 'Scan QR from Image',
            onPressed: _pickQrFromGallery,
          ),
          TextButton.icon(
            onPressed: _showManualIpDialog,
            icon: const Icon(Icons.dialpad, size: 16, color: FlikTokens.accentSoft),
            label: const Text('Enter IP', style: TextStyle(color: FlikTokens.accentSoft)),
          ),
          if (_hasPermission && _controller != null) ...[
            IconButton(
              icon: const Icon(Icons.flip_camera_ios, size: 20),
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
            final errorText = error.errorDetails?.message ?? error.errorCode.name;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off, size: 48, color: FlikTokens.muted),
                    const SizedBox(height: 12),
                    Text(
                      'Camera unavailable: $errorText',
                      style: const TextStyle(color: FlikTokens.muted, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _retryCamera,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry Camera'),
                          style: ElevatedButton.styleFrom(backgroundColor: FlikTokens.surface, foregroundColor: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _controller?.switchCamera(),
                          icon: const Icon(Icons.flip_camera_ios, size: 16),
                          label: const Text('Flip'),
                          style: ElevatedButton.styleFrom(backgroundColor: FlikTokens.surface, foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _showManualIpDialog,
                      icon: const Icon(Icons.dialpad, size: 16),
                      label: const Text('Enter PC IP Directly'),
                      style: TextButton.styleFrom(foregroundColor: FlikTokens.accentSoft),
                    ),
                    if (widget.pool.currentPeers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: widget.pool.currentPeers.map((peer) {
                          return ActionChip(
                            avatar: const Icon(Icons.laptop, size: 14, color: FlikTokens.accentSoft),
                            label: Text(
                              'Connect to ${peer.deviceName}',
                              style: const TextStyle(fontSize: 12, color: FlikTokens.text),
                            ),
                            backgroundColor: FlikTokens.raised,
                            side: const BorderSide(color: FlikTokens.line),
                            onPressed: () async {
                              final nav = Navigator.of(context);
                              widget.onToast('Connecting to ${peer.deviceName}...');
                              final ok = await widget.pool.addManualDevice(peer.ip, peer.port);
                              if (ok && mounted) nav.pop(true);
                            },
                          );
                        }).toList(),
                      ),
                    ],
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickQrFromGallery,
                    icon: const Icon(Icons.image_search, size: 16, color: Colors.white),
                    label: const Text('Scan Image', style: TextStyle(color: Colors.white, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.black45,
                      side: const BorderSide(color: FlikTokens.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlikTokens.radiusPill)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _showManualIpDialog,
                    icon: const Icon(Icons.dialpad, size: 16, color: Colors.white),
                    label: const Text('Enter IP Manually', style: TextStyle(color: Colors.white, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.black45,
                      side: const BorderSide(color: FlikTokens.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlikTokens.radiusPill)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
