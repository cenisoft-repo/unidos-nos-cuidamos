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

`Elegir categoría → describir cantidad → definir entrega → registrar contacto privado → recibir ticket/QR → seguir`

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
| Registro de aporte | Registrar una promesa | Continuar al siguiente paso | Flujo de 5 pasos con centro, destinación, perfil, valor estimado y datos internos protegidos | ✅ Implementado | Validar comprensión con aliados |
| Ticket del aporte | Guardar y seguir | Seguir mi aporte | Ticket QR, resumen e impresión | ✅ Implementado | Descarga PDF queda fuera del alcance actual |
| Seguimiento | Comprender el estado | Consultar código | Línea de hitos segura | 🟡 Simplificar | Reforzar microcopy y próximos pasos; no mostrar rutas/personas |
| Centros de acopio | Elegir punto compatible | Ver qué recibe | RPC segura, tarjetas, mapa y preselección | ✅ Implementado | Horarios reales requieren política y datos aprobados |
| Reporte ciudadano | Informar hechos | Enviar a verificación | Categorías visuales y campos privados explícitos | ✅ Implementado parcial | Recorrido multipaso opcional tras pruebas de uso |
| Ingreso | Acceder por rol | Ingresar | Claro y aislado | ✅ Conservar | Reducir lenguaje técnico secundario |
| Centro operativo | Decidir qué hacer hoy | Resolver prioridad | Lanzador por rol, KPI y pendientes | ✅ Implementado parcial | Evolucionar recepción rápida por escáner |
| Recepción | Confirmar custodia | Recibir aporte | Formulario por fila | 🔴 Rediseñar completamente | Buscar/escanear código y una acción primaria |
| Inventario | Reservar existencia | Asignar lote | Selects densos | 🟠 Rediseñar parcialmente | Tarjetas por lote y compatibilidad visible |
| Despacho | Crear salida | Despachar | Acción dentro de lista | 🟠 Rediseñar parcialmente | Recorrido por pasos y destino visible |
| Entrega | Registrar resultado | Confirmar entrega | Acción dentro de lista | 🟠 Rediseñar parcialmente | Captura móvil, resumen y feedback humano |
| Evidencias | Probar custodia/resultado | Subir evidencia | Bucket privado sin UI dedicada | 🔴 Rediseñar completamente | Componente antes/en tránsito/entrega con permisos explícitos |
| Transparencia/impacto | Comprobar cifras | Explorar dashboard o descargar Excel | KPI, barras de cobertura, distribución por estado, tabla equivalente y metodología reproducible | ✅ Implementado | Añadir serie temporal y comparación entre eventos cuando existan cortes suficientes |
| Exportaciones | Analizar sin perder el contrato de datos | Descargar `.xlsx` | Libro público seguro y libro operacional sujeto a sesión/RLS | ✅ Implementado | Incorporar selector de corte cuando exista historial autorizado |
| Tesorería sandbox | Conciliar o aprobar | Acción segregada del rol | Consola técnica | 🟡 Simplificar | Lenguaje más natural; conservar controles y separación |

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
2. ✅ Registro de aporte en cinco pasos y ticket QR.
3. ✅ Centros de acopio públicos mediante proyección segura.
4. 🟡 Lanzador operativo implementado; recepción rápida por escáner queda como siguiente incremento local.
5. ⛔ Evidencias privadas y visualización por etapa permanecen condicionadas a política y consentimiento aprobados.

Este documento se creó antes de modificar los componentes de la nueva iteración, como exige la capa UX/UI de referencia.
