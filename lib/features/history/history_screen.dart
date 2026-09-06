import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/models/episode.dart';
import '../../providers.dart';

final _dayHeader = DateFormat('EEEE d MMMM');
final _timeOnly = DateFormat('HH:mm');

/// Every episode, newest first, grouped by the day it started.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodes = ref.watch(recentEpisodesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            tooltip: 'Log a past episode',
            onPressed: () => context.push('/episode/new'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: episodes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SageEmpty(message: 'Could not read the log.\n$e'),
        data: (list) {
          if (list.isEmpty) {
            // Neutral, not congratulatory. An empty log means the app is new,
            // and even if it did mean a quiet stretch, that is not an
            // achievement to celebrate — see the design rules.
            return const SageEmpty(
              message:
                  'Nothing logged yet.\n\n'
                  'When something starts, one tap on Today records the time.',
            );
          }

          // Grouped as it is rendered rather than pre-bucketed: the list is
          // already sorted, so a header is simply a row whose day differs from
          // the one before it.
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final e = list[i];
              final prev = i == 0 ? null : list[i - 1];
              final newDay = prev == null || prev.startedDay != e.startedDay;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (newDay) ...[
                    if (i != 0) Gap.h24,
                    Text(
                      _dayHeader.format(startOfDay(e.startedDay)),
                      style: context.text.labelLarge?.copyWith(
                        color: context.t.inkMuted,
                      ),
                    ),
                    Gap.h8,
                  ],
                  _EpisodeRow(
                    episode: e,
                    onTap: () => context.push('/episode/${e.id}'),
                  ),
                  Gap.h8,
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.onTap});

  final Episode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: Radii.md,
      child: InkWell(
        borderRadius: Radii.md,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: Radii.md,
            border: Border.all(
              color: episode.isOngoing
                  ? severityColor(context, episode.severity)
                  : t.line,
            ),
          ),
          child: Row(
            children: [
              SeverityBadge(severity: episode.severity, compact: true),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(episode.kind.icon, size: 15, color: t.inkMuted),
                        Gap.w4,
                        Text(
                          episode.kind.label,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      episode.isOngoing
                          ? 'from ${_timeOnly.format(episode.startedAt)}, still going'
                          : '${_timeOnly.format(episode.startedAt)} · lasted '
                                '${formatDuration(episode.duration)}',
                      style: context.text.bodySmall?.copyWith(
                        color: t.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
