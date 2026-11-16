import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/transfer_item.dart';
import '../providers/flik_state.dart';
import '../services/sensor_service.dart';
import '../theme/tokens.dart';
import '../widgets/flik_thumbnail_image.dart';
import 'media_viewer_screen.dart';

// High-performance gallery browser supporting Chronological Photos view,
// Categorized Albums view matching phone gallery (Camera, Screenshots, Videos, More Albums),
// multi-selection, and wrist-flick gesture sending.
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

  final Map<String, int> _albumCounts = {};
  final Map<String, AssetEntity?> _albumCovers = {};

  bool _isAlbumsView = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  static const int _pageSize = 80;
  bool _hasMore = true;
  bool _sortLatestFirst = true;

  final ScrollController _scrollController = ScrollController();
  SensorService? _sensorService;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAlbums();

    // Listen to physical wrist flick gesture when multiple photos are selected
    _sensorService = SensorService(
      onFlick: (trajX) {
        if (_selectedAssetIds.isNotEmpty && mounted) {
          _sendSelectedDirectly(trajectoryX: trajX);
        }
      },
    );
    _sensorService?.start();
  }

  @override
  void dispose() {
    _sensorService?.stop();
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
            asc: false,
          ),
        ],
      );

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        filterOption: filterOption,
      );

      if (albums.isNotEmpty) {
        _albums = albums;
        _selectedAlbum = albums.first;
        _currentPage = 0;
        _hasMore = true;

        final firstBatch = await _selectedAlbum!.getAssetListPaged(
          page: 0,
          size: _pageSize,
        );
        _applySort(firstBatch);

        // Fetch counts and covers for the Albums grid asynchronously
        _loadAlbumMetadata(albums);

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

  Future<void> _loadAlbumMetadata(List<AssetPathEntity> albums) async {
    for (final album in albums) {
      final count = await album.assetCountAsync;
      final cover = (await album.getAssetListPaged(page: 0, size: 1)).firstOrNull;
      if (mounted) {
        setState(() {
          _albumCounts[album.id] = count;
          _albumCovers[album.id] = cover;
        });
      }
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
    setState(() {
      _selectedAlbum = album;
      _isAlbumsView = false;
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

  Future<void> _sendSelectedDirectly({double? trajectoryX}) async {
    final notifier = ref.read(flikAppProvider.notifier);
    final selectedAssets = _assets.where((a) => _selectedAssetIds.contains(a.id)).toList();
    if (selectedAssets.isEmpty) return;

    notifier.showToast('Streaming ${selectedAssets.length} file(s) to PC...');
    final items = <TransferItem>[];

    for (final asset in selectedAssets) {
      final file = await asset.file;
      if (file != null && await file.exists()) {
        final thumb = await asset.thumbnailDataWithSize(const ThumbnailSize(240, 240));
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
      await notifier.sendItemsDirectly(items, trajectoryX: trajectoryX);
    }
  }

  void _stageSelected() async {
    final notifier = ref.read(flikAppProvider.notifier);
    final selectedAssets = _assets.where((a) => _selectedAssetIds.contains(a.id)).toList();
    if (selectedAssets.isEmpty) return;

    final items = <TransferItem>[];
    for (final asset in selectedAssets) {
      final file = await asset.file;
      if (file != null) {
        items.add(
          TransferItem(
            id: asset.id,
            name: asset.title ?? 'Media_${asset.id}',
            size: await file.length(),
            mime: asset.mimeType ?? (asset.type == AssetType.video ? 'video/mp4' : 'image/jpeg'),
            kind: asset.type == AssetType.video ? 'video' : 'image',
            localPath: file.path,
          ),
        );
      }
    }

    if (items.isNotEmpty) {
      setState(() => _selectedAssetIds.clear());
      notifier.stageItems(items);
      notifier.showToast('Staged ${items.length} item(s). Flick to send!');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: FlikTokens.accentSoft));
    }

    return Column(
      children: [
        // Navigation Bar: Toggle Photos vs Albums, or show Back button if inside an Album
        _buildTopNavigation(),

        // Body: Either Albums Grid View or Photos Grid View
        Expanded(
          child: _isAlbumsView ? _buildAlbumsView() : _buildPhotosGrid(),
        ),

        // Bottom Multi-Selection Action Bar with Flick-to-Send Hint
        if (_selectedAssetIds.isNotEmpty) _buildSelectionActionBar(),
      ],
    );
  }

  Widget _buildTopNavigation() {
    final isInsideSubAlbum = _selectedAlbum != null && !_selectedAlbum!.isAll && !_isAlbumsView;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Row(
        children: [
          if (isInsideSubAlbum) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back, color: FlikTokens.text, size: 20),
              onPressed: () => setState(() => _isAlbumsView = true),
              tooltip: 'Back to Albums',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${_selectedAlbum?.name ?? "Album"} (${_assets.length})',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: FlikTokens.text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            // View Mode Pill Switch: Photos / Albums
            Container(
              decoration: BoxDecoration(
                color: FlikTokens.raised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: FlikTokens.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSegmentButton('Photos', !_isAlbumsView, () {
                    if (_isAlbumsView) {
                      if (_albums.isNotEmpty && _selectedAlbum != _albums.first) {
                        _switchAlbum(_albums.first);
                      } else {
                        setState(() => _isAlbumsView = false);
                      }
                    }
                  }),
                  _buildSegmentButton('Albums', _isAlbumsView, () {
                    setState(() => _isAlbumsView = true);
                  }),
                ],
              ),
            ),
            const Spacer(),
          ],

          // Sort Order Toggle (only relevant in photo grid)
          if (!_isAlbumsView)
            InkWell(
              onTap: _toggleSort,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      size: 13,
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
    );
  }

  Widget _buildSegmentButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? FlikTokens.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : FlikTokens.muted,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Beautiful Albums View matching Image 3 with Top Categories and "More albums"
  Widget _buildAlbumsView() {
    // Categorize albums into top main and others
    final mainAlbums = <AssetPathEntity>[];
    final otherAlbums = <AssetPathEntity>[];

    for (final album in _albums) {
      final name = album.name.toLowerCase();
      if (album.isAll || name == 'recent' || name.contains('camera') || name.contains('video') || name.contains('screenshot') || name.contains('favorite')) {
        mainAlbums.add(album);
      } else {
        otherAlbums.add(album);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        // Main Albums Grid (All, Camera, Screenshots, Videos, etc.)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            childAspectRatio: 0.78,
          ),
          itemCount: mainAlbums.length,
          itemBuilder: (context, index) {
            return _buildAlbumCard(mainAlbums[index]);
          },
        ),

        const SizedBox(height: 20),

        // "More albums" Section Header
        if (otherAlbums.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'More albums',
              style: TextStyle(
                color: FlikTokens.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            itemCount: otherAlbums.length,
            itemBuilder: (context, index) {
              return _buildAlbumCard(otherAlbums[index]);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildAlbumCard(AssetPathEntity album) {
    final count = _albumCounts[album.id] ?? 0;
    final coverAsset = _albumCovers[album.id];
    final displayName = album.isAll ? 'All' : album.name;

    return GestureDetector(
      onTap: () => _switchAlbum(album),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album Thumbnail Cover
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: FlikTokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: FlikTokens.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: coverAsset != null
                  ? FlikThumbnailImage(
                      asset: coverAsset,
                      size: const ThumbnailSize.square(240),
                      fit: BoxFit.cover,
                    )
                  : const Center(
                      child: Icon(Icons.photo_album_outlined, size: 28, color: FlikTokens.muted),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          // Album Title
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FlikTokens.text,
            ),
          ),
          // Count
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 11,
              color: FlikTokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  // Photos Grid
  Widget _buildPhotosGrid() {
    if (_assets.isEmpty) {
      return const Center(
        child: Text('No media items in this album', style: TextStyle(color: FlikTokens.muted)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 5 : 3;

        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: _assets.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _assets.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2, color: FlikTokens.accentSoft),
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
                  // Single tap opens Apple-style MediaViewer with Hero animation and flick send
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'media_${asset.id}',
                    child: FlikThumbnailImage(
                      asset: asset,
                      size: const ThumbnailSize.square(240),
                    ),
                  ),

                  // Video Badge
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
                            const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              _formatDuration(asset.duration),
                              style: const TextStyle(fontSize: 9, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Selection Overlay Checkmark
                  if (isSelected)
                    Container(
                      color: FlikTokens.accent.withOpacity(0.35),
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: FlikTokens.accent,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.check, size: 16, color: Colors.white),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSelectionActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: FlikTokens.surface,
        border: const Border(top: BorderSide(color: FlikTokens.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_selectedAssetIds.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: FlikTokens.text),
                ),
                const Text(
                  'Flick phone or tap Send',
                  style: TextStyle(fontSize: 11, color: FlikTokens.accentSoft),
                ),
              ],
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: () => setState(() => _selectedAssetIds.clear()),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: FlikTokens.line),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 12, color: FlikTokens.muted)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _stageSelected,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: FlikTokens.line),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Stage', style: TextStyle(fontSize: 12, color: FlikTokens.text)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _sendSelectedDirectly,
              icon: const Icon(Icons.arrow_upward, size: 16),
              label: const Text('Send'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlikTokens.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
