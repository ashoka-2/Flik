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
// Categorized Albums view precisely matching mobile gallery (All, Camera, Favorites, Videos, Screenshots, More Albums),
// instant search filtering, multi-selection, and wrist-flick gesture sending.
class GalleryTab extends ConsumerStatefulWidget {
  final void Function(List<TransferItem> items)? onStageItems;

  const GalleryTab({super.key, this.onStageItems});

  @override
  ConsumerState<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends ConsumerState<GalleryTab> {
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _assets = [];
  final Set<String> _selectedAssetIds = {};

  final Map<String, int> _albumCounts = {};
  final Map<String, AssetEntity?> _albumCovers = {};

  // Top 5 primary albums matching user gallery reference
  AssetPathEntity? _albumAll;
  AssetPathEntity? _albumCamera;
  AssetPathEntity? _albumFavorites;
  AssetPathEntity? _albumVideos;
  AssetPathEntity? _albumScreenshots;
  List<AssetPathEntity> _moreAlbums = [];

  bool _isAlbumsView = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  static const int _pageSize = 80;
  bool _hasMore = true;
  bool _sortLatestFirst = true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final ScrollController _scrollController = ScrollController();
  SensorService? _sensorService;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadAlbums();

    // Listen to physical wrist flick gesture when multiple photos are selected
    int lastGalleryFlickTime = 0;
    _sensorService = SensorService(
      onFlick: (trajX) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_selectedAssetIds.isNotEmpty && (now - lastGalleryFlickTime > 1200) && mounted) {
          lastGalleryFlickTime = now;
          _sendSelectedDirectly(
            trajectoryX: trajX,
            trajectoryY: _sensorService?.currentTiltY,
          );
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
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      _loadMoreAssets();
    }
  }

  Future<void> _loadAlbums() async {
    setState(() => _isLoading = true);
    _albumCounts.clear();
    _albumCovers.clear();
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission.isAuth || permission.hasAccess) {
      // Configure filterOption so MediaStore orders newest items first (descending createDate)
      final filterOption = FilterOptionGroup(
        orders: [
          const OrderOption(
            type: OrderOptionType.createDate,
            asc: false,
          ),
        ],
      );

      // 1. Fetch common media (images + videos) with newest-first ordering
      final commonAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        filterOption: filterOption,
      );

