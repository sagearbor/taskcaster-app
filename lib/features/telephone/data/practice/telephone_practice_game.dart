import 'dart:convert';
import 'dart:math';

import '../../../../core/models/telephone_session.dart';
import '../../../../core/practice/practice_game.dart';

/// Drawing Telephone as the first adopter of the generic practice harness.
///
/// This is the only Telephone-specific glue the [PracticeDriver] needs: it maps
/// the four [PracticeGame] hooks onto the pure [TelephoneSession] transforms and
/// teaches the bots how to scribble and quip. No networking, no Firestore —
/// every move runs against the in-memory model.
class TelephonePracticeGame extends PracticeGame<TelephoneSession> {
  @override
  final String humanUid;
  @override
  final List<String> botUids;

  final Random _rng;

  TelephonePracticeGame({
    required this.humanUid,
    required this.botUids,
    Random? random,
  }) : _rng = random ?? Random();

  // The game is finished at the reveal (classic chain) or the results screen
  // (same-prompt modes), so practice covers drawings AND ratings end-to-end.
  @override
  bool isDone(TelephoneSession state) => state.isFinished;

  @override
  bool needsSubmission(TelephoneSession state, String uid) =>
      state.isAwaitingSubmission(uid);

  @override
  TelephoneSession applySubmission(
          TelephoneSession state, String uid, String content) =>
      state.withSubmission(uid, content);

  /// A player still owes an action while they owe a drawing (playing) OR while
  /// they still have someone left to rate (rating). This is what lets the
  /// driver carry the bots through the rating phase, and stops on the human's
  /// turn whether they are drawing or rating.
  @override
  bool needsAction(TelephoneSession state, String uid) {
    if (state.isPlaying) return state.isAwaitingSubmission(uid);
    if (state.isRating) {
      return state.hasPlayer(uid) && !state.raterHasFinished(uid);
    }
    return false;
  }

  /// Bots draw during play and rate (plausibly, 5–9) during the rating phase.
  @override
  TelephoneSession applyBotAction(TelephoneSession state, String botUid) {
    if (state.isPlaying) {
      return state.withSubmission(botUid, botContent(state, botUid));
    }
    if (state.isRating) {
      final target = state.nextUnratedTarget(botUid);
      if (target == null) return state;
      return state.withRating(
        raterUid: botUid,
        targetUid: target,
        value: 5 + _rng.nextInt(5), // 5..9 — bots are generous but believable
      );
    }
    return state;
  }

  @override
  String botContent(TelephoneSession state, String botUid) {
    switch (state.currentEntryType) {
      case TelephoneEntryType.prompt:
        return _pick(_botPrompts);
      case TelephoneEntryType.guess:
        return _pick(_botGuesses);
      case TelephoneEntryType.drawing:
        return _botDrawingJson();
    }
  }

  String _pick(List<String> options) => options[_rng.nextInt(options.length)];

  /// A small canned "scribble": a few random strokes encoded in the EXACT JSON
  /// shape [DrawingStroke.toJson] produces (`{'c': colorInt, 'p': [x,y,…]}`),
  /// with points normalised to 0..1 — so `parseStrokes` / `DrawingView` render
  /// it identically to a human drawing.
  String _botDrawingJson() {
    final strokeCount = 2 + _rng.nextInt(3); // 2..4 strokes
    final strokes = <Map<String, dynamic>>[];
    for (var s = 0; s < strokeCount; s++) {
      final pointCount = 4 + _rng.nextInt(6); // 4..9 points
      final points = <double>[];
      var x = 0.15 + _rng.nextDouble() * 0.7;
      var y = 0.15 + _rng.nextDouble() * 0.7;
      for (var p = 0; p < pointCount; p++) {
        x = (x + (_rng.nextDouble() - 0.5) * 0.4).clamp(0.05, 0.95);
        y = (y + (_rng.nextDouble() - 0.5) * 0.4).clamp(0.05, 0.95);
        points.add(double.parse(x.toStringAsFixed(3)));
        points.add(double.parse(y.toStringAsFixed(3)));
      }
      strokes.add({'c': _botPenColors[_rng.nextInt(_botPenColors.length)], 'p': points});
    }
    return jsonEncode(strokes);
  }

  // ARGB pen colours, matching `kPenColors` in drawing_canvas.dart.
  static const List<int> _botPenColors = [
    0xFF000000, // black
    0xFFE53935, // red
    0xFF1E88E5, // blue
    0xFF43A047, // green
    0xFFFB8C00, // orange
    0xFF8E24AA, // purple
  ];

  static const List<String> _botPrompts = [
    'A penguin hosting a cooking show',
    'A robot walking three dogs at once',
    'A wizard losing a fight with an umbrella',
    'A cat CEO giving a big presentation',
    'A dinosaur trying to use a smartphone',
    'A banana riding a unicycle uphill',
    'A ghost who is afraid of the dark',
    'A snail winning an Olympic medal',
  ];

  static const List<String> _botGuesses = [
    'A very confused octopus',
    'My uncle at a wedding',
    'A potato having a great day',
    'Definitely a dog. Maybe a cloud.',
    'A haunted toaster',
    'Two worms sharing an umbrella',
    'A dragon doing yoga',
    'Someone who has never seen a horse',
  ];
}
