# Local FastAPI: portal + PWA/APK from site/ + /push/
# Usage: .\scripts\run_local.ps1
#        .\scripts\run_local.ps1 -Port 3000
param(
  [int]$Port = 3000
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "apps.ps1")

$root = Get-AgronizerRoot
$push = Join-Path $root "platform\push"
$req = Join-Path $push "requirements.txt"
$venvPy = Join-Path $push ".venv\Scripts\python.exe"
$site = Join-Path $root "site"

if (-not (Test-Path (Join-Path $push "main.py"))) {
  Write-Error "FastAPI app missing: $push\main.py"
}
if (-not (Test-Path (Join-Path $site "index.html"))) {
  Write-Error "Portal missing: $site\index.html"
}

if (-not (Test-Path $venvPy)) {
  Write-Host "Creating venv in $push\.venv"
  python -m venv (Join-Path $push ".venv")
  if ($LASTEXITCODE -ne 0) { Write-Error "python -m venv failed (need Python 3.12+)" }
}

Write-Host "Installing Python deps..."
& $venvPy -m pip install -q -r $req
if ($LASTEXITCODE -ne 0) { Write-Error "pip install failed" }

$env:DATA_DIR = Join-Path $push "data"
$env:STATIC_DIR = $site
$env:PORT = "$Port"

Write-Host "Agronizer FastAPI  http://127.0.0.1:$Port/"
Write-Host "  portal   http://127.0.0.1:$Port/"
Write-Host "  PWA      http://127.0.0.1:$Port/apps/microgreens/"
Write-Host "  push     http://127.0.0.1:$Port/push/health"
Write-Host ""

Set-Location $push
$uvicorn = @("main:app", "--host", "127.0.0.1", "--port", "$Port", "--reload")
$envFile = Join-Path $push ".env"
if (Test-Path $envFile) {
  $uvicorn += @("--env-file", $envFile)
}
& $venvPy -m uvicorn @uvicorn
