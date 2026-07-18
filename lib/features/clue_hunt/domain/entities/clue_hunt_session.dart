import 'package:equatable/equatable.dart';

import 'clue_player.dart';

export 'clue_player.dart';

/// The lifecycle of a Clue Hunt round-based game.
///  * [lobby]       — host advertises, players join, nobody is hiding yet.
///  * [hiding]      — the current hider is physically hiding the real object.
///                    Seekers wait; the heat meter is dormant.
///  * [seeking]     — seekers roam; the hider drives the warmer/colder meter and
///                    the heat broadcasts live to every seeker's phone.
///  * [roundResult] — a find was confirmed; who found it and the points earned
///                    are frozen and shown to all, with running totals.
///  * [gameOver]    — every round is done; the winner ceremony plays.
enum CluePhase { lobby, hiding, seeking, roundResult, gameOver }

/// The single authoritative state of a Clue Hunt game, owned by the HOST phone
/// and broadcast verbatim to every other phone over the offline Nearby
/// transport.
///
/// The hider role rotates every round ([hiderId]); the host phone stays the
/// permanent authority that owns the roster, round state and running scores —
/// exactly like [BalloonBlitzRepository]/[BlitzSession]. All mutations here are
/// PURE (they return a new [ClueHuntSession] and never touch the transport), so
/// the whole game — scoring, first-claim-wins, role rotation, winner ordering —
/// is fully unit-testable with no device.
///
/// Note: live HEAT is deliberately NOT part of this session. It updates several
/// times a second, so it travels as its own tiny throttled `heat` message rather
/// than riding on (and starving) these authoritative snapshots.
class ClueHuntSession extends Equatable {
  /// Player id of the host — the permanent authority that owns this state.
  final String hostId;

  /// Everyone in the game, including the host. Insertion order is join order,
  /// and also the fixed order the hider role rotates through.
  final List<CluePlayer> players;

  /// Where we are in the game lifecycle.
  final CluePhase phase;

  /// Player id of the CURRENT round's hider (the human "sensor" who drives the
  /// heat meter and confirms/rejects finds).
  final String hiderId;

  /// 1-based index of the current round.
  final int roundNumber;

  /// How many rounds the whole game lasts (each round = one hider).
  final int totalRounds;

  /// The seeker who has claimed "Found it!" and is awaiting the hider's verdict,
  /// or null when nobody is claiming. Only ONE claim can be pending (first wins).
  final String? pendingClaimBy;

  /// Host wall-clock (epoch ms) of when the current SEEK started, used to score
  /// a confirmed find by how fast it was. Null outside an active seek.
  final int? roundStartEpochMs;

  /// The seeker who found the object in the most recently resolved round, shown
  /// on the round-result screen. Null until the first confirmed find.
  final String? lastFinderId;

  /// Points awarded for that most recent find. Null until the first find.
  final int? lastAward;

  const ClueHuntSession({
    required this.hostId,
    required this.players,
    required this.hiderId,
    this.phase = CluePhase.lobby,
    this.roundNumber = 1,
    this.totalRounds = 3,
    this.pendingClaimBy,
    this.roundStartEpochMs,
    this.lastFinderId,
    this.lastAward,
  });

  /// A brand-new lobby containing just the host, who will hide first.
  factory ClueHuntSession.createHost({
    required String hostId,
    required String hostName,
    int totalRounds = 3,
  }) {
    return ClueHuntSession(
      hostId: hostId,
      hiderId: hostId,
      totalRounds: totalRounds,
      players: [
        CluePlayer(id: hostId, name: hostName, isHost: true),
      ],
    );
  }

  // ---- Scoring --------------------------------------------------------------

  /// Points paid for a confirmed find. Base points for an instant find,
  /// decaying with elapsed seconds down to a floor — faster grabs score more.
  static const int basePoints = 1000;
  static const int minPoints = 100;
  static const int decayPerSecond = 15;

  /// PURE elapsed→points mapping. Clamped to [[minPoints], [basePoints]] and
  /// rounded to the nearest 10 so scores read cleanly.
  static int pointsForElapsedMs(int elapsedMs) {
    final elapsedSeconds = elapsedMs / 1000.0;
    final raw = basePoints - elapsedSeconds * decayPerSecond;
    final clamped = raw.clamp(minPoints.toDouble(), basePoints.toDouble());
    return (clamped / 10).round() * 10;
  }

  // ---- Derived views --------------------------------------------------------

  bool get isLobby => phase == CluePhase.lobby;
  bool get isSeeking => phase == CluePhase.seeking;
  bool get isFinished => phase == CluePhase.gameOver;

  /// The host's own player record.
  CluePlayer? get host => _byId(hostId);

  /// The current round's hider.
  CluePlayer? get hider => _byId(hiderId);

  /// Everyone who is NOT the hider this round (i.e. the seekers).
  List<CluePlayer> get seekers =>
      players.where((p) => p.id != hiderId).toList();

