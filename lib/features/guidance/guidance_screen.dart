import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/episode_kind.dart';
import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/guidance/guidance.dart';
import '../../providers.dart';

/// Tier 1. Only reachable through the safety check.
///
/// The route is not linked from anywhere except `SafetyCheckScreen`, and the
/// screen itself does not re-run triage — it trusts the gate in front of it.
/// If a future entry point ever needs guidance, it goes through the check
/// first; it does not deep-link here.
class GuidanceScreen extends ConsumerWidget {
  const GuidanceScreen({super.key, required this.kind});

  final EpisodeKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guidance = ref.watch(guidanceProvider(kind));

    return Scaffold(
      appBar: AppBar(title: Text('${kind.label}: what helps')),
      body: guidance.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // The steps are compiled in, so a database failure must not cost the
        // user the advice — only the personal notes are lost.
        error: (_, _) => _Body(
          guidance: Guidance(
            kind: kind,
            steps: GuidanceContent.stepsFor(kind),
            avoid: GuidanceContent.avoidFor(kind),
            personalNotes: const [],
          ),
        ),
        data: (g) => _Body(guidance: g),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.guidance});

  final Guidance guidance;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        for (var i = 0; i < guidance.steps.length; i++) ...[
          _StepTile(step: guidance.steps[i], number: i + 1),
          Gap.h8,
        ],
        if (guidance.personalNotes.isNotEmpty) ...[
          Gap.h16,
          SageSection(
            title: 'From your own log',
            child: Column(
              children: [
                for (final note in guidance.personalNotes) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: t.accentSoft,
                      borderRadius: Radii.md,
                    ),
                    child: Text(
                      note,
                      style: context.text.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        Gap.h16,
        SageSection(
          title: 'Worth avoiding until it passes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in guidance.avoid)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('—  ', style: TextStyle(color: t.inkFaint)),
                      Expanded(
                        child: Text(
                          a,
                          style: context.text.bodyMedium?.copyWith(
                            color: t.inkMuted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Gap.h24,
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surfaceAlt,
            borderRadius: Radii.md,
          ),
          child: Text(
            'General information, not medical advice. If this one is '
            'different from your usual, or it is not easing the way it '
            'normally does, that is worth telling a doctor.',
            style: context.text.bodySmall?.copyWith(
              color: t.inkMuted,
              height: 1.4,
            ),
          ),
        ),
        Gap.h16,
        OutlinedButton(
          onPressed: () => context.go('/today'),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.number});

  final GuidanceStep step;
  final int number;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: Radii.md,
        border: Border.all(color: t.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: Radii.sm,
            ),
            child: Icon(step.icon, size: 19, color: t.accent),
          ),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.text,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (step.detail != null) ...[
                  Gap.h4,
                  Text(
                    step.detail!,
                    style: context.text.bodySmall?.copyWith(
                      color: t.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
