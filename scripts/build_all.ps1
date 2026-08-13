# Build all registered Agronizer apps.
# Docker-образ собирайте из корня стека (рядом с папкой agronizer/), не из этого репо.
# По умолчанию Docker не трогаем; для сборки образа: -Docker (из корня стека).
param(
  [string]$App = "",
  [switch]$SkipApk,
  [switch]$SkipWeb,
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
  if ("$($target.id)" -eq "microgreens") {
    if (-not $SkipApk) {
      $apkArgs = @{}
      if ($VerifyApk) { $apkArgs.VerifyApk = $true }
      & (Join-Path $root "scripts\build_microgreens_apk.ps1") @apkArgs
      if ($LASTEXITCODE -ne 0) {
        Write-Error "build_microgreens_apk.ps1 failed"
      }
    } else {
      Write-Host ""
      Write-Host "--- microgreens APK skipped ---"
    }

    if (-not $SkipWeb) {
      & (Join-Path $root "scripts\build_microgreens_web.ps1")
      if ($LASTEXITCODE -ne 0) {
        Write-Error "build_microgreens_web.ps1 failed"
      }
    } else {
      Write-Host ""
      Write-Host "--- microgreens Web skipped ---"
    }
    continue
  }

  $buildArgs = @{
    AppId = "$($target.id)"
    SkipApk = $SkipApk
    SkipWeb = $SkipWeb
  }
  if ($VerifyApk) { $buildArgs.VerifyApk = $true }

  & (Join-Path $root "scripts\build_app.ps1") @buildArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Error "build_app.ps1 failed for $($target.id)"
  }
}

if ($Docker) {
  Write-Host ""
  Write-Host "--- Docker image agronizer ---"
  Write-Warning "Ожидается запуск из корня стека, где есть папка .\agronizer\ и docker-compose.yml"
  docker compose build agronizer
  if ($LASTEXITCODE -ne 0) { Write-Error "docker compose build agronizer failed" }

  if ($Up) {
    Write-Host ""
    Write-Host "--- docker compose up -d agronizer ---"
    docker compose up -d agronizer
    if ($LASTEXITCODE -ne 0) { Write-Error "docker compose up failed" }
  }
} else {
  Write-Host ""
  Write-Host "--- Docker skipped (в корне стека: docker compose build agronizer) ---"
}

Write-Host ""
Write-Host "======== Done ========"
Write-Host "Project:     .\  (на сервере папка agronizer/ рядом с docker-compose.yml)"
Write-Host "Site:        .\site\"
Write-Host "Push data:   .\platform\push\data\"
Write-Host "Portal:      https://agronizer.ru/"
foreach ($target in $targets) {
  Write-Host ("App {0}:     https://agronizer.ru{1}" -f $target.id, $target.baseHref)
}
Write-Host "Push health: https://agronizer.ru/push/health"
Write-Host "Deploy:      залить в stack/agronizer/  затем:"
Write-Host "             cd /path/to/stack && docker compose restart agronizer"
