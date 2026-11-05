import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/services/invite/pending_invite_service.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/pending_invite_gate.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

/// WP-07: an invite link opened with nobody signed in signs the visitor in as
/// a guest (no cold open), so the join dialog can follow.
void main() {
  setUpAll(() => registerFallbackValue(AnonymousSignInRequested()));

  late MockAuthBloc auth;
  late StreamController<AuthState> authStates;
  late StreamController<Uri> links;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = MockAuthBloc();
    authStates = StreamController<AuthState>.broadcast();
    links = StreamController<Uri>.broadcast();
    when(() => auth.stream).thenAnswer((_) => authStates.stream);
    when(() => auth.add(any())).thenReturn(null);
  });

  tearDown(() {
    authStates.close();
    links.close();
  });

  Future<PendingInviteService> service({Uri? initial}) async {
    final s = PendingInviteService(
      getInitialLink: () async => initial,
      uriLinkStream: links.stream,
      getInstallReferrer: () async => null,
      isAndroid: false,
      isWeb: false,
    );
    await s.init();
    return s;
  }

  Widget app(PendingInviteService invites) => MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: auth,
          child: PendingInviteGuestSignIn(
            invites: invites,
            child: const Text('root'),
          ),
        ),
      );

  final invite = Uri.parse('taskcaster://join?code=ABC234');

  testWidgets('signed out + pending invite -> one guest sign-in',
      (tester) async {
    when(() => auth.state).thenReturn(AuthUnauthenticated());
    final invites = await service(initial: invite);

    await tester.pumpWidget(app(invites));
    await tester.pump();

    verify(() => auth.add(any(that: isA<AnonymousSignInRequested>())))
        .called(1);

    // A failed attempt must not loop.
    when(() => auth.state).thenReturn(const AuthError(message: 'nope'));
    authStates.add(const AuthError(message: 'nope'));
    when(() => auth.state).thenReturn(AuthUnauthenticated());
    authStates.add(AuthUnauthenticated());
    await tester.pump();
    verifyNever(() => auth.add(any()));
  });

  testWidgets('waits for the startup auth check to settle', (tester) async {
    when(() => auth.state).thenReturn(AuthLoading());
    final invites = await service(initial: invite);

    await tester.pumpWidget(app(invites));
    await tester.pump();
    verifyNever(() => auth.add(any()));

    when(() => auth.state).thenReturn(AuthUnauthenticated());
    authStates.add(AuthUnauthenticated());
    await tester.pump();
    verify(() => auth.add(any(that: isA<AnonymousSignInRequested>())))
        .called(1);
  });

  testWidgets('a link arriving later while signed out also signs in',
      (tester) async {
    when(() => auth.state).thenReturn(AuthUnauthenticated());
    final invites = await service();

    await tester.pumpWidget(app(invites));
    await tester.pump();
    verifyNever(() => auth.add(any()));

    links.add(invite);
    await tester.pump();
    verify(() => auth.add(any(that: isA<AnonymousSignInRequested>())))
        .called(1);
  });

  testWidgets('no invite -> no sign-in (cold open stays)', (tester) async {
    when(() => auth.state).thenReturn(AuthUnauthenticated());
    final invites = await service();

    await tester.pumpWidget(app(invites));
    await tester.pump();
    verifyNever(() => auth.add(any()));
    expect(find.text('root'), findsOneWidget);
  });
}
