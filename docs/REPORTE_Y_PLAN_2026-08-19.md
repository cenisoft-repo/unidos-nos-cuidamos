# Reporte de cierre y plan de acción · 19 de agosto de 2026

Estado tras la noche de integración, el despliegue a producción y la preparación de la
demostración. La bitácora de qué se hizo está en
[`BITACORA_2026-08-18_19.md`](./BITACORA_2026-08-18_19.md); esto es dónde estamos y qué
sigue.

---

## 1. Dónde estamos

| | |
|---|---|
| Migraciones en producción | 39/39, sin pendientes |
| Código desplegado | igual a `main` |
| RPC que invoca la aplicación | las 54 existen en producción |
| Suite local | `npm run verify` verde · 48/48 Playwright · pgTAP completo |
| Accesibilidad / maquetación | 0 problemas en 14 superficies · 70 mediciones sin desbordes |
| Autoridad global | concedida y activa |
| Puerta de calidad | G1 · **datos 100 % sintéticos** |

Lo que funciona de extremo a extremo: portal y mapa públicos, seguimiento por código,
registro de aliado, aporte con evidencia, verificación, recepción en bodega, traslado entre
bodegas con doble control, despacho con transporte, conciliación con faltante,
parametrización y auditoría.

## 2. Riesgos abiertos, por severidad

### P1 · Impiden operar con aliados reales

| Brecha | Qué pasa | Qué cuesta cerrarla |
|---|---|---|
| `G-044` | Sin SMTP propio, el correo de confirmación no llega a direcciones externas. **Un aliado real no puede completar su registro** | Cuenta en un proveedor (Resend/Brevo/SendGrid) + SPF y DKIM del dominio. Medio día, la mayor parte esperando DNS |
| `G-045` | La confirmación de correo está desactivada, así que **no se comprueba que quien registra controle ese buzón**. Alguien puede registrarse con el correo de otro | Se revierte con configuración, sin tocar código. Depende de `G-044` |

### P0 operativo · No es una brecha del sistema, es higiene

**Credenciales expuestas durante la operación:** la contraseña de la base de datos y las de
las tres cuentas del sandbox quedaron en el historial de la conversación de trabajo.
**Rotar todas** en cuanto termine la exposición.

### P2 · Deuda conocida

| Brecha | Qué falta |
|---|---|
| `G-026` | Cada fila auditada genera una correlación distinta dentro de la misma RPC: no se puede seguir una transacción completa |
| `G-027` | Las operaciones no generan un corte nuevo de métricas conciliadas |
| `G-031` | Los 21 puntos de gremios son públicos pero ningún aliado puede enrutar un aporte a ellos sin representante propio |
| `G-043` | La auditoría guarda antes/después solo en las tablas del parametrizador; en las operativas llevaría PII |
| `G-007`, `G-015`, `G-017` | HIBP, WAF de borde y enlaces verificables a remoto: administración de entorno |
| `G-001`–`G-006` | Operador, DPIA, política de aceptación, proveedor financiero, marca: **decisiones humanas**, no técnicas |

### Sin red de seguridad en producción

No hay **backups remotos con PITR**, ni monitoreo externo, ni alertas. Hoy el único respaldo
es el volcado de esquema que se tomó antes de migrar. Con datos sintéticos es asumible; con
datos reales no.

## 3. Plan de acción

### Ahora — antes y durante la exposición

1. **Sembrar el recorrido.** `node scripts/seed-demo-journey.mjs` deja 4 pendientes en cada
   etapa. Si la organización no tiene dos bodegas, crea la de salida por la RPC real.
2. **Dos sesiones abiertas.** El traslado exige que quien solicita no autorice: `bodega@`
   pide, `admin@` autoriza. Un navegador normal y uno de incógnito.
3. **Orden que fluye:** portal → seguimiento → registro de aliado → aporte con foto →
   verificación con evidencia → bodega y traslado → parametrización → transparencia.
   Las dos últimas son las que mejor se ven y no dependen de nada previo.

### Esta semana

4. **Configurar el workflow de despliegue** (`.github/workflows/despliegue.yml`): entorno
   `produccion` con revisores y seis secretos. Elimina de raíz la dependencia de que la red
   del equipo alcance el pooler de sesión, que hoy está cortado en el puerto 5432, y saca
   la contraseña de las terminales. **Es la mejora de mayor relación valor/esfuerzo.**
5. **Rotar todas las credenciales expuestas** y guardarlas directamente como secretos del
   repositorio, sin pasar por ninguna terminal.
6. **SMTP propio + restablecer la confirmación de correo.** Cierra `G-044` y `G-045` de una
   vez. Verificar además que el *Site URL* de Auth apunte al dominio de producción: con SMTP
   perfecto y esa URL en localhost, el correo llega y el enlace no sirve.
