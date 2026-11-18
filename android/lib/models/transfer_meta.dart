import 'transfer_item.dart';

// Represents multipart upload metadata matching transfer-meta.schema.json.
class TransferMeta {
  final String transferId;
  final List<TransferItem> items;
  final double? trajectoryX;
  final double? trajectoryY;

  TransferMeta({
    required this.transferId,
    required this.items,
    this.trajectoryX,
    this.trajectoryY,
  });

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'items': items.map((e) => e.toMetaItem()).toList(),
    if (trajectoryX != null) 'trajectoryX': trajectoryX,
    if (trajectoryY != null) 'trajectoryY': trajectoryY,
  };

  factory TransferMeta.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final parsedItems = rawItems.map((e) {
      final map = e as Map<String, dynamic>;
      return TransferItem(
        id: map['name'] as String,
        name: map['name'] as String,
        size: (map['size'] as num?)?.toInt() ?? 0,
        mime: map['mime'] as String? ?? 'application/octet-stream',
        kind: map['kind'] as String? ?? 'file',
      );
    }).toList();

    return TransferMeta(
      transferId: json['transferId'] as String,
      items: parsedItems,
      trajectoryX: (json['trajectoryX'] as num?)?.toDouble(),
      trajectoryY: (json['trajectoryY'] as num?)?.toDouble(),
    );
  }
}
