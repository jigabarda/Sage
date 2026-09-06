import 'episode_kind.dart';

/// Something the user tried in order to feel better.
///
/// Codes are persisted in `episode_relievers.reliever_code` and are permanent
/// once shipped.
class Reliever {
  const Reliever(this.code, this.label, this.kinds);

  final String code;
  final String label;
  final Set<EpisodeKind> kinds;
}

/// What people actually try, as neutral descriptions of an action.
///
/// **Nothing here names a drug or a dose.** Medication is logged through the
/// `meds` table, where the name and the dose are free text the user typed —
/// see non-negotiable 6. `rescue_med` below records only *that* a rescue
/// medication was taken, and the dose row carries the rest.
///
/// This list is the input to the Phase 1 "what helped last time" line and,
/// later, to the reliever-effectiveness rule. That rule needs the [helped]
/// rating on the row, which is why it is a separate nullable column rather
/// than inferred from the episode ending.
abstract final class Relievers {
  static const all = <Reliever>[
    // Migraine
    Reliever('dark_room', 'Lay down in the dark', {EpisodeKind.migraine}),
    Reliever('sleep', 'Slept', {EpisodeKind.migraine}),
    Reliever('cold_compress', 'Cold compress', {EpisodeKind.migraine}),
    Reliever('warm_compress', 'Warm compress', {EpisodeKind.migraine}),
    Reliever('caffeine', 'Caffeine', {EpisodeKind.migraine}),
    Reliever('quiet', 'Got somewhere quiet', {EpisodeKind.migraine}),
    Reliever('massage', 'Massage or pressure', {EpisodeKind.migraine}),

    // Reflux
    Reliever('upright', 'Stayed upright', {EpisodeKind.reflux}),
    Reliever('head_elevated', 'Propped my head up', {EpisodeKind.reflux}),
    Reliever('antacid', 'Antacid', {EpisodeKind.reflux}),
    Reliever('small_meal', 'Ate something small', {EpisodeKind.reflux}),
    Reliever('avoided_food', 'Stopped eating', {EpisodeKind.reflux}),
    Reliever('loose_clothing', 'Loosened clothing', {EpisodeKind.reflux}),

    // Both
    Reliever('water', 'Drank water', {
      EpisodeKind.migraine,
      EpisodeKind.reflux,
    }),
    Reliever('fresh_air', 'Fresh air', {
      EpisodeKind.migraine,
      EpisodeKind.reflux,
    }),
    Reliever('rescue_med', 'Took my rescue medication', {
      EpisodeKind.migraine,
      EpisodeKind.reflux,
    }),
    Reliever('waited', 'Waited it out', {
      EpisodeKind.migraine,
      EpisodeKind.reflux,
    }),
  ];

  static List<Reliever> forKind(EpisodeKind kind) =>
      all.where((r) => r.kinds.contains(kind)).toList(growable: false);

  static Reliever? byCode(String code) {
    for (final r in all) {
      if (r.code == code) return r;
    }
    return null;
  }

  static String labelFor(String code) => byCode(code)?.label ?? code;
}

/// How a reliever went.
///
/// Stored as `episode_relievers.helped`; **null means unrated, not neutral.**
/// The effectiveness rule counts rated attempts only — treating "never went
/// back to say" as "no change" would drag every reliever's score towards
/// nothing, and the people least likely to rate are the ones having the worst
/// episodes.
abstract final class RelieverOutcome {
  static const worse = -1;
  static const noChange = 0;
  static const helped = 1;

  static String labelFor(int? v) => switch (v) {
    worse => 'Made it worse',
    noChange => 'No change',
    helped => 'Helped',
    _ => 'Not rated',
  };
}
