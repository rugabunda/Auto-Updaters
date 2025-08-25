## uBlock Origin Classic Auto-Updater for Chrome

Automatically update the classic sideloaded extension. Bypass Googles war on security, evolution and innovation. Re-secure your browsing experience once again by using the classic version of uBlock Origin.

**Automatically download, install, and keep uBlock Origin Classic updated on Chromium-based browsers.** 

### Quick Start
1. Run the script to download uBO to your chosen folder
2. Enable Developer Mode in your browser's extension settings
3. Load the unpacked extension from the download folder
4. Set up a scheduled task to keep uBO automatically updated

Perfect for users who prefer a secure browsing experience or need innovations that google destroys.

---

## Key Features

### 1. **Configuration Section**
- `$UsePreRelease`: Toggle between stable (`$false`) and pre-release/beta (`$true`) versions
- `$UseFirewallRules`: Enable/disable firewall rule management
- `$DestinationFolder`: Set your desired installation path

### 2. **Version Tracking**
- Stores version info in registry at `HKCU:\Software\uBO`
- Separate registry values for stable and pre-release versions
- Only downloads when a new version is detected

### 3. **Smart Download Logic**
- Checks current version against last downloaded version
- Skips download if already up to date
- Shows upgrade information when updating

### 4. **Registry Management**
- Creates registry key if it doesn't exist
- Stores version separately for stable and pre-release tracks
- You can track both independently

### 5. **Enhanced Output**
- Clear status messages
- Shows whether downloading stable or pre-release
- Displays upgrade path (from version X to version Y)
- Color-coded messages for better readability

## Usage Examples

### For stable releases:
```powershell
$UsePreRelease = $false
# Downloads only stable releases and tracks them separately
```

### For pre-release/beta versions:
```powershell
$UsePreRelease = $true
# Downloads latest pre-release and tracks them separately
```

### To check registry values manually:
```powershell
Get-ItemProperty -Path "HKCU:\Software\uBO" | Format-List
```

### To reset version tracking:
```powershell
Remove-Item -Path "HKCU:\Software\uBO" -Force
```