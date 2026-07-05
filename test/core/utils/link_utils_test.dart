import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/utils/link_utils.dart';

void main() {
  group('LinkUtils.isLikelyUrl', () {
    test('accepts common video-hosting links', () {
      const valid = [
        'https://youtube.com/watch?v=abc123',
        'https://www.youtube.com/watch?v=abc123',
        'https://youtu.be/abc123',
        'http://youtu.be/abc123',
        'https://photos.google.com/share/AF1QipM',
        'https://photos.app.goo.gl/xyz',
        'https://drive.google.com/file/d/123/view',
        'https://www.dropbox.com/s/abc/video.mp4?dl=0',
        'https://vimeo.com/123456789',
        '  https://youtu.be/trimmed-whitespace  ',
      ];
      for (final url in valid) {
        expect(LinkUtils.isLikelyUrl(url), isTrue,
            reason: 'Expected "$url" to be accepted');
      }
    });

    test('rejects things that are not usable web links', () {
      const invalid = [
        null,
        '',
        '   ',
        'not a url',
        'my cool video',
        'youtube.com/watch?v=abc', // missing scheme
        'ftp://example.com/video.mp4', // wrong scheme
        'file:///home/user/video.mp4', // wrong scheme
        'https://', // no host
        'https://nodothost', // host without a dot
        'https://you tube.com/watch', // contains a space
        'javascript:alert(1)', // definitely not
      ];
      for (final url in invalid) {
        expect(LinkUtils.isLikelyUrl(url), isFalse,
            reason: 'Expected "$url" to be rejected');
      }
    });
  });

  group('LinkUtils.describeUrlProblem', () {
    test('returns null for empty input (nothing to complain about yet)', () {
      expect(LinkUtils.describeUrlProblem(null), isNull);
      expect(LinkUtils.describeUrlProblem(''), isNull);
      expect(LinkUtils.describeUrlProblem('   '), isNull);
    });

    test('returns null for valid links', () {
      expect(
          LinkUtils.describeUrlProblem('https://youtu.be/abc123'), isNull);
    });

    test('suggests adding https:// when only the scheme is missing', () {
      final message =
          LinkUtils.describeUrlProblem('youtube.com/watch?v=abc123');
      expect(message, isNotNull);
      expect(message, contains('https://'));
    });

    test('flags links containing spaces', () {
      final message = LinkUtils.describeUrlProblem('https://you tube.com');
      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('space'));
    });

    test('flags non-web schemes', () {
      final message =
          LinkUtils.describeUrlProblem('ftp://example.com/video.mp4');
      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('http'));
    });

    test('gives a generic friendly nudge for word salad', () {
      final message = LinkUtils.describeUrlProblem('my cool video');
      expect(message, isNotNull);
      // Friendly, not technical: no exception-speak.
      expect(message!.toLowerCase(), isNot(contains('exception')));
      expect(message.toLowerCase(), isNot(contains('error')));
    });
  });
}
