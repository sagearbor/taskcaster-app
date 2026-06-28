import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../../core/models/telephone_session.dart';
import '../../../../core/practice/practice_driver.dart';
import '../../domain/repositories/telephone_repository.dart';
import 'telephone_practice_game.dart';

/// A fully-offline [TelephoneRepository] for "Practice (solo)" mode.
///
/// It holds ONE Drawing Telephone session entirely in memory — no Firestore, no
/// invite code, no waiting — and drives two auto-playing bots through the shared
/// [PracticeDriver]. Because it satisfies the same [TelephoneRepository]
/// interface the real game uses, the existing Telephone bloc and screens run
/// against it UNCHANGED: the human plays each step on the normal UI, and the
/// instant they submit, the bots fill their turns so the game always advances —
/// straight through to the reveal where the human sees every chain.
class LocalPracticeTelephoneRepository implements TelephoneRepository {
  static const String _botOneUid = 'practice-bot-1';
  static const String _botTwoUid = 'practice-bot-2';
  static const String _botOneName = 'Doodlebot';
  static const String _botTwoName = 'Scribbletron';

  final Uuid _uuid;
  late final PracticeDriver<TelephoneSession> _driver;

  final _controller = StreamController<TelephoneSession?>.broadcast();
  TelephoneSession? _session;

  LocalPracticeTelephoneRepository({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  /// Build the local session (human + 2 bots) and start play immediately, so
  /// the session screen opens straight onto the first step — no lobby, no
  /// "Start" button, no second device. Returns the new session id.
  Future<String> startPractice({
    required String humanUid,
    required String humanName,
    TelephoneGameMode gameMode = TelephoneGameMode.classicTelephone,
    Random? random,
  }) async {
    _driver = PracticeDriver<TelephoneSession>(
      TelephonePracticeGame(
        humanUid: humanUid,
        botUids: const [_botOneUid, _botTwoUid],
        random: random,
      ),
    );

    final id = _uuid.v4();
    var session = TelephoneSession.create(
      id: id,
      gameName: 'Practice (solo)',
      inviteCode: 'SOLO',
      creatorUid: humanUid,
      creatorName: humanName,
      gameMode: gameMode,
    )
        .withPlayerJoined(_botOneUid, _botOneName)
        .withPlayerJoined(_botTwoUid, _botTwoName)
        .started();

    // Fill any bot turns that would precede the human's first move (none for
    // Telephone, but keeps the harness honest).
    session = _driver.primed(session);

    _session = session;
    _emit();
    return id;
  }

  void _emit() => _controller.add(_session);

  @override
  Stream<TelephoneSession?> watchSession(String sessionId) async* {
    yield _session;
    yield* _controller.stream;
  }

  @override
  Future<void> submitEntry({
    required String sessionId,
    required String uid,
    required String content,
  }) async {
    final current = _session;
    if (current == null || !current.isPlaying) return;
    // Apply the human's move, then let the driver auto-fill the bots up to the
    // human's next turn (or the reveal).
    _session = _driver.submitHuman(current, content);
    _emit();
  }

  @override
  Future<void> submitRating({
    required String sessionId,
    required String raterUid,
    required String targetUid,
    required int value,
  }) async {
    final current = _session;
    if (current == null || !current.isRating) return;
    // Apply the human's rating, then let the bots catch up on their own ratings
    // (and roll into the results screen once everyone has rated everyone).
    final rated = current.withRating(
      raterUid: raterUid,
      targetUid: targetUid,
      value: value,
    );
    _session = _driver.advanceBots(rated);
    _emit();
  }

  @override
  Future<void> playAgain(String sessionId) async {
    final current = _session;
    if (current == null) return;
    // Reset to a fresh round (same crew, running tally carried), then prime any
    // bot turns that precede the human's next move.
    _session = _driver.primed(current.playAgain());
    _emit();
  }

  // ---- Lobby/networking actions are unused in offline practice -------------

  @override
  Future<void> startGame(String sessionId) async {
    // The session is already playing; nothing to do.
  }

  @override
  Future<void> removePlayer({
    required String sessionId,
    required String uid,
  }) async {
    // No roster management in solo practice.
  }

  @override
  Future<({String sessionId, String inviteCode})> createSession({
    required String creatorUid,
    required String creatorName,
    String? gameName,
    TelephoneGameMode gameMode = TelephoneGameMode.classicTelephone,
  }) {
    throw UnsupportedError(
        'Practice mode is local-only; use startPractice() instead.');
  }

  @override
  Future<String> joinSession({
    required String inviteCode,
    required String uid,
    required String displayName,
  }) {
    throw UnsupportedError('Practice mode has no invite codes to join.');
  }

  void dispose() {
    _controller.close();
  }
}
