import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/episode_kind.dart';
import '../../core/sage_tokens.dart';
import '../../data/triage/red_flag.dart';
import '../../data/triage/triage_rules.dart';
import '../../providers.dart';

/// Tier 0. The gate in front of every piece of advice this app gives.
///
/// ## Why this gates advice and not logging
///
/// Making someone answer safety questions before they can record that an
/// attack started would be the wrong trade: the log is a fact, it costs
/// nothing to be wrong about, and blocking it would push people to not log at
/// all. So Today's one-tap logging stays ungated.
///
/// Advice is different. The moment the app tells someone what to do about
/// their symptoms, it has taken on responsibility for whether that is the
/// right thing to do — and "lie down in a dark room" is actively harmful
/// guidance for a subarachnoid haemorrhage. So this screen sits in front of
/// guidance, always, and cannot be skipped or remembered-dismissed.
///
/// ## Why a tap escalates immediately
///
/// There is no Submit. Ticking a flag navigates straight to the escalation,
/// because a list of checkboxes with a button underneath is a list someone can
/// fill in and then put the phone down without pressing anything.
class SafetyCheckScreen extends ConsumerWidget {
  const SafetyCheckScreen({super.key, required this.kind, this.episodeId});

  final EpisodeKind kind;
  final String? episodeId;

  Future<void> _flag(BuildContext context, WidgetRef ref, RedFlag flag) async {
    final result = ref.read(triageServiceProvider).evaluate({flag.code});
    // Recorded for the doctor export, but never awaited in a way that could
    // delay the screen — see TriageService.record.
    unawaited(
      ref.read(triageServiceProvider).record(result, episodeId: episodeId),
    );
    if (!context.mounted) return;
    context.pushReplacement('/escalate/${flag.code}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final flags = TriageRules.forKind(kind);
    final emergency = flags
        .where((f) => f.urgency == RedFlagUrgency.emergency)
        .toList();
    final urgent = flags
        .where((f) => f.urgency == RedFlagUrgency.urgent)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Quick check first')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Any of these, right now?',
            style: context.text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Gap.h8,
          Text(
            'Tap one if it applies. If none do, carry on to what usually '
            'helps.',
            style: context.text.bodyMedium?.copyWith(color: t.inkMuted),
          ),
          Gap.h24,
          for (final f in emergency) ...[
            _FlagTile(flag: f, onTap: () => _flag(context, ref, f)),
            Gap.h8,
          ],
          if (urgent.isNotEmpty) ...[
            Gap.h16,
            Text(
              'Also worth a doctor knowing',
              style: context.text.labelLarge?.copyWith(color: t.inkMuted),
            ),
            Gap.h8,
            for (final f in urgent) ...[
              _FlagTile(flag: f, onTap: () => _flag(context, ref, f)),
              Gap.h8,
            ],
          ],
          Gap.h24,
          FilledButton(
            onPressed: () => context.pushReplacement('/guidance/${kind.code}'),
            child: const Text('None of these'),
          ),
          Gap.h16,
          Text(
            'This is a checklist, not an examination. If something feels '
            'wrong in a way this list does not cover, treat that as a reason '
            'to call someone.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: t.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({required this.flag, required this.onTap});

  final RedFlag flag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isEmergency = flag.urgency == RedFlagUrgency.emergency;
    return Material(
      color: isEmergency ? t.alertSoft : t.surface,
      borderRadius: Radii.md,
      child: InkWell(
        borderRadius: Radii.md,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: Radii.md,
            border: Border.all(color: isEmergency ? t.alert : t.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isEmergency ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 20,
                color: isEmergency ? t.alert : t.inkMuted,
              ),
              Gap.w12,
              Expanded(
                child: Text(
                  flag.question,
                  style: context.text.bodyLarge?.copyWith(
                    color: t.ink,
                    height: 1.35,
                    fontWeight: isEmergency ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
