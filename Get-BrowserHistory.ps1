# Browser History Extraction Script
# Requires: PSSQLite module
# Usage: Run as Administrator for best results

#Requires -Version 5.1

<#
.SYNOPSIS
    Extracts browsing history from installed browsers on Windows.

.DESCRIPTION
    Detects Chrome, Edge, Firefox, and Brave browsers, then extracts their browsing history
    to CSV files for review. Requires the PSSQLite PowerShell module.

.PARAMETER OutputPath
    Directory where CSV files will be saved. Defaults to current user's Desktop.

.PARAMETER MaxResults
    Maximum number of history entries to extract per browser. Default is 1000.

.EXAMPLE
    .\Get-BrowserHistory.ps1
    
.EXAMPLE
    .\Get-BrowserHistory.ps1 -OutputPath "C:\Reports" -MaxResults 5000
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop",
    [int]$MaxResults = 1000
)

# Check and install PSSQLite module if needed
function Install-PSSQLiteIfNeeded {
    if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
        Write-Host "PSSQLite module not found. Installing..." -ForegroundColor Yellow
        try {
            Install-Module PSSQLite -Scope CurrentUser -Force -AllowClobber
            Write-Host "PSSQLite installed successfully!" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install PSSQLite: $_"
            Write-Host "Please install manually: Install-Module PSSQLite -Scope CurrentUser" -ForegroundColor Red
            exit 1
        }
    }
    Import-Module PSSQLite -ErrorAction Stop
}

# Convert Chrome timestamp to DateTime
function Convert-ChromeTime {
    param([long]$chromeTime)
    
    if ($chromeTime -eq 0) { return $null }
    
    try {
        # Chrome time is microseconds since 1601-01-01
        $epoch = [DateTime]"1601-01-01 00:00:00"
        return $epoch.AddMicroseconds($chromeTime)
    }
    catch {
        return $null
    }
}

# Convert Firefox timestamp to DateTime
function Convert-FirefoxTime {
    param([long]$firefoxTime)
    
    if ($firefoxTime -eq 0) { return $null }
    
    try {
        # Firefox time is microseconds since Unix epoch
        $epoch = [DateTime]"1970-01-01 00:00:00"
        return $epoch.AddTicks($firefoxTime * 10)
    }
    catch {
        return $null
    }
}

# Extract Chrome history
function Get-ChromeHistory {
    param([string]$OutputPath, [int]$MaxResults)
    
    Write-Host "`nExtracting Chrome history..." -ForegroundColor Cyan
    
    $chromePaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1\History",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 2\History"
    )
    
    $allHistory = @()
    
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            # Copy to temp (Chrome locks the file)
            $tempPath = "$env:TEMP\ChromeHistory_$(Get-Random).db"
            
            try {
                Copy-Item $path $tempPath -Force
                
                $query = "SELECT url, title, visit_count, last_visit_time 
                         FROM urls 
                         ORDER BY last_visit_time DESC 
                         LIMIT $MaxResults"
                
                $results = Invoke-SqliteQuery -DataSource $tempPath -Query $query
                
                foreach ($row in $results) {
                    $allHistory += [PSCustomObject]@{
                        Browser = "Chrome"
                        URL = $row.url
                        Title = $row.title
                        VisitCount = $row.visit_count
                        LastVisit = Convert-ChromeTime -chromeTime $row.last_visit_time
                    }
                }
                
                Write-Host "  Found $($results.Count) entries in profile" -ForegroundColor Green
            }
            catch {
                Write-Warning "  Error reading Chrome history: $_"
            }
            finally {
                Remove-Item $tempPath -ErrorAction SilentlyContinue
            }
        }
    }
    
    if ($allHistory.Count -gt 0) {
        $outputFile = Join-Path $OutputPath "Chrome_History_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $allHistory | Export-Csv -Path $outputFile -NoTypeInformation
        Write-Host "  Exported to: $outputFile" -ForegroundColor Green
    }
    else {
        Write-Host "  No Chrome history found" -ForegroundColor Yellow
    }
}

