import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/calendar_month.dart';
import '../../core/dates.dart';
import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/models/med.dart';
import '../../providers.dart';
import 'dose_actions.dart';

final _monthTitle = DateFormat('MMMM yyyy');
final _dayTitle = DateFormat('EEEE d MMMM');
final _clock = DateFormat('HH:mm');

/// A month of medication intake, one cell per day.
///
/// ## What a cell says, and what it does not
///
/// A marked cell means a dose was recorded that day, and a number means more
/// than one. That is all a cell says. There is no colour for "too much" and
/// none for "good": the limit belongs to the person (see Med.monthlyLimitDays),
/// and the Medications screen already counts against it over a rolling 30
/// days. A calendar month is the wrong window for that judgement anyway. It
/// resets on the 1st, and physiology does not.
///
/// The marker uses the accent colour, which is the brand and not a status. A
/// dose is not good news or bad news, it is just a record.
///
/// Days are local days, the same as every other figure in the app, so a 07:30
/// dose sits in the right cell wherever the phone is.
class MedCalendarScreen extends ConsumerStatefulWidget {
  const MedCalendarScreen({super.key, this.initialMedId});

  /// Opens pre-filtered to one medication, e.g. from that medication's row.
  final String? initialMedId;

  @override
  ConsumerState<MedCalendarScreen> createState() => _MedCalendarScreenState();
}

class _MedCalendarScreenState extends ConsumerState<MedCalendarScreen> {
  late CalendarMonth _month = CalendarMonth(
    DateTime.now().year,
    DateTime.now().month,
  );
  late LocalDay _selected = localDayOf(DateTime.now());
  late String? _medId = widget.initialMedId;

  LocalDay get _today => localDayOf(DateTime.now());

  bool get _atCurrentMonth => _month.isSameMonth(
    CalendarMonth(DateTime.now().year, DateTime.now().month),
  );

  void _shiftMonth(int by) {
    setState(() {
      _month = by < 0 ? _month.previous : _month.next;
      // Keep a selection inside the visible month so the list below the grid
      // never describes a day the grid is not showing. Today if it is in view,
      // otherwise the 1st.
      _selected = _month.contains(_today) ? _today : _month.firstDay;
    });
  }

  Future<void> _addDose(List<Med> activeMeds) async {
    if (activeMeds.isEmpty) return;

    // Filtered to one medication: that's the one. Otherwise ask, unless there
    // is only one to choose.
    Med? med;
    if (_medId != null) {
      med = activeMeds.where((m) => m.id == _medId).firstOrNull;
    }
    med ??= activeMeds.length == 1
        ? activeMeds.single
        : await _pickMed(activeMeds);
    if (med == null || !mounted) return;

    final day = startOfDay(_selected);
    final now = DateTime.now();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
      helpText: 'When was it taken on ${DateFormat('d MMMM').format(day)}?',
    );
    if (time == null || !mounted) return;

    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (at.isAfter(now)) {
      // A dose recorded ahead of time would count towards a day that has not
      // happened, and could push the intake figure over a limit early.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A dose can only be recorded once it has been taken.'),
        ),
      );
      return;
    }
    await recordDoseWithUndo(context, ref, med, at: at);
  }

  Future<Med?> _pickMed(List<Med> meds) {
    return showModalBottomSheet<Med>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Which one?',
                style: ctx.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final m in meds)
              ListTile(
                title: Text(m.name),
                subtitle: m.doseText.isEmpty ? null : Text(m.doseText),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final meds = ref
        .watch(medsProvider)
        .maybeWhen(data: (m) => m, orElse: () => const <Med>[]);
    final names = {for (final m in meds) m.id: m.name};
    final active = meds.where((m) => m.active).toList();
    final doses = ref.watch(
      dosesByDayProvider((
        year: _month.year,
        month: _month.month,
        medId: _medId,
      )),
    );
    final byDay = doses.maybeWhen(
      data: (d) => d,
      orElse: () => const <LocalDay, List<MedDose>>{},
    );

    final daysWithDoses = byDay.keys.where(_month.contains).length;
    final firstDayIndex = MaterialLocalizations.of(context).firstDayOfWeekIndex;

    return Scaffold(
      appBar: AppBar(title: const Text('Medication calendar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (meds.length > 1) ...[
            _MedFilter(
              meds: meds,
              selected: _medId,
              onChanged: (id) => setState(() => _medId = id),
            ),
            Gap.h16,
          ],
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _monthTitle.format(_month.first),
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                // No browsing into the future. There is nothing to record there.
                onPressed: _atCurrentMonth ? null : () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Gap.h8,
          _WeekdayHeader(firstDayIndex: firstDayIndex),
          Gap.h4,
          _MonthGrid(
            month: _month,
            firstDayIndex: firstDayIndex,
            byDay: byDay,
            today: _today,
            selected: _selected,
            onSelect: (d) => setState(() => _selected = d),
          ),
          Gap.h12,
          Text(
            daysWithDoses == 0
                ? 'No doses recorded in ${DateFormat('MMMM').format(_month.first)}.'
                : 'Doses recorded on $daysWithDoses '
                      '${daysWithDoses == 1 ? 'day' : 'days'} in '
                      '${DateFormat('MMMM').format(_month.first)}.',
            style: context.text.bodySmall?.copyWith(color: t.inkMuted),
          ),
          Gap.h24,
          _DayDetail(
            day: _selected,
            doses: byDay[_selected] ?? const [],
            names: names,
            canAdd: active.isNotEmpty && _selected <= _today,
            onAdd: () => _addDose(active),
            onDelete: (dose) => deleteDoseWithUndo(
              context,
              ref,
              dose,
              names[dose.medId] ?? 'Medication',
            ),
          ),
        ],
      ),
    );
  }
}

