const CACHE_NAME = "liquidity-signal-v3";
const SHELL_FILES = [
  "./",
  "./index.html",
  "./manifest.json",
  "./hero-bg.svg",
  "./icon-192.png",
  "./icon-512.png"
];

const NO_CACHE_HOSTS = ["generativelanguage.googleapis.com", "api.twelvedata.com"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Never cache live API calls — always go to the network.
  if (NO_CACHE_HOSTS.includes(url.hostname)) {
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => {
      return (
        cached ||
        fetch(event.request).then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        }).catch(() => cached)
      );
    })
  );
});
