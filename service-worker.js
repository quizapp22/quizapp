const CACHE_NAME = 'unitest-v2';

const STATIC_FILES = [
  './index.html',
];

// ══ INSTALL ══
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(STATIC_FILES))
  );
  self.skipWaiting();
});

// ══ ACTIVATE: احذف الكاشات القديمة ══
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// ══ FETCH: Network-First ══
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // تجاهل Supabase وأي API خارجي — يجب أن تمر على الشبكة دائماً
  if (url.hostname.includes('supabase.co')) return;
  if (url.hostname.includes('googleapis.com')) return;
  if (url.hostname.includes('cdnjs.cloudflare.com')) return;
  if (!url.protocol.startsWith('http')) return;

  // للـ HTML — Network First ثم كاش
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then(response => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match('./index.html'))
    );
    return;
  }

  // للملفات الأخرى — Cache First
  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) return cached;
      return fetch(event.request).then(response => {
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
        }
        return response;
      });
    })
  );
});
