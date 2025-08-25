# DDU Auto-Update Script

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$DDUForumListURL = "https://www.wagnardsoft.com/forums/viewforum.php?f=5",  # Forum listing page
    [string]$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Display Driver Uninstaller",
    [string]$DDUExecutablePath = "C:\Program Files (x86)\Display Driver Uninstaller\Display Driver Uninstaller.exe"
)

# Relaunch in 64-bit PowerShell if on 64-bit OS but running 32-bit PowerShell
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
    Write-Host "Re-launching in 64-bit PowerShell..." -ForegroundColor Yellow
    Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Ensure modern TLS
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Invoke-WebRequestCompat {
    param([Parameter(Mandatory)][string]$Uri, [string]$OutFile)
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if ($OutFile) { Invoke-WebRequest -Uri $Uri -OutFile $OutFile -MaximumRedirection 5 }
        else { Invoke-WebRequest -Uri $Uri -MaximumRedirection 5 }
    } else {
        if ($OutFile) { Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -MaximumRedirection 5 }
        else { Invoke-WebRequest -Uri $Uri -UseBasicParsing -MaximumRedirection 5 }
    }
}

function Get-LatestDDUThreadURL {
    param([Parameter(Mandatory)][string]$ForumListURL)
    
    try {
        Write-Host "Fetching forum listing to find latest DDU thread..." -ForegroundColor Cyan
        $resp = Invoke-WebRequestCompat -Uri $ForumListURL
        $html = $resp.Content
        
        # Look for the first DDU release thread link
        # Pattern matches links like: ./viewtopic.php?t=5370&sid=xxx or just ./viewtopic.php?t=5370
        # The title should contain "DDU" or "Display Driver Uninstaller" and "Released"
        $pattern = '<a[^>]+href="\.\/viewtopic\.php\?t=(\d+)[^"]*"[^>]+class="topictitle"[^>]*>([^<]*(?:DDU|Display Driver Uninstaller)[^<]*Released[^<]*)<\/a>'
        
        if ($html -match $pattern) {
            $topicId = $Matches[1]
            $topicTitle = $Matches[2]
            
            # Extract version from title if possible
            $version = 'Unknown'
            if ($topicTitle -match 'V?([\d\.]+)') {
                $version = $Matches[1]
            }
            
            $threadURL = "https://www.wagnardsoft.com/forums/viewtopic.php?t=$topicId"
            
            Write-Host "Found latest DDU thread: $topicTitle" -ForegroundColor Green
            Write-Host "Thread URL: $threadURL" -ForegroundColor Gray
            
            return $threadURL
        } else {
            # Try a more generic pattern
            $pattern = 'href="\.\/viewtopic\.php\?t=(\d+)[^"]*"[^>]*>.*?(?:DDU|Display Driver Uninstaller).*?<'
            if ($html -match $pattern) {
                $topicId = $Matches[1]
                $threadURL = "https://www.wagnardsoft.com/forums/viewtopic.php?t=$topicId"
                
                Write-Host "Found DDU thread: $threadURL" -ForegroundColor Yellow
                return $threadURL
            }
        }
        
        throw "Could not find DDU release thread in forum listing"
    }
    catch {
        Write-Error "Failed to get latest DDU thread URL: $_"
        return $null
    }
}

