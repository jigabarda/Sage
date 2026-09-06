import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand_palette.dart';

/// Every colour the app is allowed to draw with.
///
/// Read them through `context.t`. There are no hex literals in
/// `lib/features/**` — a literal cannot respond to the theme, and an app with
/// two incompatible looks is what that rule exists to prevent.
///
/// ## Why there is no `success` token
///
/// Deliberate. Green is the accent family here, so it cannot also mean "good"
/// without the two blurring. The deeper reason is domain, not colour: this
/// tracks a chronic condition. Colouring a day without an episode green frames
/// a day *with* one as a failure, and the user does not choose which they get.
/// Quiet days are [inkMuted], not celebrated — no green, no streaks, no
/// congratulation. Leaving the token out is what keeps that from being
/// re-added by reflex.
@immutable
class SageTokens extends ThemeExtension<SageTokens> {
  const SageTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.severityLow,
    required this.severityMid,
    required this.severityHigh,
    required this.danger,
    required this.dangerSoft,
    required this.alert,
    required this.alertSoft,
    required this.onAlert,
  });

  /// Page background.
  final Color canvas;

  /// Card and sheet background.
  final Color surface;

  /// Recessed rows, input fills, table stripes.
  final Color surfaceAlt;

  /// Borders and dividers.
  final Color line;

  /// Primary text.
  final Color ink;

  /// Secondary text, and the colour of a day with nothing to report.
  final Color inkMuted;

  /// Placeholders and disabled text.
  final Color inkFaint;

  final Color accent;

  /// A tint of [accent] composited over [surface], never a translucent colour —
  /// alpha over an unknown background is how tinted rows end up muddy.
  final Color accentSoft;

  /// Whatever reads on [accent]; computed by contrast, never hand-picked.
  final Color onAccent;

  /// The severity scale: neutral, then amber, then red.
  ///
  /// Fixed across every palette. There is no green end — see the class doc.
  final Color severityLow;
  final Color severityMid;
  final Color severityHigh;

  /// Destructive intent in ordinary UI: delete an episode, discard a draft.
  final Color danger;
  final Color dangerSoft;

  /// Red-flag escalation, and nothing else.
  ///
  /// Deliberately louder than [danger] and reserved: if this colour appears,
  /// the app is telling someone to seek emergency care. Using it to decorate a
  /// severe-but-ordinary migraine would spend the one signal that must never
  /// be ignorable.
  final Color alert;
  final Color alertSoft;
  final Color onAlert;

  static final _lightBase = SageTokens(
    canvas: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF3F4EF),
    line: Color(0xFFE2E4DC),
    ink: Color(0xFF1C1E18),
    inkMuted: Color(0xFF5D6157),
    inkFaint: Color(0xFF8E9288),
    accent: BrandPalette.olive.lightAccent,
    accentSoft: Color(0xFFEFF1E7),
    onAccent: Color(0xFFFFFFFF),
    severityLow: Color(0xFF6B7280),
    severityMid: Color(0xFFB4700A),
    severityHigh: Color(0xFFB3261E),
    danger: Color(0xFFB3261E),
    dangerSoft: Color(0xFFFBEAE8),
    alert: Color(0xFF9B0F1E),
    alertSoft: Color(0xFFFCE8EA),
    onAlert: Color(0xFFFFFFFF),
  );

  static final _darkBase = SageTokens(
    canvas: Color(0xFF121410),
    surface: Color(0xFF1B1E18),
    surfaceAlt: Color(0xFF23261F),
    line: Color(0xFF32362C),
    ink: Color(0xFFECEEE7),
    inkMuted: Color(0xFFA6AB9D),
    inkFaint: Color(0xFF71766B),
    accent: BrandPalette.olive.darkAccent,
    accentSoft: Color(0xFF272B20),
    onAccent: Color(0xFF10130C),
    severityLow: Color(0xFF9CA3AF),
    severityMid: Color(0xFFF0A93B),
    severityHigh: Color(0xFFF2857C),
    danger: Color(0xFFF2857C),
    dangerSoft: Color(0xFF33211F),
    alert: Color(0xFFFF6B7A),
    alertSoft: Color(0xFF3A1F24),
    onAlert: Color(0xFF1A0509),
  );

  /// The base set for [brightness], before a palette is applied.
  static SageTokens baseFor(Brightness brightness) =>
      brightness == Brightness.dark ? _darkBase : _lightBase;

  /// Applies [palette], computing the two derived accent colours.
  ///
  /// Adding a palette means choosing two colours and nothing else — everything
  /// downstream of the accent is derived here, so a new entry cannot forget to
  /// set one and end up with an unreadable label.
  SageTokens withPalette(BrandPalette palette, Brightness brightness) {
    final next = palette.accentFor(brightness);
    return copyWith(
      accent: next,
      accentSoft: Color.alphaBlend(
        next.withValues(alpha: brightness == Brightness.dark ? 0.16 : 0.12),
        surface,
      ),
      onAccent: onColor(next),
    );
  }

  /// Picks whichever of [ink]/[canvas] reads on [background].
  ///
  /// Compared by actual contrast ratio rather than a luminance threshold: a
  /// mid-tone olive sits close enough to the crossover that guessing gets it
  /// wrong, and the failure is an unreadable button label.
  Color onColor(Color background) =>
      _contrast(background, _darkBase.canvas) >=
          _contrast(background, _lightBase.surface)
      ? _darkBase.canvas
      : _lightBase.surface;

  @override
  SageTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? line,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? severityLow,
    Color? severityMid,
    Color? severityHigh,
    Color? danger,
    Color? dangerSoft,
    Color? alert,
    Color? alertSoft,
    Color? onAlert,
  }) {
    return SageTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      severityLow: severityLow ?? this.severityLow,
      severityMid: severityMid ?? this.severityMid,
      severityHigh: severityHigh ?? this.severityHigh,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      alert: alert ?? this.alert,
      alertSoft: alertSoft ?? this.alertSoft,
      onAlert: onAlert ?? this.onAlert,
    );
  }

  @override
  SageTokens lerp(ThemeExtension<SageTokens>? other, double t) {
    if (other is! SageTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SageTokens(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      line: c(line, other.line),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      inkFaint: c(inkFaint, other.inkFaint),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      onAccent: c(onAccent, other.onAccent),
      severityLow: c(severityLow, other.severityLow),
      severityMid: c(severityMid, other.severityMid),
      severityHigh: c(severityHigh, other.severityHigh),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      alert: c(alert, other.alert),
      alertSoft: c(alertSoft, other.alertSoft),
      onAlert: c(onAlert, other.onAlert),
    );
  }
}

