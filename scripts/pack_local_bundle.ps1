# Pack site/ + FastAPI into a zip for local run on another PC (no Flutter needed).
# Usage:
#   .\scripts\pack_local_bundle.ps1
#   .\scripts\pack_local_bundle.ps1 -OutDir $env:USERPROFILE\Desktop
#   .\scripts\pack_local_bundle.ps1 -BuildWeb
#   .\scripts\pack_local_bundle.ps1 -IncludeApk
param(
  [string]$OutDir = "",
  [switch]$BuildWeb,
  [switch]$IncludeApk
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "apps.ps1")

$root = Get-AgronizerRoot
$site = Join-Path $root "site"
$push = Join-Path $root "platform\push"
$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$bundleName = "agronizer-local-$stamp"

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path $root "dist"
}
if (-not (Test-Path $OutDir)) {
  New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$zipPath = Join-Path $OutDir "$bundleName.zip"
$stage = Join-Path ([System.IO.Path]::GetTempPath()) "agronizer-pack-$stamp"

if ($BuildWeb) {
  Write-Host "==> Building PWA (microgreens)..."
  & (Join-Path $root "scripts\build_microgreens_web.ps1")
  if ($LASTEXITCODE -ne 0) {
    Write-Error "build_microgreens_web.ps1 failed (exit $LASTEXITCODE)"
  }
}

if (-not (Test-Path (Join-Path $site "index.html"))) {
  Write-Error "Missing site\index.html. Build first or pass -BuildWeb."
}
if (-not (Test-Path (Join-Path $site "apps\microgreens\index.html"))) {
  Write-Error "Missing site\apps\microgreens\. Run: .\scripts\build_microgreens_web.ps1  or pass -BuildWeb."
}
$requiredPush = @(
  "main.py", "store.py", "auth.py", "access.py", "db.py",
  "requirements.txt", ".env.example", ".env"
)
foreach ($f in $requiredPush) {
  if (-not (Test-Path (Join-Path $push $f))) {
    Write-Error "Missing platform\push\$f"
  }
}

if (Test-Path $stage) {
  Remove-Item -Recurse -Force $stage
}
New-Item -ItemType Directory -Path $stage | Out-Null
$dest = Join-Path $stage $bundleName
New-Item -ItemType Directory -Path $dest | Out-Null

Write-Host "==> Staging $bundleName ..."

# site/
$siteDest = Join-Path $dest "site"
Copy-Item -Path $site -Destination $siteDest -Recurse -Force
if (-not $IncludeApk) {
  Get-ChildItem -Path $siteDest -Filter *.apk -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Force
}

# platform/push (code + env; skip venv/data/cache)
$pushDest = Join-Path $dest "platform\push"
New-Item -ItemType Directory -Path $pushDest -Force | Out-Null
Get-ChildItem -Path $push -File -Filter *.py | ForEach-Object {
  Copy-Item -Path $_.FullName -Destination (Join-Path $pushDest $_.Name) -Force
}
foreach ($f in @("requirements.txt", ".env.example", ".env", "Dockerfile")) {
  $src = Join-Path $push $f
  if (Test-Path $src) {
    Copy-Item -Path $src -Destination (Join-Path $pushDest $f) -Force
  }
}
Write-Host "    included platform\push\.env (secrets - do not share publicly)"
Write-Host ("    python modules: " + ((Get-ChildItem $pushDest -Filter *.py).Name -join ", "))

# scripts needed to run
$scriptsDest = Join-Path $dest "scripts"
New-Item -ItemType Directory -Path $scriptsDest -Force | Out-Null
Copy-Item -Path (Join-Path $root "scripts\run_local.ps1") -Destination $scriptsDest -Force
Copy-Item -Path (Join-Path $root "scripts\apps.ps1") -Destination $scriptsDest -Force

# Russian text lives in a separate UTF-8 file (not in this .ps1).
# PS 5.1 misreads Cyrillic in scripts without BOM and corrupts zip contents.
# ASCII filename only: Compress-Archive breaks Cyrillic entry names.
$readmeSrc = Join-Path $PSScriptRoot "pack_local_bundle_README.txt"
if (-not (Test-Path $readmeSrc)) {
  Write-Error "Missing $readmeSrc"
}
$readme = [System.IO.File]::ReadAllText($readmeSrc, [System.Text.UTF8Encoding]::new($false))
$readme = $readme.Replace("{{STAMP}}", $stamp)
# UTF-16 LE + BOM — Notepad / Explorer open Russian correctly on Windows
$readmePath = Join-Path $dest "README-LOCAL.txt"
[System.IO.File]::WriteAllText($readmePath, $readme, [System.Text.Encoding]::Unicode)

if (Test-Path $zipPath) {
  Remove-Item -Force $zipPath
}

Write-Host "==> Zipping -> $zipPath"
Compress-Archive -Path $dest -DestinationPath $zipPath -CompressionLevel Optimal

Remove-Item -Recurse -Force $stage

$sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host ""
Write-Host "Ready: $zipPath ($sizeMb MB)"
Write-Host "Give this zip to the other PC; open README-LOCAL.txt inside."
