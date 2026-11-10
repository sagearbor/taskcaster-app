import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/config/e2e_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    E2eMode.debugReset();
  });

  tearDown(E2eMode.debugReset);

  final plain = Uri.parse('https://taskmaster-app-3d480.web.app/');

  group('flagIn', () {
    test('reads the real query', () {
      expect(E2eMode.flagIn(Uri.parse('https://x.app/?e2e=1')), isTrue);
      expect(E2eMode.flagIn(Uri.parse('https://x.app/?e2e=true')), isTrue);
      expect(E2eMode.flagIn(Uri.parse('https://x.app/?e2e')), isTrue);
      expect(E2eMode.flagIn(Uri.parse('https://x.app/?e2e=0')), isFalse);
      expect(E2eMode.flagIn(Uri.parse('https://x.app/?e2e=off')), isFalse);
    });

    test('reads a query inside a hash route', () {
      expect(E2eMode.flagIn(Uri.parse('https://x.app/#/?e2e=1')), isTrue);
      expect(
        E2eMode.flagIn(Uri.parse('https://x.app/#/home?a=b&e2e=0')),
        isFalse,
      );
    });

    test('says nothing when the flag is absent or garbled', () {
      expect(E2eMode.flagIn(plain), isNull);
      expect(E2eMode.flagIn(Uri.parse('https://x.app/?join=ABC')), isNull);
      expect(E2eMode.flagIn(Uri.parse('https://x.app/?e2e=maybe')), isNull);
    });
  });

  test('default off', () async {
    await E2eMode.init(launchUri: plain);
    expect(E2eMode.isOn, isFalse);
  });

  test('URL flag turns it on and persists it', () async {
    await E2eMode.init(launchUri: Uri.parse('https://x.app/?e2e=1'));
    expect(E2eMode.isOn, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(E2eMode.prefsKey), isTrue);
  });

  test('persisted flag survives a reload whose URL was stripped', () async {
    SharedPreferences.setMockInitialValues({E2eMode.prefsKey: true});
    await E2eMode.init(launchUri: plain);
    expect(E2eMode.isOn, isTrue);
  });

  test('?e2e=0 turns it off and clears the persisted flag', () async {
    SharedPreferences.setMockInitialValues({E2eMode.prefsKey: true});
    await E2eMode.init(launchUri: Uri.parse('https://x.app/?e2e=0'));
    expect(E2eMode.isOn, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(E2eMode.prefsKey), isNull);
  });

  test('debugOverride wins and debugReset clears it', () {
    E2eMode.debugOverride(true);
    expect(E2eMode.isOn, isTrue);
    E2eMode.debugReset();
    expect(E2eMode.isOn, isFalse);
  });
}