function Parse-DDUReleasesFromHtml {
    param([Parameter(Mandatory)][string]$Html)

    # Match a block: SHA-1 ... SHA-256 ... then the very next <a href="...DDU...exe">
    # We then classify the URL as Portable (no _setup) vs Installer (_setup.exe)
    $pattern = '(?is)SHA-1\s*([A-F0-9]{40}).*?SHA-256\s*([A-F0-9]{64}).*?<a[^>]+href="(https://www\.wagnardsoft\.com/DDU/download/DDU[^"]+?\.exe)"'
    $matches = [System.Text.RegularExpressions.Regex]::Matches($Html, $pattern)

    $results = foreach ($m in $matches) {
        $sha1   = $m.Groups[1].Value.ToUpperInvariant()
        $sha256 = $m.Groups[2].Value.ToUpperInvariant()
        $url    = $m.Groups[3].Value

        # Determine type by filename
        $type = if ($url -match '_setup\.exe$') { 'Installer' } else { 'Portable' }

        # Extract version from file name (handles %20 or space)
        # Use the Uri object's AbsolutePath to avoid pipeline/parenthesis issues
        $fileName = [System.IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
        $fileName = [uri]::UnescapeDataString($fileName)
        $version = 'Unknown'
        if ($fileName -match 'DDU(?: |%20)?v([\d\.]+)') { $version = $Matches[1] }

        [PSCustomObject]@{
            Type     = $type
            Url      = $url
            FileName = $fileName
            SHA1     = $sha1
            SHA256   = $sha256
            Version  = $version
        }
    }

    return $results
}

function Get-DDULatestInfo {
    param([Parameter(Mandatory)][string]$ForumURL)
    try {
        Write-Host "Fetching DDU version information from thread..." -ForegroundColor Cyan
        $resp = Invoke-WebRequestCompat -Uri $ForumURL
        $html = $resp.Content

        $blocks = Parse-DDUReleasesFromHtml -Html $html
        if (-not $blocks -or $blocks.Count -eq 0) { throw "No release blocks found." }

        $installer = $blocks | Where-Object { $_.Type -eq 'Installer' } | Select-Object -First 1
        if (-not $installer) { throw "Could not find Installer block on the page." }

        return $installer
    }
    catch {
        Write-Error "Failed to parse forum page: $_"
        return $null
    }
}

function Get-StoredHash {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Test-Path $Path) {
            $val = (Get-ItemProperty -Path $Path -Name 'SHA256' -ErrorAction SilentlyContinue).SHA256
            if ($val) { return $val.ToUpperInvariant() }
        }
        return $null
    } catch {
        Write-Warning "Could not read stored hash from registry: $_"
        return $null
    }
}

function Test-DDUExecutableExists {
    param([Parameter(Mandatory)][string]$Path)
    $exists = Test-Path -Path $Path -PathType Leaf
    if ($exists) {
        Write-Host "DDU executable found at: $Path" -ForegroundColor Green
    } else {
        Write-Host "DDU executable NOT found at: $Path" -ForegroundColor Yellow
    }
    return $exists
}

function Set-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Value,
        [ValidateSet('String','ExpandString','DWord','QWord','Binary','MultiString')]
        [string]$Type = 'String'
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value | Out-Null
    } else {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type | Out-Null
    }
}

function Save-HashToRegistry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Hash,
        [Parameter(Mandatory)][string]$Version
    )
    try {
        $newlyCreated = -not (Test-Path $Path)
        if ($newlyCreated) { New-Item -Path $Path -Force | Out-Null }

        # Save only what we own; keep it resilient if the real installer overwrites other values
        Set-RegValue -Path $Path -Name 'SHA256' -Value $Hash -Type 'String'
        Set-RegValue -Path $Path -Name 'DisplayVersion' -Value $Version -Type 'String'
        Set-RegValue -Path $Path -Name 'InstallDate' -Value (Get-Date -Format 'yyyyMMdd') -Type 'String'

        # If we had to create the key (first install), hide it from Apps & Features
        if ($newlyCreated) {
            Set-RegValue -Path $Path -Name 'DisplayName' -Value 'Display Driver Uninstaller' -Type 'String'
            Set-RegValue -Path $Path -Name 'Publisher' -Value 'Wagnardsoft' -Type 'String'
            Set-RegValue -Path $Path -Name 'SystemComponent' -Value 1 -Type 'DWord'   # Hide from ARP if we created it
            Set-RegValue -Path $Path -Name 'NoModify' -Value 1 -Type 'DWord'
            Set-RegValue -Path $Path -Name 'NoRepair' -Value 1 -Type 'DWord'
        }

        Write-Host "Registry updated successfully" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to save to registry: $_"
        return $false
    }
}

function Download-File {
    param(
        [Parameter(Mandatory)][string]$URL,
        [Parameter(Mandatory)][string]$OutputPath
    )
    try {
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue }
        Write-Host "Downloading DDU installer..." -ForegroundColor Cyan
        Write-Host "URL: $URL" -ForegroundColor Gray
        Invoke-WebRequestCompat -Uri $URL -OutFile $OutputPath
        if (-not (Test-Path $OutputPath)) { throw "Downloaded file not found" }
        Write-Host "Download completed successfully" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to download: $_"
        return $false
    }
}