# Extract Edge history
function Get-EdgeHistory {
    param([string]$OutputPath, [int]$MaxResults)
    
    Write-Host "`nExtracting Edge history..." -ForegroundColor Cyan
    
    $edgePaths = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Profile 1\History"
    )
    
    $allHistory = @()
    
    foreach ($path in $edgePaths) {
        if (Test-Path $path) {
            $tempPath = "$env:TEMP\EdgeHistory_$(Get-Random).db"
            
            try {
                Copy-Item $path $tempPath -Force
                
                $query = "SELECT url, title, visit_count, last_visit_time 
                         FROM urls 
                         ORDER BY last_visit_time DESC 
                         LIMIT $MaxResults"
                
                $results = Invoke-SqliteQuery -DataSource $tempPath -Query $query
                
                foreach ($row in $results) {
                    $allHistory += [PSCustomObject]@{
                        Browser = "Edge"
                        URL = $row.url
                        Title = $row.title
                        VisitCount = $row.visit_count
                        LastVisit = Convert-ChromeTime -chromeTime $row.last_visit_time
                    }
                }
                
                Write-Host "  Found $($results.Count) entries in profile" -ForegroundColor Green
            }
            catch {
                Write-Warning "  Error reading Edge history: $_"
            }
            finally {
                Remove-Item $tempPath -ErrorAction SilentlyContinue
            }
        }
    }
    
    if ($allHistory.Count -gt 0) {
        $outputFile = Join-Path $OutputPath "Edge_History_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $allHistory | Export-Csv -Path $outputFile -NoTypeInformation
        Write-Host "  Exported to: $outputFile" -ForegroundColor Green
    }
    else {
        Write-Host "  No Edge history found" -ForegroundColor Yellow
    }
}

# Extract Firefox history
function Get-FirefoxHistory {
    param([string]$OutputPath, [int]$MaxResults)
    
    Write-Host "`nExtracting Firefox history..." -ForegroundColor Cyan
    
    $firefoxPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
    
    if (-not (Test-Path $firefoxPath)) {
        Write-Host "  No Firefox profiles found" -ForegroundColor Yellow
        return
    }
    
    $allHistory = @()
    $profiles = Get-ChildItem $firefoxPath -Directory
    
    foreach ($profile in $profiles) {
        $placesDb = Join-Path $profile.FullName "places.sqlite"
        
        if (Test-Path $placesDb) {
            $tempPath = "$env:TEMP\FirefoxHistory_$(Get-Random).db"
            
            try {
                Copy-Item $placesDb $tempPath -Force
                
                $query = "SELECT url, title, visit_count, last_visit_date 
                         FROM moz_places 
                         WHERE url NOT LIKE 'place:%'
                         ORDER BY last_visit_date DESC 
                         LIMIT $MaxResults"
                
                $results = Invoke-SqliteQuery -DataSource $tempPath -Query $query
                
                foreach ($row in $results) {
                    $allHistory += [PSCustomObject]@{
                        Browser = "Firefox"
                        URL = $row.url
                        Title = $row.title
                        VisitCount = $row.visit_count
                        LastVisit = Convert-FirefoxTime -firefoxTime $row.last_visit_date
                    }
                }
                
                Write-Host "  Found $($results.Count) entries in profile: $($profile.Name)" -ForegroundColor Green
            }
            catch {
                Write-Warning "  Error reading Firefox history: $_"
            }
            finally {
                Remove-Item $tempPath -ErrorAction SilentlyContinue
            }
        }
    }
    
    if ($allHistory.Count -gt 0) {
        $outputFile = Join-Path $OutputPath "Firefox_History_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $allHistory | Export-Csv -Path $outputFile -NoTypeInformation
        Write-Host "  Exported to: $outputFile" -ForegroundColor Green
    }
    else {
        Write-Host "  No Firefox history found" -ForegroundColor Yellow
    }
}

