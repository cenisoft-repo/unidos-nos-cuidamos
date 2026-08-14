# Diccionario de datos · clasificación

| Grupo | Sensibilidad | Visibilidad/retención sandbox |
|---|---|---|
| Contacto, identidad interna, ubicación exacta | Restringida | Solo roles autorizados; nunca pública; 30 días tras cierre simulado |
| Evidencia y referencias de pago | Restringida | Bucket privado; metadatos mínimos; sin URLs públicas |
| Necesidad operacional | Interna | Tenant/evento; proyección pública aproximada y aprobada |
| Inventario/logística | Interna | Organización/evento; cifras agregadas públicas |
| Libro financiero sandbox | Restringida | Tesorería/auditoría; métricas públicas conciliadas |
| Atribución pública | Pública autorizada | Alias/organización/anónimo; persona natural exige autorización versionada |
| Perfil, destinación y estimaciones del aporte | Interna declarada | Tipo/sector, destino, beneficiarios y valores estimados; no son impacto ni conciliación pública |
| Responsable, contacto y observaciones del aporte | Restringida | Solo operación autorizada por RLS; se excluye de ambas exportaciones Excel |
| Logística cartográfica pública | Pública aproximada | Centro, código/estado de despacho y origen-destino aproximados; sin dirección, transportador, custodio o GPS |
| Auditoría | Confidencial append-only | Auditor/admin; conservación según política aprobada futura |

Todas las entidades incluyen UUID, evento/organización aplicable, estado, autor/origen, timestamps y clasificación de visibilidad. Los detalles de campos viven en las migraciones versionadas.
