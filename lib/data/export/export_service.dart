import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../constants/episode_kind.dart';
import '../../constants/relievers.dart';
import '../../constants/symptoms.dart';
import '../../constants/triggers.dart';
import '../../core/dates.dart';
import '../insights/insights_service.dart';

final _date = DateFormat('yyyy-MM-dd');
final _dateLong = DateFormat('d MMMM yyyy');
final _time = DateFormat('HH:mm');
final _stamp = DateFormat('yyyy-MM-dd HH:mm');

/// Builds the document someone hands to a doctor.
///
/// ## Why plain text
///
/// A PDF looks nicer and costs a rendering dependency; a doctor is as happy
/// with text they can paste into a record, and text opens on every device
/// without anything installed. Markdown was rejected for the opposite reason —
/// a `.md` file opened on a phone shows the reader raw asterisks.
///
/// ## What this document must always do
///
/// - **Say that everything in it is self-reported, at the top.** A clinician
///   reading a tidy generated document can reasonably mistake it for measured
///   data unless it says otherwise before they start.
/// - **Never present a medication dose as a prescription.** `meds.dose_text`
///   is free text the user typed and is reproduced verbatim, labelled as
///   theirs.
/// - **Carry the correlational caveat next to the patterns**, not in a footer.
/// - **Include every safety check that fired.** That was designed into Tier 0
///   for this: "the app told me to go to A&E on the 6th and I did not" is
///   exactly the sort of thing worth a doctor seeing, and it cannot be
///   reconstructed from the episode rows.
class ExportService {
  ExportService(this._db, this._insights);

  final Database _db;
  final InsightsService _insights;

  /// A suggested filename. Dated so two exports do not overwrite each other.
  String get suggestedFileName =>
      'sage-log-${_date.format(DateTime.now())}.txt';

  Future<String> buildReport({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final b = StringBuffer();

    _header(b, at);
    await _coverage(b);
    await _summary(b);
    await _patterns(b);
    await _medications(b);
    await _safetyChecks(b);
    await _episodeLog(b);
    _footer(b);

    return b.toString();
  }

  void _header(StringBuffer b, DateTime at) {
    b.writeln('SAGE — MIGRAINE AND REFLUX LOG');
    b.writeln('Prepared ${_dateLong.format(at)}');
    b.writeln();
    // Before anything else, so it is read before the numbers are.
    b.writeln(
      'Everything below is self-reported by the person using the app. Nothing\n'
      'here is measured, diagnosed or clinically verified. Severity is their\n'
      'own 1-10 rating.',
    );
    b.writeln();
  }

  Future<void> _coverage(StringBuffer b) async {
    // The period spans both tables, not episodes alone. Someone fills in the
    // daily log on days they had nothing, so an episode-derived period
    // reported "40 of 37 days" — more context entries than days in the period.
    // Visibly wrong, in a document whose whole job is to be trusted.
    final range = await _db.rawQuery(
      'SELECT MIN(d) AS a, MAX(d) AS z FROM ('
      ' SELECT MIN(started_day) AS d FROM episodes'
      ' UNION ALL SELECT MAX(started_day) FROM episodes'
      ' UNION ALL SELECT MIN(local_day) FROM daily_log'
      ' UNION ALL SELECT MAX(local_day) FROM daily_log'
      ')',
    );
    final a = range.single['a'] as int?;
    final z = range.single['z'] as int?;

    b.writeln('PERIOD');
    if (a == null || z == null) {
      b.writeln('  Nothing recorded yet.');
      b.writeln();
      return;
    }

    final span = z - a + 1;
    // Counted inside the period, so the two figures are commensurable.
    final loggedDays =
        (await _db.rawQuery(
              'SELECT COUNT(*) AS n FROM daily_log '
              'WHERE local_day >= ? AND local_day <= ?',
              [a, z],
            )).single['n']
            as int? ??
        0;

    b.writeln(
      '  ${_dateLong.format(startOfDay(a))} to ${_dateLong.format(startOfDay(z))}'
      '  ($span days)',
    );
    b.writeln(
      '  Days with a context entry (sleep, stress, meals): '
      '$loggedDays of $span',
    );
    b.writeln();
  }

  Future<void> _summary(StringBuffer b) async {
    b.writeln('SUMMARY');
    for (final kind in EpisodeKind.values) {
      final rows = await _db.query(
        'episodes',
        columns: ['severity', 'started_at', 'ended_at'],
        where: 'kind = ?',
        whereArgs: [kind.code],
      );
      if (rows.isEmpty) {
        b.writeln('  ${kind.label.padRight(9)} none recorded');
        continue;
      }

      final severities = rows.map((r) => r['severity']! as int).toList()
        ..sort();
      final durations =
          rows
              .where((r) => r['ended_at'] != null)
              .map((r) => (r['ended_at']! as int) - (r['started_at']! as int))
              .toList()
            ..sort();

      final sev = _median(severities.map((e) => e.toDouble()).toList());
      // Median rather than mean throughout: one 40-hour episode would drag a
      // mean into a figure that describes none of them.
      final dur = durations.isEmpty
          ? null
          : Duration(
              milliseconds: _median(
                durations.map((e) => e.toDouble()).toList(),
              ).round(),
            );

      b.write(
        '  ${kind.label.padRight(9)} ${rows.length} episodes, '
        'median severity ${sev.toStringAsFixed(0)}/10',
      );
      if (dur != null) {
        b.write(', median duration ${_duration(dur)}');
        if (durations.length < rows.length) {
          b.write(' (from ${durations.length} with an end time)');
        }
      }
      b.writeln();
    }
    b.writeln();
  }

  Future<void> _patterns(StringBuffer b) async {
    final found = await _insights.all();
    b.writeln('PATTERNS IN THE LOG');
    if (found.isEmpty) {
      b.writeln('  Nothing has cleared the app\'s evidence threshold yet.');
      b.writeln();
      return;
    }
    // The caveat sits with the findings, not in a footer nobody reaches.
    b.writeln(
      '  Worked out by counting, not by a model. These are things that',
    );
    b.writeln('  occurred together in the log; that is not the same as one');
    b.writeln('  causing the other, and anything absent may simply not have');
    b.writeln('  enough days behind it yet.');
    b.writeln();
    for (final i in found) {
      b.writeln('  - ${i.detail}');
    }
    b.writeln();
  }

  Future<void> _medications(StringBuffer b) async {
    final rows = await _db.query('meds', orderBy: 'name ASC');
    b.writeln('MEDICATIONS THE PERSON RECORDED');
    if (rows.isEmpty) {
      b.writeln('  None recorded.');
      b.writeln();
      return;
    }
    b.writeln(
      '  Names and doses below are free text the person typed. The app',
    );
    b.writeln('  does not suggest, complete or check them, and they are not a');
    b.writeln('  prescription record.');
    b.writeln();
    for (final r in rows) {
      final dose = (r['dose_text'] as String?) ?? '';
      final kind = r['kind'] == 'preventive' ? 'preventive' : 'rescue';
      final active = (r['active'] as int? ?? 1) == 1 ? '' : ' (no longer used)';
      b.writeln(
        '  - ${r['name']}'
        '${dose.isEmpty ? '' : ' — "$dose"'} [$kind]$active',
      );
    }
    b.writeln();
  }

  Future<void> _safetyChecks(StringBuffer b) async {
    final rows = await _db.query(
      'chat_messages',
      where: 'tier = ?',
      whereArgs: ['triage'],
      orderBy: 'created_at ASC',
    );
    b.writeln('SAFETY CHECKS THAT FLAGGED');
    if (rows.isEmpty) {
      b.writeln('  None.');
      b.writeln();
      return;
    }
    b.writeln('  Times the app stopped giving self-care advice and said to');
    b.writeln('  seek care. Whether the person acted on it is not recorded.');
    b.writeln();
    for (final r in rows) {
      final when = DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int);
      b.writeln('  ${_stamp.format(when)}  ${r['content']}');
    }
    b.writeln();
  }