# Extract Brave history
function Get-BraveHistory {
    param([string]$OutputPath, [int]$MaxResults)
    
    Write-Host "`nExtracting Brave history..." -ForegroundColor Cyan
    
    $bravePaths = @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\History",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Profile 1\History"
    )
    
    $allHistory = @()
    
    foreach ($path in $bravePaths) {
        if (Test-Path $path) {
            $tempPath = "$env:TEMP\BraveHistory_$(Get-Random).db"
            
            try {
                Copy-Item $path $tempPath -Force
                
                $query = "SELECT url, title, visit_count, last_visit_time 
                         FROM urls 
                         ORDER BY last_visit_time DESC 
                         LIMIT $MaxResults"
                
                $results = Invoke-SqliteQuery -DataSource $tempPath -Query $query
                
                foreach ($row in $results) {
                    $allHistory += [PSCustomObject]@{
                        Browser = "Brave"
                        URL = $row.url
                        Title = $row.title
                        VisitCount = $row.visit_count
                        LastVisit = Convert-ChromeTime -chromeTime $row.last_visit_time
                    }
                }
                
                Write-Host "  Found $($results.Count) entries in profile" -ForegroundColor Green
            }
            catch {
                Write-Warning "  Error reading Brave history: $_"
            }
            finally {
                Remove-Item $tempPath -ErrorAction SilentlyContinue
            }
        }
    }
    
    if ($allHistory.Count -gt 0) {
        $outputFile = Join-Path $OutputPath "Brave_History_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $allHistory | Export-Csv -Path $outputFile -NoTypeInformation
        Write-Host "  Exported to: $outputFile" -ForegroundColor Green
    }
    else {
        Write-Host "  No Brave history found" -ForegroundColor Yellow
    }
}

# Detect installed browsers
function Get-InstalledBrowsers {
    $browsers = @()
    
    # Check Chrome - multiple possible locations
    $chromePaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "$env:PROGRAMFILES\Google\Chrome\Application\chrome.exe",
        "${env:PROGRAMFILES(X86)}\Google\Chrome\Application\chrome.exe"
    )
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            $browsers += "Chrome"
            break
        }
    }
    
    # Check Edge - multiple possible locations
    $edgePaths = @(
        "${env:PROGRAMFILES(X86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:PROGRAMFILES\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($path in $edgePaths) {
        if (Test-Path $path) {
            $browsers += "Edge"
            break
        }
    }
    
    # Check Firefox - multiple possible locations
    $firefoxPaths = @(
        "$env:PROGRAMFILES\Mozilla Firefox\firefox.exe",
        "${env:PROGRAMFILES(X86)}\Mozilla Firefox\firefox.exe"
    )
    foreach ($path in $firefoxPaths) {
        if (Test-Path $path) {
            $browsers += "Firefox"
            break
        }
    }
    
    # Check Brave - multiple possible locations
    $bravePaths = @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:PROGRAMFILES\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    foreach ($path in $bravePaths) {
        if (Test-Path $path) {
            $browsers += "Brave"
            break
        }
    }
    
    return $browsers
}

# Main execution
try {
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Browser History Extraction Tool" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Ensure output directory exists
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }
    
    # Install PSSQLite if needed
    Install-PSSQLiteIfNeeded
    
    # Detect browsers
    Write-Host "Detecting installed browsers..." -ForegroundColor Cyan
    $installedBrowsers = Get-InstalledBrowsers
    
    if ($installedBrowsers.Count -eq 0) {
        Write-Host "No supported browsers found!" -ForegroundColor Red
        exit 0
    }
    
    Write-Host "Found: $($installedBrowsers -join ', ')" -ForegroundColor Green
    
    # Extract history from each browser
    if ($installedBrowsers -contains "Chrome") { 
        Get-ChromeHistory -OutputPath $OutputPath -MaxResults $MaxResults 
    }
    
    if ($installedBrowsers -contains "Edge") { 
        Get-EdgeHistory -OutputPath $OutputPath -MaxResults $MaxResults 
    }
    
    if ($installedBrowsers -contains "Firefox") { 
        Get-FirefoxHistory -OutputPath $OutputPath -MaxResults $MaxResults 
    }
    
    if ($installedBrowsers -contains "Brave") { 
        Get-BraveHistory -OutputPath $OutputPath -MaxResults $MaxResults 
    }
    
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  Extraction Complete!" -ForegroundColor Green
    Write-Host "  Output location: $OutputPath" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Cyan
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
