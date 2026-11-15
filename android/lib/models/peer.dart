// Represents a local peer device discovered on the Wi-Fi/Hotspot network.
class DiscoveredPeer {
  final String deviceId;
  final String deviceName;
  final String platform; // 'android' or 'windows'
  final String ip;
  final int port;
  double angle; // Relative angle on the radar arc (-60 to +60 degrees)
  bool isSelected;
  bool isLocked;
  bool isConnected;
  String? token;

  DiscoveredPeer({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.ip,
    required this.port,
    this.angle = 0.0,
    this.isSelected = false,
    this.isLocked = false,
    this.isConnected = false,
    this.token,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'ip': ip,
    'port': port,
    'token': token,
  };

  factory DiscoveredPeer.fromJson(Map<String, dynamic> json) => DiscoveredPeer(
    deviceId: json['deviceId'] as String,
    deviceName: json['deviceName'] as String,
    platform: json['platform'] as String,
    ip: json['ip'] as String? ?? '127.0.0.1',
    port: json['port'] as int? ?? 54321,
    token: json['token'] as String?,
  );
}
