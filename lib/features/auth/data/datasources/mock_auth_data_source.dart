import 'dart:async';

import 'auth_remote_data_source.dart';

class MockAuthDataSource implements AuthRemoteDataSource {
  final StreamController<String?> _authStateController =
      StreamController<String?>.broadcast();
  String? _currentUserId;

  // In-memory profile for the signed-in user so profile edits/upgrades are
  // reflected back through getCurrentUser(...).
  String _displayName = 'Mock User';
  String? _email;
  String? _avatarEmoji;
  bool _isAnonymous = false;

  MockAuthDataSource() {
    // Simulate no user logged in initially
    _authStateController.add(null);
  }

  @override
  Stream<String?> get authStateChanges => _authStateController.stream;

  @override
  Future<String> signInWithEmailAndPassword(
      String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Simple validation for demo
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Email and password cannot be empty');
    }

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    // Simulate successful login
    _currentUserId = 'mock_user_${email.hashCode.abs()}';
    _email = email;
    _displayName = email.split('@')[0];
    _isAnonymous = false;
    _authStateController.add(_currentUserId);

    return _currentUserId!;
  }

  @override
  Future<String> createUserWithEmailAndPassword(
      String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1000));

    // Simple validation for demo
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Email and password cannot be empty');
    }

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    if (!email.contains('@')) {
      throw Exception('Invalid email format');
    }

    // Simulate successful account creation
    _currentUserId = 'mock_user_${email.hashCode.abs()}';
    _email = email;
    _displayName = email.split('@')[0];
    _isAnonymous = false;
    _authStateController.add(_currentUserId);

    return _currentUserId!;
  }

  @override
  Future<String> signInAnonymously() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Create anonymous user ID
    _currentUserId = 'mock_anon_${DateTime.now().millisecondsSinceEpoch}';
    _email = null;
    _displayName = 'Guest';
    _avatarEmoji = null;
    _isAnonymous = true;
    _authStateController.add(_currentUserId);

    return _currentUserId!;
  }

  @override
  Future<String> signInWithGoogle() async {
    await Future.delayed(const Duration(milliseconds: 800));
    _currentUserId = 'mock_google_${DateTime.now().millisecondsSinceEpoch}';
    _email = 'google.user@example.com';
    _displayName = 'Google User';
    _avatarEmoji = null;
    _isAnonymous = false;
    _authStateController.add(_currentUserId);
    return _currentUserId!;
  }

  @override
  Future<String> signInWithApple() async {
    await Future.delayed(const Duration(milliseconds: 800));
    _currentUserId = 'mock_apple_${DateTime.now().millisecondsSinceEpoch}';
    _email = 'apple.user@example.com';
    _displayName = 'Apple User';
    _avatarEmoji = null;
    _isAnonymous = false;
    _authStateController.add(_currentUserId);
    return _currentUserId!;
  }

  @override
  Future<void> signOut() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    _currentUserId = null;
    _email = null;
    _avatarEmoji = null;
    _isAnonymous = false;
    _authStateController.add(null);
  }

  @override
  String? getCurrentUserId() {
    return _currentUserId;
  }

  @override
  Map<String, dynamic>? getCurrentUserData() {
    if (_currentUserId == null) return null;

    return {
      'displayName': _displayName,
      'email': _email,
      'isAnonymous': _isAnonymous,
      'avatarEmoji': _avatarEmoji,
    };
  }

  @override
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    return getCurrentUserData();
  }

  @override
  Future<void> updateProfile({String? displayName, String? avatarEmoji}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (_currentUserId == null) {
      throw Exception('No signed-in user to update');
    }
    if (displayName != null && displayName.trim().isNotEmpty) {
      _displayName = displayName.trim();
    }
    if (avatarEmoji != null) {
      _avatarEmoji = avatarEmoji.isEmpty ? null : avatarEmoji;
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (email.isEmpty || !email.contains('@')) {
      throw Exception('Please enter a valid email address');
    }
    // Mock: no-op (no email actually sent).
  }

  @override
  Future<String> upgradeGuestAccount(
      String email, String password, String displayName) async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (_currentUserId == null || !_isAnonymous) {
      throw Exception('Only a guest account can be upgraded');
    }
    if (!email.contains('@')) {
      throw Exception('Invalid email format');
    }
    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }
    // Keep the SAME uid so existing game data is preserved.
    _email = email;
    _displayName =
        displayName.trim().isNotEmpty ? displayName.trim() : email.split('@')[0];
    _isAnonymous = false;
    // Re-emit the (unchanged) uid so listeners refresh.
    _authStateController.add(_currentUserId);
    return _currentUserId!;
  }

  void dispose() {
    _authStateController.close();
  }
}
