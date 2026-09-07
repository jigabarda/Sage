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

  final DateTime createdAt;

  factory Med.fromRow(Map<String, Object?> row) => Med(
    id: row['id']! as String,
    name: row['name']! as String,
    doseText: (row['dose_text'] as String?) ?? '',
    kind: MedKind.fromCode(row['kind'] as String?),
    active: (row['active'] as int? ?? 1) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'dose_text': doseText,
    'kind': kind.code,
    'active': active ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}
