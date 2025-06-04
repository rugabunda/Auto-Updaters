#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Checks for, downloads, installs, and cleans up K-Lite Codec Pack updates for the detected/chosen variant.
    Includes a post-fresh-install check for immediate incremental updates.

.DESCRIPTION
    Automates keeping K-Lite Codec Pack up-to-date.
    Detects the installed K-Lite variant. If not installed, prompts user to choose from an ordered list.
    After a fresh variant installation, it re-checks for and applies any applicable incremental updates.
    Uses '/FORCEUPGRADE' for all installations.
    - For Basic, Standard, Full, or Mega variant installations:
        - If 'klcp_[variant]_unattended.ini' exists, it's used via a temporary batch file.
        - Otherwise, a direct silent install is attempted.
    - For Incremental installations: Executes installer directly with silent parameters.
    Downloads and temporary files are cleaned up. A firewall rule is toggled.

.NOTES
    Changelog:
    1.9.3 - Corrected the fresh install variant selection menu to display options in a
            fixed order (Basic, Standard, Full, Mega) using an array of PSCustomObjects.
    1.9.2 - Added a "second pass" check after a fresh variant installation for incremental updates.
    1.9.1 - Extended INI file and temporary batch file logic to Basic, Standard, and Mega variants.
    (Older changelog entries omitted for brevity)

.COMPONENT_DEPENDENCY
    Optional: klcp_basic_unattended.ini, klcp_standard_unattended.ini, etc.
    Firewall rule "Windows PowerShell (powershell.exe)"
#>

# --- Configuration & Setup (Identical to v1.9.2) ---
$KliteVariantConfig = @{
    "Basic"    = @{ PageUrl = "https://www.codecguide.com/download_k-lite_codec_pack_basic.htm"    }
    "Standard" = @{ PageUrl = "https://www.codecguide.com/download_k-lite_codec_pack_standard.htm" }
    "Full"     = @{ PageUrl = "https://www.codecguide.com/download_k-lite_codec_pack_full.htm"     }
    "Mega"     = @{ PageUrl = "https://www.codecguide.com/download_k-lite_codec_pack_mega.htm"     }
}
$IncrementalUpdatePageUrl = "https://www.codecguide.com/klcp_update.htm"
$DownloadFolderName = "Klite_Downloads" 
$ScriptDir = $PSScriptRoot 
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$DownloadDir = Join-Path -Path $ScriptDir -ChildPath $DownloadFolderName      
$TempBatFileForVariantInstall = Join-Path -Path $DownloadDir -ChildPath "_temp_klcp_variant_install.bat"

# --- Helper Functions (Identical to v1.9.2) ---

