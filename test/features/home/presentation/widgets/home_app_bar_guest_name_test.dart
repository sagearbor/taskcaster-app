import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/core/utils/funny_names.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/home_app_bar.dart';

class _MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  late _MockAuthBloc authBloc;
  // The longest possible combination, to prove nothing overflows.
  final longest =
      '${FunnyNames.adjectives.reduce((a, b) => a.length >= b.length ? a : b)} '
      '${FunnyNames.nouns.reduce((a, b) => a.length >= b.length ? a : b)}';

  void stubUser(User user) {
    when(() => authBloc.state).thenReturn(AuthAuthenticated(user: user));
    when(() => authBloc.stream)
        .thenAnswer((_) => const Stream<AuthState>.empty());
  }

  setUp(() => authBloc = _MockAuthBloc());

  Future<void> pump(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize = const Size(360, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: Scaffold(appBar: HomeAppBar(onPlay: () {})),
      ),
    ));
  }

  for (final dark in [false, true]) {
    testWidgets(
        'a guest sees their funny name and initial at 360x640 '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      stubUser(User(
        id: 'guest-uid',
        displayName: longest,
        email: null,
        createdAt: DateTime(2026, 11, 9),
      ));
      await pump(tester, dark: dark);

      // Avatar initial comes from the funny name.
      expect(find.text(longest[0]), findsOneWidget);

      await tester.tap(find.text(longest[0]));
      await tester.pumpAndSettle();

      expect(find.text(longest), findsOneWidget);
      expect(find.text('Guest. Name assigned.'), findsOneWidget);
      expect(find.text('Guest'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a signed-in player still sees their email', (tester) async {
    stubUser(User(
      id: 'u1',
      displayName: 'Sophie',
      email: 'sophie@example.com',
      createdAt: DateTime(2026, 11, 9),
    ));
    await pump(tester, dark: false);
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();
    expect(find.text('Sophie'), findsOneWidget);
    expect(find.text('sophie@example.com'), findsOneWidget);
  });
}
