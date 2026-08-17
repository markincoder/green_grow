# Shortcut: PWA only. Same as: .\scripts\build_app.ps1 -AppId microgreens -SkipApk
param(
  [switch]$SkipClean
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$buildArgs = @{
  AppId   = "microgreens"
  SkipApk = $true
}
if ($SkipClean) { $buildArgs.SkipClean = $true }

& (Join-Path $root "scripts\build_app.ps1") @buildArgs
if ($LASTEXITCODE -ne 0) {
  Write-Error "build_microgreens_web.ps1 failed (exit $LASTEXITCODE)"
}
