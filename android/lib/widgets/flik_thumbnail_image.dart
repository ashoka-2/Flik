import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../theme/tokens.dart';

// High-speed memory-optimized thumbnail widget for silky smooth 120fps scrolling on both low-end and flagship devices.
class FlikThumbnailImage extends StatefulWidget {
  final AssetEntity asset;
  final ThumbnailSize size;
  final BoxFit fit;

  const FlikThumbnailImage({
    super.key,
    required this.asset,
    this.size = const ThumbnailSize.square(220),
    this.fit = BoxFit.cover,
  });

  static void clearCache() {
    _FlikThumbnailImageState._memoryCache.clear();
  }

  @override
  State<FlikThumbnailImage> createState() => _FlikThumbnailImageState();
}

class _FlikThumbnailImageState extends State<FlikThumbnailImage> {
  // Static bounded memory cache for decoded thumbnail bytes
  static final Map<String, Uint8List> _memoryCache = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FlikThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _load();
    }
  }

  void _load() {
    final cached = _memoryCache[widget.asset.id];
    if (cached != null) {
      _bytes = cached;
      return;
    }

    widget.asset.thumbnailDataWithSize(widget.size).then((data) {
      if (data != null) {
        // Prevent unbounded cache growth on low-end devices
        if (_memoryCache.length > 250) {
          _memoryCache.remove(_memoryCache.keys.first);
        }
        _memoryCache[widget.asset.id] = data;
        if (mounted) {
          setState(() => _bytes = data);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        cacheWidth: 220,
        cacheHeight: 220,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: child,
          );
        },
      );
    }

    return Container(
      color: FlikTokens.raised,
      child: const Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: FlikTokens.line),
        ),
      ),
    );
  }
}