7. **Backups con PITR y un monitor externo** sobre `/api/health`. Sin esto, cualquier
   incidente en producción se descubre porque alguien mira.

### Antes de G2 — datos reales

8. **`G-002` a `G-006`.** Nada de esto lo resuelve el equipo técnico: entidad operadora y
   RACI, DPIA y base legal, política de aceptación validada por autoridad humanitaria,
   proveedor financiero, y autorización de marca. **Son la puerta real, no el código.**
9. **Decidir `G-031`:** o cada gremio habilita a su representante, o el modelo admite
   entregar en un punto de otra organización validando en recepción.
10. **Repetir el arnés de simulación remota** para cerrar `G-022` globalmente.

## 4. Mejoras propuestas

Ordenadas por lo que rinden, no por lo que cuestan.

### 4.1 Un identificador de correlación por transacción (`G-026`)

Hoy cada fila auditada nace con su propia correlación, así que reconstruir «qué pasó en esta
operación» exige cruzar por tiempo y esperar que no haya concurrencia. Con un identificador
por transacción, la auditoría pasa de ser un registro a ser una historia legible. Es barato
—una variable de sesión fijada al entrar en cada RPC— y es exactamente lo que se necesita
cuando algo sale mal en producción.

### 4.2 La evidencia se guarda pero nadie la analiza

`evidence.scan_status` existe desde `202608160002` y **ningún proceso lo escribe**: toda
fotografía queda con su estado inicial. Se aceptan imágenes de terceros en un bucket privado
sin ninguna comprobación de contenido. Mientras las fotos las suban aliados conocidos el
riesgo es bajo; con autorregistro abierto deja de serlo. Conviene decidir: o se analiza, o
se retira la columna para que no sugiera una garantía que no existe.

### 4.3 Cerrar la puerta de calidad antes de fusionar

La verificación corre en cada PR y sobre `main`, pero nada impide fusionar con la suite en
rojo. Una regla de protección de rama que exija «Verificación sandbox» convierte la puerta
en puerta. Cuesta cinco minutos.

### 4.4 Decidir el doble control del traslado

Hoy quien solicita un traslado no puede autorizarlo. Es un control deliberado y vale la pena
en una operación con varias personas; en una bodega pequeña con una sola, estorba. **No
conviene relajarlo por conveniencia de una demostración**, pero sí decidirlo con la
operación real delante y dejarlo escrito en `DECISIONS.md`.

### 4.5 Que la parametrización alcance las reglas de aceptación

`item_acceptance_rules` decide qué categorías recibe cada punto y hoy solo se toca por la
RPC de puntos. Exponerlo en la parametrización evitaría el rechazo más común en recepción
—«el centro no recibe esa categoría»— sin tocar ninguna invariante: son datos, no contrato.

### 4.6 Lo que **no** conviene hacer

- **Desactivar «Confirm sign up» de forma permanente.** Es la puerta sobre la que descansa
  ADR-013. Está desactivada por una carencia de infraestructura, no por diseño.
- **Usar `supabase config push` contra producción.** `config.toml` declara `site_url` en
  localhost: rompería todos los enlaces de confirmación.
- **Conceder SUPER_ADMIN a una cuenta del sandbox.** Su contraseña vive en el repositorio.
- **Añadir volcados de datos a los artefactos de CI.** Hoy son sintéticos; el día que no lo
  sean, eso es una filtración y no una copia de seguridad.

## 5. Lecciones que conviene no olvidar

**Una migración que compila no es una migración que funciona.** Seis migraciones pasaron
revisión y análisis sintáctico, y al ejecutarlas por primera vez aparecieron cuatro
defectos, uno de ellos la reapertura de un P0. Nada falló al compilar.

**Un envoltorio que valida se pierde en silencio.** `submit_donation_intake_v2` perdió su
validación de tenant porque alguien reimplementó la función que el envoltorio envolvía. No
hubo error, ni aviso, ni prueba en rojo: la regla simplemente dejó de existir.

**Comprobar los privilegios contra `proacl`, no contra la intención.** `grant_super_admin`
afirmaba en su comentario ser alcanzable con `service_role` y no lo era; `revoke all from
public, anon, authenticated` no deja una función «solo para service_role», la deja sin
dueño.

**Los fallos silenciosos los encuentran las pruebas, no la vista.** La CSP bloqueaba la
evidencia sin ningún error visible. Lo detectó una aserción sobre `naturalWidth`, no una
revisión visual: el elemento estaba ahí, simplemente no cargaba.

---

> **Recordatorio permanente:** el entorno sigue siendo **G1 con datos sintéticos**. No debe
> recibir datos reales, dinero ni comunicación institucional hasta que `G-002` a `G-006`
> estén cerradas por decisión humana.