/// WCAG relative luminance of an opaque colour.
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colours, 1.0 to 21.0.
///
/// Public because the theme test asserts every token pair the app actually
/// draws clears AA, and because a new palette entry is expected to be checked
/// against it rather than eyeballed.
double contrastRatio(Color a, Color b) => _contrast(a, b);

double _contrast(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Spacing scale. Prefer `Gap.h12` over a raw `SizedBox(height: 12)` so the
/// rhythm stays in one place.
abstract final class Gap {
  static const h4 = SizedBox(height: 4);
  static const h8 = SizedBox(height: 8);
  static const h12 = SizedBox(height: 12);
  static const h16 = SizedBox(height: 16);
  static const h24 = SizedBox(height: 24);
  static const h32 = SizedBox(height: 32);

  static const w4 = SizedBox(width: 4);
  static const w8 = SizedBox(width: 8);
  static const w12 = SizedBox(width: 12);
  static const w16 = SizedBox(width: 16);
}

/// Corner radii.
abstract final class Radii {
  static const sm = BorderRadius.all(Radius.circular(8));
  static const md = BorderRadius.all(Radius.circular(12));
  static const lg = BorderRadius.all(Radius.circular(18));
  static const pill = BorderRadius.all(Radius.circular(999));
}

/// `context.t` for tokens, `context.text` for type.
extension SageThemeAccess on BuildContext {
  SageTokens get t => Theme.of(this).extension<SageTokens>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
