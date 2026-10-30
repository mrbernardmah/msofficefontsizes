param([String] $userkey, [String] $region)

# Create Log File
$Logfile = "$env:LOCALAPPDATA\Temp\PaperCut-Hive-User-Email-$(Get-Date -UFormat "%Y-%m-%d_%H-%M-%S").log"
If (!(Test-Path $Logfile)) { New-Item -Path $Logfile -Force | Out-Null }
Add-Content -Path $Logfile -Value "PaperCut Hive Print Client User Email Match LogFile"

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

Function LogWrite {
    Param ([string]$logstring)
    Add-Content $Logfile -Value $logstring
}

# Retrieve current user's UPN (assumed to match their email address)
$upn = "$(whoami /upn)"
LogWrite "$(Get-TimeStamp) - Current Users UPN: $upn"

# Place email address string in double quotes
$emailAddress = [string]::Join("", """", $upn, """")
LogWrite "$(Get-TimeStamp) - Email Address copied to emailAddress variable is: $emailAddress"

# Mask the userkey for the log (show last 4 characters only)
$maskedKey = if ($userkey.Length -gt 4) { ('*' * ($userkey.Length - 4)) + $userkey.Substring($userkey.Length - 4) } else { '****' }
LogWrite "$(Get-TimeStamp) - PaperCut Hive Userkey: $maskedKey"
LogWrite "$(Get-TimeStamp) - PaperCut Hive Region: $region"

# Place userkey and region strings in double quotes
$userkey = [string]::Join("", """", $userkey, """")
$region  = [string]::Join("", """", $region, """")

# ---------------------------------------------------------------------------
# Stop every process running from the PaperCut Hive install folder and
# confirm they have exited before running the installer (up to 30 seconds).
# ---------------------------------------------------------------------------
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\PaperCut Hive'

function Get-HiveProcesses {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -like "$installRoot\*" }
}

$deadline = (Get-Date).AddSeconds(30)
do {
    Get-HiveProcesses | ForEach-Object {
        LogWrite "$(Get-TimeStamp) - Stopping $($_.Name) (PID $($_.Id))"
        try {
            Stop-Process -Id $_.Id -Force -ErrorAction Stop
        } catch {
            LogWrite "$(Get-TimeStamp) - Failed to stop $($_.Name): $($_.Exception.Message)"
        }
    }
    Start-Sleep -Seconds 2
    $remaining = Get-HiveProcesses
} while ($remaining -and (Get-Date) -lt $deadline)

if ($remaining) {
    LogWrite "$(Get-TimeStamp) - WARNING: still running after 30s: $(($remaining.Name | Sort-Object -Unique) -join ', ')"
} else {
    LogWrite "$(Get-TimeStamp) - No PaperCut Hive processes running."
}

# ---------------------------------------------------------------------------
# Run the PaperCut Hive installer
#   /SUPPRESSMSGBOXES       - never show a dialog (fail with an exit code instead of hanging)
#   /CLOSEAPPLICATIONS      - let Restart Manager close anything still locking files
#   /FORCECLOSEAPPLICATIONS - force-close those apps if they don't close cleanly
# ---------------------------------------------------------------------------
$argList = "/VERYSILENT /SUPPRESSMSGBOXES /CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS " +
           "/region=$region /CURRENTUSER /userkey=$userkey /useremail=$emailAddress"

$installer = Join-Path $PSScriptRoot 'papercut-hive.exe'
LogWrite "$(Get-TimeStamp) - Running installer: $installer"

$Process = Start-Process `
    -FilePath $installer `
    -ArgumentList $argList `
    -Wait `
    -PassThru

LogWrite "$(Get-TimeStamp) - Installer exit code: $($Process.ExitCode)"

if ($Process.ExitCode -ne 0) {
    LogWrite "$(Get-TimeStamp) - PaperCut Hive installation failed."
    exit $Process.ExitCode
}

# Intune detection marker
$MarkerPath = "$env:LOCALAPPDATA\Sunwater\IntuneDetection"
New-Item -Path $MarkerPath -ItemType Directory -Force | Out-Null
New-Item -Path "$MarkerPath\PaperCutHive-Autologon.txt" -ItemType File -Force | Out-Null
LogWrite "$(Get-TimeStamp) - Detection marker written. Done."
exit 0
