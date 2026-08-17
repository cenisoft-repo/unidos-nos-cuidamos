# Descripción técnica · Ruta Solidaria

**Producto:** Ruta Solidaria — plataforma de registro, verificación, asignación, transporte, entrega y auditoría de donaciones durante emergencias en Colombia.
**Versión:** 0.1.0 · **Puerta de madurez:** G1 (sandbox para demostración controlada)
**Fecha del documento:** 2026-08-16
**Alcance de la entrega:** entorno local/sandbox con datos 100 % sintéticos. No recauda dinero real, no publica datos reales y no está autorizado para producción.

---

## 1. Resumen del producto

Ruta Solidaria digitaliza la cadena de ayuda humanitaria de extremo a extremo, cuidando dos principios centrales:

- **Falla segura:** la plataforma nunca reemplaza información ausente por ceros o listas vacías. Si no puede verificar los datos contra la base, muestra un estado de "conexión interrumpida" en lugar de cifras engañosas.
- **Privacidad por diseño:** contactos, direcciones exactas, transportadores, rutas y evidencias con personas permanecen privados. El mapa público solo muestra zonas aproximadas y una conexión origen–destino, nunca una ruta GPS real.

La solución cubre cuatro recorridos: **ciudadanía**, **donante/aliado**, **operación** y **auditoría**.

---

## 2. Arquitectura

### 2.1 Stack tecnológico

| Capa | Tecnología | Versión |
|---|---|---|
| Framework web | Next.js (App Router, React Server Components, Turbopack) | 16.3.1 |
| Lenguaje / runtime | TypeScript 5.9 · Node.js ≥ 20 (probado con 22.19) | — |
| UI | React 19.2 · Lucide (íconos SVG) · CSS propio (`globals.css`) | — |
| Backend / BaaS | Supabase (PostgreSQL 17, PostgREST, Auth, Realtime, Storage) | CLI 2.114 |
| Base de datos | PostgreSQL 17 + PostGIS (geodatos) | — |
| Validación | Zod | 4.4 |
| Cartografía | MapLibre GL + OpenFreeMap, respaldo Leaflet + OpenStreetMap | — |
| Gráficas | Recharts | 3.10 |
| Exportaciones | ExcelJS (`.xlsx`) | 4.4 |
| QR | qrcode.react | 4.2 |
| Pruebas | Vitest (unitarias) · Playwright (E2E web/móvil) · pgTAP (SQL/RLS) | — |

### 2.2 Modelo de despliegue

- **Frontend Next.js** renderiza en el servidor (`force-dynamic`) y consulta Supabase mediante `@supabase/ssr`. Las páginas públicas usan la *publishable/anon key*; las operativas exigen sesión autenticada y quedan sujetas a RLS.
- **Supabase local** se levanta con Docker (Kong, PostgREST, Auth/GoTrue, Realtime, Storage, Studio, Mailpit, Analytics).
- La seguridad de datos se aplica en la base (RLS por rol y organización), no solo en la aplicación.

### 2.3 Puertos locales

> **Nota de entorno Windows.** Los puertos por defecto de Supabase (54321–54324) caen dentro del rango que Hyper-V/WinNAT reserva en algunos equipos Windows (`54290–54389`), lo que impide que Docker los publique. En este equipo se reubicaron al rango **553xx** (ver `supabase/config.toml`). En equipos sin ese bloqueo pueden usarse los puertos estándar.

| Servicio | Este equipo | Estándar Supabase |
|---|---|---|
| Aplicación (Next.js) | http://localhost:3000 | 3000 |
| API Supabase (Kong/REST) | http://127.0.0.1:55321 | 54321 |
| Base de datos PostgreSQL | 127.0.0.1:55322 | 54322 |
| Supabase Studio | http://127.0.0.1:55323 | 54323 |
| Mailpit (correo de prueba) | http://127.0.0.1:55324 | 54324 |

---

## 3. Base de datos

- **14 migraciones** reconstruyen el esquema completo (`supabase/migrations/`). La base se reconstruye con `npm run db:reset` y se siembra con datos sintéticos (`supabase/seed.sql`).
- **Seguridad a nivel de fila (RLS):** cada rol y organización solo accede a lo que le corresponde. Las vistas y RPC públicas (`public_event_dashboard`, `public_need_projections`, `public_need_map`, `public_collection_centers`, `public_logistics_map`) exponen únicamente proyecciones seguras sin PII.
- **Libros críticos append-only:** los eventos de auditoría y financieros agregan historia; no se sobrescriben. Las correcciones se registran como nuevos eventos.
- **Geodatos:** PostGIS almacena ubicaciones; hacia el público solo se emiten coordenadas aproximadas.

### 3.1 Dominios de datos principales

- **Necesidades** (`need_cases`, proyecciones públicas): categoría, ubicación aproximada, faltante, cobertura, estado, prioridad.
- **Aportes** (`donation_intakes`, `donation_intake_items`): en especie o económicos, con código de seguimiento, atribución pública e idempotencia.
- **Inventario y logística** (`inventory_lots`): recepción parcial, lotes, reserva, despacho, tránsito, entrega y validación.
- **Tesorería** (`financial_transactions`, `expense_requests`): fondo conciliado, solicitudes, aprobación segregada y pago (adaptador sandbox, sin dinero real).
- **Auditoría** (`audit_events`) y **métricas verificadas** con fórmula reproducible.

---

