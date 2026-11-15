import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Manages the Android background receive foreground service (type: dataSync).
class ForegroundReceiverService {
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'flik_receiver_channel',
        channelName: 'Flik Receive Service',
        channelDescription: 'Keeps Flik ready to receive incoming files and links over Wi-Fi.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }
    return await FlutterForegroundTask.startService(
      notificationTitle: 'Flik Receive Mode Active',
      notificationText: 'Ready to receive files from your PC and peers.',
    );
  }

  static Future<bool> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      return await FlutterForegroundTask.stopService();
    }
    return true;
  }
}
