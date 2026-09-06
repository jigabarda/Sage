import 'package:sqflite/sqflite.dart';

import '../../core/ids.dart';
import 'red_flag.dart';
import 'triage_rules.dart';

/// What the safety check concluded.
class TriageResult {
  const TriageResult(this.matched);

  const TriageResult.clear() : matched = const [];

  /// Every flag the user ticked. All of them, not the worst one — the
  /// escalation screen lists them, because a person repeating this to a nurse
  /// or a doctor should be able to read out everything that applied.
  final List<RedFlag> matched;

  bool get isClear => matched.isEmpty;

  /// Emergency beats urgent. Used only to choose the wording of the
  /// escalation, never to decide *whether* to escalate.
  RedFlagUrgency? get urgency {
    if (matched.isEmpty) return null;
    return matched.any((f) => f.urgency == RedFlagUrgency.emergency)
        ? RedFlagUrgency.emergency
        : RedFlagUrgency.urgent;
  }
}

/// Tier 0. Deterministic, offline, and always first.
///
/// This is the one component in Sage that must never become probabilistic.
/// Every other part of the app can be wrong and be corrected by editing a row;
/// this one cannot. There is no model, no scoring, no threshold and no
/// severity gate — [evaluate] is a set intersection, and it fires on a single
/// match.
class TriageService {
  TriageService(this._db);

  final Database _db;

  /// Maps ticked codes to the flags they name.
  ///
  /// Pure and synchronous so it can be exercised exhaustively in tests without
  /// a database, and so nothing about the decision depends on I/O that could
  /// fail.
  TriageResult evaluate(Set<String> tickedCodes) {
    if (tickedCodes.isEmpty) return const TriageResult.clear();
    final matched = <RedFlag>[];
    for (final code in tickedCodes) {
      final flag = TriageRules.byCode(code);
      // An unknown code is ignored rather than treated as a match. It can only
      // come from a build that has since dropped a flag, and inventing an
      // escalation from a code nothing recognises would be noise the user
      // cannot act on.
      if (flag != null) matched.add(flag);
    }
    matched.sort((a, b) => a.urgency.index.compareTo(b.urgency.index));
    return TriageResult(matched);
  }

  /// Writes a fired triage into the log.
  ///
  /// Recorded so it appears in the doctor export. "The app told me to go to
  /// A&E on the 6th and I did not" is exactly the sort of thing worth having
  /// written down, and it cannot be reconstructed later from the episode row.
  ///
  /// Best-effort: a failure here must never stop the escalation screen from
  /// showing. Getting the person to care matters more than the audit trail.
  Future<void> record(TriageResult result, {String? episodeId}) async {
    if (result.isClear) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final codes = result.matched.map((f) => f.code).join(', ');
    try {
      await _db.insert('chat_messages', {
        'id': newLocalId('msg'),
        'role': 'assistant',
        'content':
            'Safety check flagged: $codes. '
            'Advised ${result.urgency == RedFlagUrgency.emergency ? 'emergency care' : 'seeing a doctor promptly'}.',
        'tier': 'triage',
        'episode_id': episodeId,
        'created_at': now,
      });
    } catch (_) {
      // Deliberately swallowed. See above.
    }
  }
}
