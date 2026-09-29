@echo off
REM ============================================================
REM  HCIS - step 2: restart the API so it can see the new columns
REM
REM  Double-click this. It calls reload-api.ps1 for you, so there
REM  is no right-clicking and no execution-policy message.
REM
REM  Needs to run as Administrator to stop and start the service.
REM  If it says access denied, right-click this file and choose
REM  "Run as administrator".
REM ============================================================
setlocal
set HERE=%~dp0

if not exist "%HERE%reload-api.ps1" (
  echo ERROR: reload-api.ps1 is missing from this folder.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%reload-api.ps1"
