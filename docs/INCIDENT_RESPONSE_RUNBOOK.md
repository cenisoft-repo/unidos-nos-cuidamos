# Respuesta a incidentes · runbook sandbox

Este procedimiento está listo para ejercicios con datos sintéticos. Antes de G2 deben asignarse personas nominales, turnos, teléfonos seguros y autoridad para activar cada acción. No autoriza comunicaciones externas ni tratamiento de datos reales.

## Severidad y tiempos objetivo

| Nivel | Ejemplo | Acuse | Escalamiento |
|---|---|---:|---:|
| P0 | exposición sensible, desvío de dinero, corrupción o indisponibilidad crítica | 15 min | inmediato a responsable del evento, seguridad y privacidad |
| P1 | flujo esencial, conciliación, autorización o recuperación rota | 30 min | 1 h |
| P2 | degradación con alternativa segura | 4 h | siguiente turno |
| P3 | mejora sin impacto operacional | 1 día hábil | planificación |

Los tiempos son objetivos del simulacro, no SLA aprobados.

## Primeros 30 minutos

1. Crear un incidente en el registro operacional con evento, severidad, fuente, alcance estimado y actor que declara. No incluir secretos ni PII en título o logs.
2. Preservar evidencia: request ID, timestamp UTC, versión, estado de salud y eventos append-only. No borrar ni editar la historia.
3. Contener de forma reversible: suspender el evento o la función afectada, revocar sesiones comprometidas y mantener las superficies públicas en falla segura.
4. Si hay posible exposición, bloquear nuevas capturas y preservar la proyección pública existente; nunca publicar direcciones, contactos o archivos para “investigar”.
5. Si hay inconsistencia financiera o de inventario, detener nuevas transiciones y conciliar desde libros independientes antes de reanudar.

## Diagnóstico mínimo

```powershell
Invoke-WebRequest http://127.0.0.1:3000/api/health
npm run db:status
npm run db:test
npm run test:rls
npm run test:concurrency
```

Registrar únicamente códigos de error, request IDs, rutas de operación y tiempos. Los logs estructurados excluyen cuerpos, URL con query, contactos y secretos.

## Recuperación

- Aplicación: volver al último artefacto revisado; una promoción o rollback remoto requiere autorización.
- Base local sintética: seguir `docs/OPERATIONAL_READINESS.md` y verificar checksums antes de restaurar.
- Registro crítico: corregir con una transacción compensatoria; nunca `UPDATE`/`DELETE` sobre auditoría.
- Sesiones: revocar antes de eliminar una cuenta; un JWT emitido no se invalida solo por borrar el usuario.
- Publicación: comparar proyecciones públicas con consultas operacionales independientes antes de reabrir.

## Cierre y aprendizaje

El cierre exige causa, línea de tiempo, datos afectados, decisiones, conciliación, pruebas repetidas, acción preventiva y responsable. Un P0/P1 genera prueba de regresión. La notificación a titulares, autoridades, donantes o aliados queda sujeta al procedimiento jurídico aprobado; en sandbox solo se ensaya con destinatarios ficticios y no se envían mensajes.
