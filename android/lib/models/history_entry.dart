// Represents a record of a sent or received transfer for the Library tab.
class TransferHistoryEntry {
  final String id;
  final String deviceName;
  final bool isOutbound; // true if sent, false if received
  final int itemsCount;
  final int totalBytes;
  final DateTime timestamp;
  final String summaryName;
  final String status; // 'completed', 'cancelled', 'failed'
  final String? localPath;
  final String? kind; // 'image', 'video', 'file'

  TransferHistoryEntry({
    required this.id,
    required this.deviceName,
    required this.isOutbound,
    required this.itemsCount,
    required this.totalBytes,
    required this.timestamp,
    required this.summaryName,
    required this.status,
    this.localPath,
    this.kind,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'deviceName': deviceName,
    'isOutbound': isOutbound,
    'itemsCount': itemsCount,
    'totalBytes': totalBytes,
    'timestamp': timestamp.toIso8601String(),
    'summaryName': summaryName,
    'status': status,
    'localPath': localPath,
    'kind': kind,
  };

  factory TransferHistoryEntry.fromJson(Map<String, dynamic> json) => TransferHistoryEntry(
    id: json['id'] as String,
    deviceName: json['deviceName'] as String,
    isOutbound: json['isOutbound'] as bool? ?? true,
    itemsCount: json['itemsCount'] as int? ?? 1,
    totalBytes: json['totalBytes'] as int? ?? 0,
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    summaryName: json['summaryName'] as String? ?? 'Transfer',
    status: json['status'] as String? ?? 'completed',
    localPath: json['localPath'] as String?,
    kind: json['kind'] as String?,
  );
}
