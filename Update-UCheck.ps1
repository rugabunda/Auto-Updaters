<#
.SYNOPSIS
    Checks for, downloads, and installs updates for Adlice UCheck.
    Can also create a scheduled task to automate this process.

.DESCRIPTION
    This script requires Administrator privileges to run.

    It retrieves the currently installed version of UCheck from the registry and compares it
    against the latest version listed in the official changelog.

    If a newer version is found (or if UCheck is not installed), it downloads the installer
    and runs it silently.

    When run with the -Schedule flag, it creates a Windows Scheduled Task to perform
    the update check automatically every 6 hours.

.PARAMETER Schedule
    A switch to trigger the creation of a scheduled task. When this is used, the script
    will set up the task and then exit.

.PARAMETER Name
    Specifies a custom name for the scheduled task. If omitted when using -Schedule,
    a default name 'UCheck-AutoUpdater' will be used.

.EXAMPLE
    .\Update-UCheck.ps1
    Performs a one-time check for UCheck updates. Requires running as Administrator.

.EXAMPLE
    .\Update-UCheck.ps1 -Schedule
    Creates a scheduled task named 'UCheck-AutoUpdater' to run the update check.

.NOTES
    Author: Your Name/Organization
    Date:   2024-10-27
    Requires: PowerShell 5.1 or later running with Administrator privileges.
#>
[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'Schedule', HelpMessage = "Create a scheduled task to run the update check.")]
    [Alias('s')]
    [switch]$Schedule,

    [Parameter(ParameterSetName = 'Schedule', HelpMessage = "Specify the name for the scheduled task.")]
    [string]$Name = "UCheck-AutoUpdater"
)

#region Functions

function Test-IsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstalledUCheckVersion {
    Write-Verbose "Checking registry for installed UCheck version..."
    try {
        $uninstallPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )

        foreach ($path in $uninstallPaths) {
            $regKey = Get-ChildItem -Path $path -ErrorAction SilentlyContinue |
                      Where-Object { $_.GetValue('DisplayName') -like '*UCheck*' } |
                      Select-Object -First 1

            if ($regKey) {
                $version = $regKey.GetValue('DisplayVersion')
                Write-Verbose "Found installed version: $version"
                return $version
            }
        }

        Write-Verbose "UCheck does not appear to be installed."
        return $null
    }
    catch {
        Write-Warning "An error occurred while checking for installed version: $($_.Exception.Message)"
        return $null
    }
}

function Get-LatestUCheckVersion {
    Write-Verbose "Fetching latest version from changelog..."
    $changelogUrl = 'https://download.adlice.com/UCheck/Changelog.txt'
    try {
        $content = Invoke-WebRequest -Uri $changelogUrl -UseBasicParsing | Select-Object -ExpandProperty Content
        
        if ($content -match '(?m)^V(\d+\.\d+\.\d+)') {
            $latestVersion = $Matches[1]
            Write-Verbose "Found latest version: $latestVersion"
            return $latestVersion
        }
        else {
            Write-Warning "Could not parse the version from the changelog."
            return $null
        }
    }
    catch {
        Write-Warning "Failed to download changelog: $($_.Exception.Message)"
        return $null
    }
}

function Install-UCheckUpdate {
    $downloadUrl = 'https://download.adlice.com/api?action=download&app=ucheck&type=setup'
    $installerPath = Join-Path $env:TEMP 'ucheck_setup.exe'
    
    try {
        Write-Host "Downloading the latest version of UCheck..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
        Write-Verbose "Download command finished. Verifying file..."

        if (-not (Test-Path $installerPath) -or (Get-Item $installerPath).Length -lt 1MB) {
            throw "Download verification failed. The installer is missing or invalid (less than 1 MB)."
        }
        Write-Verbose "Installer file validated successfully."

        Write-Host "Installing UCheck silently... Please wait." -ForegroundColor Yellow
        $installArgs = '/verysilent /norestart /suppressmsgboxes'
        
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "UCheck installation/update completed successfully." -ForegroundColor Green
        }
        else {
            Write-Warning "The installer exited with a non-zero exit code: $($process.ExitCode)."
        }
    }
    catch {
        Write-Error "An error occurred during download or installation: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $installerPath) {
            Write-Verbose "Cleaning up installer file: $installerPath"
            Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-UCheckUpdateTask {
    param(
        [string]$TaskName
    )

    if (-not (Test-IsAdmin)) {
        Write-Error "Administrator privileges are required to create a scheduled task. Please re-run from an elevated PowerShell prompt."
        return
    }

    Write-Host "Creating scheduled task '$TaskName'..." -ForegroundColor Cyan
    
    try {
        $scriptPath = $PSCommandPath
        $argumentString = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $scriptPath
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentString

        $taskTrigger = New-ScheduledTaskTrigger `
            -Once `
            -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Hours 6) `
            -RandomDelay (New-TimeSpan -Hours 2)

        $taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable

        $taskPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $taskAction `
            -Trigger $taskTrigger `
            -Settings $taskSettings `
            -Principal $taskPrincipal `
            -Force
        
        Write-Host "Successfully created and configured scheduled task '$TaskName'." -ForegroundColor Green
        Write-Host "It will run every 6 hours to check for UCheck updates."
    }
    catch {
        Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
    }
}

#endregion

#region Main Logic

if ($PSBoundParameters.ContainsKey('Schedule')) {
    New-UCheckUpdateTask -TaskName $Name
    return
}

if (-not (Test-IsAdmin)) {
    Write-Error "Administrator privileges are required to install software and create scheduled tasks. Please re-run from an elevated PowerShell prompt."
    exit 1
}

Write-Host "Starting UCheck update check..." -ForegroundColor Cyan

$installedVersion = Get-InstalledUCheckVersion
$latestVersion = Get-LatestUCheckVersion

if (-not $latestVersion) {
    Write-Error "Could not determine the latest version. Aborting update check."
    exit 1
}

$updateNeeded = $false
if (-not $installedVersion) {
    Write-Host "UCheck is not installed." -ForegroundColor Yellow
    $updateNeeded = $true
}
elseif ([version]$latestVersion -gt [version]$installedVersion) {
    Write-Host "A new version of UCheck is available." -ForegroundColor Green
    Write-Host "  Installed: $installedVersion"
    Write-Host "  Latest:    $latestVersion"
    $updateNeeded = $true
}
else {
    Write-Host "UCheck is already up to date (Version: $installedVersion)." -ForegroundColor Green
}

if ($updateNeeded) {
    Install-UCheckUpdate
}

#endregion
