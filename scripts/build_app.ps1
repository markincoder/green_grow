# Build one Agronizer Flutter app: PWA → site/apps/<id>/, APK → dist/ (+ Yandex.Disk).
# Артефакты PWA отдаёт FastAPI из platform/push (STATIC_DIR=site). Flutter на сервер не нужен.
# APK кладётся в dist/ и копируется в Yandex.Disk\agronizer (на сайт больше не копируется).
param(
  [Parameter(Mandatory = $true)]
  [Alias("App")]
  [string]$AppId,

  [switch]$SkipApk,
  [switch]$SkipWeb,
  [switch]$SkipClean,
  [switch]$VerifyApk,
  [switch]$Aab
)

# Flutter 3.44 runs apkanalyzer after bundleRelease. JDK 25 makes that
# process fail even when the AAB already contains .sym metadata.
function Get-JbrHome {
  $candidates = @()
  foreach ($studio in @(
      (Join-Path $env:LOCALAPPDATA "Programs\Android Studio\jbr"),
      (Join-Path $env:ProgramFiles "Android\Android Studio\jbr")
    )) {
    $candidates += $studio
  }
  $jb = Join-Path $env:ProgramFiles "JetBrains"
  if (Test-Path $jb) {
    $candidates += Get-ChildItem $jb -Directory -ErrorAction SilentlyContinue |
      ForEach-Object { Join-Path $_.FullName "jbr" }
  }
  foreach ($jdkHome in $candidates) {
    if (Test-Path (Join-Path $jdkHome "bin\java.exe")) { return $jdkHome }
  }
  return $null
}

function Test-AabDebugSymbols {
  param([Parameter(Mandatory = $true)][string]$AabPath)
  $analyzer = Join-Path $env:LOCALAPPDATA "Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat"
  if (-not (Test-Path $analyzer)) { return $false }
  $jbr = Get-JbrHome
  $oldJavaHome = $env:JAVA_HOME
  try {
    if ($jbr) { $env:JAVA_HOME = $jbr }
    $out = & $analyzer files list $AabPath 2>&1 | Out-String
    return ($LASTEXITCODE -eq 0) -and
      ($out -match "libflutter\.so\.sym") -and
      ($out -match "libapp\.so\.sym")
  } finally {
    $env:JAVA_HOME = $oldJavaHome
  }
}

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "apps.ps1")

