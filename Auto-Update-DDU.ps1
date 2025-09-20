# DDU Auto-Update Script
# Uses the central releases page -> content page -> forum fallback
# Pairs each download link with the nearest SHA-256 on the page to avoid hash mismatches.

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$DDUIndexURL = "https://www.wagnardsoft.com/display-driver-uninstaller-ddu",
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

function Resolve-Url {
    param([Parameter(Mandatory)][string]$BaseUrl, [Parameter(Mandatory)][string]$Href)
    try {
        if ($Href -match '^https?://') { return $Href }
        $base = [Uri]$BaseUrl
        $u = New-Object System.Uri($base, $Href)
        return $u.AbsoluteUri
    } catch { return $Href }
}

function Get-VersionSortKey {
    param([string]$Version)
    try { return [Version]$Version } catch { return $null }
}

function Get-LatestDDUContentURL {
    param([Parameter(Mandatory)][string]$IndexURL)
    try {
        Write-Host "Fetching DDU releases index page..." -ForegroundColor Cyan
        $resp = Invoke-WebRequestCompat -Uri $IndexURL
        $html = $resp.Content

        # Find content links like /content/Download-Display-Driver-Uninstaller-DDU-18132
        $pattern = '(?is)<a[^>]+href\s*=\s*(["''])(?<href>\/content\/Download-Display-Driver-Uninstaller-DDU-[^"'']+)\1[^>]*>(?<text>.*?)<\/a>'
        $matches = [System.Text.RegularExpressions.Regex]::Matches($html, $pattern)

        if ($matches.Count -eq 0) { throw "No release content links found on the index page." }

        $candidates = foreach ($m in $matches) {
            $href = $m.Groups['href'].Value
            $textRaw = $m.Groups['text'].Value
            $text = [regex]::Replace($textRaw, '(?is)<.*?>', '').Trim()

            if ($text -notmatch '(?i)Download\s+Display\s+Driver\s+Uninstaller') { continue }

            $version = 'Unknown'
            $mv = [regex]::Match($text, '(?i)([0-9]+(?:\.[0-9]+)+)')
            if ($mv.Success) { $version = $mv.Groups[1].Value }

            [PSCustomObject]@{
                Url         = Resolve-Url -BaseUrl $IndexURL -Href $href
                Title       = $text
                Version     = $version
                VersionKey  = Get-VersionSortKey -Version $version
            }
        }

        if (-not $candidates -or $candidates.Count -eq 0) {
            throw "Could not extract any valid DDU content links with versions."
        }

        $latest = $candidates | Sort-Object -Property @{Expression='VersionKey';Descending=$true}, @{Expression='Title';Descending=$true} | Select-Object -First 1

        Write-Host "Latest content page: $($latest.Title)" -ForegroundColor Green
        Write-Host "Content URL: $($latest.Url)" -ForegroundColor Gray
        return $latest
    } catch {
        Write-Error "Failed to get latest DDU content URL: $_"
        return $null
    }
}

