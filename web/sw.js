const CACHE_NAME = 'mob-racing-v0.8.0-r2';
const FORCE_COI_HEADERS = false;

// Keep install precache lightweight so first-time COI Service Worker activation
// on static hosts (GitHub Pages) completes rapidly without double-downloading large Wasm/font files.
const PRECACHE_SHELL = [
  './',
  './index.html',
  './mob-env.js',
  './manifest.json',
  './ui-overlay.css',
  './ui-overlay.js'
];

function shouldInjectCoiHeaders() {
  if (FORCE_COI_HEADERS) return true;
  try {
    return /\.github\.io$/i.test(self.location.hostname || '');
  } catch (_) {
    return false;
  }
}

function withCoiHeaders(response) {
  if (!response || !shouldInjectCoiHeaders()) return response;
  if (response.status === 0 || response.type === 'opaque' || response.type === 'opaqueredirect') {
    return response;
  }
  const headers = new Headers(response.headers);
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_SHELL)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.cache === 'only-if-cached' && req.mode !== 'same-origin') {
    return;
  }

  let url;
  try {
    url = new URL(req.url);
  } catch (_) {
    return;
  }

  if (url.origin !== self.location.origin || url.pathname.endsWith('.ashx')) {
    return;
  }

  const networkPromise = req.mode === 'navigate'
    ? fetch(req.url, { cache: 'no-cache', credentials: 'same-origin', redirect: 'follow' })
    : fetch(req, { cache: 'no-cache' });

  event.respondWith(
    networkPromise
      .then((res) => {
        if (res && res.status === 200 && req.method === 'GET' && res.type !== 'opaque') {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, copy)).catch(() => {});
        }
        return withCoiHeaders(res);
      })
      .catch(() => caches.match(req).then((cached) => (cached ? withCoiHeaders(cached) : cached)))
  );
});
