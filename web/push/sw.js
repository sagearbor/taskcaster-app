/* TaskCaster web push service worker.
 *
 * Deliberately NOT flutter_service_worker.js: Flutter owns that file and
 * regenerates it on every `flutter build web`, so anything added there is lost
 * at the next build. This is a second, tiny worker registered only for push.
 *
 * It does two things: draw the notification when one arrives, and focus the
 * app when it is clicked. No caching, no fetch handler -- Flutter's own worker
 * handles the app shell.
 */

'use strict';

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (err) {
    payload = {};
  }

  const title = payload.title || 'TaskCaster';
  const options = {
    body: payload.body || 'Someone graded your clip.',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    // Re-using the tag means a second grade on the same post replaces the
    // first notification instead of stacking another one on the lock screen.
    tag: payload.tag || 'taskcaster',
    renotify: true,
    data: payload.data || {url: '/'},
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || '/';

  event.waitUntil(
    self.clients.matchAll({type: 'window', includeUncontrolled: true}).then((clients) => {
      // Prefer an already-open tab: opening a second copy of a game the player
      // is mid-task in would be worse than useless.
      for (const client of clients) {
        if ('focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
      return undefined;
    }),
  );
});
