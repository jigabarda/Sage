import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/brand_palette.dart';
import 'core/theme_controller.dart';
import 'data/db/sage_database.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened here rather than lazily so the first frame already has both, and so
  // a schema migration happens once at startup instead of racing the first
  // screen that reads a table.
  final prefs = await SharedPreferences.getInstance();
  final db = await SageDatabase.open();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        themeModeProvider.overrideWith((ref) => ThemeController(prefs)),
        brandPaletteProvider.overrideWith(
          (ref) => BrandPaletteController(prefs),
        ),
      ],
      child: const SageApp(),
    ),
  );
}
