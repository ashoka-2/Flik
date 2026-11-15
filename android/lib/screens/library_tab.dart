import 'package:flutter/material.dart';
import '../models/history_entry.dart';
import '../services/storage_service.dart';
import '../theme/tokens.dart';

// Library tab showing persistent history of sent and received transfers with Re-send action.
class LibraryTab extends StatefulWidget {
  final StorageService storage;
  final void Function(String message) onToast;

  const LibraryTab({super.key, required this.storage, required this.onToast});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  List<TransferHistoryEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _history = widget.storage.getHistory();
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

    return ListView.separated(
      padding: const EdgeInsets.all(FlikTokens.screenMargin),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = _history[index];
        final sizeMb = (entry.totalBytes / (1024 * 1024)).toStringAsFixed(1);
        final dateStr = '${entry.timestamp.hour}:${entry.timestamp.minute.toString().padLeft(2, '0')}';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FlikTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FlikTokens.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: FlikTokens.raised,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  entry.isOutbound ? Icons.arrow_upward : Icons.arrow_downward,
                  color: entry.isOutbound ? FlikTokens.accentSoft : Colors.greenAccent,
                  size: 20,
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
                    const SizedBox(height: 2),
                    Text(
                      '${entry.isOutbound ? "Sent to" : "From"} ${entry.deviceName} · $sizeMb MB · $dateStr',
                      style: const TextStyle(fontSize: 12, color: FlikTokens.muted),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () {
                  widget.onToast('Item staged for re-send');
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(60, 32),
                ),
                child: const Text('Re-send', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }
}
