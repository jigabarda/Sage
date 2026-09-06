import '../../constants/episode_kind.dart';

/// How fast someone needs to act on a red flag.
///
/// This is **routing, not scoring.** Both levels stop self-care advice
/// outright; they differ only in what the escalation screen tells the person to
/// do. Collapsing them would mean either telling someone with unexplained
/// weight loss to call an ambulance, or telling someone with a thunderclap
/// headache to book an appointment. Both are wrong, and the second is
/// dangerous.
enum RedFlagUrgency {
  /// Emergency services or an emergency department, now.
  emergency,

  /// A doctor within days, not weeks. Still not something this app advises on.
  urgent,
}

/// A pattern that means "stop advising and send them to a person".
///
/// Every field is fixed text compiled into the app. There is no model here and
/// there must never be one: this is the one path in Sage where being wrong has
/// a consequence that cannot be undone by editing a row later.
class RedFlag {
  const RedFlag({
    required this.code,
    required this.question,
    required this.because,
    required this.urgency,
    required this.kinds,
  });

  /// Stable identifier, written into `chat_messages` when this fires so the
  /// doctor export shows what the app reacted to.
  final String code;

  /// What the user reads, in the second person and in plain words.
  ///
  /// Written to be answerable by someone in pain who is not a clinician.
  /// "Sudden, severe headache that peaked within a minute" is a description
  /// someone can match against; "thunderclap headache" is a term they would
  /// have to already know.
  final String question;

  /// Why this is being escalated, shown on the escalation screen.
  ///
  /// Names the *concern*, never a diagnosis — "this can be a sign of bleeding
  /// around the brain" rather than "you have a subarachnoid haemorrhage". The
  /// app is not diagnosing; it is explaining why it stopped talking.
  final String because;

  final RedFlagUrgency urgency;

  /// Which condition's safety check offers this. Cardiac patterns appear under
  /// reflux because that is where chest pain gets misread as heartburn.
  final Set<EpisodeKind> kinds;
}
