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

function Read-Utf8File([string]$Path) {
  $sr = New-Object System.IO.StreamReader($Path, [System.Text.UTF8Encoding]::new($false), $true)
  try { return $sr.ReadToEnd() } finally { $sr.Close() }
}

function Write-Utf8File([string]$Path, [string]$Text) {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

Copy-Item -Force $ours $sw

$webOut = Split-Path $sw -Parent
$verFile = Join-Path $webOut "version.json"
$stamp = Get-Date -Format "yyyyMMddHHmmss"
if (Test-Path $verFile) {
  $ver = Get-Content -Raw $verFile | ConvertFrom-Json
  $name = [string]$ver.version
  $build = [string]$ver.build_number
  if (-not [string]::IsNullOrWhiteSpace($name)) {
    $stamp = "$name+$build"
  }
}
$mainJs = Join-Path $webOut "main.dart.js"
if (Test-Path $mainJs) {
  $hash = (Get-FileHash $mainJs -Algorithm MD5).Hash.Substring(0, 8).ToLowerInvariant()
  $stamp = "$stamp-$hash"
}

$cache = "microgreens-shell-$stamp"
$text = Read-Utf8File $sw
$text = [regex]::Replace($text, "const CACHE = '[^']+'", "const CACHE = '$cache'")
Write-Utf8File $sw $text
Write-Host "PWA cache name -> $cache"

$boot = Join-Path $webOut "flutter_bootstrap.js"
if (Test-Path $boot) {
  $bootText = Read-Utf8File $boot
  $bootText = [regex]::Replace(
    $bootText,
    '_flutter\.loader\.load\(\s*\{.*?\}\s*\);',
    '_flutter.loader.load({ config: { canvasKitBaseUrl: "canvaskit/" } });',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  Write-Utf8File $boot $bootText
  Write-Host "Flutter bootstrap: skip SW wait, local CanvasKit"
}

$index = Join-Path $webOut "index.html"
if (Test-Path $index) {
  $html = Read-Utf8File $index
  $html = [regex]::Replace(
    $html,
    'src="flutter_bootstrap\.js[^"]*"',
    "src=`"flutter_bootstrap.js?v=$stamp`""
  )
  $html = [regex]::Replace(
    $html,
    'src="pwa_update\.js[^"]*"',
    "src=`"pwa_update.js?v=$stamp`""
  )
  Write-Utf8File $index $html
}

Write-Host "Installed PWA SW ($($cfg.id)) -> $sw ($((Get-Item $sw).Length) bytes)"
