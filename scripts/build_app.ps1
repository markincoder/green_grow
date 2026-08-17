# Build one Agronizer Flutter app (APK and/or PWA) into site/apps/<id>/.
# Артефакты отдаёт FastAPI из platform/push (STATIC_DIR=site). Flutter на сервер не нужен.
param(
  [Parameter(Mandatory = $true)]
  [Alias("App")]
  [string]$AppId,

  [switch]$SkipApk,
  [switch]$SkipWeb,
  [switch]$SkipClean,
  [switch]$VerifyApk
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "apps.ps1")

$root = Get-AgronizerRoot
Set-Location $root
$cfg = Get-AgronizerApp -AppId $AppId
$flutter = Get-FlutterBat
$flutterRoot = Join-Path $root (($cfg.flutterRoot -replace "/", "\").TrimStart("\"))
$siteApp = Join-Path $root (($cfg.sitePath -replace "/", "\").TrimStart("\"))
$baseHref = "$($cfg.baseHref)"
if ([string]::IsNullOrWhiteSpace($baseHref)) {
  throw "App '$AppId' has empty baseHref in apps/apps.json"
}
if (-not $baseHref.StartsWith("/")) { $baseHref = "/$baseHref" }
if (-not $baseHref.EndsWith("/")) { $baseHref = "$baseHref/" }

if (-not (Test-Path (Join-Path $flutterRoot "pubspec.yaml"))) {
  Write-Error "Flutter project missing: $flutterRoot"
}

Write-Host "======== Build app: $($cfg.id) ($($cfg.name)) ========"
Write-Host "Flutter: $flutterRoot"
Write-Host "Site:    $siteApp"
Write-Host "Href:    $baseHref"

if (-not (Test-Path $siteApp)) {
  New-Item -ItemType Directory -Path $siteApp -Force | Out-Null
}

# —— APK ——
if (-not $SkipApk) {
  Write-Host ""
  Write-Host "--- APK ---"
  $keyProps = Join-Path $flutterRoot "android\key.properties"
  if (-not (Test-Path $keyProps)) {
    Write-Warning "android/key.properties not found — APK will be signed with the debug key. Play Protect will warn. Run .\scripts\create_android_keystore.ps1"
  }
  Set-Location $flutterRoot
  $apkOutDir = Join-Path $flutterRoot "build\app\outputs\flutter-apk"
  $arm64Apk = Join-Path $apkOutDir "app-arm64-v8a-release.apk"
  $destApk = Join-Path $siteApp "$($cfg.apkFile)"

  if (-not $SkipClean -and (Test-Path $apkOutDir)) {
    Remove-Item -Recurse -Force $apkOutDir
  }

  & $flutter build apk --release --split-per-abi
  if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build apk failed (exit $LASTEXITCODE)"
  }
  if (-not (Test-Path $arm64Apk)) {
    Write-Error "Expected APK not found: $arm64Apk"
  }

  Copy-Item $arm64Apk $destApk -Force
  $sizeMb = [math]::Round((Get-Item $destApk).Length / 1MB, 2)
  Write-Host "==> APK -> $destApk ($sizeMb MB)"

  if ($VerifyApk) {
    $apksigner = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools\36.0.0\apksigner.bat"
    if (-not (Test-Path $apksigner)) {
      $buildTools = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools"
      $latest = Get-ChildItem $buildTools -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
      if ($latest) { $apksigner = Join-Path $latest.FullName "apksigner.bat" }
    }
    if (Test-Path $apksigner) {
      Write-Host "==> Verifying signature..."
      & $apksigner verify --verbose $destApk
    } else {
      Write-Warning "apksigner not found - skip verify"
    }
  }
} else {
  Write-Host ""
  Write-Host "--- APK skipped ---"
}

# —— Web / PWA ——
if (-not $SkipWeb) {
  Write-Host ""
  Write-Host "--- Web / PWA ---"
  Set-Location $flutterRoot
  $buildWeb = Join-Path $flutterRoot "build\web"
  $patchScript = Join-Path $root "scripts\patch_pwa_sw.ps1"

  & $flutter build web --release --base-href $baseHref --no-wasm-dry-run
  if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build web failed (exit $LASTEXITCODE)"
  }

  & $patchScript -AppId $AppId -WebRoot "build\web"
  if ($LASTEXITCODE -ne 0) {
    Write-Error "patch_pwa_sw.ps1 failed"
  }

  Write-Host "==> Copying PWA -> $siteApp"
  Get-ChildItem $siteApp -Force |
    Where-Object { $_.Name -ne "$($cfg.apkFile)" } |
    Remove-Item -Recurse -Force

  Copy-Item -Path (Join-Path $buildWeb "*") -Destination $siteApp -Recurse -Force

  $webSrc = Join-Path $flutterRoot "web"
  foreach ($extra in @("push_client.js", "setup_gate.js", "manifest.json")) {
    $from = Join-Path $webSrc $extra
    if (Test-Path $from) {
      Copy-Item -Force $from (Join-Path $siteApp $extra)
    }
  }

  $sw = Join-Path $siteApp "flutter_service_worker.js"
  $index = Join-Path $siteApp "index.html"
  $manifest = Join-Path $siteApp "manifest.json"
  if (-not (Test-Path $index)) { Write-Error "Missing $index after copy" }
  if (-not (Test-Path $manifest)) { Write-Error "Missing $manifest after copy" }
  if (-not (Test-Path $sw)) { Write-Error "Missing $sw after copy" }

  $swText = Get-Content -Raw $sw
  if ($swText -match "registration\.unregister\(") {
    Write-Error "Deploy SW still contains unregister() - install/push will fail."
  }
  if ($swText -notmatch "addEventListener\(.fetch.") {
    Write-Error "Deploy SW missing fetch handler - Chrome will not offer Install."
  }
  if ($swText -notmatch "addEventListener\(.push.") {
    Write-Warning "Deploy SW missing push handler."
  }

  Write-Host "==> PWA ready: https://agronizer.ru$baseHref"
} else {
  Write-Host ""
  Write-Host "--- Web skipped ---"
}

Set-Location $root
Write-Host ""
Write-Host "======== Done: $($cfg.id) ========"
