import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../constants/episode_kind.dart';
import '../../constants/relievers.dart';
import '../../constants/symptoms.dart';
import '../../constants/triggers.dart';
import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/models/episode.dart';
import '../../data/models/med.dart';
import '../../providers.dart';

final _dateFormat = DateFormat('EEE d MMM, HH:mm');

/// Create or edit one episode.
///
/// The same screen for both, because the fields are identical and a separate
/// read-only detail view would be one more place for the two to drift.
class EpisodeEditorScreen extends ConsumerStatefulWidget {
  const EpisodeEditorScreen({super.key, this.episodeId});

  /// Null for a new episode.
  final String? episodeId;

  bool get isNew => episodeId == null;

  @override
  ConsumerState<EpisodeEditorScreen> createState() =>
      _EpisodeEditorScreenState();
}

class _EpisodeEditorScreenState extends ConsumerState<EpisodeEditorScreen> {
  EpisodeKind _kind = EpisodeKind.migraine;
  DateTime _startedAt = DateTime.now();
  DateTime? _endedAt;
  int _severity = Severity.quickLogDefault;
  final _symptoms = <String>{};
  final _triggers = <String>{};
  final _relievers = <String, EpisodeReliever>{};
  final _medIds = <String>{};
  final _notes = TextEditingController();

  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _hydrate(EpisodeDetail detail) {
    final e = detail.episode;
    _kind = e.kind;
    _startedAt = e.startedAt;
    _endedAt = e.endedAt;
    _severity = e.severity;
    _notes.text = e.notes;
    _symptoms
      ..clear()
      ..addAll(detail.symptomCodes);
    _triggers
      ..clear()
      // Only the user's own attributions are editable here. An inferred row
      // belongs to the correlation engine, and letting the editor rewrite it
      // would let a belief overwrite arithmetic.
      ..addAll(
        detail.triggers
            .where((t) => t.source == TriggerSource.user)
            .map((t) => t.triggerCode),
      );
    _relievers
      ..clear()
      ..addEntries(detail.relievers.map((r) => MapEntry(r.relieverCode, r)));
    _medIds
      ..clear()
      ..addAll(detail.medIds);
    _loaded = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(episodeRepositoryProvider);
    try {
      if (widget.isNew) {
        await repo.create(
          kind: _kind,
          startedAt: _startedAt,
          endedAt: _endedAt,
          severity: _severity,
          notes: _notes.text.trim(),
          symptomCodes: _symptoms.toList(),
          relievers: _relievers.values.toList(),
          userTriggerCodes: _triggers.toList(),
          medIds: _medIds.toList(),
        );
      } else {
        await repo.update(
          id: widget.episodeId!,
          kind: _kind,
          startedAt: _startedAt,
          endedAt: _endedAt,
          severity: _severity,
          notes: _notes.text.trim(),
          symptomCodes: _symptoms.toList(),
          relievers: _relievers.values.toList(),
          userTriggerCodes: _triggers.toList(),
          medIds: _medIds.toList(),
        );
      }
      if (!mounted) return;
      invalidateEpisodeData(ref);
      context.pop();
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message.toString())));
    }
  }

  Future<void> _confirmDelete() async {
    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this episode?'),
        content: const Text(
          'It will be removed from your history and from any patterns built '
          'on it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: t.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await ref.read(episodeRepositoryProvider).delete(widget.episodeId!);
    if (!mounted) return;
    invalidateEpisodeData(ref);
    context.pop();
  }

  Future<void> _pickMoment({required bool isStart}) async {
    final initial = isStart ? _startedAt : (_endedAt ?? DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      // No future episodes. A start time after now is always a mis-tap, and it
      // would put a row in a day the daily log cannot have data for.
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    setState(() {
      final picked = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _startedAt = picked;
      } else {
        _endedAt = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isNew && !_loaded) {
      final detail = ref.watch(episodeDetailProvider(widget.episodeId!));
      return detail.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: SageEmpty(message: 'Could not open this episode.\n$e'),
        ),
        data: (d) {
          if (d == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const SageEmpty(message: 'This episode is no longer here.'),
            );
          }
          _hydrate(d);
          return _form(context);
        },
      );
    }
    return _form(context);
  }

  Widget _form(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New episode' : 'Episode'),
        actions: [
          if (!widget.isNew)
            IconButton(
              tooltip: 'Delete',
              onPressed: _saving ? null : _confirmDelete,
              icon: Icon(Icons.delete_outline, color: t.danger),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          SageSection(
            title: 'What was it?',
            child: Row(
              children: [
                for (final k in EpisodeKind.values) ...[
                  Expanded(
                    child: SageChip(
                      label: k.label,
                      selected: _kind == k,
                      onTap: () => setState(() {
                        _kind = k;
                        // Codes are scoped per condition, so anything the other
                        // condition does not offer is dropped rather than left
                        // as an invisible orphan on the row.
                        _symptoms.removeWhere(
                          (c) => !Symptoms.forKind(k).any((s) => s.code == c),
                        );
                        _triggers.removeWhere(
                          (c) => !Triggers.forKind(k).any((tr) => tr.code == c),
                        );
                        _relievers.removeWhere(
                          (c, _) =>
                              !Relievers.forKind(k).any((r) => r.code == c),
                        );
                      }),
                    ),
                  ),
                  if (k != EpisodeKind.values.last) Gap.w12,
                ],
              ],
            ),
          ),
          Gap.h24,
          SageSection(
            title: 'How bad?',
            hint: '1 is barely there, 10 is the worst you have had.',
            child: _SeverityPicker(
              value: _severity,
              onChanged: (v) => setState(() => _severity = v),
            ),
          ),
          Gap.h24,
          SageSection(
            title: 'When',
            child: Column(
              children: [
                _MomentRow(
                  label: 'Started',
                  value: _dateFormat.format(_startedAt),
                  onTap: () => _pickMoment(isStart: true),
                ),
                Gap.h8,
                _MomentRow(
                  label: 'Ended',
                  value: _endedAt == null
                      ? 'Still going'
                      : _dateFormat.format(_endedAt!),
                  onTap: () => _pickMoment(isStart: false),
                  onClear: _endedAt == null
                      ? null
                      : () => setState(() => _endedAt = null),
                ),
              ],
            ),
          ),
          Gap.h24,
          SageSection(
            title: 'Symptoms',
            child: _CodeChips(
              options: {
                for (final s in Symptoms.forKind(_kind)) s.code: s.label,
              },
              selected: _symptoms,
              onToggle: (c) => setState(
                () => _symptoms.contains(c)
                    ? _symptoms.remove(c)
                    : _symptoms.add(c),
              ),
            ),
          ),
          Gap.h24,
          SageSection(
            title: 'What do you think set it off?',
            hint:
                'Your own hunch. Patterns are worked out separately, from '
                'what you log day to day.',
            child: _CodeChips(
              options: {
                for (final tr in Triggers.forKind(_kind)) tr.code: tr.label,
              },
              selected: _triggers,
              onToggle: (c) => setState(
                () => _triggers.contains(c)
                    ? _triggers.remove(c)
                    : _triggers.add(c),
              ),
            ),
          ),
          Gap.h24,
          SageSection(
            title: 'What did you try?',
            hint:
                'Rate one only if you know. Unrated is fine and is not '
                'counted as "no change".',
            child: _RelieverPicker(
              kind: _kind,
              chosen: _relievers,
              onToggle: (code) => setState(() {
                if (_relievers.containsKey(code)) {
                  _relievers.remove(code);
                } else {
                  _relievers[code] = EpisodeReliever(
                    relieverCode: code,
                    takenAt: DateTime.now(),
                    helped: null,
                  );
                }
              }),
              onRate: (code, v) => setState(() {
                final existing = _relievers[code]!;
                _relievers[code] = EpisodeReliever(
                  relieverCode: code,
                  takenAt: existing.takenAt,
                  helped: existing.helped == v ? null : v,
                );
              }),
            ),
          ),
          Gap.h24,
          _MedsSection(
            selected: _medIds,
            onToggle: (id) => setState(
              () => _medIds.contains(id) ? _medIds.remove(id) : _medIds.add(id),
            ),
          ),
          Gap.h24,
          SageSection(
            title: 'Anything else',
            child: TextField(
              controller: _notes,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Whatever you want to remember about this one.',
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ),
    );
  }
}

class _SeverityPicker extends StatelessWidget {
  const _SeverityPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Ten discrete targets rather than a slider: a slider needs a drag to be
    // accurate, and precise dragging is exactly what a bad migraine takes away.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = Severity.min; i <= Severity.max; i++)
          SizedBox(
            width: 52,
            height: 52,
            child: Material(
              color: i == value ? severityColor(context, i) : t.surface,
              borderRadius: Radii.md,
              child: InkWell(
                borderRadius: Radii.md,
                onTap: () => onChanged(i),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: Radii.md,
                    border: Border.all(
                      color: i == value ? severityColor(context, i) : t.line,
                    ),
                  ),
                  child: Text(
                    '$i',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: i == value
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: i == value
                          ? t.onColor(severityColor(context, i))
                          : t.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surfaceAlt,
      borderRadius: Radii.md,
      child: InkWell(
        borderRadius: Radii.md,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text(label, style: context.text.bodyMedium),
              const Spacer(),
              Text(
                value,
                style: context.text.bodyMedium?.copyWith(color: t.inkMuted),
              ),
              if (onClear != null) ...[
                Gap.w8,
                InkWell(
                  onTap: onClear,
                  child: Icon(Icons.close, size: 18, color: t.inkFaint),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeChips extends StatelessWidget {
  const _CodeChips({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in options.entries)
          SageChip(
            label: entry.value,
            selected: selected.contains(entry.key),
            onTap: () => onToggle(entry.key),
          ),
      ],
    );
  }
}

class _RelieverPicker extends StatelessWidget {
  const _RelieverPicker({
    required this.kind,
    required this.chosen,
    required this.onToggle,
    required this.onRate,
  });

  final EpisodeKind kind;
  final Map<String, EpisodeReliever> chosen;
  final ValueChanged<String> onToggle;
  final void Function(String code, int outcome) onRate;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in Relievers.forKind(kind))
              SageChip(
                label: r.label,
                selected: chosen.containsKey(r.code),
                onTap: () => onToggle(r.code),
              ),
          ],
        ),
        if (chosen.isNotEmpty) ...[
          Gap.h16,
          for (final code in chosen.keys) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: Radii.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Relievers.labelFor(code),
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Gap.h8,
                  Row(
                    children: [
                      for (final v in [
                        RelieverOutcome.helped,
                        RelieverOutcome.noChange,
                        RelieverOutcome.worse,
                      ]) ...[
                        Expanded(
                          child: SageChip(
                            label: RelieverOutcome.labelFor(v),
                            selected: chosen[code]?.helped == v,
                            onTap: () => onRate(code, v),
                          ),
                        ),
                        if (v != RelieverOutcome.worse) Gap.w8,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Which medications were taken for this episode.
///
/// Only what is currently taken is offered; something marked "no longer taken"
/// stays on past episodes but is not a choice for new ones.
///
/// The dose is recorded at the episode's *start*, not now, so filling this in
/// a week later does not move the dose into the wrong day for the rescue-use
/// count.
class _MedsSection extends ConsumerWidget {
  const _MedsSection({required this.selected, required this.onToggle});

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rescue = ref.watch(activeMedsProvider(MedKind.rescue));
    final preventive = ref.watch(activeMedsProvider(MedKind.preventive));

    final meds = <Med>[
      ...rescue.maybeWhen(data: (m) => m, orElse: () => const <Med>[]),
      ...preventive.maybeWhen(data: (m) => m, orElse: () => const <Med>[]),
    ];

    if (meds.isEmpty) {
      // No prompt to go and add one. Someone mid-form does not want to be sent
      // to a different screen, and Settings is where medications live.
      return const SizedBox.shrink();
    }

    return SageSection(
      title: 'Medication taken',
      hint:
          'Recorded against this episode, so the doctor export can show how '
          'often you have needed it.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in meds)
            SageChip(
              label: m.name,
              selected: selected.contains(m.id),
              onTap: () => onToggle(m.id),
            ),
        ],
      ),
    );
  }
}
