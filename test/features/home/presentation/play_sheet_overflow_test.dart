import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/games_bloc.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/play_sheet.dart';

/// Regression test for a real RenderFlex overflow found on the Play sheet
/// ("BOTTOM OVERFLOWED BY 142 PIXELS") that reproduced on the pixel10_api35
/// emulator (a Pixel-9-class 1080x2424 physical panel, devicePixelRatio
/// ~2.625 -> ~411x923 logical) once all 11 Play-sheet rows were visible. The
/// sheet's Column used MainAxisSize.min with no scrolling, so on a screen
/// this short the row list simply didn't fit and overflowed instead of
/// scrolling.
///
/// This pumps the Play sheet directly (rather than through the full
/// HomeScreen) so the test is isolated to the widget this bug lives in and
/// isn't coupled to unrelated Home-screen layout at this narrow width.
void main() {
  setUp(() async {
    await sl.reset();
    await ServiceLocator.init(useMockServices: true);
  });
  tearDown(() => sl.reset());

  Future<void> pumpPlaySheetAtPixel10Size(WidgetTester tester) async {
    // Physical size + device pixel ratio matching the pixel10_api35
    // emulator's panel (1080x2424 @ 2.625x -> ~411x923 logical) that this
    // bug was originally reported on.
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gamesBloc = GamesBloc(
      gameRepository: sl<GameRepository>(),
      authRepository: sl<AuthRepository>(),
    );
    addTearDown(gamesBloc.close);
    final authBloc = AuthBloc(authRepository: sl<AuthRepository>());
    addTearDown(authBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<GamesBloc>.value(value: gamesBloc),
            BlocProvider<AuthBloc>.value(value: authBloc),
          ],
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showPlaySheet(context),
                  child: const Text('Open Play sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'renders every row at the pixel10_api35 screen size with no '
      'RenderFlex overflow', (tester) async {
    await pumpPlaySheetAtPixel10Size(tester);

    await tester.tap(find.text('Open Play sheet'));
    await tester.pumpAndSettle();

    // No overflow (or any other) exception was thrown while laying out /
    // rendering the sheet at this screen size.
    expect(tester.takeException(), isNull);

    // Every row is reachable — the first ones are visible immediately, and
    // scrolling the (now-scrollable) sheet reveals the ones that don't fit
    // on screen at once, instead of them being clipped/overflowed off the
    // bottom.
    expect(find.text('Quick Play'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Join with a code'), 200);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