class _MedFilter extends StatelessWidget {
  const _MedFilter({
    required this.meds,
    required this.selected,
    required this.onChanged,
  });

  final List<Med> meds;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SageChip(
          label: 'All',
          selected: selected == null,
          onTap: () => onChanged(null),
        ),
        for (final m in meds)
          SageChip(
            label: m.name,
            selected: selected == m.id,
            onTap: () => onChanged(m.id),
          ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.firstDayIndex});

  final int firstDayIndex;

  @override
  Widget build(BuildContext context) {
    // narrowWeekdays starts on Sunday. Rotated so the header matches the
    // locale's first day, which is the same value the grid is laid out with.
    final names = MaterialLocalizations.of(context).narrowWeekdays;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  names[(firstDayIndex + i) % 7],
                  style: context.text.labelSmall?.copyWith(
                    color: context.t.inkMuted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.firstDayIndex,
    required this.byDay,
    required this.today,
    required this.selected,
    required this.onSelect,
  });

  final CalendarMonth month;
  final int firstDayIndex;
  final Map<LocalDay, List<MedDose>> byDay;
  final LocalDay today;
  final LocalDay selected;
  final ValueChanged<LocalDay> onSelect;

  @override
  Widget build(BuildContext context) {
    final blanks = month.leadingBlanks(firstDayIndex);
    final rows = month.rows(firstDayIndex);

    // Built from Rows rather than a GridView, so the height follows the
    // content inside the page's own scroll view and never nests a second one.
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _cell(context, r * 7 + c - blanks),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, int offset) {
    if (offset < 0 || offset >= month.daysInMonth) {
      return const SizedBox.shrink();
    }

    final t = context.t;
    final day = month.firstDay + offset;
    final count = byDay[day]?.length ?? 0;
    final isToday = day == today;
    final isSelected = day == selected;
    final isFuture = day > today;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSelected ? t.accentSoft : Colors.transparent,
        borderRadius: Radii.sm,
        child: InkWell(
          borderRadius: Radii.sm,
          onTap: isFuture ? null : () => onSelect(day),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: Radii.sm,
              border: isToday ? Border.all(color: t.accent, width: 1.5) : null,
            ),
            // FittedBox so a doubled system font shrinks the contents of a
            // 40dp cell rather than overflowing it. Large text is common among
            // people with migraine, not an edge case.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${offset + 1}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        color: isFuture ? t.inkFaint : t.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _Marker(count: count),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dot for one dose, the count for more.
///
/// Always the same height, marked or not, so a row of cells never jumps when
/// some days have doses and others do not.
class _Marker extends StatelessWidget {
  const _Marker({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (count == 0) return const SizedBox(height: 14);
    if (count == 1) {
      return SizedBox(
        height: 14,
        child: Center(
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
          ),
        ),
      );
    }
    return Container(
      height: 14,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: t.accent, borderRadius: Radii.pill),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: t.onAccent,
        ),
      ),
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.day,
    required this.doses,
    required this.names,
    required this.canAdd,
    required this.onAdd,
    required this.onDelete,
  });

  final LocalDay day;
  final List<MedDose> doses;
  final Map<String, String> names;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<MedDose> onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SageSection(
      title: _dayTitle.format(startOfDay(day)),
      hint: doses.isEmpty
          ? 'Nothing recorded this day.'
          : 'Tap a dose to remove it. You can undo straight away.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in doses) ...[
            Material(
              color: t.surface,
              borderRadius: Radii.md,
              child: InkWell(
                borderRadius: Radii.md,
                onTap: () => onDelete(d),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: Radii.md,
                    border: Border.all(color: t.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          names[d.medId] ?? 'Removed medication',
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (d.episodeId != null) ...[
                        Tooltip(
                          message: 'Recorded on an episode',
                          child: Icon(Icons.link, size: 16, color: t.inkFaint),
                        ),
                        Gap.w8,
                      ],
                      Text(
                        _clock.format(d.takenAt),
                        style: context.text.bodySmall?.copyWith(
                          color: t.inkMuted,
                        ),
                      ),
                      Gap.w8,
                      Icon(Icons.close, size: 16, color: t.inkFaint),
                    ],
                  ),
                ),
              ),
            ),
            Gap.h8,
          ],
          if (canAdd)
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Record a dose on this day'),
            ),
        ],
      ),
    );
  }
}
