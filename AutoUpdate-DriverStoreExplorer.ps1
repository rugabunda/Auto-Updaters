# DriverStoreExplorer Auto-Update Script
# This script automatically downloads and extracts the latest DriverStoreExplorer
# to the specified install directory, overwriting any existing files.
# Change the $installDir variable below to customize the installation location.

# INSTALL DIRECTORY - Change this path to where you want DriverStoreExplorer installed
$installDir = "C:\path\to\"

# FIREWALL CONTROL
$controlFirewall = $false  # Default: false

# Variables
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$tagFilePath = Join-Path -Path $scriptDir -ChildPath "dse_latest_tag.txt"
$downloadDir = $scriptDir
$apiUrl = "https://api.github.com/repos/lostindark/DriverStoreExplorer/releases/latest"

# Fetch latest release data
$response = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "Mozilla/5.0" }
$latestTag = $response.tag_name
$assets = $response.assets

# Check if a tag file exists and read its value
if (Test-Path -Path $tagFilePath) {
    $savedTag = Get-Content -Path $tagFilePath
    if ($savedTag -eq $latestTag) {
        Write-Output "No new updates. Exiting script."
        return
    }
}

# Save the new tag to the tag file
Set-Content -Path $tagFilePath -Value $latestTag

# Check and download the required asset
foreach ($asset in $assets) {
    if ($asset.name -like "DriverStoreExplorer*.zip") {
        $downloadUrl = $asset.browser_download_url
        $zipPath = Join-Path -Path $downloadDir -ChildPath $asset.name

        Write-Output "Downloading $($asset.name)..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
        Write-Output "$($asset.name) downloaded successfully."

        # Disable firewall for PowerShell if option is enabled
        if ($controlFirewall) {
            Set-NetFirewallRule -DisplayName "Windows PowerShell (powershell.exe)" -Enabled False
            Write-Output "PowerShell firewall rule temporarily disabled."
        }

        # Create install directory if it doesn't exist
        if (-not (Test-Path -Path $installDir)) {
            New-Item -ItemType Directory -Path $installDir -Force
            Write-Output "Created install directory: $installDir"
        }

        Write-Output "Extracting $($asset.name) to $installDir..."
        
        # Extract ZIP and overwrite existing files
        Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
        
        Write-Output "DriverStoreExplorer extracted successfully to $installDir"

        # Re-enable firewall for PowerShell if it was disabled
        if ($controlFirewall) {
            Set-NetFirewallRule -DisplayName "Windows PowerShell (powershell.exe)" -Enabled True
            Write-Output "PowerShell firewall rule re-enabled."
        }

        # Delete the downloaded ZIP file
        Remove-Item -Path $zipPath -Force
        Write-Output "Downloaded ZIP file deleted after extraction."
        
        break
    }
}