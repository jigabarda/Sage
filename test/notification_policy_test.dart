import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sage/constants/episode_kind.dart';
import 'package:sage/data/insights/insight.dart';
import 'package:sage/data/models/episode.dart';
import 'package:sage/data/notifications/notification_policy.dart';

/// The plugin is a platform channel and cannot be exercised here, but the part
/// worth getting right — whether to send at all, and what it says — is pure.
void main() {
  Insight insight(InsightStrength strength, String detail) => Insight(
    id: 'x_$strength',
    strength: strength,
    icon: Icons.abc,
    title: 'title',
    detail: detail,
  );

  Episode episode({required DateTime startedAt, DateTime? endedAt}) => Episode(
    id: 'ep',
    kind: EpisodeKind.migraine,
    startedAt: startedAt,
    endedAt: endedAt,
    severity: 6,
    notes: '',
    startedDay: 0,
    createdAt: startedAt,
    updatedAt: startedAt,
  );

  group('nothing to say means silence', () {
    test('no findings, no weekly summary', () {
      expect(NotificationPolicy.weeklySummary(const []), isNull);
    });

    test('only plain summaries is still nothing worth interrupting for', () {
      // A weekly ping reading "you logged 4 this month" teaches someone to
      // swipe the next one away without reading it, and the one after that is
      // the one that mattered.
      final found = [
        insight(InsightStrength.info, 'You logged 4 in the last four weeks.'),
      ];
      expect(NotificationPolicy.weeklySummary(found), isNull);
    });

    test('a real finding is sent, carrying its own numbers', () {
      final found = [
        insight(
          InsightStrength.strong,
          'You had a migraine on 7 of the 10 days you slept under 6 hours.',
        ),
        insight(InsightStrength.moderate, 'something weaker'),
      ];
      final n = NotificationPolicy.weeklySummary(found)!;
      // The strongest one only. Three findings crammed into a lock-screen line
      // is none read.
      expect(n.body, contains('7 of the 10 days'));
      expect(n.body, isNot(contains('something weaker')));
    });

    test('the daily nudge is skipped once the day has an entry', () {
      expect(NotificationPolicy.dailyNudge(dayAlreadyLogged: true), isNull);
      expect(NotificationPolicy.dailyNudge(dayAlreadyLogged: false), isNotNull);
    });
  });

  group('follow-up', () {
    final start = DateTime(2026, 9, 6, 9);

    test('does not fire while the episode is young', () {
      // Most migraines are hours, not minutes. A nudge at one hour lands
      // mid-attack, which is the one moment the app should leave them alone.
      expect(
        NotificationPolicy.followUp(
          episode(startedAt: start),
          start.add(const Duration(hours: 1)),
        ),
        isNull,
      );
    });

    test('fires once it has been open long enough', () {
      final n = NotificationPolicy.followUp(
        episode(startedAt: start),
        start.add(NotificationPolicy.followUpAfter),
      );
      expect(n, isNotNull);
      expect(n!.body, contains('09:00'));
    });

    test('never fires for an episode that has been closed', () {
      expect(
        NotificationPolicy.followUp(
          episode(
            startedAt: start,
            endedAt: start.add(const Duration(hours: 2)),
          ),
          start.add(const Duration(hours: 8)),
        ),
        isNull,
      );
    });
  });

  group('scheduling arithmetic', () {
    test('the weekly slot lands on the right weekday and hour', () {
      // 2026-09-07 is a Monday.
      final from = DateTime(2026, 9, 7, 10);
      final next = NotificationPolicy.nextWeekly(from);
      expect(next.weekday, DateTime.sunday);
      expect(next.hour, NotificationPolicy.weeklyHour);
      expect(next.isAfter(from), isTrue);
    });

    test('rescheduling on the slot itself moves to next week, not now', () {
      // Sunday at exactly 19:00. Without a strict comparison this fires
      // immediately and then again in seven days.
      final onTheHour = DateTime(2026, 9, 6, NotificationPolicy.weeklyHour);
      expect(onTheHour.weekday, DateTime.sunday);

      final next = NotificationPolicy.nextWeekly(onTheHour);
      expect(next.difference(onTheHour), const Duration(days: 7));
    });

    test('the daily slot is today when it is still ahead, tomorrow after', () {
      final morning = DateTime(2026, 9, 7, 8);
      expect(NotificationPolicy.nextDaily(morning).day, 7);

      final lateEvening = DateTime(2026, 9, 7, 23);
      expect(NotificationPolicy.nextDaily(lateEvening).day, 8);
    });
  });

  group('settings', () {
    test('everything is off until asked for', () {
      // An app that starts sending things nobody asked for gets its
      // notifications disabled wholesale, and the follow-up is the one worth
      // keeping.
      const s = NotificationSettings();
      expect(s.weeklySummary, isFalse);
      expect(s.episodeFollowUp, isFalse);
      expect(s.dailyNudge, isFalse);
      expect(s.anyEnabled, isFalse);
    });

    test('copyWith flips one without disturbing the others', () {
      const s = NotificationSettings(episodeFollowUp: true);
      final next = s.copyWith(weeklySummary: true);
      expect(next.episodeFollowUp, isTrue);
      expect(next.weeklySummary, isTrue);
      expect(next.dailyNudge, isFalse);
      expect(next.anyEnabled, isTrue);
    });
  });

  test('no notification text tells anyone to seek care', () {
    // Same rule as the insights: urgency belongs to Tier 0, evaluated at the
    // moment it matters. A notification is the worst possible instrument for
    // it - it can arrive days late and be read on a lock screen.
    final texts = <String>[
      ...?NotificationPolicy.weeklySummary([
        insight(InsightStrength.strong, 'You had a migraine on 7 of 10 days.'),
      ]).let((n) => [n.title, n.body]),
      ...?NotificationPolicy.dailyNudge(
        dayAlreadyLogged: false,
      ).let((n) => [n.title, n.body]),
      ...?NotificationPolicy.followUp(
        episode(startedAt: DateTime(2026, 9, 6, 9)),
        DateTime(2026, 9, 6, 20),
      ).let((n) => [n.title, n.body]),
    ];

    final urgent = RegExp(
      r'\b(emergency|urgent|ambulance|999|911|hospital|see a doctor|'
      r'seek (medical )?(care|help|attention))\b',
      caseSensitive: false,
    );
    for (final t in texts) {
      expect(urgent.hasMatch(t), isFalse, reason: t);
    }
    expect(texts, isNotEmpty);
  });
}

extension<T> on T? {
  R? let<R>(R Function(T) f) {
    final v = this;
    return v == null ? null : f(v);
  }
}
