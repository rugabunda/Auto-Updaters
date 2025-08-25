
```

## Key Features:

### 1. **Configuration Section**:
- `$UsePreRelease`: Toggle between stable (`$false`) and pre-release/beta (`$true`) versions
- `$UseFirewallRules`: Enable/disable firewall rule management
- `$DestinationFolder`: Set your desired installation path

### 2. **Version Tracking**:
- Stores version info in registry at `HKCU:\Software\uBO`
- Separate registry values for stable and pre-release versions
- Only downloads when a new version is detected

### 3. **Smart Download Logic**:
- Checks current version against last downloaded version
- Skips download if already up to date
- Shows upgrade information when updating

### 4. **Registry Management**:
- Creates registry key if it doesn't exist
- Stores version separately for stable and pre-release tracks
- You can track both independently

### 5. **Enhanced Output**:
- Clear status messages
- Shows whether downloading stable or pre-release
- Displays upgrade path (from version X to version Y)
- Color-coded messages for better readability

## Usage Examples:

**For stable releases:**
```powershell
$UsePreRelease = $false
# Downloads only stable releases and tracks them separately
```

**For pre-release/beta versions:**
```powershell
$UsePreRelease = $true
# Downloads latest pre-release and tracks them separately
```

**To check registry values manually:**
```powershell
Get-ItemProperty -Path "HKCU:\Software\uBO" | Format-List
```

**To reset version tracking:**
```powershell
Remove-Item -Path "HKCU:\Software\uBO" -Force
```

The script now efficiently manages updates, avoiding unnecessary downloads while keeping track of which version type you're using.