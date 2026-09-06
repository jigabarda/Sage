import 'dart:math';

final _rand = Random();

/// A local row id: `<prefix>_<millis base36>_<random>`.
///
/// Time-ordered by construction, so ids sort roughly by creation without a
/// separate index, and readable enough that a row in an exported file can be
/// traced back. There is no server issuing keys and no second device to
/// collide with, so this does not need to be a UUID.
String newLocalId(String prefix) {
  final ms = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final salt = _rand.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '${prefix}_${ms}_$salt';
}
