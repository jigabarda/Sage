import 'package:flutter/foundation.dart';

import '../../constants/episode_kind.dart';
import '../../core/dates.dart';

/// One row of `episodes`, without its children.
///
/// The history list renders hundreds of these, so loading symptoms and
/// relievers alongside would be an N+1 for data no row in a list shows. Use
/// [EpisodeDetail] when the children are actually needed.
@immutable
class Episode {
  const Episode({
    required this.id,
    required this.kind,
    required this.startedAt,
    required this.endedAt,
    required this.severity,
    required this.notes,
    required this.startedDay,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final EpisodeKind kind;
  final DateTime startedAt;

  /// Null while the episode is still going.
  final DateTime? endedAt;

  final int severity;
  final String notes;

  /// Denormalised local day of [startedAt]. Written by the repository, never
  /// by a caller — see [EpisodeRepository].
  final LocalDay startedDay;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOngoing => endedAt == null;

  /// How long it lasted, or how long it has been going so far.
  ///
  /// Callers that display this for an ongoing episode need to rebuild on a
  /// timer; it is computed from `DateTime.now()` and will not change on its
  /// own.
  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  SeverityBand get band => Severity.bandOf(severity);

  factory Episode.fromRow(Map<String, Object?> row) => Episode(
    id: row['id']! as String,
    kind: EpisodeKind.fromCode(row['kind']! as String),
    startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at']! as int),
    endedAt: row['ended_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['ended_at']! as int),
    severity: row['severity']! as int,
    notes: row['notes']! as String,
    startedDay: row['started_day']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'kind': kind.code,
    'started_at': startedAt.millisecondsSinceEpoch,
    'ended_at': endedAt?.millisecondsSinceEpoch,
    'severity': severity,
    'notes': notes,
    'started_day': startedDay,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  Episode copyWith({
    EpisodeKind? kind,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
    int? severity,
    String? notes,
    LocalDay? startedDay,
    DateTime? updatedAt,
  }) => Episode(
    id: id,
    kind: kind ?? this.kind,
    startedAt: startedAt ?? this.startedAt,
    // A nullable field needs an explicit clear flag: `endedAt: null` in a
    // copyWith is indistinguishable from "leave it alone", and silently
    // re-opening a closed episode is the bug that causes.
    endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
    severity: severity ?? this.severity,
    notes: notes ?? this.notes,
    startedDay: startedDay ?? this.startedDay,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A reliever attempt on an episode.
@immutable
class EpisodeReliever {
  const EpisodeReliever({
    required this.relieverCode,
    required this.takenAt,
    required this.helped,
  });

  final String relieverCode;
  final DateTime takenAt;

  /// `RelieverOutcome`, or null for unrated. Null is not neutral — the
  /// effectiveness rule counts rated attempts only.
  final int? helped;

  factory EpisodeReliever.fromRow(Map<String, Object?> row) => EpisodeReliever(
    relieverCode: row['reliever_code']! as String,
    takenAt: DateTime.fromMillisecondsSinceEpoch(row['taken_at']! as int),
    helped: row['helped'] as int?,
  );
}

/// A trigger the user attributed to an episode.
@immutable
class EpisodeTrigger {
  const EpisodeTrigger({required this.triggerCode, required this.source});

  final String triggerCode;

  /// `TriggerSource.user` or `TriggerSource.inferred`.
  final String source;

  factory EpisodeTrigger.fromRow(Map<String, Object?> row) => EpisodeTrigger(
    triggerCode: row['trigger_code']! as String,
    source: row['source']! as String,
  );
}

/// An episode with everything attached to it.
@immutable
class EpisodeDetail {
  const EpisodeDetail({
    required this.episode,
    required this.symptomCodes,
    required this.relievers,
    required this.triggers,
  });

  final Episode episode;
  final List<String> symptomCodes;
  final List<EpisodeReliever> relievers;
  final List<EpisodeTrigger> triggers;
}
