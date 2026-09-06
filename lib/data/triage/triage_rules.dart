import '../../constants/episode_kind.dart';
import 'red_flag.dart';

/// The red-flag set. Fixed text, evaluated by exact match on what the user
/// ticked. No inference, no scoring, no thresholds.
///
/// ## Provenance
///
/// The headache entries follow the **SNOOP** framework used in clinical
/// practice to separate primary headache from secondary causes needing
/// imaging: **S**ystemic signs, **N**eurologic deficit, sudden **O**nset,
/// **O**lder age of onset, **P**attern change. The upper-GI entries are the
/// commonly published alarm features for dyspepsia and reflux, plus the
/// cardiac patterns that are routinely mistaken for heartburn.
///
/// **This list has not been reviewed by a clinician.** It is assembled from
/// standard published warning signs and is adequate for the author's own use.
/// Before this APK goes to anyone else, check it against a current clinical
/// source — see the note in `SAGE_PROJECT_GUIDE.md`.
///
/// ## Rules for changing this file
///
/// - **Adding a flag is cheap; removing one is not.** A false positive costs
///   someone an unnecessary worry and possibly a wasted trip. A false negative
///   costs something that cannot be given back. When unsure, keep it.
/// - **Never soften a question into a hedge.** "Does your neck feel a bit
///   stiff?" invites a no from someone who wants to be told they are fine.
/// - **Never make a flag conditional on severity.** A thunderclap headache in
///   someone who rated it a 4 is still a thunderclap headache.
/// - Treat any edit here as a safety change: say so in the commit and do not
///   bundle it with unrelated work.
abstract final class TriageRules {
  static const all = <RedFlag>[
    // ---------------------------------------------------------------------
    // Headache — emergency
    // ---------------------------------------------------------------------
    RedFlag(
      code: 'thunderclap',
      question: 'It came on suddenly and hit full force within about a minute',
      because:
          'A headache that peaks almost instantly can be a sign of bleeding '
          'around the brain. This needs to be looked at straight away, even '
          'if it has since eased off.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'worst_ever',
      question: 'This is the worst headache you have ever had',
      because:
          'A headache clearly unlike any you have had before is treated as an '
          'emergency until someone has ruled out a serious cause.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'neuro_deficit',
      question:
          'Weakness or numbness down one side, a drooping face, or trouble '
          'speaking or understanding',
      because:
          'These are the signs of a stroke. Time changes the outcome here more '
          'than in almost anything else.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'vision_loss',
      question: 'Sudden loss of vision, or double vision that is not going',
      because:
          'Sudden vision change alongside a headache can mean pressure or a '
          'blockage that needs urgent assessment.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'confusion',
      question: 'Confusion, or trouble staying awake',
      because: 'A headache with reduced alertness needs emergency assessment.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'seizure',
      question: 'You have had a seizure',
      because: 'A seizure with a headache needs emergency assessment.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'fever_stiff_neck',
      question: 'A fever, and your neck is stiff or hurts to bend forward',
      because:
          'Fever with a stiff neck can mean an infection around the brain and '
          'spinal cord. This gets worse quickly.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'head_injury',
      question: 'It started after a knock to the head',
      because:
          'A headache after a head injury can mean bleeding that builds up '
          'slowly, sometimes hours or days later.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.migraine},
    ),

    // ---------------------------------------------------------------------
    // Headache — urgent
    // ---------------------------------------------------------------------
    RedFlag(
      code: 'new_after_50',
      question: 'This is a new kind of headache and you are over 50',
      because:
          'A headache that starts as a new pattern later in life is worth a '
          'doctor looking at rather than treating at home.',
      urgency: RedFlagUrgency.urgent,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'pattern_change',
      question:
          'Clearly different from your usual ones, or getting steadily '
          'worse over days or weeks',
      because:
          'A change in your own established pattern is the thing worth '
          'mentioning to a doctor, more than any single bad episode.',
      urgency: RedFlagUrgency.urgent,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'worse_lying_or_straining',
      question: 'Worse when you lie flat, cough, strain or bend over',
      because:
          'A headache that changes with position or pressure can point to a '
          'cause that needs imaging.',
      urgency: RedFlagUrgency.urgent,
      kinds: {EpisodeKind.migraine},
    ),
    RedFlag(
      code: 'pregnancy',
      question: 'You are pregnant, or gave birth in the last six weeks',
      because:
          'Headaches in pregnancy and just after are assessed differently, and '
          'some causes are specific to that period.',
      urgency: RedFlagUrgency.urgent,
      kinds: {EpisodeKind.migraine},
    ),

    // ---------------------------------------------------------------------
    // Reflux / upper GI — emergency
    //
    // The first two exist because this is the app someone opens when their
    // chest burns, and a heart attack is the thing most often mistaken for
    // heartburn. They are deliberately the first questions asked.
    // ---------------------------------------------------------------------
    RedFlag(
      code: 'cardiac_radiation',
      question: 'The pain spreads to your arm, jaw, neck, shoulder or back',
      because:
          'Pain that travels like this can be coming from the heart rather '
          'than the stomach. The two feel alike and are told apart with tests, '
          'not by waiting.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.reflux},
    ),
    RedFlag(
      code: 'cardiac_associated',
      question:
          'Sweating, shortness of breath, feeling faint, or a crushing '
          'tightness in your chest',
      because:
          'These alongside chest discomfort are the pattern of a heart '
          'problem. Getting this checked and being wrong costs an evening.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.reflux},
    ),
    RedFlag(
      code: 'vomiting_blood',
      question:
          'You have vomited blood, or something that looked like coffee '
          'grounds',
      because:
          'That is bleeding in the upper gut. It needs to be seen now, not '
          'watched.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.reflux},
    ),
    RedFlag(
      code: 'black_stool',
      question: 'Black, tarry stools',
      because:
          'Black tarry stools usually mean blood from higher up in the gut, '
          'and need urgent assessment.',
      urgency: RedFlagUrgency.emergency,
      kinds: {EpisodeKind.reflux},
    ),

    // ---------------------------------------------------------------------
    // Reflux / upper GI — urgent
    // ---------------------------------------------------------------------
    RedFlag(
      code: 'dysphagia',
      question: 'Food sticks when you swallow, or swallowing hurts',
      because:
          'Trouble swallowing is one of the signs doctors specifically want to '
          'know about rather than treat as ordinary reflux.',
      urgency: RedFlagUrgency.urgent,
      kinds: {EpisodeKind.reflux},
    ),
    RedFlag(
      code: 'weight_loss',
      question: 'You are losing weight without trying',
      because:
          'Unintentional weight loss alongside gut symptoms is worth '
          'investigating rather than managing at home.',
      urgency: RedFlagUrgency.urgent,
      kinds: {EpisodeKind.reflux},
    ),
    RedFlag(
      code: 'persistent_vomiting',
      question: 'Vomiting that will not stop, or keeps coming back',
      because:
          'Persistent vomiting causes problems of its own and can point to a '
          'blockage.',
      urgency: RedFlagUrgency.urgent,
      kinds: {EpisodeKind.reflux},
    ),
  ];

  /// The questions to ask for [kind], emergency ones first.
  ///
  /// Order is not cosmetic. Someone scanning a list while in pain reads the
  /// top of it, and the entries where minutes matter have to be there.
  static List<RedFlag> forKind(EpisodeKind kind) {
    final matching = all.where((f) => f.kinds.contains(kind)).toList();
    matching.sort((a, b) => a.urgency.index.compareTo(b.urgency.index));
    return List.unmodifiable(matching);
  }

  static RedFlag? byCode(String code) {
    for (final f in all) {
      if (f.code == code) return f;
    }
    return null;
  }
}
