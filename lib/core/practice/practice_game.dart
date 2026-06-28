/// Generic, game-agnostic contract for single-player "Practice (solo)" mode.
///
/// A party game (Drawing Telephone, Trivia, …) owns its rules in a pure,
/// immutable state object. To make that game playable SOLO — one human plus a
/// few auto-playing bots, fully offline — the game only has to teach this
/// harness four things: who the bots are, whether it's the human's turn, how to
/// apply a submission, and what a bot would submit. Everything about *driving*
/// the bots to keep the game moving lives in [PracticeDriver], shared by every
/// game.
///
/// [TState] is the game's immutable state type (e.g. `TelephoneSession`).
///
/// Design goal: adding a new game to practice mode is just implementing this
/// small contract for that game's pure model plus a bot-fill function — no new
/// lifecycle code, no networking. The per-game UI stays per-game; the
/// bot-driving is reused.
abstract class PracticeGame<TState> {
  /// The human player's id (the person actually tapping the screen).
  String get humanUid;

  /// The auto-playing bot player ids. These turns are filled by [botContent].
  List<String> get botUids;

  /// True once the game has finished and there is nothing left to submit
  /// (e.g. the reveal/results phase has been reached).
  bool isDone(TState state);

  /// True if [uid] still owes a contribution for the current turn/step. The
  /// driver treats "the human still owes a submission" as "it's the human's
  /// turn" and hands control back to the UI.
  bool needsSubmission(TState state, String uid);

  /// Apply one player's submission and return the next state. Must be PURE —
  /// no mutation of [state] — so the same call is safe to retry.
  TState applySubmission(TState state, String uid, String content);

  /// Produce the contribution [botUid] would make for the current turn (a guess,
  /// an answer, an encoded scribble, …). May use randomness; never mutates.
  String botContent(TState state, String botUid);

  // ---- Generalised actions (optional) --------------------------------------
  // Most games only have one kind of move (a "submission"), so the two hooks
  // below default to [needsSubmission] / [applySubmission] and such games never
  // touch them. Games with MORE THAN ONE action type per round — e.g. Drawing
  // Telephone's same-prompt modes, which collect drawings AND then 1–10 ratings
  // — override these so the shared [PracticeDriver] can keep the bots moving
  // through every phase, not just the submission phase.

  /// True if [uid] still owes ANY action this turn (a submission, a rating, …).
  /// The driver treats "the human still owes an action" as "it's the human's
  /// turn" and hands control back to the UI.
  bool needsAction(TState state, String uid) => needsSubmission(state, uid);

  /// Perform the next pending action for [botUid] and return the new state.
  /// Defaults to a plain submission via [botContent]; override to also produce
  /// ratings or other non-submission moves. Must be PURE.
  TState applyBotAction(TState state, String botUid) =>
      applySubmission(state, botUid, botContent(state, botUid));
}
