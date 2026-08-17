# UX Map · Ruta Solidaria

Este mapa traduce la capa UX/UI amigable al sandbox funcional actual. Mantiene los límites del proyecto: datos sintéticos, privacidad geoespacial, estados conciliados y ausencia de marcas institucionales no autorizadas.

## Promesa de experiencia

La persona debe poder responder, sin capacitación:

1. ¿Qué hace falta?
2. ¿Cómo puedo ayudar?
3. ¿Dónde puedo entregar?
4. ¿En qué etapa está mi aporte?
5. ¿Qué resultado se puede comprobar?

## Recorridos principales

### Ciudadanía

`Entender → explorar necesidades → elegir una → ayudar o reportar → guardar código → comprobar estado`

### Donante o aliado

`Elegir categoría y describir cantidad → definir entrega (solo especie) → registrar contacto privado → revisar → recibir ticket/QR → seguir`

### Operación

`Escanear o buscar código → confirmar recepción → clasificar → reservar → despachar → registrar entrega → validar evidencia`

### Auditoría

`Seleccionar evento → revisar proyección → reproducir eventos append-only → verificar fórmula/corte → reportar excepción`

## Mapa de pantallas y auditoría

| Superficie | Objetivo principal | Acción principal | Estado inicial | Decisión UX | Ajuste prioritario |
|---|---|---|---|---|---|
| Home pública | Entender y actuar | Quiero ayudar | Hero humano, foto acreditada y rastreo visible | ✅ Implementado | Validar con usuarios antes de G2 |
| Necesidades | Elegir dónde ayudar | Donar a una necesidad | Catálogo visual con faltante, avance, ubicación y CTA | ✅ Implementado | Añadir filtros profundos si aumenta el volumen |
| Mapa territorial | Explorar por lugar | Seleccionar zona, centro o despacho | Cartografía real MapLibre/OpenFreeMap, fallback Leaflet/OSM, PostGIS y Realtime | ✅ Implementado | Validar densidad y proveedor con SLA antes de G2 |
| Registro de aporte | Registrar una promesa | Continuar al siguiente paso | Flujo adaptativo: 4 pasos en especie y 3 en dinero. Solo quedan a la vista los campos obligatorios; destinación, valor estimado, cuidado y datos internos viven en bloques opcionales plegados | ✅ Implementado | Validar comprensión con aliados |
| Ticket del aporte | Guardar y seguir | Seguir mi aporte | Ticket QR, resumen e impresión | ✅ Implementado | Descarga PDF queda fuera del alcance actual |
| Seguimiento | Comprender el estado | Consultar código | Cronología de hitos comprobados con fecha; el código del aporte atraviesa su donación operacional y se nombra el siguiente control | ✅ Implementado | Validar comprensión con donantes reales antes de G2 |
| Centros de acopio | Elegir punto compatible | Ver qué recibe | RPC segura, tarjetas, mapa y preselección | ✅ Implementado | Horarios reales requieren política y datos aprobados |
| Reporte ciudadano | Informar hechos | Enviar a verificación | Categorías visuales y campos privados explícitos | ✅ Implementado parcial | Recorrido multipaso opcional tras pruebas de uso |
| Ingreso | Acceder por rol | Ingresar | Claro y aislado | ✅ Conservar | Reducir lenguaje técnico secundario |
| Centro operativo | Decidir qué hacer hoy | Resolver prioridad | Lanzador por rol, KPI y pendientes | ✅ Implementado | Validar con operadores antes de G2 |
| Administración de puntos | Definir dónde se recibe y desde dónde se despacha | Crear/editar punto | `/operaciones/centros`: organización, propósito (acopio, despacho o ambos), privacidad, coordenada, disponibilidad, frío y categorías | ✅ Implementado local | Desplegar solo tras autorización y repetir aislamiento remoto |
| Recepción | Confirmar custodia | Recibir aporte | Búsqueda por código/categoría, cantidades etiquetadas y centro receptor | ✅ Implementado | Escáner físico requiere dispositivo/política aprobados |
| Inventario | Reservar existencia | Asignar lote | Tarjetas de lote y necesidades filtradas por categoría/unidad | ✅ Implementado | Validar reglas de compatibilidad con autoridad |
| Despacho | Crear salida | Despachar | Formulario con punto de origen habilitado, zona de destino y transportador privado; el origen queda registrado en el despacho | ✅ Implementado | Transportador real permanece privado y bloqueado |
| Entrega | Registrar resultado | Confirmar entrega | Etapa móvil, resultado y validación independiente | ✅ Implementado | Evidencia real requiere consentimiento/antimalware |
| Evidencias | Probar custodia/resultado | Subir evidencia | Bucket privado sin UI dedicada | 🔴 Rediseñar completamente | Componente antes/en tránsito/entrega con permisos explícitos |
| Transparencia/impacto | Comprobar cifras | Explorar dashboard o descargar Excel | KPI, barras de cobertura, distribución por estado, tabla equivalente y metodología reproducible | ✅ Implementado | Añadir serie temporal y comparación entre eventos cuando existan cortes suficientes |
| Exportaciones | Analizar sin perder el contrato de datos | Descargar `.xlsx` | Libro público seguro y libro operacional sujeto a sesión/RLS | ✅ Implementado | Incorporar selector de corte cuando exista historial autorizado |
| Tesorería sandbox | Conciliar o aprobar | Acción segregada del rol | Etapas 01 Conciliar → 04 Pagar con sus colas, saldo del libro completo, justificación obligatoria y legible, y explicación de por qué una solicitud propia no ofrece decisión | ✅ Implementado | Validar el vocabulario financiero con tesorería antes de G2 |

