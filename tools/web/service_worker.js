// Replaces Godot's exported index.service.worker.js (see tools/build_web.sh).
//
// Godot's worker serves index.html cache-first and only switches to a new
// version after every tab is closed, so phones would keep showing the
// previous build after each push. This one goes to the network first, always
// revalidates the page itself, takes over immediately, and caches only the
// offline page (no second copy of the 35 MB engine on the phone).
// It exists so the game can be installed ("Add to Home Screen" / "Install").
'use strict';
const CACHE = 'cat-rpg-offline-v1';
const OFFLINE_URL = 'index.offline.html';

self.addEventListener('install', (event) => {
	event.waitUntil(caches.open(CACHE).then((c) => c.add(OFFLINE_URL)).catch(() => {}).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
	event.waitUntil(caches.keys()
		.then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
		.then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
	const req = event.request;
	if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) {
		return;
	}
	if (req.mode === 'navigate') {
		event.respondWith(fetch(req, { cache: 'no-cache' }).catch(() => caches.match(OFFLINE_URL)));
		return;
	}
	event.respondWith(fetch(req));
});
