import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/localization/localized_text.dart';

/// Sends the one post-meal question as an OS notification.
///
/// There is exactly one slot: scheduling again replaces what was there, so a
/// second order can never stack a second question on the first.
abstract interface class ReflectionNotifier {
  /// Wires up tap handling. [onTap] receives the payload.
  Future<void> initialize({required ValueChanged<String?> onTap});

  /// The payload of the notification that launched the app, if one did.
  Future<String?> launchPayload();

  /// Asks the OS for permission, quietly where the OS allows it.
  Future<void> requestPermission();

  /// Puts the question in the slot for [at].
  Future<void> schedule({
    required String payload,
    required DateTime at,
    required AppLanguage language,
  });

  /// Empties the slot.
  Future<void> cancel();
}

/// Records calls instead of talking to the OS. For tests.
final class FakeReflectionNotifier implements ReflectionNotifier {
  /// The slot: payload and time, or null.
  ({String payload, DateTime at, AppLanguage language})? scheduled;

  /// How many times permission was asked for.
  int permissionRequests = 0;

  /// What [launchPayload] returns.
  String? launchedWith;

  /// The tap handler, so a test can "tap" the notification.
  ValueChanged<String?>? onTap;

  @override
  Future<void> initialize({required ValueChanged<String?> onTap}) async =>
      this.onTap = onTap;

  @override
  Future<String?> launchPayload() async => launchedWith;

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<void> schedule({
    required String payload,
    required DateTime at,
    required AppLanguage language,
  }) async =>
      scheduled = (payload: payload, at: at, language: language);

  @override
  Future<void> cancel() async => scheduled = null;
}

/// The real thing, on `flutter_local_notifications`.
///
/// Low stimulation by construction: Android gets a low-importance channel (no
/// sound, no heads-up, no badge); iOS gets provisional authorisation (no
/// prompt, delivered straight to the notification list) at the passive level.
final class LocalReflectionNotifier implements ReflectionNotifier {
  /// Creates the notifier. The plugin is resolved lazily.
  LocalReflectionNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _pluginOverride = plugin;

  static const int _slot = 1001;
  static const String _channelId = 'mindful_reflection';

  static const LocalizedText _title = LocalizedText(ar: 'موزون', en: 'Mawzoon');
  static const LocalizedText _body =
      LocalizedText(ar: 'كيف يشعر جسمك الآن؟', en: 'How does your body feel?');

  final FlutterLocalNotificationsPlugin? _pluginOverride;
  late final FlutterLocalNotificationsPlugin _plugin =
      _pluginOverride ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize({required ValueChanged<String?> onTap}) async {
    tz_data.initializeTimeZones();
    try {
      final TimezoneInfo zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      // Unknown zone name: stay on the package default (UTC). The question
      // arrives at the right instant either way; only quiet-hours math, which
      // runs on the device clock, not here, would care.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Nothing is requested at start-up; see requestPermission.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse r) =>
          onTap(r.payload),
    );
  }

  @override
  Future<String?> launchPayload() async {
    final NotificationAppLaunchDetails? details =
        await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  @override
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, provisional: true);
  }

  @override
  Future<void> schedule({
    required String payload,
    required DateTime at,
    required AppLanguage language,
  }) async {
    await _plugin.zonedSchedule(
      id: _slot,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      title: _title.resolve(language),
      body: _body.resolve(language),
      payload: payload,
      // Inexact: a few minutes' drift is fine, and exact alarms need a
      // permission Play restricts.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          language == AppLanguage.arabic ? 'تأمل بعد الوجبة' : 'After-meal check-in',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          channelShowBadge: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
          interruptionLevel: InterruptionLevel.passive,
        ),
      ),
    );
  }

  @override
  Future<void> cancel() => _plugin.cancel(id: _slot);
}
