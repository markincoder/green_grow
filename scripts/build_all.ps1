# Build all apps from apps/apps.json into site/apps/<id>/.
# Docker-образ FastAPI собирайте из корня стека (рядом с папкой agronizer/), не из этого репо.
# По умолчанию Docker не трогаем; -Docker / -Up — только если найден docker-compose.yml стека.
param(
  [Alias("AppId")]
  [string]$App = "",
  [switch]$SkipApk,
  [switch]$SkipWeb,
  [switch]$SkipClean,
  [switch]$Docker,
  [switch]$VerifyApk,
  [switch]$Up
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "apps.ps1")

$root = Get-AgronizerRoot
Set-Location $root

Write-Host "======== Agronizer multi-app build ========"

$targets = if ($App) {
  @(Get-AgronizerApp -AppId $App)
} else {
  Get-AgronizerApps
}

foreach ($target in $targets) {
  $buildArgs = @{
    AppId    = "$($target.id)"
    SkipApk  = $SkipApk
    SkipWeb  = $SkipWeb
  }
  if ($SkipClean) { $buildArgs.SkipClean = $true }
  if ($VerifyApk) { $buildArgs.VerifyApk = $true }

  & (Join-Path $root "scripts\build_app.ps1") @buildArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Error "build_app.ps1 failed for $($target.id)"
  }
}

if ($Docker) {
  $stack = Get-AgronizerStackRoot
  if (-not $stack) {
    Write-Error "docker-compose.yml не найден. -Docker запускайте там, где лежит стек (рядом с папкой agronizer/)."
  }
  Write-Host ""
  Write-Host "--- Docker image agronizer (FastAPI) ---"
  Write-Host "Stack: $stack"
  $composeCtx = Join-Path $stack "agronizer\platform\push"
  if (-not (Test-Path $composeCtx)) {
    Write-Warning "В стеке нет agronizer\platform\push. На сервере compose собирает ./agronizer/platform/push — запускайте -Docker из корня стека, не из клона репо."
  }
  Push-Location $stack
  try {
    docker compose build agronizer
    if ($LASTEXITCODE -ne 0) { Write-Error "docker compose build agronizer failed" }
    if ($Up) {
      Write-Host ""
      Write-Host "--- docker compose up -d agronizer ---"
      docker compose up -d agronizer
      if ($LASTEXITCODE -ne 0) { Write-Error "docker compose up failed" }
    }
  } finally {
    Pop-Location
  }
} else {
  Write-Host ""
  Write-Host "--- Docker skipped (в корне стека: docker compose build agronizer) ---"
}

Write-Host ""
Write-Host "======== Done ========"
Write-Host "Project:     $root"
Write-Host "Site:        $(Join-Path $root 'site')"
Write-Host "FastAPI:     $(Join-Path $root 'platform\push')"
Write-Host "Portal:      https://agronizer.ru/"
foreach ($target in $targets) {
  Write-Host ("App {0}:     https://agronizer.ru{1}" -f $target.id, $target.baseHref)
}
Write-Host "Push health: https://agronizer.ru/push/health"
Write-Host "Deploy site: залить site/  ->  docker compose restart agronizer"
Write-Host "Deploy API:  залить platform/push (без data/, .venv)  ->  docker compose build agronizer && docker compose up -d agronizer"
Write-Host "SQLite/VAPID: том agronizer_data (/data), rebuild его не затирает"
