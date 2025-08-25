# DriverStoreExplorer Auto-Updater

A PowerShell script that automatically downloads and installs the latest version of DriverStoreExplorer from GitHub.

## Features
- Checks for new releases and skips if already up-to-date
- Downloads and extracts to specified directory
- Optional firewall control during download
- Cleans up downloaded files after extraction

## Configuration

### Required Settings
```powershell
$installDir = "C:\path\to\"  # Set your installation directory
```

### Optional Settings
```powershell
$controlFirewall = $false  # Set to $true to manage firewall during download
```

## Usage

1. Edit the script to set your desired install directory
2. Run the script manually or via Task Scheduler for automatic updates
3. Script will only download when a new version is available

## Requirements
- PowerShell 5.0+
- Internet connection
- Administrator rights (if firewall control is enabled)

## How It Works
1. Queries GitHub API for latest release
2. Compares with saved version tag
3. Downloads new version if available
4. Extracts to installation directory
5. Cleans up temporary files