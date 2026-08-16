# Preparación operativa del sandbox

Este runbook cubre únicamente la base local con datos sintéticos. No autoriza despliegue, uso de datos reales, marcas, recaudo ni restauración sobre un proyecto remoto.

## Controles ejecutables

- `npm run preflight:local`: verifica URLs de loopback, plantilla sin `service_role`, secretos/respaldos ignorados y ausencia de enlaces remotos.
- `npm run verify`: preflight, lint, TypeScript, 13 unitarias, 94 pgTAP, RLS, concurrencia, build y 24 pruebas de navegador.
- `GET /api/health`: responde `no-store`, request ID, Server-Timing y estado de PostgreSQL.
- Logs: las rutas de salud/Excel y los errores servidor emiten JSON con operación, resultado, estado y duración; nunca registran cuerpo, correo, teléfono, URL con query ni secretos.
- Auth: alta pública cerrada, proveedor email habilitado solo para cuentas provisionadas, contraseña robusta, cambio sensible con reautenticación, sesiones 12 h/2 h.

## Backup local

```powershell
npm run db:backup
```

El comando escribe en `.local-backups/<fecha>/` un snapshot del esquema público, datos públicos sintéticos y `manifest.json` con SHA-256. Los contadores antiabuso se excluyen por ser estado efímero. La carpeta está ignorada por Git.

## Restauración local

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/restore-local.ps1 `
  -BackupDirectory ".local-backups/<fecha>" `
  -ConfirmLocalDestructiveRestore
```

La restauración valida checksums, ejecuta migraciones/seed, trunca solo el esquema público local, restaura los datos y exige pgTAP verde. El 15 de agosto de 2026 se restauró el snapshot `20260815-175403`: 94 pruebas pasaron, quedó un evento sintético y el RTO observado fue 57,1 s. El RPO local equivale al momento del snapshot manual.

Antes de G2 deben definirse retención, frecuencia, cifrado, copia externa, PITR, responsables, RPO/RTO contractuales y un ensayo sobre staging autorizado. Este resultado local no demuestra recuperación remota.

## Preflight de despliegue

```powershell
npm run preflight:deploy
```

El comando es de solo lectura. Debe devolver `blocked` mientras falten variables remotas, enlaces Vercel/Supabase o brechas G2. No enlaza, no crea recursos, no publica WAF y no despliega. Tras autorización, las reglas perimetrales deben empezar en observación, validarse contra tráfico sintético y publicarse por una persona autorizada.
