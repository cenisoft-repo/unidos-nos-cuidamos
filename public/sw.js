const CACHE = "ruta-solidaria-v2";
const APP_SHELL = ["/", "/reportar", "/donar", "/seguimiento", "/transparencia", "/icon-192.png"];

/*
 * Nunca se cachea lo autenticado. El armazón sin conexión existe para que alguien pueda
 * reportar o consultar desde la calle con mala señal; la consola operativa, la pasarela y
 * la API llevan datos de personas y de dinero, y una copia suya en el disco del navegador
 * sobrevive al cierre de sesión. En un teléfono compartido —que en una emergencia es la
 * norma, no la excepción— eso es la siguiente persona leyendo lo del anterior.
 */
const PRIVADO = [/^\/operaciones/, /^\/pagos/, /^\/api/, /^\/ingresar/, /^\/registro/];
const esPrivado = (ruta) => PRIVADO.some((patron) => patron.test(ruta));

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      // Una a una y no con addAll: aquello es atómico, así que un solo recurso ausente
      // dejaba el armazón entero sin instalar y sin modo sin conexión, en silencio.
      Promise.all(APP_SHELL.map((ruta) => cache.add(ruta).catch(() => null))),
    ),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))),
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== self.location.origin) return;
  if (esPrivado(url.pathname)) return;
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(event.request, copy));
        return response;
      })
      .catch(() => caches.match(event.request).then((cached) => cached || caches.match("/"))),
  );
});

/* Cerrar sesión borra lo cacheado: la aplicación lo pide con un mensaje al trabajador. */
self.addEventListener("message", (event) => {
  if (event.data === "purgar-cache") {
    event.waitUntil(caches.keys().then((keys) => Promise.all(keys.map((key) => caches.delete(key)))));
  }
});
