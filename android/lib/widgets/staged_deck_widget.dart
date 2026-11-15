import 'package:flutter/material.dart';
import '../models/transfer_item.dart';
import '../theme/tokens.dart';

// Displays staged items as a tactile stacked deck with swipe flick gesture and reset button.
class StagedDeckWidget extends StatefulWidget {
  final List<TransferItem> items;
  final bool isSending;
  final double sendProgress;
  final VoidCallback onClear;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const StagedDeckWidget({
    super.key,
    required this.items,
    required this.isSending,
    required this.sendProgress,
    required this.onClear,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<StagedDeckWidget> createState() => _StagedDeckWidgetState();
}

class _StagedDeckWidgetState extends State<StagedDeckWidget> with SingleTickerProviderStateMixin {
  double _dragOffsetY = 0.0;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Container(
        height: 140,
        alignment: Alignment.center,
        child: const Text(
          'Select photos, files, or links to stage',
          style: TextStyle(color: FlikTokens.muted, fontSize: 14),
        ),
      );
    }

    final topItem = widget.items.last;
    final totalBytes = widget.items.fold(0, (sum, it) => sum + it.size);
    final sizeMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Swipable Deck Card
        GestureDetector(
          onVerticalDragUpdate: (details) {
            if (widget.isSending) return;
            setState(() {
              _dragOffsetY += details.delta.dy;
              if (_dragOffsetY > 0) _dragOffsetY = 0; // Only swipe upward
            });
          },
          onVerticalDragEnd: (details) {
            if (_dragOffsetY < -80 || (details.primaryVelocity ?? 0) < -400) {
              // Trigger flick launch
              widget.onSend();
            }
            setState(() {
              _dragOffsetY = 0.0;
            });
          },
          child: Transform.translate(
            offset: Offset(0, _dragOffsetY),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Visual under-cards for depth if 2+ items
                if (widget.items.length > 1)
                  Positioned(
                    top: -6,
                    child: Container(
                      width: 260,
                      height: 80,
                      decoration: BoxDecoration(
                        color: FlikTokens.raised,
                        borderRadius: BorderRadius.circular(FlikTokens.radiusGroup),
                        border: Border.all(color: FlikTokens.line),
                      ),
                    ),
                  ),

                // Main card surface
                Container(
                  width: 280,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FlikTokens.surface,
                    borderRadius: BorderRadius.circular(FlikTokens.radiusGroup),
                    border: Border.all(color: FlikTokens.line),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: FlikTokens.raised,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          topItem.kind == 'image'
                              ? Icons.image
                              : (topItem.kind == 'video' ? Icons.videocam : Icons.insert_drive_file),
                          color: FlikTokens.accentSoft,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              topItem.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: FlikTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.items.length} items · $sizeMb MB',
                              style: const TextStyle(
                                fontSize: 12,
                                color: FlikTokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Count badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: FlikTokens.accent,
                          borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                        ),
                        child: Text(
                          '${widget.items.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Action bar: Flick button, Reset "Put papers back", or Cancel during send
        if (widget.isSending) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: LinearProgressIndicator(
              value: widget.sendProgress > 0 ? widget.sendProgress : null,
              backgroundColor: FlikTokens.raised,
              valueColor: const AlwaysStoppedAnimation<Color>(FlikTokens.accent),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: widget.onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: FlikTokens.danger,
              side: const BorderSide(color: FlikTokens.danger),
            ),
            child: const Text('Cancel Transfer'),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: widget.onClear,
                style: TextButton.styleFrom(foregroundColor: FlikTokens.muted),
                child: const Text('Put papers back'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: widget.onSend,
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: const Text('Flick to Send'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
