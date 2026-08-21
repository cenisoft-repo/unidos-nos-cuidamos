# Calidad visual y de experiencia

Memoria de la pista UX/visual del sistema operativo Opus 5. Se actualiza **solo
la fila que cambió** en cada ciclo; no se reescribe la tabla.

Escala: 0 sin diseño · 1 wireframe funcional · 2 visual básico coherente ·
3 pulido con estados completos · 4 nivel producto (microinteracción, motion, AA+, mobile impecable)

## Regla de evidencia para asignar nivel

El antipatrón declarado es «declarar nivel 3-4 sin haber corrido
`audit:a11y`/`audit:visual`». Por eso el nivel sembrado depende de qué cubre
realmente la herramienta:

Desde el 2026-08-17, `scripts/accessibility-audit.mjs` y
`scripts/visual-metrics.mjs` recorren las rutas declaradas en
`scripts/lib/rutas-auditadas.mjs`, cada consola con el rol que la usa
—`/operaciones` dos veces, porque coordinación y aliado ven pantallas
distintas—. Al 2026-08-20 son **catorce superficies**: siete públicas y siete
autenticadas. El número no se fija aquí a mano: sale de `cobertura` en el
informe, que es lo que se transcribe.

Tres reglas del instrumento, para que la evidencia signifique algo:

- **Solo contra loopback.** La contraseña sembrada no se prueba contra ningún
  otro host; con `AUDIT_SKIP_AUTH=1` se recorren solo las públicas y el informe
  declara la omisión en `cobertura.autenticadasOmitidas`.
- **Lo que no se puede calcular no se cuenta como fallo ni como aprobado.** El
  contraste sobre una fotografía o un degradado de pseudo-elemento no es
  computable desde el DOM; esos casos salen en `contrasteIndeterminado` y hay
  que medirlos a mano. Antes se contaban como fallo y `audit:a11y` no podía
  estar verde nunca, así que no servía de puerta y se ignoraba.
- **El movimiento se comprueba pidiendo que no lo haya.** Desde el 2026-08-20 hay
  una segunda pasada con `prefers-reduced-motion: reduce` que mira lo que calcula
  el motor, no lo que el CSS pretende, y suma a `totalProblemas` cualquier
  transición o animación que sobreviva. Se validó rompiéndola a propósito.

Estado del instrumento al 2026-08-20, ya con la identidad institucional:
**`audit:a11y` sale en 0** sobre las catorce superficies, con 3 indeterminados
—los tres rótulos sobre la fotografía del portal—. Medidos a mano componiendo el
velo `rgba(13,35,67,.86)` sobre el peor fondo posible (una zona blanca de la
foto): el compuesto queda en `#2f425d`, con **10,2:1** para el texto blanco y
**7,87:1** para el secundario. Mejoran los 5,54 · 5,99 · 6,10 del velo verde
anterior, porque el azul oscuro de marca es más profundo que el verde que
sustituye. `audit:visual` toma 70 mediciones —14 superficies × 5 anchos— sin un
solo desborde horizontal.

## Tabla de superficies

