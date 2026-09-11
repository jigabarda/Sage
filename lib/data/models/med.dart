import 'package:flutter/foundation.dart';

/// What a medication is for.
enum MedKind {
  /// Taken when an episode starts.
  rescue('rescue', 'Rescue', 'Taken when one starts'),

  /// Taken regularly to reduce how often episodes happen.
  preventive('preventive', 'Preventive', 'Taken regularly');

  const MedKind(this.code, this.label, this.hint);

  final String code;
  final String label;
  final String hint;

  static MedKind fromCode(String? code) =>
      code == 'preventive' ? MedKind.preventive : MedKind.rescue;
}

/// A medication the person has told the app about.
///
/// ## Everything here is theirs, verbatim
///
/// [name] and [doseText] are free text. The app does not autocomplete a drug
/// name, does not suggest a dose, does not check an interaction and does not
/// know what any of this means — see non-negotiable 6. A field that offered
/// completions would imply the app had a drug database and had checked
/// something, and it has neither.
///
/// [doseText] is deliberately a string rather than a number and a unit. People
/// write "two at onset" and "half a tablet if it's bad", and forcing that into
/// `400` + `mg` would either lose the instruction or invent precision that was
/// never there.
@immutable
class Med {
  const Med({
    required this.id,
    required this.name,
    required this.doseText,
    required this.kind,
    required this.active,
    required this.monthlyLimitDays,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String doseText;
  final MedKind kind;

  /// False for something no longer taken. Kept rather than deleted so past
  /// doses still name what was taken — deleting the row would cascade the
  /// doses away and rewrite history.
  final bool active;

  /// Days in a 30-day window the person is aiming to stay under, or null for
  /// no limit set.
  ///
  /// **The app never fills this in, and never suggests a value.** How many
  /// days of a given medication is too many is a clinical question with
  /// different answers for different drugs — a default here would be the app
  /// quietly issuing medical advice, which is exactly what non-negotiable 6
  /// forbids.
  ///
  /// A number in this field came from the person or from what their doctor
  /// told them. All the app does is count against it, so "you have used this
  /// on 12 of the last 30 days, against the 10 you set" is arithmetic on their
  /// own target rather than a judgement of the app's own.
  ///
  /// Null is not zero. No limit set means the count is still shown, without
  /// anything to compare it to.
  final int? monthlyLimitDays;

  final DateTime createdAt;

  factory Med.fromRow(Map<String, Object?> row) => Med(
    id: row['id']! as String,
    name: row['name']! as String,
    doseText: (row['dose_text'] as String?) ?? '',
    kind: MedKind.fromCode(row['kind'] as String?),
    active: (row['active'] as int? ?? 1) == 1,
    monthlyLimitDays: row['monthly_limit_days'] as int?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'dose_text': doseText,
    'kind': kind.code,
    'active': active ? 1 : 0,
    'monthly_limit_days': monthlyLimitDays,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}

/// One dose, as recorded.
@immutable
class MedDose {
  const MedDose({
    required this.id,
    required this.medId,
    required this.takenAt,
    required this.episodeId,
  });

  final String id;
  final String medId;
  final DateTime takenAt;

  /// Null for a dose logged on its own rather than against an episode — a
  /// preventive taken daily, or a rescue taken without logging an attack.
  final String? episodeId;

  factory MedDose.fromRow(Map<String, Object?> row) => MedDose(
    id: row['id']! as String,
    medId: row['med_id']! as String,
    takenAt: DateTime.fromMillisecondsSinceEpoch(row['taken_at']! as int),
    episodeId: row['episode_id'] as String?,
  );
}

/// How much of one medication has been taken lately.
@immutable
class MedIntake {
  const MedIntake({
    required this.med,
    required this.doses,
    required this.days,
    required this.windowDays,
    required this.lastTaken,
  });

  final Med med;

  /// Doses in the window. Two in one day is two doses and one day.
  final int doses;

  /// Distinct days with at least one dose. This is the figure a limit is
  /// expressed in, because that is how limits are given.
  final int days;

  final int windowDays;
  final DateTime? lastTaken;

  int? get limit => med.monthlyLimitDays;

  /// Whether [days] has passed the limit the person set.
  ///
  /// False when no limit is set — the app has no opinion of its own to
  /// compare against.
  bool get overLimit => limit != null && days > limit!;

  /// Days left before the person's own limit is reached, or null if none set.
  int? get remaining => limit == null ? null : (limit! - days);
}
