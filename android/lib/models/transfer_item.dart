import 'dart:typed_data';

// Represents an individual item (file, image, video, link) staged or received.
class TransferItem {
  final String id;
  final String name;
  final int size; // In bytes
  final String mime;
  final String kind; // 'file', 'image', 'video'
  final String? localPath;
  final Uint8List? thumbnailBytes;
  final String? url;
  bool isSelected;

  TransferItem({
    required this.id,
    required this.name,
    required this.size,
    required this.mime,
    required this.kind,
    this.localPath,
    this.thumbnailBytes,
    this.url,
    this.isSelected = false,
  });

  Map<String, dynamic> toMetaItem() => {
    'name': name,
    'size': size,
    'mime': mime,
    'kind': kind,
  };
}
