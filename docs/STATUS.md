# Estado comprobado

Fecha: 2026-08-15 · Puerta: G1 sandbox para demostración controlada.

Supabase y Next.js locales están activos con datos 100 % sintéticos. La base se reconstruye con 14 migraciones. Pasan 94 pruebas SQL, RLS, concurrencia real, 13 unitarias, 24 Playwright, lint, TypeScript y build. La salud HTTP entrega request ID, duración y estado de base; las exportaciones registran telemetría estructurada sin PII.

La entrada ciudadana conserva moderación y honeypot, y ahora limita cinco reportes exitosos por origen/evento cada diez minutos mediante un hash SHA-256 sin IP en claro. Auth bloquea el auto-registro, exige 12 caracteres con mayúsculas, minúsculas, dígitos y símbolo, requiere reautenticación para cambiar contraseña y limita sesiones a 12 h/2 h de inactividad.

La recuperación local fue ejecutada: snapshot de esquema/datos, manifiesto con checksums, reconstrucción desde migraciones, restauración y 94 pgTAP. RTO observado: 57,1 segundos. El procedimiento y sus límites están en `docs/OPERATIONAL_READINESS.md`.

La bodega ofrece búsqueda, etapas, compatibilidad categoría/unidad y cola offline con validación estricta, TTL 72 h, máximo 50 y cero PII. CI y runbooks de incidente, datos, WAF y aprobación están versionados; no se ejecutó ninguna mutación remota.

Local: aplicación `http://127.0.0.1:3000`, Studio `http://127.0.0.1:54323`, Mailpit `http://127.0.0.1:54324`.

Bloqueos: G2/G3 requieren operador jurídico, autoridades/organizaciones, DPIA y políticas aprobadas, proveedor financiero, WAF/monitoreo externo, backups remotos/PITR, protección de contraseñas filtradas, marcas y autorización explícita. No existe enlace vigente a Supabase remoto ni Vercel.

Siguiente: completar y firmar `docs/PILOT_APPROVAL_PACKET.md`; solo después enlazar entornos, ejecutar `npm run preflight:deploy` y cerrar bloqueos comprobados. El preflight no despliega ni publica.
