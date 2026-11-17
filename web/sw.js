const CACHE_NAME = 'mob-racing-v0.8.0-r1';
const PRECACHE_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './ui-overlay.css',
  './ui-overlay.js',
  './fonts/stack_sans.ttf',
  './fonts/symbols.ttf',
  './intro/jagofr-rvl-splash.webp',
  './intro/icons/logo_haxe.webp',
  './intro/icons/logo_hlwgpu.svg',
  './intro/icons/logo_webgpu.svg',
  './icons/gas-pedal.png',
  './icons/brake.png',
  './icons/hand-brake.png',
  './icons/burn.png',
  './game.wasm',
  './xgpu.wasm',
  './xwindow.wasm',
  './ash_browser.js',
  './ash_browser_bg.wasm',
  './libraries.json',
  './worker.js',
  './thread.js',
  './display.js',
  './window.mjs',
  './xwindow.mjs',
  './xwindow_wire.mjs',
  './gpu.mjs',
  './gpu-worker.mjs',
  './gpu-agent.mjs'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_ASSETS)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || url.pathname.endsWith('.ashx')) {
    return;
  }
  event.respondWith(
    fetch(event.request, { cache: 'no-cache' })
      .then((res) => {
        if (res && res.status === 200 && event.request.method === 'GET') {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() => caches.match(event.request))
  );
});
