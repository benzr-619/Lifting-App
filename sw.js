var pendingTimer = null;

self.addEventListener('message', function(event) {
  var data = event.data;
  if (!data) return;

  if (data.type === 'SCHEDULE_TIMER') {
    if (pendingTimer !== null) {
      clearTimeout(pendingTimer);
      pendingTimer = null;
    }
    var delay = Math.max(0, data.endTime - Date.now());
    pendingTimer = setTimeout(function() {
      pendingTimer = null;
      self.registration.showNotification(data.title || 'Rest over', {
        body: data.body || 'Time to lift your next set!',
        icon: 'logo.png',
        tag: 'rest-timer',
        renotify: true,
        silent: false,
        requireInteraction: false
      });
    }, delay);
  } else if (data.type === 'CANCEL_TIMER') {
    if (pendingTimer !== null) {
      clearTimeout(pendingTimer);
      pendingTimer = null;
    }
  }
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(list) {
      if (list.length > 0) return list[0].focus();
      return clients.openWindow('./');
    })
  );
});
