@echo off
REM ============================================================
REM  HCIS - Government box, database catch-up
REM  29 September 2026
REM
REM  Double-click this. It calls catchup-database.ps1, which:
REM
REM    1. takes a backup, and refuses to go on without one
REM    2. applies the eleven updates this box has not had,
REM       each one its own transaction, stopping at the first
REM       failure so the box is never left half way
REM    3. installs the token signing key, read off this
REM       machine's own PostgREST configuration
REM
REM  Step 3 is not optional. From update 31 onwards signing in
REM  needs that key, and without it every update reports success
REM  while nobody can log in.
REM ============================================================
setlocal
set HERE=%~dp0

if not exist "%HERE%catchup-database.ps1" (
  echo.
  echo   ERROR: catchup-database.ps1 is missing from this folder.
  echo   The download is incomplete - unzip it again.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%catchup-database.ps1"

echo.
pause
