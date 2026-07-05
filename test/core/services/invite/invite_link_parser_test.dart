import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/invite/invite_link_parser.dart';

void main() {
  group('InviteLinks.isValidCode', () {
    test('accepts a 6-char code from the alphabet', () {
      expect(InviteLinks.isValidCode('ABC234'), isTrue);
      expect(InviteLinks.isValidCode('ZZZZZZ'), isTrue);
      expect(InviteLinks.isValidCode('23456789'.substring(0, 6)), isTrue);
    });

    test('rejects wrong lengths', () {
      expect(InviteLinks.isValidCode(''), isFalse);
      expect(InviteLinks.isValidCode('ABC23'), isFalse);
      expect(InviteLinks.isValidCode('ABC2345'), isFalse);
    });

    test('rejects characters outside the alphabet (I, L, O, 0, 1, symbols)',
        () {
      expect(InviteLinks.isValidCode('ABC23I'), isFalse);
      expect(InviteLinks.isValidCode('ABC23L'), isFalse);
      expect(InviteLinks.isValidCode('ABC23O'), isFalse);
      expect(InviteLinks.isValidCode('ABC230'), isFalse);
      expect(InviteLinks.isValidCode('ABC231'), isFalse);
      expect(InviteLinks.isValidCode('ABC2&4'), isFalse);
    });

    test('rejects lowercase (normalizeCode handles case-folding)', () {
      expect(InviteLinks.isValidCode('abc234'), isFalse);
      expect(InviteLinks.normalizeCode('abc234'), 'ABC234');
    });
  });

  group('InviteLinks.normalizeCode', () {
    test('trims whitespace and uppercases', () {
      expect(InviteLinks.normalizeCode('  abc234\n'), 'ABC234');
    });

    test('returns null for null, junk and invalid codes', () {
      expect(InviteLinks.normalizeCode(null), isNull);
      expect(InviteLinks.normalizeCode(''), isNull);
      expect(InviteLinks.normalizeCode('hello world'), isNull);
      expect(InviteLinks.normalizeCode('ABC10Z'), isNull); // 1 and 0 excluded
    });
  });

  group('InviteLinks.joinUrl', () {
    test('builds the canonical landing-page URL', () {
      expect(
        InviteLinks.joinUrl('ABC234'),
        'https://taskmaster-app-3d480.web.app/join/?code=ABC234',
      );
    });

    test('appends the inviter ref when supplied', () {
      expect(
        InviteLinks.joinUrl('ABC234', ref: 'uid_123'),
        'https://taskmaster-app-3d480.web.app/join/?code=ABC234&ref=uid_123',
      );
    });

    test('omits the ref when null or blank', () {
      expect(
        InviteLinks.joinUrl('ABC234', ref: null),
        'https://taskmaster-app-3d480.web.app/join/?code=ABC234',
      );
      expect(
        InviteLinks.joinUrl('ABC234', ref: '   '),
        'https://taskmaster-app-3d480.web.app/join/?code=ABC234',
      );
    });
  });

  group('InviteLinks.refFromUri', () {
    test('extracts ref from a deep link that also carries a valid code', () {
      expect(
        InviteLinks.refFromUri(
            Uri.parse('taskcaster://join?code=ABC234&ref=uid_123')),
        'uid_123',
      );
      expect(
        InviteLinks.refFromUri(Uri.parse(
            'https://taskmaster-app-3d480.web.app/join/?code=ABC234&ref=uid_9')),
        'uid_9',
      );
    });

    test('round-trips the URL built by joinUrl with a ref', () {
      final url = InviteLinks.joinUrl('QRS789', ref: 'uid_abc');
      expect(InviteLinks.refFromUri(Uri.parse(url)), 'uid_abc');
    });

    test('returns null when there is no ref', () {
      expect(
        InviteLinks.refFromUri(Uri.parse('taskcaster://join?code=ABC234')),
        isNull,
      );
    });

    test('returns null when the code itself is missing/invalid', () {
      // A bare ref with no valid code is meaningless.
      expect(
        InviteLinks.refFromUri(Uri.parse('taskcaster://join?ref=uid_123')),
        isNull,
      );
      expect(
        InviteLinks.refFromUri(
            Uri.parse('taskcaster://join?code=BAD&ref=uid_123')),
        isNull,
      );
    });

    test('returns null for unrelated hosts/schemes', () {
      expect(
        InviteLinks.refFromUri(
            Uri.parse('https://evil.example.com/join/?code=ABC234&ref=uid_1')),
        isNull,
      );
    });
  });

  group('InviteLinks.refFromReferrer', () {
    test('extracts ref from invite_code=X&ref=Y', () {
      expect(
        InviteLinks.refFromReferrer('invite_code=ABC234&ref=uid_123'),
        'uid_123',
      );
    });

    test('extracts ref amid utm noise', () {
      expect(
        InviteLinks.refFromReferrer(
            'utm_source=x&invite_code=ABC234&ref=uid_7&utm_medium=share'),
        'uid_7',
      );
    });

    test('extracts ref from a still-URL-encoded referrer', () {
      expect(
        InviteLinks.refFromReferrer('invite_code%3DABC234%26ref%3Duid_123'),
        'uid_123',
      );
    });

    test('returns null when ref absent or code invalid', () {
      expect(InviteLinks.refFromReferrer('invite_code=ABC234'), isNull);
      expect(InviteLinks.refFromReferrer('ref=uid_123'), isNull); // no code
      expect(InviteLinks.refFromReferrer('invite_code=BAD&ref=uid_123'), isNull);
      expect(InviteLinks.refFromReferrer(null), isNull);
    });

    test('does not crash on malformed percent-encoding', () {
      expect(InviteLinks.refFromReferrer('invite_code=%ZZ&ref=uid'), isNull);
    });
  });

  group('InviteLinks.codeFromUri', () {
    test('parses the custom scheme link', () {
      expect(
        InviteLinks.codeFromUri(Uri.parse('taskcaster://join?code=ABC234')),
        'ABC234',
      );
    });

    test('parses the https landing-page link (with and without slash)', () {
      expect(
        InviteLinks.codeFromUri(Uri.parse(
            'https://taskmaster-app-3d480.web.app/join/?code=ABC234')),
        'ABC234',
      );
      expect(
        InviteLinks.codeFromUri(Uri.parse(
            'https://taskmaster-app-3d480.web.app/join?code=ABC234')),
        'ABC234',
      );
    });

    test('accepts a lowercase code and uppercases it', () {
      expect(
        InviteLinks.codeFromUri(Uri.parse('taskcaster://join?code=abc234')),
        'ABC234',
      );
    });

    test('round-trips the URL built by joinUrl', () {
      expect(
        InviteLinks.codeFromUri(Uri.parse(InviteLinks.joinUrl('QRS789'))),
        'QRS789',
      );
    });

    test('rejects a missing or junk code', () {
      expect(
          InviteLinks.codeFromUri(Uri.parse('taskcaster://join')), isNull);
      expect(InviteLinks.codeFromUri(Uri.parse('taskcaster://join?code=')),
          isNull);
      expect(
        InviteLinks.codeFromUri(
            Uri.parse('taskcaster://join?code=NOT_A_CODE')),
        isNull,
      );
      expect(
        InviteLinks.codeFromUri(Uri.parse('taskcaster://join?other=ABC234')),
        isNull,
      );
    });

    test('rejects unrelated hosts, schemes and paths', () {
      expect(
        InviteLinks.codeFromUri(Uri.parse('taskcaster://other?code=ABC234')),
        isNull,
      );
      expect(
        InviteLinks.codeFromUri(
            Uri.parse('https://evil.example.com/join/?code=ABC234')),
        isNull,
      );
      expect(
        InviteLinks.codeFromUri(Uri.parse(
            'https://taskmaster-app-3d480.web.app/other/?code=ABC234')),
        isNull,
      );
      expect(
        InviteLinks.codeFromUri(
            Uri.parse('mailto:someone@example.com?code=ABC234')),
        isNull,
      );
    });
  });

  group('InviteLinks.codeFromReferrer', () {
    test('parses a plain referrer', () {
      expect(InviteLinks.codeFromReferrer('invite_code=ABC234'), 'ABC234');
    });

    test('parses a referrer with utm noise around it', () {
      expect(
        InviteLinks.codeFromReferrer(
            'utm_source=x&invite_code=ABC234&utm_medium=share'),
        'ABC234',
      );
    });

    test('parses a still-URL-encoded referrer', () {
      expect(
          InviteLinks.codeFromReferrer('invite_code%3DABC234'), 'ABC234');
      expect(
        InviteLinks.codeFromReferrer(
            'utm_source%3Dx%26invite_code%3DABC234'),
        'ABC234',
      );
    });

    test('uppercases a lowercase code', () {
      expect(InviteLinks.codeFromReferrer('invite_code=abc234'), 'ABC234');
    });

    test('returns null for null/empty/absent/invalid', () {
      expect(InviteLinks.codeFromReferrer(null), isNull);
      expect(InviteLinks.codeFromReferrer(''), isNull);
      expect(InviteLinks.codeFromReferrer('   '), isNull);
      expect(InviteLinks.codeFromReferrer('utm_source=google'), isNull);
      expect(InviteLinks.codeFromReferrer('invite_code=BAD'), isNull);
      expect(
          InviteLinks.codeFromReferrer('organic install from search'), isNull);
    });

    test('does not crash on malformed percent-encoding', () {
      expect(InviteLinks.codeFromReferrer('invite_code=%ZZ'), isNull);
      expect(InviteLinks.codeFromReferrer('%E0%A4%A'), isNull);
    });
  });
}
