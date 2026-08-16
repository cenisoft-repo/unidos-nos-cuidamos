# Matriz de trazabilidad inicial

| Requisito | Diseño/implementación | Prueba | Estado |
|---|---|---|---|
| Ingreso no se publica automáticamente | `donation_intakes` separado de `public_donation_projections` | E2E H | Probado |
| Necesidad basada en hechos | RPC sin urgencia/rescate predeterminados | E2E C + Playwright | Probado |
| Inventario exactamente una vez | RPC idempotente + `stock_movements` | E2E A/D/G | Probado |
| Dinero conciliado y segregado | libro append-only + aprobación por actor distinto | E2E B + UI | Probado |
| Evidencia/ubicación privada | Storage privado, RLS y vistas explícitas | RLS + E2E C/H | Probado en sandbox |
| Lote restringido no sale | hold/recall validado en asignación | E2E F | Probado |
| Migración no verifica | staging en cuarentena + rollback por lote | E2E E | Probado con fixture |
| Mapa público con precisión protegida | MapLibre + cartografía vectorial real OpenFreeMap/OSM + RPC `public_need_map` + PostGIS; solo usa coordenadas aproximadas y conserva lista accesible | SQL/RLS + E2E web/móvil + inspección visual | Probado en sandbox |
| Mapa real sin WebGL | Fallback Leaflet con teselas OpenStreetMap, necesidades, centros y líneas origen-destino; conserva filtros y detalle semántico | Inspección visual en navegador integrado sin WebGL + E2E | Probado en sandbox |
| Centros de acopio sin exponer direcciones | RPC `public_collection_centers`, columnas públicas aproximadas y tarjetas/mapa; dirección exacta queda fuera de la proyección | SQL/RLS + E2E web/móvil | Probado en sandbox |
| Aporte guiado y comprobable | Flujo de cinco pasos, centro preferido, contexto privado, organización derivada, donante/responsable separados, estado declarado y ticket QR `APO-*` sin PII | SQL transaccional + E2E web/móvil | Probado para especie y dinero |
| Excel público seguro | Ruta dinámica con hojas de resumen, necesidades, aportes publicados, centros y metodología; tipos nativos, fórmulas reproducibles y neutralización de fórmulas inyectadas | Unitarias Excel + descarga y apertura real en E2E | Probado en sandbox |
| Excel operativo autorizado | Ruta autenticada; consultas sujetas a RLS; excluye nombre, correo, teléfono, observaciones y contactos internos | 401 anónimo + descarga autenticada y apertura de seis hojas | Probado en sandbox |
| Dashboard sin métricas engañosas | Cobertura por necesidad y dashboard de aportes; cuenta proyecciones por categoría, conserva cantidades con su unidad y separa COP conciliados | SQL + E2E web/móvil + Excel | Probado en sandbox |
| Marcas institucionales controladas | Identidad neutral en sandbox; logos y franjas territoriales requieren autorización expresa de publicación | Nota visible y revisión de límites | Bloqueado fuera del sandbox |
| Entrada ciudadana comprensible | Categorías visuales con controles radio semánticos; se preservan moderación, campos privados y confirmación de buena fe | 4 E2E web/móvil | Probado en sandbox |
| Centro operativo orientado a tareas | Lanzador condicionado por membresía para verificar, recibir, consultar y conciliar | Auth/RLS + E2E de roles | Probado en sandbox |
| Actualización territorial en vivo | `public_need_projections` y `public_logistics_projections` en `supabase_realtime`; centros y despachos se refrescan mediante RPC sujetas a RLS | SQL de publicación/proyección + RLS + conexión E2E | Probado en sandbox |
| Despachos georreferenciados sin GPS público | Trigger deriva origen del centro y destino de la necesidad publicada; expone código, estado y coordenadas aproximadas, nunca custodia/transportador/ruta exacta | E2E SQL de creación de despacho + fixture visual | Probado en sandbox |
| Seguimiento comprensible sin rastrear personas | línea de hitos derivada de `track_public_code`, sin ubicación ni evidencia privada | E2E web y móvil + RLS | Probado en sandbox |
| Accesibilidad y responsive | filtros con `aria-pressed`, gráficos con nombre accesible, tablas equivalentes, campos requeridos, errores vivos, stepper y control de desbordamiento | 24 pruebas Playwright en Chromium y móvil | Probado básico |
| Validación autoritativa del aporte | La última RPC ejecutable replica el contrato obligatorio, catálogo y coherencia por tipo | Pruebas negativas directas + 94 pgTAP | Probado · G-009 cerrada |
| Idempotencia concurrente | Inserción `ON CONFLICT`, recuperación de resultado y huella SHA-256 del payload | Dos conexiones simultáneas + prueba de payload distinto | Probado · G-010 cerrada |
| Aporte monetario conciliado | Intake aprobado → cola segura → fondo verificado → transacción/recibo → proyección pública | pgTAP + Playwright web/móvil | Probado · G-011 cerrada |
| Proyección por artículo | Cada artículo en especie conserva categoría, unidad y cantidad verificadas sin agregación cruzada | Restricción única `donation_item_id` + recorrido de entrega | Probado · G-012 cerrada |
| Clasificación público/privado completa | Confirmación divide campos publicables tras verificación y campos privados; superficies públicas usan allowlist | UI web/móvil + RLS + Excel | Probado G1 · G-014 cerrada |
| Entrada ciudadana antiabuso local | Honeypot + cuota transaccional 5/10 min por hash de origen/evento; firma anterior revocada y contadores sin privilegios públicos | pgTAP de cuota, privacidad y privilegios + E2E | Probado local; WAF remoto pendiente |
| Observabilidad mínima sin PII | logs JSON por operación, hook de errores servidor, request ID, Server-Timing y salud no cacheable | E2E de `/api/health` y cabeceras | Probado local |
| Recuperación sintética | snapshot de esquema/datos, manifiesto SHA-256, reset, truncado controlado, restore y pgTAP | restauración real en 57,1 s + 94 pruebas | Probado local |
| Cola offline mínima segura | Solo UUID/cantidades/condición; esquema estricto, TTL 72 h, máximo 50, deduplicación e idempotencia | 4 unitarias con cargas alteradas, vencidas y exceso | Probado local; política de dispositivo bloquea G2 |
| Operación de bodega amigable | Etapas, búsqueda, campos etiquetados, tarjetas de lote y filtro categoría/unidad | 2 Playwright web/móvil + contratos PostgreSQL | Probado local |
| Integración continua | GitHub Actions levanta Supabase local, crea env mínima, ejecuta `npm run verify` y conserva Playwright si falla | Sintaxis versionada + suite local equivalente | Preparado; ejecución remota requiere push autorizado |
| Gobierno y respuesta | Runbooks de incidentes, datos, WAF y paquete de aprobación enlazan bloqueos con responsable/evidencia | revisión documental + preflight bloqueado | Preparado; aprobación humana pendiente |
