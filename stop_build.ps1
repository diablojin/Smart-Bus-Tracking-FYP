# Quick Stop Script - Stops all Flutter/Android build processes gracefully

Write-Host "Stopping Flutter/Android build processes..." -ForegroundColor Yellow

# Stop Gradle daemon (most important - releases file locks)
Write-Host "`n[1/3] Stopping Gradle daemon..." -ForegroundColor Cyan
if (Test-Path "android\gradlew.bat") {
    cd android
    .\gradlew --stop 2>$null
    cd ..
    Write-Host "   ✓ Gradle daemon stopped" -ForegroundColor Green
} else {
    Write-Host "   ⚠ Gradle wrapper not found" -ForegroundColor Yellow
}

# Wait for processes to release file handles
Write-Host "`n[2/3] Waiting for processes to release files..." -ForegroundColor Cyan
Start-Sleep -Seconds 2

# Kill any remaining Java/Gradle/Kotlin processes
Write-Host "`n[3/3] Killing remaining build processes..." -ForegroundColor Cyan
$processes = Get-Process | Where-Object {
    $_.ProcessName -like "*java*" -or 
    $_.ProcessName -like "*gradle*" -or 
    $_.ProcessName -like "*kotlin*"
}

if ($processes) {
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "   ✓ Stopped $($processes.Count) process(es)" -ForegroundColor Green
} else {
    Write-Host "   ✓ No processes found" -ForegroundColor Green
}

Write-Host "`n✓ All build processes stopped!" -ForegroundColor Green
Write-Host "You can now safely run 'flutter clean' or start a new build." -ForegroundColor Gray