## Arquitectura de información objetivo

### Público

- Inicio
  - Hoy hace falta
  - Mapa territorial
  - Centros de acopio
  - Cómo viaja una ayuda
  - Impacto conciliado
- Necesidades
- Ayudar
- Rastrear mi ayuda
- Transparencia

### Operación autenticada

- Hoy
  - Recibir
  - Clasificar
  - Asignar
  - Despachar
  - Entregar
  - Evidencias
- Puntos de entrega (solo administración)
- Pendientes importantes
- Bodega y logística
- Tesorería
- Auditoría

## Sistema visual

- Verde: verificado, completado o entregado.
- Azul: información territorial y logística.
- Naranja: atención o revisión.
- Rojo: incidencia o urgencia comprobada, nunca decoración.
- Gris: pendiente o inactivo.
- Cada estado combina icono, texto y color.
- Una acción principal por pantalla; hasta tres secundarias.
- Lucide como biblioteca SVG consistente.
- Movimiento solo para carga, sincronización o confirmación; se respeta `prefers-reduced-motion`.

## Privacidad y confianza

- El mapa público solo consume proyecciones aprobadas y coordenadas aproximadas.
- El mapa muestra una conexión origen-destino, no una ruta vial calculada ni la posición GPS de un vehículo.
- Evidencia, contacto, dirección exacta, transportador y rutas permanecen privados.
- La portada usa una fotografía editorial de stock acreditada que no identifica personas beneficiarias; imágenes operativas o evidencias con personas siguen bloqueadas hasta contar con consentimiento y política aprobada.
- El QR identifica un código seguro, no contiene PII.
- Ninguna cifra de impacto se infiere a partir de promesas o cantidades incompatibles.
- Beneficiarios y valores estimados son declaraciones operacionales; no alimentan métricas públicas antes de verificación y conciliación.
- Los libros Excel públicos excluyen PII; los operativos también omiten contactos y observaciones internas aunque el rol pueda verlos en la aplicación.
- Logos, slogans y franjas institucionales solo se incorporan tras autorización de marca; el sandbox conserva identidad neutral.

## Secuencia de implementación

1. ✅ Home humana, catálogo “Hoy hace falta” y acceso universal al rastreo.
2. ✅ Registro de aporte adaptativo (cuatro pasos en especie, tres en dinero) y ticket QR.
3. ✅ Centros de acopio públicos mediante proyección segura.
4. ✅ Lanzador, búsqueda de recepción, selección de lote, compatibilidad y etapas logísticas implementados.
5. ⛔ Evidencias privadas y visualización por etapa permanecen condicionadas a política y consentimiento aprobados.

Este documento se creó antes de modificar los componentes de la nueva iteración, como exige la capa UX/UI de referencia.