      // 2. Fetch video-specific query to ensure all device videos are categorized
      final videoAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
        filterOption: filterOption,
      );

      if (commonAlbums.isNotEmpty) {
        // True system device-wide "All" album has isAll == true
        final allAlbum = commonAlbums.firstWhere((a) => a.isAll, orElse: () => commonAlbums.first);
        _albumAll = allAlbum;

        AssetPathEntity? foundCamera;
        AssetPathEntity? foundFavorites;
        AssetPathEntity? foundVideos;
        AssetPathEntity? foundScreenshots;
        int maxScreenshotCount = -1;
        int maxCameraCount = -1;
        final others = <AssetPathEntity>[];

        for (final album in commonAlbums) {
          // Never duplicate the All album or add it to other categories
          if (album.id == allAlbum.id || album.isAll) continue;

          final name = album.name.trim().toLowerCase();
          // Never treat secondary folders named 'all', 'recent', 'recents' as duplicate albums
          if (['all', 'recent', 'recents', 'all photos', 'recent photos'].contains(name)) {
            continue;
          }

          if (name == 'camera' || name == 'dcim' || name.contains('camera')) {
            final count = await album.assetCountAsync;
            if (count > maxCameraCount) {
              foundCamera = album;
              maxCameraCount = count;
            }
          } else if (name.contains('favorit') || name.contains('favourite')) {
            foundFavorites ??= album;
          } else if (name.contains('screenshot') || name.contains('screen_shot')) {
            final count = await album.assetCountAsync;
            // Always pick the screenshot album with the largest number of images!
            if (count > maxScreenshotCount) {
              foundScreenshots = album;
              maxScreenshotCount = count;
            }
          } else if (name.contains('video')) {
            foundVideos ??= album;
          } else {
            others.add(album);
          }
        }

        others.removeWhere((a) =>
            a.id == allAlbum.id ||
            a.isAll ||
            (foundVideos != null && a.id == foundVideos.id) ||
            ['all', 'recent', 'recents', 'all photos', 'recent photos'].contains(a.name.trim().toLowerCase()));

        // Guarantee dedicated full-device Videos album if available
        if (videoAlbums.isNotEmpty) {
          foundVideos = videoAlbums.firstWhere((album) => album.isAll, orElse: () => videoAlbums.first);
        }

        _albumCamera = foundCamera;
        _albumFavorites = foundFavorites;
        _albumVideos = foundVideos;
        _albumScreenshots = foundScreenshots;
        _moreAlbums = others;

        _selectedAlbum = _albumAll;
        _currentPage = 0;
        _hasMore = true;

        final firstBatch = await _selectedAlbum!.getAssetListPaged(
          page: 0,
          size: _pageSize,
        );
        _applySort(firstBatch);

        // Fetch counts and covers for album cards asynchronously
        _loadAlbumMetadata([
          if (_albumAll != null) _albumAll!,
          if (_albumCamera != null) _albumCamera!,
          if (_albumFavorites != null) _albumFavorites!,
          if (_albumVideos != null) _albumVideos!,
          if (_albumScreenshots != null) _albumScreenshots!,
          ..._moreAlbums,
        ]);

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
          final key = _albumKey(album);
          _albumCounts[key] = count;
          _albumCovers[key] = cover;
        });
      }
    }
  }

  String _albumKey(AssetPathEntity album) {
    if (identical(album, _albumAll)) return '__all_media__';
    if (identical(album, _albumVideos)) return '__all_videos__';
    return album.id;
  }

  void _applySort(List<AssetEntity> list) {
    if (_sortLatestFirst) {
      list.sort((a, b) {
        final timeA = a.modifiedDateTime.isAfter(a.createDateTime) ? a.modifiedDateTime : a.createDateTime;
        final timeB = b.modifiedDateTime.isAfter(b.createDateTime) ? b.modifiedDateTime : b.createDateTime;
        return timeB.compareTo(timeA);
      });
    } else {
      list.sort((a, b) {
        final timeA = a.modifiedDateTime.isAfter(a.createDateTime) ? a.modifiedDateTime : a.createDateTime;
        final timeB = b.modifiedDateTime.isAfter(b.createDateTime) ? b.modifiedDateTime : b.createDateTime;
        return timeA.compareTo(timeB);
      });
    }
  }

  void _toggleSort() {
    setState(() {
      _sortLatestFirst = !_sortLatestFirst;
      _applySort(_assets);
    });
  }

  Future<void> _reloadCurrentView() async {
    PhotoManager.clearFileCache();
    await _loadAlbums();
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

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

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

  Future<void> _sendSelectedDirectly({double? trajectoryX, double? trajectoryY}) async {
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
      await notifier.sendItemsDirectly(
        items,
        trajectoryX: trajectoryX,
        trajectoryY: trajectoryY,
      );
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
        // Top Search Bar & Navigation Control
        _buildTopHeader(),

        // Body: Either Albums Grid View or Photos Grid View
        Expanded(
          child: _isAlbumsView ? _buildAlbumsView() : _buildPhotosGrid(),
        ),

        // Bottom Multi-Selection Action Bar with Flick-to-Send Hint
        if (_selectedAssetIds.isNotEmpty) _buildSelectionActionBar(),
      ],
    );
  }

  Widget _buildTopHeader() {
    final isInsideSubAlbum = _selectedAlbum != null && !_selectedAlbum!.isAll && !_isAlbumsView;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search Bar matching the user's reference gallery
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: FlikTokens.raised,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: FlikTokens.line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.search, color: FlikTokens.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: FlikTokens.text, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Times, places, file name...',
                      hintStyle: TextStyle(color: FlikTokens.muted, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () => _searchController.clear(),
                    child: const Icon(Icons.close, color: FlikTokens.muted, size: 18),
                  )
                else
                  const Icon(Icons.more_vert, color: FlikTokens.muted, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Secondary Controls: Sub-album back button or Photos/Albums pill switch
          Row(
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
                    '${_formatAlbumName(_selectedAlbum!)} (${_albumCounts[_albumKey(_selectedAlbum!)] ?? _assets.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: FlikTokens.text),
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
                          if (_albumAll != null && _selectedAlbum != _albumAll) {
                            _switchAlbum(_albumAll!);
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

              // Sort Order Toggle (only in Photos view)
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
              const SizedBox(width: 6),
              InkWell(
                onTap: _reloadCurrentView,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: FlikTokens.raised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FlikTokens.line),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 13, color: FlikTokens.accentSoft),
                      SizedBox(width: 4),
                      Text('Reload', style: TextStyle(fontSize: 11, color: FlikTokens.text, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
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

  // Categorized Albums View precisely matching Image 3 (All, Camera, Favorites, Videos, Screenshots, More albums)
  Widget _buildAlbumsView() {
    // Collect top primary albums that exist
    final primaryAlbums = <AssetPathEntity>[
      if (_albumAll != null) _albumAll!,
      if (_albumCamera != null) _albumCamera!,
      if (_albumFavorites != null) _albumFavorites!,
      if (_albumVideos != null) _albumVideos!,
      if (_albumScreenshots != null) _albumScreenshots!,
    ];

    // Filter by search query if user typed anything
    final filteredPrimary = _searchQuery.isEmpty
        ? primaryAlbums
        : primaryAlbums.where((a) => _formatAlbumName(a).toLowerCase().contains(_searchQuery)).toList();

    final primaryIds = primaryAlbums.map((a) => a.id).toSet();
    final primaryNames = primaryAlbums.map((a) => _formatAlbumName(a).toLowerCase()).toSet();
    final uniqueOthers = _moreAlbums.where((a) {
      if (primaryIds.contains(a.id) || a.isAll) return false;
      final formatted = _formatAlbumName(a).toLowerCase();
      if (primaryNames.contains(formatted) || formatted == 'all' || formatted == 'all photos') return false;
      return true;
    }).toList();

    final filteredOthers = _searchQuery.isEmpty
        ? uniqueOthers
        : uniqueOthers.where((a) => a.name.toLowerCase().contains(_searchQuery)).toList();

    return RefreshIndicator(
      onRefresh: _reloadCurrentView,
      color: FlikTokens.accentSoft,
      backgroundColor: FlikTokens.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        children: [
        // Primary Top Albums (Row 1: All, Camera, Favorites | Row 2: Videos, Screenshots)
        if (filteredPrimary.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            itemCount: filteredPrimary.length,
            itemBuilder: (context, index) {
              return _buildAlbumCard(filteredPrimary[index]);
            },
          ),

        const SizedBox(height: 18),

        // "More albums" Section Header
        if (filteredOthers.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'More albums',
              style: TextStyle(
                color: FlikTokens.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            itemCount: filteredOthers.length,
            itemBuilder: (context, index) {
              return _buildAlbumCard(filteredOthers[index]);
            },
          ),
        ],
      ],
    ),
  );
}

  Widget _buildAlbumCard(AssetPathEntity album) {
    final key = _albumKey(album);
    final count = _albumCounts[key] ?? 0;
    final coverAsset = _albumCovers[key];
    final displayName = _formatAlbumName(album);

    return GestureDetector(
      onTap: () => _switchAlbum(album),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large Squarish Cover Thumbnail
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: FlikTokens.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: FlikTokens.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: coverAsset != null
                  ? FlikThumbnailImage(
                      asset: coverAsset,
                      size: const ThumbnailSize.square(260),
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
          // Item Count Formatted (e.g., 3,731 or 586)
          Text(
            _formatCount(count),
            style: const TextStyle(
              fontSize: 11,
              color: FlikTokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAlbumName(AssetPathEntity album) {
    if (identical(album, _albumAll)) return 'All photos';
    if (identical(album, _albumVideos)) return 'Videos';
    if (album.id == _albumCamera?.id) return 'Camera';
    if (album.id == _albumFavorites?.id) return 'Favorites';
    if (album.id == _albumScreenshots?.id) return 'Screenshots';
    if (album.isAll) return 'All photos';
    final name = album.name;
    final lower = name.toLowerCase();
    if (lower == 'camera' || lower == 'dcim') return 'Camera';
    if (lower.contains('favorit')) return 'Favorites';
    if (lower.contains('video')) return 'Videos';
    if (lower.contains('screenshot')) return 'Screenshots';
    return name;
  }

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    final str = count.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]},');
  }

  // Photos Grid
  Widget _buildPhotosGrid() {
    final displayedAssets = _searchQuery.isEmpty
        ? _assets
        : _assets.where((a) => (a.title ?? '').toLowerCase().contains(_searchQuery)).toList();

    if (displayedAssets.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'No media matching "$_searchQuery"' : 'No media items in this album',
          style: const TextStyle(color: FlikTokens.muted),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reloadCurrentView,
      color: FlikTokens.accentSoft,
      backgroundColor: FlikTokens.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 5 : 3;

          return GridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(6),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            cacheExtent: 600,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: displayedAssets.length + (_hasMore && _searchQuery.isEmpty ? 1 : 0),
            itemBuilder: (context, index) {
            if (index >= displayedAssets.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2, color: FlikTokens.accentSoft),
                ),
              );
            }

            final asset = displayedAssets[index];
            final isSelected = _selectedAssetIds.contains(asset.id);

            return RepaintBoundary(
              child: GestureDetector(
                onTap: () {
                  if (_selectedAssetIds.isNotEmpty) {
                    _toggleSelection(asset);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MediaViewerScreen(
                          assets: displayedAssets,
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
                        size: const ThumbnailSize.square(220),
                      ),
                    ),

                  // Video Duration Badge
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
            ),
          );
        },
      );
      },
    ),
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
