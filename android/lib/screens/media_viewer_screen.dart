import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import '../models/transfer_item.dart';
import '../theme/tokens.dart';

// Fullscreen viewer with InteractiveViewer for images and video_player for videos.
class MediaViewerScreen extends StatefulWidget {
  final AssetEntity asset;
  final void Function(TransferItem item) onStage;

  const MediaViewerScreen({super.key, required this.asset, required this.onStage});

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  File? _file;
  VideoPlayerController? _videoController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    final file = await widget.asset.file;
    if (file != null) {
      _file = file;
      if (widget.asset.type == AssetType.video) {
        _videoController = VideoPlayerController.file(file);
        await _videoController!.initialize();
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _stageAndClose() async {
    if (_file != null) {
      final thumb = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
      final item = TransferItem(
        id: widget.asset.id,
        name: widget.asset.title ?? 'Media_${widget.asset.id}',
        size: await _file!.length(),
        mime: widget.asset.mimeType ?? (widget.asset.type == AssetType.video ? 'video/mp4' : 'image/jpeg'),
        kind: widget.asset.type == AssetType.video ? 'video' : 'image',
        localPath: _file!.path,
        thumbnailBytes: thumb,
      );
      widget.onStage(item);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        title: Text(widget.asset.title ?? 'Viewer'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Center(
                  child: widget.asset.type == AssetType.video && _videoController != null
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_videoController!),
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
                          ),
                        )
                      : InteractiveViewer(
                          maxScale: 4.0,
                          child: _file != null ? Image.file(_file!) : const SizedBox(),
                        ),
                ),

                // "Stage to Flick" floating pill button
                Positioned(
                  bottom: 32,
                  left: 32,
                  right: 32,
                  child: ElevatedButton.icon(
                    onPressed: _stageAndClose,
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    label: const Text('Stage to Flick'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(FlikTokens.buttonHeightLarge),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
