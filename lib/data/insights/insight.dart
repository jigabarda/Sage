import 'package:flutter/widgets.dart';

/// How well evidenced a finding is.
///
/// **This is not medical urgency, and must never be read as it.** Tier 0 owns
/// urgency exclusively; nothing produced by the correlation engine is an
/// alarm, and no insight may ever tell someone to seek care. If a finding
/// seems to warrant that, the condition belongs in `TriageRules` where it is
/// evaluated deterministically at the moment it matters — not in a card
/// someone might read a week later.
enum InsightStrength {
  /// A large, consistent difference over a good number of days.
  strong,

  /// Real by the gates, but a smaller effect or a thinner window.
  moderate,

  /// A plain summary. No causal claim at all.
  info,
}

/// One thing worth telling someone about their own record.
///
/// Derived entirely from their own rows by arithmetic. There is no model
/// anywhere in this path.
@immutable
class Insight {
  const Insight({
    required this.id,
    required this.strength,
    required this.icon,
    required this.title,
    required this.detail,
  });

  /// Stable across runs for the same underlying fact, so a future "dismiss"
  /// feature has something to key on.
  final String id;

  final InsightStrength strength;
  final IconData icon;

  /// One line, naming the thing. Read on its own in a list.
  final String title;

  /// The sentence carrying the evidence.
  ///
  /// **[detail] must state the numbers it was derived from.** "Sleep affects
  /// your migraines" is not an insight; "you had one on 5 of the 9 days you
  /// slept under 6 hours, against 2 of the 21 days you slept more" is,
  /// because the reader can check it against what they already know. An
  /// insight the reader cannot verify is indistinguishable from one that is
  /// simply wrong — and in a health app, an unverifiable claim is what makes
  /// someone change their diet for nothing.
  final String detail;
}
