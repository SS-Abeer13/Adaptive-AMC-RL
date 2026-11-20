param(
    [string]$BaseDir = "d:\Adaptive AMC A2C+QL\Optimized\v17x",
    [string]$LogsDir = "logs",
    [int]$PollSeconds = 60,
    [int]$ReportIntervalSeconds = 300,
    [double]$StallTimeoutMinutes = 15.0
)

if (-not [System.IO.Path]::IsPathRooted($BaseDir)) {
    $BaseDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $BaseDir))
}
$fullLogs = if ([System.IO.Path]::IsPathRooted($LogsDir)) { $LogsDir } else { Join-Path $BaseDir $LogsDir }
$hbFile = Join-Path $fullLogs "heartbeat_v17x.txt"

$lastCpu = -1.0
$lastChangeTime = Get-Date
$lastReportTime = [DateTime]::MinValue
$stalled = $false

while ($true) {
    Start-Sleep -Seconds $PollSeconds

    # Find active MATLAB process
    $matlab = Get-Process -Name "MATLAB" -ErrorAction SilentlyContinue
    if (-not $matlab) {
        break
    }

    $p = $matlab | Sort-Object CPU -Descending | Select-Object -First 1
    $curCpu = [double]$p.CPU
    $now = Get-Date

    if ($lastCpu -lt 0) {
        $lastCpu = $curCpu
        $lastChangeTime = $now
        continue
    }

    # Only write when MATLAB's CPU time has gone up
    if ($curCpu -gt ($lastCpu + 0.1)) {
        $lastCpu = $curCpu
        $lastChangeTime = $now
        $stalled = $false

        # Write heartbeat line at most once per ReportIntervalSeconds
        if (($now - $lastReportTime).TotalSeconds -ge $ReportIntervalSeconds) {
            $lastReportTime = $now
            $ts = $now.ToString("yyyy-MM-dd HH:mm:ss")
            $cpuRound = [math]::Round($curCpu)
            $line = "$ts | eot            | unit computing (pid $($p.Id) active, CPU ${cpuRound}s)"
            Add-Content -Path $hbFile -Value $line
        }
    } else {
        # CPU is flat
        $flatSpan = $now - $lastChangeTime
        if ($flatSpan.TotalMinutes -ge $StallTimeoutMinutes) {
            if (-not $stalled) {
                $stalled = $true
                $ts = $now.ToString("yyyy-MM-dd HH:mm:ss")
                $sinceTs = $lastChangeTime.ToString("yyyy-MM-dd HH:mm:ss")
                $cpuRound = [math]::Round($curCpu)
                $stallLine = "$ts | runner         | KEEPER|stall|cpu_s=$cpuRound|since=$sinceTs"
                Add-Content -Path $hbFile -Value $stallLine
            }
            # Stop writing heartbeats so watchdog can fire
        }
    }
}
