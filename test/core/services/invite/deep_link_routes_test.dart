import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/invite/invite_link_parser.dart';

/// WP-07: the deep-link route table (InviteLinks.parse) and the association
/// files / manifest that must stay in sync with it.
void main() {
  const host = 'https://taskmaster-app-3d480.web.app';
  DeepLink? parse(String s, {bool anyHost = false}) =>
      InviteLinks.parse(Uri.parse(s), anyHost: anyHost);

  group('InviteLinks.parse: join', () {
    test('https /join/?code= with and without trailing slash', () {
      expect(parse('$host/join/?code=ABC234'), const JoinGameLink('ABC234'));
      expect(parse('$host/join?code=ABC234'), const JoinGameLink('ABC234'));
    });

    test('carries ref, lowercase code is normalised', () {
      expect(
        parse('$host/join/?code=abc234&ref=uid_1'),
        const JoinGameLink('ABC234', ref: 'uid_1'),
      );
    });

    test('path form /join/CODE', () {
      expect(parse('$host/join/QRS789'), const JoinGameLink('QRS789'));
    });

    test('custom scheme taskcaster://join', () {
      expect(parse('taskcaster://join?code=ABC234&ref=u'),
          const JoinGameLink('ABC234', ref: 'u'));
    });

    test('web root ?join= ("Play in browser")', () {
      expect(parse('$host/?join=ABC234'), const JoinGameLink('ABC234'));
      expect(parse('$host/?join=ABC234&ref=u#/'),
          const JoinGameLink('ABC234', ref: 'u'));
      expect(parse('$host/'), isNull);
      expect(parse('$host/?join=NOPE'), isNull);
    });

    test('round-trips joinUrl and playInBrowserUrl', () {
      expect(parse(InviteLinks.joinUrl('WXY567', ref: 'r')),
          const JoinGameLink('WXY567', ref: 'r'));
      expect(parse(InviteLinks.playInBrowserUrl('WXY567', ref: 'r')),
          const JoinGameLink('WXY567', ref: 'r'));
      expect(InviteLinks.playInBrowserUrl('WXY567'), '$host/?join=WXY567');
    });

    test('rejects a join link with a missing or invalid code', () {
      expect(parse('$host/join/'), isNull);
      expect(parse('$host/join/?code=ABC1O0'), isNull);
      expect(parse('taskcaster://join'), isNull);
    });
  });

  group('InviteLinks.parse: reserved share routes', () {
    test('/p/<postId>', () {
      expect(parse('$host/p/AbC123xyz'), const FeedPostLink('AbC123xyz'));
      expect(parse('taskcaster://p/post_1'), const FeedPostLink('post_1'));
    });

    test('/t/<taskId>', () {
      expect(parse('$host/t/task-42'), const TaskLink('task-42'));
    });

    test('/c/<challengeId>', () {
      expect(parse('$host/c/ch1/'), const ChallengeLink('ch1'));
    });

    test('WP-09: /t/<taskId>?from=<postId> carries the answered post', () {
      expect(parse('$host/t/starter-03?from=post_1'),
          const TaskLink('starter-03', fromPostId: 'post_1'));
      expect(parse('$host/t/starter-03?from=bad%20id'),
          const TaskLink('starter-03'));
    });

    test('WP-09: web root ?task= (a share page\'s "Your turn")', () {
      expect(parse('$host/?task=starter-09-v2&from=abc', anyHost: true),
          const TaskLink('starter-09-v2', fromPostId: 'abc'));
      expect(parse('http://localhost:5000/?task=starter-03', anyHost: true),
          const TaskLink('starter-03'));
      expect(parse('$host/?task=bad%20id'), isNull);
      // A join code still wins at the root.
      expect(parse('$host/?join=ABC234&task=starter-03'),
          const JoinGameLink('ABC234'));
    });

    test('rejects missing, extra or unsafe ids', () {
      expect(parse('$host/p/'), isNull);
      expect(parse('$host/p/a/b'), isNull);
      expect(parse('$host/t/bad%20id'), isNull);
      expect(parse('$host/c/${'x' * 129}'), isNull);
    });
  });

  group('InviteLinks.parse: hosts and schemes', () {
    test('rejects other hosts unless anyHost (web Uri.base)', () {
      expect(parse('https://evil.example.com/join/?code=ABC234'), isNull);
      expect(parse('https://evil.example.com/?join=ABC234'), isNull);
      expect(parse('http://localhost:5000/?join=ABC234', anyHost: true),
          const JoinGameLink('ABC234'));
      expect(
        parse('https://taskmaster-app-3d480.firebaseapp.com/?join=ABC234',
            anyHost: true),
        const JoinGameLink('ABC234'),
      );
    });

    test('rejects unknown routes and schemes', () {
      expect(parse('$host/arena'), isNull);
      expect(parse('$host/privacy/'), isNull);
      expect(parse('taskcaster://settings'), isNull);
      expect(parse('mailto:a@b.c?join=ABC234'), isNull);
      expect(parse('ftp://taskmaster-app-3d480.web.app/join/?code=ABC234'),
          isNull);
    });
  });

  group('association files stay in sync with the route table', () {
    test('apple-app-site-association claims exactly the routed prefixes', () {
      final aasa = jsonDecode(
        File('web/.well-known/apple-app-site-association').readAsStringSync(),
      ) as Map<String, dynamic>;
      final details = (aasa['applinks']['details'] as List).single
          as Map<String, dynamic>;
      expect(details['appIDs'],
          ['553Y9KWR84.com.sagearbor.taskcaster.app']);
      final components = (details['components'] as List)
          .map((c) => (c as Map)['/'] as String)
          .toList();
      expect(details['paths'], components);
      for (final prefix in InviteLinks.claimedPathPrefixes) {
        final p = prefix.endsWith('/') ? '$prefix*' : prefix;
        expect(components, contains(p));
      }
      // Each claimed component must parse to a route (sample id/code).
      for (final c in components) {
        final sample = c
            .replaceAll('/join/*', '/join/?code=ABC234')
            .replaceAll('*', 'id1');
        final uri = Uri.parse('$host$sample${c == '/join' ? '?code=ABC234' : ''}');
        expect(InviteLinks.parse(uri), isNotNull, reason: c);
      }
      // The web root ("Play in browser") must never be claimed.
      expect(components, isNot(contains('/')));
      expect(components, isNot(contains('/*')));
    });

    test('assetlinks.json targets the app package', () {
      final links = jsonDecode(
        File('web/.well-known/assetlinks.json').readAsStringSync(),
      ) as List;
      final target = (links.single as Map)['target'] as Map;
      expect(target['package_name'], 'com.sagearbor.taskcaster.app');
      expect(target['sha256_cert_fingerprints'], isNotEmpty);
    });

    test('Android autoVerify intent-filter uses the same path prefixes', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:autoVerify="true"'));
      expect(manifest,
          contains('android:host="${InviteLinks.webHost}"'));
      final prefixes = RegExp(r'android:pathPrefix="([^"]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1))
          .toList();
      expect(prefixes, unorderedEquals(InviteLinks.claimedPathPrefixes));
    });

    test('iOS entitlements carry the applinks domain', () {
      final ent = File('ios/Runner/Runner.entitlements').readAsStringSync();
      expect(ent, contains('com.apple.developer.associated-domains'));
      expect(ent, contains('applinks:${InviteLinks.webHost}'));
    });

    test('hosting serves .well-known as JSON and keeps it out of the SPA '
        'rewrite', () {
      final fb = jsonDecode(File('firebase.json').readAsStringSync())
          as Map<String, dynamic>;
      final hosting = fb['hosting'] as Map<String, dynamic>;
      for (final ignore in hosting['ignore'] as List) {
        expect(ignore, isNot('**/.*'),
            reason: 'would drop .well-known from the deploy');
      }
      final headerSources = (hosting['headers'] as List)
          .map((h) => (h as Map)['source'])
          .toList();
      expect(headerSources, contains('/.well-known/apple-app-site-association'));
      expect(headerSources, contains('/.well-known/assetlinks.json'));

      final rewrites = (hosting['rewrites'] as List).cast<Map>();
      // WP-09: the share routes go to the sharePage function, BEFORE the
      // SPA catch-all (Hosting takes the first match).
      final catchAllAt = rewrites.indexWhere((r) => r['regex'] != null);
      for (final route in ['/p/**', '/c/**', '/t/**', '/f/**']) {
        final at = rewrites.indexWhere((r) => r['source'] == route);
        expect(at, isNonNegative, reason: '$route must be rewritten');
        expect(at, lessThan(catchAllAt));
        expect((rewrites[at]['function'] as Map)['functionId'], 'sharePage');
      }
      final rewrite = rewrites[catchAllAt];
      final re = RegExp(rewrite['regex'] as String);
      expect(re.hasMatch('/'), isTrue);
      expect(re.hasMatch('/join/ABC234'), isTrue);
      expect(re.hasMatch('/p/abc'), isTrue);
      expect(re.hasMatch('/.well-known/apple-app-site-association'), isFalse);
      expect(re.hasMatch('/.well-known/assetlinks.json'), isFalse);
    });
  });
}
