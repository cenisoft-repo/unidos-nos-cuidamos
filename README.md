# Ruta Solidaria

Plataforma local/sandbox para registrar, verificar, asignar, transportar, entregar y auditar donaciones durante emergencias en Colombia.

## Inicio rápido

Requisitos: Node.js 20+, Docker Desktop activo y npm.

```bash
npm install
npm run db:start
npm run db:reset
npm run dev
```

- Aplicación: http://localhost:3000
- Supabase Studio: http://127.0.0.1:54323
- Mailpit: http://127.0.0.1:54324

Después de `db:start`, copia la URL y la publishable/anon key mostradas por `npm run db:status -o env` a `.env.local` usando `.env.example` como base. Los pasos completos y usuarios sandbox quedan en `docs/LOCAL_DEVELOPMENT.md`.

## Módulos implementados

- Inicio público humano con catálogo visual de necesidades, centros de acopio seguros y acceso universal al seguimiento.
- Centro territorial con MapLibre, respaldo visual sin WebGL, cartografía local, filtros, PostGIS y Supabase Realtime.
- Reporte ciudadano privado con categorías visuales, moderación de teléfonos/cuentas y código seguro.
- Defensa antiabuso local con honeypot y cuota PostgreSQL de cinco reportes por origen/10 minutos, sin conservar la IP en claro.
- Aporte guiado en cinco pasos, centro preferido, idempotencia y ticket imprimible con QR.
- Centro de mando con lanzador de tareas para verificar, recibir, consultar y conciliar según el rol.
- Bodega/logística: recepción parcial, lotes, cola offline mínima, reserva, despacho, entrega y validación.
- Bodega guiada: búsqueda por código/categoría, etapas visibles y compatibilidad automática de categoría/unidad.
- Tesorería sandbox: fondo verificado, conciliación idempotente, solicitud, aprobación segregada, pago y saldo.
- Transparencia derivada de proyecciones seguras; auditoría y libros críticos append-only.

## Cuentas locales

Contraseña común: `RutaSolidaria2026!`

- `admin@rutasolidaria.local`
- `aliado@rutasolidaria.local`
- `bodega@rutasolidaria.local`
- `solicita@rutasolidaria.local`
- `aprueba@rutasolidaria.local`

## Verificación

```bash
npm run verify
npm run db:backup
```

`npm run verify` cubre preflight local, lint, TypeScript, unitarias, pgTAP, RLS, concurrencia, build y Playwright web/móvil. El mismo recorrido está versionado en `.github/workflows/verify.yml`. La restauración destructiva está limitada a la base sintética y se documenta en `docs/OPERATIONAL_READINESS.md`.

El estado comprobado y los límites de madurez están en `docs/STATUS.md`.

## Alcance

Esta versión no recauda dinero real, no publica datos reales ni está autorizada para producción. Los aportes económicos usan un adaptador sandbox y los registros de muestra son ficticios.
