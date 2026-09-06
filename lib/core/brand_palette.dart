import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefBrandPalette = 'brand_palette';

/// Accent colours the app can be themed with.
///
/// Only the accent varies. Canvas, ink, the severity scale and the alert
/// semantics stay fixed across every palette — a severity-9 migraine has to
/// read as severe whichever accent is chosen, and letting the brand colour
/// move those would make the two indistinguishable.
///
/// **Every entry here is low-chroma, and that is a requirement rather than a
/// house style.** Photophobia is a core migraine symptom, so the in-attack
/// screens are read on a dimmed display by someone whose eyes hurt. A
/// saturated accent is actively unpleasant under that condition. Sellora ships
/// eighteen palettes including fuchsia and cyan because businesses brand it;
/// none of those belong here.
///
/// Each entry carries a hand-picked pair rather than one colour lightened
/// programmatically: a hue that reads well on a near-white canvas is usually
/// too dark and too saturated against a near-black one.
enum BrandPalette {
  /// The default, and the app's namesake.
  olive('Olive', Color(0xFF5A6E3A), Color(0xFFA3B57A)),
  sage('Sage', Color(0xFF5F7360), Color(0xFFA8BFA6)),
  moss('Moss', Color(0xFF4A6B4F), Color(0xFF92B899)),
  clay('Clay', Color(0xFF8A5A45), Color(0xFFCFA08B)),
  slate('Slate', Color(0xFF4C5A66), Color(0xFFA3B2BF)),
  plum('Plum', Color(0xFF6B4F63), Color(0xFFBFA0B8));

  const BrandPalette(this.label, this.lightAccent, this.darkAccent);

  /// Shown in the Settings picker.
  final String label;

  final Color lightAccent;
  final Color darkAccent;

  static const fallback = BrandPalette.olive;

  Color accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccent : lightAccent;

  /// Resolves a stored name, falling back when the value is absent or came
  /// from a build that had a palette this one no longer ships.
  static BrandPalette fromName(String? name) {
    for (final p in BrandPalette.values) {
      if (p.name == name) return p;
    }
    return fallback;
  }
}

/// Persists the palette choice so it survives a restart.
class BrandPaletteController extends StateNotifier<BrandPalette> {
  BrandPaletteController(this._prefs)
    : super(BrandPalette.fromName(_prefs.getString(_prefBrandPalette)));

  final SharedPreferences _prefs;

  Future<void> set(BrandPalette palette) async {
    state = palette;
    await _prefs.setString(_prefBrandPalette, palette.name);
  }
}

/// Overridden in `main.dart` once SharedPreferences is open.
final brandPaletteProvider =
    StateNotifierProvider<BrandPaletteController, BrandPalette>(
      (ref) => throw StateError(
        'brandPaletteProvider must be overridden in ProviderScope',
      ),
    );
