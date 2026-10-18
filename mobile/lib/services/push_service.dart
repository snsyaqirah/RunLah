import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/l10n/i18n.dart';
import 'notification_center.dart';

/// Android channel for checkpoint passes, finishes, cheers and results.
const raceUpdatesChannelId = 'race_updates';

/// Wires [NotificationCenter] to OS notifications with
/// flutter_local_notifications (local notifications in demo mode; in
/// production the same notices arrive through FCM / APNs).
///
/// Never throws and never blocks startup: everything is wrapped, plugin
/// calls time out, and the permission prompt is not awaited. No-op on web
/// and desktop (the in-app banner and feed still work there).
Future<void> initPushService(NotificationCenter center) async {
  if (kIsWeb) return;
  final platform = defaultTargetPlatform;
  final android = platform == TargetPlatform.android;
  final darwin = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  if (!android && !darwin) return;

  final plugin = FlutterLocalNotificationsPlugin();
  try {
    const darwinInit = DarwinInitializationSettings(
      // Asked below, without blocking app start.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final ok = await plugin
        .initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: darwinInit,
            macOS: darwinInit,
          ),
        )
        .timeout(const Duration(seconds: 3));
    if (ok == false) return;

    if (android) {
      final impl = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await impl
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              raceUpdatesChannelId,
              tr('Race updates'),
              description: tr('Checkpoint passes, finishes and cheers for the runners you follow'),
              importance: Importance.high,
            ),
          )
          .timeout(const Duration(seconds: 3));
    }
  } catch (_) {
    // MissingPluginException in tests, old OS versions, timeouts...
    return;
  }

  unawaited(_requestPermission(plugin, android: android));

  var nextId = 1;
  center.platformNotifier = (notice) async {
    try {
      // In the foreground the shell already shows an in-app banner, so the
      // OS copy goes quietly to the tray instead of popping up again.
      final foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      await plugin.show(
        id: nextId++ & 0x7fffffff,
        title: notice.title,
        body: notice.body,
        payload: '${notice.kind.name}:${notice.participantId ?? ''}',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            raceUpdatesChannelId,
            tr('Race updates'),
            channelDescription: tr('Checkpoint passes, finishes and cheers for the runners you follow'),
            importance: Importance.high,
            priority: foreground ? Priority.low : Priority.high,
            silent: foreground,
            color: notice.color,
            category: AndroidNotificationCategory.event,
            styleInformation: BigTextStyleInformation(notice.body),
          ),
          iOS: DarwinNotificationDetails(presentBanner: !foreground, presentList: true, presentSound: !foreground),
          macOS: DarwinNotificationDetails(presentBanner: !foreground, presentList: true, presentSound: !foreground),
        ),
      );
    } catch (_) {
      // Notification permission denied or plugin gone: the feed still has it.
    }
  };
}

Future<void> _requestPermission(FlutterLocalNotificationsPlugin plugin, {required bool android}) async {
  try {
    if (android) {
      await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } else {
      await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
      await plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    }
  } catch (_) {}
}
