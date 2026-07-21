@echo off
setlocal EnableExtensions

rem Apply Windows-specific Rime default configuration files.
rem This script must be placed in the Rime user data directory.

chcp 65001 >nul 2>nul

set "RIME_DIR=%~dp0"
set "SRC_DEFAULT=%RIME_DIR%default_win.yaml"
set "SRC_CUSTOM=%RIME_DIR%default.custom_win.yaml"
set "DST_DEFAULT=%RIME_DIR%default.yaml"
set "DST_CUSTOM=%RIME_DIR%default.custom.yaml"
set "BACKUP_DIR=%RIME_DIR%backups"

echo.
echo [Rime] Applying Windows default configuration...
echo Rime directory: "%RIME_DIR%"
echo.

if not exist "%SRC_DEFAULT%" (
  echo ERROR: Source file not found: "%SRC_DEFAULT%"
  goto :fail
)

if not exist "%SRC_CUSTOM%" (
  echo ERROR: Source file not found: "%SRC_CUSTOM%"
  goto :fail
)

for /f %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format yyyyMMdd-HHmmss" 2^>nul') do set "TS=%%I"
if not defined TS (
  set "TS=%DATE%-%TIME%"
  set "TS=%TS:/=-%"
  set "TS=%TS::=-%"
  set "TS=%TS: =0%"
  set "TS=%TS:.=-%"
)

if not exist "%BACKUP_DIR%" (
  mkdir "%BACKUP_DIR%" || goto :fail
)

if exist "%DST_DEFAULT%" (
  copy /Y "%DST_DEFAULT%" "%BACKUP_DIR%\default.yaml.%TS%.bak" >nul || goto :fail
  echo Backed up default.yaml
)

if exist "%DST_CUSTOM%" (
  copy /Y "%DST_CUSTOM%" "%BACKUP_DIR%\default.custom.yaml.%TS%.bak" >nul || goto :fail
  echo Backed up default.custom.yaml
)

copy /Y "%SRC_DEFAULT%" "%DST_DEFAULT%" >nul || goto :fail
copy /Y "%SRC_CUSTOM%" "%DST_CUSTOM%" >nul || goto :fail

echo.
echo Done.
echo Replaced:
echo   default.yaml        ^<- default_win.yaml
echo   default.custom.yaml ^<- default.custom_win.yaml
echo.
echo Backup directory:
echo   "%BACKUP_DIR%"
echo.
echo Please redeploy Rime/Weasel manually after this.
echo.
pause
exit /b 0

:fail
echo.
echo Failed. No further changes were applied after the error above.
echo.
pause
exit /b 1
