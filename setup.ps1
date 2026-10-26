# =====================================================================
# setup.ps1
#
# Takes a freshly extracted FoodBook folder to a working Flutter
# project. Safe to re-run.
#
#   cd C:\Users\acyat\Desktop\FoodBook
#   .\setup.ps1
#
# If PowerShell refuses to run it ("running scripts is disabled"),
# unblock it for this session only:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# =====================================================================

$ErrorActionPreference = "Stop"

function Step($n, $text) { Write-Host "`n[$n] $text" -ForegroundColor Cyan }
function Ok($text)       { Write-Host "    OK  $text" -ForegroundColor Green }
function Warn($text)     { Write-Host "    --  $text" -ForegroundColor Yellow }

# ---------------------------------------------------------------------
Step 1 "Locating the Flutter SDK"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    if (Test-Path "C:\src\flutter\bin\flutter.bat") {
        $env:Path += ";C:\src\flutter\bin"
        Warn "flutter was not on PATH; added for this session only."
        Warn "To make it permanent, close VS Code entirely and reopen it."
    } else {
        Write-Host "`nFlutter is not installed. Run:" -ForegroundColor Red
        Write-Host "  git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter"
        Write-Host "then add C:\src\flutter\bin to your PATH and restart VS Code."
        exit 1
    }
}
Ok (flutter --version | Select-Object -First 1)

# ---------------------------------------------------------------------
Step 2 "Resolving dependencies"
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Ok "dependencies resolved"

# ---------------------------------------------------------------------
Step 3 "Checking platform scaffolding"
#
# Platform source/configuration is kept in the project. Generate the
# folders only when this script is used with a fresh source archive.
#
# iOS is omitted: building it requires macOS. The iPhone route is the
# web build installed from Safari via Add to Home Screen.

if (Test-Path ".\web") {
    Ok "platform folders already present; skipping"
} else {
    flutter create . --platforms=web,windows,android --project-name cookistrybook
    Ok "android, web and windows scaffolding created"
}

# ---------------------------------------------------------------------
Step 4 "Analyzing and testing the app"

Write-Host ""
flutter analyze
$analyzeExit = $LASTEXITCODE
if ($analyzeExit -ne 0) {
    Write-Host "Analysis failed." -ForegroundColor Red
    exit $analyzeExit
}

Write-Host ""
flutter test
$testExit = $LASTEXITCODE
if ($testExit -ne 0) {
    Write-Host "Tests failed." -ForegroundColor Red
    exit $testExit
}

Write-Host "Analysis and tests passed." -ForegroundColor Green
Write-Host ""
Write-Host "Next: configure a Supabase project before running the app."
Write-Host "See README.md, then launch with:"
Write-Host ""
Write-Host "  flutter run -d chrome ``"
Write-Host "    --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co ``"
Write-Host "    --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY"
Write-Host ""
Write-Host "Read VERIFICATION.md for what has actually been tested and what has not."
