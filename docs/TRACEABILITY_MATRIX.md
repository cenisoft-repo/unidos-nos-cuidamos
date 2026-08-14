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
| Aporte guiado y comprobable | Flujo de cinco pasos, centro preferido, contexto declarado y privado, organización derivada de membresía, valor estimado no conciliado y ticket QR `APO-*` sin PII | SQL transaccional de contexto/idempotencia/privacidad + E2E completo web/móvil | Probado en sandbox |
| Excel público seguro | Ruta dinámica con hojas de resumen, necesidades, aportes publicados, centros y metodología; tipos nativos, fórmulas reproducibles y neutralización de fórmulas inyectadas | Unitarias Excel + descarga y apertura real en E2E | Probado en sandbox |
| Excel operativo autorizado | Ruta autenticada; consultas sujetas a RLS; excluye nombre, correo, teléfono, observaciones y contactos internos | 401 anónimo + descarga autenticada y apertura de seis hojas | Probado en sandbox |
| Dashboard sin métricas engañosas | Barras de cobertura por necesidad, distribución por estado, filtros por categoría y tabla equivalente; no mezcla litros, kits y unidades | E2E web/móvil + inspección visual en navegador integrado | Probado en sandbox |
| Marcas institucionales controladas | Identidad neutral en sandbox; logos y franjas territoriales requieren autorización expresa de publicación | Nota visible y revisión de límites | Bloqueado fuera del sandbox |
| Entrada ciudadana comprensible | Categorías visuales con controles radio semánticos; se preservan moderación, campos privados y confirmación de buena fe | 4 E2E web/móvil | Probado en sandbox |
| Centro operativo orientado a tareas | Lanzador condicionado por membresía para verificar, recibir, consultar y conciliar | Auth/RLS + E2E de roles | Probado en sandbox |
| Actualización territorial en vivo | `public_need_projections` y `public_logistics_projections` en `supabase_realtime`; centros y despachos se refrescan mediante RPC sujetas a RLS | SQL de publicación/proyección + RLS + conexión E2E | Probado en sandbox |
| Despachos georreferenciados sin GPS público | Trigger deriva origen del centro y destino de la necesidad publicada; expone código, estado y coordenadas aproximadas, nunca custodia/transportador/ruta exacta | E2E SQL de creación de despacho + fixture visual | Probado en sandbox |
| Seguimiento comprensible sin rastrear personas | línea de hitos derivada de `track_public_code`, sin ubicación ni evidencia privada | E2E web y móvil + RLS | Probado en sandbox |
| Accesibilidad y responsive | filtros con `aria-pressed`, gráficos con nombre accesible, tabla equivalente, radios semánticos, navegación por teclado, stepper, línea de hitos y control de desbordamiento | 18 pruebas Playwright en Chromium y móvil | Probado básico |