$root = Get-AgronizerRoot
Set-Location $root
$cfg = Get-AgronizerApp -AppId $AppId
$flutter = Get-FlutterBat
$flutterRoot = Join-Path $root (($cfg.flutterRoot -replace "/", "\").TrimStart("\"))
$siteApp = Join-Path $root (($cfg.sitePath -replace "/", "\").TrimStart("\"))
$distDir = Join-Path $root "dist"
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
Write-Host "Dist:    $distDir"
Write-Host "Href:    $baseHref"

if (-not (Test-Path $siteApp)) {
  New-Item -ItemType Directory -Path $siteApp -Force | Out-Null
}
if (-not (Test-Path $distDir)) {
  New-Item -ItemType Directory -Path $distDir -Force | Out-Null
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
  $destApk = Join-Path $distDir "$($cfg.apkFile)"

  if (-not $SkipClean -and (Test-Path $apkOutDir)) {
    Remove-Item -Recurse -Force $apkOutDir
  }

  & $flutter build apk --release --split-per-abi --target-platform android-arm64 -P disable-abi-filtering=true
  if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build apk failed (exit $LASTEXITCODE)"
  }
  if (-not (Test-Path $arm64Apk)) {
    Write-Error "Expected APK not found: $arm64Apk"
  }

  Copy-Item $arm64Apk $destApk -Force
  # Do not ship APK with the website — RuStore is the install channel.
  $staleSiteApk = Join-Path $siteApp "$($cfg.apkFile)"
  if (Test-Path $staleSiteApk) {
    Remove-Item -Force $staleSiteApk
    Write-Host "==> Removed stale site APK: $staleSiteApk"
  }
  $sizeMb = [math]::Round((Get-Item $destApk).Length / 1MB, 2)
  Write-Host "==> APK -> $destApk ($sizeMb MB)"

  $yandexApkDir = "C:\Users\Sergey\Documents\Yandex.Disk\agronizer"
  if (-not (Test-Path $yandexApkDir)) {
    New-Item -ItemType Directory -Path $yandexApkDir -Force | Out-Null
  }
  $yandexApk = Join-Path $yandexApkDir "$($cfg.apkFile)"
  Copy-Item $destApk $yandexApk -Force
  Write-Host "==> APK -> $yandexApk"

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

# —— App Bundle (Google Play) ——
if ($Aab) {
  Write-Host ""
  Write-Host "--- App Bundle ---"
  $keyProps = Join-Path $flutterRoot "android\key.properties"
  if (-not (Test-Path $keyProps)) {
    Write-Error "android/key.properties not found — AAB must be signed. Run .\scripts\create_android_keystore.ps1"
  }
  Set-Location $flutterRoot
  $aabOutDir = Join-Path $flutterRoot "build\app\outputs\bundle\release"
  $aabPath = Join-Path $aabOutDir "app-release.aab"

  if (-not $SkipClean) {
    foreach ($stale in @(
        $aabOutDir,
        (Join-Path $flutterRoot "build\app\intermediates\merged_native_libs"),
        (Join-Path $flutterRoot "build\app\intermediates\stripped_native_libs"),
        (Join-Path $flutterRoot "build\app\intermediates\cxx")
      )) {
      if (Test-Path $stale) { Remove-Item -Recurse -Force $stale }
    }
  }

  & $flutter build appbundle --release --target-platform android-arm64
  $aabExit = $LASTEXITCODE
  if (-not (Test-Path $aabPath)) {
    Write-Error "Expected AAB not found: $aabPath"
  }
  if ($aabExit -ne 0) {
    if (-not (Test-AabDebugSymbols $aabPath)) {
      Write-Error "flutter build appbundle failed (exit $aabExit)"
    }
    Write-Warning "Flutter apkanalyzer check failed (JDK 25); AAB debug symbols are present."
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($aabPath)
  try {
    $native = $zip.Entries | ForEach-Object { $_.FullName } |
      Where-Object { $_ -match '(^|/)base/lib/(armeabi-v7a|arm64-v8a|x86_64)/' }
    $abis = @(
      $native |
        ForEach-Object { [regex]::Match($_, '/lib/(armeabi-v7a|arm64-v8a|x86_64)/').Groups[1].Value } |
        Select-Object -Unique
    )
    if ($abis.Count -eq 0) {
      Write-Host "==> AAB native libs (all lib/ paths):"
      $zip.Entries | ForEach-Object { $_.FullName } |
        Where-Object { $_ -match '/lib/' } |
        Select-Object -First 30 |
        ForEach-Object { Write-Host "    $_" }
    }
    Write-Host ("==> AAB native ABIs: " + (($abis -join ", ") -replace '^$', '(none in base/lib)'))
    if ($abis -contains "armeabi-v7a" -or $abis -contains "x86_64") {
      Write-Error "AAB still contains extra ABIs ($($abis -join ', ')). Expected arm64-v8a only."
    }
  } finally {
    $zip.Dispose()
  }

  $destAab = Join-Path $distDir ([IO.Path]::ChangeExtension("$($cfg.apkFile)", ".aab"))
  if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
  }
  Copy-Item $aabPath $destAab -Force
  $sizeMb = [math]::Round((Get-Item $destAab).Length / 1MB, 2)
  Write-Host "==> AAB -> $destAab ($sizeMb MB)"
  Write-Host "Upload this file to Google Play Console (Production / Testing)."
}

# —— Web / PWA ——
if (-not $SkipWeb) {
  Write-Host ""
  Write-Host "--- Web / PWA ---"
  Set-Location $flutterRoot
  $buildWeb = Join-Path $flutterRoot "build\web"
  $patchScript = Join-Path $root "scripts\patch_pwa_sw.ps1"

  & $flutter build web --release --base-href $baseHref --no-wasm-dry-run --no-web-resources-cdn
  if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build web failed (exit $LASTEXITCODE)"
  }

  & $patchScript -AppId $AppId -WebRoot "build\web"
  if ($LASTEXITCODE -ne 0) {
    Write-Error "patch_pwa_sw.ps1 failed"
  }

  Write-Host "==> Copying PWA -> $siteApp"
  Get-ChildItem $siteApp -Force | Remove-Item -Recurse -Force

  Copy-Item -Path (Join-Path $buildWeb "*") -Destination $siteApp -Recurse -Force

  $webSrc = Join-Path $flutterRoot "web"
  foreach ($extra in @("push_client.js", "setup_gate.js", "manifest.json", "pwa_update.js")) {
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
