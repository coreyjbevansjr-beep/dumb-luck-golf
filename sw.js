/* Dumb Luck Golf service worker - offline shell, never cache Supabase */
const CACHE = 'dlg-golf-v116';
// v8.20+: include the exact ?v= URLs index.html requests (cache-first lookups match the full URL incl. query)
const PRECACHE = [
  './',
  './manifest.webmanifest',
  './manifest.webmanifest?v=81',
  './favicon-32.png',
  './favicon-32.png?v=81',
  './icon-192.png',
  './icon-192.png?v=81',
  './icon-512.png',
  './icon-192-maskable.png',
  './icon-512-maskable.png',
  './apple-touch-icon.png',
  './apple-touch-icon.png?v=81',
  './og-image.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(PRECACHE.map((u) => new Request(u, { cache: 'reload' }))).catch(() => {})).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});

function isSupabase(url) {
  return /supabase\.co/i.test(url) || /\/rest\/v1\//i.test(url);
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = req.url;
  if (isSupabase(url)) return; // network only - never cache leaderboard traffic

  const dest = req.destination;
  const isNav = req.mode === 'navigate' || dest === 'document';
  const isHtml = isNav || /\.html(\?|$)/i.test(url) || /\/$/.test(new URL(url).pathname);

  if (isHtml) {
    // network-first for HTML / navigations so updates show up
    e.respondWith(
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => caches.match(req).then((r) => r || caches.match('./')))
    );
    return;
  }

  // cache-first for static assets
  e.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      });
    })
  );
});
