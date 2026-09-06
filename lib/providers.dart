import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Both are opened once in `main.dart` and injected as overrides, so no screen
/// ever awaits a database handle mid-build. A provider that throws until
/// overridden fails loudly at startup rather than silently handing out a
/// second connection later.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  ),
);

final databaseProvider = Provider<Database>(
  (ref) =>
      throw StateError('databaseProvider must be overridden in ProviderScope'),
);
