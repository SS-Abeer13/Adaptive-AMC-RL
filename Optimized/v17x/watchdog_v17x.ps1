param(
    [string]$BaseDir = "D:\Adaptive AMC A2C+QL\Optimized\v17x",
    [string]$LogsDir = "logs",
    [string]$DataDir = "Dataset",
    [int]$TimeoutMinutes = 30,
    [int]$PollSeconds = 15
)

# Mutex to ensure single instance
$createdNew = $false
$mutex = [System.Threading.Mutex]::new($true, "Global\v17x_watchdog_mutex", [ref]$createdNew)
if (-not $createdNew) {
    # Another watchdog instance is already active
    exit 0
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

        # Exit cleanly if campaign completed or halted
        if (Test-Path (Join-Path $fullData "FINISHED_ALL.marker")) {
            break
        }
        if (Test-Path (Join-Path $fullData "HALTED.marker")) {
            break
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

            # Sleep to allow runner loop to detect exit and trigger restart
            Start-Sleep -Seconds 60
        }
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
