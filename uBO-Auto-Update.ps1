# ============================
# CONFIGURATION SECTION
# ============================
$DestinationFolder = "F:\ubo\uBlock0_1.65.1b8.chromium\uBlock0.chromium"  # Change this to your desired folder
$UseFirewallRules = $true                    # Set to $false to disable firewall rule management
$UsePreRelease = $true                       # Set to $true for pre-release/beta versions, $false for stable

# Registry settings
$RegistryPath = "HKCU:\Software\uBO"         # Registry path for storing version info
$RegistryValue = if ($UsePreRelease) { "LastPreReleaseVersion" } else { "LastStableVersion" }

# ============================
# FUNCTIONS
# ============================

function Get-LastDownloadedVersion {
    if (Test-Path $RegistryPath) {
        $regValue = Get-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
        if ($regValue) {
            return $regValue.$RegistryValue
        }
    }
    return $null
}

function Set-LastDownloadedVersion {
    param([string]$Version)
    
    if (!(Test-Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RegistryPath -Name $RegistryValue -Value $Version
}

function Enable-FirewallRuleIfNeeded {
    if ($UseFirewallRules) {
        Write-Host "Enabling firewall rule for network access..." -ForegroundColor Yellow
        try {
            Set-NetFirewallRule -DisplayName "Windows PowerShell (powershell.exe)" -Enabled True -ErrorAction Stop
            Start-Sleep -Milliseconds 150  # Small delay to ensure rule takes effect
            return $true
        } catch {
            Write-Host "Warning: Could not modify firewall rule. Admin rights may be required." -ForegroundColor Yellow
            Write-Host "Attempting to continue anyway..." -ForegroundColor Yellow
            return $false
        }
    }
    return $false
}

function Disable-FirewallRuleIfNeeded {
    param([bool]$WasEnabled)
    
    if ($UseFirewallRules -and $WasEnabled) {
        Write-Host "Disabling firewall rule..." -ForegroundColor Yellow
        try {
            Set-NetFirewallRule -DisplayName "Windows PowerShell (powershell.exe)" -Enabled False -ErrorAction Stop
        } catch {
            Write-Host "Warning: Could not disable firewall rule." -ForegroundColor Yellow
        }
    }
}

# ============================
# MAIN SCRIPT
# ============================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "uBlock Origin Downloader" -ForegroundColor Cyan
Write-Host "Mode: $(if ($UsePreRelease) { 'Pre-Release/Beta' } else { 'Stable' })" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

# Check last downloaded version
$lastVersion = Get-LastDownloadedVersion
if ($lastVersion) {
    Write-Host "Last downloaded version: $lastVersion" -ForegroundColor Gray
} else {
    Write-Host "No previous version found in registry" -ForegroundColor Gray
}

$firewallWasEnabled = $false

try {
    # Enable firewall BEFORE any network requests
    $firewallWasEnabled = Enable-FirewallRuleIfNeeded
    
    Write-Host "Fetching latest uBlock Origin release information..." -ForegroundColor Cyan
    
    # Set up API request
    $headers = @{
        "User-Agent" = "PowerShell/uBlockDownloader"
    }
    
    # Determine API URL based on release type preference
    if ($UsePreRelease) {
        # Get all releases and pick the first one (latest, including pre-releases)
        $apiUrl = "https://api.github.com/repos/gorhill/uBlock/releases"
        $releaseInfo = (Invoke-RestMethod -Uri $apiUrl -Headers $headers)[0]
    } else {
        # Get only the latest stable release
        $apiUrl = "https://api.github.com/repos/gorhill/uBlock/releases/latest"
        $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers
    }
    
    $currentVersion = $releaseInfo.tag_name
    $isPreRelease = $releaseInfo.prerelease
    
    Write-Host "Latest available version: $currentVersion $(if ($isPreRelease) { '(Pre-Release)' } else { '(Stable)' })" -ForegroundColor Green
    
    # Check if we need to download
    if ($lastVersion -eq $currentVersion) {
        Write-Host "Already up to date! No download needed." -ForegroundColor Green
        Write-Host "Destination folder: $DestinationFolder" -ForegroundColor Gray
        
        # Disable firewall before exiting
        Disable-FirewallRuleIfNeeded -WasEnabled $firewallWasEnabled
        exit 0
    }
    
    Write-Host "New version available! Proceeding with download..." -ForegroundColor Yellow
    
    # Find the Chromium asset
    $chromiumAsset = $releaseInfo.assets | Where-Object { $_.name -like "*chromium.zip" }
    
    if (!$chromiumAsset) {
        throw "Could not find Chromium release asset"
    }
    
    $downloadUrl = $chromiumAsset.browser_download_url
    $assetName = $chromiumAsset.name
    
    Write-Host "Download URL: $downloadUrl" -ForegroundColor Gray
    
    # Ensure destination folder exists
    if (!(Test-Path $DestinationFolder)) {
        New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        Write-Host "Created destination folder: $DestinationFolder" -ForegroundColor Green
    }
    
    # Prepare temp paths
    $tempFolder = Join-Path $env:TEMP "uBlock_temp_$(Get-Random)"
    $zipPath = Join-Path $tempFolder $assetName
    
    # Create temp folder
    New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
    
    try {
        # Download the file (firewall should already be enabled if needed)
        Write-Host "Downloading $assetName..." -ForegroundColor Cyan
        $ProgressPreference = 'SilentlyContinue'  # Speeds up Invoke-WebRequest
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -Headers $headers
        $ProgressPreference = 'Continue'
        
        # Disable firewall immediately after download
        Disable-FirewallRuleIfNeeded -WasEnabled $firewallWasEnabled
        $firewallWasEnabled = $false  # Mark as disabled so we don't try again in finally block
        
        Write-Host "Download complete. Extracting..." -ForegroundColor Green
        
        # Extract the zip file
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tempFolder)
        
        # The structure is: zipfile.zip contains uBlock0.chromium folder directly
        $innerFolder = Join-Path $tempFolder "uBlock0.chromium"
        
        if (!(Test-Path $innerFolder)) {
            # If not found directly, look for it in any subfolder (fallback for different structure)
            $searchPath = Get-ChildItem -Path $tempFolder -Directory -Recurse | Where-Object { $_.Name -eq "uBlock0.chromium" } | Select-Object -First 1
            if ($searchPath) {
                $innerFolder = $searchPath.FullName
            } else {
                throw "Could not find uBlock0.chromium folder in extracted contents"
            }
        }
        
        Write-Host "Found extension folder at: $innerFolder" -ForegroundColor Gray
        
        # Clear destination folder if it exists
        if (Test-Path $DestinationFolder) {
            Write-Host "Cleaning destination folder..." -ForegroundColor Yellow
            Get-ChildItem -Path $DestinationFolder -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        
        # Copy the inner folder contents to destination
        Write-Host "Copying extension files to $DestinationFolder..." -ForegroundColor Cyan
        
        # Get all items from the inner folder
        Get-ChildItem -Path $innerFolder | ForEach-Object {
            $destPath = Join-Path $DestinationFolder $_.Name
            if ($_.PSIsContainer) {
                Copy-Item -Path $_.FullName -Destination $destPath -Recurse -Force
            } else {
                Copy-Item -Path $_.FullName -Destination $destPath -Force
            }
        }
        
        # Save version to registry
        Set-LastDownloadedVersion -Version $currentVersion
        Write-Host "Saved version $currentVersion to registry" -ForegroundColor Green
        
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Successfully installed uBlock Origin" -ForegroundColor Green
        Write-Host "Version: $currentVersion $(if ($isPreRelease) { '(Pre-Release)' } else { '(Stable)' })" -ForegroundColor Green
        Write-Host "Location: $DestinationFolder" -ForegroundColor Green
        if ($lastVersion) {
            Write-Host "Upgraded from: $lastVersion" -ForegroundColor Gray
        }
        Write-Host "========================================" -ForegroundColor Green
        
    } finally {
        # Clean up temp folder
        if (Test-Path $tempFolder) {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    
    # Show more error details
    if ($_.Exception.InnerException) {
        Write-Host "Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    
    exit 1
    
} finally {
    # Ensure firewall rule is disabled
    Disable-FirewallRuleIfNeeded -WasEnabled $firewallWasEnabled
}