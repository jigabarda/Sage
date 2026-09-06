import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefThemeMode = 'theme_mode';

/// Persists the light/dark/system choice.
///
/// Note for the in-attack screens: this is the *app-wide* preference, and the
/// logging flow is expected to override it towards dark regardless. Someone
/// mid-migraine should not have to go change a setting to stop the screen
/// hurting.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static ThemeMode _read(SharedPreferences prefs) {
    switch (prefs.getString(_prefThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_prefThemeMode, mode.name);
  }
}

/// Overridden in `main.dart` once SharedPreferences is open.
final themeModeProvider = StateNotifierProvider<ThemeController, ThemeMode>(
  (ref) =>
      throw StateError('themeModeProvider must be overridden in ProviderScope'),
);
