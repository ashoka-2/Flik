import 'dart:async';
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
// Preview subsequent photos layered behind, flick or tap Send to launch off-screen to PC.
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
  bool _isSending = false;
  double _lastFlickTrajX = 0.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _flyOffsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.0, -1.8), // Fly straight off the top edge
    ).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeInCubic));

    _flyOpacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _flyController, curve: const Interval(0.5, 1.0)));

    _flyRotationAnimation = Tween<double>(
      begin: 0.0,
      end: -0.08,
    ).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeIn));

    _initSensors();
    _initVideoIfNeeded();
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

  Future<void> _initVideoIfNeeded() async {
    _videoController?.dispose();
    _videoController = null;

    if (_currentIndex < widget.assets.length) {
      final currentAsset = widget.assets[_currentIndex];
      if (currentAsset.type == AssetType.video) {
        final file = await currentAsset.file;
        if (file != null && mounted) {
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
    setState(() => _isSending = true);

    final currentAsset = widget.assets[_currentIndex];
    final file = await currentAsset.file;
    if (file == null) {
      setState(() => _isSending = false);
      return;
    }

    final thumb = await currentAsset.thumbnailDataWithSize(const ThumbnailSize(240, 240));
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

    // Launch off-screen flight animation
    _flyController.forward();

    // Send item to connected PC
    final notifier = ref.read(flikAppProvider.notifier);
    notifier.sendItemsDirectly([item], trajectoryX: trajX);

    // Advance to next photo after flight finishes
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;

    _flyController.reset();
    _lastFlickTrajX = 0.0;

    if (_currentIndex + 1 < widget.assets.length) {
      setState(() {
        _currentIndex++;
        _isSending = false;
      });
      _initVideoIfNeeded();
    } else {
      // Reached end of deck
      Navigator.pop(context);
    }
  }

  void _nextPhoto() {
    if (_currentIndex + 1 < widget.assets.length) {
      setState(() => _currentIndex++);
      _initVideoIfNeeded();
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _initVideoIfNeeded();
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
                  const SizedBox(width: 48), // Balance leading back button
                ],
              ),
            ),

            // Card Deck Area with Swipe Detector
            Expanded(
              child: GestureDetector(
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

                        // Top Card with Hero, Flight Animation and Tilt
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
                        const Icon(Icons.arrow_upward, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _isSending ? 'Sending...' : 'Send',
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
        child: isTop && asset.type == AssetType.video && _videoController != null
            ? Stack(
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
              )
            : FlikThumbnailImage(
                asset: asset,
                size: const ThumbnailSize(900, 1200),
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}