function Get-InstalledKliteInfo {
    $uninstallPaths = @("HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\KLiteCodecPack_is1", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\KLiteCodecPack_is1")
    foreach ($path in $uninstallPaths) {
        $regKey = Get-ItemProperty -Path $path -Name DisplayVersion, DisplayName -ErrorAction SilentlyContinue
        if ($regKey -and $regKey.DisplayVersion -and $regKey.DisplayName) {
            try {
                $versionObject = [version]$regKey.DisplayVersion; $variant = $null
                if ($regKey.DisplayName -match 'K-Lite Codec Pack\s*[\d\.]+\s*(Basic|Standard|Full|Mega)') { $variant = $Matches[1] }
                if ($variant) { Write-Verbose "Detected K-Lite: V $($versionObject), Variant $variant"; return @{ Version = $versionObject; Variant = $variant } }
                else { Write-Warning "No K-Lite variant in DisplayName: '$($regKey.DisplayName)'. V $versionObject."; return @{ Version = $versionObject; Variant = $null }  }
            } catch { Write-Warning "Could not parse K-Lite version ('$($regKey.DisplayVersion)')." }
        }
    }
    return $null 
}

function Get-LatestVariantVersionInfo {
    param ([string]$VariantName, [string]$VariantPageUrl)
    Write-Host "Fetching latest '$VariantName' version info from $VariantPageUrl..."
    try { $response = Invoke-WebRequest -Uri $VariantPageUrl -UseBasicParsing -TimeoutSec 30 }
    catch { Write-Error "Failed to fetch '$VariantName' page: $($_.Exception.Message)"; return $null }
    $versionPattern = 'K-Lite Codec Pack(?:.|\s)*?(?:<b>|<STRONG>)?\s*(\d+\.\d+\.\d+)\s*(?:<\/b>|</STRONG>)?(?:.|\s)*?' + [regex]::Escape($VariantName)
    $versionMatch = $response.Content -match $versionPattern; $latestVersionStr = $null
    if (-not $versionMatch) {
        Write-Warning "Could not find '$VariantName' version in page text."
        $linkVersionPattern = 'K-Lite_Codec_Pack_(\d{2})(\d{1})(\d{1,2})_' + [regex]::Escape($VariantName) + '\.exe'
        if ($response.Content -match $linkVersionPattern) { $latestVersionStr = "$($Matches[1]).$($Matches[2]).$($Matches[3])"; Write-Warning "Backup: found v'$latestVersionStr' for '$VariantName' from filename." }
        else { Write-Error "Could not determine '$VariantName' version."; return $null }
    } else { $latestVersionStr = $Matches[1]; Write-Verbose "Found '$VariantName' v'$latestVersionStr' via text." }
    try { $latestVersion = [version]$latestVersionStr } catch { Write-Error "Found '$VariantName' v'$latestVersionStr' is invalid."; return $null }
    $downloadLinkPattern = 'href="(https?://(?:files\d*\.codecguide\.com|www\.codecguide\.com/files)/K-Lite_Codec_Pack_\d+_' + [regex]::Escape($VariantName) + '\.exe)"'
    if (-not ($response.Content -match $downloadLinkPattern)) { Write-Error "No download link for '$VariantName'."; return $null }
    $downloadUrl = $Matches[1]
    Write-Host "Latest '$VariantName' version: $latestVersion, URL: $downloadUrl"
    return @{ Version = $latestVersion; Url = $downloadUrl; Type = $VariantName } 
}

function Get-LatestIncrementalVersionInfo {
    param ([string]$Url)
    Write-Host "Fetching latest Incremental update info from $Url..."
    try { $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 } catch { Write-Error "Failed to fetch Incremental page: $($_.Exception.Message)"; return $null }
    $fromVersionStr = $null; $toVersionStr = $null; $fromVersionKnown = $false
    $Pattern = '(?is)This update requires version(?:.|\s)*?(?:<b>|<STRONG>)?\s*(\d+\.\d+\.\d+)\s*(?:<\/b|</STRONG>)?(?:.|\s)*?It updates (?:it |K-Lite Codec Pack )to version(?:.|\s)*?(?:<b>|<STRONG>)?\s*(\d+\.\d+\.\d+)\s*(?:<\/b|</STRONG>)?'
    if ($response.Content -match $Pattern) { $fromVersionStr = $Matches[1]; $toVersionStr = $Matches[2]; $fromVersionKnown = $true; Write-Verbose "Inc: Found From/To via primary pattern."}
    else {
        $FallbackPattern = '(?is)Update from version(?:.|\s)*?(?:<b>|<STRONG>)?\s*(\d+\.\d+\.\d+)\s*(?:<\/b|</STRONG>)?(?:.|\s)*?to version(?:.|\s)*?(?:<b>|<STRONG>)?\s*(\d+\.\d+\.\d+)\s*(?:<\/b|</STRONG>)?'
        if ($response.Content -match $FallbackPattern) { $fromVersionStr = $Matches[1]; $toVersionStr = $Matches[2]; $fromVersionKnown = $true; Write-Verbose "Inc: Found From/To via fallback."}
    }
    if (-not $toVersionStr) { if ($response.Content -match 'klcp_update_(\d{2})(\d{1})(\d{1,2})_\d+\.exe') { $toVersionStr = "$($Matches[1]).$($Matches[2]).$($Matches[3])"; Write-Verbose "Inc: Found To from filename."}}
    if (-not $toVersionStr) { Write-Error "No Inc 'To' version."; return $null }
    if (-not $fromVersionKnown) { Write-Warning "No Inc 'From' version. Target 'To' is $toVersionStr." }
    try { $toVersionObject = [version]$toVersionStr; $fromVersionObject = $null; if ($fromVersionKnown) { $fromVersionObject = [version]$fromVersionStr }}
    catch { Write-Error "Inc versions '$fromVersionStr'/'$toVersionStr' invalid."; return $null }
    if (-not ($response.Content -match 'href="(https?://(?:files\d*\.codecguide\.com|www\.codecguide\.com/files)/klcp_update_\d+_\d+\.exe)"')) { Write-Error "No Inc download link."; return $null }
    $downloadUrl = $Matches[1]
    if ($fromVersionKnown) { Write-Host "Latest Incremental package: From $fromVersionObject To $toVersionObject, URL: $downloadUrl" }
    else { Write-Host "Latest Incremental package: To $toVersionObject ('From' unknown), URL: $downloadUrl" }
    return @{ FromVersion = $fromVersionObject; ToVersion = $toVersionObject; FromVersionKnown = $fromVersionKnown; Url = $downloadUrl; Type = "Incremental" }
}

function Download-AndInstall { # Identical to v1.9.2
    param ([hashtable]$VersionInfo) 
    Write-Host "Preparing to download $($VersionInfo.Type) installer from $($VersionInfo.Url)"
    if (-not (Test-Path $DownloadDir)) { New-Item -Path $DownloadDir -ItemType Directory -Force | Out-Null }
    $InstallerFileName = $VersionInfo.Url.Split('/')[-1]; $InstallerPath = Join-Path -Path $DownloadDir -ChildPath $InstallerFileName 
    Write-Host "Downloading $InstallerFileName to '$($DownloadDir)\$InstallerFileName'..."
    try { Invoke-WebRequest -Uri $VersionInfo.Url -OutFile $InstallerPath -TimeoutSec 600; Write-Host "Download complete." }
    catch { Write-Error "Failed to download: $($_.Exception.Message)"; return $false  }
    if (-not (Test-Path $InstallerPath)) { Write-Error "Downloaded file not found: '$InstallerPath'."; return $false }
    if ((Get-Item -LiteralPath $InstallerPath).Length -eq 0) { Write-Error "Downloaded file '$InstallerPath' is empty."; return $false }
    Write-Host "Downloaded file '$InstallerFileName' verified."
    $exitCode = -1; $copiedIniNameForCleanup = $null; $useIniAndBatch = $false; $pathToVariantIniFile = $null
    if ($VersionInfo.Type -in ("Basic", "Standard", "Full", "Mega")) {
        $expectedIniFileName = "klcp_$($VersionInfo.Type.ToLower())_unattended.ini"; $pathToVariantIniFile = Join-Path -Path $ScriptDir -ChildPath $expectedIniFileName
        if (Test-Path $pathToVariantIniFile) { $useIniAndBatch = $true; Write-Host "Found INI '$expectedIniFileName' for '$($VersionInfo.Type)'. Will use batch." }
        else { Write-Warning "INI '$expectedIniFileName' for '$($VersionInfo.Type)' not found. Direct silent install (no INI)." }
    }
    try { 
        if ($useIniAndBatch) { 
            Write-Host "Preparing '$($VersionInfo.Type)' via batch/INI..."; $copiedIniNameForCleanup = Split-Path -Path $pathToVariantIniFile -Leaf
            Copy-Item -Path $pathToVariantIniFile -Destination (Join-Path -Path $DownloadDir -ChildPath $copiedIniNameForCleanup) -Force
            $batContent = "@echo off`necho Installing: K-Lite ($($VersionInfo.Type))`ncd /D `"%~dp0`"`necho Batch CWD: %cd% & dir /b /a-d`n`"$($InstallerFileName)`" /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /LOADINF=`"$copiedIniNameForCleanup`" /FORCEUPGRADE`n@echo Exit code: %errorlevel%`nexit /b %errorlevel%"
            Write-Host "Creating batch: '$($TempBatFileForVariantInstall)'"; Set-Content -Path $TempBatFileForVariantInstall -Value $batContent -Encoding UTF8 -Force
            Write-Host "Launching '$($VersionInfo.Type)' via batch..."; $process = Start-Process -FilePath $TempBatFileForVariantInstall -WorkingDirectory $DownloadDir -Wait -PassThru -Verb RunAs; $exitCode = $process.ExitCode
            Write-Host "Batch for '$($VersionInfo.Type)' finished. Exit: $exitCode"
        } elseif ($VersionInfo.Type -in ("Basic", "Standard", "Full", "Mega", "Incremental")) { 
            Write-Host "Preparing '$($VersionInfo.Type)' direct install..."; $arguments = "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /FORCEUPGRADE"
            Write-Host "Executing: `"$InstallerPath`" $arguments"; $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru -Verb RunAs; $exitCode = $process.ExitCode
            Write-Host "'$($VersionInfo.Type)' installer finished. Exit: $exitCode"
        } else { Write-Error "Unknown type: '$($VersionInfo.Type)'."; return $false }
    } catch { Write-Error "Install error: $($_.Exception.Message)" }
    finally {
        Write-Host "Cleaning up downloads..."
        if (Test-Path $InstallerPath) { Write-Host "Del: $InstallerPath"; Remove-Item -Path $InstallerPath -Force -EA SilentlyContinue }
        if ($useIniAndBatch) { 
            if (Test-Path $TempBatFileForVariantInstall) { Write-Host "Del: $TempBatFileForVariantInstall"; Remove-Item -Path $TempBatFileForVariantInstall -Force -EA SilentlyContinue }
            if ($copiedIniNameForCleanup -and (Test-Path (Join-Path $DownloadDir $copiedIniNameForCleanup))) { $copiedIniFP = Join-Path $DownloadDir $copiedIniNameForCleanup; Write-Host "Del copied INI: $copiedIniFP"; Remove-Item -Path $copiedIniFP -Force -EA SilentlyContinue }
        }
        Write-Host "Cleanup done. Folder '.\$DownloadFolderName' kept."
    }
    if ($exitCode -ne 0) { Write-Warning "Install of $($VersionInfo.Type) might have failed/reboot needed (Exit: $exitCode)." } else { Write-Host "$($VersionInfo.Type) install OK." }
    return $true 
}

# --- Main Logic ---
# $VerbosePreference = "Continue" 

Write-Host "K-Lite Codec Pack Updater (v1.9.3)"
$RelativeDownloadDir = Join-Path -Path ".\" -ChildPath $DownloadFolderName
Write-Host "Script's actual directory: $ScriptDir" 
Write-Host "Unattended INI files (e.g., klcp_full_unattended.ini) should be in this script directory."
Write-Host "Download Directory: $RelativeDownloadDir"
Write-Host "------------------------------------"

if ($PSVersionTable.PSVersion.Major -lt 5) { Write-Error "Requires PowerShell v5.0+."; exit 1 }
if (-not (New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) { Write-Error "Must run as Administrator."; exit 1 }

$ErrorEncounteredInMain = $false
try {

    $initialInstalledInfo = Get-InstalledKliteInfo 
    $currentInstalledVersion = $null
    $targetVariantName = $null 
    $isFreshInstallScenario = (-not $initialInstalledInfo) 

    if ($initialInstalledInfo) {
        $currentInstalledVersion = $initialInstalledInfo.Version
        if ($initialInstalledInfo.Variant) { $targetVariantName = $initialInstalledInfo.Variant }
        else { Write-Warning "K-Lite installed (V $currentInstalledVersion), but variant unknown. Defaulting to 'Full' for update check."; $targetVariantName = "Full" }
        Write-Host "Detected K-Lite: Version $currentInstalledVersion, Variant $targetVariantName"
    } else {
        Write-Host "K-Lite Codec Pack is not currently installed."
        # Define the menu options in the desired order
        $menuOptions = @(
            [PSCustomObject]@{ Key = "1"; Value = "Basic"    },
            [PSCustomObject]@{ Key = "2"; Value = "Standard" },
            [PSCustomObject]@{ Key = "3"; Value = "Full"     },
            [PSCustomObject]@{ Key = "4"; Value = "Mega"     }
        )
        Write-Host "Please choose which variant to install:"
        foreach ($option in $menuOptions) {
            Write-Host "  $($option.Key). $($option.Value)"
        }
        
        $choice = ""
        $validChoices = $menuOptions.Key
        while (-not ($validChoices -contains $choice)) {
            $choice = Read-Host "Enter your choice (1-4)"
            if (-not ($validChoices -contains $choice)) {
                Write-Warning "Invalid selection. Please enter a number from 1 to 4."
            }
        }
        $targetVariantName = ($menuOptions | Where-Object {$_.Key -eq $choice}).Value
        Write-Host "You selected to install: $targetVariantName"
    }

    if (-not $targetVariantName) { Write-Error "Could not determine target K-Lite variant. Halting."; $ErrorEncounteredInMain = $true }
    else {
        $latestVariantInstallerInfo = $null
        if ($KliteVariantConfig.ContainsKey($targetVariantName)) {
            $latestVariantInstallerInfo = Get-LatestVariantVersionInfo -VariantName $targetVariantName -VariantPageUrl $KliteVariantConfig[$targetVariantName].PageUrl
        } else { Write-Warning "Config for variant '$targetVariantName' not found." }
        
        $latestIncrementalInfo = Get-LatestIncrementalVersionInfo -Url $IncrementalUpdatePageUrl
        if (-not $latestVariantInstallerInfo -and -not $latestIncrementalInfo) { Write-Error "Could not retrieve any K-Lite version info. Halting."; $ErrorEncounteredInMain = $true }
    }

    if (-not $ErrorEncounteredInMain) {
        $updateNeeded = $false; $selectedInstallerInfo = $null
        if ($isFreshInstallScenario) { 
            if ($latestVariantInstallerInfo) {
                Write-Host "Action: Install latest '$($latestVariantInstallerInfo.Type)' version $($latestVariantInstallerInfo.Version)."
                $selectedInstallerInfo = $latestVariantInstallerInfo; $updateNeeded = $true
            } else { Write-Warning "Cannot fresh install: Variant installer info for '$targetVariantName' missing." }
        } else { 
            if ($latestVariantInstallerInfo -and ($latestVariantInstallerInfo.Version -gt $currentInstalledVersion)) {
                Write-Host "Newer '$($latestVariantInstallerInfo.Type)' installer available: $($latestVariantInstallerInfo.Version). Action: Update with this installer."
                $selectedInstallerInfo = $latestVariantInstallerInfo; $updateNeeded = $true
            } elseif ($latestIncrementalInfo -and ($latestIncrementalInfo.ToVersion -gt $currentInstalledVersion)) {
                if ($latestIncrementalInfo.FromVersionKnown -and ($latestIncrementalInfo.FromVersion -le $currentInstalledVersion)) {
                    Write-Host "Newer Incremental available: From $($latestIncrementalInfo.FromVersion) To $($latestIncrementalInfo.ToVersion). Action: Incremental update."
                    $selectedInstallerInfo = $latestIncrementalInfo; $updateNeeded = $true
                } elseif (-not $latestIncrementalInfo.FromVersionKnown) {
                    Write-Warning "ATTENTION: Incremental package targets $($latestIncrementalInfo.ToVersion) (Newer). 'From' version unknown."
                    Write-Warning "Proceeding with this Incremental update as requested (carries small risk)."
                    $selectedInstallerInfo = $latestIncrementalInfo; $updateNeeded = $true
                } elseif ($latestIncrementalInfo.FromVersionKnown -and ($latestIncrementalInfo.FromVersion -gt $currentInstalledVersion)) {
                    Write-Host "Incremental package (To $($latestIncrementalInfo.ToVersion)) is for base $($latestIncrementalInfo.FromVersion) (newer than installed). Not suitable."
                    if ($latestVariantInstallerInfo -and ($latestVariantInstallerInfo.Version -gt $currentInstalledVersion)) {
                         Write-Host "Fallback: Variant installer $($latestVariantInstallerInfo.Type) version $($latestVariantInstallerInfo.Version) is newer. Will use that."
                         $selectedInstallerInfo = $latestVariantInstallerInfo; $updateNeeded = $true
                    } else { Write-Host "No suitable update: Incremental not for this version, specific variant installer not newer/available." }
                }
            } else { 
                 $upToDateMessage = "K-Lite ($targetVariantName) appears up-to-date"
                 if ($latestVariantInstallerInfo -and ($latestVariantInstallerInfo.Version -le $currentInstalledVersion)) { $upToDateMessage += " (Variant installer not newer)." } 
                 elseif(-not $latestVariantInstallerInfo) { $upToDateMessage += " (Variant installer info missing)." }
                 if ($latestIncrementalInfo -and ($latestIncrementalInfo.ToVersion -le $currentInstalledVersion)) { $upToDateMessage += " (Incremental not newer)." }
                 elseif (-not $latestIncrementalInfo) { $upToDateMessage += " (Incremental info missing)." }
                 Write-Host $upToDateMessage
            }
        }

        if ($updateNeeded -and $selectedInstallerInfo) {
            Write-Host "Proceeding with $($selectedInstallerInfo.Type) installation..."
            $installSuccess = Download-AndInstall -VersionInfo $selectedInstallerInfo 
            
            if ($installSuccess) {
                Write-Host "K-Lite update/installation process finished (check installer exit code)."
                $newlyInstalledInfo = Get-InstalledKliteInfo 
                
                if ($newlyInstalledInfo) { 
                    Write-Host "Version after initial update/install: $($newlyInstalledInfo.Version), Variant: $($newlyInstalledInfo.Variant)"
                    if ($isFreshInstallScenario) { 
                        Write-Host "[INFO] Post-fresh-install check for incremental updates..."
                        $versionAfterFreshInstall = $newlyInstalledInfo.Version 
                        $incrementalCheckAfterFresh = Get-LatestIncrementalVersionInfo -Url $IncrementalUpdatePageUrl
                        if ($incrementalCheckAfterFresh -and ($incrementalCheckAfterFresh.ToVersion -gt $versionAfterFreshInstall)) {
                            $applySecondIncremental = $false; $secondIncMsg = ""
                            if ($incrementalCheckAfterFresh.FromVersionKnown -and ($incrementalCheckAfterFresh.FromVersion -le $versionAfterFreshInstall)) {
                                $applySecondIncremental = $true; $secondIncMsg = "Post-fresh-install Incremental: From $($incrementalCheckAfterFresh.FromVersion) To $($incrementalCheckAfterFresh.ToVersion)."
                            } elseif (-not $incrementalCheckAfterFresh.FromVersionKnown) {
                                $applySecondIncremental = $true; $secondIncMsg = "ATTENTION (Post-Fresh): Incremental targets $($incrementalCheckAfterFresh.ToVersion). 'From' unknown. Proceeding."
                                Write-Warning $secondIncMsg 
                            }
                            if ($applySecondIncremental) {
                                Write-Host "$secondIncMsg Action: Applying Incremental update."
                                $secondInstallSuccess = Download-AndInstall -VersionInfo $incrementalCheckAfterFresh
                                if ($secondInstallSuccess) {
                                    $finalInstalledInfo = Get-InstalledKliteInfo
                                    if ($finalInstalledInfo) { Write-Host "Version after immediate incremental: $($finalInstalledInfo.Version), Variant: $($finalInstalledInfo.Variant)" }
                                    else { Write-Warning "Could not get K-Lite version after second (incremental) install."}
                                } else { Write-Warning "Second (incremental) install process had issues." }
                            } else { Write-Host "[INFO] No immediate incremental update applicable post-fresh-install." }
                        } else { Write-Host "[INFO] No immediate incremental update available/needed post-fresh-install." }
                        Write-Host "[INFO] Finished post-fresh-install check."
                    } 
                } else { Write-Warning "Could not determine K-Lite version after the first installation attempt." }
            } else { Write-Warning "K-Lite update/installation process had issues (download/INI/launch)." }
        } 
    } 
}
catch { Write-Error "Unexpected error in main script: $($_.Exception.Message)"; $ErrorEncounteredInMain = $true }
finally {
    Write-Host "------------------------------------"; Write-Host "Script finished."
    if ($ErrorEncounteredInMain) { Write-Warning "Script finished with errors reported above." }
}
