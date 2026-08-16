[CmdletBinding()]
param(
  [string]$OutputRoot = ""
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

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$backupRoot = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  Join-Path $projectRoot ".local-backups"
} elseif ([System.IO.Path]::IsPathRooted($OutputRoot)) {
  [System.IO.Path]::GetFullPath($OutputRoot)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputRoot))
}

$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot ".local-backups"))
if (-not $backupRoot.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "El respaldo local debe quedar dentro de $allowedRoot"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$target = Join-Path $backupRoot $stamp
New-Item -ItemType Directory -Path $target -Force | Out-Null

$schemaFile = Join-Path $target "public-schema.sql"
$dataFile = Join-Path $target "public-data.sql"

& npx.cmd supabase db dump --local --schema public --file $schemaFile
if ($LASTEXITCODE -ne 0) { throw "Falló el snapshot del esquema local" }
& npx.cmd supabase db dump --local --schema public --data-only --use-copy --exclude public.anonymous_rate_limits --file $dataFile
if ($LASTEXITCODE -ne 0) { throw "Falló el snapshot de datos locales" }

$manifest = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  source = "supabase-local-synthetic"
  recovery_mode = "migrations-then-public-data"
  schema = [ordered]@{ file = "public-schema.sql"; sha256 = (Get-Sha256 $schemaFile) }
  data = [ordered]@{ file = "public-data.sql"; sha256 = (Get-Sha256 $dataFile) }
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $target "manifest.json")

Write-Output $target
