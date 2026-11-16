import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/transfer_item.dart';
import '../providers/flik_state.dart';
import '../theme/tokens.dart';
import '../widgets/flik_thumbnail_image.dart';
import 'media_viewer_screen.dart';

// High-performance gallery browser with crisp thumbnails, album filtering, sorting, and multi-select.
class GalleryTab extends ConsumerStatefulWidget {
  final void Function(List<TransferItem> items)? onStageItems;

  const GalleryTab({super.key, this.onStageItems});

  @override
  ConsumerState<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends ConsumerState<GalleryTab> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _assets = [];
  final Set<String> _selectedAssetIds = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  static const int _pageSize = 80;
  bool _hasMore = true;
  bool _sortLatestFirst = true;
  final RequestType _mediaFilter = RequestType.common;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAlbums();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      _loadMoreAssets();
    }
  }

  Future<void> _loadAlbums() async {
    setState(() => _isLoading = true);
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission.isAuth || permission.hasAccess) {
      final filterOption = FilterOptionGroup(
        orders: [
          const OrderOption(
            type: OrderOptionType.createDate,
            asc: false, // DESCENDING: Newest photos, screenshots & WhatsApp first!
          ),
        ],
      );

      final albums = await PhotoManager.getAssetPathList(
        type: _mediaFilter,
        hasAll: true,
        filterOption: filterOption,
      );

      if (albums.isNotEmpty) {
        _albums = albums;
        // Always select the "All Photos" album by default
        _selectedAlbum = albums.first;
        _currentPage = 0;
        _hasMore = true;

        final firstBatch = await _selectedAlbum!.getAssetListPaged(
          page: 0,
          size: _pageSize,
        );

        _applySort(firstBatch);

        if (mounted) {
          setState(() {
            _assets = firstBatch;
            _isLoading = false;
            _hasMore = firstBatch.length >= _pageSize;
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _applySort(List<AssetEntity> list) {
    if (_sortLatestFirst) {
      list.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    } else {
      list.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
    }
  }

  void _toggleSort() {
    setState(() {
      _sortLatestFirst = !_sortLatestFirst;
      _applySort(_assets);
    });
  }

  Future<void> _switchAlbum(AssetPathEntity album) async {
    if (_selectedAlbum?.id == album.id) return;
    setState(() {
      _selectedAlbum = album;
      _isLoading = true;
      _assets = [];
      _currentPage = 0;
      _hasMore = true;
      _selectedAssetIds.clear();
    });

    final items = await album.getAssetListPaged(page: 0, size: _pageSize);
    _applySort(items);

    if (mounted) {
      setState(() {
        _assets = items;
        _isLoading = false;
        _hasMore = items.length >= _pageSize;
      });
    }
  }

  Future<void> _loadMoreAssets() async {
    if (_isLoadingMore || !_hasMore || _selectedAlbum == null) return;
    _isLoadingMore = true;

    final nextPage = _currentPage + 1;
    final newItems = await _selectedAlbum!.getAssetListPaged(
      page: nextPage,
      size: _pageSize,
    );

    _applySort(newItems);

    if (mounted) {
      setState(() {
        _currentPage = nextPage;
        _assets.addAll(newItems);
        _hasMore = newItems.length >= _pageSize;
        _isLoadingMore = false;
      });
    }
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

  Future<void> _sendSelectedDirectly() async {
    final notifier = ref.read(flikAppProvider.notifier);
    final selectedAssets = _assets.where((a) => _selectedAssetIds.contains(a.id)).toList();
    if (selectedAssets.isEmpty) return;

    notifier.showToast('Preparing ${selectedAssets.length} file(s)...');
    final items = <TransferItem>[];

    for (final asset in selectedAssets) {
      final file = await asset.file;
      if (file != null) {
        final thumb = await asset.thumbnailDataWithSize(const ThumbnailSize(360, 360));
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
      setState(() => _selectedAssetIds.clear());
      await notifier.sendItemsDirectly(items);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: FlikTokens.accentSoft));
    }

    if (_assets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library_outlined, size: 48, color: FlikTokens.muted),
            const SizedBox(height: 12),
            const Text('No photos or videos found', style: TextStyle(color: FlikTokens.muted)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadAlbums,
              child: const Text('Refresh / Permissions'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Controls bar: Album Selector & Sort Toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              // Horizontal album chips
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _albums.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final album = _albums[index];
                      final isSelected = _selectedAlbum?.id == album.id;
                      final displayName = album.isAll || album.name.isEmpty || album.name.toLowerCase() == 'recent'
                          ? 'All Photos'
                          : album.name;

                      return ChoiceChip(
                        label: Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? Colors.white : FlikTokens.muted,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: FlikTokens.accent,
                        backgroundColor: FlikTokens.raised,
                        side: BorderSide(
                          color: isSelected ? FlikTokens.accent : FlikTokens.line,
                        ),
                        onSelected: (_) => _switchAlbum(album),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Sort order toggle button
              InkWell(
                onTap: _toggleSort,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: FlikTokens.raised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FlikTokens.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _sortLatestFirst ? Icons.arrow_downward : Icons.arrow_upward,
                        size: 14,
                        color: FlikTokens.accentSoft,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _sortLatestFirst ? 'Newest' : 'Oldest',
                        style: const TextStyle(fontSize: 11, color: FlikTokens.text, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Grid of images
        Expanded(
          child: Stack(
            children: [
              GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: _assets.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _assets.length) {
                    return const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

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
                              assets: _assets,
                              initialIndex: index,
                            ),
                          ),
                        );
                      }
                    },
                    onLongPress: () => _toggleSelection(asset),
                    child: Hero(
                      tag: 'media_${asset.id}',
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: FlikThumbnailImage(
                              asset: asset,
                              size: const ThumbnailSize.square(360),
                              fit: BoxFit.cover,
                            ),
                          ),

                          // Video duration badge
                          if (asset.type == AssetType.video)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.play_arrow, size: 10, color: Colors.white),
                                    const SizedBox(width: 2),
                                    Text(
                                      _formatDuration(asset.duration),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Selection checkbox indicator
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 22,
                              height: 22,
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
                    ),
                  );
                },
              ),

              // Bottom Send Selected Button
              if (_selectedAssetIds.isNotEmpty)
                Positioned(
                  bottom: 16,
                  left: 24,
                  right: 24,
                  child: ElevatedButton.icon(
                    onPressed: _sendSelectedDirectly,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    label: Text('Send Selected (${_selectedAssetIds.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlikTokens.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                      ),
                    ),
                  ),
                ),
            ],
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