  /// The pending claimant's player record, if any.
  CluePlayer? get pendingClaimant =>
      pendingClaimBy == null ? null : _byId(pendingClaimBy!);

  /// The most recent finder's player record, if any.
  CluePlayer? get lastFinder =>
      lastFinderId == null ? null : _byId(lastFinderId!);

  bool isHider(String playerId) => playerId == hiderId;

  CluePlayer? _byId(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Players ranked for display: highest running total first, ties broken by
  /// name (case-insensitive) then id so the order is stable and deterministic.
  List<CluePlayer> get leaderboard {
    final sorted = [...players];
    sorted.sort((a, b) {
      final byScore = b.totalScore.compareTo(a.totalScore);
      if (byScore != 0) return byScore;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  // ---- Pure mutations -------------------------------------------------------

  /// Add a player to the lobby. Idempotent on [id]: re-joining with the same id
  /// just refreshes the name (and marks them connected again, healing an earlier
  /// drop) and never creates a duplicate.
  ClueHuntSession withPlayerJoined(String id, String name) {
    final next = [...players];
    final idx = next.indexWhere((p) => p.id == id);
    if (idx == -1) {
      next.add(CluePlayer(id: id, name: name));
    } else {
      next[idx] = next[idx].copyWith(name: name, connected: true);
    }
    return copyWith(players: next);
  }

  /// Flag a player's connectivity without removing them: a dropped phone stays
  /// in the roster (so scores and history survive) but is skipped by the hider
  /// rotation. No-op for an unknown id.
  ClueHuntSession withPlayerConnection(String id, bool connected) {
    final idx = players.indexWhere((p) => p.id == id);
    if (idx == -1) return this;
    final next = [...players];
    next[idx] = next[idx].copyWith(connected: connected);
    return copyWith(players: next);
  }

  /// The next player after the current hider (in join order, wrapping) whose
  /// phone is still connected — so the role can never land on a departed player.
  /// Falls back to the host (always connected to itself) if nobody else is.
  String _nextConnectedHiderId() {
    final n = players.length;
    if (n == 0) return hiderId;
    final idx = players.indexWhere((p) => p.id == hiderId);
    final start = idx == -1 ? 0 : idx;
    for (var step = 1; step <= n; step++) {
      final cand = players[(start + step) % n];
      if (cand.connected) return cand.id;
    }
    return hostId;
  }

  /// HOST leaves the lobby and starts round 1: the host hides first.
  ClueHuntSession started() {
    return copyWith(
      phase: CluePhase.hiding,
      hiderId: hostId,
      roundNumber: 1,
      clearPending: true,
      clearRoundStart: true,
      clearLast: true,
    );
  }

  /// HIDER has hidden the object and the hunt begins: stamp the seek start so a
  /// confirmed find can be scored by elapsed time. [now] is injectable.
  ClueHuntSession beganSeeking({required int now}) {
    if (phase != CluePhase.hiding) return this;
    return copyWith(
      phase: CluePhase.seeking,
      roundStartEpochMs: now,
      clearPending: true,
      clearLast: true,
    );
  }

  /// A seeker claims they physically grabbed the object. First-claim-wins: a
  /// claim is only taken when we're seeking, no claim is already pending, and
  /// the claimant is a real seeker (not the hider). Otherwise unchanged.
  ClueHuntSession withClaim(String seekerId) {
    if (phase != CluePhase.seeking) return this;
    if (pendingClaimBy != null) return this;
    if (seekerId == hiderId) return this;
    if (_byId(seekerId) == null) return this;
    return copyWith(pendingClaimBy: seekerId);
  }

  /// HIDER rejects the pending claim (they didn't really have it): clear the
  /// slot so someone else can claim. No-op when nothing is pending.
  ///
  /// [expectClaimant], when given, must equal the currently pending claimant for
  /// the reject to apply — a stale reject that arrives after the pending slot has
  /// moved on to someone else is ignored, so it can never drop the wrong claim.
  ClueHuntSession claimRejected({String? expectClaimant}) {
    if (pendingClaimBy == null) return this;
    if (expectClaimant != null && expectClaimant != pendingClaimBy) return this;
    return copyWith(clearPending: true);
  }

  /// HIDER confirms the pending claim: score the finder by how fast they were,
  /// freeze the round result and clear the pending slot. No-op when nothing is
  /// pending. [now] is injectable so scoring is deterministic in tests.
  ///
  /// [expectClaimant], when given, must equal the currently pending claimant for
  /// the confirm to apply — a stale confirm (e.g. the hider rejected A, then B
  /// claimed, then A's late confirm arrives) is ignored, so points can never be
  /// awarded to a DIFFERENT claim than the one the hider actually approved.
  ClueHuntSession claimConfirmed({required int now, String? expectClaimant}) {
    final finderId = pendingClaimBy;
    if (finderId == null) return this;
    if (expectClaimant != null && expectClaimant != finderId) return this;
    final elapsedMs = now - (roundStartEpochMs ?? now);
    final award = pointsForElapsedMs(elapsedMs < 0 ? 0 : elapsedMs);
    final next = [...players];
    final idx = next.indexWhere((p) => p.id == finderId);
    if (idx != -1) {
      next[idx] = next[idx].copyWith(totalScore: next[idx].totalScore + award);
    }
    return copyWith(
      players: next,
      phase: CluePhase.roundResult,
      lastFinderId: finderId,
      lastAward: award,
      clearPending: true,
    );
  }

  /// HOST advances past a round result: rotate the hider to the next CONNECTED
  /// player and begin their round, or end the game when the last round is done.
  /// Skipping departed players keeps the role off a phone that has left.
  ClueHuntSession advancedRound() {
    if (roundNumber >= totalRounds) {
      return copyWith(phase: CluePhase.gameOver);
    }
    return copyWith(
      phase: CluePhase.hiding,
      hiderId: _nextConnectedHiderId(),
      roundNumber: roundNumber + 1,
      clearPending: true,
      clearRoundStart: true,
      clearLast: true,
    );
  }

  /// HOST escape hatch: the current hider went dark (or is stalling) during the
  /// HIDING phase, so hand the role to the next CONNECTED player WITHOUT
  /// advancing the round — the round hasn't really started yet. No-op outside
  /// the hiding phase. This is what unsticks an "X is hiding…" soft-lock.
  ClueHuntSession hiderSkipped() {
    if (phase != CluePhase.hiding) return this;
    return copyWith(
      phase: CluePhase.hiding,
      hiderId: _nextConnectedHiderId(),
      clearPending: true,
      clearRoundStart: true,
      clearLast: true,
    );
  }

  /// HOST returns everyone to a fresh lobby for another whole game: scores zero,
  /// the host hides first again.
  ClueHuntSession backToLobby() {
    final reset = players.map((p) => p.copyWith(totalScore: 0)).toList();
    return ClueHuntSession(
      hostId: hostId,
      players: reset,
      hiderId: hostId,
      totalRounds: totalRounds,
      phase: CluePhase.lobby,
      roundNumber: 1,
    );
  }

  ClueHuntSession copyWith({
    List<CluePlayer>? players,
    CluePhase? phase,
    String? hiderId,
    int? roundNumber,
    int? totalRounds,
    String? pendingClaimBy,
    int? roundStartEpochMs,
    String? lastFinderId,
    int? lastAward,
    bool clearPending = false,
    bool clearRoundStart = false,
    bool clearLast = false,
  }) {
    return ClueHuntSession(
      hostId: hostId,
      players: players ?? this.players,
      phase: phase ?? this.phase,
      hiderId: hiderId ?? this.hiderId,
      roundNumber: roundNumber ?? this.roundNumber,
      totalRounds: totalRounds ?? this.totalRounds,
      pendingClaimBy:
          clearPending ? null : (pendingClaimBy ?? this.pendingClaimBy),
      roundStartEpochMs: clearRoundStart
          ? null
          : (roundStartEpochMs ?? this.roundStartEpochMs),
      lastFinderId: clearLast ? null : (lastFinderId ?? this.lastFinderId),
      lastAward: clearLast ? null : (lastAward ?? this.lastAward),
    );
  }

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'hiderId': hiderId,
        'phase': phase.name,
        'roundNumber': roundNumber,
        'totalRounds': totalRounds,
        'pendingClaimBy': pendingClaimBy,
        'roundStartEpochMs': roundStartEpochMs,
        'lastFinderId': lastFinderId,
        'lastAward': lastAward,
        'players': players.map((p) => p.toMap()).toList(),
      };

  factory ClueHuntSession.fromMap(Map<String, dynamic> map) {
    final rawPlayers = (map['players'] as List<dynamic>? ?? const []);
    return ClueHuntSession(
      hostId: map['hostId'] as String? ?? '',
      hiderId: map['hiderId'] as String? ?? '',
      phase: CluePhase.values.firstWhere(
        (p) => p.name == map['phase'],
        orElse: () => CluePhase.lobby,
      ),
      roundNumber: (map['roundNumber'] as num?)?.toInt() ?? 1,
      totalRounds: (map['totalRounds'] as num?)?.toInt() ?? 3,
      pendingClaimBy: map['pendingClaimBy'] as String?,
      roundStartEpochMs: (map['roundStartEpochMs'] as num?)?.toInt(),
      lastFinderId: map['lastFinderId'] as String?,
      lastAward: (map['lastAward'] as num?)?.toInt(),
      players: rawPlayers
          .map((e) => CluePlayer.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
        hostId,
        players,
        phase,
        hiderId,
        roundNumber,
        totalRounds,
        pendingClaimBy,
        roundStartEpochMs,
        lastFinderId,
        lastAward,
      ];
}
