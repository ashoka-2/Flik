import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/transfer_item.dart';
import '../theme/tokens.dart';
import 'media_viewer_screen.dart';

// Gallery browser tab with multi-select, duration badges, and "Flick Selected" action.
class GalleryTab extends StatefulWidget {
  final void Function(List<TransferItem> items) onStageItems;

  const GalleryTab({super.key, required this.onStageItems});

  @override
  State<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<GalleryTab> {
  List<AssetEntity> _assets = [];
  final Set<String> _selectedAssetIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission.isAuth || permission.hasAccess) {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (albums.isNotEmpty) {
        final recentAlbum = albums.first;
        final list = await recentAlbum.getAssetListPaged(page: 0, size: 80);
        setState(() {
          _assets = list;
          _isLoading = false;
        });
        return;
      }
    }
    setState(() => _isLoading = false);
  }

  void _toggleSelection(AssetEntity asset) {
    setState(() {
      if (_selectedAssetIds.contains(asset.id)) {
        _selectedAssetIds.remove(asset.id);
      } else {
        _selectedAssetIds.add(asset.id);
      }
    });
  }

  Future<void> _stageSelected() async {
    final selectedAssets = _assets.where((a) => _selectedAssetIds.contains(a.id)).toList();
    final items = <TransferItem>[];

    for (final asset in selectedAssets) {
      final file = await asset.file;
      if (file != null) {
        final thumb = await asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
        items.add(
          TransferItem(
            id: asset.id,
            name: asset.title ?? 'Media_${asset.id}',
            size: await file.length(),
            mime: asset.mimeType ?? (asset.type == AssetType.video ? 'video/mp4' : 'image/jpeg'),
            kind: asset.type == AssetType.video ? 'video' : 'image',
            localPath: file.path,
            thumbnailBytes: thumb,
          ),
        );
      }
    }

    if (items.isNotEmpty) {
      widget.onStageItems(items);
      setState(() => _selectedAssetIds.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_assets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library_outlined, size: 48, color: FlikTokens.muted),
            const SizedBox(height: 12),
            const Text('No photos or videos found', style: TextStyle(color: FlikTokens.muted)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadMedia, child: const Text('Grant Access')),
          ],
        ),
      );
    }

    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _assets.length,
          itemBuilder: (context, index) {
            final asset = _assets[index];
            final isSelected = _selectedAssetIds.contains(asset.id);

            return GestureDetector(
              onTap: () {
                if (_selectedAssetIds.isNotEmpty) {
                  _toggleSelection(asset);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MediaViewerScreen(
                        asset: asset,
                        onStage: (item) => widget.onStageItems([item]),
                      ),
                    ),
                  );
                }
              },
              onLongPress: () => _toggleSelection(asset),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FutureBuilder(
                      future: asset.thumbnailDataWithSize(const ThumbnailSize(240, 240)),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.memory(snapshot.data!, fit: BoxFit.cover);
                        }
                        return Container(color: FlikTokens.raised);
                      },
                    ),
                  ),

                  // Duration badge for video
                  if (asset.type == AssetType.video)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                        ),
                        child: Text(
                          _formatDuration(asset.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),

                  // Selection checkbox indicator
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isSelected ? FlikTokens.accent : Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // Bottom "Flick Selected" bar
        if (_selectedAssetIds.isNotEmpty)
          Positioned(
            bottom: 16,
            left: 24,
            right: 24,
            child: ElevatedButton.icon(
              onPressed: _stageSelected,
              icon: const Icon(Icons.touch_app, size: 18),
              label: Text('Flick Selected (${_selectedAssetIds.length})'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(FlikTokens.buttonHeightLarge),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
