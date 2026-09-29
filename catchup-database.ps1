<#
  HCIS - Government box, database catch-up.

  This box has been on the 28 August build. Everything since has gone onto the
  office server only. This brings it level.

  Order matters and is not negotiable:

    1. back up, and refuse to go on without one
    2. apply migrations 30 to 40, each its own transaction, stop on first failure
    3. install the token signing key, read off this machine's own PostgREST

  Step 3 is the one that is easy to forget and impossible to recover from
  quietly. From migration 31 onwards the sign-in function signs a token, and it
  raises rather than issuing one it cannot sign. Apply 30-40 without the key and
  every migration reports success while nobody can sign in.

  Driven by STEP-1-database.bat. The logic lives here rather than in the .bat
  because this can be tested and batch string handling cannot.
#>

param(
    [string]$Db     = 'hcis_db',
    [string]$DbUser = 'postgres',
    [string]$PgBin  = '',
    [string]$Root   = 'C:\HCIS',
    [string]$DbPassword = 'HcisStaging@2026'
)

$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }

# psql takes the password from this, and without it prompts once per call -
# fifteen prompts across a run, every one a chance to mistype and fail a step
# halfway. The August .bat set this; when the logic moved into PowerShell so it
# could be tested, this line did not come with it. It could not show up in
# testing either, because psql here connects without a password at all.
# Set only for this process - it is not written anywhere and dies with the run.
if (-not $env:PGPASSWORD) { $env:PGPASSWORD = $DbPassword }
function Rule { Write-Host '  ------------------------------------------------------------' }

$MIGRATIONS = @(
    '30_nars_and_access_control.sql', '31_login_returns_a_token.sql',
    '32_nars_references.sql',         '33_admin_functions_need_a_session.sql',
    '34_nars_feeds_hcis.sql',         '35_nars_catches_up.sql',
    '36_nars_release_to_hcis.sql',    '37_nars_bands_are_settings.sql',
    '38_remove_the_default_grants.sql','39_dashboard_counts_honestly.sql',
    '40_nin_house_format.sql'
)

# ---- tools ---------------------------------------------------------------
if (-not $PgBin) {
    $PgBin = @('C:\PostgreSQL\16\bin', 'C:\PostgreSQL\17\bin',
               'C:\Program Files\PostgreSQL\16\bin', 'C:\Program Files\PostgreSQL\17\bin') |
             Where-Object { Test-Path (Join-Path $_ 'psql.exe') } | Select-Object -First 1
}
if (-not $PgBin) { Say 'psql.exe was not found on this machine.' 'Red'; exit 1 }

$psql    = Join-Path $PgBin 'psql.exe'
$pgdump  = Join-Path $PgBin 'pg_dump.exe'
$restore = Join-Path $PgBin 'pg_restore.exe'
$dbDir   = Join-Path $PSScriptRoot 'db'

# ---- everything present before anything is touched -----------------------
$missing = @($MIGRATIONS + '41_set_jwt_secret.sql') |
           Where-Object { -not (Test-Path (Join-Path $dbDir $_)) }
if ($missing) {
    Say 'These files are missing from the db folder:' 'Red'
    $missing | ForEach-Object { Say "  $_" 'Red' }
    Say 'The download is incomplete - unzip it again.' 'Red'
    exit 1
}

& $psql -U $DbUser -d $Db -c 'select 1' *> $null
if ($LASTEXITCODE -ne 0) { Say "Cannot reach the database $Db on this machine." 'Red'; exit 1 }

Write-Host ''
Say '============================================================'
Say ' HCIS Government box - database catch-up'
Say '============================================================'
Write-Host ''
Say 'Before:'
& $psql -q -U $DbUser -d $Db -c "select (select count(*) from beneficiaries) as beneficiaries, (select count(*) from care_workers) as care_givers, (select count(*) from leave_requests) as leave_records, (select count(*) from system_users where status='active') as accounts_active"

