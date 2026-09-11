import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/models/med.dart';
import '../../data/repositories/meds_repository.dart';
import '../../providers.dart';
import 'dose_actions.dart';

final _doseStamp = DateFormat('d MMM, HH:mm');

/// Medications, and how much of them has been taken lately.
///
/// There is no autocomplete, no drug database and no interaction check, and
/// that absence is the design. A field offering completions would imply the app
/// knew what the drug was and had checked something about it — non-negotiable 6.
///
/// ## How intake is reported
///
/// Every figure is over a rolling 30 days, and the unit is **days used**, not
/// doses — because that is how limits are given. Two tablets in one afternoon
/// is one day.
///
/// The app never sets a limit and never suggests one. Where a limit appears it
/// came from the person or from what their doctor told them, and all the app
/// does is count against it.
class MedsScreen extends ConsumerWidget {
  const MedsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    Med? existing,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MedSheet(existing: existing),
    );
    if (saved == true) invalidateMedData(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(medIntakeProvider);
    final t = context.t;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medications'),
        actions: [
          IconButton(
            tooltip: 'Calendar',
            onPressed: () => context.push('/meds/calendar'),
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Add',
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: intake.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SageEmpty(message: 'Could not read these.\n$e'),
        data: (list) {
          if (list.isEmpty) {
            return const SageEmpty(
              message:
                  'Nothing added yet.\n\n'
                  'Adding what you take lets you record each dose, see how '
                  'many days you have used it, and put it in the doctor '
                  'export in your own words.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surfaceAlt,
                  borderRadius: Radii.md,
                ),
                child: Text(
                  'Counts are over the last ${MedsRepository.windowDays} days '
                  'and are in days used, not doses — two in one afternoon is '
                  'one day.\n\n'
                  'Sage stores everything here exactly as you type it. It does '
                  'not suggest doses or limits, check interactions, or know '
                  'what any of it means.',
                  style: context.text.bodySmall?.copyWith(
                    color: t.inkMuted,
                    height: 1.45,
                  ),
                ),
              ),
              Gap.h16,
              for (final i in list) ...[
                _IntakeRow(
                  intake: i,
                  onTap: () => _edit(context, ref, existing: i.med),
                  onLog: i.med.active
                      ? () => recordDoseWithUndo(context, ref, i.med)
                      : null,
                ),
                Gap.h8,
              ],
              Gap.h24,
              const _RecentDoses(),
            ],
          );
        },
      ),
    );
  }
}

class _IntakeRow extends StatelessWidget {
  const _IntakeRow({
    required this.intake,
    required this.onTap,
    required this.onLog,
  });

  final MedIntake intake;
  final VoidCallback onTap;
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final med = intake.med;
    final limit = intake.limit;

    // Over the person's own limit uses the severity scale, not `alert`. Alert
    // is reserved for red-flag escalation, and spending it here would blunt
    // the one signal that must never be ignorable.
    final countColour = intake.overLimit ? t.severityHigh : t.accent;

