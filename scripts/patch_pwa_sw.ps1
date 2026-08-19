# Called by build_app.ps1 after `flutter build web`.
# Replace Flutter's uninstall-stub SW with the app PWA worker (fetch + push).
param(
  [Parameter(Mandatory = $true)]
  [Alias("App")]
  [string]$AppId,

  [string]$WebRoot = "build\web"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "apps.ps1")

$root = Get-AgronizerRoot
$cfg = Get-AgronizerApp -AppId $AppId
$flutterRoot = Join-Path $root (($cfg.flutterRoot -replace "/", "\").TrimStart("\"))
$sw = Join-Path $flutterRoot (Join-Path $WebRoot "flutter_service_worker.js")
$ours = Join-Path $flutterRoot "web\pwa-sw.js"
if (-not (Test-Path $ours)) {
  # Backward-compatible name used by microgreens
  $ours = Join-Path $flutterRoot "web\agronizer-sw.js"
}

if (-not (Test-Path $ours)) {
  Write-Error "Not found: web/pwa-sw.js or web/agronizer-sw.js under $flutterRoot"
}
if (-not (Test-Path (Split-Path $sw -Parent))) {
  Write-Error "Build output missing: $(Split-Path $sw -Parent) - run flutter build web first"
}

Copy-Item -Force $ours $sw

$verFile = Join-Path $flutterRoot (Join-Path $WebRoot "version.json")
if (Test-Path $verFile) {
  $ver = Get-Content -Raw $verFile | ConvertFrom-Json
  $name = [string]$ver.version
  $build = [string]$ver.build_number
  if (-not [string]::IsNullOrWhiteSpace($name)) {
    $cache = "microgreens-shell-$name+$build"
    $text = Get-Content -Raw $sw
    $text = [regex]::Replace($text, "const CACHE = '[^']+'", "const CACHE = '$cache'")
    Set-Content -Path $sw -Value $text -NoNewline -Encoding utf8
    Write-Host "PWA cache name -> $cache"
  }
}

Write-Host "Installed PWA SW ($($cfg.id)) -> $sw ($((Get-Item $sw).Length) bytes)"
