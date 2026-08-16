# Manual de usuario · Ruta Solidaria

**Producto:** Ruta Solidaria — plataforma de donaciones y ayuda humanitaria (entorno de demostración).
**Versión:** 0.1.0 · **Fecha:** 2026-08-16

> **Importante.** Esta es una versión de demostración controlada (sandbox). **Todos los datos, personas, fondos y decisiones son ficticios.** No se recauda dinero real ni se publican datos reales.

---

## 1. Antes de empezar

### 1.1 Acceder a la plataforma
Abre en tu navegador: **http://localhost:3000**

Si ves un aviso de **"Conexión temporalmente interrumpida"**, no es un error tuyo: la plataforma evita mostrar cifras incompletas cuando no puede confirmar los datos. Espera unos segundos y pulsa **Reintentar**, o avisa al equipo técnico para que la base de datos esté activa.

### 1.2 ¿Quién usa la plataforma?
- **Ciudadanía y donantes:** no necesitan cuenta. Pueden ver necesidades, donar, reportar y hacer seguimiento.
- **Equipo operativo:** necesita cuenta y entra por **Ingresar**. Lo que puede hacer depende de su rol.

### 1.3 Códigos de color (en toda la aplicación)
| Color | Significado |
|---|---|
| 🟢 Verde | Verificado, completado o entregado |
| 🔵 Azul | Información territorial y logística |
| 🟠 Naranja | Requiere atención o revisión |
| 🔴 Rojo | Incidencia o urgencia comprobada |
| ⚪ Gris | Pendiente o inactivo |

Cada estado combina **ícono + texto + color** para que se entienda sin capacitación.

---

## 2. Para ciudadanía y donantes (sin cuenta)

### 2.1 Ver qué hace falta
1. En el inicio, ve a la sección **"Hoy hace falta"**.
2. Cada tarjeta muestra: categoría (Agua, Alimentos, Higiene, Refugio, Salud, Protección), ubicación **aproximada**, cuánto falta y el porcentaje ya cubierto.
3. Usa el **Mapa territorial** para explorar por zona. Los puntos **azules** son centros de acopio; los demás colores, necesidades. El mapa muestra zonas aproximadas, nunca direcciones exactas ni personas.

### 2.2 Hacer un aporte (5 pasos)
Pulsa **"Quiero ayudar"** en una necesidad o en el inicio, y sigue el asistente:

1. **Categoría / tipo de aporte** — en especie (bienes) o económico.
2. **Cantidad y descripción** — qué entregas y cuánto.
3. **Entrega** — elige el centro de acopio preferido.
4. **Tus datos de contacto** — quedan **privados**; no se publican.
5. **Confirmación** — recibes un **ticket con código y QR**.

> **Guarda tu código o el QR.** Es la única forma de seguir tu aporte. El QR **no** contiene datos personales, solo un código seguro.

Desde el ticket puedes **imprimir** el comprobante. (La descarga en PDF no está incluida en esta versión.)

### 2.3 Seguir mi aporte
1. Ve a **"Rastrear mi ayuda"** / **Seguimiento** (`/seguimiento`).
2. Ingresa tu **código**.
3. Verás la línea de hitos de tu aporte, de forma segura. Por privacidad **no** se muestran rutas ni personas.

### 2.4 Reportar una necesidad
1. Entra a **"Necesito reportar una necesidad"** (`/reportar`).
2. Elige la categoría y describe los hechos.
3. Los teléfonos o cuentas que incluyas se tratan como **privados** y pasan por moderación antes de cualquier verificación.
4. Envía. Tu reporte va a la **cola de verificación** del equipo; no se publica automáticamente.

> Por seguridad, se permiten hasta **5 reportes cada 10 minutos** desde un mismo origen.

### 2.5 Ver el impacto (Transparencia)
En **Transparencia** (`/transparencia`) encontrarás indicadores, barras de cobertura, distribución por estado y una tabla equivalente. Puedes **descargar el Excel público** (sin datos personales). Cada cifra incluye su metodología reproducible. **Ninguna cifra de impacto se infiere de promesas sin verificar.**

---

## 3. Para el equipo operativo (con cuenta)

### 3.1 Ingresar
1. Ve a **Ingresar** (`/ingresar`).
2. Escribe tu correo y contraseña.
3. Entrarás al **Centro operativo** (`/operaciones`).

**Cuentas de demostración** — contraseña común: `RutaSolidaria2026!`

