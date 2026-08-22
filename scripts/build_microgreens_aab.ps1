# Shortcut: Android App Bundle for Google Play.
# Same as: .\scripts\build_app.ps1 -AppId microgreens -SkipApk -SkipWeb -Aab
param(
  [switch]$SkipClean
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$buildArgs = @{
  AppId   = "microgreens"
  SkipApk = $true
  SkipWeb = $true
  Aab     = $true
}
if ($SkipClean) { $buildArgs.SkipClean = $true }

& (Join-Path $root "scripts\build_app.ps1") @buildArgs
if ($LASTEXITCODE -ne 0) {
  Write-Error "build_microgreens_aab.ps1 failed (exit $LASTEXITCODE)"
}
