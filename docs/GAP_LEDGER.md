# Libro de brechas

| ID | Sev. | Brecha | Responsable/decisión | Prueba de cierre |
|---|---|---|---|---|
| G-001 | P2 | No hay snapshot autorizado del legado | Operador futuro; no copiar datos | Ensayo con fixture anonimizado y checksum |
| G-002 | P2 | Operador/RACI nominal no definido | Dueño humano; roles genéricos en sandbox | Acta y usuarios reales antes de G2 |
| G-003 | P2 | Política de aceptación no validada por autoridad | Política sintética conservadora | Aprobación humanitaria antes de G2 |
| G-004 | P2 | Proveedor financiero no definido | Adaptador sandbox; cero tarjeta/cuenta | Contrato + conciliación en staging |
| G-005 | P2 | DPIA/base legal pendiente | Minimización y retención provisional | Validación jurídica antes de G2 |
| G-006 | P2 | Marca y fuentes oficiales no autorizadas | Marca neutra y evento “simulado” | Aprobación de identidad/fuentes |
| G-007 | P2 | Protección de contraseñas filtradas desactivada en Supabase Auth | Administración del proyecto remoto | Habilitar el control y repetir asesor de seguridad |
| G-008 | P2 | Preview Vercel protegido y no visible para el conector | Enlazar proyecto/equipo y persistir variables | Recorrido remoto navegador → función → Supabase |
| G-009 | Cerrada | La RPC de aporte no replicaba todas las validaciones del navegador | Contrato autoritativo PostgreSQL implementado | pgTAP rechaza nombre inválido y valida catálogos/contacto/contexto |
| G-010 | Cerrada | Dos reintentos simultáneos producían una violación de unicidad | Inserción atómica + huella SHA-256 | `npm run test:concurrency` devuelve un intake y un reintento sin error |
| G-011 | Cerrada | El aporte económico aprobado quedaba sin conciliación ni proyección pública | Flujo tesorería/intake implementado | SQL + Playwright enlazan intake, transacción y cifra pública exactamente una vez |
| G-012 | Cerrada | La proyección única por donación podía sumar unidades incompatibles | Proyección por artículo + restricción monetaria parcial | SQL conserva filas por `donation_item_id`; dashboard no agrega unidades |
| G-013 | Cerrada G1 | Donante real, persona reportante y estado declarado estaban mezclados | Producto + datos alineados | UI distingue donante, responsable, organización y estado declarado |
| G-014 | Cerrada G1 | Faltaba matriz visible de campos públicos y privados | UX + privacidad alineadas | Revisión visible + allowlists RLS/RPC/HTML/Excel verificadas |
| G-015 | P2 | La app ya limita 5 reportes/10 min por hash de origen y honeypot; falta WAF/rate limiting de borde | Seguridad de borde | Prueba de abuso y control remoto configurado antes de piloto |
| G-016 | Cerrada | Existían cinco conjuntos de políticas RLS permisivas duplicadas | Políticas consolidadas | Advisors sin hallazgos y pruebas RLS conservan el acceso |
| G-017 | P2 | El repositorio no conserva enlaces verificables a Supabase remoto ni Vercel | Administración de entornos | Auditoría remota read-only reproducible sin exponer secretos ni datos reales |
| G-018 | Cerrada G1 | Recuperación local no estaba ejecutada | Snapshot + restore con checksums | Restauración real en 57,1 s y 94 pgTAP verdes |
| G-019 | Cerrada G1 | Faltaban CI y runbooks operativos de incidente/aprobación/WAF/datos | Artefactos locales versionados | Workflow + paquete G2 + runbooks inspeccionados y suite verde |
| G-020 | Cerrada G1 | Cola offline aceptaba JSON alterado y bodega tenía controles densos | Endurecimiento local/UX | 4 unitarias de cola + 2 E2E web/móvil de bodega |
| G-021 | P0 | `partner_reporter` puede consultar ubicación exacta y contacto privado de necesidades por la política amplia de miembros del evento | Seguridad de datos/RLS | IDOR por rol rechaza columnas privadas; verificadores consumen una RPC mínima autorizada |
| G-022 | Cerrada local · P0 remoto | UI y RPC aceptaban un centro de otra organización, pero recepción exigía el mismo tenant y dejaba el aporte sin ruta | Modelo exclusivo por organización: selección autenticada filtrada, validación transaccional y administración auditada | 152 SQL + Playwright web/móvil prueban usuario-organización-punto; falta aplicar `202608160003` y repetir la simulación remota antes de cerrar globalmente |
| G-023 | P1 | El QR `APO-*` no avanza al estado de la donación/entrega `DON-*` vinculada | Producto + seguimiento | El mismo QR muestra el estado operacional seguro después de recepción/conciliación/entrega |
| G-024 | P1 | El reporte ciudadano no produce coordenadas aproximadas autorizadas y los despachos reales no se publican en el mapa | Territorio + privacidad | Selección/geocodificación moderada, precisión aprobada y despacho visible sin dirección exacta |
| G-025 | P1 | Auditoría de varias tablas hijas queda sin evento/organización derivados del padre | Seguridad/auditoría | Todos los eventos críticos conservan contexto de tenant y la política no abre registros huérfanos |
| G-026 | P2 | Cada fila auditada genera una correlación distinta aun dentro de la misma RPC | Observabilidad | Un correlation ID enlaza todos los cambios y movimientos de cada transacción crítica |
| G-027 | P2 | Las operaciones no generan un nuevo corte de métricas conciliadas | Analítica/operación | Job o acción de cierre crea snapshot reproducible y la UI declara el corte vigente |