## 4. Módulos funcionales

| Módulo | Ruta | Acceso |
|---|---|---|
| Inicio público (catálogo "Hoy hace falta", mapa territorial, centros de acopio, impacto) | `/` | Público |
| Necesidades / donar a una necesidad | `/` · `/donar` | Público |
| Registro de aporte adaptativo (4 pasos en especie, 3 en dinero) + ticket QR | `/donar` | Público |
| Seguimiento por código seguro | `/seguimiento` | Público |
| Reporte ciudadano privado (con honeypot y cuota antiabuso) | `/reportar` | Público |
| Transparencia / impacto conciliado + exportación Excel | `/transparencia` | Público |
| Ingreso por rol | `/ingresar` | Público |
| Centro operativo (lanzador por rol, KPI, cola de verificación) | `/operaciones` | Autenticado |
| Bodega y logística (recepción, lotes, compatibilidad, cola offline) | `/operaciones/bodega` | Bodega/Logística/Admin |
| Tesorería sandbox (conciliación, solicitud, aprobación segregada, pago) | `/operaciones/tesoreria` | Tesorería/Admin/Auditoría |
| Exportaciones `.xlsx` (libro público y operacional) | `/api/exports/*.xlsx` | Público / según sesión |
| Salud del servicio (request ID, duración, estado de base) | `/api/health` | Interno |

### 4.1 Roles del sistema

`event_admin` (administración de evento) · `verifier` (verificación) · `partner_reporter` (aliado reportante) · `warehouse_operator` (centro de acopio) · `logistics_operator` (logística) · `treasury_requester` (solicitudes de tesorería) · `treasury_approver` (aprobación financiera) · `auditor` (auditoría).

El lanzador del centro operativo **solo muestra los recorridos permitidos por el rol** de la persona autenticada.

---

## 5. Seguridad y privacidad

- **Autenticación:** Supabase Auth con auto-registro bloqueado. Contraseñas de 12+ caracteres (mayúsculas, minúsculas, dígito y símbolo), reautenticación para cambio de contraseña, sesiones limitadas a 12 h y 2 h de inactividad.
- **Antiabuso ciudadano:** honeypot y cuota de 5 reportes exitosos por origen/evento cada 10 minutos, mediante hash SHA-256 sin conservar la IP en claro.
- **Moderación:** teléfonos y cuentas del reporte ciudadano pasan por moderación.
- **Datos públicos sin PII:** los libros Excel públicos excluyen PII; los operacionales omiten contactos y observaciones internas aun cuando el rol pueda verlos en la app.
- **Telemetría estructurada** en exportaciones y salud, sin PII.
- **Identidad neutral:** logos, slogans y franjas institucionales solo se incorporan tras autorización de marca.

---

## 6. Calidad y verificación

El comando `npm run verify` ejecuta el recorrido completo (también versionado en `.github/workflows/verify.yml`):

`preflight local → lint → TypeScript → unitarias (Vitest) → pgTAP → RLS → concurrencia → build → Playwright web/móvil`

Estado comprobado en la última corrida (ver `docs/STATUS.md`):

- 94 pruebas SQL/RLS/concurrencia, 13 unitarias, 24 Playwright, lint, TypeScript y build en verde.
- Recuperación local ejecutada: snapshot, manifiesto con checksums, reconstrucción, restauración y 94 pgTAP. **RTO observado: 57,1 s.**
- No se ejecutó ninguna mutación remota.

---

## 7. Operación local

| Acción | Comando |
|---|---|
| Instalar dependencias | `npm install` |
| Levantar base Supabase | `npm run db:start` |
| Reconstruir + sembrar base | `npm run db:reset` |
| Arrancar aplicación | `npm run dev` |
| Estado de Supabase | `npm run db:status` |
| Respaldo local | `npm run db:backup` |
| Verificación completa | `npm run verify` |
| Detener base | `npm run db:stop` |

Requisitos: Node.js 20+, Docker Desktop activo, npm. La configuración de entorno se toma de `.env.local` (base en `.env.example`).

---

## 8. Límites de la entrega (G1) y bloqueos para producción

Esta versión **no** está autorizada para producción. Para avanzar a G2/G3 se requiere (ver `docs/PILOT_APPROVAL_PACKET.md` y `docs/STATUS.md`):

- Operador jurídico, autoridades/organizaciones participantes, DPIA y políticas de datos aprobadas.
- Proveedor financiero real (hoy se usa un adaptador sandbox).
- WAF y monitoreo externo, backups remotos / PITR, protección contra contraseñas filtradas.
- Autorización de marca e identidad institucional.
- Componente de **evidencias privadas** (antes/en tránsito/entrega) con consentimiento y política aprobados — actualmente pendiente de rediseño.

No existe enlace vigente a Supabase remoto ni a Vercel. El `preflight:deploy` verifica, **no despliega ni publica**.

---

## 9. Referencias

- `README.md` — inicio rápido y módulos.
- `docs/STATUS.md` — estado comprobado y bloqueos.
- `docs/UX_MAP.md` — recorridos y mapa de pantallas.
- `docs/OPERATIONAL_READINESS.md` — recuperación y límites.
- `docs/THREAT_MODEL.md` · `docs/TRACEABILITY_MATRIX.md` · `docs/TEST_STRATEGY.md` — seguridad, trazabilidad y pruebas.
- `docs/MANUAL_USUARIO.md` — manual de usuario (este paquete de entrega).