function Get-FileHashSHA256 {
    param([Parameter(Mandatory)][string]$FilePath)
    try {
        return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToUpperInvariant()
    } catch {
        Write-Error "Failed to calculate file hash: $_"
        return $null
    }
}

function Install-Silently {
    param([Parameter(Mandatory)][string]$InstallerPath)
    try {
        Write-Host "Installing DDU silently..." -ForegroundColor Cyan
        $p = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -PassThru
        if ($p.ExitCode -eq 0) {
            Write-Host "DDU installed successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Installer exit code: $($p.ExitCode)"
            return $false
        }
    } catch {
        Write-Error "Failed to install DDU: $_"
        return $false
    }
}

Write-Host ""
Write-Host "=== DDU Auto-Update Script ===" -ForegroundColor Yellow
Write-Host "Forum List URL: $DDUForumListURL`n" -ForegroundColor Gray

try {
    # Step 1: Find the latest DDU thread URL from the forum listing
    $latestThreadURL = Get-LatestDDUThreadURL -ForumListURL $DDUForumListURL
    if (-not $latestThreadURL) { throw "Could not determine latest DDU thread URL" }
    
    # Step 2: Check if DDU executable actually exists
    $dduExists = Test-DDUExecutableExists -Path $DDUExecutablePath
    
    # Step 3: Get latest DDU info from the thread
    $latest = Get-DDULatestInfo -ForumURL $latestThreadURL
    if (-not $latest) { throw "Could not retrieve latest DDU info." }

    Write-Host "Latest DDU Version: $($latest.Version)" -ForegroundColor Cyan
    Write-Host "Latest SHA256 (Installer): $($latest.SHA256)" -ForegroundColor Gray

    # Determine if we need to install or update
    $needInstall = $false
    $installReason = ""
    
    if (-not $dduExists) {
        # DDU executable doesn't exist - need to install regardless of registry
        $needInstall = $true
        $installReason = "DDU executable not found - performing fresh installation"
        Write-Host "`n$installReason" -ForegroundColor Yellow
    } else {
        # DDU executable exists - check if update is needed
        $storedHash = Get-StoredHash -Path $RegistryPath
        if ($storedHash) {
            Write-Host "`nStored SHA256: $storedHash" -ForegroundColor Gray
            if ($storedHash -eq $latest.SHA256) {
                Write-Host "`nDDU is already up to date!" -ForegroundColor Green
                return
            } else {
                $needInstall = $true
                $installReason = "Update available! New installer detected."
                Write-Host "`n$installReason" -ForegroundColor Yellow
            }
        } else {
            # Executable exists but no registry entry - could be portable version or corrupted registry
            $needInstall = $true
            $installReason = "DDU found but no registry entry - performing installation to ensure proper setup"
            Write-Host "`n$installReason" -ForegroundColor Yellow
        }
    }

    if ($needInstall) {
        # Build output path using actual file name
        $installerName = $latest.FileName
        $outputPath = Join-Path $env:TEMP $installerName

        if (Download-File -URL $latest.Url -OutputPath $outputPath) {
            Write-Host "`nVerifying file integrity..." -ForegroundColor Cyan
            $downloadedHash = Get-FileHashSHA256 -FilePath $outputPath

            if ($downloadedHash -eq $latest.SHA256) {
                Write-Host "Hash verification successful!" -ForegroundColor Green

                if (Install-Silently -InstallerPath $outputPath) {
                    if (Save-HashToRegistry -Path $RegistryPath -Hash $latest.SHA256 -Version $latest.Version) {
                        Write-Host "`n=== DDU Installation/Update Complete ===" -ForegroundColor Green
                        
                        # Verify the executable now exists
                        if (Test-DDUExecutableExists -Path $DDUExecutablePath) {
                            Write-Host "Installation verified successfully!" -ForegroundColor Green
                        } else {
                            Write-Warning "Installation completed but executable not found at expected location"
                        }
                    }
                }
            } else {
                Write-Error "Hash verification failed!"
                Write-Host "Expected: $($latest.SHA256)" -ForegroundColor Red
                Write-Host "Got:      $downloadedHash" -ForegroundColor Red
            }

            # Cleanup
            if (Test-Path $outputPath) {
                Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
                Write-Host "Temporary files cleaned up" -ForegroundColor Gray
            }
        } else {
            throw "Download failed."
        }
    }
}
finally {
    Write-Host "`nScript completed.`n" -ForegroundColor Cyan
}