import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/insights/cycle.dart';
import '../../data/models/daily_log.dart';
import '../../data/settings/cycle_tracking.dart';
import '../../providers.dart';

final _dayLabel = DateFormat('EEEE d MMMM');

/// The substrate the correlation engine runs on.
///
/// ## Why every control can be left blank, and can be cleared again
///
/// A blank measure is recorded as null and means "not recorded". The rules
/// read that as *no evidence* about that measure, which is different from
/// evidence of zero — a day where someone logged their sleep but not their
/// stress says nothing about stress, and counting it as a calm day would let
/// the stress rule find a pattern in people's forgetfulness.
///
/// So there is no sensible default here and nothing is pre-filled. Every
/// control starts blank and can be put back to blank.
class DailyLogScreen extends ConsumerStatefulWidget {
  const DailyLogScreen({super.key});

  @override
  ConsumerState<DailyLogScreen> createState() => _DailyLogScreenState();
}

class _DailyLogScreenState extends ConsumerState<DailyLogScreen> {
  late LocalDay _day = localDayOf(DateTime.now());
  DailyLog? _draft;
  LocalDay? _loadedFor;
  bool _saving = false;

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    await ref.read(dailyLogRepositoryProvider).save(draft);
    if (!mounted) return;
    invalidateDailyData(ref);
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Saved')));
  }

  void _shiftDay(int by) {
    final next = _day + by;
    // No logging the future. There is nothing to remember about tomorrow, and
    // a row there would sit in every rule's window as a day with no episodes.
    if (next > localDayOf(DateTime.now())) return;
    setState(() {
      _day = next;
      _draft = null;
      _loadedFor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final async = ref.watch(dailyLogForDayProvider(_day));

    return Scaffold(
      appBar: AppBar(title: const Text('Daily log')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SageEmpty(message: 'Could not read the day.\n$e'),
        data: (stored) {
          if (_loadedFor != _day) {
            _draft = stored;
            _loadedFor = _day;
          }
          final d = _draft!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              _DayNav(
                day: _day,
                onPrev: () => _shiftDay(-1),
                onNext: _day >= localDayOf(DateTime.now())
                    ? null
                    : () => _shiftDay(1),
              ),
              Gap.h8,
              Text(
                'Leave anything you did not track blank. Blank means "not '
                'recorded", and the patterns treat that differently from zero.',
                style: context.text.bodySmall?.copyWith(color: t.inkMuted),
              ),
              Gap.h24,
              _Stepper(
                label: 'Sleep last night',
                value: d.sleepHours,
                unit: 'hours',
                step: 0.5,
                min: 0,
                max: 16,
                format: (v) => v == v.roundToDouble()
                    ? '${v.toInt()}'
                    : v.toStringAsFixed(1),
                onChanged: (v) => setState(
                  () =>
                      _draft = d.copyWith(sleepHours: v, clearSleep: v == null),
                ),
              ),
              _IntStepper(
                label: 'Stress',
                value: d.stressLevel,
                unit: 'of 5',
                min: 1,
                max: 5,
                onChanged: (v) => setState(
                  () => _draft = d.copyWith(
                    stressLevel: v,
                    clearStress: v == null,
                  ),
                ),
              ),
              _IntStepper(
                label: 'Meals skipped',
                value: d.mealsSkipped,
                min: 0,
                max: 5,
                onChanged: (v) => setState(
                  () => _draft = d.copyWith(
                    mealsSkipped: v,
                    clearMealsSkipped: v == null,
                  ),
                ),
              ),
              _IntStepper(
                label: 'Caffeinated drinks',
                value: d.caffeineUnits,
                min: 0,
                max: 12,
                onChanged: (v) => setState(
                  () => _draft = d.copyWith(
                    caffeineUnits: v,
                    clearCaffeine: v == null,
                  ),
                ),
              ),
              _IntStepper(
                label: 'Alcohol',
                value: d.alcoholUnits,
                unit: 'drinks',
                min: 0,
                max: 20,
                onChanged: (v) => setState(
                  () => _draft = d.copyWith(
                    alcoholUnits: v,
                    clearAlcohol: v == null,
                  ),
                ),
              ),
              _IntStepper(
                label: 'Water',
                value: d.waterGlasses,
                unit: 'glasses',
                min: 0,
                max: 20,
                onChanged: (v) => setState(
                  () => _draft = d.copyWith(
                    waterGlasses: v,
                    clearWater: v == null,
                  ),
                ),
              ),
              if (ref.watch(cycleTrackingProvider)) ...[
                Gap.h16,
                _CycleSection(
                  day: _day,
                  value: d.cycleDay,
                  onChanged: (v) => setState(
                    () => _draft = d.copyWith(
                      cycleDay: v,
                      clearCycleDay: v == null,
                    ),
                  ),
                ),
                Gap.h8,
              ],
              Gap.h8,
              _Tristate(
                label: 'Ate within about 3 hours of lying down',
                value: d.lateMeal,
                onChanged: (v) => setState(
                  () => _draft = d.copyWith(
                    lateMeal: v,
                    clearLateMeal: v == null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        child: FilledButton(
          onPressed: _saving || _draft == null ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ),
    );
  }
}

class _DayNav extends StatelessWidget {
  const _DayNav({required this.day, required this.onPrev, this.onNext});

  final LocalDay day;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final isToday = day == localDayOf(DateTime.now());
    return Row(
      children: [
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(
            isToday ? 'Today' : _dayLabel.format(startOfDay(day)),
            textAlign: TextAlign.center,
            style: context.text.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

/// Shared chrome for a measure that can be blank.
class _MeasureRow extends StatelessWidget {
  const _MeasureRow({
    required this.label,
    required this.display,
    required this.isSet,
    required this.onClear,
    required this.controls,
  });

  final String label;
  final String display;
  final bool isSet;
  final VoidCallback onClear;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSet ? t.surface : t.surfaceAlt,
        borderRadius: Radii.md,
        border: Border.all(color: isSet ? t.line : Colors.transparent),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.bodyMedium),
                Text(
                  display,
                  style: context.text.bodySmall?.copyWith(
                    color: isSet ? t.accent : t.inkFaint,
                    fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (isSet)
            IconButton(
              tooltip: 'Leave blank',
              onPressed: onClear,
              icon: Icon(Icons.backspace_outlined, size: 18, color: t.inkFaint),
            ),
          controls,
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    required this.format,
    this.unit,
  });

  final String label;
  final double? value;
  final double min;
  final double max;
  final double step;
  final String? unit;
  final String Function(double) format;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return _MeasureRow(
      label: label,
      display: v == null
          ? 'Not recorded'
          : '${format(v)}${unit == null ? '' : ' $unit'}',
      isSet: v != null,
      onClear: () => onChanged(null),
      controls: Row(
        children: [
          IconButton(
            onPressed: v == null || v <= min
                ? null
                : () => onChanged((v - step).clamp(min, max)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            // The first tap sets a starting value rather than incrementing
            // from an implied zero, so touching the control never silently
            // records something the person did not mean.
            onPressed: () =>
                onChanged(v == null ? 7 : (v + step).clamp(min, max)),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _IntStepper extends StatelessWidget {
  const _IntStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit,
  });

  final String label;
  final int? value;
  final int min;
  final int max;
  final String? unit;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return _MeasureRow(
      label: label,
      display: v == null ? 'Not recorded' : '$v${unit == null ? '' : ' $unit'}',
      isSet: v != null,
      onClear: () => onChanged(null),
      controls: Row(
        children: [
          IconButton(
            onPressed: v == null || v <= min
                ? null
                : () => onChanged((v - 1).clamp(min, max)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            onPressed: () =>
                onChanged(v == null ? min : (v + 1).clamp(min, max)),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

/// Yes / No / blank. Three states, because "no" and "did not record" are
/// different answers and the reflux rule depends on telling them apart.
class _Tristate extends StatelessWidget {
  const _Tristate({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: value == null ? t.surfaceAlt : t.surface,
        borderRadius: Radii.md,
        border: Border.all(color: value == null ? Colors.transparent : t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodyMedium),
          Gap.h12,
          Row(
            children: [
              Expanded(
                child: SageChip(
                  label: 'Yes',
                  selected: value == true,
                  onTap: () => onChanged(value == true ? null : true),
                ),
              ),
              Gap.w8,
              Expanded(
                child: SageChip(
                  label: 'No',
                  selected: value == false,
                  onTap: () => onChanged(value == false ? null : false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The cycle question, shown only when tracking is switched on.
///
/// Day 1 is the first day of a period, and it is the only value the app really
/// needs: every other day number and the whole perimenstrual rule are derived
/// from the days recorded as 1. So "Period started today" is the prominent
/// control, and the day number is a secondary field that fills itself in.
class _CycleSection extends ConsumerWidget {
  const _CycleSection({
    required this.day,
    required this.value,
    required this.onChanged,
  });

  final LocalDay day;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final starts = ref
        .watch(periodStartsProvider)
        .maybeWhen(data: (s) => s, orElse: () => const <LocalDay>[]);

    // Counted from the last recorded start, so nobody has to work it out.
    // Null when there is nothing to count from, or when the answer would be
    // absurd — see Cycle.dayNumberFor.
    final suggested = Cycle.dayNumberFor(day, starts);
    final isStart = value == 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: value == null ? t.surfaceAlt : t.surface,
        borderRadius: Radii.md,
        border: Border.all(color: value == null ? Colors.transparent : t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Menstrual cycle', style: context.text.bodyMedium),
          Gap.h12,
          SageChip(
            label: 'Period started today',
            selected: isStart,
            onTap: () => onChanged(isStart ? null : 1),
          ),
          Gap.h12,
          Row(
            children: [
              Expanded(
                child: Text(
                  value == null ? 'Cycle day not recorded' : 'Cycle day $value',
                  style: context.text.bodySmall?.copyWith(
                    color: value == null ? t.inkFaint : t.accent,
                    fontWeight: value == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                ),
              ),
              if (value != null)
                IconButton(
                  tooltip: 'Leave blank',
                  onPressed: () => onChanged(null),
                  icon: Icon(
                    Icons.backspace_outlined,
                    size: 18,
                    color: t.inkFaint,
                  ),
                ),
              IconButton(
                onPressed: value == null || value! <= 1
                    ? null
                    : () => onChanged(value! - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                onPressed: () => onChanged(
                  value == null ? (suggested ?? 1) : (value! + 1).clamp(1, 60),
                ),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (value == null && suggested != null)
            Text(
              'Counting from your last recorded period, today would be day '
              '$suggested.',
              style: context.text.bodySmall?.copyWith(color: t.inkMuted),
            ),
        ],
      ),
    );
  }
}
