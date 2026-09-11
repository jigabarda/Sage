import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/models/med.dart';
import '../../providers.dart';
import 'dose_actions.dart';

/// One-tap dose recording, on Today.
///
/// Medication used to be reachable only through Settings, which is the wrong
/// place for something done every day, and during an attack in the case of
/// rescue medication. Today is the screen opened at that moment, so the button
/// is there.
///
/// When no medications have been added, this shows nothing at all, rather than
/// a prompt to go and add one. Today is read by someone who may be in pain, and
/// a setup nudge is noise to them.
class MedQuickLog extends ConsumerWidget {
  const MedQuickLog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rescue = ref
        .watch(activeMedsProvider(MedKind.rescue))
        .maybeWhen(data: (m) => m, orElse: () => const <Med>[]);
    final preventive = ref
        .watch(activeMedsProvider(MedKind.preventive))
        .maybeWhen(data: (m) => m, orElse: () => const <Med>[]);

    // Rescue first: that is the one reached for mid-attack.
    final meds = [...rescue, ...preventive];
    if (meds.isEmpty) return const SizedBox.shrink();

    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: Radii.lg,
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Took a medication?',
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push('/meds/calendar'),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Calendar'),
              ),
            ],
          ),
          Text(
            'Tap to record it now.',
            style: context.text.bodySmall?.copyWith(color: t.inkMuted),
          ),
          Gap.h12,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in meds)
                SageChip(
                  label: m.name,
                  selected: false,
                  onTap: () => recordDoseWithUndo(context, ref, m),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
