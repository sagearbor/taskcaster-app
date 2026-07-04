import 'package:get_it/get_it.dart';

import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/datasources/mock_auth_data_source.dart';
import '../../features/auth/data/datasources/firebase_auth_data_source.dart';

import '../../features/games/data/repositories/game_repository_impl.dart';
import '../../features/games/domain/repositories/game_repository.dart';
import '../../features/games/data/datasources/game_remote_data_source.dart';
import '../../features/games/data/datasources/mock_game_data_source.dart';
import '../../features/games/data/datasources/firestore_game_data_source.dart';

import '../../features/tasks/data/repositories/task_repository_impl.dart';
import '../../features/tasks/domain/repositories/task_repository.dart';
import '../../features/tasks/data/datasources/task_remote_data_source.dart';
import '../../features/tasks/data/datasources/mock_task_data_source.dart';
import '../../features/tasks/data/datasources/firebase_task_data_source.dart';

import '../../features/telephone/data/repositories/telephone_repository_impl.dart';
import '../../features/telephone/domain/repositories/telephone_repository.dart';
import '../../features/telephone/data/datasources/telephone_remote_data_source.dart';
import '../../features/telephone/data/datasources/mock_telephone_data_source.dart';
import '../../features/telephone/data/datasources/firestore_telephone_data_source.dart';
import '../../features/telephone/data/datasources/telephone_session_store.dart';

import '../../features/trivia/data/repositories/trivia_repository_impl.dart';
import '../../features/trivia/domain/repositories/trivia_repository.dart';
import '../../features/trivia/data/datasources/trivia_remote_data_source.dart';
import '../../features/trivia/data/datasources/mock_trivia_data_source.dart';

import '../services/invite/pending_invite_service.dart';
import '../services/ad_service_simple.dart';
import '../services/purchase_service_simple.dart';
import '../services/ai_task_service.dart';
import '../services/notification_service.dart';
import '../services/ar/ar_capability_service.dart';
import '../services/ar/ar_engine.dart';
import '../services/ar/ar_flutter_engine.dart';

final GetIt sl = GetIt.instance;

class ServiceLocator {
  static Future<void> init({bool useMockServices = true}) async {
    // Data Sources
    if (useMockServices) {
      sl.registerLazySingleton<AuthRemoteDataSource>(
        () => MockAuthDataSource(),
      );
      sl.registerLazySingleton<GameRemoteDataSource>(
        () => MockGameDataSource(),
      );
      sl.registerLazySingleton<TaskRemoteDataSource>(
        () => MockTaskDataSource(),
      );
      sl.registerLazySingleton<TelephoneRemoteDataSource>(
        () => MockTelephoneDataSource(),
      );
    } else {
      // Firebase implementations
      sl.registerLazySingleton<AuthRemoteDataSource>(
        () => FirebaseAuthDataSource(),
      );
      sl.registerLazySingleton<GameRemoteDataSource>(
        () => FirestoreGameDataSource(),
      );
      sl.registerLazySingleton<TaskRemoteDataSource>(
        () => FirebaseTaskDataSource(),
      );
      sl.registerLazySingleton<TelephoneRemoteDataSource>(
        () => FirestoreTelephoneDataSource(),
      );
    }

    // Repositories
    sl.registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(sl()),
    );
    sl.registerLazySingleton<GameRepository>(
      () => GameRepositoryImpl(sl()),
    );
    sl.registerLazySingleton<TaskRepository>(
      () => TaskRepositoryImpl(sl()),
    );
    sl.registerLazySingleton<TelephoneRepository>(
      () => TelephoneRepositoryImpl(sl()),
    );

    // Local persistence of the player's active Drawing Telephone identity, so a
    // user who navigates away can rejoin as the same player (host stays host).
    sl.registerLazySingleton<TelephoneSessionStore>(
      () => TelephoneSessionStore(),
    );

    // Trivia Buzzer is offline / host-authoritative-transport first: it always
    // uses the in-memory data source for now. A Nearby / Bluetooth transport
    // (or a Firestore source) implementing TriviaRemoteDataSource slots in here
    // later — the repository and bloc are already transport-agnostic.
    sl.registerLazySingleton<TriviaRemoteDataSource>(
      () => MockTriviaDataSource(),
    );
    sl.registerLazySingleton<TriviaRepository>(
      () => TriviaRepositoryImpl(sl()),
    );

    // AR capability gating. Single real implementation on all builds — it
    // self-gates by platform/permission and never throws, so there is no need
    // for a separate mock. Tests construct ArCapabilityServiceImpl directly
    // with injected platform seams.
    sl.registerLazySingleton<ArCapabilityService>(
      () => ArCapabilityServiceImpl(),
    );

    // AR render engine. A FACTORY (not a singleton): each AR task gets a fresh
    // engine so its platform AR view + streams are cleanly torn down on exit.
    // Only constructed on AR-capable mobile devices (the capability check gates
    // every caller), so the plugin is never instantiated on web/desktop.
    sl.registerFactory<ArEngine>(() => ArFlutterEngine());

    // Friend-invite loop: captures invite codes arriving via deep link or
    // Play Install Referrer. Same implementation for mock and real services —
    // it is a platform concern, not a data-source one. init() is fired from
    // main() so cold-start links are caught before the home screen mounts.
    sl.registerLazySingleton<PendingInviteService>(
      () => PendingInviteService(),
    );


    // Additional Services
    if (useMockServices) {
      sl.registerLazySingleton<AdService>(() => MockAdService());
      sl.registerLazySingleton<PurchaseService>(() => MockPurchaseService());
      sl.registerLazySingleton<AITaskService>(() => MockAITaskService());
      sl.registerLazySingleton<NotificationService>(
          () => MockNotificationService());
    } else {
      sl.registerLazySingleton<AdService>(() => AdServiceImpl());
      sl.registerLazySingleton<PurchaseService>(() => PurchaseServiceImpl());
      sl.registerLazySingleton<AITaskService>(() => AITaskServiceImpl());
      sl.registerLazySingleton<NotificationService>(
          () => FcmNotificationService());
    }
  }
}

