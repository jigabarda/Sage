import 'episode_kind.dart';

/// Something the user believes set an episode off.
///
/// Codes are persisted in `episode_triggers.trigger_code` and are permanent
/// once shipped.
class Trigger {
  const Trigger(this.code, this.label, this.kinds);

  final String code;
  final String label;
  final Set<EpisodeKind> kinds;
}

/// Where a trigger row came from. Persisted in `episode_triggers.source`.
///
/// The distinction is not bookkeeping. A user-stated trigger is a belief; an
/// inferred one is arithmetic over `daily_log`. Feeding beliefs back into the
/// correlation rules would let the rules confirm whatever the user already
/// suspected and report it as a finding — so Phase 3 reads [inferred] rows and
/// `daily_log`, never [user] rows.
abstract final class TriggerSource {
  /// The user ticked it.
  static const user = 'user';

  /// A Phase 3 rule derived it. Never written by a screen.
  static const inferred = 'inferred';
}

abstract final class Triggers {
  static const all = <Trigger>[
    // Migraine
    Trigger('short_sleep', 'Not enough sleep', {EpisodeKind.migraine}),
    Trigger('skipped_meal', 'Skipped a meal', {EpisodeKind.migraine}),
    Trigger('bright_light', 'Bright light', {EpisodeKind.migraine}),
    Trigger('loud_noise', 'Loud noise', {EpisodeKind.migraine}),
    Trigger('strong_smell', 'Strong smell', {EpisodeKind.migraine}),
    Trigger('screen_time', 'Long screen time', {EpisodeKind.migraine}),
    Trigger('weather', 'Weather change', {EpisodeKind.migraine}),
    Trigger('menstruation', 'Period', {EpisodeKind.migraine}),
    Trigger('exercise', 'Exertion', {EpisodeKind.migraine}),

    // Reflux
    Trigger('late_meal', 'Ate late', {EpisodeKind.reflux}),
    Trigger('large_meal', 'Large meal', {EpisodeKind.reflux}),
    Trigger('spicy_food', 'Spicy food', {EpisodeKind.reflux}),
    Trigger('fatty_food', 'Fatty or fried food', {EpisodeKind.reflux}),
    Trigger('acidic_food', 'Citrus or tomato', {EpisodeKind.reflux}),
    Trigger('chocolate', 'Chocolate', {EpisodeKind.reflux}),
    Trigger('carbonated', 'Fizzy drink', {EpisodeKind.reflux}),
    Trigger('lay_down_after', 'Lay down after eating', {EpisodeKind.reflux}),

    // Both
    Trigger('stress', 'Stress', {EpisodeKind.migraine, EpisodeKind.reflux}),
    Trigger('alcohol', 'Alcohol', {EpisodeKind.migraine, EpisodeKind.reflux}),
    Trigger('coffee', 'Coffee', {EpisodeKind.migraine, EpisodeKind.reflux}),
    Trigger('dehydration', 'Not enough water', {
      EpisodeKind.migraine,
      EpisodeKind.reflux,
    }),
    Trigger('poor_sleep', 'Slept badly', {
      EpisodeKind.migraine,
      EpisodeKind.reflux,
    }),
  ];

  static List<Trigger> forKind(EpisodeKind kind) =>
      all.where((t) => t.kinds.contains(kind)).toList(growable: false);

  static Trigger? byCode(String code) {
    for (final t in all) {
      if (t.code == code) return t;
    }
    return null;
  }

  static String labelFor(String code) => byCode(code)?.label ?? code;
}
