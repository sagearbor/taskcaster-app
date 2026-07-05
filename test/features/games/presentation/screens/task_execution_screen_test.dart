import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';

class MockGameRepository extends Mock implements GameRepository {}

class FakeGame extends Fake implements Game {}

void main() {
  late MockGameRepository mockRepo;

  setUpAll(() {
    registerFallbackValue(FakeGame());
  });

  setUp(() {
    mockRepo = MockGameRepository();
  });

  Game buildGame({PlayerTaskStatus? user1Status}) {
    return Game(
      id: 'game1',
      gameName: 'Test Game',
      creatorId: 'user1',
      judgeId: 'judge1',
      status: GameStatus.inProgress,
      inviteCode: 'ABC123',
      createdAt: DateTime.now(),
      players: [
        const Player(userId: 'user1', displayName: 'Alice', totalScore: 0),
        const Player(userId: 'user2', displayName: 'Bob', totalScore: 0),
      ],
      tasks: [
        Task(
          id: 'task-1',
          title: 'Butter a slice of bread wearing oven mitts',
          description:
              'Both hands in oven mitts. Butter one slice of bread edge to edge. Most elegant technique wins.',
          taskType: TaskType.video,
          category: 'Kitchen Capers',
          submissions: const [],
          playerStatuses: {
            'user1': user1Status ??
                const PlayerTaskStatus(
                  playerId: 'user1',
                  state: TaskPlayerState.not_started,
                ),
            'user2': const PlayerTaskStatus(
              playerId: 'user2',
              state: TaskPlayerState.not_started,
            ),
          },
        ),
      ],
      settings: const GameSettings(),
    );
  }

  Widget buildTestApp() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BlocProvider(
                    create: (_) => TaskExecutionBloc(gameRepository: mockRepo)
                      ..add(const LoadTask(
                        gameId: 'game1',
                        taskIndex: 0,
                        userId: 'user1',
                      )),
                    child: const TaskExecutionView(
                      gameId: 'game1',
                      taskIndex: 0,
                      userId: 'user1',
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open Task'),
          ),
        ),
      ),
    );
  }

  Future<void> openTaskScreen(WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.tap(find.text('Open Task'));
    await tester.pumpAndSettle();
  }

  group('TaskExecutionView', () {
    testWidgets('presents the task as a reveal card with category chip',
        (tester) async {
      when(() => mockRepo.getGameStream('game1'))
          .thenAnswer((_) => Stream.value(buildGame()));

      await openTaskScreen(tester);

      expect(find.text('YOUR TASK, SHOULD YOU ACCEPT IT…'), findsOneWidget);
      expect(find.text('Butter a slice of bread wearing oven mitts'),
          findsOneWidget);
      expect(find.text('Kitchen Capers'), findsOneWidget);

      // The submission checklist is visible.
      expect(find.text('How it works'), findsOneWidget);
      expect(find.text('Film it with your camera app'), findsOneWidget);
      expect(
          find.text('Upload to Google Photos or YouTube'), findsOneWidget);
      expect(find.text('Paste the share link below'), findsOneWidget);
    });

    testWidgets('paste button fills the link field and enables submit',
        (tester) async {
      when(() => mockRepo.getGameStream('game1'))
          .thenAnswer((_) => Stream.value(buildGame()));
      when(() => mockRepo.updateGame(any(), any())).thenAnswer((_) async {});

      // Put a link on the (mock) clipboard.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': 'https://youtu.be/mitts123'};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await openTaskScreen(tester);

      // Submit is disabled until we have a valid link.
      // Use byWidgetPredicate so the is-subtype check matches _ElevatedButtonWithIcon
      // (ElevatedButton.icon factory creates that private subtype; find.byType uses
      // exact runtimeType equality and would miss it).
      final submitButton = find.ancestor(
        of: find.text('Submit Video'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      await tester.ensureVisible(submitButton);
      expect(tester.widget<ElevatedButton>(submitButton).onPressed, isNull);

      // Tap paste-from-clipboard.
      await tester.tap(find.byIcon(Icons.content_paste));
      await tester.pump();

      expect(find.text('https://youtu.be/mitts123'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsWidgets);
      expect(
          tester.widget<ElevatedButton>(submitButton).onPressed, isNotNull);

      // Submit and land in the submitted state.
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Submission successful! ✅'), findsOneWidget);
      verify(() => mockRepo.updateGame('game1', any())).called(1);

      // Let the auto-close timer fire.
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('shows a friendly error for an invalid link', (tester) async {
      when(() => mockRepo.getGameStream('game1'))
          .thenAnswer((_) => Stream.value(buildGame()));

      await openTaskScreen(tester);

      await tester.enterText(
          find.byType(TextField), 'youtube.com/watch?v=abc');
      await tester.pump();

      expect(
          find.text('Almost! Add https:// to the front of that link.'),
          findsOneWidget);

      final submitButton = find.ancestor(
        of: find.text('Submit Video'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      await tester.ensureVisible(submitButton);
      expect(tester.widget<ElevatedButton>(submitButton).onPressed, isNull);
    });

    testWidgets('shows the submitted state when the player already submitted',
        (tester) async {
      when(() => mockRepo.getGameStream('game1')).thenAnswer(
        (_) => Stream.value(buildGame(
          user1Status: PlayerTaskStatus(
            playerId: 'user1',
            state: TaskPlayerState.submitted,
            submissionUrl: 'https://youtu.be/done456',
            submittedAt: DateTime.now(),
          ),
        )),
      );

      await openTaskScreen(tester);

      expect(find.text('Already Submitted ✅'), findsOneWidget);
      expect(find.text('https://youtu.be/done456'), findsOneWidget);
      expect(find.text('Change my video'), findsOneWidget);
    });
  });
}
