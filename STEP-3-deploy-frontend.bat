@echo off
REM ============================================================
REM  HCIS - step 3: put the new build on the site
REM
REM  Double-click this. It calls deploy-frontend.ps1 for you.
REM
REM  It checks it can write BEFORE it removes anything, keeps a
REM  timestamped backup, and does not touch config.js - that file
REM  holds this server's own address and key.
REM
REM  If it says it cannot write, right-click this file and choose
REM  "Run as administrator".
REM ============================================================
setlocal
set HERE=%~dp0

if not exist "%HERE%deploy-frontend.ps1" (
  echo ERROR: deploy-frontend.ps1 is missing from this folder.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%deploy-frontend.ps1"
