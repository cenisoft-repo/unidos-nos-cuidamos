# Plan de migración del legado

No se dispone de copia autorizada. El ensayo usa un CSV sintético con válidos, duplicados, vencidos, no ubicados, desmentidos y PII artificial.

Proceso: snapshot/checksum → perfilado/PII → mapeo → catálogos/territorios → deduplicación → cuarentena → conciliación/muestra → aprobación humana → publicación gradual. Cada lote conserva fuente, corte, checksum, conteos y resultados. Rollback elimina únicamente proyecciones/entidades creadas por ese lote y agrega el evento compensatorio; la evidencia del lote se conserva.

Ningún registro migra como verificado.
