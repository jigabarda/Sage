import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefTrackCycle = 'track_cycle';

/// Whether the daily log asks about a menstrual cycle.
///
/// **Off by default, and it stays off until someone turns it on.** The guide
/// left this as an open question because it depends entirely on who is using
/// the app; shipping it on would put a period question in front of everyone
/// who installs it, and shipping it not at all would drop one of the strongest
/// patterns in migraine. Opt-in resolves that without deciding for anyone.
///
/// Turning it off hides the field but keeps what was recorded. Deleting the
/// data would be a surprise, and the correlation rule simply stops finding
/// new period starts.
class CycleTrackingController extends StateNotifier<bool> {
  CycleTrackingController(this._prefs)
    : super(_prefs.getBool(_prefTrackCycle) ?? false);

  final SharedPreferences _prefs;

  Future<void> set(bool enabled) async {
    state = enabled;
    await _prefs.setBool(_prefTrackCycle, enabled);
  }
}

final cycleTrackingProvider =
    StateNotifierProvider<CycleTrackingController, bool>(
      (ref) => throw StateError(
        'cycleTrackingProvider must be overridden in ProviderScope',
      ),
    );
