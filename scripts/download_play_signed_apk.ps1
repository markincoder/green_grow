# Download a store-signed APK into dist/ (for RuStore upload).
# Local flutter APK uses the upload key — Play Protect warns. This file matches Play.
#
# One-time setup:
#   1. Google Cloud → IAM → service account → JSON key
#   2. Enable "Google Play Android Developer API"
#   3. Play Console → Users and permissions → invite the service account (Release to production / View app info + Releases)
#   4. Save JSON as secrets/play-service-account.json (gitignored)
#
# Usage:
#   .\scripts\download_play_signed_apk.ps1
#   .\scripts\download_play_signed_apk.ps1 -VersionCode 7 -Track internal
param(
  [string]$AppId = "microgreens",
  [int]$VersionCode = 0,
  [string]$Track = "internal",
  [string]$JsonKey = "",
  [string]$Out = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "apps.ps1")

$root = Get-AgronizerRoot
$cfg = Get-AgronizerApp -AppId $AppId
$distDir = Join-Path $root "dist"
if (-not (Test-Path $distDir)) {
  New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}
$distApk = Join-Path $distDir "$($cfg.apkFile)"

if ([string]::IsNullOrWhiteSpace($JsonKey)) {
  $JsonKey = Join-Path $root "secrets\play-service-account.json"
}
if (-not (Test-Path $JsonKey)) {
  Write-Error @"
Service account JSON not found: $JsonKey

Create a Play Console API service account, invite it as a user with Releases access,
and save the JSON key there (or pass -JsonKey).
"@
}

if ([string]::IsNullOrWhiteSpace($Out)) {
  $Out = $distApk
}

$py = Join-Path $PSScriptRoot "download_play_signed_apk.py"
$pyArgs = @(
  $py,
  "--package", "com.agronizer.greengrow",
  "--track", $Track,
  "--json-key", $JsonKey,
  "--out", $Out
)
if ($VersionCode -gt 0) {
  $pyArgs += @("--version-code", "$VersionCode")
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) { Write-Error "Python not found" }

& $python.Source @pyArgs
if ($LASTEXITCODE -ne 0) {
  Write-Error "download_play_signed_apk.py failed (exit $LASTEXITCODE)"
}

Write-Host "==> Dist APK: $Out"

$yandexApkDir = "C:\Users\Sergey\Documents\Yandex.Disk\agronizer"
if (-not (Test-Path $yandexApkDir)) {
  New-Item -ItemType Directory -Path $yandexApkDir -Force | Out-Null
}
$yandexApk = Join-Path $yandexApkDir (Split-Path $Out -Leaf)
Copy-Item $Out $yandexApk -Force
Write-Host "==> Yandex.Disk APK: $yandexApk"
