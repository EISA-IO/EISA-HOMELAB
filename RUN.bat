@echo off
setlocal
:: =============================================================================
:: EISA HOMELAB ULTIMATE — start script
:: Delegates to scripts\setup.ps1 which:
::   - checks Docker is running
::   - on first run, walks you through .env values + secret generation
::   - renders Caddyfile / Authelia config / SearXNG settings from .tmpl files
::   - runs `docker compose up -d` (with the `tunnel` profile if you opted in)
::
:: Re-prompt every value:        RUN.bat --reconfigure
:: Configure but don't start:    RUN.bat --no-start
:: =============================================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul

set "EXTRA_ARGS="
:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--reconfigure" set "EXTRA_ARGS=%EXTRA_ARGS% -Reconfigure"
if /I "%~1"=="--no-start"    set "EXTRA_ARGS=%EXTRA_ARGS% -NoStart"
shift
goto parse_args

:run
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
    set "PS=pwsh"
) else (
    set "PS=powershell"
)

%PS% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\setup.ps1" %EXTRA_ARGS%
set "EXITCODE=%ERRORLEVEL%"

popd >nul
endlocal & exit /b %EXITCODE%
