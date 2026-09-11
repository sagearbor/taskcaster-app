import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/auth/presentation/screens/login_screen.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  group('LoginScreen', () {
    late MockAuthBloc mockAuthBloc;

    setUp(() {
      mockAuthBloc = MockAuthBloc();
      when(() => mockAuthBloc.state).thenReturn(AuthInitial());
      // BlocListener subscribes to .stream; mocktail returns null unless
      // stubbed.
      when(() => mockAuthBloc.stream)
          .thenAnswer((_) => const Stream<AuthState>.empty());
    });

    Widget createTestWidget({Future<void> Function(Uri uri)? openLink}) {
      return MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: mockAuthBloc,
          child: LoginScreen(openLink: openLink),
        ),
      );
    }

    Future<void> pumpAtSize(
      WidgetTester tester,
      Size logicalSize,
      double devicePixelRatio,
    ) async {
      tester.view.physicalSize = logicalSize * devicePixelRatio;
      tester.view.devicePixelRatio = devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(createTestWidget());
      await tester.pump();
    }

    testWidgets('shows Privacy Policy and Terms links', (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
    });

    testWidgets('shows the guest-play hint under the Play button',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(
        find.textContaining('Play as a guest'),
        findsOneWidget,
      );
    });

    testWidgets('tapping Privacy Policy / Terms opens the hosted legal pages',
        (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        createTestWidget(openLink: (uri) async => opened.add(uri)),
      );

      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();
      await tester.tap(find.text('Terms'));
      await tester.pump();

      expect(opened.map((u) => u.toString()).toList(), [
        'https://taskmaster-app-3d480.web.app/privacy/',
        'https://taskmaster-app-3d480.web.app/terms/',
      ]);
    });

    testWidgets('the Play button still dispatches AnonymousSignInRequested',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.tap(find.text('Play'));

      verify(() => mockAuthBloc.add(AnonymousSignInRequested())).called(1);
    });

    testWidgets('the password-visibility icon shows visibility when obscured',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Reveal the sign-in form (which contains the password field).
      await tester.tap(find.text('Sign in or create account'));
      await tester.pumpAndSettle();

      // Obscured by default -> "eye" icon inviting a tap to reveal.
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });

    testWidgets('renders with no overflow at a 390x844 @3x phone size',
        (tester) async {
      await pumpAtSize(tester, const Size(390, 844), 3.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with no overflow at a small 360x640 @2x phone size',
        (tester) async {
      await pumpAtSize(tester, const Size(360, 640), 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'renders with no overflow with sign-in options expanded on a small phone',
        (tester) async {
      await pumpAtSize(tester, const Size(360, 640), 2.0);

      await tester.tap(find.text('Sign in or create account'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
