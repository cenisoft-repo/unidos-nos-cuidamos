# Reportes, dashboard y Excel

## Cobertura de los campos de referencia

| Aspecto | Implementación local | Regla de confianza |
|---|---|---|
| Aliado que reporta | Se deriva de la membresía autenticada en Supabase | El usuario no puede atribuirse otra organización |
| Donante y sector | Nombre privado, tipo de donante y sector económico | El nombre no aparece en la exportación pública ni operacional |
| Aporte | Tipo, categoría, descripción, cantidad, unidad y valor estimado COP por artículo | El valor estimado es declarado y no conciliado |
| Destino | Destinación específica, detalle privado, departamento y municipio/zona | La precisión pública sigue siendo aproximada |
| Beneficiarios | Estimación operacional separada | Nunca se convierte automáticamente en impacto |
| Seguimiento | Estado, canal previsto y centro preferido | La promesa no equivale a recepción o entrega |
| Coordinación | Responsable, contacto y observaciones privadas | RLS; excluidos de ambos Excel |
| Marcas y logos | Identidad neutral en el sandbox | Requieren autorización expresa antes de publicación |

## Dashboard público

- Fuente: `public_need_projections`, nunca tablas operacionales crudas.
- Barras: porcentaje cubierto por necesidad, limitado a 0–100 % para la visualización.
- Distribución: número de necesidades por estado público.
- Filtro: categoría, con `aria-pressed` y tabla equivalente para teclado y lectores de pantalla.
- Regla: no se suman litros, kits y unidades como si fueran una sola magnitud.

## Exportaciones

### Pública · `/api/exports/transparency.xlsx`

Incluye `Resumen`, `Necesidades`, `Aportes públicos`, `Centros` y `Metodología`. Solo consulta proyecciones públicas o RPC seguras, preserva tipos de fecha/número, añade fórmulas con resultado precalculado y neutraliza texto que pudiera ejecutarse como fórmula.

### Operacional · `/api/exports/operations.xlsx`

Exige una sesión con membresía activa del evento. Todas las consultas se ejecutan con esa sesión y RLS, sin `service_role`. Incluye seis hojas operativas, pero omite nombres de donantes, correos, teléfonos, contactos internos y observaciones.

Ambos libros identifican el entorno como simulación local y usan únicamente fixtures sintéticos.
