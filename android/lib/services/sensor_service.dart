import 'dart:async';
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

// Provides hardware sensor integration: wrist flick gesture detection, continuous tilt, and compass heading.
class SensorService {
  // Flick sensitivity thresholds
  static const double flickThreshold = 16.0; // m/s^2 user acceleration
  static const int cooldownMs = 800; // 800ms cooldown to avoid double trigger

  StreamSubscription? _userAccelSub;
  StreamSubscription? _rawAccelSub;
  StreamSubscription? _compassSub;
  int _lastFlickTime = 0;

  // Real-time horizontal tilt (-1.0 left to +1.0 right)
  double currentTiltX = 0.0;

  final void Function(double trajectoryX) onFlick;
  final void Function(double headingDegrees)? onHeadingChanged;

  SensorService({
    required this.onFlick,
    this.onHeadingChanged,
  });

  // Starts sensor listeners with error handling and silent fallback if sensors are absent
  void start() {
    try {
      // Continuous device tilt (gravity component)
      _rawAccelSub = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          // In portrait: tilt left produces negative x, tilt right produces positive x
          currentTiltX = (-event.x / 6.0).clamp(-1.0, 1.0);
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}

    try {
      // Dynamic flick detection (user-initiated jerk / impulse)
      _userAccelSub = userAccelerometerEventStream().listen(
        (UserAccelerometerEvent event) {
          final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
          final now = DateTime.now().millisecondsSinceEpoch;

          if (magnitude > flickThreshold && (now - _lastFlickTime) > cooldownMs) {
            _lastFlickTime = now;
            // Trajectory combines dynamic jerk and steady tilt
            final dynamicX = (-event.x / 8.0);
            final trajectory = (dynamicX + currentTiltX).clamp(-1.0, 1.0);
            onFlick(trajectory);
          }
        },
        onError: (_) {
          // Hardware sensor missing or unavailable: silent fallback
        },
        cancelOnError: false,
      );
    } catch (_) {}

    try {
      if (onHeadingChanged != null && FlutterCompass.events != null) {
        _compassSub = FlutterCompass.events?.listen(
          (CompassEvent event) {
            if (event.heading != null) {
              onHeadingChanged!(event.heading!);
            }
          },
          onError: (_) {
            // Compass missing: silent fallback
          },
          cancelOnError: false,
        );
      }
    } catch (_) {}
  }

  void stop() {
    try {
      _userAccelSub?.cancel();
      _userAccelSub = null;
    } catch (_) {}

    try {
      _rawAccelSub?.cancel();
      _rawAccelSub = null;
    } catch (_) {}

    try {
      _compassSub?.cancel();
      _compassSub = null;
    } catch (_) {}
  }
}
