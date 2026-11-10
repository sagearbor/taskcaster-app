import 'package:taskcaster_app/core/services/sfx/game_sfx.dart';

/// A [GameSfx] that plays nothing and remembers what it was asked to play,
/// in order, so tests can assert on the soundtrack.
class RecordingGameSfx implements GameSfx {
  final List<String> played = [];

  @override
  void prime() => played.add('prime');
  @override
  void pop({double pitch = 1.0}) => played.add('pop');
  @override
  void boom() => played.add('boom');
  @override
  void tick() => played.add('tick');
  @override
  void go() => played.add('go');
  @override
  void fanfare() => played.add('fanfare');
  @override
  void whoosh() => played.add('whoosh');
  @override
  void sizzle() => played.add('sizzle');
}
