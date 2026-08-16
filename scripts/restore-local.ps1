[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BackupDirectory,
  [switch]$ConfirmLocalDestructiveRestore
)

$ErrorActionPreference = "Stop"
function Get-Sha256([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
  } finally {
    $stream.Dispose()
    $sha.Dispose()
  }
}

if (-not $ConfirmLocalDestructiveRestore) {
  throw "La restauración reinicia únicamente la base local sintética. Repite con -ConfirmLocalDestructiveRestore."
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot ".local-backups"))
$resolvedBackup = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $BackupDirectory).Path)
if (-not $resolvedBackup.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Solo se restauran respaldos creados dentro de $allowedRoot"
}

$manifestPath = Join-Path $resolvedBackup "manifest.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$schemaFile = Join-Path $resolvedBackup $manifest.schema.file
$dataFile = Join-Path $resolvedBackup $manifest.data.file

if ((Get-Sha256 $schemaFile) -ne $manifest.schema.sha256) {
  throw "El checksum del esquema no coincide"
}
if ((Get-Sha256 $dataFile) -ne $manifest.data.sha256) {
  throw "El checksum de datos no coincide"
}

$startedAt = Get-Date
Push-Location $projectRoot
try {
  & npx.cmd supabase db reset
  if ($LASTEXITCODE -ne 0) { throw "Falló la reconstrucción desde migraciones" }

  $truncateSql = @'
do $$
declare targets text;
begin
  select string_agg(format('%I.%I', schemaname, tablename), ', ' order by tablename)
  into targets
  from pg_catalog.pg_tables
  where schemaname = 'public'
    and tablename <> 'spatial_ref_sys';
  if targets is not null then
    execute 'truncate table ' || targets || ' restart identity cascade';
  end if;
end
$$;
'@
  $truncateFile = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($truncateFile, $truncateSql, [System.Text.UTF8Encoding]::new($false))
    & npx.cmd supabase db query --local --file $truncateFile
    if ($LASTEXITCODE -ne 0) { throw "Falló la preparación del esquema para restaurar" }
  } finally {
    if (Test-Path -LiteralPath $truncateFile) { Remove-Item -LiteralPath $truncateFile -Force }
  }

  $projectMatch = Select-String -Path (Join-Path $projectRoot "supabase/config.toml") -Pattern '^project_id\s*=\s*"([^"]+)"'
  $projectId = $projectMatch.Matches[0].Groups[1].Value
  $databaseContainer = @(docker ps --filter "label=com.supabase.cli.project=$projectId" --filter "name=supabase_db_" --format "{{.Names}}")
  if ($LASTEXITCODE -ne 0 -or $databaseContainer.Count -ne 1) { throw "No se encontró un único contenedor PostgreSQL local" }

  $containerDataFile = "/tmp/ruta-solidaria-public-data.sql"
  try {
    & docker cp $dataFile "$($databaseContainer[0]):$containerDataFile"
    if ($LASTEXITCODE -ne 0) { throw "No fue posible copiar el respaldo al contenedor local" }
    & docker exec $databaseContainer[0] psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f $containerDataFile
    if ($LASTEXITCODE -ne 0) { throw "Falló la restauración de los datos" }
  } finally {
    & docker exec $databaseContainer[0] unlink $containerDataFile 2>$null
  }

  & npx.cmd supabase test db
  if ($LASTEXITCODE -ne 0) { throw "La base restaurada no superó pgTAP" }

  & npx.cmd supabase db query --local "select json_build_object('events', count(*)) from public.emergency_events;"
  if ($LASTEXITCODE -ne 0) { throw "Falló la comprobación final de recuperación" }
} finally {
  Pop-Location
}

$elapsed = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
Write-Output "Restauración local verificada en $elapsed segundos desde $resolvedBackup"
