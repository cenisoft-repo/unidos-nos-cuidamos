# Línea base de carga · F0 del loop de escala

**Tomada el 2026-08-21** sobre volumen sintético local. Se regenera con:

```
npm run db:reset && npm run seed:volumen && node scripts/verify-carga.mjs --establecer-linea-base
```

y se comprueba con `npm run verify:carga`, que falla si una consulta se sale de su línea base.

## El volumen sobre el que se midió

| | |
|---|---|
| Movimientos de Kardex | **980.007** |
| Eventos de auditoría | **1.031.334** |
| Lotes de inventario | 20.004 |
| Solicitudes logísticas | 10.000 · 20.000 líneas |
| Operadores con membresía | 1.036 |
| Bodegas | 64 |

Sembrado en **125 s**, con cero posiciones de Kardex negativas. Que la auditoría supere a la
operación —1.031.334 contra 980.007— no es un defecto del sembrador: es **B8 medido**. Cada
escritura del sistema genera al menos otra fila que nadie puede podar.

## Lo que tarda hoy el camino caliente

Medido con `EXPLAIN (ANALYZE, BUFFERS)`, tres ejecuciones, p95. La puerta de F3 exige **p95
por debajo de 200 ms**. Hoy la incumplen tres:

| Consulta | p95 | Qué la hunde |
|---|---|---|
| `bodega:solicitudes-logisticas` | **no termina en 20 s** | **B6** · subconsulta correlacionada por línea, sobre el Kardex agregado entero |
| `bodega:disponibilidad-compartida` | **1.233 ms** | agrega existencia compartida de toda la red |
| `bodega:posiciones-kardex` | **273 ms** | **B6** · `Seq Scan` sobre 326.669 filas de `stock_movements` |
| `consola:conteo-auditoria` | 44 ms | **B8** · conteo sobre la tabla que más crece |
| `idempotencia:movimiento` | **43 ms** | **B5** · `Seq Scan` porque la búsqueda no aporta `organization_id` |
| `bodega:aportes-por-recibir` | 15 ms | `Seq Scan` sobre 20.004 artículos y 20.002 aportes |
| las trece restantes | < 7 ms | — |

**Seis consultas recorren alguna tabla entera.** Un `Seq Scan` que hoy pasa la puerta por
tener pocas filas es una bomba con fecha, así que el arnés lo anota aunque el tiempo aguante.

## Cómo leer estos números

- Miden **el motor**, no la aplicación: es el `Execution Time` que informa PostgreSQL, sin la
  latencia de red ni el tiempo de arranque del proceso. La experiencia real será peor.
- Se midió en una máquina de trabajo con Docker, no en la infraestructura de destino. Sirven
  para **comparar antes y después** de un cambio, que es para lo que existe una línea base;
  no para prometer un tiempo de respuesta a nadie.
- `AGOTADA` no es un fallo del arnés: es el resultado. Una consulta que no termina en 20 s con
  10.000 solicitudes es una consulta que no existe a escala.

## La regla que esto habilita

§5 del loop: **ninguna optimización posterior se acepta sin su línea base.** A partir de aquí,
un cambio de rendimiento que no muestre su antes y su después medidos no se da por bueno.
