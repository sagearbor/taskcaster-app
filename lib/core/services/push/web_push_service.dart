/// "Tell me when someone grades my clip."
///
/// Ties the browser Push API ([PushGateway]) to the store the Cloud Function
/// reads: `push_subscriptions/{uid}.subs.{id}`.
///
/// Subscriptions live in their own collection rather than on `users/{uid}`
/// because the rules let any signed-in user READ any user document, and a push
/// endpoint is not something to hand out. `push_subscriptions` is readable and
/// writable only by its owner.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'push_gateway.dart';

/// The outcome of asking. The UI needs to tell these apart: "denied" must
/// never re-prompt, and "unsupported" must never have been offered.
enum PushOptInResult { enabled, declined, unsupported, failed }

class WebPushService {
  static const String collection = 'push_subscriptions';

  final PushGateway _gateway;
  final FirebaseFirestore? _injectedFirestore;

  /// Resolved only when there is actually a subscription to store.
  ///
  /// Eagerly reading `FirebaseFirestore.instance` here would make merely
  /// ASKING whether to show the opt-in card require an initialised Firebase —
  /// which it does not, and which throws in widget tests that build the Posted
  /// screen without one.
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  WebPushService({PushGateway? gateway, FirebaseFirestore? firestore})
      : _gateway = gateway ?? PushGateway(),
        _injectedFirestore = firestore;

  /// Whether it is worth showing the opt-in card at all: only when the browser
  /// can do push AND has not already been answered either way.
  bool get canPrompt => _gateway.permission() == PushPermission.prompt;

  /// Whether this browser is already subscribed.
  bool get isEnabled => _gateway.permission() == PushPermission.granted;

  /// Prompt, subscribe, and persist. Safe to call twice: the subscription id
  /// is derived from the endpoint, so a re-subscribe overwrites its own entry.
  Future<PushOptInResult> enable(String uid) async {
    if (uid.isEmpty) return PushOptInResult.failed;
    if (_gateway.permission() == PushPermission.unsupported) {
      return PushOptInResult.unsupported;
    }

    final subscription = await _gateway.subscribe();
    if (subscription == null) {
      // Either the player said no, or the browser refused. Both mean the same
      // thing to the caller, and neither is an error worth surfacing.
      return _gateway.permission() == PushPermission.denied
          ? PushOptInResult.declined
          : PushOptInResult.failed;
    }

    try {
      await _firestore.collection(collection).doc(uid).set({
        'subs': {subscription.id: subscription.toMap()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return PushOptInResult.enabled;
    } catch (e) {
      // The browser is subscribed but we could not record it. Say so rather
      // than claiming success: without the Firestore doc nothing will ever
      // send to it.
      debugPrint('WebPushService.enable failed to persist: $e');
      return PushOptInResult.failed;
    }
  }
}
