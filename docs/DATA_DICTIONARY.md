# Diccionario de datos · clasificación

| Grupo | Sensibilidad | Visibilidad/retención sandbox |
|---|---|---|
| Contacto, identidad interna, ubicación exacta | Restringida | Solo roles autorizados; nunca pública; 30 días tras cierre simulado |
| Evidencia y referencias de pago | Restringida | Bucket privado; metadatos mínimos; sin URLs públicas |
| Fotografías del intake | Restringida | Hasta 3 JPG/PNG de 5 MB; ruta generada por servidor, hash SHA-256, revisión pendiente y vínculo `APO-*`; nunca pública ni prueba automática de entrega |
| Necesidad operacional | Interna | Tenant/evento; proyección pública aproximada y aprobada |
| Inventario/logística | Interna | Organización/evento; cifras agregadas públicas |
| Libro financiero sandbox | Restringida | Tesorería/auditoría; métricas públicas conciliadas |
| Atribución pública | Pública autorizada | Alias/organización/anónimo; persona natural exige autorización versionada |
| Perfil, destinación y estimaciones del aporte | Interna declarada | Tipo/sector, destino, beneficiarios y valores estimados; no son impacto ni conciliación pública |
| Aliado de referencia del aporte | Interna declarada | Código de catálogo para resumen; no reemplaza la organización derivada de membresía, no concede permisos ni autoriza uso público de marca |
| Responsable, contacto y observaciones del aporte | Restringida | Solo operación autorizada por RLS; se excluye de ambas exportaciones Excel |
| Logística cartográfica pública | Pública aproximada | Centro, código/estado de despacho y origen-destino aproximados; sin dirección, transportador, custodio o GPS |
| Punto de entrega parametrizado | Mixta | Nombre, zona, instrucción, coordenada aproximada, capacidad y categorías son públicas/organizacionales según superficie; `exact_address_private` es restringida y nunca sale en mapa, formulario del aliado ni Excel público |
| Historial de parametrización | Confidencial append-only | `delivery_point_changes` conserva actor, tenant, punto, idempotencia y huella; las reglas anteriores se cierran por vigencia y no se borran |
| Registro de aliado | Restringida | `ally_registrations` guarda razón social, NIT, responsable, teléfono y correo; solo los ve la propia cuenta y la verificación/administración del evento. El identificador `alias@rutasolidaria.co` es una identidad de plataforma, no un buzón, y no se publica |
| Transporte del despacho | Restringida | Tipo, empresa, nombre, identificación, teléfono, vehículo, placa y responsable viven en `shipments` y nunca entran a la proyección logística pública |
| Traslado entre bodegas | Interna | `transfer_requests` conserva origen, destino, cantidad solicitada y autorizada, justificación y quién decidió; no tiene superficie pública |
| Alcance por bodega | Interna | `membership_locations` declara qué puntos administra una membresía; sin filas, el alcance es toda la organización |
| Auditoría | Confidencial append-only | Auditor/admin; conservación según política aprobada futura |

Todas las entidades incluyen UUID, evento/organización aplicable, estado, autor/origen, timestamps y clasificación de visibilidad. Los detalles de campos viven en las migraciones versionadas.
