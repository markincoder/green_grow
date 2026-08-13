# Shared helpers for Agronizer multi-app builds.
$script:AppsRegistryPath = Join-Path (Split-Path -Parent $PSScriptRoot) "apps\apps.json"

function Get-AgronizerRoot {
  return (Split-Path -Parent $PSScriptRoot)
}

function Get-AgronizerApps {
  $root = Get-AgronizerRoot
  $path = Join-Path $root "apps\apps.json"
  if (-not (Test-Path $path)) {
    Write-Error "Apps registry not found: $path"
  }
  $json = Get-Content -Raw -Path $path | ConvertFrom-Json
  return @($json.apps)
}

function Get-AgronizerApp {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AppId
  )
  $apps = Get-AgronizerApps
  $app = $apps | Where-Object { $_.id -eq $AppId } | Select-Object -First 1
  if ($null -eq $app) {
    $ids = ($apps | ForEach-Object { $_.id }) -join ", "
    throw "Unknown app '$AppId'. Known: $ids"
  }
  if ([string]::IsNullOrWhiteSpace("$($app.flutterRoot)") -or
      [string]::IsNullOrWhiteSpace("$($app.sitePath)") -or
      [string]::IsNullOrWhiteSpace("$($app.baseHref)") -or
      [string]::IsNullOrWhiteSpace("$($app.apkFile)")) {
    throw "App '$AppId' is missing flutterRoot/sitePath/baseHref/apkFile in apps/apps.json"
  }
  return $app
}

function Get-FlutterBat {
  $flutter = "C:\src\flutter\bin\flutter.bat"
  if (Test-Path $flutter) { return $flutter }
  $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
  if (-not $flutterCmd) {
    Write-Error "Flutter not found. Install SDK or add flutter to PATH."
  }
  return $flutterCmd.Source
}
