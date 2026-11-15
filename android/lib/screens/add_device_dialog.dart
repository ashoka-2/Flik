import 'package:flutter/material.dart';
import '../services/connection_pool_service.dart';
import '../theme/tokens.dart';

// Dialog for manual IP device addition (e.g. for Wi-Fi hotspot or isolated subnets).
class AddDeviceDialog extends StatefulWidget {
  final ConnectionPoolService pool;

  const AddDeviceDialog({super.key, required this.pool});

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '54321');
  bool _isConnecting = false;
  String? _errorMessage;

  Future<void> _submit() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 54321;

    if (ip.isEmpty) {
      setState(() => _errorMessage = 'Please enter an IPv4 address');
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final success = await widget.pool.addManualDevice(ip, port);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isConnecting = false;
        _errorMessage = "Couldn't reach $ip:$port. Check network and firewall.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Device Manually', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'Device IPv4 Address',
              hintText: 'e.g. 192.168.1.100',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port (54321 - 54330)',
            ),
            keyboardType: TextInputType.number,
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: FlikTokens.danger, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isConnecting ? null : _submit,
          child: _isConnecting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Connect'),
        ),
      ],
    );
  }
}
