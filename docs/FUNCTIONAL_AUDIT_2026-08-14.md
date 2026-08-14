# Auditoría funcional final · ciclo 2026-08-14

Alcance: sandbox sintético local y Supabase remoto `qfwjwtykajjeynokvqjr`. Esta auditoría no autoriza datos reales, recaudo, marcas institucionales ni producción.

## Veredicto

- Resultado: **G1 sandbox apta para demostración controlada**.
- Regresiones P0/P1 abiertas: **0**.
- Recorridos verificados: portal, mapa, centros, reporte ciudadano, aporte autenticado, seguimiento, centro operativo, bodega, tesorería, dashboards y Excel público/operativo.
- G2/G3: **no autorizadas**; siguen sujetas a operador, DPIA, políticas, observabilidad, recuperación y proveedores reales.

## Evidencia reproducible

| Límite | Evidencia | Resultado |
|---|---|---|
| Aplicación local | `GET /api/health` | 200; base conectada |
| Esquema desde cero | `npm run db:reset` | 12 migraciones + seed sintético |
| Contratos PostgreSQL | `npm run db:test` | 68/68 pgTAP |
| RLS/IDOR/privilegios | `npm run test:rls` | aislamiento de tenant, mapa y mutaciones sensibles bloqueadas |
| Unidad | `npm run test` | 9/9 |
| Navegador | `npm run test:e2e` | 18/18, Chromium y móvil |
| Calidad | `npm run verify` | lint, TypeScript, unidad, RLS y build verdes |
| Dependencias | `npm audit --omit=dev` | 0 vulnerabilidades |
| QA visual | navegador real | 5 rutas móviles sin overflow; consola sin errores |
| Cartografía | DOM y teselas | MapLibre cuando está disponible; fallback Leaflet con teselas OpenStreetMap 256×256 reales |
| Supabase remoto | SQL de auditoría | 0 tablas públicas sin RLS; 0 FK sin índice; 12 migraciones |

## Hallazgos corregidos en loop

| ID | Sev. | Hallazgo | Corrección | Prueba de cierre |
|---|---:|---|---|---|
| F-001 | P1 | Los Excel podían reemplazar una falla de Supabase por un libro vacío aparentemente válido. | Respuesta fail-closed 503, `no-store`, `Retry-After` y mensaje sin detalle interno. | Unidad + E2E de ambos exportadores |
| F-002 | P1 | Portada, transparencia y módulos operativos podían presentar listas vacías o ceros ante consultas parciales. | Validador común de resultados y límite de error amigable con reintento. | lint, typecheck, unidad y recorridos E2E |
| F-003 | P2 | 97 columnas FK no tenían índice de soporte. | Migración `202608140009_foreign_key_indexes.sql` con nombres deterministas. | pgTAP y SQL remoto: 0 pendientes |
| F-004 | P2 | El test exigía MapLibre aunque el fallback cartográfico real estuviera sano; el texto atribuía toda caída a WebGL. | Contrato E2E acepta MapLibre o Leaflet y el aviso contempla estilo vectorial/WebGL. | 18/18 E2E |

## Seguridad y privacidad

- Todas las tablas operacionales expuestas tienen RLS; las tablas deliberadamente sin políticas niegan acceso por defecto.
- 32 funciones `SECURITY DEFINER` auditadas: ninguna conserva `EXECUTE` para `PUBLIC`; todas fijan `search_path`.
- RPC anónimos deliberados: `public_collection_centers`, `submit_need_report` y `track_public_code`.
- Registro de aportes privados: solo `authenticated`; `anon` no puede ejecutarlo.
- Contactos, direcciones exactas, observaciones internas y evidencias privadas no aparecen en vistas ni Excel públicos.
- Los avisos del linter sobre `SECURITY DEFINER` son esperados para RPC explícitos y funciones autenticadas con control de rol; no equivalen por sí solos a una vulnerabilidad.

## Brechas externas abiertas

1. **G-007 · P2:** Supabase Auth informa `auth_leaked_password_protection` desactivado. Cierre: habilitar protección de contraseñas filtradas en el proyecto y repetir el asesor de seguridad. Referencia: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
2. **G-008 · P2:** el preview de Vercel exige SSO y el conector no lista el proyecto/despliegue, por lo que falta una verificación remota navegador → función → Supabase. Cierre: enlazar el proyecto a la cuenta/equipo accesible, configurar variables persistentes y ejecutar el recorrido remoto.
3. Los P2 G-001 a G-006 de `docs/GAP_LEDGER.md` continúan bloqueando piloto y producción.

## Cambios de plataforma revisados

- El cambio de gateway Kong → Envoy afecta self-hosting; el proyecto local usa Supabase CLI y no personaliza `kong.yml`.
- La deprecación del pin de versiones de extensiones no afecta las migraciones actuales: no especifican una versión de extensión.
- El requisito futuro de TypeScript 5+ para `supabase-js` está cubierto: el proyecto usa TypeScript 5.9.3.

## Próximo gate

No ampliar a G2 hasta cerrar G-001 a G-008 y ejecutar restauración, observabilidad, rate limiting/CAPTCHA del reporte anónimo y una prueba remota completa sobre un preview accesible.
