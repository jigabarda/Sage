import 'package:flutter/material.dart';

/// The two conditions this app tracks.
///
/// Stored as the `kind` string on `episodes`. They share the logging substrate
/// but not their symptoms, relievers, triggers or red flags, so almost
/// everything downstream branches on this.
enum EpisodeKind {
  migraine('migraine', 'Migraine', 'a migraine', Icons.psychology_alt_outlined),
  reflux('reflux', 'Reflux', 'reflux', Icons.local_fire_department_outlined);

  const EpisodeKind(this.code, this.label, this.inSentence, this.icon);

  /// Persisted value. Never store [name] — a rename would silently orphan rows.
  final String code;
  final String label;

  /// How the condition reads mid-sentence, with its article if it takes
  /// one: "you had **a migraine** on 4 of..." but "you had **reflux** on
  /// 4 of...". Lowercasing [label] and prefixing "a" produces "a reflux",
  /// which the dump tool caught before anyone read it on a screen.
  final String inSentence;

  final IconData icon;

  static EpisodeKind fromCode(String code) => EpisodeKind.values.firstWhere(
    (k) => k.code == code,
    orElse: () => EpisodeKind.migraine,
  );
}

/// How bad it is, 1–10.
///
/// A free 1–10 scale is what people are used to being asked in a clinic, and
/// it exports to a doctor without a translation table. The bands below only
/// decide presentation.
abstract final class Severity {
  static const min = 1;
  static const max = 10;

  /// The severity a one-tap "having one now" starts at.
  ///
  /// Mid-scale on purpose. A default of 1 would under-report every episode
  /// someone never went back to edit, and a default of 10 would poison the
  /// correlation rules in the other direction. The point of the quick log is
  /// that the *timestamp* is captured accurately while the person is in no
  /// state to fill in a form; severity is refined later.
  static const quickLogDefault = 5;

  static bool isValid(int v) => v >= min && v <= max;

  static SeverityBand bandOf(int v) {
    if (v <= 3) return SeverityBand.low;
    if (v <= 7) return SeverityBand.moderate;
    return SeverityBand.high;
  }
}

/// Presentation bands for [Severity].
///
/// Three bands, none of them green — see the note in `sage_tokens.dart`. Low is
/// neutral rather than positive: a mild migraine is still a migraine.
enum SeverityBand { low, moderate, high }
