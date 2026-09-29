<#
  HCIS - restart the API and PROVE the new columns are visible.

  Why this step exists at all:

  The database now has columns that did not exist before - the payroll
  placements, the pension amounts, the institution allowance. PostgREST keeps
  its own copy of the database's shape in memory and will happily keep serving
  the OLD shape after the database has changed. When that happens the site
  looks broken in a way that has nothing to do with the browser: payroll comes
  back empty or errors, and clearing the cache does not help.

  The catch-up asks the database to tell PostgREST to reload. That only works
  if PostgREST is listening for it, so this restarts it outright and then
  checks the result rather than assuming.

  And it checks by the PID. On 21 August "schtasks /End" reported SUCCESS on
  this very box while killing nothing at all - the running postgrest.exe had
  been started by hand, and a service manager can only stop what it started.
  It reported success and the old schema kept being served for an afternoon.
  So: the process id must CHANGE, or this script says so.
#>
$ErrorActionPreference = 'Continue'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

Say ''
Say '============================================================'
Say ' HCIS - reload the API so it can see the new columns'
Say '============================================================'
Say ''

function Get-PortPid {
    $line = (netstat -ano | Select-String ':3000\s' | Select-String 'LISTENING' |
             Select-Object -First 1)
    if (-not $line) { return $null }
    return ($line.ToString().Trim() -split '\s+')[-1]
}

$before = Get-PortPid
if ($before) { Say "PostgREST is running now as process $before." }
else { Say 'Nothing is listening on port 3000 at the moment.' 'Yellow' }

Say ''
Say 'Stopping it...'
taskkill /F /IM postgrest.exe 2>&1 | Out-String | Write-Host
Start-Sleep -Seconds 2

Say 'Starting it again through the scheduled task...'
schtasks /Run /TN "PostgREST-HCIS" 2>&1 | Out-String | Write-Host
Start-Sleep -Seconds 6

$after = Get-PortPid
if (-not $after) {
    Say ''
    Say 'The scheduled task did not bring it back up. Trying directly...' 'Yellow'
    $bat = 'C:\HCIS\postgrest\start-postgrest.bat'
    if (Test-Path -LiteralPath $bat) {
        Start-Process -FilePath $bat -WindowStyle Minimized
        Start-Sleep -Seconds 6
        $after = Get-PortPid
    }
}

if (-not $after) {
    Say ''
    Say 'THE API IS NOT RUNNING. The site will not load data until it is.' 'Red'
    Say 'Send me a photo of this window - do not run anything else.'
    Say ''
    if ($Host.Name -eq 'ConsoleHost') { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}

Say ''
if ($before -and ($after -eq $before)) {
    Say "The process id is STILL $after - it did not actually restart." 'Red'
    Say 'This is exactly what happened on 21 August. Send me a photo.'
    Say ''
    if ($Host.Name -eq 'ConsoleHost') { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}
Say "Restarted. It is now process $after (it was $before) - so it really did restart." 'Green'

# ---- the actual proof: ask the API for a column that did not exist before
Say ''
Say 'Asking the API for one of the new columns...'
$key = ''
$cfg = 'C:\HCIS\wwwroot\config.js'
if (Test-Path -LiteralPath $cfg) {
    $m = [regex]::Match((Get-Content -Raw -LiteralPath $cfg), "supabaseKey:\s*'([^']+)'")
    if ($m.Success) { $key = $m.Groups[1].Value }
}
$headers = @{}
if ($key) { $headers['apikey'] = $key; $headers['Authorization'] = "Bearer $key" }

$ok = $false
try {
    $r = Invoke-WebRequest -Uri 'http://localhost:3000/payroll_records?select=placements,institution_allowance&limit=1' `
                           -Headers $headers -UseBasicParsing -TimeoutSec 20
    if ($r.StatusCode -eq 200) { $ok = $true }
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $sr = New-Object IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd()
        Say ''
        Say 'The API refused that request:' 'Red'
        Say $body
    } else {
        Say ''
        Say ('Could not reach the API: ' + $_.Exception.Message) 'Red'
    }
}

Say ''
if ($ok) {
    Say '============================================================'
    Say ' GOOD - the API can see the new columns.' 'Green'
    Say ' Now run deploy-frontend.ps1, then Ctrl+F5 in the browser.'
    Say '============================================================'
} else {
    Say '============================================================'
    Say ' The API is running but could not return the new columns.' 'Red'
    Say ' Do NOT deploy the new build yet - it needs those columns.'
    Say ' Send me a photo of this window and I will sort it.'
    Say '============================================================'
}
Say ''
if ($Host.Name -eq 'ConsoleHost') { Read-Host 'Press Enter to close' | Out-Null }
if ($ok) { exit 0 } else { exit 1 }
