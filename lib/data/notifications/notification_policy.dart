import '../insights/insight.dart';
import '../models/episode.dart';

/// What each scheduled notification is for.
///
/// The id is stable per kind so rescheduling replaces rather than stacks —
/// three copies of the same weekly summary is how someone turns notifications
/// off for good.
enum SageNotification {
  weeklySummary(1),
  dailyLogNudge(2),
  episodeFollowUp(3);

  const SageNotification(this.id);
  final int id;
}

/// The decisions behind the notifications, separated from the plugin that
/// delivers them.
///
/// Everything here is pure, so the part worth getting right — *whether* to
/// send, and *what it says* — is testable without a platform channel.
///
/// ## The rule that governs all of this
///
/// **A notification with nothing to say must not be sent.** A weekly ping
/// reading "no patterns yet" teaches someone to swipe the next one away
/// without reading it, and the one after that is the one that mattered. Every
/// method below can return null, and null means silence.
abstract final class NotificationPolicy {
  /// Hours an episode may sit open before asking whether it is over.
  ///
  /// Long enough not to interrupt someone who is still in it, short enough
  /// that the end time is worth recording. Most migraines are hours, not
  /// minutes, so a nudge at one hour would land mid-attack — which is the one
  /// moment this app should be leaving them alone.
  static const followUpAfter = Duration(hours: 5);

  /// Sunday evening: late enough that the week is over, early enough to still
  /// be awake.
  static const weeklyWeekday = DateTime.sunday;
  static const weeklyHour = 19;

  /// Evening, after the day has happened. A morning nudge would ask someone to
  /// record a day they have not had yet.
  static const dailyNudgeHour = 20;

  /// The next occurrence of [weekday] at [hour], strictly after [from].
  ///
  /// Strictly after, so rescheduling at 19:00:00 on a Sunday does not fire
  /// immediately and then again in seven days.
  static DateTime nextWeekly(
    DateTime from, {
    int weekday = weeklyWeekday,
    int hour = weeklyHour,
  }) {
    var candidate = DateTime(from.year, from.month, from.day, hour);
    while (candidate.weekday != weekday || !candidate.isAfter(from)) {
      candidate = candidate.add(const Duration(days: 1));
      candidate = DateTime(
        candidate.year,
        candidate.month,
        candidate.day,
        hour,
      );
    }
    return candidate;
  }

  /// The next daily nudge, strictly after [from].
  static DateTime nextDaily(DateTime from, {int hour = dailyNudgeHour}) {
    final today = DateTime(from.year, from.month, from.day, hour);
    if (today.isAfter(from)) return today;
    final tomorrow = from.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hour);
  }

  /// The weekly summary, or null when there is nothing worth saying.
  ///
  /// Takes the strongest finding rather than a digest of all of them. A
  /// notification is one line someone reads on a lock screen; three findings
  /// crammed in is none read.
  static ({String title, String body})? weeklySummary(List<Insight> insights) {
    if (insights.isEmpty) return null;

    // `all()` already sorts strongest first. Anything at `info` strength is a
    // plain summary rather than a pattern, and is not worth interrupting
    // someone for.
    final top = insights.first;
    if (top.strength == InsightStrength.info) return null;

    return (title: 'From your log this week', body: top.detail);
  }

  /// The follow-up for an episode still open, or null if it is too soon or it
  /// has already been closed.
  static ({String title, String body})? followUp(
    Episode episode,
    DateTime now,
  ) {
    if (!episode.isOngoing) return null;
    if (now.difference(episode.startedAt) < followUpAfter) return null;
    return (
      title: 'Still going?',
      body:
          'Your ${episode.kind.label.toLowerCase()} has been open since '
          '${_clock(episode.startedAt)}. Closing it records how long it '
          'lasted.',
    );
  }

  /// The daily nudge, or null when the day already has an entry.
  static ({String title, String body})? dailyNudge({
    required bool dayAlreadyLogged,
  }) {
    if (dayAlreadyLogged) return null;
    return (
      title: 'Today\'s log',
      body: 'Sleep, stress and meals. Anything you did not track, leave blank.',
    );
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// Which notifications the user has switched on.
///
/// **All off by default.** An app that starts sending things nobody asked for
/// gets its notifications disabled wholesale, and the follow-up is genuinely
/// useful — spending that goodwill on an unrequested daily nudge is a bad
/// trade.
class NotificationSettings {
  const NotificationSettings({
    this.weeklySummary = false,
    this.episodeFollowUp = false,
    this.dailyNudge = false,
  });

  final bool weeklySummary;
  final bool episodeFollowUp;
  final bool dailyNudge;

  bool get anyEnabled => weeklySummary || episodeFollowUp || dailyNudge;

  NotificationSettings copyWith({
    bool? weeklySummary,
    bool? episodeFollowUp,
    bool? dailyNudge,
  }) => NotificationSettings(
    weeklySummary: weeklySummary ?? this.weeklySummary,
    episodeFollowUp: episodeFollowUp ?? this.episodeFollowUp,
    dailyNudge: dailyNudge ?? this.dailyNudge,
  );
}
