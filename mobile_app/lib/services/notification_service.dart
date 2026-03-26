import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert_model.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _fallChannelId       = 'fall_alerts';
  static const String _discomfortChannelId = 'discomfort_alerts';
  static const String _thresholdChannelId  = 'threshold_alerts';

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(initSettings);
    await _createNotificationChannels();
    debugPrint('NotificationService: Initialized');
  }

  Future<void> _createNotificationChannels() async {
    const fallChannel = AndroidNotificationChannel(
      _fallChannelId,
      'Fall Alerts',
      description: 'Urgent alerts when a fall is detected',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    const discomfortChannel = AndroidNotificationChannel(
      _discomfortChannelId,
      'Discomfort Alerts',
      description: 'Alerts when the person may be uncomfortable',
      importance: Importance.high,
      playSound: true,
    );
    const thresholdChannel = AndroidNotificationChannel(
      _thresholdChannelId,
      'Threshold Alerts',
      description: 'Alerts when sensor readings leave the comfort range',
      importance: Importance.defaultImportance,
      playSound: false,
    );

    // FIX: keep generic on one line to avoid parser issues on older SDK
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(fallChannel);
      await androidPlugin.createNotificationChannel(discomfortChannel);
      await androidPlugin.createNotificationChannel(thresholdChannel);
    }
  }

  Future<void> showFallAlert(AlertEvent event) async {
    final confidence = (event.confidence * 100).toInt();
    await _show(
      id:         1,
      channelId:  _fallChannelId,
      title:      '⚠️ Fall Detected',
      body:       'Please check on the person immediately. ($confidence% confidence)',
      priority:   Priority.max,
      importance: Importance.max,
    );
  }

  Future<void> showDiscomfortAlert(AlertEvent event) async {
    final confidence = (event.confidence * 100).toInt();
    await _show(
      id:         2,
      channelId:  _discomfortChannelId,
      title:      'Possible Discomfort ($confidence%)',
      body:       event.message,
      priority:   Priority.high,
      importance: Importance.high,
    );
  }

  Future<void> showThresholdBreachAlert(ThresholdBreachDetail breach) async {
    await _show(
      id:         breach.sensorName.hashCode,
      channelId:  _thresholdChannelId,
      title:      'Unusual ${breach.sensorName}',
      body:       breach.breachMessage,
      priority:   Priority.defaultPriority,
      importance: Importance.defaultImportance,
    );
  }

  Future<void> cancelAll() async => _plugin.cancelAll();

  Future<void> _show({
    required int        id,
    required String     channelId,
    required String     title,
    required String     body,
    required Priority   priority,
    required Importance importance,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelId,
        importance: importance,
        priority:   priority,
        playSound:  true,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      );
      await _plugin.show(id, title, body, details);
      debugPrint('NotificationService: Showed "$title"');
    } catch (e) {
      debugPrint('NotificationService: Failed to show notification: $e');
    }
  }
}