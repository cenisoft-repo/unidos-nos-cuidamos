# Modelo de amenazas

## Fronteras

Navegador público → API Supabase → modelo operacional; navegador autenticado → RLS/membresía; servicios sandbox → funciones idempotentes; Storage privado → evidencia redactada/proyección.

## Abusos prioritarios

- Doxxing, teléfonos/cuentas en texto, evidencia sensible o ejecutable.
- Suplantación de aliado, enumeración de códigos, IDOR y elevación de rol.
- Doble recepción/asignación, stock negativo, colusión y borrado de eventos.
- Webhook repetido, monto declarado tratado como ingreso y autoaprobación.
- Pérdida offline, conflicto silencioso y publicación de ubicación exacta.

## Controles

RLS deny-by-default, RPC con checks de rol/estado, códigos de alta entropía, regex de moderación, Storage privado con MIME/tamaño, locks, claves idempotentes, eventos append-only y listas públicas explícitas. Rate limiting perimetral, escaneo antivirus y SIEM quedan obligatorios antes de G2.
