# Create a release upload keystore for the microgreens Android APK.
# Writes android/upload-keystore.jks and android/key.properties (both gitignored).
# Does not overwrite an existing keystore.
param(
  [string]$Alias = "upload",
  [string]$DName = "CN=Agronizer, OU=Microgreens, O=Agronizer, C=RU"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$android = Join-Path $root "apps\microgreens\android"
$keystore = Join-Path $android "upload-keystore.jks"
$props = Join-Path $android "key.properties"

if (Test-Path $keystore) {
  Write-Host "Keystore already exists: $keystore"
  Write-Host "Not overwriting. Delete it only if you intend to lose the old signing identity."
  exit 0
}

function Find-Keytool {
  $candidates = @()
  if ($env:JAVA_HOME) {
    $candidates += (Join-Path $env:JAVA_HOME "bin\keytool.exe")
  }
  $studio = Join-Path $env:LOCALAPPDATA "Programs\Android Studio\jbr\bin\keytool.exe"
  $candidates += $studio
  $candidates += (Join-Path $env:ProgramFiles "Android\Android Studio\jbr\bin\keytool.exe")
  $cmd = Get-Command keytool -ErrorAction SilentlyContinue
  if ($cmd) { $candidates += $cmd.Source }
  foreach ($p in $candidates) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  throw "keytool not found. Install JDK 17+ or Android Studio."
}

$keytool = Find-Keytool
$alphabet = (48..57 + 65..90 + 97..122 | ForEach-Object { [char]$_ }) -join ""
$passChars = 1..24 | ForEach-Object { $alphabet[(Get-Random -Maximum $alphabet.Length)] }
$pass = -join $passChars

Write-Host "Creating $keystore"
& $keytool -genkeypair -v `
  -keystore $keystore `
  -storetype JKS `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias $Alias `
  -storepass $pass `
  -keypass $pass `
  -dname $DName
if ($LASTEXITCODE -ne 0) { Write-Error "keytool -genkeypair failed" }

@"
storePassword=$pass
keyPassword=$pass
keyAlias=$Alias
storeFile=../upload-keystore.jks
"@ | Set-Content -Path $props -Encoding ASCII

Write-Host ""
Write-Host "Wrote $props (gitignored). Back up both files somewhere safe."
Write-Host "Losing them means you cannot update the same Android app."
Write-Host ""
Write-Host "SHA-256 of the signing cert (for Google Play / Android Developer Console):"
& $keytool -list -v -keystore $keystore -alias $Alias -storepass $pass |
  Select-String -Pattern "SHA256:"
