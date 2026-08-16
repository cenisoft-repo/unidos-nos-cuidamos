# Plan WAF y antiabuso para entorno autorizado

No se ejecutó ningún comando remoto. El proyecto no está enlazado a Vercel ni a Supabase remoto.

## Fronteras reales

- Vercel puede proteger páginas, Server Actions y rutas Next.js como `/api/health` y `/api/exports/*`.
- El reporte ciudadano actual llama directamente a Supabase REST/RPC. Una regla WAF de Vercel **no** protege esa llamada.
- Antes de G2 debe elegirse una de dos rutas: rate limiting administrado delante de Supabase, o BFF Next.js con RPC firmada y revocación de la firma anónima directa. La gestión del secreto debe resolverse con un almacén aprobado, no con una clave versionada.
- Mientras se decide, PostgreSQL aplica honeypot y cuota 5/10 min por hash de origen/evento como defensa local.

## Despliegue gradual

1. Enlazar un preview sintético solo después de autorización y configurar variables por entorno.
2. Ejecutar `npm run preflight:deploy`; no continuar mientras responda `blocked`.
3. Inventariar rutas y tráfico esperado. Crear reglas en acción `log`, nunca `deny` inicialmente.
4. Publicar el borrador únicamente por una persona autorizada y observar falsos positivos.
5. Probar bloqueo en preview, volver a `log` en producción y luego endurecer con evidencia.
6. Mantener rollback: deshabilitar la regla o regresar a `log`; no pausar mitigaciones DDoS.

Ejemplo para revisión futura, no ejecutado:

```powershell
vercel firewall rules add "Observar abuso API" `
  --condition '{"type":"path","op":"pre","value":"/api"}' `
  --action log --yes
vercel firewall diff
```

Las cuotas finales se derivan de pruebas de carga y tráfico legítimo. No se configura bypass por un encabezado conocido ni se bloquea por user-agent/JA4 sin observar primero. La publicación de reglas y Attack Mode permanece en manos del operador autorizado.
