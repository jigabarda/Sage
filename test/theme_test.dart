import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sage/core/brand_palette.dart';
import 'package:sage/core/sage_theme.dart';
import 'package:sage/core/sage_tokens.dart';

/// Guards the two design rules that are easy to break silently: text has to
/// stay readable on every palette, and green must not creep back into the
/// severity scale.
void main() {
  const aa = 4.5;
  const aaLarge = 3.0;

  for (final brightness in Brightness.values) {
    for (final palette in BrandPalette.values) {
      final t = SageTokens.baseFor(brightness).withPalette(palette, brightness);
      final name = '${palette.label} / ${brightness.name}';

      test('$name — body text clears AA on every surface', () {
        expect(contrastRatio(t.ink, t.canvas), greaterThanOrEqualTo(aa));
        expect(contrastRatio(t.ink, t.surface), greaterThanOrEqualTo(aa));
        expect(contrastRatio(t.ink, t.surfaceAlt), greaterThanOrEqualTo(aa));
        expect(contrastRatio(t.inkMuted, t.canvas), greaterThanOrEqualTo(aa));
        expect(contrastRatio(t.inkMuted, t.surface), greaterThanOrEqualTo(aa));
      });

      test('$name — a filled button label is readable', () {
        // onAccent is computed, not hand-picked. If withPalette ever stops
        // computing it, this is what catches the unreadable label.
        expect(contrastRatio(t.onAccent, t.accent), greaterThanOrEqualTo(aa));
        expect(contrastRatio(t.onAlert, t.alert), greaterThanOrEqualTo(aa));
      });

      test('$name — the severity scale is legible on a card', () {
        // Severity is carried by large figures and filled chips rather than
        // body copy, so AA-large is the right bar here.
        for (final c in [t.severityLow, t.severityMid, t.severityHigh]) {
          expect(contrastRatio(c, t.surface), greaterThanOrEqualTo(aaLarge));
        }
      });

      test('$name — the accent tint stays behind readable text', () {
        expect(contrastRatio(t.ink, t.accentSoft), greaterThanOrEqualTo(aa));
      });

      test('$name — no green anywhere on the severity scale', () {
        // The rule is in the guide and in the tokens doc; this is what stops
        // a future "mild = green" from being added by reflex. Green here means
        // a hue where green dominates both other channels.
        for (final c in [t.severityLow, t.severityMid, t.severityHigh]) {
          final greenDominant = c.g > c.r && c.g > c.b;
          expect(
            greenDominant,
            isFalse,
            reason: 'severity must never read as "good"',
          );
        }
      });
    }
  }

  test('the accent moves with the palette but the severity scale does not', () {
    final olive = SageTokens.baseFor(
      Brightness.light,
    ).withPalette(BrandPalette.olive, Brightness.light);
    final clay = SageTokens.baseFor(
      Brightness.light,
    ).withPalette(BrandPalette.clay, Brightness.light);

    expect(olive.accent, isNot(clay.accent));
    expect(olive.severityHigh, clay.severityHigh);
    expect(olive.alert, clay.alert);
    expect(olive.ink, clay.ink);
  });

  test('the theme exposes the tokens it was built from', () {
    final theme = buildSageTheme(Brightness.light, BrandPalette.olive);
    final t = theme.extension<SageTokens>();

    expect(t, isNotNull);
    expect(t!.accent, BrandPalette.olive.lightAccent);
    expect(theme.scaffoldBackgroundColor, t.canvas);
    // Material's scheme is derived from the tokens, so a widget reaching for
    // colorScheme.primary still lands on the accent.
    expect(theme.colorScheme.primary, t.accent);
  });
}
