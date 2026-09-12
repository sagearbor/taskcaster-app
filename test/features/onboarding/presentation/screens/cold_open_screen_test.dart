import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/onboarding/presentation/screens/cold_open_screen.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  group('ColdOpenScreen', () {
    late MockAuthBloc mockAuthBloc;
    late bool started;

    setUp(() {
      mockAuthBloc = MockAuthBloc();
      started = false;
      when(() => mockAuthBloc.state).thenReturn(AuthInitial());
      when(() => mockAuthBloc.stream)
          .thenAnswer((_) => const Stream<AuthState>.empty());
    });

    Widget createTestWidget() {
      return MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: mockAuthBloc,
          child: ColdOpenScreen(
            taskTitle: 'A vegetable that has just received terrible news',
            taskDescription: 'Find a vegetable. Photograph it at the exact '
                'moment it receives devastating news.',
            timerSeconds: 90,
            onStart: () => started = true,
          ),
        ),
      );
    }

    testWidgets('shows the wordmark, the first task and the timer',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.text('TASKCASTER'), findsOneWidget);
      expect(find.textContaining('Your first task'), findsOneWidget);
      expect(
        find.text('A vegetable that has just received terrible news'),
        findsOneWidget,
      );
      expect(find.text('⏱ 90 s'), findsOneWidget);
      expect(find.text('Start — 90 s'), findsOneWidget);
    });

    testWidgets('shows the reveal-gating copy and no-account line',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(
        find.textContaining('Post yours to unlock everyone else\'s'),
        findsOneWidget,
      );
      expect(find.textContaining('No account needed'), findsOneWidget);
    });

    testWidgets('tapping Start invokes the onStart callback', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.tap(find.text('Start — 90 s'));
      await tester.pump();

      expect(started, isTrue);
    });

    testWidgets('tapping Sign in reveals the account options section',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.text('Continue with Google'), findsNothing);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
    });

    testWidgets('keeps the legal footer', (tester) async {
      await tester.pumpWidget(createTestWidget());
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
    });

    testWidgets('renders with no overflow at 390x844 @3x', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3.0;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(createTestWidget());
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with no overflow at 360x640 @2x, sign-in expanded',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(createTestWidget());

      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
