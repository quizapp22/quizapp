const CACHE_NAME = 'durat-v1';

// الملفات التي تُخزَّن عند أول تثبيت
const STATIC_FILES = [
  '/quizapp/',
  '/quizapp/index.html',
];

// ══ INSTALL: خزّن الملفات الأساسية ══
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(STATIC_FILES);
    })
  );
  self.skipWaiting();
});

// ══ ACTIVATE: احذف الكاشات القديمة ══
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(key => key !== CACHE_NAME)
          .map(key => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

// ══ FETCH: استراتيجية Network-First ══
// حاول الشبكة أولاً، إذا فشلت أعطِ من الكاش
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // تجاهل طلبات Supabase — يجب أن تمر على الشبكة دائماً
  if (url.hostname.includes('supabase.co')) return;

  // تجاهل طلبات Chrome Extensions وغيرها
  if (!url.protocol.startsWith('http')) return;

  event.respondWith(
    fetch(event.request)
      .then(response => {
        // إذا نجح الطلب — خزّن نسخة في الكاش
        if (response && response.status === 200 && response.type === 'basic') {
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then(cache => {
            cache.put(event.request, responseClone);
          });
        }
        return response;
      })
      .catch(() => {
        // إذا فشلت الشبكة — أعطِ من الكاش
        return caches.match(event.request).then(cached => {
          if (cached) return cached;
          // إذا ما في كاش — أعطِ الصفحة الرئيسية
          return caches.match('/quizapp/index.html');
        });
      })
  );
});