| # | Superficie | Ruta | Nivel | Brecha principal | Prueba de cierre |
|---|---|---|---:|---|---|
| S-01 | Evidencias | (sin UI) | **0** | Bucket privado sin superficie. Sin componente de captura por etapa, sin permisos visibles por rol, sin estados | `audit:a11y` + `audit:visual` + pgTAP de permisos por rol + E2E de las tres etapas |
| S-02 | Centro operativo | `/operaciones` | **3** | Auditada con sesión en los dos roles que la usan: contraste en 0, sin desborde de 1440 a 390 px. **2026-08-20 (`G-052`):** la consola abre con «¿Qué necesitas hacer?» y las tres acciones del recorrido —Solicitar, Recibir, Despachar— como nivel dominante, con la cifra real de lo que espera cada una y apiladas a ancho completo en móvil. Falta el recorrido cronometrado con operadores reales, que es validación humana | Prueba de uso con coordinación y con un aliado antes de G2 |
| S-03 | Bodega y logística | `/operaciones/bodega` | **3** | Auditada con sesión de bodega. Aquí apareció DQ-04: el contraste del lote seleccionado. Corregido y verificado. **2026-08-20:** la etapa 03 pasa de «Trasladar» a «Solicitar» y admite varios productos por solicitud, con el modo por producto —una cantidad, un lote completo o todo lo disponible— y la autorización línea por línea; la recepción se declara producto a producto y el faltante se deduce en vez de escribirse. Reauditada: contraste en 0 y sin desborde de 1440 a 390 px | Prueba de uso con bodega antes de G2, ahora también sobre una solicitud de varios productos |
| S-04 | Tesorería | `/operaciones/tesoreria` | **3** | Auditada con sesión de aprobación: contraste en 0, sin desborde. El vocabulario financiero sigue sin validar con tesorería | Revisión con tesorería antes de G2 |
| S-05 | Administración de puntos | `/operaciones/centros` | **2** | Auditada con sesión: contraste en 0, pero **DQ-06 abierto** — 14,9 pantallas de móvil contra 1,8 de escritorio, y creciendo con cada punto. No sube de 2 mientras la consola sea inusable en un teléfono | Acotar la lista y volver a medir la razón móvil/escritorio |
| S-06 | Reporte ciudadano | `/reportar` | **2** | `UX_MAP` lo marca «Implementado parcial»: falta el recorrido multipaso | `audit:a11y` + prueba de uso antes de convertirlo en multipaso |
| S-07 | Home pública | `/` | **3** | **2026-08-20:** adopta la identidad institucional —banda azul oscuro, mosaico de marca, botón de acción azul— y la marca real sustituye al cuadrado con puntos que la imitaba. Falta validar con usuarios reales antes de G2 | Prueba de comprensión con 5 personas fuera del equipo |
| S-08 | Necesidades | `/` (sección) | **3** | No tiene ruta propia; vive en la portada. Filtros profundos si crece el volumen | Medir si la sección aguanta >20 necesidades sin filtro dedicado |
| S-09 | Mapa territorial | `/` (sección) | **3** | Validar densidad y proveedor con SLA antes de G2 | Prueba de densidad con volumen realista |
| S-10 | Registro de aporte | `/donar` | **3** | Validar comprensión con aliados | Métrica de abandono por paso |
| S-11 | Ticket del aporte | `/donar` (final) | **3** | Descarga PDF fuera de alcance | — |
| S-12 | Seguimiento | `/seguimiento` | **3** | Validar comprensión con donantes reales antes de G2 | Prueba de comprensión de la cronología |
| S-13 | Centros de acopio | `/` (sección) | **3** | Horarios reales requieren política y datos aprobados | Bloqueo humano, no de diseño |
| S-14 | Transparencia e impacto | `/transparencia` | **3** | Falta serie temporal cuando existan cortes (ligado a `G-027`) | Verificación visual con datos de ≥2 cortes |
| S-15 | Exportaciones | `/transparencia` (acción) | **3** | Selector de corte cuando exista historial autorizado | Ligado a `G-027` |
| S-16 | Ingreso | `/ingresar` | **3** | Reducir lenguaje técnico secundario | `audit:a11y` tras el ajuste de microcopy |
| S-17 | Pasarela de pago | `/pagos/practica/[ref]` | **2** | Nace con el recaudo (`G-053`). **No entra en `audit:a11y`/`audit:visual`**: la ruta exige una referencia de cobro viva, que no existe cuando corre la auditoría. Lo que sí la cubre es el E2E, que la recorre en web y en móvil | Auditarla con una referencia sembrada, o aceptar por escrito que su cobertura es solo E2E |

Resumen: 1 superficie en nivel 0, 3 en nivel 2, 13 en nivel 3, ninguna en 4.

El movimiento del 2026-08-17 es de evidencia, no de maquillaje: S-02, S-03 y S-04
suben porque ahora existe la medición que faltaba. S-05 se queda en 2 aunque su
contraste esté limpio, porque `DQ-06` la deja inusable en un teléfono.

## Hallazgos de la pista visual

