import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/brand_palette.dart';
import 'core/theme_controller.dart';
import 'data/db/sage_database.dart';
import 'data/notifications/notification_service.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened here rather than lazily so the first frame already has both, and so
  // a schema migration happens once at startup instead of racing the first
  // screen that reads a table.
  final prefs = await SharedPreferences.getInstance();
  final db = await SageDatabase.open();

  // Prepared here so the settings screen never waits on it. init()
  // swallows its own failures: an app that will not start because a
  // reminder could not be scheduled has its priorities the wrong way
  // round.
  final notifications = NotificationService(prefs);
  await notifications.init();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notifications),
        themeModeProvider.overrideWith((ref) => ThemeController(prefs)),
        brandPaletteProvider.overrideWith(
          (ref) => BrandPaletteController(prefs),
        ),
      ],
      child: const SageApp(),
    ),
  );
}
