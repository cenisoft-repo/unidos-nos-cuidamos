# Línea base de carga · F0 del loop de escala

**Tomada el 2026-08-21**, sobre volumen sintético local. Se regenera con:

```
npm run db:reset && npm run seed:volumen && node scripts/verify-carga.mjs --establecer-linea-base
```

y se comprueba con `npm run verify:carga`, que falla si una consulta se sale de su línea base
o si deja de terminar.

## Una advertencia primero, porque esta línea base sustituye a otra que mentía

La primera versión de este arnés medía **con la RLS desactivada** —entraba como `postgres`, que
tiene `rolbypassrls`, y nunca cambiaba de rol— y **sobre tablas que el sembrador dejaba
vacías**. Las cifras que publicó describían un sistema que nadie usa. Se retiraron enteras.

El arreglo no fue «poner RLS a todo»: fue **modelar cada consulta como se ejecuta de verdad**,
que son tres situaciones distintas y aplastarlas en una era el problema:

| Cómo corre en producción | Cómo se mide |
|---|---|
| Con sesión, leyendo tablas | `authenticated`, con la RLS aplicándose |
| Sin sesión | `anon`, igual con RLS |
| Dentro de una función `security definer` | como el dueño, **sin** RLS, porque así corre |

Las cuatro búsquedas de idempotencia son del tercer tipo. Medirlas con RLS habría sido el error
simétrico del que se venía a corregir.

## El volumen sobre el que se midió

| | |
|---|---|
| Movimientos de Kardex | **980.007** |
| Eventos de auditoría | **1.049.334** |
| Lotes de inventario | 20.004 |
| Solicitudes logísticas · líneas | 10.000 · 20.000 |
| Asignaciones | 5.001 |
| Aportes en cola | 5.000 |
| Movimientos financieros | 3.000 |
| Casos de necesidad | 2.003 |
| Despachos | 2.001 |
| Entregas | 1.000 |
| Operadores con membresía | 1.036 |

Sembrado en **184 s**, cero posiciones de Kardex negativas y cero discrepancias entre la caché
de saldo y el Kardex.

## Lo que tarda hoy el camino caliente

`EXPLAIN (ANALYZE, BUFFERS)`, tres ejecuciones, p95. La puerta de F3 exige **p95 < 200 ms**.
Hoy la incumplen **nueve de diecinueve**.

| Consulta | p95 | Qué la hunde |
|---|---|---|
| `consola:conteo-auditoria` | **8.370 ms** | **B8 + B7** · contar 1.049.311 filas de auditoría con la política evaluándose |
| `bodega:posiciones-kardex` | **2.336 ms** | **B7** · la consola principal de bodega |
| `bodega:aportes-por-recibir` | **1.361 ms** | `Seq Scan` sobre `donations` con política |
| `bodega:solicitudes-logisticas` | 1.315 ms | `security definer`, sin RLS: aquí manda la forma, no la compuerta |
| `bodega:disponibilidad-compartida` | 809 ms | ídem |
| `bodega:asignaciones` | **632 ms** | **B7** · antes medía 0,3 ms sobre una tabla vacía |
| `consola:aportes-en-cola` | 338 ms | **B7** |
| `bodega:conciliacion-despachos` | 229 ms | **B7** |
| `bodega:despachos` | 201 ms | **B7** |
| las diez restantes | < 132 ms | — |

## Lo que estos números dicen y los anteriores no podían decir

**B7 es ahora el bloqueo dominante, por encima de B6.** El patrón es nítido: las dos consultas
que apenas cambiaron —`logistics_requests` y `shared_stock_availability`— son las que pasan por
funciones `security definer`, donde no hay RLS. Las que se dispararon son las que la aplicación
lee **directamente** como `authenticated`, donde la compuerta se evalúa por fila.

Es exactamente lo que el loop describe en B7 —`is_org_member` no se iza a InitPlan porque usa
columnas de la fila— y es lo que el arnés anterior no podía ver **por construcción**, porque
medía justo con eso apagado.

## Cómo leer estos números

- Miden **el motor**, no la aplicación: es el `Execution Time` que informa PostgreSQL, sin
  latencia de red. La experiencia real será peor.
- Se midieron en una máquina de trabajo con Docker, no en la infraestructura de destino. Sirven
  para **comparar antes y después**, que es para lo que existe una línea base; no para
  prometerle un tiempo de respuesta a nadie.
- `AGOTADA` no es un fallo del arnés: es el resultado, y **cuenta como rojo**. Una consulta que
  deja de terminar es la peor regresión que existe y antes atravesaba la puerta en verde.

## Lo que sigue sin estar comprobado (`G-073`)

Nadie ha comprobado que la **forma** de los datos sembrados coincida con la que producen
`receive_donation` y `reserve_lot_quantity`. El andamiaje respeta todas las restricciones,
claves foráneas y disparadores del esquema —lo rechazó cinco veces mientras se escribía, y cada
rechazo era el esquema enseñando una regla real— pero eso no es lo mismo que haber pasado por
la validación de negocio de cada RPC. Queda escrito en vez de prometido.
