param(
    [string]$BaseDir = "D:\Adaptive AMC A2C+QL\Optimized\v17x",
    [string]$LogsDir = "logs",
    [string]$DataDir = "Dataset",
    [double]$TimeoutMinutes = 30.0,
    [int]$PollSeconds = 15
)

$scriptStartTime = Get-Date

# Ensure single watchdog instance using local process check + mutex
$runningWd = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -like "*watchdog_v17x.ps1*" -and $_.ProcessId -ne $PID }
if ($runningWd) {
    # Another watchdog instance is already actively running
    exit 0
}

$createdNew = $false
try {
    $mutex = [System.Threading.Mutex]::new($true, "Local\v17x_watchdog_mutex", [ref]$createdNew)
} catch {
    try {
        $mutex = [System.Threading.Mutex]::new($true, "v17x_watchdog_mutex", [ref]$createdNew)
    } catch {
        $mutex = $null
    }
}

try {
    if (-not [System.IO.Path]::IsPathRooted($BaseDir)) {
        $BaseDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $BaseDir))
    }
    $fullLogs = if ([System.IO.Path]::IsPathRooted($LogsDir)) { $LogsDir } else { Join-Path $BaseDir $LogsDir }
    $fullData = if ([System.IO.Path]::IsPathRooted($DataDir)) { $DataDir } else { Join-Path $BaseDir $DataDir }
    $restartsFile = Join-Path $fullLogs "restarts_v17x.txt"
    $hbFile = Join-Path $fullLogs "heartbeat_v17x.txt"

    while ($true) {
        Start-Sleep -Seconds $PollSeconds

        # Exit cleanly if campaign completed or halted AFTER this watchdog started
        $finFile = Join-Path $fullData "FINISHED_ALL.marker"
        if (Test-Path $finFile) {
            $finTime = (Get-Item $finFile).LastWriteTime
            if ($finTime -ge $scriptStartTime) {
                break
            }
        }
        $haltFile = Join-Path $fullData "HALTED.marker"
        if (Test-Path $haltFile) {
            $haltTime = (Get-Item $haltFile).LastWriteTime
            if ($haltTime -ge $scriptStartTime) {
                break
            }
        }

        # Check if MATLAB is currently running
        $matlab = Get-Process -Name "MATLAB" -ErrorAction SilentlyContinue
        if (-not $matlab) {
            continue
        }

        # Check log timestamps: heartbeat_v17x.txt and newest matlab_batch_*.log
        $times = @()
        if (Test-Path $hbFile) {
            $times += (Get-Item $hbFile).LastWriteTime
        }

        $batchLogs = Get-ChildItem -Path $fullLogs -Filter "matlab_batch_*.log" -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending
        if ($batchLogs -and $batchLogs.Count -gt 0) {
            $times += $batchLogs[0].LastWriteTime
        }

        if ($times.Count -eq 0) {
            # If neither file has been written yet, fallback to MATLAB process start time
            $times += ($matlab | Sort-Object StartTime | Select-Object -First 1).StartTime
        }

        $newest = ($times | Sort-Object -Descending | Select-Object -First 1)
        $idleSpan = (Get-Date) - $newest

        if ($idleSpan.TotalMinutes -ge $TimeoutMinutes) {
            $ts = (Get-Date).ToString("ddd MM/dd/yyyy HH:mm:ss.ff")
            $logLine = "[$ts] WATCHDOG kill"
            Add-Content -Path $restartsFile -Value $logLine

            # Terminate MATLAB process tree
            & taskkill.exe /F /IM MATLAB.exe /T *>$null
            & taskkill.exe /F /IM matlab.exe /T *>$null

            # Sleep to allow runner loop to detect exit and trigger restart
            Start-Sleep -Seconds 60
        }
    }
}
finally {
    if ($mutex) {
        try { $mutex.ReleaseMutex() } catch {}
        $mutex.Dispose()
    }
}
