import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/utils/funny_names.dart';
import 'package:taskcaster_app/features/auth/data/datasources/mock_auth_data_source.dart';
import 'package:taskcaster_app/features/auth/data/repositories/auth_repository_impl.dart';

void main() {
  group('AuthRepositoryImpl.updateProfile (mock)', () {
    late MockAuthDataSource dataSource;
    late AuthRepositoryImpl repository;

    setUp(() {
      dataSource = MockAuthDataSource();
      repository = AuthRepositoryImpl(dataSource);
    });

    tearDown(() => dataSource.dispose());

    test('updates display name and avatar emoji', () async {
      await repository.signInWithEmailAndPassword(
          'sophie@example.com', 'password123');

      final updated = await repository.updateProfile(
        displayName: 'Sophie A',
        avatarEmoji: '🏆',
      );

      expect(updated.displayName, 'Sophie A');
      expect(updated.avatarEmoji, '🏆');

      // A fresh read reflects the change.
      final current = await repository.getCurrentUser();
      expect(current?.displayName, 'Sophie A');
      expect(current?.avatarEmoji, '🏆');
    });

    test('Google/Apple from a guest keeps the same uid (mock mirrors link)',
        () async {
      final guest = await repository.signInAnonymously();
      final viaGoogle = await repository.signInWithGoogle();
      expect(viaGoogle.id, guest.id);
      expect(repository.isCurrentUserAnonymous(), isFalse);
      expect(repository.takeSignInNotice(), isNull);
    });

    test('upgradeGuestAccount keeps the same uid (preserves data)', () async {
      final guest = await repository.signInAnonymously();
      expect(repository.isCurrentUserAnonymous(), isTrue);

      final upgraded = await repository.upgradeGuestAccount(
        'new@example.com',
        'password123',
        'New Name',
      );

      // Same uid → existing game data stays attached to the user.
      expect(upgraded.id, guest.id);
      expect(upgraded.email, 'new@example.com');
      expect(repository.isCurrentUserAnonymous(), isFalse);
    });

    test('signInWithGoogle returns a non-anonymous user with email', () async {
      final user = await repository.signInWithGoogle();

      expect(user.id, isNotEmpty);
      expect(user.email, isNotNull);
      expect(repository.isCurrentUserAnonymous(), isFalse);

      // A fresh read resolves the same signed-in user.
      final current = await repository.getCurrentUser();
      expect(current?.id, user.id);
    });

    test('signInWithApple returns a non-anonymous user', () async {
      final user = await repository.signInWithApple();

      expect(user.id, isNotEmpty);
      expect(repository.isCurrentUserAnonymous(), isFalse);
      expect(repository.getCurrentUserId(), user.id);
    });

    test('a new guest gets their funny name, not "Guest"', () async {
      final guest = await repository.signInAnonymously();
      expect(guest.displayName, FunnyNames.forUid(guest.id));
      expect(guest.displayName, isNot('Guest'));

      // It is saved to the profile, so a fresh read returns the same name.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(dataSource.getCurrentUserData()?['displayName'],
          FunnyNames.forUid(guest.id));
      final current = await repository.getCurrentUser();
      expect(current?.displayName, FunnyNames.forUid(guest.id));
    });

    test('an existing guest stored as "Guest" is renamed on next launch',
        () async {
      final guest = await repository.signInAnonymously();
      // Simulate an older build: the profile still says "Guest".
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await dataSource.updateProfile(displayName: 'Guest');
      expect(dataSource.getCurrentUserData()?['displayName'], 'Guest');

      final current = await repository.getCurrentUser();
      expect(current?.displayName, FunnyNames.forUid(guest.id));
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(dataSource.getCurrentUserData()?['displayName'],
          FunnyNames.forUid(guest.id));
    });

    test('a guest who picked their own name keeps it', () async {
      await repository.signInAnonymously();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final updated = await repository.updateProfile(displayName: 'Sophie');
      expect(updated.displayName, 'Sophie');
      final current = await repository.getCurrentUser();
      expect(current?.displayName, 'Sophie');
    });

    test('sendPasswordReset rejects an invalid email', () async {
      await repository.signInWithEmailAndPassword('a@b.com', 'password123');
      expect(
        () => repository.sendPasswordReset('not-an-email'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
