# How to Properly Stop Flutter/Android Builds

## The Problem
When you interrupt a build (Ctrl+C, close terminal, etc.) without properly stopping processes, you get:
- **File locks** - Gradle daemon holds locks on build files
- **Corrupted caches** - Kotlin/CMake caches get corrupted
- **Permission errors** - Processes lock files that need cleanup
- **Asset compression failures** - Build artifacts in inconsistent state

## Proper Way to Stop Builds

### Method 1: Let Flutter Finish or Stop Gracefully
1. **Wait for build to complete** - Best option if possible
2. **Press `q` in Flutter terminal** - Gracefully stops the app
3. **Use `flutter clean`** - Before restarting if you interrupted

### Method 2: Stop Gradle First (Recommended for Android builds)
```powershell
# In your project root
cd android
.\gradlew --stop
cd ..
```

This stops the Gradle daemon gracefully, releasing all file locks.

### Method 3: Use the Clean Script
Run the provided cleanup script:
```powershell
.\clean_build.ps1
```

## What Happens When You Don't Stop Properly

### ❌ Bad: Force Stop (Causes Your Errors)
- Press Ctrl+C multiple times
- Close terminal window
- Force kill processes in Task Manager
- **Result**: File locks, corrupted caches, permission errors

### ✅ Good: Graceful Stop
1. Press `q` in Flutter terminal (stops app gracefully)
2. Run `cd android && .\gradlew --stop` (stops Gradle)
3. Close terminal normally
4. **Result**: Clean shutdown, no locks

## Emergency Cleanup (When You Already Have Errors)

If you're already seeing errors, follow this order:

### Step 1: Stop All Processes
```powershell
# Stop Gradle
cd android
.\gradlew --stop
cd ..

# Kill any remaining processes
Get-Process | Where-Object {
    $_.ProcessName -like "*java*" -or 
    $_.ProcessName -like "*gradle*" -or 
    $_.ProcessName -like "*kotlin*"
} | Stop-Process -Force -ErrorAction SilentlyContinue
```

### Step 2: Wait for Processes to Release
```powershell
Start-Sleep -Seconds 3
```

### Step 3: Clean Everything
```powershell
flutter clean
.\clean_build.ps1  # Or run the cleanup script
```

### Step 4: Rebuild
```powershell
flutter pub get
flutter run -d emulator-5554
```

## Preventing Issues in the Future

### Best Practices:
1. **Always stop Gradle before closing terminal:**
   ```powershell
   cd android && .\gradlew --stop
   ```

2. **Use `q` to quit Flutter apps** instead of Ctrl+C

3. **If build hangs**, wait 30-60 seconds before force stopping

4. **Run cleanup script** before starting new builds after errors

5. **Close IDE/Android Studio** before running cleanup (they also lock files)

## Quick Reference

### Normal Stop (App is running):
```
Press 'q' in terminal
```

### Stop Build in Progress:
```
Press Ctrl+C once (wait)
cd android
.\gradlew --stop
```

### Clean Up After Errors:
```powershell
.\clean_build.ps1
```

### Check for Running Processes:
```powershell
Get-Process | Where-Object {$_.ProcessName -like "*java*" -or $_.ProcessName -like "*gradle*"}
```

## Why Your Errors Happened

Your specific errors were caused by:
1. **Kotlin cache locks** - "Storage already registered" = files still locked by previous build
2. **CMake permission denied** - ninja build tool couldn't access files locked by previous process
3. **Asset compression failures** - Build artifacts in inconsistent state from interrupted build
4. **Gradle execution permission** - File handles not released from interrupted Gradle daemon

All of these point to **processes not being properly terminated** before starting a new build.

