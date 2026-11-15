import 'dart:async';
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

// Provides hardware sensor integration: wrist flick gesture detection and compass heading.
class SensorService {
  // Flick sensitivity thresholds
  static const double flickThreshold = 22.0; // m/s^2 user acceleration
  static const int cooldownMs = 800; // 800ms cooldown to avoid double trigger

  StreamSubscription? _accelSub;
  StreamSubscription? _compassSub;
  int _lastFlickTime = 0;

  final void Function() onFlick;
  final void Function(double headingDegrees)? onHeadingChanged;

  SensorService({
    required this.onFlick,
    this.onHeadingChanged,
  });

  // Starts sensor listeners with error handling and silent fallback if sensors are absent
  void start() {
    try {
      _accelSub = userAccelerometerEventStream().listen(
        (UserAccelerometerEvent event) {
          final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
          final now = DateTime.now().millisecondsSinceEpoch;

          if (magnitude > flickThreshold && (now - _lastFlickTime) > cooldownMs) {
            _lastFlickTime = now;
            onFlick();
          }
        },
        onError: (_) {
          // Hardware sensor missing or unavailable: silent fallback
        },
        cancelOnError: false,
      );
    } catch (_) {
      // Silent fallback
    }

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
    } catch (_) {
      // Silent fallback
    }
  }

  void stop() {
    try {
      _accelSub?.cancel();
      _accelSub = null;
    } catch (_) {}

    try {
      _compassSub?.cancel();
      _compassSub = null;
    } catch (_) {}
  }
}
