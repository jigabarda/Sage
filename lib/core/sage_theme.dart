import 'package:flutter/material.dart';

import 'brand_palette.dart';
import 'sage_tokens.dart';

/// Builds the app's [ThemeData] for one brightness and one accent.
///
/// Material's own colour scheme is derived from the tokens rather than the
/// other way round, so a widget that reaches for `colorScheme.primary` instead
/// of `context.t.accent` still lands on the right colour. The tokens remain
/// the source of truth.
ThemeData buildSageTheme(Brightness brightness, BrandPalette palette) {
  final t = SageTokens.baseFor(brightness).withPalette(palette, brightness);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.ink,
    secondary: t.accent,
    onSecondary: t.onAccent,
    error: t.danger,
    onError: t.onColor(t.danger),
    surface: t.surface,
    onSurface: t.ink,
    surfaceContainerHighest: t.surfaceAlt,
    onSurfaceVariant: t.inkMuted,
    outline: t.line,
    outlineVariant: t.line,
  );

  // Type is the platform font for now. Sellora bundles Plus Jakarta Sans and
  // Inter; that is deferred here until there are screens to set it on, because
  // an unbundled weight is synthesised by Flutter and visibly smears.
  final base = brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.canvas,
    dividerColor: t.line,
    extensions: [t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.canvas,
      foregroundColor: t.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.lg,
        side: BorderSide(color: t.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: Radii.md),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        side: BorderSide(color: t.line),
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: Radii.md),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceAlt,
      hintStyle: TextStyle(color: t.inkFaint),
      border: OutlineInputBorder(
        borderRadius: Radii.md,
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Radii.md,
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Radii.md,
        borderSide: BorderSide(color: t.accent, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.accentSoft,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: t.inkMuted),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: TextStyle(color: t.canvas),
      behavior: SnackBarBehavior.floating,
    ),
    textTheme: base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink),
  );
}
