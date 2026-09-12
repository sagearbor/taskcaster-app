import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/auth/presentation/screens/register_screen.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  group('RegisterScreen', () {
    late MockAuthBloc mockAuthBloc;

    setUp(() {
      mockAuthBloc = MockAuthBloc();
      when(() => mockAuthBloc.state).thenReturn(AuthInitial());
      // BlocListener/BlocBuilder subscribe to .stream; mocktail returns null
      // unless stubbed.
      when(() => mockAuthBloc.stream)
          .thenAnswer((_) => const Stream<AuthState>.empty());
    });

    Widget createTestWidget({Future<void> Function(Uri uri)? openLink}) {
      return MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: mockAuthBloc,
          child: RegisterScreen(openLink: openLink),
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

    testWidgets('shows the Terms and Privacy Policy consent copy',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.text('Terms'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(
        find.textContaining('you agree to our'),
        findsOneWidget,
      );
    });

    testWidgets('tapping Terms / Privacy Policy opens the hosted legal pages',
        (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        createTestWidget(openLink: (uri) async => opened.add(uri)),
      );

      await tester.tap(find.text('Terms'));
      await tester.pump();
      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();

      expect(opened.map((u) => u.toString()).toList(), [
        'https://taskmaster-app-3d480.web.app/terms/',
        'https://taskmaster-app-3d480.web.app/privacy/',
      ]);
    });

    testWidgets('the password-visibility icon shows visibility when obscured',
        (tester) async {
      await tester.pumpWidget(createTestWidget());

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
  });
}
