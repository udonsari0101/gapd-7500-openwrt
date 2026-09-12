@echo off
setlocal

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs -Wait"
    exit /b %errorlevel%
)

pushd "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\disable-gapd-network.ps1"
set "GAPD_EXIT=%errorlevel%"
echo.
if "%GAPD_EXIT%"=="0" (
    echo GAPD network automation disabled and rolled back successfully.
) else (
    echo Disable/rollback failed with exit code %GAPD_EXIT%.
)
popd
pause
exit /b %GAPD_EXIT%
