import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/history_entry.dart';
import '../models/transfer_item.dart';
import '../providers/flik_state.dart';
import '../services/storage_service.dart';
import '../theme/tokens.dart';

// Library tab showing persistent history of sent and received transfers with real thumbnails and working Re-send.
class LibraryTab extends ConsumerStatefulWidget {
  final StorageService storage;
  final void Function(String message) onToast;

  const LibraryTab({super.key, required this.storage, required this.onToast});

  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab> {
  List<TransferHistoryEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    setState(() {
      _history = widget.storage.getHistory();
    });
  }

  void _resendItem(TransferHistoryEntry entry) {
    if (entry.localPath == null || !File(entry.localPath!).existsSync()) {
      widget.onToast('Original file not found on device.');
      return;
    }

    final file = File(entry.localPath!);
    final fileName = entry.summaryName;
    final ext = fileName.split('.').last.toLowerCase();
    final isImg = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'].contains(ext);
    final isVid = ['mp4', 'mkv', 'mov', 'avi', 'webm', '3gp'].contains(ext);
    final kind = isImg ? 'image' : (isVid ? 'video' : 'file');
    final mime = isImg ? 'image/$ext' : (isVid ? 'video/$ext' : 'application/octet-stream');

    final item = TransferItem(
      id: const Uuid().v4(),
      name: fileName,
      size: entry.totalBytes > 0 ? entry.totalBytes : file.lengthSync(),
      mime: mime,
      kind: kind,
      localPath: entry.localPath!,
    );

    final notifier = ref.read(flikAppProvider.notifier);
    notifier.stageItems([item]);
    widget.onToast('Staged "${entry.summaryName}" for re-send. Flick to send!');
  }

  @override
  Widget build(BuildContext context) {
    if (_history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: FlikTokens.muted),
            SizedBox(height: 12),
            Text('No transfers yet', style: TextStyle(color: FlikTokens.muted, fontSize: 14)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _loadHistory(),
      color: FlikTokens.accentSoft,
      backgroundColor: FlikTokens.surface,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(FlikTokens.screenMargin),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
        final entry = _history[index];
        final sizeMb = (entry.totalBytes / (1024 * 1024)).toStringAsFixed(1);
        final dateStr = '${entry.timestamp.hour}:${entry.timestamp.minute.toString().padLeft(2, '0')}';
        final hasValidFile = entry.localPath != null && File(entry.localPath!).existsSync();
        final isImage = entry.kind == 'image' || entry.summaryName.toLowerCase().endsWith('.jpg') || entry.summaryName.toLowerCase().endsWith('.png') || entry.summaryName.toLowerCase().endsWith('.webp');

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FlikTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FlikTokens.line),
          ),
          child: Row(
            children: [
              // Image or Video Thumbnail / Fallback Direction Icon
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: hasValidFile && isImage
                      ? Image.file(
                          File(entry.localPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildFallbackIcon(entry),
                        )
                      : _buildFallbackIcon(entry),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.summaryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: FlikTokens.text),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.isOutbound ? "Sent to" : "From"} ${entry.deviceName} · $sizeMb MB · $dateStr',
                      style: const TextStyle(fontSize: 12, color: FlikTokens.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _resendItem(entry),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(60, 32),
                  side: const BorderSide(color: FlikTokens.line),
                ),
                child: const Text('Re-send', style: TextStyle(fontSize: 12, color: FlikTokens.accentSoft)),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  Widget _buildFallbackIcon(TransferHistoryEntry entry) {
    return Container(
      color: FlikTokens.raised,
      child: Center(
        child: Icon(
          entry.isOutbound ? Icons.arrow_upward : Icons.arrow_downward,
          color: entry.isOutbound ? FlikTokens.accentSoft : Colors.greenAccent,
          size: 20,
        ),
      ),
    );
  }
}
