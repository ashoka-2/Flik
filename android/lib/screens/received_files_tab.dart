import 'dart:io';
import 'package:flutter/material.dart';
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
                      return _buildReceivedCard(context, entry, notifier);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildReceivedCard(BuildContext context, TransferHistoryEntry entry, dynamic notifier) {
    final isUrl = entry.kind == 'url' || entry.kind == 'link' || entry.itemsCount == 0;
    final isVideo = entry.kind == 'video';
    final isAudio = entry.kind == 'audio';
    final isImage = entry.kind == 'image' || entry.kind == 'photo';
    final hasLocalFile = entry.localPath != null && File(entry.localPath!).existsSync();

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
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: FlikTokens.raised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FlikTokens.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasLocalFile && isImage
                ? Image.file(File(entry.localPath!), fit: BoxFit.cover)
                : Center(
                    child: Icon(
                      isUrl
                          ? Icons.link
                          : isVideo
                              ? Icons.videocam
                              : isAudio
                                  ? Icons.music_note
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
            onPressed: () async {
              if (isUrl) {
                final uri = Uri.tryParse(entry.summaryName);
                if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
              } else if (hasLocalFile) {
                notifier.showToast('File located at: ${entry.localPath}');
              }
            },
          ),
        ],
      ),
    );
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
