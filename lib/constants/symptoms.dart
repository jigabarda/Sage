import 'episode_kind.dart';

/// A symptom the user can tick on an episode.
///
/// Codes are persisted in `episode_symptoms.symptom_code` and must never
/// change once shipped — a rename orphans every row that used it. Labels are
/// free to be reworded.
class Symptom {
  const Symptom(this.code, this.label, this.kinds);

  final String code;
  final String label;

  /// Which conditions this symptom is offered for. Some appear under both.
  final Set<EpisodeKind> kinds;
}

/// The pick-list, ordered roughly by how often people report each one, because
/// the list is read top-down by someone who wants to stop reading.
///
/// **None of these are red flags.** Warning signs that mean "seek care now"
/// live in the Phase 2 triage set, deliberately separate: a red flag is not a
/// checkbox on a log, it is a different screen. Neck *pain* is here because it
/// is ordinary in migraine; neck *stiffness with fever* is a triage pattern and
/// is not in this file.
abstract final class Symptoms {
  static const all = <Symptom>[
    // Migraine
    Symptom('throbbing', 'Throbbing pain', {EpisodeKind.migraine}),
    Symptom('one_sided', 'One-sided', {EpisodeKind.migraine}),
    Symptom('photophobia', 'Light hurts', {EpisodeKind.migraine}),
    Symptom('phonophobia', 'Sound hurts', {EpisodeKind.migraine}),
    Symptom('osmophobia', 'Smells bother me', {EpisodeKind.migraine}),
    Symptom('aura', 'Visual aura', {EpisodeKind.migraine}),
    Symptom('neck_pain', 'Neck pain', {EpisodeKind.migraine}),
    Symptom('dizziness', 'Dizzy', {EpisodeKind.migraine}),
    Symptom('brain_fog', 'Foggy thinking', {EpisodeKind.migraine}),

    // Reflux
    Symptom('heartburn', 'Burning in chest', {EpisodeKind.reflux}),
    Symptom('regurgitation', 'Acid coming up', {EpisodeKind.reflux}),
    Symptom('sour_taste', 'Sour taste', {EpisodeKind.reflux}),
    Symptom('bloating', 'Bloated', {EpisodeKind.reflux}),
    Symptom('burping', 'Burping', {EpisodeKind.reflux}),
    Symptom('globus', 'Lump in throat', {EpisodeKind.reflux}),
    Symptom('cough', 'Dry cough', {EpisodeKind.reflux}),
    Symptom('hoarseness', 'Hoarse voice', {EpisodeKind.reflux}),

    // Both
    Symptom('nausea', 'Nauseous', {EpisodeKind.migraine, EpisodeKind.reflux}),
    Symptom('vomiting', 'Vomited', {EpisodeKind.migraine, EpisodeKind.reflux}),
    Symptom('appetite_loss', 'No appetite', {
      EpisodeKind.migraine,
      EpisodeKind.reflux,
    }),
  ];

  static List<Symptom> forKind(EpisodeKind kind) =>
      all.where((s) => s.kinds.contains(kind)).toList(growable: false);

  static Symptom? byCode(String code) {
    for (final s in all) {
      if (s.code == code) return s;
    }
    // Null rather than a placeholder: a code from a build that has since
    // dropped it should be visibly absent, not silently relabelled.
    return null;
  }

  /// Label for a stored code, falling back to the raw code so an unknown
  /// value is still traceable in an export rather than vanishing.
  static String labelFor(String code) => byCode(code)?.label ?? code;
}
