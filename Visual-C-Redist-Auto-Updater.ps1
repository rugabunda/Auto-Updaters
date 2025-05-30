netsh advfirewall firewall set rule name="Windows PowerShell (powershell.exe)" new enable=yes
# Variables
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$tagFilePath = Join-Path -Path $scriptDir -ChildPath "latest_tag.txt"
$downloadDir = $scriptDir
$requiredFileName = "VisualCppRedist_AIO_x86_x64.exe"
$apiUrl = "https://api.github.com/repos/abbodi1406/vcredist/releases/latest"

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
    if ($asset.name -eq $requiredFileName) {
        $downloadUrl = $asset.browser_download_url
        $filePath = Join-Path -Path $downloadDir -ChildPath $asset.name

        Write-Output "Downloading $requiredFileName..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $filePath
        Write-Output "$requiredFileName downloaded successfully."

netsh advfirewall firewall set rule name="Windows PowerShell (powershell.exe)" new enable=no

        # Silent install command
        Start-Process -FilePath $filePath -ArgumentList "/ai /gm2" -NoNewWindow -Wait

        # Delete the downloaded file after execution
        Remove-Item -Path $filePath -Force
        Write-Output "$requiredFileName deleted after execution."
    }
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
