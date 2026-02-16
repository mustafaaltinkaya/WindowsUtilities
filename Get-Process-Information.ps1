<#
.SYNOPSIS
    Retrieves process information including names, IDs, and parent-child relationships.

.DESCRIPTION
    This script queries all running processes and displays their names, process IDs (PIDs),
    parent process IDs (PPIDs), and builds a hierarchical tree structure showing 
    parent-child relationships.

.PARAMETER ProcessName
    Optional. Filter results by process name (supports wildcards).

.PARAMETER ExportPath
    Optional. Path to export results to CSV file.

.EXAMPLE
    .\Get-ProcessTree.ps1
    Displays all processes in table format.

.EXAMPLE
    .\Get-ProcessTree.ps1 -ProcessName "powershell*"
    Displays only PowerShell processes in table format.

.EXAMPLE
    .\Get-ProcessTree.ps1 -ExportPath "C:\temp\processes.csv"
    Exports process information to CSV file.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ProcessName,
    
    [Parameter()]
    [string]$ExportPath
)

# Function to get process information with parent details
function Get-ProcessWithParent {
    $processes = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CommandLine, CreationDate
    
    $processInfo = foreach ($proc in $processes) {
        # Get parent process name if it exists
        $parentName = $null
        if ($proc.ParentProcessId -ne 0) {
            $parent = $processes | Where-Object { $_.ProcessId -eq $proc.ParentProcessId }
            $parentName = $parent.Name
        }
        
        [PSCustomObject]@{
            ProcessId       = $proc.ProcessId
            ProcessName     = $proc.Name
            ParentProcessId = $proc.ParentProcessId
            ParentName      = $parentName
            CommandLine     = $proc.CommandLine
            CreationDate    = $proc.CreationDate
        }
    }
    
    return $processInfo
}

# Main execution
Write-Host "`n=== Windows Process Information ===" -ForegroundColor Green
Write-Host "Gathering process data...`n" -ForegroundColor Yellow

# Get all process information
$allProcesses = Get-ProcessWithParent

# Apply filter if specified
if ($ProcessName) {
    $filteredProcesses = $allProcesses | Where-Object { $_.ProcessName -like $ProcessName }
    Write-Host "Filtered to processes matching: $ProcessName" -ForegroundColor Yellow
    Write-Host "Found $($filteredProcesses.Count) matching processes`n" -ForegroundColor Yellow
} else {
    $filteredProcesses = $allProcesses
    Write-Host "Total processes: $($filteredProcesses.Count)`n" -ForegroundColor Yellow
}

# Display in table format
Write-Host "`n--- Process Table ---" -ForegroundColor Green
$filteredProcesses | 
    Sort-Object ProcessId | 
    Format-Table ProcessId, ProcessName, ParentProcessId, ParentName -AutoSize

# Export to CSV if requested
if ($ExportPath) {
    try {
        $filteredProcesses | Export-Csv -Path $ExportPath -NoTypeInformation -Force
        Write-Host "`n[SUCCESS] Process information exported to: $ExportPath" -ForegroundColor Green
    }
    catch {
        Write-Host "`n[ERROR] Failed to export to CSV: $_" -ForegroundColor Red
    }
}

# Summary statistics
Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "Total Processes: $($filteredProcesses.Count)"
Write-Host "Unique Process Names: $(($filteredProcesses.ProcessName | Select-Object -Unique).Count)"
Write-Host "Root Processes (no parent): $(($filteredProcesses | Where-Object { $_.ParentProcessId -eq 0 }).Count)"
Write-Host ""