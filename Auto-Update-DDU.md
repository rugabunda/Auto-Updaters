# DDU Auto-Update Script

Automatically installs or updates Display Driver Uninstaller (DDU) to the latest version by checking the official Wagnardsoft forums.

## Features

- **Auto-discovery**: Automatically finds the latest DDU release thread on the forums
- **Hash verification**: Verifies SHA-256 integrity of downloaded files
- **Smart detection**: Only downloads/installs when:
  - DDU is not installed
  - A newer version is available
  - Installation is corrupted (executable missing)
- **Silent installation**: Installs DDU without user interaction
- **Registry tracking**: Stores version info to track updates

## Requirements

- Windows PowerShell 5.1 or later
- Administrator privileges
- Internet connection

## Usage

### Quick Run
```powershell
# Right-click and "Run with PowerShell" as Administrator
.\DDU-AutoUpdate.ps1
```

### Command Line
```powershell
# Run with default settings
powershell -ExecutionPolicy Bypass -File "DDU-AutoUpdate.ps1"

# Specify custom DDU installation path
powershell -ExecutionPolicy Bypass -File "DDU-AutoUpdate.ps1" -DDUExecutablePath "D:\Tools\DDU\Display Driver Uninstaller.exe"
```

### Scheduled Task
Create a scheduled task to run every 6 hours:
```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Scripts\DDU-AutoUpdate.ps1`""
$trigger = New-ScheduledTaskTrigger -Daily -At 12am
$trigger.Repetition.Interval = "PT6H"  # Repeat every 6 hours
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "DDU Auto-Update" -Action $action -Trigger $trigger -Principal $principal
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DDUForumListURL` | `https://www.wagnardsoft.com/forums/viewforum.php?f=5` | Forum listing page URL |
| `RegistryPath` | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Display Driver Uninstaller` | Registry location for tracking |
| `DDUExecutablePath` | `C:\Program Files (x86)\Display Driver Uninstaller\Display Driver Uninstaller.exe` | DDU installation path |

## How It Works

1. **Discovers** the latest DDU thread from the forum listing
2. **Fetches** the latest version info and SHA-256 hashes
3. **Compares** with installed version (if any)
4. **Downloads** the installer if update needed
5. **Verifies** file integrity via SHA-256
6. **Installs** silently with `/S` flag
7. **Updates** registry with version info

## Notes

- Script requires Administrator privileges for registry access and installation
- Automatically handles 32/64-bit PowerShell environments
- Downloads are saved temporarily to `%TEMP%` and cleaned up after installation
- Only tracks the installer version (not the portable version)

## License

This script is provided as-is for automating DDU updates. DDU itself is developed by Wagnardsoft.