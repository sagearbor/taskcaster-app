import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'plans.dart';

/// The signed-in player's plan, live.
///
/// Reads the server-owned plan fields on `users/{uid}` (written by the
/// RevenueCat webhook / refreshEntitlement Cloud Functions). Because the plan
/// lives in Firestore, Pro bought in the iOS/Android app also shows up on the
/// web, which has no in-app purchase of its own.
abstract class PlanRepository {
  /// The current plan, re-emitted on every auth or plan change.
  Stream<UserPlan> watchPlan();

  /// The plan right now (one read). Never throws: a failure is the free plan
  /// for a signed-in player and the guest plan for an anonymous one, which is
  /// what the Storage rules would assume as well.
  Future<UserPlan> currentPlan();
}

/// Firestore + Firebase Auth.
class FirestorePlanRepository implements PlanRepository {
  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirestorePlanRepository({fb.FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<UserPlan> watchPlan() {
    // userChanges (not authStateChanges): linking a guest to Apple/Google
    // keeps the uid but flips isAnonymous, and only userChanges reports it.
    return _auth.userChanges().asyncExpand((user) {
      if (user == null) return Stream.value(UserPlan.guest);
      return _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map((snap) => UserPlan.fromUserDoc(
                snap.data(),
                isAnonymous: user.isAnonymous,
              ))
          .handleError((Object _) {});
    });
  }

  @override
  Future<UserPlan> currentPlan() async {
    final user = _auth.currentUser;
    if (user == null) return UserPlan.guest;
    final fallback = user.isAnonymous ? UserPlan.guest : UserPlan.free;
    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      return UserPlan.fromUserDoc(snap.data(), isAnonymous: user.isAnonymous);
    } catch (_) {
      return fallback;
    }
  }
}

/// In-memory plan for mock builds and widget tests. Starts free.
class MockPlanRepository implements PlanRepository {
  final StreamController<UserPlan> _controller =
      StreamController<UserPlan>.broadcast();
  UserPlan _plan;

  MockPlanRepository({UserPlan initial = UserPlan.free}) : _plan = initial;

  UserPlan get plan => _plan;

  set plan(UserPlan value) {
    _plan = value;
    _controller.add(value);
  }

  @override
  Stream<UserPlan> watchPlan() async* {
    yield _plan;
    yield* _controller.stream;
  }

  @override
  Future<UserPlan> currentPlan() async => _plan;
}