| ID | Hallazgo | Sev. | Estado |
|---|---|---|---|
| DQ-01 | `audit:a11y` y `audit:visual` no cubrían ninguna ruta autenticada | P2 | **Cerrado** · 11 superficies auditadas con el rol que las usa (`scripts/lib/rutas-auditadas.mjs`) |
| DQ-02 | La superficie de evidencias no existe: el bucket es privado y no hay UI. Es la única en nivel 0 | P2 | Abierto · condicionada a `G-003`/`G-005` |
| DQ-03 | Ninguna superficie alcanza nivel 4. No hay microinteracción de estado declarada ni verificación de `prefers-reduced-motion` en los scripts de auditoría | P3 | **Cerrado en sus dos partes nombradas** (2026-08-20) · sistema de movimiento con tokens y microinteracción declarada de pulsación, foco, espera, hover y entrada (ADR-021); y `audit:a11y` estrena una pasada con `prefers-reduced-motion: reduce` que falla si algo se mueve —probada rompiéndola a propósito—. El **nivel 4 sigue sin reclamarse**: eso exige prueba de uso con personas, no más CSS |
| DQ-04 | `--muted` (#5f6d68) daba 4,89:1 sobre `--paper` pero **4,37 sobre `--mint`**, que es el fondo de todo estado seleccionado. El fallo era latente en diez fondos claros del stylesheet y solo se hizo visible al auditar `/operaciones/bodega` con sesión | P2 | **Cerrado** · token a #57645f (5,58 / 4,99); `audit:a11y` en 0 |
| DQ-05 | En el selector de lote, la cantidad —el dato por el que se elige— iba a 10 px en el color más tenue: el número decisivo era lo menos legible del control | P2 | **Cerrado** · tinta plena, 11 px, peso 700 |
| DQ-08 | El azul de identidad `#008bed` no alcanza AA cuando **es** texto o cuando lleva texto encima: 3,55:1 sobre blanco. Como fondo del botón principal dejaba la etiqueta de 14 px por debajo del mínimo, y como antetítulo de 12 px sobre tarjeta teñida se quedaba en 4,18. Lo destapó `audit:a11y` al pasar de 3 a 9 indeterminados tras el cambio de paleta | P2 | **Cerrado** · dos azules con papeles distintos: `--brand` para lo gráfico y `--forest-2` (`#0b5ea3`, 6,67:1 sobre blanco) para todo lo que es texto o lo sostiene. Desviación del comparativo documentada en ADR-020 |
| DQ-07 | El panel «Movimiento» desbordaba **25 px a 768 px**. `inline-form` fija `88px 88px minmax(150px,1fr) auto`: un mínimo de 347 px que no se puede encoger, y `.ops-bottom` reparte tres columnas cuyo mínimo automático es el min-content de cada hija, así que la del medio empujaba a la tercera fuera de la pantalla. Solo se veía en la banda 761–1024 px, justo donde no llega la regla móvil, y por eso ni la vista de escritorio ni la de teléfono lo mostraban | P2 | **Cerrado** · la recepción estrena rejilla propia y fluida (`reception-form`), como ya se había hecho con los traslados en DQ/G-048; `audit:visual` vuelve a 70 mediciones sin desbordes |
| DQ-06 | `/operaciones/centros` crece sin tope en móvil: **1,8 pantallas en escritorio contra 14,9 en un teléfono** con los mismos 28 puntos. En escritorio la lista tiene scroll interno y el alto no depende del número de puntos; ese scroll solo existe desde 761 px, así que en móvil cada punto añadido alarga la página. Compactar la ficha (dos columnas en vez de una) bajó la fila de 364 a 280 px, pero no cambia que el alto sea proporcional a los datos | P2 | **Mitigado, no cerrado** · la solución real es acotar la lista (buscador o ficha replegable), que es decisión de producto, no de CSS |

## Bloqueos humanos que afectan a esta pista

No son deuda técnica: sin estas decisiones no se puede subir de nivel.

- **Evidencia fotográfica real** exige consentimiento y política aprobada
  (`G-003`, `G-005`). La superficie S-01 puede diseñarse y probarse con datos
  sintéticos, pero no habilitarse para material real.
- **Horarios de centros** (S-13) y **marca institucional** dependen de `G-006`.
- **Serie temporal de impacto** (S-14, S-15) depende de que exista más de un
  corte conciliado, que es `G-027`.
