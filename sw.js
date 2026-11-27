// @less fashion Scratch & Win - makes the app installable and loads fast on shop Wi-Fi
const CACHE = 'sw-app-v2';
const SHELL = ['/counter.html', '/admin.html', '/index.html', '/style.css', '/common.js', '/config.js', '/manifest.webmanifest', '/icon-192.png', '/icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return; // Supabase and fonts go straight to the network
  // always try the network first so updates show at once; fall back to the saved copy when offline
  e.respondWith(fetch(e.request).then(r => { if (r.ok) { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); } return r; })
    .catch(() => caches.match(e.request, {ignoreSearch: true})));
});
