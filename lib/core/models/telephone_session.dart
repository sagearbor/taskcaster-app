import 'package:equatable/equatable.dart';

import 'session_mode.dart';
import 'telephone_prompts.dart';

/// What kind of contribution an entry in a chain is.
enum TelephoneEntryType { prompt, drawing, guess }

/// Lifecycle of a Drawing Telephone session.
///
/// Classic mode runs `lobby → playing → reveal`. The "Same prompt" modes add a
/// `rating` step (players score each other's drawings 1–10) and a `results`
/// step (winner + leaderboard): `lobby → playing → rating → results`.
enum TelephonePhase { lobby, playing, reveal, rating, results }

/// How a Drawing Telephone game plays out. Stored per session and fully
/// backward-compatible: documents written before this field existed parse back
/// to [classicTelephone].
enum TelephoneGameMode {
  /// The original Gartic-Phone style chain: prompt → draw → guess → …
  classicTelephone,

  /// Everyone draws the SAME shared prompt at the same time, then rates.
  samePrompt,

  /// Everyone draws the SAME shared prompt, but ONE player at a time, then
  /// rates.
  samePromptTurns;

  static TelephoneGameMode fromName(String? name) =>
      TelephoneGameMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => TelephoneGameMode.classicTelephone,
      );

  /// True for the two "everyone draws the same thing" modes (which add rating +
  /// results), false for the classic chain.
  bool get isSamePrompt => this == samePrompt || this == samePromptTurns;

  /// True only for the one-at-a-time variant.
  bool get isTurnTaking => this == samePromptTurns;
}

/// One contribution in a chain: a starting prompt, a freehand drawing, or a
/// text guess describing the previous drawing.
///
/// [content] is plain text for [TelephoneEntryType.prompt] and
/// [TelephoneEntryType.guess], and a lightweight JSON-encoded stroke list for
/// [TelephoneEntryType.drawing] (see `DrawingCanvas`).
class TelephoneEntry extends Equatable {
  final TelephoneEntryType type;
  final String content;
  final String authorUid;
  final String authorName;

  const TelephoneEntry({
    required this.type,
    required this.content,
    required this.authorUid,
    required this.authorName,
  });

  factory TelephoneEntry.fromMap(Map<String, dynamic> map) {
    return TelephoneEntry(
      type: TelephoneEntryType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => TelephoneEntryType.prompt,
      ),
      content: map['content'] as String? ?? '',
      authorUid: map['authorUid'] as String? ?? '',
      authorName: map['authorName'] as String? ?? 'Player',
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'content': content,
        'authorUid': authorUid,
        'authorName': authorName,
      };

  @override
  List<Object?> get props => [type, content, authorUid, authorName];
}

/// One player's 1–10 rating of another player's drawing.
///
/// Serialized as a flat map (NOT a nested array) so it is Firestore-safe. The
/// invariant "you cannot rate your own drawing" is enforced where ratings are
/// applied ([TelephoneSession.withRating]).
class DrawingRating extends Equatable {
  /// Who gave the rating.
  final String raterUid;

  /// The author of the drawing being rated.
  final String targetUid;

  /// 1..10.
  final int value;

  const DrawingRating({
    required this.raterUid,
    required this.targetUid,
    required this.value,
  });

