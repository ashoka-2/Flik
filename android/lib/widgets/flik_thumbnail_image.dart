import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../theme/tokens.dart';

// High-speed in-memory cached thumbnail widget for ultra-smooth 120fps gallery scrolling.
class FlikThumbnailImage extends StatefulWidget {
  final AssetEntity asset;
  final ThumbnailSize size;
  final BoxFit fit;

  const FlikThumbnailImage({
    super.key,
    required this.asset,
    this.size = const ThumbnailSize.square(360),
    this.fit = BoxFit.cover,
  });

  @override
  State<FlikThumbnailImage> createState() => _FlikThumbnailImageState();
}

class _FlikThumbnailImageState extends State<FlikThumbnailImage> {
  // Static LRU-like memory cache for decoded thumbnail bytes
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
        // Prevent unbounded cache growth
        if (_memoryCache.length > 500) {
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
        gaplessPlayback: true,
      );
    }

    return Container(
      color: FlikTokens.raised,
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: FlikTokens.line),
        ),
      ),
    );
  }
}
