import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand_palette.dart';
import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../core/theme_controller.dart';
import '../../data/notifications/notification_policy.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Appearance(),
          Gap.h32,
          const _Notifications(),
          Gap.h32,
          SageSection(
            title: 'Your data',
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: Radii.md,
              ),
              child: Text(
                'Everything you log stays on this phone. There is no account, '
                'no sync and no server copy, and the app has no permission to '
                'use the internet at all.\n\n'
                'Reminders are scheduled on the device, so nothing about them '
                'leaves it either.',
                style: context.text.bodySmall?.copyWith(
                  color: t.inkMuted,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Appearance extends ConsumerWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final palette = ref.watch(brandPaletteProvider);

    return SageSection(
      title: 'Appearance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final m in ThemeMode.values) ...[
                Expanded(
                  child: SageChip(
                    label: switch (m) {
                      ThemeMode.system => 'System',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    },
                    selected: mode == m,
                    onTap: () => ref.read(themeModeProvider.notifier).set(m),
                  ),
                ),
                if (m != ThemeMode.values.last) Gap.w8,
              ],
            ],
          ),
          Gap.h16,
          Text(
            'Accent',
            style: context.text.bodySmall?.copyWith(color: context.t.inkMuted),
          ),
          Gap.h8,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in BrandPalette.values)
                SageChip(
                  label: p.label,
                  selected: palette == p,
                  onTap: () => ref.read(brandPaletteProvider.notifier).set(p),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notifications extends ConsumerStatefulWidget {
  const _Notifications();

  @override
  ConsumerState<_Notifications> createState() => _NotificationsState();
}

class _NotificationsState extends ConsumerState<_Notifications> {
  bool _busy = false;

  /// Applies a toggle, asking for permission the first time one is turned on.
  ///
  /// The prompt is deliberately here and not at launch. Android gives an app
  /// one good chance: a permission asked before any value has been shown gets
  /// denied, and a second denial is permanent until the user goes into system
  /// settings. So it is asked at the exact moment someone has said they want
  /// a notification.
  Future<void> _set(NotificationSettings next) async {
    final service = ref.read(notificationServiceProvider);
    final wasEnabled = service.settings.anyEnabled;

    setState(() => _busy = true);
    try {
      if (!wasEnabled && next.anyEnabled) {
        final granted = await service.requestPermission();
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Android is blocking notifications for Sage. You can turn '
                'them on in system settings.',
              ),
            ),
          );
          return;
        }
      }

      await service.saveSettings(next);
      await ref.read(rearmNotificationsProvider.future);
      if (!mounted) return;
      // Rebuilds the toggles from the saved settings.
      setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(notificationServiceProvider).settings;

    return SageSection(
      title: 'Reminders',
      hint: 'Scheduled on this phone. Nothing is sent anywhere.',
      child: Column(
        children: [
          _Toggle(
            label: 'Still going?',
            detail:
                'Asks about an episode you left open, ${NotificationPolicy.followUpAfter.inHours} hours after it started.',
            value: s.episodeFollowUp,
            enabled: !_busy,
            onChanged: (v) => _set(s.copyWith(episodeFollowUp: v)),
          ),
          _Toggle(
            label: 'Weekly summary',
            detail:
                'Sunday evening, and only when something has actually cleared '
                'its evidence bar. No message when there is nothing to say.',
            value: s.weeklySummary,
            enabled: !_busy,
            onChanged: (v) => _set(s.copyWith(weeklySummary: v)),
          ),
          _Toggle(
            label: 'Daily log reminder',
            detail: 'Evening nudge to fill in sleep, stress and meals.',
            value: s.dailyNudge,
            enabled: !_busy,
            onChanged: (v) => _set(s.copyWith(dailyNudge: v)),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.detail,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: Radii.md,
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Gap.h4,
                Text(
                  detail,
                  style: context.text.bodySmall?.copyWith(
                    color: t.inkMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
