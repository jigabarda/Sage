import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/episode_kind.dart';
import '../../constants/relievers.dart';
import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/models/episode.dart';
import '../../providers.dart';

/// The screen someone opens while an attack is starting.
///
/// Everything here is built around one constraint: the person using it may be
/// in significant pain, on a dimmed screen, and unwilling to read. So the
/// primary action is a single large tap that records an accurate start time
/// and nothing else. Detail is something they add later, from the couch, if
/// they feel like it — and if they never do, the timestamp and the default
/// severity are still a usable row.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // An ongoing episode shows an elapsed time computed from DateTime.now(),
    // which does not change on its own. A minute is the finest granularity the
    // label shows, so anything faster is wasted frames.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _startNow(EpisodeKind kind) async {
    final repo = ref.read(episodeRepositoryProvider);
    final id = await repo.startNow(kind);
    if (!mounted) return;
    invalidateEpisodeData(ref);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${kind.label} logged. Rest first.'),
          action: SnackBarAction(
            label: 'What helps',
            // Guidance, not the form. Mid-attack this is the more useful of
            // the two, and it routes through the safety check.
            onPressed: () => context.push('/safety/${kind.code}?episode=$id'),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
  }

  Future<void> _close(Episode e) async {
    await ref.read(episodeRepositoryProvider).close(e.id);
    if (!mounted) return;
    invalidateEpisodeData(ref);
  }

  @override
  Widget build(BuildContext context) {
    final ongoing = ref.watch(ongoingEpisodesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: ongoing.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SageEmpty(message: 'Could not read the log.\n$e'),
        data: (episodes) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final e in episodes) ...[
              _OngoingCard(
                episode: e,
                onClose: () => _close(e),
                onOpen: () => context.push('/episode/${e.id}'),
                onGuidance: () =>
                    context.push('/safety/${e.kind.code}?episode=${e.id}'),
              ),
              Gap.h12,
            ],
            if (episodes.isNotEmpty) Gap.h12,
            Text(
              episodes.isEmpty ? 'Having one now?' : 'Something else starting?',
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap.h4,
            Text(
              'One tap records the time. Everything else can wait.',
              style: context.text.bodySmall?.copyWith(
                color: context.t.inkMuted,
              ),
            ),
            Gap.h16,
            for (final kind in EpisodeKind.values) ...[
              _StartButton(kind: kind, onTap: () => _startNow(kind)),
              Gap.h12,
            ],
            Gap.h16,
            _LastHelpedNote(
              kind: episodes.isNotEmpty
                  ? episodes.first.kind
                  : EpisodeKind.migraine,
            ),
            Gap.h24,
            Center(
              child: TextButton(
                onPressed: () => context.push('/episode/new'),
                child: const Text('Log something that already passed'),
              ),
            ),
            // Guidance without logging first. Someone who wants to know what
            // to do should not have to create a row to find out, and the
            // safety check gates this route the same as every other.
            Center(
              child: TextButton(
                onPressed: () =>
                    context.push('/safety/${EpisodeKind.migraine.code}'),
                child: const Text('What helps, without logging it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The big primary target. Deliberately full-width and tall.
class _StartButton extends StatelessWidget {
  const _StartButton({required this.kind, required this.onTap});

  final EpisodeKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: Radii.lg,
      child: InkWell(
        borderRadius: Radii.lg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            borderRadius: Radii.lg,
            border: Border.all(color: t.line),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: Radii.md,
                ),
                child: Icon(kind.icon, color: t.accent),
              ),
              Gap.w16,
              Expanded(
                child: Text(
                  '${kind.label} now',
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: t.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _OngoingCard extends StatelessWidget {
  const _OngoingCard({
    required this.episode,
    required this.onClose,
    required this.onOpen,
    required this.onGuidance,
  });

  final Episode episode;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final VoidCallback onGuidance;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: Radii.lg,
        border: Border.all(color: severityColor(context, episode.severity)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SeverityBadge(severity: episode.severity),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${episode.kind.label}, still going',
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'started ${formatDuration(episode.duration)} ago',
                      style: context.text.bodySmall?.copyWith(
                        color: t.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Gap.h16,
          FilledButton(onPressed: onGuidance, child: const Text('What helps')),
          Gap.h8,
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpen,
                  child: const Text('Add detail'),
                ),
              ),
              Gap.w12,
              Expanded(
                child: OutlinedButton(
                  onPressed: onClose,
                  child: const Text('It stopped'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One remembered fact, phrased as one.
///
/// "Last time, a cold compress helped" is honest about being a single
/// observation. It must not drift into "cold compresses help you" — that is an
/// aggregate claim, and aggregate claims belong to Phase 3 where they carry an
/// evidence gate and state their numbers.
class _LastHelpedNote extends ConsumerWidget {
  const _LastHelpedNote({required this.kind});

  final EpisodeKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastHelpedProvider(kind));
    return last.maybeWhen(
      data: (code) {
        if (code == null) return const SizedBox.shrink();
        final t = context.t;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surfaceAlt,
            borderRadius: Radii.md,
          ),
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: t.inkMuted),
              Gap.w12,
              Expanded(
                child: Text(
                  'Last time, "${Relievers.labelFor(code)}" helped.',
                  style: context.text.bodySmall?.copyWith(color: t.inkMuted),
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
