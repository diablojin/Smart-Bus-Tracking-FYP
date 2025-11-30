# Clean Build Script for Smart Bus Tracking
# This script completely cleans all build artifacts and caches

Write-Host "Cleaning Flutter build..." -ForegroundColor Cyan
flutter clean

Write-Host "Stopping Gradle daemon..." -ForegroundColor Cyan
cd android
.\gradlew --stop
cd ..

Write-Host "Killing Java/Gradle/Kotlin processes..." -ForegroundColor Cyan
Get-Process | Where-Object {
    $_.ProcessName -like "*java*" -or 
    $_.ProcessName -like "*gradle*" -or 
    $_.ProcessName -like "*kotlin*"
} | Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 3

Write-Host "Removing build directories..." -ForegroundColor Cyan
if (Test-Path "build") { 
    Remove-Item "build" -Recurse -Force -ErrorAction SilentlyContinue 
}
if (Test-Path "android\.gradle") { 
    Remove-Item "android\.gradle" -Recurse -Force -ErrorAction SilentlyContinue 
}
if (Test-Path "android\app\build") { 
    Remove-Item "android\app\build" -Recurse -Force -ErrorAction SilentlyContinue 
}
if (Test-Path "android\build") { 
    Remove-Item "android\build" -Recurse -Force -ErrorAction SilentlyContinue 
}

Write-Host "Clearing Gradle user cache..." -ForegroundColor Cyan
if (Test-Path "$env:USERPROFILE\.gradle\caches") { 
    Remove-Item "$env:USERPROFILE\.gradle\caches" -Recurse -Force -ErrorAction SilentlyContinue 
}

Write-Host "Getting Flutter dependencies..." -ForegroundColor Cyan
flutter pub get

Write-Host "`nClean completed! You can now run: flutter run" -ForegroundColor Green

