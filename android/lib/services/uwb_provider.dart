// Abstract interface for Ultra-Wideband (UWB) high-precision spatial positioning.
abstract class UwbProvider {
  Future<bool> isAvailable();
  Future<void> startRanging();
  Future<void> stopRanging();
  Stream<UwbDevicePosition>? get positionStream;
}

class UwbDevicePosition {
  final String peerId;
  final double distanceMeters;
  final double azimuthDegrees;
  final double elevationDegrees;

  UwbDevicePosition({
    required this.peerId,
    required this.distanceMeters,
    required this.azimuthDegrees,
    required this.elevationDegrees,
  });
}

// Default safe fallback implementation when hardware UWB is not present.
class NoOpUwbProvider implements UwbProvider {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> startRanging() async {}

  @override
  Future<void> stopRanging() async {}

  @override
  Stream<UwbDevicePosition>? get positionStream => null;
}
