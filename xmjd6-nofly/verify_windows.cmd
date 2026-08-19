@echo off
setlocal EnableExtensions
chcp 65001 >nul
set "ROOT=%~dp0"
set "FAILED=0"

call :require "xmjd6.schema.yaml"
call :require "xmjd6.extended.dict.yaml"
call :require "default.yaml"
call :require "default.custom.yaml"
call :require "weasel.custom.yaml"
call :require "symbols.yaml"
call :require "conversion-report.txt"
call :require "lua\xmjd6"
call :require "opencc"

if exist "%ROOT%build\" (
  echo [FAIL] Package must not contain a build directory.
  set "FAILED=1"
)

if "%FAILED%"=="0" (
  echo [OK] Package structure is complete. No files were installed or changed.
) else (
  echo [FAIL] Package verification failed.
)
exit /b %FAILED%

:require
if not exist "%ROOT%%~1" (
  echo [MISS] %~1
  set "FAILED=1"
) else (
  echo [ OK ] %~1
)
exit /b 0
