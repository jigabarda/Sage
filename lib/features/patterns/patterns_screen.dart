import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/insights/insight.dart';
import '../../providers.dart';

/// Tier 2. What the record shows, as arithmetic over the person's own rows.
class PatternsScreen extends ConsumerWidget {
  const PatternsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patterns'),
        actions: [
          IconButton(
            tooltip: 'Daily log',
            onPressed: () => context.push('/daily'),
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
        ],
      ),
      body: insights.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SageEmpty(message: 'Could not work these out.\n$e'),
        data: (list) => list.isEmpty
            ? const _NotYet()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Worked out from your own log. Every line says what it is '
                    'based on, so you can check it.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.t.inkMuted,
                    ),
                  ),
                  Gap.h16,
                  for (final i in list) ...[_InsightCard(insight: i), Gap.h8],
                  Gap.h16,
                  const _Caveat(),
                ],
              ),
      ),
    );
  }
}

/// The empty state, which is a real answer rather than a gap.
class _NotYet extends ConsumerWidget {
  const _NotYet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(insightsProgressProvider);
    final t = context.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      children: [
        Icon(Icons.insights_outlined, size: 36, color: t.inkFaint),
        Gap.h16,
        Text(
          'Nothing to report yet',
          textAlign: TextAlign.center,
          style: context.text.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Gap.h12,
        Text(
          note.maybeWhen(data: (n) => n, orElse: () => ''),
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(
            color: t.inkMuted,
            height: 1.45,
          ),
        ),
        Gap.h24,
        OutlinedButton(
          onPressed: () => context.push('/daily'),
          child: const Text('Fill in today'),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Strength is evidence, not urgency, so it is carried by weight rather
    // than by an alarming colour. Nothing on this screen may look like a
    // medical warning — that is Tier 0's job and its alone.
    final tint = switch (insight.strength) {
      InsightStrength.strong => t.accent,
      InsightStrength.moderate => t.inkMuted,
      InsightStrength.info => t.inkFaint,
    };

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
            child: Icon(insight.icon, size: 19, color: tint),
          ),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                Gap.h4,
                Text(
                  insight.detail,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.inkMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Caveat extends StatelessWidget {
  const _Caveat();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: Radii.md),
      child: Text(
        'These are things that happened together in your log. That is not the '
        'same as one causing the other, and something not listed here has not '
        'been ruled out — it may just not have enough days behind it yet. '
        'Worth raising with a doctor rather than acting on alone.',
        style: context.text.bodySmall?.copyWith(
          color: t.inkMuted,
          height: 1.45,
        ),
      ),
    );
  }
}
