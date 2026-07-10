import 'package:uuid/uuid.dart';

import '../../../core/models/game.dart';
import '../../../core/models/player.dart';
import '../../../core/models/task.dart';
import '../../auth/domain/repositories/auth_repository.dart';
import '../../friends/domain/models/friend.dart';
import '../../friends/domain/repositories/invites_repository.dart';
import '../../games/domain/repositories/game_repository.dart';

/// The result of authoring + sending a House Hunt: enough for the caller to
/// drop the hider straight into the lobby and, if they skipped the friend
/// picker, share the [inviteCode].
class HouseHuntCreation {
  const HouseHuntCreation({
    required this.gameId,
    required this.inviteCode,
    required this.game,
  });

  final String gameId;
  final String inviteCode;
  final Game game;
}

/// Turns a hand of hunt prompts into a real, ordinary game and (optionally)
/// fires a one-tap invite at a faraway friend.
///
/// House Hunt is deliberately thin: it reuses the existing games collection,
/// the ordinary video/photo task type, the judging machinery and the friend
/// invite system unchanged. This service is the ONLY new backend-touching
/// code, and every write it makes fits the existing Firestore rules (a creator
/// creates their own game; the inviter stamps themselves on the invite).
class HouseHuntService {
  HouseHuntService({
    required this.authRepository,
    required this.gameRepository,
    required this.invitesRepository,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AuthRepository authRepository;
  final GameRepository gameRepository;
  final InvitesRepository invitesRepository;
  final Uuid _uuid;

  /// How many prompts make up one hunt (matches the deck).
  static const int huntSize = 5;

  /// Library category stamped on every hunt task.
  static const String category = 'House Hunt';

  /// The default game name for a hunt authored by [hiderName].
  static String gameNameFor(String hiderName) {
    final trimmed = hiderName.trim();
    final base = trimmed.isEmpty ? 'A Sneaky Hider' : trimmed;
    return "$base's House Hunt";
  }

  /// Whether [game] is a House Hunt, detected by its name convention. Used to
  /// decide when to offer "Send one back" on the winner ceremony. (Games carry
  /// no type field, and adding one would touch the shared model + rules, so the
  /// naming convention set by [gameNameFor] is the marker.)
  static bool isHouseHuntGame(Game game) =>
      game.gameName.trimRight().endsWith('House Hunt');

  /// Wrap a raw prompt in the hunt framing and build an ordinary video task —
  /// the seeker submits a photo/video link exactly like any other task.
  Task buildTask(String prompt) {
    final text = prompt.trim();
    return Task(
      id: _uuid.v4(),
      title: text,
      description: 'Hunt! $text Snap a photo or short video as your proof.',
      taskType: TaskType.video,
      submissions: const [],
      category: category,
    );
  }

  /// Author a hunt of exactly [huntSize] [prompts] (deck picks or custom text),
  /// create the lobby game with the hider as creator AND judge, then invite the
  /// seeker: a known [friend], or an [email], or neither (the caller shares the
  /// returned [HouseHuntCreation.inviteCode]).
  ///
  /// Throws [ArgumentError] if the wrong number of non-empty prompts is given,
  /// and [StateError] if there is no signed-in hider.
  Future<HouseHuntCreation> createAndSendHunt({
    required List<String> prompts,
    Friend? friend,
    String? email,
  }) async {
    final cleaned =
        prompts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (cleaned.length != huntSize) {
      throw ArgumentError('A House Hunt needs exactly $huntSize prompts.');
    }

    final hider = await authRepository.getCurrentUser();
    if (hider == null) {
      throw StateError('You need to be signed in to send a hunt.');
    }

    final gameName = gameNameFor(hider.displayName);

    // createGame seeds the lobby doc (owner + generated invite code); read it
    // back so the invite we send carries the SAME code that is on the game.
    final gameId = await gameRepository.createGame(gameName, hider.id, hider.id);
    final fresh = await gameRepository.getGameStream(gameId).first;
    if (fresh == null) {
      throw StateError('The hunt game vanished right after it was created.');
    }

    final complete = fresh.copyWith(
      gameName: gameName,
      players: [
        Player(
          userId: hider.id,
          displayName: hider.displayName,
          totalScore: 0,
        ),
      ],
      tasks: cleaned.map(buildTask).toList(),
      // The hider only judges — without this, startGame seeds the hider a
      // per-task status they'd never fulfil and the hunt could never complete.
      settings: fresh.settings.copyWith(judgePlays: false),
    );
    await gameRepository.updateGame(gameId, complete);

    // Land the hunt in the seeker's invite inbox exactly like any game invite.
    if (friend != null) {
      await invitesRepository.sendToFriend(friend.uid, complete);
    } else if (email != null && email.trim().isNotEmpty) {
      await invitesRepository.sendToEmail(email.trim(), complete);
    }

    return HouseHuntCreation(
      gameId: gameId,
      inviteCode: complete.inviteCode,
      game: complete,
    );
  }
}
