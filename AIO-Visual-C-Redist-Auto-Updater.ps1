# Variables
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$tagFilePath = Join-Path -Path $scriptDir -ChildPath "latest_tag.txt"
$releaseInfoPath = Join-Path -Path $scriptDir -ChildPath "release_info.json"
$downloadDir = $scriptDir
$requiredFileName = "VisualCppRedist_AIO_x86_x64.exe"
$apiUrl = "https://api.github.com/repos/abbodi1406/vcredist/releases"

# Fetch all releases (including prereleases)
$releases = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "Mozilla/5.0" }

# Get the most recent release (first in the array, whether prerelease or not)
$latestRelease = $releases[0]
$latestTag = $latestRelease.tag_name
$isPrerelease = $latestRelease.prerelease
$releaseId = $latestRelease.id
$assets = $latestRelease.assets

# Create current release info object
$currentReleaseInfo = @{
    tag = $latestTag
    prerelease = $isPrerelease
    releaseId = $releaseId
} | ConvertTo-Json

# Check if release info file exists and compare
$shouldInstall = $true
if (Test-Path -Path $releaseInfoPath) {
    $savedReleaseInfo = Get-Content -Path $releaseInfoPath | ConvertFrom-Json
    
    # Install if:
    # 1. Tag is different (new version)
    # 2. Same tag but was prerelease and now is official release
    # 3. Different release ID (ensures we catch any updates)
    if ($savedReleaseInfo.tag -eq $latestTag -and 
        $savedReleaseInfo.releaseId -eq $releaseId) {
        $shouldInstall = $false
        Write-Output "No new updates. Current version: $latestTag (Prerelease: $isPrerelease)"
        Write-Output "Exiting script."
        return
    }
    
    if ($savedReleaseInfo.tag -eq $latestTag -and 
        $savedReleaseInfo.prerelease -eq $true -and 
        $isPrerelease -eq $false) {
        Write-Output "Official release available for version $latestTag (replacing prerelease)"
    } elseif ($savedReleaseInfo.tag -ne $latestTag) {
        Write-Output "New version available: $latestTag (Prerelease: $isPrerelease)"
    }
}

# Save the new release info
Set-Content -Path $releaseInfoPath -Value $currentReleaseInfo

# Check and download the required asset
foreach ($asset in $assets) {
    if ($asset.name -eq $requiredFileName) {
        $downloadUrl = $asset.browser_download_url
        $filePath = Join-Path -Path $downloadDir -ChildPath $asset.name

        Write-Output "Downloading $requiredFileName..."
        Write-Output "Version: $latestTag | Prerelease: $isPrerelease"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $filePath
        Write-Output "$requiredFileName downloaded successfully."

        # Print output when installing the redist
        Write-Output "Installing $requiredFileName..."

        # Silent install command
        Start-Process -FilePath $filePath -ArgumentList "/ai /gm2" -NoNewWindow -Wait

        # Delete the downloaded file after execution
        Remove-Item -Path $filePath -Force
        Write-Output "$requiredFileName deleted after execution."
        break
    }
}

# Clean up old tag file if it exists (migrating to new format)
if (Test-Path -Path $tagFilePath) {
    Remove-Item -Path $tagFilePath -Force
}

#Examples:

#Automatically install all packages and display progress:  
#VisualCppRedist_AIO_x86_x64.exe /y

#Silently install all packages and display no progress:  
#VisualCppRedist_AIO_x86_x64.exe /ai /gm2

#Silently install 2022 package:  
#VisualCppRedist_AIO_x86_x64.exe /ai9

#Silently install 2010/2012/2013/2022 packages:  
#VisualCppRedist_AIO_x86_x64.exe /aiX239

#Silently install VSTOR and Extra VB/C packages:  
#VisualCppRedist_AIO_x86_x64.exe /aiTE

#Silently install all packages and hide ARP entries:  
#VisualCppRedist_AIO_x86_x64.exe /aiA /gm2