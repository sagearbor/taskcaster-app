import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/telephone/domain/nearby_cast_label.dart';

void main() {
  group('NearbyCastLabel.encode', () {
    test('round-trips host name, game type and a short session fingerprint', () {
      final encoded = NearbyCastLabel.encode(
        hostName: 'Sage',
        gameType: NearbyGameType.telephone,
        sessionId: 'abcdef1234567890',
      );
      final label = NearbyCastLabel.decode(encoded);

      expect(label.isTaskCaster, isTrue);
      expect(label.hostName, 'Sage');
      expect(label.gameType, NearbyGameType.telephone);
      expect(label.sessionId, 'abcdef12', reason: 'fingerprint capped at 8');
    });

    test('never exceeds the byte budget even with a very long host name', () {
      final encoded = NearbyCastLabel.encode(
        hostName: 'A' * 500,
        gameType: NearbyGameType.telephone,
        sessionId: 'session-id-here',
      );
      expect(utf8.encode(encoded).length,
          lessThanOrEqualTo(NearbyCastLabel.maxBytes));
      // The fixed fields survive truncation; only the host name is trimmed.
      final label = NearbyCastLabel.decode(encoded);
      expect(label.gameType, NearbyGameType.telephone);
      expect(label.hostName, startsWith('A'));
    });

    test('truncates multi-byte host names on rune boundaries (no broken UTF-8)',
        () {
      final encoded = NearbyCastLabel.encode(
        hostName: '🎮' * 100, // 4 UTF-8 bytes each
        gameType: NearbyGameType.telephone,
      );
      // Must remain valid UTF-8 and within budget.
      expect(utf8.encode(encoded).length,
          lessThanOrEqualTo(NearbyCastLabel.maxBytes));
      final label = NearbyCastLabel.decode(encoded);
      expect(label.hostName, isNotEmpty);
      // Every char is the whole emoji — decoding back yields only '🎮's.
      expect(label.hostName.runes.every((r) => r == '🎮'.runes.first), isTrue);
    });

    test('blank host name falls back to a placeholder', () {
      final label = NearbyCastLabel.decode(
        NearbyCastLabel.encode(hostName: '   ', gameType: NearbyGameType.telephone),
      );
      expect(label.hostName, 'A player');
    });

    test('strips the separator char from free text so framing can not break',
        () {
      final encoded = NearbyCastLabel.encode(
        hostName: 'Sa\u001fge', // contains the unit separator
        gameType: NearbyGameType.telephone,
        sessionId: 'x\u001fy',
      );
      final label = NearbyCastLabel.decode(encoded);
      expect(label.hostName, 'Sa ge');
      expect(label.sessionId, 'xy');
    });
  });

  group('NearbyCastLabel.decode', () {
    test('treats an unrecognised / legacy name as a plain host name', () {
      final label = NearbyCastLabel.decode("Robin's game");
      expect(label.isTaskCaster, isFalse);
      expect(label.hostName, "Robin's game");
      expect(label.gameType, NearbyGameType.unknown);
      expect(label.sessionId, '');
    });

    test('empty name is safe', () {
      final label = NearbyCastLabel.decode('');
      expect(label.hostName, 'A player');
      expect(label.isTaskCaster, isFalse);
    });
  });

  group('bannerText', () {
    test('names the game when known', () {
      final label = NearbyCastLabel.decode(
        NearbyCastLabel.encode(hostName: 'Sage', gameType: NearbyGameType.telephone),
      );
      expect(label.bannerText, 'Sage started Drawing Telephone nearby');
    });

    test('degrades gracefully for an unknown game', () {
      final label = NearbyCastLabel.decode('Sage');
      expect(label.bannerText, 'Sage started a game nearby');
    });
  });
}
