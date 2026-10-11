/**
 * M.O.B. // Motors on Boost - Service Worker
 * Strategy: Network-First (Live Server First) with Offline Cache Fallback.
 * Ensures the client always fetches the freshest live build while gracefully
 * falling back to local cached assets if offline or if network encounters errors.
 */

const CACHE_NAME = 'mob-motors-on-boost-v3-0';

const ASSETS_TO_CACHE = [
  './',
  './index.html',
  './game.js',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/brake.png',
  './icons/burn.png',
  './icons/gas-pedal.png',
  './icons/hand-brake.png',
  './intro/jagofr-rvl-splash.webp',
  './intro/heaps-haxe-splash.webp',
  './intro/icons/logo_haxe.webp',
  './intro/icons/logo_heaps.webp',
  './intro/icons/logo_webgl.webp'
];

// 1. Installation: Pre-cache primary game shell and assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS_TO_CACHE);
    }).then(() => self.skipWaiting())
  );
});

// 2. Activation: Clean up stale caches and claim clients immediately
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
    }).then(() => self.clients.claim())
  );
});

// 3. Fetch Strategy: Network-First with Cache Fallback
self.addEventListener('fetch', (event) => {
  // Only handle standard GET requests
  if (event.request.method !== 'GET') {
    return;
  }

  // Bypass chrome-extension and non-HTTP/HTTPS schemes
  if (!event.request.url.startsWith('http://') && !event.request.url.startsWith('https://')) {
    return;
  }

  event.respondWith(
    // Always attempt live network request first
    fetch(event.request)
      .then((networkResponse) => {
        // If response is valid, update local cache with the newest live asset
        if (networkResponse && networkResponse.status === 200 && networkResponse.type === 'basic') {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseToCache);
          });
        }
        return networkResponse;
      })
      .catch(() => {
        // Live server failed (offline, timeout, connection lost) -> Fallback to Cache
        return caches.match(event.request).then((cachedResponse) => {
          if (cachedResponse) {
            return cachedResponse;
          }
          // If HTML navigation failed and specific page not found, fallback to root index.html
          if (event.request.mode === 'navigate') {
            return caches.match('./index.html');
          }
          return new Response('Network error and asset not found in offline cache.', {
            status: 503,
            statusText: 'Service Unavailable',
            headers: new Headers({ 'Content-Type': 'text/plain' })
          });
        });
      })
  );
});