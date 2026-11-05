import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/features/arena/data/repositories/mock_montage_repository.dart';
import 'package:taskcaster_app/features/arena/domain/models/montage.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/montage_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/arena_video.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/countdown_burn.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/finale_card.dart';

import '../../../../helpers/fake_video_player_platform.dart';

void main() {
  late MockMontageRepository montages;

  setUp(() async {
    await sl.reset();
    FakeVideoPlayerPlatform.install();
    montages = MockMontageRepository();
    sl.registerLazySingleton<MontageRepository>(() => montages);
  });

  Future<void> pump(
    WidgetTester tester, {
    String gameId = 'game-1',
    String taskId = 'starter-01',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FinaleCard(gameId: gameId, taskId: taskId),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('opens ONE montage listener across rebuilds, a new one per task',
      (tester) async {
    final counting = _CountingMontageRepository(montages);
    await sl.reset();
    sl.registerLazySingleton<MontageRepository>(() => counting);

    late StateSetter rebuild;
    var taskId = 'starter-01';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return FinaleCard(gameId: 'game-1', taskId: taskId);
          }),
        ),
      ),
    );
    expect(counting.calls, 1);

    for (var i = 0; i < 5; i++) {
      rebuild(() {});
      await tester.pump();
    }
    expect(counting.calls, 1, reason: 'rebuilds must reuse the stream');

    rebuild(() => taskId = 'starter-02');
    await tester.pump();
    expect(counting.calls, 2, reason: 'a new task opens a new listener');
  });

  testWidgets('renders nothing when no montage exists', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('arena-finale-card')), findsNothing);
    expect(find.byType(ArenaVideo), findsNothing);
  });

  testWidgets('renders nothing while the render is pending', (tester) async {
    montages.seed(const Montage(
      gameId: 'game-1',
      taskId: 'starter-01',
      status: MontageStatus.pending,
    ));
    await pump(tester);
    expect(find.byKey(const Key('arena-finale-card')), findsNothing);
  });

  testWidgets('renders nothing when the first render failed (no finale yet)',
      (tester) async {
    montages.seed(const Montage(
      gameId: 'game-1',
      taskId: 'starter-01',
      status: MontageStatus.failed,
    ));
    await pump(tester);
    expect(find.byKey(const Key('arena-finale-card')), findsNothing);
  });

  testWidgets('keeps the last finale while a re-render is pending or failed',
      (tester) async {
    // The server flips status on every new clip; the last rendered finale
    // stays up until a newer one replaces it (seen on production).
    montages.seed(const Montage(
      gameId: 'game-1',
      taskId: 'starter-01',
      finaleUrl: 'https://cdn.test/previous.mp4',
      status: MontageStatus.pending,
    ));
    await pump(tester);
    expect(find.byKey(const Key('arena-finale-card')), findsOneWidget);
  });

  testWidgets('shows the finale once the server says ready', (tester) async {
    montages.seed(const Montage(
      gameId: 'game-1',
      taskId: 'starter-01',
      finaleUrl: 'https://cdn.test/finale.mp4',
      status: MontageStatus.ready,
    ));
    await pump(tester);

    expect(find.byKey(const Key('arena-finale-card')), findsOneWidget);
    expect(find.text('Watch the finale'), findsOneWidget);
    expect(find.byType(ArenaVideo), findsOneWidget);
    // The montage carries its own burned-in clock.
    expect(find.byType(CountdownBurn), findsNothing);
  });

  testWidgets('a house post (no game) never asks for a montage',
      (tester) async {
    await pump(tester, gameId: '');
    expect(find.byKey(const Key('arena-finale-card')), findsNothing);
  });
}

class _CountingMontageRepository implements MontageRepository {
  final MontageRepository inner;
  int calls = 0;

  _CountingMontageRepository(this.inner);

  @override
  Stream<Montage?> watchMontage(String gameId, String taskId) {
    calls++;
    return inner.watchMontage(gameId, taskId);
  }
}
