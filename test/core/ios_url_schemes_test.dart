import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// GoogleSignIn on iOS aborts the app ("missing support for the following URL
/// schemes") unless Info.plist registers the REVERSED_CLIENT_ID from
/// GoogleService-Info.plist as a URL scheme. Pin the two files together so a
/// regenerated GoogleService-Info.plist cannot silently reintroduce the crash.
void main() {
  String plistString(String xml, String key) {
    final match =
        RegExp('<key>$key</key>\\s*<string>([^<]+)</string>').firstMatch(xml);
    expect(match, isNotNull, reason: '$key missing');
    return match!.group(1)!;
  }

  test('Info.plist registers the Google REVERSED_CLIENT_ID URL scheme', () {
    final google =
        File('ios/Runner/GoogleService-Info.plist').readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    final reversed = plistString(google, 'REVERSED_CLIENT_ID');

    expect(info, contains('<key>CFBundleURLTypes</key>'));
    expect(info, contains('<string>$reversed</string>'));
  });

  test('Info.plist registers the taskcaster:// scheme for invite links', () {
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    expect(info, contains('<string>taskcaster</string>'));
  });
}
