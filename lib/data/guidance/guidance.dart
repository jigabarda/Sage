import 'package:flutter/material.dart';

import '../../constants/episode_kind.dart';

/// One thing to do, phrased as an action.
@immutable
class GuidanceStep {
  const GuidanceStep(this.icon, this.text, [this.detail]);

  final IconData icon;

  /// The instruction. Imperative and short — this is read by someone who does
  /// not want to be reading.
  final String text;

  /// Optional second line for the "why" or a caveat. Never required to
  /// understand the step.
  final String? detail;
}

/// What Tier 1 hands back: fixed steps, things to avoid, and at most one
/// sentence about this person's own record.
@immutable
class Guidance {
  const Guidance({
    required this.kind,
    required this.steps,
    required this.avoid,
    required this.personalNotes,
  });

  final EpisodeKind kind;
  final List<GuidanceStep> steps;
  final List<String> avoid;

  /// Statements about this person's own log, each carrying its numbers.
  ///
  /// Empty until there is enough history to say anything honest — see the
  /// gates in `GuidanceService`. An empty list is the correct output for a new
  /// user, and is never padded with a generality to fill the space.
  final List<String> personalNotes;
}

/// The fixed content. Compiled in, identical every time, no generation.
///
/// ## Why this is a template and not a language model
///
/// Someone mid-attack needs the same correct answer every time, instantly,
/// offline, on whatever phone they have. A template gives that for 0 MB. A
/// small on-device model would give a slightly different answer each time, at
/// the cost of a gigabyte and the risk of inventing one — and the failure mode
/// of an invented instruction here is not clumsy prose, it is bad advice to
/// someone in pain.
///
/// ## Rules for editing
///
/// - **No drug names and no doses.** "Take it as your doctor told you" is the
///   most this may ever say about medication. Non-negotiable 6.
/// - **Nothing here is a red flag.** If a step ever needs the words "if it
///   gets worse, go to hospital", that condition belongs in `TriageRules`,
///   not in a bullet someone has to reach the bottom of the list to see.
/// - Keep the imperative short. The detail line is optional by design.
abstract final class GuidanceContent {
  static const migraineSteps = <GuidanceStep>[
    GuidanceStep(
      Icons.bedroom_baby_outlined,
      'Get somewhere dark and quiet',
      'Light and sound make it worse for most people. This is the one that '
          'tends to matter most.',
    ),
    GuidanceStep(Icons.airline_seat_flat_outlined, 'Lie down if you can'),
    GuidanceStep(
      Icons.ac_unit_outlined,
      'Cold on your forehead or the back of your neck',
      'Some people do better with warmth on the neck instead. Use whichever '
          'has worked for you before.',
    ),
    GuidanceStep(
      Icons.water_drop_outlined,
      'Sip water steadily',
      'Small and often is easier to keep down than a full glass.',
    ),
    GuidanceStep(
      Icons.medication_outlined,
      'If you have medication for this, take it the way your doctor told you',
      'For most rescue medication, earlier in an attack works better than '
          'later. Your prescription is the instruction, not this app.',
    ),
    GuidanceStep(
      Icons.phone_android_outlined,
      'Then put the phone down',
      'Nothing else here needs reading right now.',
    ),
  ];

  static const migraineAvoid = <String>[
    'Bright screens, including this one',
    'Skipping your next meal',
    'Pushing through it at work if you have any choice',
  ];

  static const refluxSteps = <GuidanceStep>[
    GuidanceStep(
      Icons.airline_seat_recline_normal_outlined,
      'Stay upright',
      'Sitting or standing. Lying flat lets acid move the wrong way.',
    ),
    GuidanceStep(
      Icons.bed_outlined,
      'If you have to lie down, prop your head and chest up',
      'Pillows under your shoulders, not just your head — bending at the neck '
          'does not help.',
    ),
    GuidanceStep(
      Icons.checkroom_outlined,
      'Loosen anything tight around your waist',
    ),
    GuidanceStep(Icons.water_drop_outlined, 'Small sips of water'),
    GuidanceStep(
      Icons.no_meals_outlined,
      'Do not eat anything more until it settles',
    ),
    GuidanceStep(
      Icons.medication_outlined,
      'If you use an antacid, take it as the packet says',
      'The packet is the instruction, not this app.',
    ),
  ];

  static const refluxAvoid = <String>[
    'Lying flat, and bending over',
    'Eating more, even something small and bland',
    'Coffee, alcohol, and anything spicy or fatty until it passes',
  ];

  static List<GuidanceStep> stepsFor(EpisodeKind kind) => switch (kind) {
    EpisodeKind.migraine => migraineSteps,
    EpisodeKind.reflux => refluxSteps,
  };

  static List<String> avoidFor(EpisodeKind kind) => switch (kind) {
    EpisodeKind.migraine => migraineAvoid,
    EpisodeKind.reflux => refluxAvoid,
  };
}
