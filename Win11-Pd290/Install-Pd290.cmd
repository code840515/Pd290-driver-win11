@echo off
setlocal
fltmc >nul 2>&1
if errorlevel 1 (
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
cd /d "%~dp0"
echo Installing the Pd290 Windows 11 driver and relay...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Pd290-New-Win11.ps1" -ConfirmAllChanges -SetDefaultPrinter
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" (
  echo Installation failed. Keep this window open and copy the error message.
) else (
  echo Installation completed. Test Pd290-Win11 from Windows Settings.
)
pause
exit /b %RESULT%