    return Material(
      color: t.surface,
      borderRadius: Radii.md,
      child: InkWell(
        borderRadius: Radii.md,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: Radii.md,
            border: Border.all(
              color: intake.overLimit ? t.severityHigh : t.line,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.name,
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: med.active
                            ? null
                            : TextDecoration.lineThrough,
                        color: med.active ? t.ink : t.inkFaint,
                      ),
                    ),
                    Gap.h4,
                    Text(
                      [
                        med.kind.label,
                        if (med.doseText.isNotEmpty) med.doseText,
                        if (!med.active) 'no longer taken',
                      ].join(' · '),
                      style: context.text.bodySmall?.copyWith(
                        color: t.inkMuted,
                      ),
                    ),
                    Gap.h8,
                    Text(
                      limit == null
                          ? 'Used on ${intake.days} of the last '
                                '${intake.windowDays} days'
                          : 'Used on ${intake.days} of the last '
                                '${intake.windowDays} days, against the $limit '
                                'you set',
                      style: context.text.bodySmall?.copyWith(
                        color: countColour,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onLog != null)
                IconButton(
                  tooltip: 'Record a dose now',
                  onPressed: onLog,
                  icon: const Icon(Icons.add_circle_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The last few doses, so a mistake noticed later can still be fixed.
///
/// A record someone cannot correct is one they stop trusting, and an intake
/// count is only worth having if the person believes it.
class _RecentDoses extends ConsumerWidget {
  const _RecentDoses();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final doses = ref.watch(recentDosesProvider);
    final meds = ref.watch(medsProvider);

    return doses.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final names = meds.maybeWhen(
          data: (m) => {for (final x in m) x.id: x.name},
          orElse: () => const <String, String>{},
        );

        return SageSection(
          title: 'Recent doses',
          hint:
              'Tap one to remove it if it was recorded by mistake. You can undo '
              'straight away.',
          child: Column(
            children: [
              for (final d in list.take(15))
                Material(
                  color: t.surfaceAlt,
                  borderRadius: Radii.sm,
                  child: InkWell(
                    borderRadius: Radii.sm,
                    onTap: () => deleteDoseWithUndo(
                      context,
                      ref,
                      d,
                      names[d.medId] ?? 'Medication',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              names[d.medId] ?? 'Removed medication',
                              style: context.text.bodySmall,
                            ),
                          ),
                          Text(
                            _doseStamp.format(d.takenAt),
                            style: context.text.bodySmall?.copyWith(
                              color: t.inkMuted,
                            ),
                          ),
                          if (d.episodeId != null) ...[
                            Gap.w8,
                            Icon(Icons.link, size: 14, color: t.inkFaint),
                          ],
                          Gap.w8,
                          Icon(Icons.close, size: 15, color: t.inkFaint),
                        ],
                      ),
                    ),
                  ),
                ),
              Gap.h8,
              Text(
                'A linked dose was recorded on an episode. Removing it here '
                'does not change the episode.',
                style: context.text.bodySmall?.copyWith(color: t.inkFaint),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MedSheet extends ConsumerStatefulWidget {
  const _MedSheet({this.existing});

  final Med? existing;

  @override
  ConsumerState<_MedSheet> createState() => _MedSheetState();
}

class _MedSheetState extends ConsumerState<_MedSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _dose = TextEditingController(
    text: widget.existing?.doseText ?? '',
  );
  late final _limit = TextEditingController(
    text: widget.existing?.monthlyLimitDays?.toString() ?? '',
  );
  late MedKind _kind = widget.existing?.kind ?? MedKind.rescue;
  late bool _active = widget.existing?.active ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _limit.dispose();
    super.dispose();
  }

  /// Null for blank, which is "no limit set" rather than a limit of zero.
  int? get _parsedLimit {
    final raw = _limit.text.trim();
    if (raw.isEmpty) return null;
    final n = int.tryParse(raw);
    if (n == null || n < 0 || n > MedsRepository.windowDays) return null;
    return n;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A name is needed.');
      return;
    }
    if (_limit.text.trim().isNotEmpty && _parsedLimit == null) {
      setState(
        () => _error =
            'A limit has to be a whole number of days, 0 to ${MedsRepository.windowDays}.',
      );
      return;
    }

    final repo = ref.read(medsRepositoryProvider);
    if (widget.existing == null) {
      await repo.create(
        name: _name.text,
        doseText: _dose.text,
        kind: _kind,
        monthlyLimitDays: _parsedLimit,
      );
    } else {
      await repo.update(
        widget.existing!.id,
        name: _name.text,
        doseText: _dose.text,
        kind: _kind,
        active: _active,
        monthlyLimitDays: _parsedLimit,
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final med = widget.existing!;
    final doses = await ref.read(medsRepositoryProvider).doseCount(med.id);
    if (!mounted) return;

    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${med.name}?'),
        content: Text(
          doses == 0
              ? 'It has no recorded doses, so nothing else is affected.'
              : 'This also deletes $doses recorded ${doses == 1 ? 'dose' : 'doses'}, '
                    'and they will no longer appear in the doctor export. If you '
                    'have simply stopped taking it, mark it "no longer taken" '
                    'instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
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

    await ref.read(medsRepositoryProvider).delete(med.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? 'Add a medication' : 'Edit',
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap.h16,
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            Gap.h12,
            TextField(
              controller: _dose,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'How you take it',
                hintText: 'e.g. two at onset — in your own words',
              ),
            ),
            Gap.h16,
            Row(
              children: [
                for (final k in MedKind.values) ...[
                  Expanded(
                    child: SageChip(
                      label: k.label,
                      selected: _kind == k,
                      onTap: () => setState(() => _kind = k),
                    ),
                  ),
                  if (k != MedKind.values.last) Gap.w8,
                ],
              ],
            ),
            Gap.h4,
            Text(
              _kind.hint,
              style: context.text.bodySmall?.copyWith(color: t.inkMuted),
            ),
            Gap.h16,
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Days per month you are aiming to stay under',
                hintText: 'Leave blank for no limit',
                helperMaxLines: 4,
                // Says whose number it is. The app has no view on what a safe
                // figure would be and must not appear to.
                helperText:
                    'Optional, and Sage never fills this in. Use whatever you '
                    'or your doctor decided — it only counts against it.',
              ),
            ),
            if (widget.existing != null) ...[
              Gap.h16,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Still taking this',
                      style: context.text.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              Gap.h12,
              Text(_error!, style: TextStyle(color: t.danger)),
            ],
            Gap.h24,
            Row(
              children: [
                if (widget.existing != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.danger,
                      ),
                      child: const Text('Delete'),
                    ),
                  ),
                  Gap.w12,
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