  Future<void> _episodeLog(StringBuffer b) async {
    final episodes = await _db.query('episodes', orderBy: 'started_at ASC');
    b.writeln('EPISODE LOG');
    if (episodes.isEmpty) {
      b.writeln('  Nothing recorded.');
      b.writeln();
      return;
    }

    // Bulk-loaded and grouped in Dart rather than a detail query per episode.
    // A few hundred episodes would otherwise be a few hundred round trips.
    final symptoms = await _groupBy('episode_symptoms', 'symptom_code');
    final relievers = await _relieversByEpisode();
    final triggers = await _groupBy(
      'episode_triggers',
      'trigger_code',
      where: "source = 'user'",
    );

    for (final e in episodes) {
      final id = e['id']! as String;
      final started = DateTime.fromMillisecondsSinceEpoch(
        e['started_at']! as int,
      );
      final endedMs = e['ended_at'] as int?;
      final kind = EpisodeKind.fromCode(e['kind']! as String);

      final duration = endedMs == null
          ? 'still open'
          : _duration(
              Duration(milliseconds: endedMs - (e['started_at']! as int)),
            );

      b.writeln(
        '  ${_date.format(started)}  ${_time.format(started)}  '
        '${kind.label.padRight(9)} ${e['severity']}/10  $duration',
      );

      final s = symptoms[id];
      if (s != null && s.isNotEmpty) {
        b.writeln('      symptoms:  ${s.map(Symptoms.labelFor).join(', ')}');
      }
      final t = triggers[id];
      if (t != null && t.isNotEmpty) {
        // Labelled as the person's own attribution, because that is what it
        // is — the app's own correlation findings are in PATTERNS above.
        b.writeln(
          '      they thought:  ${t.map(Triggers.labelFor).join(', ')}',
        );
      }
      final r = relievers[id];
      if (r != null && r.isNotEmpty) {
        b.writeln('      tried:  ${r.join(', ')}');
      }
      final notes = (e['notes'] as String?) ?? '';
      if (notes.trim().isNotEmpty) {
        b.writeln('      note:  ${notes.trim().replaceAll('\n', ' ')}');
      }
    }
    b.writeln();
  }

  void _footer(StringBuffer b) {
    b.writeln('---');
    b.writeln('Produced by Sage, an offline log kept on the person\'s own');
    b.writeln('phone. No part of this was reviewed by a clinician.');
  }

  Future<Map<String, List<String>>> _groupBy(
    String table,
    String column, {
    String? where,
  }) async {
    final rows = await _db.query(table, where: where);
    final out = <String, List<String>>{};
    for (final r in rows) {
      (out[r['episode_id']! as String] ??= []).add(r[column]! as String);
    }
    return out;
  }

  Future<Map<String, List<String>>> _relieversByEpisode() async {
    final rows = await _db.query('episode_relievers', orderBy: 'taken_at ASC');
    final out = <String, List<String>>{};
    for (final r in rows) {
      final label = Relievers.labelFor(r['reliever_code']! as String);
      final helped = r['helped'] as int?;
      // "not rated" is written out rather than left blank, so an unrated
      // attempt is visibly unrated instead of looking like it did nothing.
      final verdict = switch (helped) {
        1 => 'helped',
        0 => 'no change',
        -1 => 'worse',
        _ => 'not rated',
      };
      (out[r['episode_id']! as String] ??= []).add('$label ($verdict)');
    }
    return out;
  }

  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static String _duration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
