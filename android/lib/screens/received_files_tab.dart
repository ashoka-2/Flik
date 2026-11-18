import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/history_entry.dart';
import '../providers/flik_state.dart';
import '../services/storage_service.dart';
import '../theme/tokens.dart';

// Dedicated Received Files tab showcasing all incoming files, photos, videos,
// audio tracks, and web links received from PC or other phones.
class ReceivedFilesTab extends ConsumerStatefulWidget {
  final StorageService storage;

  const ReceivedFilesTab({super.key, required this.storage});

  @override
  ConsumerState<ReceivedFilesTab> createState() => _ReceivedFilesTabState();
}

class _ReceivedFilesTabState extends ConsumerState<ReceivedFilesTab> {
  static const _fileChannel = MethodChannel('flik/files');
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Photos', 'Videos', 'Audio', 'Files', 'Links'];

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(flikAppProvider.notifier);
    final history = widget.storage.getHistory();

    // Filter to inbound / received items only
    final receivedEntries = history.where((e) {
      if (e.isOutbound) return false;
      if (_selectedFilter == 'All') return true;
      if (_selectedFilter == 'Photos') return e.kind == 'image' || e.kind == 'photo';
      if (_selectedFilter == 'Videos') return e.kind == 'video';
      if (_selectedFilter == 'Audio') return e.kind == 'audio';
      if (_selectedFilter == 'Links') return e.kind == 'link' || e.kind == 'url';
      if (_selectedFilter == 'Files') return e.kind == 'file';
      return true;
    }).toList();
    final receivedPathCounts = <String, int>{};
    for (final entry in receivedEntries) {
      final path = entry.localPath;
      if (path != null) receivedPathCounts.update(path, (count) => count + 1, ifAbsent: () => 1);
    }

    return Column(
      children: [
        // Category Filter Chips
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final f = _filters[idx];
              final isSelected = _selectedFilter == f;
              return GestureDetector(
                onTap: () => setState(() => _selectedFilter = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? FlikTokens.accent : FlikTokens.raised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? FlikTokens.accent : FlikTokens.line),
                  ),
                  child: Center(
                    child: Text(
                      f,
                      style: TextStyle(
                        color: isSelected ? Colors.white : FlikTokens.muted,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // List of Received Items
        Expanded(
          child: receivedEntries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inbox_outlined, size: 48, color: FlikTokens.muted),
                      const SizedBox(height: 12),
                      Text(
                        'No $_selectedFilter received yet',
                        style: const TextStyle(color: FlikTokens.text, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Photos, videos, files and links received from PC or phones will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: FlikTokens.muted, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  color: FlikTokens.accentSoft,
                  backgroundColor: FlikTokens.surface,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    itemCount: receivedEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final entry = receivedEntries[idx];
                      final legacySharedPath = entry.localPath != null && (receivedPathCounts[entry.localPath] ?? 0) > 1;
                      return _buildReceivedCard(context, entry, notifier, legacySharedPath: legacySharedPath);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildReceivedCard(
    BuildContext context,
    TransferHistoryEntry entry,
    dynamic notifier, {
    required bool legacySharedPath,
  }) {
    final isUrl = entry.kind == 'url' || entry.kind == 'link' || entry.itemsCount == 0;
    final isVideo = entry.kind == 'video';
    final isAudio = entry.kind == 'audio';
    final isImage = entry.kind == 'image' || entry.kind == 'photo';
    final hasLocalFile = !legacySharedPath && entry.localPath != null && File(entry.localPath!).existsSync();
    Future<void> openEntry() async {
      if (isUrl) {
        final uri = Uri.tryParse(entry.summaryName);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          notifier.showToast('This link is not valid');
        }
      } else if (hasLocalFile) {
        try {
          await _fileChannel.invokeMethod<bool>('openFile', {
            'path': entry.localPath,
            'mimeType': _mimeFor(entry.localPath!),
          });
        } on PlatformException catch (error) {
          notifier.showToast(error.message ?? 'No app can open this file');
        } catch (_) {
          notifier.showToast('Could not open this file');
        }
      } else {
        notifier.showToast('This received file is no longer available on this device');
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlikTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FlikTokens.line),
      ),
      child: Row(
        children: [
          // Media Thumbnail or Icon Badge
          InkWell(
            onTap: openEntry,
            borderRadius: BorderRadius.circular(12),
            child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: FlikTokens.raised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FlikTokens.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasLocalFile && isImage
                ? Image.file(
                    File(entry.localPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: FlikTokens.muted)),
                  )
                : Center(
                    child: Icon(
                      isUrl
                          ? Icons.link
                          : isVideo
                              ? Icons.videocam
                              : isAudio
                                  ? Icons.music_note
                                  : isImage
                                      ? Icons.image
                                      : Icons.insert_drive_file,
                      color: isUrl
                          ? Colors.amber
                          : isAudio
                              ? Colors.purpleAccent
                              : isVideo
                                  ? Colors.redAccent
                                  : FlikTokens.accentSoft,
                      size: 26,
                    ),
                  ),
          ),
          ),
          const SizedBox(width: 12),

          // Details: Name, Sender, Time, Size
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.summaryName.isNotEmpty ? entry.summaryName : 'Received Item',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: FlikTokens.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'From ${entry.deviceName} • ${_formatTimestamp(entry.timestamp)}',
                  style: const TextStyle(fontSize: 11, color: FlikTokens.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  isUrl
                      ? 'Web Link'
                      : entry.totalBytes > 0
                          ? '${(entry.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                          : 'Received file',
                  style: const TextStyle(fontSize: 10, color: FlikTokens.accentSoft),
                ),
              ],
            ),
          ),

          // Actions: Open or Re-send
          IconButton(
            icon: Icon(isUrl ? Icons.open_in_browser : Icons.open_in_new, size: 20, color: FlikTokens.accentSoft),
            tooltip: isUrl ? 'Open Link' : 'Open File',
            onPressed: openEntry,
          ),
        ],
      ),
    );
  }

  String _mimeFor(String path) {
    final extension = path.split('.').last.toLowerCase();
    const mimeTypes = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'mkv': 'video/x-matroska',
      'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'wav': 'audio/wav', 'pdf': 'application/pdf',
      'txt': 'text/plain', 'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint', 'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'apk': 'application/vnd.android.package-archive', 'zip': 'application/zip',
    };
    return mimeTypes[extension] ?? '*/*';
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
