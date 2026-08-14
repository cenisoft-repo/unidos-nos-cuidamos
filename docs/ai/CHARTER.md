# Constitución operativa compacta

## Propósito

Dar a ciudadanía, donantes y equipos humanitarios una ruta segura y trazable desde el reporte hasta un resultado validado, diferenciando siempre lo declarado, verificado, conciliado y publicado.

## Alcance local

- Multi-evento y multi-organización.
- Necesidades, ingreso de aliados, especie, inventario, logística, dinero sandbox y transparencia.
- Supabase local como fuente transaccional; Next.js como PWA y capa de experiencia.
- Mapa público como proyección segura, nunca como libro operacional.

## Reglas innegociables

- No publicar contactos, ubicaciones precisas, soportes, referencias financieras ni PII.
- No preseleccionar rescate, urgencia o verificación.
- Solo organizaciones/fondos verificados participan en dinero; el sandbox no captura tarjetas.
- Inventario y dinero usan transacciones, idempotencia, segregación y eventos append-only.
- El tenant se deriva de la membresía autenticada; nunca de un selector confiado.
- Un estado declarado no altera inventario, cobertura, entrega ni métricas públicas.

## Puertas

- G0: especificación/arquitectura seguras y datos sintéticos; habilita desarrollo local.
- G1: ocho E2E, seguridad/privacidad sin P0/P1 y migración ensayada; habilita demo controlada.
- G2/G3 exigen operador, validaciones humanas y autorización externa; no se simulan.

Fuente normativa: `docs/LOOP_MAESTRO_DESARROLLO_PLATAFORMA_DONACIONES_EMERGENCIA.md`.
