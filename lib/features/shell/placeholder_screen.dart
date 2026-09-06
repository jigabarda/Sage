import 'package:flutter/material.dart';

import '../../core/sage_tokens.dart';

/// Stands in for a screen a later phase builds.
///
/// Deliberately states which phase owns it, so a scaffold left in place by
/// accident reads as unfinished rather than as an empty state someone has to
/// reverse-engineer.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.phase,
    required this.summary,
  });

  final String title;
  final String phase;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: Radii.pill,
                ),
                child: Text(
                  phase,
                  style: context.text.labelSmall?.copyWith(color: t.accent),
                ),
              ),
              Gap.h16,
              Text(
                summary,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(color: t.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
