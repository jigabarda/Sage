import 'package:flutter/material.dart';

import '../constants/episode_kind.dart';
import 'sage_tokens.dart';

/// The colour for a severity band.
///
/// Free function rather than a method on the enum so the mapping lives beside
/// the tokens it reads. There is no green case, and there must not be one —
/// see the note in `sage_tokens.dart`.
Color severityColor(BuildContext context, int severity) {
  final t = context.t;
  return switch (Severity.bandOf(severity)) {
    SeverityBand.low => t.severityLow,
    SeverityBand.moderate => t.severityMid,
    SeverityBand.high => t.severityHigh,
  };
}

/// A small filled badge carrying a severity number.
class SeverityBadge extends StatelessWidget {
  const SeverityBadge({
    super.key,
    required this.severity,
    this.compact = false,
  });

  final int severity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = severityColor(context, severity);
    final size = compact ? 32.0 : 44.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: Text(
        '$severity',
        style: TextStyle(
          color: context.t.onColor(c),
          fontWeight: FontWeight.w700,
          fontSize: compact ? 13 : 17,
        ),
      ),
    );
  }
}

/// A tappable filter/selection chip drawn from tokens.
class SageChip extends StatelessWidget {
  const SageChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: selected ? t.accentSoft : t.surface,
      borderRadius: Radii.pill,
      child: InkWell(
        borderRadius: Radii.pill,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: Radii.pill,
            border: Border.all(color: selected ? t.accent : t.line),
          ),
          child: Text(
            label,
            style: context.text.bodyMedium?.copyWith(
              color: selected ? t.accent : t.ink,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled block within a form or detail screen.
class SageSection extends StatelessWidget {
  const SageSection({
    super.key,
    required this.title,
    this.hint,
    required this.child,
  });

  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (hint != null) ...[
          Gap.h4,
          Text(
            hint!,
            style: context.text.bodySmall?.copyWith(color: t.inkMuted),
          ),
        ],
        Gap.h12,
        child,
      ],
    );
  }
}

/// Renders an empty state without implying anything about it.
///
/// No illustration, no encouragement, no "great job, no episodes!". A quiet
/// stretch is not an achievement and the app does not congratulate it — see
/// the design rules in the guide.
class SageEmpty extends StatelessWidget {
  const SageEmpty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.text.bodyMedium?.copyWith(color: context.t.inkMuted),
      ),
    );
  }
}

/// Human-readable duration: "2h 15m", "45m", "just now".
String formatDuration(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h < 24) return m == 0 ? '${h}h' : '${h}h ${m}m';
  final days = d.inDays;
  final hours = h.remainder(24);
  return hours == 0 ? '${days}d' : '${days}d ${hours}h';
}
