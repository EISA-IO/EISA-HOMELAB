@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title EISA Homelab - Start
color 0A
mode con: cols=120 lines=32 >nul 2>&1

:: =============================================================================
:: EISA HOMELAB - One-click start
:: Runs setup.ps1 -StartOnly (auto-launches Docker Desktop if needed, renders
:: configs, brings the chosen profiles up, wires the *arr/Seerr stack) and
:: then opens Heimdall in your default browser.
::
:: Use WINDOWS-HOMELAB-MANAGER.BAT for the menu-driven first-run wizard,
:: stop/list, and the LLM manager. start.bat is intentionally a no-questions
:: launcher — double-click and walk away.
:: =============================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "SETUP_PS1=%SCRIPT_DIR%\files\scripts\setup.ps1"
set "HEIMDALL_URL=http://hub.localhost"

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (set "PS=pwsh") else (set "PS=powershell")

cls
echo.
echo  ============================================================
echo   EISA HOMELAB - Starting
echo  ============================================================
echo.
echo   Docker auto-start  -  stack up  -  Heimdall dashboard
echo.

if not exist "%SETUP_PS1%" (
    echo   [X] Could not find setup.ps1 at:
    echo       %SETUP_PS1%
    echo       Run start.bat from the homelab repo root.
    echo.
    pause
    exit /b 1
)

%PS% -NoProfile -ExecutionPolicy Bypass -File "%SETUP_PS1%" -StartOnly
set "EXITCODE=!ERRORLEVEL!"

if "!EXITCODE!"=="0" (
    echo.
    echo   [OK] Stack started. Opening Heimdall in your browser...
    start "" "%HEIMDALL_URL%"
    :: Brief hold so the user can see the OK before the window closes.
    timeout /t 3 /nobreak >nul
    exit /b 0
) else (
    echo.
    echo   [!] Start failed with code !EXITCODE!.
    echo       Open WINDOWS-HOMELAB-MANAGER.BAT for diagnostics, stop/list,
    echo       and the first-run wizard.
    echo.
    pause
    exit /b !EXITCODE!
)
