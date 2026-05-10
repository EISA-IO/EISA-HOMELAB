@echo off
setlocal
:: =============================================================================
:: EISA HOMELAB ULTIMATE — stop script
:: Delegates to scripts\stop.ps1.
::   STOP.bat            — interactive, asks about volumes/prune.
::   STOP.bat --volumes  — also wipe docker volumes (destructive).
::   STOP.bat --prune    — also `docker system prune -f` after stopping.
::   STOP.bat --volumes --prune  — both, no prompts.
:: =============================================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul

set "EXTRA_ARGS="
:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--volumes" set "EXTRA_ARGS=%EXTRA_ARGS% -Volumes"
if /I "%~1"=="--prune"   set "EXTRA_ARGS=%EXTRA_ARGS% -Prune"
shift
goto parse_args

:run
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
    set "PS=pwsh"
) else (
    set "PS=powershell"
)

%PS% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\stop.ps1" %EXTRA_ARGS%
set "EXITCODE=%ERRORLEVEL%"

popd >nul
endlocal & exit /b %EXITCODE%