function Parse-PageForDownloads {
    param(
        [Parameter(Mandatory)][string]$Html,
        [Parameter(Mandatory)][string]$BaseUrl
    )

    # Collect all EXE links that look like DDU
    $linkPattern = '(?is)<a[^>]+href\s*=\s*(["''])(?<url>[^"'']*DDU[^"'']+?\.exe)\1[^>]*>(?<text>.*?)<\/a>'
    $linkMatches = [System.Text.RegularExpressions.Regex]::Matches($Html, $linkPattern)

    # Collect all SHA hashes with their indices
    $sha256Pattern = '(?is)\bSHA(?:\s*-\s*)?256\b[^A-Fa-f0-9]{0,40}([A-Fa-f0-9]{64})'
    $sha1Pattern   = '(?is)\bSHA(?:\s*-\s*)?1\b[^A-Fa-f0-9]{0,40}([A-Fa-f0-9]{40})'
    $sha256All = [System.Text.RegularExpressions.Regex]::Matches($Html, $sha256Pattern)
    $sha1All   = [System.Text.RegularExpressions.Regex]::Matches($Html, $sha1Pattern)

    # Max allowed distance (in characters) to consider a hash "belonging" to a link
    $maxDist = 8000

    $list = foreach ($lm in $linkMatches) {
        $anchorIndex = $lm.Index
        $raw = $lm.Groups['url'].Value
        $textRaw = $lm.Groups['text'].Value
        $text = [regex]::Replace($textRaw, '(?is)<.*?>', '').Trim()

        $url = Resolve-Url -BaseUrl $BaseUrl -Href $raw
        if ($url -notmatch '(?i)DDU') { continue }

        $fileName = [System.IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
        $fileName = [uri]::UnescapeDataString($fileName)
        $lowerName = $fileName.ToLowerInvariant()
        $lowerText = $text.ToLowerInvariant()

        # Prefer installer (setup/installer) over self-extracting/portable
        $isInstaller = ($lowerName -match '(?:^|[-_.\s])(setup|installer)(?:[-_.\s]|$)') -or ($lowerText -match 'setup|installer') -or ($lowerName -match '_setup\.exe$')
        $type = if ($isInstaller) { 'Installer' } else { 'Portable' }

        # Extract version
        $version = 'Unknown'
        $mv = [regex]::Match($fileName, '(?i)DDU(?:\s|%20)?v?([0-9]+(?:\.[0-9]+)+)')
        if ($mv.Success) {
            $version = $mv.Groups[1].Value
        } else {
            $mv = [regex]::Match($text, '(?i)v?([0-9]+(?:\.[0-9]+)+)')
            if ($mv.Success) { $version = $mv.Groups[1].Value }
        }

        # Pair nearest SHA-256 (and SHA-1) to this link
        $nearest256 = $null; $dist256 = $null
        if ($sha256All.Count -gt 0) {
            $nearest256 = ($sha256All | Sort-Object @{ Expression = { [math]::Abs($_.Index - $anchorIndex) } }) | Select-Object -First 1
            $dist256 = [math]::Abs($nearest256.Index - $anchorIndex)
            if ($dist256 -gt $maxDist) { $nearest256 = $null }
        }
        $nearest1 = $null; $dist1 = $null
        if ($sha1All.Count -gt 0) {
            $nearest1 = ($sha1All | Sort-Object @{ Expression = { [math]::Abs($_.Index - $anchorIndex) } }) | Select-Object -First 1
            $dist1 = [math]::Abs($nearest1.Index - $anchorIndex)
            if ($dist1 -gt $maxDist) { $nearest1 = $null }
        }

        $sha256 = if ($nearest256) { $nearest256.Groups[1].Value.ToUpperInvariant() } else { $null }
        $sha1   = if ($nearest1)   { $nearest1.Groups[1].Value.ToUpperInvariant() } else { $null }

        # Optional tiny debug hint
        if ($sha256) {
            Write-Host "Paired SHA256 for $fileName (distance: $dist256)" -ForegroundColor DarkGray
        } else {
            Write-Host "No nearby SHA256 found for $fileName" -ForegroundColor DarkYellow
        }

        $urlHost = try { ([Uri]$url).Host.ToLowerInvariant() } catch { '' }
        $isWagnard = $urlHost -match 'wagnardsoft\.com'

        [PSCustomObject]@{
            Type       = $type
            Url        = $url
            FileName   = $fileName
            SHA1       = $sha1
            SHA256     = $sha256
            Version    = $version
            VersionKey = Get-VersionSortKey -Version $version
            HostScore  = if ($isWagnard) { 1 } else { 0 }
            Distance   = $dist256
        }
    }

    if ($list.Count -gt 1) {
        $list = $list | Group-Object FileName | ForEach-Object { $_.Group | Select-Object -First 1 }
    }

    return $list
}

function Get-ForumThreadURLFromContentPage {
    param([Parameter(Mandatory)][string]$Html, [Parameter(Mandatory)][string]$BaseUrl)
    $m = [regex]::Match($Html, '(?is)href\s*=\s*(["''])(?<href>(?:https?:\/\/(?:www\.)?wagnardsoft\.com)?\/forums\/viewtopic\.php\?t=\d+)\1')
    if ($m.Success) {
        return Resolve-Url -BaseUrl $BaseUrl -Href $m.Groups['href'].Value
    }
    return $null
}

function Get-DDULatestInfo {
    param([Parameter(Mandatory)][string]$IndexURL)

    try {
        $contentInfo = Get-LatestDDUContentURL -IndexURL $IndexURL
        if (-not $contentInfo) { throw "Could not determine latest DDU content page." }

        Write-Host "Fetching latest content page..." -ForegroundColor Cyan
        $contentResp = Invoke-WebRequestCompat -Uri $contentInfo.Url
        $contentHtml = $contentResp.Content

        $downloads = Parse-PageForDownloads -Html $contentHtml -BaseUrl $contentInfo.Url

        # If no direct downloads on content page, try the linked forum thread
        if (-not $downloads -or $downloads.Count -eq 0) {
            $threadUrl = Get-ForumThreadURLFromContentPage -Html $contentHtml -BaseUrl $contentInfo.Url
            if ($threadUrl) {
                Write-Host "No direct downloads on the content page. Following forum thread: $threadUrl" -ForegroundColor Yellow
                $threadResp = Invoke-WebRequestCompat -Uri $threadUrl
                $threadHtml = $threadResp.Content
                $downloads = Parse-PageForDownloads -Html $threadHtml -BaseUrl $threadUrl
            }
        }

        if (-not $downloads -or $downloads.Count -eq 0) {
            throw "No DDU downloads found on the content or forum page."
        }

        # Prefer Installer on wagnardsoft host; then highest version; then closest hash distance
        $preferred = $downloads |
            Sort-Object `
                @{Expression={ if ($_.Type -eq 'Installer') {1} else {0} }; Descending=$true}, `
                @{Expression='HostScore'; Descending=$true}, `
                @{Expression='VersionKey'; Descending=$true}, `
                @{Expression={ if ($_.Distance) { -1 * [int]$_.Distance } else { -999999 } }; Descending=$true} |
            Select-Object -First 1

        if (-not $preferred) { $preferred = $downloads | Select-Object -First 1 }

        if ($preferred.Version -eq 'Unknown' -and $contentInfo.Version -ne 'Unknown') {
            $preferred.Version = $contentInfo.Version
            $preferred.VersionKey = Get-VersionSortKey -Version $preferred.Version
        }

        return $preferred
    }
    catch {
        Write-Error "Failed to retrieve latest DDU info: $_"
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

        Set-RegValue -Path $Path -Name 'SHA256' -Value $Hash -Type 'String'
        Set-RegValue -Path $Path -Name 'DisplayVersion' -Value $Version -Type 'String'
        Set-RegValue -Path $Path -Name 'InstallDate' -Value (Get-Date -Format 'yyyyMMdd') -Type 'String'

        if ($newlyCreated) {
            Set-RegValue -Path $Path -Name 'DisplayName' -Value 'Display Driver Uninstaller' -Type 'String'
            Set-RegValue -Path $Path -Name 'Publisher' -Value 'Wagnardsoft' -Type 'String'
            Set-RegValue -Path $Path -Name 'SystemComponent' -Value 1 -Type 'DWord'
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
Write-Host "Index URL: $DDUIndexURL`n" -ForegroundColor Gray

try {
    # Step 1: Check if DDU executable actually exists
    $dduExists = Test-DDUExecutableExists -Path $DDUExecutablePath

    # Step 2: Get latest DDU info from the releases index -> content page (-> forum if needed)
    $latest = Get-DDULatestInfo -IndexURL $DDUIndexURL
    if (-not $latest) { throw "Could not retrieve latest DDU info." }

    Write-Host "Latest DDU Version: $($latest.Version)" -ForegroundColor Cyan
    Write-Host "Selected file: $($latest.FileName) [$($latest.Type)]" -ForegroundColor Gray
    $shaDisplay = if ($latest.SHA256) { $latest.SHA256 } else { 'N/A' }
    Write-Host "SHA256 (from page): $shaDisplay" -ForegroundColor Gray

    # Step 3: Decide if we need to install/update
    $needInstall = $false
    if (-not $dduExists) {
        $needInstall = $true
        Write-Host "`nDDU executable not found - performing fresh installation" -ForegroundColor Yellow
    } else {
        $storedHash = Get-StoredHash -Path $RegistryPath
        if ($storedHash) {
            Write-Host "`nStored SHA256: $storedHash" -ForegroundColor Gray
            if ($latest.SHA256 -and ($storedHash -eq $latest.SHA256)) {
                Write-Host "`nDDU is already up to date!" -ForegroundColor Green
                return
            } else {
                $needInstall = $true
                Write-Host "`nUpdate available! New installer detected." -ForegroundColor Yellow
            }
        } else {
            $needInstall = $true
            Write-Host "`nDDU found but no registry entry - installing to ensure proper setup" -ForegroundColor Yellow
        }
    }

    if ($needInstall) {
        $installerName = $latest.FileName
        $outputPath = Join-Path $env:TEMP $installerName

        if (Download-File -URL $latest.Url -OutputPath $outputPath) {
            Write-Host "`nVerifying file integrity..." -ForegroundColor Cyan
            $downloadedHash = Get-FileHashSHA256 -FilePath $outputPath

            $proceedInstall = $false
            if ($latest.SHA256) {
                if ($downloadedHash -eq $latest.SHA256) {
                    Write-Host "Hash verification successful!" -ForegroundColor Green
                    $proceedInstall = $true
                } else {
                    Write-Error "Hash verification failed!"
                    Write-Host "Expected: $($latest.SHA256)" -ForegroundColor Red
                    Write-Host "Got:      $downloadedHash" -ForegroundColor Red
                }
            } else {
                Write-Warning "No SHA256 found near the selected link; proceeding with caution."
                $proceedInstall = $true
            }

            if ($proceedInstall) {
                if (Install-Silently -InstallerPath $outputPath) {
                    $hashToSave = if ($latest.SHA256) { $latest.SHA256 } else { $downloadedHash }
                    if (Save-HashToRegistry -Path $RegistryPath -Hash $hashToSave -Version $latest.Version) {
                        Write-Host "`n=== DDU Installation/Update Complete ===" -ForegroundColor Green
                        if (Test-DDUExecutableExists -Path $DDUExecutablePath) {
                            Write-Host "Installation verified successfully!" -ForegroundColor Green
                        } else {
                            Write-Warning "Installation completed but executable not found at expected location"
                        }
                    }
                }
            }

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