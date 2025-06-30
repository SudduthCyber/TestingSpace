<#
.SYNOPSIS
    Performs system enumeration and health checks on Windows 10/11.
.DESCRIPTION
    Collects OS, CPU, memory, disk, services, and event log information, evaluates them
    against defined thresholds, and logs details. Outputs a final health status (GOOD/BAD).
.PARAMETER LogFile
    Path to output log file. Defaults to 'SystemHealthCheck.log' in the current directory.
.EXAMPLE
    .\Check-SystemHealth.ps1 -LogFile C:\Logs\Health.log -Verbose
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "SystemHealthCheck.log"
)
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timeStamp `t $Message"
    Write-Host $logEntry
    $logEntry | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# Initialize log file
if (Test-Path $LogFile) { Remove-Item $LogFile -Force }
"" | Out-File -FilePath $LogFile -Encoding UTF8
Write-Log "Log initialized. Output file: $LogFile"
$HealthStates = @()
Write-Log "Starting System Health Check..."

# OS Information
Write-Log "Collecting OS Information..."
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$osName = $os.Caption
$osVersion = $os.Version
Write-Log "Operating System: $osName Version: $osVersion"

# CPU Information
Write-Log "Collecting CPU Information..."
$cpu = Get-CimInstance Win32_Processor
$cpuName = $cpu.Name
$cpuLoad = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty CounterSamples |
    Select-Object -ExpandProperty CookedValue
$cpuLoad = [math]::Round($cpuLoad,2)
Write-Log "CPU: $cpuName Load: $cpuLoad%"
if ($cpuLoad -gt 80) {
    Write-Log "CPU load is above threshold (80%)."
    $HealthStates += "CPU load high"
} else {
    Write-Log "CPU load is within acceptable range."
}

# Memory Information
Write-Log "Collecting Memory Information..."
$totalMem = $os.TotalVisibleMemorySize/1KB
$freeMem  = $os.FreePhysicalMemory/1KB
$memFreePercent = [math]::Round(($freeMem/$totalMem)*100,2)
Write-Log "Memory Total: $([math]::Round($totalMem/1MB,2)) GB Free: $([math]::Round($freeMem/1MB,2)) GB Free%: $memFreePercent%"
if ($memFreePercent -lt 15) {
    Write-Log "Memory free percentage is below threshold (15%)."
    $HealthStates += "Low memory"
} else {
    Write-Log "Memory usage is within acceptable range."
}

# Disk Information
Write-Log "Collecting Disk Information..."
$drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
foreach ($drive in $drives) {
    $device = $drive.DeviceID
    $sizeGB = [math]::Round($drive.Size/1GB,2)
    $freeGB = [math]::Round($drive.FreeSpace/1GB,2)
    if ($drive.Size -gt 0) {
        $freePercent = [math]::Round(($drive.FreeSpace/$drive.Size)*100,2)
    } else {
        $freePercent = 0
    }
    Write-Log "Drive $device: Size: $sizeGB GB Free: $freeGB GB Free%: $freePercent%"
    if ($freePercent -lt 10) {
        Write-Log "Free space on drive $device is below threshold (10%)."
        $HealthStates += "Low disk space on $device"
    } else {
        Write-Log "Disk usage on drive $device is within acceptable range."
    }
}

# Services Status
Write-Log "Checking critical services status..."
$criticalServices = @('wuauserv','WinDefend','bits')
foreach ($svcName in $criticalServices) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Log "Service $svcName not found."
        $HealthStates += "Service $svcName not installed"
    } else {
        Write-Log "Service $svcName is $($svc.Status)"
        if ($svc.Status -ne 'Running') {
            Write-Log "Service $svcName is not running."
            $HealthStates += "Service $svcName not running"
        }
    }
}

# Event Log Errors in the last hour
Write-Log "Checking recent critical errors in System and Application logs..."
$events = Get-WinEvent -LogName System,Application -Level 1,2 -StartTime (Get-Date).AddHours(-1) -ErrorAction SilentlyContinue
if ($events -and $events.Count -gt 0) {
    $errorCount = $events.Count
    Write-Log "Found $errorCount critical errors in the last hour."
    $HealthStates += "$errorCount critical errors"
} else {
    Write-Log "No critical errors found in the last hour."
}

# Pending Reboot after Windows Update
Write-Log "Checking for pending reboot after Windows Update..."
$rebootKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
if (Test-Path $rebootKey) {
    Write-Log "System has pending reboot after update."
    $HealthStates += "Pending reboot"
} else {
    Write-Log "No pending reboot after update detected."
}

# Summary
Write-Log "Summarizing system health status..."
if ($HealthStates.Count -eq 0) {
    Write-Log "System Health Status: GOOD"
    $exitCode = 0
} else {
    Write-Log "System Health Status: BAD"
    Write-Log "Issues detected:"
    foreach ($issue in $HealthStates) {
        Write-Log " - $issue"
    }
    $exitCode = 1
}

Write-Log "Health check completed."
exit $exitCode