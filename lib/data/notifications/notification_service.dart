import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_policy.dart';

const _prefWeekly = 'notify_weekly_summary';
const _prefFollowUp = 'notify_episode_follow_up';
const _prefDaily = 'notify_daily_nudge';

/// Delivers the notifications [NotificationPolicy] decides on.
///
/// Everything is scheduled on the device. There is no FCM, no push token and
/// no server — a reminder about your own log has no business leaving the
/// phone, and this app has no `INTERNET` permission to send it with anyway.
///
/// ## Lock-screen privacy
///
/// Every notification is posted with `Visibility.private`, so the body is
/// hidden on a secure lock screen and only the app name shows. "You had a
/// migraine on 10 of the 20 days you slept under 6 hours" is health data, and
/// a lock screen is read by whoever picks the phone up.
class NotificationService {
  NotificationService(this._prefs);

  final SharedPreferences _prefs;
  final _plugin = FlutterLocalNotificationsPlugin();

  bool _ready = false;

  static const _channelId = 'sage_reminders';
  static const _channelName = 'Reminders';

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription:
          'Weekly summaries, follow-ups on an open episode, and the '
          'optional daily log reminder.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      // Health data. Hidden on a secure lock screen.
      visibility: NotificationVisibility.private,
    ),
  );

  /// Prepares the plugin and the timezone database.
  ///
  /// Safe to call more than once. Failures are swallowed: notifications are a
  /// convenience, and an app that will not start because a reminder could not
  /// be scheduled has its priorities the wrong way round.
  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      // Scheduling in the device's own zone, not UTC. "Sunday at 19:00" has to
      // mean the user's Sunday evening, and it has to keep meaning that if
      // they travel.
      tz.setLocalLocation(
        tz.getLocation(await FlutterTimezone.getLocalTimezone()),
      );

      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (e) {
      // Leaves _ready false, so every schedule call below no-ops.
      debugPrint('NotificationService.init failed: $e');
    }
  }

  /// Asks for the Android 13+ runtime permission.
  ///
  /// **Call this only after the person has switched something on**, never at
  /// launch. A permission prompt shown before any value has been demonstrated
  /// is the one that gets denied, and on Android a second denial is permanent
  /// until the user digs into system settings.
  Future<bool> requestPermission() async {
    if (!_ready) await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  NotificationSettings get settings => NotificationSettings(
    weeklySummary: _prefs.getBool(_prefWeekly) ?? false,
    episodeFollowUp: _prefs.getBool(_prefFollowUp) ?? false,
    dailyNudge: _prefs.getBool(_prefDaily) ?? false,
  );

  Future<void> saveSettings(NotificationSettings s) async {
    await _prefs.setBool(_prefWeekly, s.weeklySummary);
    await _prefs.setBool(_prefFollowUp, s.episodeFollowUp);
    await _prefs.setBool(_prefDaily, s.dailyNudge);
  }

  /// Schedules a one-off at [when].
  ///
  /// Inexact on purpose. Exact alarms need `SCHEDULE_EXACT_ALARM`, which on
  /// Android 14 is a separate user grant and is meant for alarm clocks and
  /// calendar events. Nothing here needs to land on a specific second — a
  /// weekly summary that arrives at 19:14 instead of 19:00 is the same
  /// notification.
  Future<void> _scheduleAt(
    SageNotification which,
    DateTime when,
    String title,
    String body, {
    DateTimeComponents? repeating,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.zonedSchedule(
        which.id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Android-only app, but the parameter is required by the API.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: repeating,
      );
    } catch (e) {
      debugPrint('schedule ${which.name} failed: $e');
    }
  }

  Future<void> cancel(SageNotification which) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(which.id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Re-arms the recurring reminders from current settings and content.
  ///
  /// Called at startup and after any change, so the schedule is rebuilt from
  /// scratch rather than patched. Ids are stable per notification, so this
  /// replaces rather than stacks.
  ///
  /// [weeklyBody] is null when there is nothing worth saying, and then the
  /// weekly summary is simply not scheduled — see the rule in
  /// [NotificationPolicy].
  Future<void> rearm({
    required ({String title, String body})? weekly,
    required bool dayAlreadyLogged,
    DateTime? now,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;

    final at = now ?? DateTime.now();
    final s = settings;

    await cancel(SageNotification.weeklySummary);
    if (s.weeklySummary && weekly != null) {
      await _scheduleAt(
        SageNotification.weeklySummary,
        NotificationPolicy.nextWeekly(at),
        weekly.title,
        weekly.body,
        // Weekly, same weekday and time. The body is refreshed on the next
        // rearm, so a repeating schedule never goes stale for more than a
        // week.
        repeating: DateTimeComponents.dayOfWeekAndTime,
      );
    }

    await cancel(SageNotification.dailyLogNudge);
    if (s.dailyNudge) {
      final nudge = NotificationPolicy.dailyNudge(
        dayAlreadyLogged: dayAlreadyLogged,
      );
      if (nudge != null) {
        await _scheduleAt(
          SageNotification.dailyLogNudge,
          NotificationPolicy.nextDaily(at),
          nudge.title,
          nudge.body,
          repeating: DateTimeComponents.time,
        );
      }
    }
  }

  /// Arms the "still going?" nudge for an episode that was just opened.
  Future<void> scheduleFollowUp({
    required String kindLabel,
    required DateTime startedAt,
  }) async {
    if (!_ready) await init();
    if (!_ready || !settings.episodeFollowUp) return;
    await _scheduleAt(
      SageNotification.episodeFollowUp,
      startedAt.add(NotificationPolicy.followUpAfter),
      'Still going?',
      'Your ${kindLabel.toLowerCase()} is still open. Closing it records how '
          'long it lasted.',
    );
  }

  /// Called when an episode is closed, so the follow-up does not arrive after
  /// the thing it is asking about is over.
  Future<void> cancelFollowUp() => cancel(SageNotification.episodeFollowUp);
}