  factory DrawingRating.fromMap(Map<String, dynamic> map) => DrawingRating(
        raterUid: map['raterUid'] as String? ?? '',
        targetUid: map['targetUid'] as String? ?? '',
        value: (map['value'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'raterUid': raterUid,
        'targetUid': targetUid,
        'value': value,
      };

  @override
  List<Object?> get props => [raterUid, targetUid, value];
}

/// A player in a Drawing Telephone session. Identity is a per-session id (not
/// the Firebase auth uid) so two browser tabs on the same anonymous account —
/// or two guests — are still distinct players.
class TelephonePlayer extends Equatable {
  final String uid;
  final String displayName;

  const TelephonePlayer({required this.uid, required this.displayName});

  factory TelephonePlayer.fromMap(Map<String, dynamic> map) {
    return TelephonePlayer(
      uid: map['uid'] as String,
      displayName: map['displayName'] as String? ?? 'Player',
    );
  }

  Map<String, dynamic> toMap() => {'uid': uid, 'displayName': displayName};

  @override
  List<Object?> get props => [uid, displayName];
}

/// The live state of a Drawing Telephone game.
///
/// This model owns ALL of the game's pure logic — chain assignment, the
/// phase-gated step advance, reveal assembly, rating tally and the winner /
/// running leaderboard — so the rules are identical whether they run against
/// the mock data source (tests), inside a Firestore transaction (online play),
/// over Nearby (offline play) or in solo Practice. Data sources stay dumb: they
/// persist [toMap]/[fromMap] and apply transforms; they never re-implement game
/// rules.
///
/// ## Classic chain mechanics ([TelephoneGameMode.classicTelephone])
/// Players are kept in a fixed order. There is exactly one chain per player;
/// chain `i` is *started* by `players[i]` (their prompt). On each [step], every
/// player contributes exactly one entry, and the chains rotate so nobody ever
/// works on their own chain twice in a row:
///
///   chainIndexForPlayer(p, step) = (p - step) mod N
///
/// So for chain `c`, the author at step `s` is `players[(c + s) mod N]`. Over
/// `N` steps each chain collects `N` entries, one from every distinct player.
/// Entry type by step: step 0 is a prompt; odd steps are drawings; even steps
/// (>0) are guesses → prompt → draw → guess → draw → guess …
///
/// ## Same-prompt mechanics ([TelephoneGameMode.samePrompt] / [samePromptTurns])
/// Every player draws the SAME shared [prompt]. Each player owns chain `i`
/// containing a single drawing entry (their take on the prompt). In [samePrompt]
/// everyone draws at once; in [samePromptTurns] one player draws at a time
/// (the active drawer is `players[step]`). When all drawings are in the game
/// moves to [TelephonePhase.rating]; once everyone has rated everyone else it
/// moves to [TelephonePhase.results], which crowns a winner and folds this
/// round's points into the running [tallyPoints] / [roundsWon] leaderboard that
/// survives "Play again".
class TelephoneSession extends Equatable {
  final String id;
  final String gameName;
  final SessionMode mode;
  final TelephoneGameMode gameMode;
  final String inviteCode;
  final String creatorUid;
  final DateTime createdAt;
  final List<TelephonePlayer> players;
  final TelephonePhase phase;

  /// 0-based index of the step currently being filled while [phase] is
  /// [TelephonePhase.playing].
  final int step;

  /// The shared prompt everyone draws in the same-prompt modes. Empty for the
  /// classic chain (where each player writes their own).
  final String prompt;

  /// One chain per player, in player order. Each chain is an ordered list of
  /// entries. Empty until the game starts.
  final List<List<TelephoneEntry>> chains;

  /// Player uids that have already submitted the CURRENT [step]. Reset to empty
  /// each time the step advances / the phase changes. Drives the live "waiting
  /// on N players" UI.
  final List<String> submittedUids;

  /// Ratings collected during [TelephonePhase.rating]. One entry per
  /// (rater, target) pair.
  final List<DrawingRating> ratings;

  /// 1-based round counter. Increments on every "Play again".
  final int roundNumber;

  /// Running cumulative score (sum of received ratings) per player across ALL
  /// rounds in this group. Persists across "Play again".
  final Map<String, int> tallyPoints;

  /// How many rounds each player has won, across the whole session. Persists
  /// across "Play again".
  final Map<String, int> roundsWon;

  const TelephoneSession({
    required this.id,
    required this.gameName,
    required this.mode,
    required this.gameMode,
    required this.inviteCode,
    required this.creatorUid,
    required this.createdAt,
    required this.players,
    required this.phase,
    required this.step,
    required this.prompt,
    required this.chains,
    required this.submittedUids,
    required this.ratings,
    required this.roundNumber,
    required this.tallyPoints,
    required this.roundsWon,
  });

  /// A fresh session sitting in the lobby with just the creator present.
  factory TelephoneSession.create({
    required String id,
    required String gameName,
    required String inviteCode,
    required String creatorUid,
    required String creatorName,
    TelephoneGameMode gameMode = TelephoneGameMode.classicTelephone,
    DateTime? createdAt,
  }) {
    return TelephoneSession(
      id: id,
      gameName: gameName,
      mode: SessionMode.party,
      gameMode: gameMode,
      inviteCode: inviteCode,
      creatorUid: creatorUid,
      createdAt: createdAt ?? DateTime.now(),
      players: [TelephonePlayer(uid: creatorUid, displayName: creatorName)],
      phase: TelephonePhase.lobby,
      step: 0,
      prompt: '',
      chains: const [],
      submittedUids: const [],
      ratings: const [],
      roundNumber: 1,
      tallyPoints: const {},
      roundsWon: const {},
    );
  }

  factory TelephoneSession.fromMap(Map<String, dynamic> map) {
    return TelephoneSession(
      id: map['id'] as String,
      gameName: map['gameName'] as String? ?? 'Drawing Telephone',
      mode: SessionMode.fromName(map['mode'] as String?,
          fallback: SessionMode.party),
      gameMode: TelephoneGameMode.fromName(map['gameMode'] as String?),
      inviteCode: map['inviteCode'] as String? ?? '',
      creatorUid: map['creatorUid'] as String? ?? '',
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      players: (map['players'] as List<dynamic>?)
              ?.map((e) =>
                  TelephonePlayer.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      phase: TelephonePhase.values.firstWhere(
        (p) => p.name == map['phase'],
        orElse: () => TelephonePhase.lobby,
      ),
      step: map['step'] as int? ?? 0,
      prompt: map['prompt'] as String? ?? '',
      chains: (map['chains'] as List<dynamic>?)
              ?.map((chain) {
                // New form: each chain is {'entries': [...]}. Tolerate the old
                // raw-list form too for any in-flight sessions.
                final entries = chain is Map
                    ? (chain['entries'] as List<dynamic>? ?? const [])
                    : (chain as List<dynamic>);
                return entries
                    .map((e) => TelephoneEntry.fromMap(
                        Map<String, dynamic>.from(e as Map)))
                    .toList();
              })
              .toList() ??
          const [],
      submittedUids: (map['submittedUids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      ratings: (map['ratings'] as List<dynamic>?)
              ?.map((e) =>
                  DrawingRating.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      roundNumber: map['roundNumber'] as int? ?? 1,
      tallyPoints: _intMapFrom(map['tallyPoints']),
      roundsWon: _intMapFrom(map['roundsWon']),
    );
  }

  static Map<String, int> _intMapFrom(dynamic raw) {
    if (raw is! Map) return const {};
    return raw.map(
        (key, value) => MapEntry(key as String, (value as num).toInt()));
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'gameName': gameName,
        'mode': mode.name,
        'gameMode': gameMode.name,
        'inviteCode': inviteCode,
        'creatorUid': creatorUid,
        'createdAt': createdAt.toIso8601String(),
        'players': players.map((p) => p.toMap()).toList(),
        'phase': phase.name,
        'step': step,
        'prompt': prompt,
        // Firestore forbids an array that directly contains another array, so
        // each chain is wrapped in a map: [{entries:[...]}, {entries:[...]}].
        // Writing a raw List<List<...>> here is what caused the
        // "[cloud_firestore/unknown]" failure when starting a game.
        'chains': chains
            .map((c) => {'entries': c.map((e) => e.toMap()).toList()})
            .toList(),
        'submittedUids': submittedUids,
        'ratings': ratings.map((r) => r.toMap()).toList(),
        'roundNumber': roundNumber,
        'tallyPoints': tallyPoints,
        'roundsWon': roundsWon,
      };

  TelephoneSession copyWith({
    String? gameName,
    SessionMode? mode,
    TelephoneGameMode? gameMode,
    List<TelephonePlayer>? players,
    TelephonePhase? phase,
    int? step,
    String? prompt,
    List<List<TelephoneEntry>>? chains,
    List<String>? submittedUids,
    List<DrawingRating>? ratings,
    int? roundNumber,
    Map<String, int>? tallyPoints,
    Map<String, int>? roundsWon,
  }) {
    return TelephoneSession(
      id: id,
      gameName: gameName ?? this.gameName,
      mode: mode ?? this.mode,
      gameMode: gameMode ?? this.gameMode,
      inviteCode: inviteCode,
      creatorUid: creatorUid,
      createdAt: createdAt,
      players: players ?? this.players,
      phase: phase ?? this.phase,
      step: step ?? this.step,
      prompt: prompt ?? this.prompt,
      chains: chains ?? this.chains,
      submittedUids: submittedUids ?? this.submittedUids,
      ratings: ratings ?? this.ratings,
      roundNumber: roundNumber ?? this.roundNumber,
      tallyPoints: tallyPoints ?? this.tallyPoints,
      roundsWon: roundsWon ?? this.roundsWon,
    );
  }

  // ---- Derived helpers -----------------------------------------------------

  int get playerCount => players.length;

  bool get isInLobby => phase == TelephonePhase.lobby;
  bool get isPlaying => phase == TelephonePhase.playing;
  bool get isRevealing => phase == TelephonePhase.reveal;
  bool get isRating => phase == TelephonePhase.rating;
  bool get isShowingResults => phase == TelephonePhase.results;

  /// True once the game has reached its terminal phase for this mode (reveal
  /// for the classic chain, results for the same-prompt modes). Drives the
  /// "Play again" affordance and the solo Practice harness's `isDone`.
  bool get isFinished =>
      gameMode.isSamePrompt ? isShowingResults : isRevealing;

  /// Total number of drawing/play steps the game will run.
  ///  * Classic: one step per player (prompt → draw → guess → …).
  ///  * Same prompt (simultaneous): a single step — everyone draws at once.
  ///  * Same prompt (turns): one step per player — each takes a turn.
  int get totalSteps {
    if (gameMode == TelephoneGameMode.samePrompt) return 1;
    return playerCount; // classic and samePromptTurns
  }

  int orderIndexOf(String uid) => players.indexWhere((p) => p.uid == uid);

  bool hasPlayer(String uid) => orderIndexOf(uid) != -1;

  /// Which chain a player works on at [step] in the CLASSIC chain (positive
  /// modulo). In the same-prompt modes a player always owns their own chain.
  int chainIndexForPlayer(int orderIndex, int step) {
    final n = playerCount;
    return ((orderIndex - step) % n + n) % n;
  }

  /// The entry type expected at [step] in the classic chain: prompt → draw →
  /// guess → draw → guess …
  static TelephoneEntryType expectedTypeForStep(int step) {
    if (step == 0) return TelephoneEntryType.prompt;
    return step.isOdd ? TelephoneEntryType.drawing : TelephoneEntryType.guess;
  }

  /// The entry type the current step collects. Always a drawing in the
  /// same-prompt modes.
  TelephoneEntryType get currentEntryType => gameMode.isSamePrompt
      ? TelephoneEntryType.drawing
      : expectedTypeForStep(step);

  /// True once every player has submitted the current step (classic) /
  /// every drawing is in (same prompt).
  bool get allSubmittedCurrentStep =>
      isPlaying && submittedUids.length >= playerCount;

  bool hasSubmittedCurrentStep(String uid) => submittedUids.contains(uid);

  /// True when [uid] still owes a contribution RIGHT NOW. In turn-taking only
  /// the active drawer (`players[step]`) owes one; in every other mode every
  /// player who hasn't submitted owes one.
  bool isAwaitingSubmission(String uid) {
    if (!isPlaying || !hasPlayer(uid)) return false;
    if (hasSubmittedCurrentStep(uid)) return false;
    if (gameMode.isTurnTaking) return orderIndexOf(uid) == step;
    return true;
  }

  /// In turn-taking, the player whose turn it is to draw right now (or null).
  TelephonePlayer? get activeDrawer {
    if (!isPlaying || !gameMode.isTurnTaking) return null;
    if (step < 0 || step >= playerCount) return null;
    return players[step];
  }

  /// The chain index [uid] is responsible for on the current step, or null if
  /// the player is not in a position to submit (not playing / not a player).
  int? assignedChainForUid(String uid) {
    if (!isPlaying) return null;
    final idx = orderIndexOf(uid);
    if (idx == -1) return null;
    // In the same-prompt modes you always draw into your OWN chain.
    if (gameMode.isSamePrompt) return idx;
    return chainIndexForPlayer(idx, step);
  }

  /// The previous entry [uid] must respond to this step (the prompt to draw, or
  /// the drawing to guess). Null on the prompt step, and null in the
  /// same-prompt modes (where the thing to draw is the shared [prompt]).
  TelephoneEntry? promptEntryForUid(String uid) {
    if (!isPlaying || gameMode.isSamePrompt || step == 0) return null;
    final chainIdx = assignedChainForUid(uid);
    if (chainIdx == null) return null;
    final chain = chains[chainIdx];
    return chain.length >= step ? chain[step - 1] : null;
  }

  /// The single drawing the player at [orderIndex] made of the shared prompt,
  /// or null. Same-prompt modes only.
  TelephoneEntry? drawingForOrderIndex(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= chains.length) return null;
    final chain = chains[orderIndex];
    return chain.isEmpty ? null : chain.first;
  }

  TelephoneEntry? drawingForUid(String uid) =>
      drawingForOrderIndex(orderIndexOf(uid));

  // ---- Pure state transitions ----------------------------------------------

  /// Add a player in the lobby. Idempotent — a uid already present is returned
  /// unchanged, so joining twice (or racing the host) is safe.
  TelephoneSession withPlayerJoined(String uid, String displayName) {
    if (!isInLobby || hasPlayer(uid)) return this;
    return copyWith(players: [
      ...players,
      TelephonePlayer(uid: uid, displayName: displayName),
    ]);
  }

  /// Remove a player from the lobby roster (a host "kick"). No-op if the game
  /// has left the lobby, the uid is the creator (the host can't be removed),
  /// or the uid isn't present. Pure — returns a new session.
  TelephoneSession withPlayerRemoved(String uid) {
    if (!isInLobby) return this;
    if (uid == creatorUid) return this;
    if (!hasPlayer(uid)) return this;
    return copyWith(
      players: players.where((p) => p.uid != uid).toList(),
    );
  }

  /// Begin play: lock the roster, create one empty chain per player, and move
  /// to step 0. In the same-prompt modes a shared [prompt] is chosen (the
  /// caller may pass one; otherwise a deterministic prompt is picked from the
  /// bank). Throws if called outside the lobby or with too few players.
  /// Idempotent-safe: re-starting an already-playing game is a no-op.
  TelephoneSession started({String? prompt}) {
    if (phase != TelephonePhase.lobby) return this;
    if (playerCount < 2) {
      throw StateError('Need at least 2 players to start');
    }
    final chosenPrompt =
        gameMode.isSamePrompt ? _resolvePrompt(prompt, roundNumber) : '';
    return copyWith(
      phase: TelephonePhase.playing,
      step: 0,
      prompt: chosenPrompt,
      chains: List.generate(playerCount, (_) => <TelephoneEntry>[]),
      submittedUids: const [],
      ratings: const [],
    );
  }

  String _resolvePrompt(String? supplied, int round) {
    if (supplied != null && supplied.trim().isNotEmpty) return supplied.trim();
    return TelephonePrompts.pick(id.hashCode ^ (round * 2654435761));
  }

  /// Apply one player's submission for the current step.
  ///
  /// Classic: appends to the player's assigned (rotating) chain and advances
  /// once every player has submitted, flipping to [TelephonePhase.reveal] after
  /// the last step. Same-prompt: appends the drawing to the player's OWN chain;
  /// in turn-taking it advances the active-drawer pointer; once all drawings are
  /// in it flips to [TelephonePhase.rating]. Re-submitting is ignored
  /// (idempotent), which makes this safe to retry and to run inside a Firestore
  /// transaction.
  TelephoneSession withSubmission(String uid, String content) {
    if (!isPlaying) return this;
    final orderIndex = orderIndexOf(uid);
    if (orderIndex == -1) return this;
    if (hasSubmittedCurrentStep(uid)) return this;

    if (gameMode.isSamePrompt) {
      return _withSamePromptSubmission(uid, orderIndex, content);
    }
    return _withClassicSubmission(uid, orderIndex, content);
  }

  TelephoneSession _withClassicSubmission(
      String uid, int orderIndex, String content) {
    final chainIndex = chainIndexForPlayer(orderIndex, step);
    final entry = TelephoneEntry(
      type: currentEntryType,
      content: content,
      authorUid: uid,
      authorName: players[orderIndex].displayName,
    );

    final newChains = chains.map((c) => List<TelephoneEntry>.from(c)).toList();
    newChains[chainIndex].add(entry);
    final newSubmitted = [...submittedUids, uid];

    if (newSubmitted.length >= playerCount) {
      final nextStep = step + 1;
      if (nextStep >= totalSteps) {
        return copyWith(
          chains: newChains,
          submittedUids: const [],
          phase: TelephonePhase.reveal,
          step: nextStep,
        );
      }
      return copyWith(
        chains: newChains,
        submittedUids: const [],
        step: nextStep,
      );
    }
    return copyWith(chains: newChains, submittedUids: newSubmitted);
  }

  TelephoneSession _withSamePromptSubmission(
      String uid, int orderIndex, String content) {
    // Turn-taking: only the active drawer may submit right now.
    if (gameMode.isTurnTaking && orderIndex != step) return this;

    final entry = TelephoneEntry(
      type: TelephoneEntryType.drawing,
      content: content,
      authorUid: uid,
      authorName: players[orderIndex].displayName,
    );

    final newChains = chains.map((c) => List<TelephoneEntry>.from(c)).toList();
    newChains[orderIndex].add(entry); // your own chain
    final newSubmitted = [...submittedUids, uid];

    // Every drawing is in → move to rating.
    if (newSubmitted.length >= playerCount) {
      return copyWith(
        chains: newChains,
        submittedUids: const [],
        phase: TelephonePhase.rating,
      );
    }
    // Turn-taking advances the active-drawer pointer to the next player.
    if (gameMode.isTurnTaking) {
      return copyWith(
        chains: newChains,
        submittedUids: newSubmitted,
        step: step + 1,
      );
    }
    return copyWith(chains: newChains, submittedUids: newSubmitted);
  }

  // ---- Rating & results ----------------------------------------------------

  /// Has [raterUid] rated every OTHER player's drawing?
  bool raterHasFinished(String raterUid) {
    if (!hasPlayer(raterUid)) return false;
    return players
        .where((p) => p.uid != raterUid)
        .every((p) => _hasRated(raterUid, p.uid));
  }

  bool _hasRated(String raterUid, String targetUid) =>
      ratings.any((r) => r.raterUid == raterUid && r.targetUid == targetUid);

  /// The current value [raterUid] gave [targetUid], or null if not yet rated.
  int? ratingValue(String raterUid, String targetUid) {
    for (final r in ratings) {
      if (r.raterUid == raterUid && r.targetUid == targetUid) return r.value;
    }
    return null;
  }

  /// The next player [raterUid] still has to rate (in player order), or null if
  /// they have rated everyone. Used by the solo-practice bots.
  String? nextUnratedTarget(String raterUid) {
    for (final p in players) {
      if (p.uid == raterUid) continue;
      if (!_hasRated(raterUid, p.uid)) return p.uid;
    }
    return null;
  }

  /// Apply (or update) one rating. Enforces the core rules:
  ///  * only valid while in [TelephonePhase.rating];
  ///  * both rater and target must be players;
  ///  * a player CANNOT rate their own drawing;
  ///  * the value is ignored unless it is 1..10.
  ///
  /// Re-rating the same target replaces the previous value (a player can change
  /// their mind before everyone is done). When the final outstanding rating
  /// lands, the round is tallied into the running leaderboard and the game
  /// flips to [TelephonePhase.results].
  TelephoneSession withRating({
    required String raterUid,
    required String targetUid,
    required int value,
  }) {
    if (!isRating) return this;
    if (raterUid == targetUid) return this; // can't rate your own drawing
    if (!hasPlayer(raterUid) || !hasPlayer(targetUid)) return this;
    if (value < 1 || value > 10) return this;

    final newRatings = ratings
        .where((r) => !(r.raterUid == raterUid && r.targetUid == targetUid))
        .toList()
      ..add(DrawingRating(
          raterUid: raterUid, targetUid: targetUid, value: value));

    final complete = players.every((p) => players
        .where((q) => q.uid != p.uid)
        .every((q) =>
            newRatings.any((r) => r.raterUid == p.uid && r.targetUid == q.uid)));

    if (!complete) {
      return copyWith(ratings: newRatings);
    }

    // Tally this round into the running leaderboard, then reveal results.
    final roundScores = _scoresFrom(newRatings);
    final newTally = Map<String, int>.from(tallyPoints);
    roundScores.forEach((uid, v) {
      newTally[uid] = (newTally[uid] ?? 0) + v;
    });

    final maxScore = roundScores.values.fold<int>(0, (m, v) => v > m ? v : m);
    final newRoundsWon = Map<String, int>.from(roundsWon);
    if (maxScore > 0) {
      for (final entry in roundScores.entries) {
        if (entry.value == maxScore) {
          newRoundsWon[entry.key] = (newRoundsWon[entry.key] ?? 0) + 1;
        }
      }
    }

    return copyWith(
      ratings: newRatings,
      phase: TelephonePhase.results,
      tallyPoints: newTally,
      roundsWon: newRoundsWon,
    );
  }

  Map<String, int> _scoresFrom(List<DrawingRating> rs) {
    final scores = <String, int>{for (final p in players) p.uid: 0};
    for (final r in rs) {
      if (scores.containsKey(r.targetUid)) {
        scores[r.targetUid] = (scores[r.targetUid] ?? 0) + r.value;
      }
    }
    return scores;
  }

  /// This round's score (sum of received ratings) per player uid.
  Map<String, int> get roundScores => _scoresFrom(ratings);

  /// This round's average received rating per player uid (0 if unrated).
  Map<String, double> get roundAverages {
    final counts = <String, int>{for (final p in players) p.uid: 0};
    for (final r in ratings) {
      if (counts.containsKey(r.targetUid)) {
        counts[r.targetUid] = (counts[r.targetUid] ?? 0) + 1;
      }
    }
    final sums = _scoresFrom(ratings);
    return {
      for (final p in players)
        p.uid: (counts[p.uid] ?? 0) == 0
            ? 0.0
            : (sums[p.uid] ?? 0) / (counts[p.uid] ?? 1)
    };
  }

  /// Players ordered by this round's score (highest first); ties broken by the
  /// running tally then name, for a stable display.
  List<TelephonePlayer> get roundLeaderboard {
    final scores = roundScores;
    final sorted = [...players];
    sorted.sort((a, b) {
      final byRound = (scores[b.uid] ?? 0).compareTo(scores[a.uid] ?? 0);
      if (byRound != 0) return byRound;
      final byTally =
          (tallyPoints[b.uid] ?? 0).compareTo(tallyPoints[a.uid] ?? 0);
      if (byTally != 0) return byTally;
      return a.displayName.compareTo(b.displayName);
    });
    return sorted;
  }

  /// Players ordered by the running cumulative tally (highest first).
  List<TelephonePlayer> get overallLeaderboard {
    final sorted = [...players];
    sorted.sort((a, b) {
      final byTally =
          (tallyPoints[b.uid] ?? 0).compareTo(tallyPoints[a.uid] ?? 0);
      if (byTally != 0) return byTally;
      final byWins = (roundsWon[b.uid] ?? 0).compareTo(roundsWon[a.uid] ?? 0);
      if (byWins != 0) return byWins;
      return a.displayName.compareTo(b.displayName);
    });
    return sorted;
  }

  /// The uid(s) with the top score this round (more than one ⇒ a tie). Empty
  /// if nobody scored.
  List<String> get winnerUids {
    final scores = roundScores;
    final maxScore = scores.values.fold<int>(0, (m, v) => v > m ? v : m);
    if (maxScore <= 0) return const [];
    return [
      for (final entry in scores.entries)
        if (entry.value == maxScore) entry.key
    ];
  }

  /// Start a fresh round with the SAME players, mode and settings — the
  /// one-tap "Play again". The running [tallyPoints] / [roundsWon] leaderboard
  /// and [roundNumber] carry over (and increment); chains, submissions and
  /// ratings reset. Only valid from a terminal phase ([reveal]/[results]), so a
  /// second concurrent tap is a harmless no-op.
  TelephoneSession playAgain({String? prompt}) {
    if (phase != TelephonePhase.reveal && phase != TelephonePhase.results) {
      return this;
    }
    final nextRound = roundNumber + 1;
    final newPrompt =
        gameMode.isSamePrompt ? _resolvePrompt(prompt, nextRound) : '';
    return copyWith(
      phase: TelephonePhase.playing,
      step: 0,
      prompt: newPrompt,
      chains: List.generate(playerCount, (_) => <TelephoneEntry>[]),
      submittedUids: const [],
      ratings: const [],
      roundNumber: nextRound,
      // tallyPoints & roundsWon intentionally carried over (running tally).
    );
  }

  @override
  List<Object?> get props => [
        id,
        gameName,
        mode,
        gameMode,
        inviteCode,
        creatorUid,
        createdAt,
        players,
        phase,
        step,
        prompt,
        chains,
        submittedUids,
        ratings,
        roundNumber,
        tallyPoints,
        roundsWon,
      ];
}
