# Instrucciones del repositorio

## Fuente y límites

- `docs/LOOP_MAESTRO_DESARROLLO_PLATAFORMA_DONACIONES_EMERGENCIA.md` es la constitución funcional.
- El entorno actual es exclusivamente local/sandbox. No desplegar, recaudar, enviar mensajes, migrar datos vivos ni usar marcas institucionales sin autorización explícita.
- Todo dato de desarrollo es sintético. Nunca incorporar PII o evidencia del sistema vivo.
- Preservar historial: las acciones críticas crean eventos append-only y las correcciones compensan; no borran.

## Comandos

- Instalar: `npm install`
- Backend local: `npm run db:start`
- Reiniciar esquema/fixtures: `npm run db:reset`
- Aplicación: `npm run dev`
- Validación: `npm run verify`
- E2E: `npm run test:e2e`

## Convenciones

- TypeScript estricto, App Router y componentes de servidor por defecto.
- Mutaciones sensibles mediante funciones PostgreSQL transaccionales; RLS en todas las tablas expuestas.
- No usar `service_role` en cliente ni basar autorización en `user_metadata`.
- Superficies públicas consumen vistas/RPC seguras, nunca tablas operacionales.
- Una escritura crítica requiere actor, tenant/evento, validación de estado, idempotencia y auditoría correlacionada.

## Definición local de terminado

- Criterios del recorrido satisfechos y pruebas focales verdes.
- `lint`, `typecheck`, pruebas y build pasan.
- Persistencia, permisos, privacidad, idempotencia y auditoría verificados.
- `docs/ai/STATE.md` y trazabilidad reflejan el resultado real.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
