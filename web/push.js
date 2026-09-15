/* Browser half of "you got graded" web push.
 *
 * Exposes three functions on `window` for the Dart side to call through
 * js_interop (see lib/core/services/push/). Keeping the Push API here rather
 * than in Dart means the whole thing is plain, debuggable browser code, and it
 * keeps the VAPID public key in exactly one client-side place.
 *
 * The Dart side never sees the key: it calls taskcasterPushSubscribe() and
 * gets back the subscription JSON to write to Firestore.
 */

'use strict';

(function () {
  /* The VAPID public key. Public by design -- it is the applicationServerKey
   * the browser subscribes with. Its private half lives in Secret Manager as
   * VAPID_PRIVATE_KEY. MUST match VAPID_PUBLIC_KEY in functions/src/push.js;
   * functions/test/push.test.js reads this file and asserts that it does,
   * because a mismatch fails silently (every send 403s, nothing else breaks).
   */
  var VAPID_PUBLIC_KEY =
    'BGOwK1VgkCnM159BYg50FxO_RdNoXvoEMTUml5nQ7LQiYvtN2T7uoO1vOrPt0smZ-dt4g9MqmsZOsv9j4NBzdxU';

  /* The push worker is served from its own directory, and registered with the
   * matching scope, because a scope holds exactly ONE service worker and
   * Flutter already owns '/' with flutter_service_worker.js. Registering this
   * one at '/' silently lost that fight: the subscription was created against
   * Flutter's worker, which has no 'push' handler, so every notification would
   * have arrived as Chrome's generic "this site was updated in the background"
   * instead of ours. A service worker's scope cannot be broader than its own
   * path, so serving it at /push/sw.js is what makes /push/ available.
   */
  var SW_URL = '/push/sw.js';
  var SW_SCOPE = '/push/';

  /** base64url -> Uint8Array, which is what applicationServerKey wants. */
  function urlBase64ToUint8Array(base64String) {
    var padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    var base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    var raw = window.atob(base64);
    var output = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; ++i) output[i] = raw.charCodeAt(i);
    return output;
  }

  /** Resolves once a registration has an activated worker to subscribe on. */
  function waitUntilActive(registration) {
    if (!registration) return Promise.resolve(null);
    if (registration.active) return Promise.resolve(registration);
    var pending = registration.installing || registration.waiting;
    if (!pending) return Promise.resolve(registration);
    return new Promise(function (resolve) {
      pending.addEventListener('statechange', function () {
        if (pending.state === 'activated') resolve(registration);
      });
    });
  }

  /** Whether this browser can do web push at all (Safari < 16.4, http://, ...). */
  window.taskcasterPushSupported = function () {
    return (
      'serviceWorker' in navigator &&
      'PushManager' in window &&
      'Notification' in window &&
      window.isSecureContext === true
    );
  };

  /** 'granted' | 'denied' | 'default' | 'unsupported' */
  window.taskcasterPushPermission = function () {
    if (!window.taskcasterPushSupported()) return 'unsupported';
    return Notification.permission;
  };

  /**
   * Ask for permission (if not already answered), subscribe, and hand the
   * subscription back as a JSON string for Dart to persist.
   *
   * Resolves to null rather than rejecting for every "no push this time"
   * outcome -- unsupported browser, denied permission, subscribe failure --
   * because the caller treats them all the same way: leave the player alone.
   */
  window.taskcasterPushSubscribe = function () {
    if (!window.taskcasterPushSupported()) return Promise.resolve(null);

    return Notification.requestPermission()
      .then(function (permission) {
        if (permission !== 'granted') return null;
        // NOT navigator.serviceWorker.ready: that resolves with the worker
        // controlling THIS page, which is Flutter's. We need our own
        // registration, so wait for it specifically to activate.
        return navigator.serviceWorker
          .register(SW_URL, {scope: SW_SCOPE})
          .then(waitUntilActive);
      })
      .then(function (registration) {
        if (!registration) return null;
        return registration.pushManager.getSubscription().then(function (existing) {
          if (existing) return existing;
          return registration.pushManager.subscribe({
            // Required by Chrome: every push must show a notification.
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
          });
        });
      })
      .then(function (subscription) {
        if (!subscription) return null;
        var json = subscription.toJSON();
        if (!json || !json.endpoint || !json.keys) return null;
        return JSON.stringify({
          endpoint: json.endpoint,
          p256dh: json.keys.p256dh,
          auth: json.keys.auth,
        });
      })
      .catch(function (err) {
        console.warn('taskcasterPushSubscribe failed', err);
        return null;
      });
  };
})();
