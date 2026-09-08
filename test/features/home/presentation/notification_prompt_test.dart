import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/services/notification_prompt.dart';
import 'package:taskcaster_app/core/services/notification_service.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/home/presentation/screens/home_screen.dart';

class _SpyNotificationService extends MockNotificationService {
  int initializeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }
}

void main() {
  late _SpyNotificationService spy;

  setUp(() async {
    await sl.reset();
    await ServiceLocator.init(useMockServices: true);
    spy = _SpyNotificationService();
    sl.unregister<NotificationService>();
    sl.registerSingleton<NotificationService>(spy);
    NotificationPrompt.resetForTest();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(authRepository: sl<AuthRepository>()),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('notification setup runs once, after the home screen renders',
      (tester) async {
    expect(spy.initializeCalls, 0,
        reason: 'nothing may prompt before the home screen exists');

    await pumpHome(tester);
    expect(spy.initializeCalls, 1);

    // Rebuilds / re-entering home must not prompt again.
    await tester.pump(const Duration(milliseconds: 50));
    await pumpHome(tester);
    expect(spy.initializeCalls, 1);
  });
}