| Correo | Persona | Rol(es) | Qué puede hacer |
|---|---|---|---|
| `admin@rutasolidaria.local` | Ana Coordinadora | Administración, Verificación, Auditoría | Verificar casos, ver todo, auditar |
| `aliado@rutasolidaria.local` | Luis Aliado | Aliado reportante | Registrar aportes como aliado autenticado |
| `bodega@rutasolidaria.local` | Marta Bodega | Centro de acopio + Logística | Recibir, clasificar, reservar, despachar y entregar |
| `solicita@rutasolidaria.local` | Sofía Solicitudes | Solicitudes de tesorería | Crear solicitudes de gasto |
| `aprueba@rutasolidaria.local` | Carlos Aprobaciones | Aprobación financiera | Aprobar y registrar pagos |

> El menú y el lanzador **solo muestran las acciones que tu rol permite**. Si no ves un módulo, tu cuenta no tiene ese permiso.

### 3.2 Centro operativo (pantalla "Mando")
Al entrar verás:
- **Acciones rápidas:** solo los recorridos habilitados para tu rol (revisar casos, recibir/mover bienes, revisar tesorería, consultar un código).
- **Indicadores:** necesidades en cola, aportes por revisar, lotes visibles y saldo conciliado.
- **Cola de verificación:** necesidades y aportes pendientes. Si tienes rol de verificación, cada caso muestra sus botones de acción.
- **Inventario reciente** y paneles de auditoría, tesorería y conciliación.

Puedes **Exportar Excel** operacional (respeta tu sesión y los permisos; omite contactos y notas internas).

### 3.3 Verificar casos (roles Verificación / Administración)
1. En la **Cola de verificación**, revisa cada necesidad o aporte.
2. Usa los botones del caso para aprobarlo, observarlo o marcarlo según corresponda.
3. **Aprobar una promesa no equivale a recibirla:** los bienes solo cuentan como inventario cuando se reciben físicamente en bodega.

### 3.4 Bodega y logística (roles Centro de acopio / Logística)
Entra a **Bodega y logística** (`/operaciones/bodega`). El recorrido guiado es:

`Buscar código o categoría → confirmar recepción → clasificar → reservar → despachar → registrar entrega → validar`

- **Recepción parcial:** puedes recibir una parte de lo prometido; el sistema crea **lotes**.
- **Compatibilidad automática:** solo permite asignar categorías/unidades compatibles.
- **Cola offline:** si pierdes conexión, las acciones se guardan localmente (máximo 50, validez 72 h, sin datos personales) y se sincronizan al reconectar.
- El transportador y las rutas reales permanecen **privados**.

### 3.5 Tesorería (roles Solicitudes / Aprobación / Auditoría)
Entra a **Tesorería** (`/operaciones/tesoreria`). Funciona con **separación de responsabilidades**:

- **Solicitante** (`solicita@…`) crea la solicitud de gasto.
- **Aprobador** (`aprueba@…`) la aprueba y registra el pago.
- La conciliación es **idempotente** y solo los movimientos **conciliados** afectan el saldo.
- Es un **entorno sandbox**: no se mueve dinero real.

### 3.6 Auditoría (rol Auditoría)
- Selecciona el evento y revisa la proyección.
- Reproduce los **eventos append-only** (no se borran; las correcciones agregan historia).
- Verifica la fórmula y el corte, y reporta cualquier excepción.

### 3.7 Cerrar sesión
Usa el botón de **cerrar sesión** (ícono de salida) en la esquina superior del Centro operativo. Las sesiones caducan automáticamente tras 12 horas o 2 horas de inactividad.

---

## 4. Preguntas frecuentes

**No puedo entrar / olvidé la contraseña.**
El auto-registro está bloqueado. Solicita al administrador que gestione tu acceso. El cambio de contraseña exige reautenticación.

**¿Por qué el mapa no muestra la dirección exacta?**
Por privacidad. El mapa solo usa zonas aproximadas y una conexión origen–destino, nunca la ubicación exacta ni la posición de un vehículo.

**Aparece "Conexión temporalmente interrumpida".**
La plataforma prefiere no mostrar cifras incompletas. Pulsa **Reintentar**; si persiste, avisa al equipo técnico (la base de datos debe estar activa).

**Perdí mi código de aporte.**
El código es la única forma de seguimiento y no contiene datos personales. Sin él no es posible rastrear el aporte; deberás registrar uno nuevo o consultar con el equipo operativo.

**¿Los datos son reales?**
No. Esta versión es una simulación con datos ficticios; no recauda dinero ni publica información real.

---

## 5. Soporte

- Documento técnico: `docs/DESCRIPCION_TECNICA.md`
- Estado y límites: `docs/STATUS.md`
- Mapa de pantallas: `docs/UX_MAP.md`

Para incidencias operativas, contacta al administrador del evento.
