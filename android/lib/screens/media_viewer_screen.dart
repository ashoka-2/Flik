import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import '../models/transfer_item.dart';
import '../providers/flik_state.dart';
import '../services/sensor_service.dart';
import '../theme/tokens.dart';
import '../widgets/flik_thumbnail_image.dart';

// Stacked card deck media viewer matching the physical Flik experience:
// High-res rendering, physical tilt/flick trajectory, and sequential transfers.
class MediaViewerScreen extends ConsumerStatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;

  const MediaViewerScreen({
    super.key,
    required this.assets,
    required this.initialIndex,
  });

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late AnimationController _flyController;
  late Animation<Offset> _flyOffsetAnimation;
  late Animation<double> _flyOpacityAnimation;
  late Animation<double> _flyRotationAnimation;

  SensorService? _sensorService;
  VideoPlayerController? _videoController;
  File? _currentFile;
  bool _isSending = false;
  double _lastFlickTrajX = 0.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _flyOffsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.0, -1.8),
    ).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeInCubic));

    _flyOpacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _flyController, curve: const Interval(0.4, 1.0)));

    _flyRotationAnimation = Tween<double>(
      begin: 0.0,
      end: -0.06,
    ).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeIn));

    _initSensors();
    _loadCurrentMedia();
  }

  void _initSensors() {
    _sensorService = SensorService(
      onFlick: (trajX) {
        if (!_isSending && mounted) {
          _lastFlickTrajX = trajX;
          _triggerFlickSend();
        }
      },
    );
    _sensorService?.start();
  }

  Future<void> _loadCurrentMedia() async {
    _videoController?.dispose();
    _videoController = null;
    _currentFile = null;

    if (_currentIndex < widget.assets.length) {
      final currentAsset = widget.assets[_currentIndex];
      final file = await currentAsset.file;
      if (file != null && mounted) {
        setState(() => _currentFile = file);
        if (currentAsset.type == AssetType.video) {
          _videoController = VideoPlayerController.file(file);
          await _videoController!.initialize();
          if (mounted) setState(() {});
        }
      }
    }
  }

  @override
  void dispose() {
    _sensorService?.stop();
    _videoController?.dispose();
    _flyController.dispose();
    super.dispose();
  }

  Future<void> _triggerFlickSend() async {
    if (_isSending || _currentIndex >= widget.assets.length) return;

    final state = ref.read(flikAppProvider);
    if (state.peers.isEmpty) {
      ref.read(flikAppProvider.notifier).showToast('No device connected. Please pair with PC or phone first.');
      return;
    }

    setState(() => _isSending = true);

    final currentAsset = widget.assets[_currentIndex];
    final file = _currentFile ?? await currentAsset.file;
    if (file == null) {
      setState(() => _isSending = false);
      return;
    }

    final thumb = await currentAsset.thumbnailDataWithSize(const ThumbnailSize(360, 360));
    final item = TransferItem(
      id: currentAsset.id,
      name: currentAsset.title ?? 'Media_${currentAsset.id}',
      size: await file.length(),
      mime: currentAsset.mimeType ?? (currentAsset.type == AssetType.video ? 'video/mp4' : 'image/jpeg'),
      kind: currentAsset.type == AssetType.video ? 'video' : 'image',
      localPath: file.path,
      thumbnailBytes: thumb,
    );

    // Calculate dynamic trajectory from sensor tilt or horizontal flick impulse
    final trajX = _lastFlickTrajX != 0.0
        ? _lastFlickTrajX
        : (_sensorService?.currentTiltX ?? 0.0);

    // Start off-screen flight animation
    _flyController.forward();

    // Send item to connected PC and await completion
    final notifier = ref.read(flikAppProvider.notifier);
    await notifier.sendItemsDirectly([item], trajectoryX: trajX);

    if (!mounted) return;

    _flyController.reset();
    _lastFlickTrajX = 0.0;

    if (_currentIndex + 1 < widget.assets.length) {
      setState(() {
        _currentIndex++;
        _isSending = false;
      });
      _loadCurrentMedia();
    } else {
      // Reached end of deck
      Navigator.pop(context);
    }
  }

  String _getAimingLabel(double tilt) {
    if (tilt < -0.25) {
      return 'Aiming Left ◄';
    } else if (tilt > 0.25) {
      return 'Aiming Right ►';
    }
    return 'Aiming Center ▲';
  }

  void _nextPhoto() {
    if (_currentIndex + 1 < widget.assets.length && !_isSending) {
      setState(() => _currentIndex++);
      _loadCurrentMedia();
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0 && !_isSending) {
      setState(() => _currentIndex--);
      _loadCurrentMedia();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flikAppProvider);
    final targetDeviceName = state.lockedPeerId != null
        ? state.peers.where((p) => p.deviceId == state.lockedPeerId).firstOrNull?.deviceName ?? 'PC'
        : state.peers.firstOrNull?.deviceName ?? 'Windows PC';

    if (_currentIndex >= widget.assets.length) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final topAsset = widget.assets[_currentIndex];
    final secondAsset = _currentIndex + 1 < widget.assets.length ? widget.assets[_currentIndex + 1] : null;
    final thirdAsset = _currentIndex + 2 < widget.assets.length ? widget.assets[_currentIndex + 2] : null;

    final screenHeight = MediaQuery.of(context).size.height;
    final cardHeight = screenHeight * 0.58;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    '${_currentIndex + 1} of ${widget.assets.length}',
                    style: const TextStyle(
                      color: FlikTokens.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Card Deck Area with Gesture Detector
            Expanded(
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  // Swipe up flick gesture
                  if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
                    _triggerFlickSend();
                  }
                },
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -200) {
                      _nextPhoto();
                    } else if (details.primaryVelocity! > 200) {
                      _prevPhoto();
                    }
                  }
                },
                child: Center(
                  child: SizedBox(
                    height: cardHeight + 40,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Card 3 (deepest background card)
                        if (thirdAsset != null)
                          Transform.translate(
                            offset: const Offset(0, 30),
                            child: Transform.scale(
                              scale: 0.88,
                              child: Opacity(
                                opacity: 0.4,
                                child: _buildCard(thirdAsset, cardHeight),
                              ),
                            ),
                          ),

                        // Card 2 (middle background card)
                        if (secondAsset != null)
                          Transform.translate(
                            offset: const Offset(0, 16),
                            child: Transform.scale(
                              scale: 0.94,
                              child: Opacity(
                                opacity: 0.7,
                                child: _buildCard(secondAsset, cardHeight),
                              ),
                            ),
                          ),

                        // Top Card with Hero, Flight Animation and Full Resolution
                        AnimatedBuilder(
                          animation: _flyController,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(
                                _flyOffsetAnimation.value.dx * screenHeight,
                                _flyOffsetAnimation.value.dy * screenHeight,
                              ),
                              child: Transform.rotate(
                                angle: _flyRotationAnimation.value,
                                child: Opacity(
                                  opacity: _flyOpacityAnimation.value,
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: Hero(
                            tag: 'media_${topAsset.id}',
                            child: _buildCard(topAsset, cardHeight, isTop: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Action Area matching reference video
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live trajectory aiming pill
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: FlikTokens.surface,
                      borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                      border: Border.all(color: FlikTokens.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.screen_share, size: 14, color: FlikTokens.accentSoft),
                        const SizedBox(width: 6),
                        Text(
                          _getAimingLabel(_sensorService?.currentTiltX ?? 0.0),
                          style: const TextStyle(
                            color: FlikTokens.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Prominent Send Pill Button
                  ElevatedButton(
                    onPressed: _isSending ? null : _triggerFlickSend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlikTokens.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      elevation: 8,
                      shadowColor: FlikTokens.accent.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.arrow_upward, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _isSending ? 'Sending to PC...' : 'Send',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Tactile flick hint
                  Text(
                    'Give it a little flick!',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    'to $targetDeviceName',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(AssetEntity asset, double height, {bool isTop = false}) {
    final width = MediaQuery.of(context).size.width * 0.85;

    Widget mediaContent;
    if (isTop && asset.type == AssetType.video && _videoController != null) {
      mediaContent = Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
          IconButton(
            iconSize: 56,
            icon: Icon(
              _videoController!.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _videoController!.value.isPlaying
                    ? _videoController!.pause()
                    : _videoController!.play();
              });
            },
          ),
        ],
      );
    } else if (isTop && _currentFile != null) {
      // 100% full original resolution image
      mediaContent = Image.file(
        _currentFile!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => FlikThumbnailImage(
          asset: asset,
          size: const ThumbnailSize.square(400),
          fit: BoxFit.cover,
        ),
      );
    } else {
      // Crisp preview for background cards
      mediaContent = FlikThumbnailImage(
        asset: asset,
        size: const ThumbnailSize.square(400),
        fit: BoxFit.cover,
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FlikTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isTop ? FlikTokens.line : FlikTokens.line.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: mediaContent,
      ),
    );
  }
}
