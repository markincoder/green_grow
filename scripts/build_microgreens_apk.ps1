# Shortcut: APK only. Same as: .\scripts\build_app.ps1 -AppId microgreens -SkipWeb
param(
  [switch]$SkipClean,
  [switch]$VerifyApk
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$buildArgs = @{
  AppId   = "microgreens"
  SkipWeb = $true
}
if ($SkipClean) { $buildArgs.SkipClean = $true }
if ($VerifyApk) { $buildArgs.VerifyApk = $true }

& (Join-Path $root "scripts\build_app.ps1") @buildArgs
if ($LASTEXITCODE -ne 0) {
  Write-Error "build_microgreens_apk.ps1 failed (exit $LASTEXITCODE)"
}
