import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/flik_state.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../theme/tokens.dart';
import 'add_device_dialog.dart';

// Settings screen providing cache management, storage folder customization,
// history retention rules, device naming, and manual IP pairing.
class SettingsScreen extends ConsumerStatefulWidget {
  final StorageService storage;

  const SettingsScreen({super.key, required this.storage});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _cacheSizeMb = 0.0;
  bool _isClearingCache = false;
  bool _isCheckingUpdates = false;
  String? _receiveFolder;
  int _retentionHours = 168; // 7 days default
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _receiveFolder = widget.storage.getReceivePath();
    _retentionHours = widget.storage.getHistoryRetentionHours();
    _nameController = TextEditingController(text: widget.storage.getDeviceName());
    _calculateCacheSize();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _calculateCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      int totalBytes = 0;
      if (tempDir.existsSync()) {
        final files = tempDir.listSync(recursive: true, followLinks: false);
        for (final file in files) {
          if (file is File) {
            totalBytes += await file.length();
          }
        }
      }
      if (mounted) {
        setState(() {
          _cacheSizeMb = totalBytes / (1024 * 1024);
        });
      }
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    setState(() => _isClearingCache = true);
    final notifier = ref.read(flikAppProvider.notifier);
    double freedMb = _cacheSizeMb;

    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final files = tempDir.listSync(recursive: true, followLinks: false);
        for (final file in files) {
          try {
            if (file is File) await file.delete();
          } catch (_) {}
        }
      }
      imageCache.clear();
      imageCache.clearLiveImages();
      await _calculateCacheSize();
      notifier.showToast('Cache cleared! Freed ${freedMb.toStringAsFixed(1)} MB.');
    } catch (e) {
      notifier.showToast('Error clearing cache: $e');
    } finally {
      if (mounted) setState(() => _isClearingCache = false);
    }
  }

  Future<void> _pickReceiveFolder() async {
    final notifier = ref.read(flikAppProvider.notifier);
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await widget.storage.setReceivePath(selectedDirectory);
        setState(() => _receiveFolder = selectedDirectory);
        notifier.showToast('Receive folder updated!');
      }
    } catch (e) {
      notifier.showToast('Could not select folder: $e');
    }
  }

  Future<void> _resetReceiveFolder() async {
    await widget.storage.setReceivePath(null);
    setState(() => _receiveFolder = null);
    ref.read(flikAppProvider.notifier).showToast('Reset to default gallery storage.');
  }

  Future<void> _saveDeviceName() async {
    final newName = _nameController.text.trim();
    if (newName.isNotEmpty) {
      await widget.storage.setDeviceName(newName);
      ref.read(flikAppProvider.notifier).showToast('Device name saved: $newName');
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingUpdates) return;
    setState(() => _isCheckingUpdates = true);
    final notifier = ref.read(flikAppProvider.notifier);
    try {
      final update = await UpdateService().checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        notifier.showToast('Flik is up to date.');
        return;
      }

      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: FlikTokens.surface,
          title: Text('Flik ${update.version} is available'),
          content: const Text('Download the new APK? Android will ask you to confirm the installation.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update now'),
            ),
          ],
        ),
      );

      if (shouldUpdate == true) {
        final opened = await launchUrl(Uri.parse(update.apkUrl), mode: LaunchMode.externalApplication);
        if (!opened) notifier.showToast('Could not open the APK download.');
      }
    } catch (_) {
      if (mounted) notifier.showToast('Could not check for updates. Try again when online.');
    } finally {
      if (mounted) setState(() => _isCheckingUpdates = false);
    }
  }

  Future<void> _openGitHubProfile() async {
    await launchUrl(Uri.parse('https://github.com/ashoka-2'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(flikAppProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: FlikTokens.surface,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Device Name Section
          _buildSectionHeader('Device Identity'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FlikTokens.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(color: FlikTokens.text, fontSize: 15),
                    decoration: const InputDecoration(
                      labelText: 'Device Name',
                      labelStyle: TextStyle(color: FlikTokens.muted),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _saveDeviceName,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlikTokens.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Storage Folder for Received Files
          _buildSectionHeader('Receive Folder'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FlikTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Where received files from PC & phones are stored:',
                  style: TextStyle(color: FlikTokens.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  _receiveFolder ?? 'Default (Phone Gallery & Downloads/Flik)',
                  style: const TextStyle(color: FlikTokens.text, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickReceiveFolder,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Change Folder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FlikTokens.raised,
                        foregroundColor: FlikTokens.text,
                        elevation: 0,
                        side: const BorderSide(color: FlikTokens.line),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    if (_receiveFolder != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _resetReceiveFolder,
                        child: const Text('Reset', style: TextStyle(color: FlikTokens.muted)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Cache & Storage Optimization
          _buildSectionHeader('Storage & Cache Optimization'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FlikTokens.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Temporary Media Cache',
                        style: TextStyle(color: FlikTokens.text, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_cacheSizeMb.toStringAsFixed(1)} MB cached previews',
                        style: const TextStyle(color: FlikTokens.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isClearingCache ? null : _clearCache,
                  icon: _isClearingCache
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Clear Cache'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlikTokens.raised,
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. History Retention Period
          _buildSectionHeader('Transfer Library Retention'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FlikTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Automatically clean up transfer history after:',
                  style: TextStyle(color: FlikTokens.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildRetentionChip('24 Hours', 24),
                    _buildRetentionChip('7 Days', 168),
                    _buildRetentionChip('30 Days', 720),
                    _buildRetentionChip('Forever', -1),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    await widget.storage.clearHistory();
                    notifier.showToast('Transfer history cleared');
                  },
                  icon: const Icon(Icons.clear_all, size: 16, color: FlikTokens.muted),
                  label: const Text('Clear All History', style: TextStyle(color: FlikTokens.muted, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5. Manual Device Connect
          _buildSectionHeader('Direct Connection'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FlikTokens.line),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connect by IP Address', style: TextStyle(color: FlikTokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Manually enter PC or phone Wi-Fi IP', style: TextStyle(color: FlikTokens.muted, fontSize: 13)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AddDeviceDialog(pool: notifier.connectionPool),
                    );
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add IP'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FlikTokens.accentSoft,
                    side: const BorderSide(color: FlikTokens.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 6. Updates and project links
          _buildSectionHeader('About Flik'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FlikTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _isCheckingUpdates ? null : _checkForUpdates,
                  icon: _isCheckingUpdates
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.system_update_alt, size: 18),
                  label: Text(_isCheckingUpdates ? 'Checking…' : 'Check for updates'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlikTokens.raised,
                    foregroundColor: FlikTokens.text,
                    elevation: 0,
                    side: const BorderSide(color: FlikTokens.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openGitHubProfile,
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('GitHub · @ashoka-2'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FlikTokens.accentSoft,
                    side: const BorderSide(color: FlikTokens.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: FlikTokens.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildRetentionChip(String label, int hours) {
    final isSelected = _retentionHours == hours;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) async {
        if (val) {
          setState(() => _retentionHours = hours);
          await widget.storage.setHistoryRetentionHours(hours);
          ref.read(flikAppProvider.notifier).showToast('Retention rule updated: $label');
        }
      },
      selectedColor: FlikTokens.accent.withOpacity(0.2),
      backgroundColor: FlikTokens.raised,
      labelStyle: TextStyle(
        color: isSelected ? FlikTokens.accentSoft : FlikTokens.text,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
        side: BorderSide(color: isSelected ? FlikTokens.accentSoft : FlikTokens.line),
      ),
    );
  }
}