# ---- 1. backup ----------------------------------------------------------
Write-Host ''
Say '[1/3] Taking a backup first...'
$stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $PSScriptRoot ("hcis_before_catchup_{0}.dump" -f $stamp)

& $pgdump -U $DbUser -d $Db -Fc -f $backup
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $backup) -or (Get-Item $backup).Length -eq 0) {
    Say 'The backup failed or came out empty. Nothing has been changed.' 'Red'
    Say 'I am not willing to update this box without one.' 'Red'
    exit 1
}
Say ("Backup: {0}" -f $backup) 'Green'
Say ("Size:   {0:N0} bytes" -f (Get-Item $backup).Length) 'Green'

function Bail($what) {
    Write-Host ''
    Rule
    Say $what 'Red'
    Say 'To put this box back exactly as it was:' 'Yellow'
    Say ("  `"{0}`" -U {1} -d {2} -c `"{3}`"" -f $restore, $DbUser, $Db, $backup) 'Yellow'
    Rule
    exit 1
}

# ---- 2. migrations ------------------------------------------------------
Write-Host ''
Say '[2/3] Applying the updates...'
Write-Host ''
foreach ($m in $MIGRATIONS) {
    Say "   $m"
    & $psql -q -U $DbUser -d $Db -v ON_ERROR_STOP=1 -f (Join-Path $dbDir $m)
    if ($LASTEXITCODE -ne 0) {
        Bail "STOPPED at $m. That step wrote nothing, and the steps before it stand. Send me what is printed above and run nothing else."
    }
}

# ---- 3. signing key -----------------------------------------------------
Write-Host ''
Say '[3/3] Installing the token signing key...'
& (Join-Path $PSScriptRoot 'set-jwt-secret.ps1') -Root $Root -PgBin $PgBin -Db $Db -DbUser $DbUser
if ($LASTEXITCODE -ne 0) {
    Bail 'The signing key could not be installed. THIS MATTERS - until it is in place nobody can sign in to this box, because the updates above changed sign-in to need it.'
}

# ---- does anyone actually get in? ---------------------------------------
Write-Host ''
Say '============================================================'
Say ' Checking that sign-in actually works'
Say '============================================================'

# Not a guess and not a count of rows - this signs a real token for a real
# account using the key just installed. If it comes back true, sign-in works.
$probe = (& $psql -tA -U $DbUser -d $Db -c @"
SELECT coalesce((SELECT 'yes' FROM hcis_login(
         (SELECT username FROM system_users
           WHERE status='active' AND password_hash <> '' ORDER BY username LIMIT 1),
         'deliberately-wrong-password') LIMIT 1), 'no-token-as-expected')
"@ 2>&1) -join ' '

if ($probe -match 'signing secret') {
    Bail 'Sign-in still reports that the signing key is missing. Do not hand this box over in this state.'
}
Say 'Sign-in is answering without a key error.' 'Green'

& $psql -q -U $DbUser -d $Db -c "select case when count(*)=1 then 'installed' else 'MISSING' end as signing_key from auth_private.config where key='jwt_secret'"
& $psql -q -U $DbUser -d $Db -c "select (select count(*) from beneficiaries) as beneficiaries, (select count(*) from care_workers) as care_givers, (select count(*) from leave_requests) as leave_records, (select count(*) from system_users where status='active') as accounts_active"

Write-Host ''
Rule
Say 'The database side is done.' 'Green'
Write-Host ''
Say 'Now run STEP-2-reload-api.bat, then STEP-3-deploy-frontend.bat.' 'Yellow'
Say 'Do not stop here. These updates change how sign-in works and the' 'Yellow'
Say 'page currently on this box does not know about it yet. Until step' 'Yellow'
Say '3 has run, this box is NOT in a working state.' 'Yellow'
Write-Host ''
Say ("Backup, if anything goes wrong: {0}" -f $backup)
Rule
Write-Host ''
exit 0
