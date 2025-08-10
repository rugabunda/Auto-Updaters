<#
  AutoUpdate-SkuSiPolicy.ps1
  -----------------------
  Mirrors C:\Windows\System32\SecureBootUpdates\SkuSiPolicy.p7b
  to     EFI\Microsoft\Boot\SkuSiPolicy.p7b
  – but only when contents changed (MD5 comparison).

  • A MessageBox appears every time the file really gets copied.
  • Console output is colourful when run interactively; minimal logging when quiet.
  • Only logs significant events (changes, copies, errors) to reduce log verbosity.

  Tested on Windows 11 / PowerShell 5.1
#>

# Needed for [System.Windows.Forms.MessageBox]
Add-Type -AssemblyName System.Windows.Forms

# ------------------------------------------------------------ CONFIG ------
$SystemFile = 'C:\Windows\System32\SecureBootUpdates\SkuSiPolicy.p7b'
$StateFile  = 'C:\Log\SkuSiPolicy.last'     # will contain the last MD5 hash
$LogFile    = 'C:\Log\Update.log'

$EfiLetter  = 'Z'                           # choose a free drive letter
$EfiFile    = "${EfiLetter}:\EFI\Microsoft\Boot\SkuSiPolicy.p7b"
# -------------------------------------------------------------------------

# ---------- helpers -------------------------------------------------------
$IsInteractive = [Environment]::UserInteractive

function Write-Log {
    param(
        [string]       $Text,
        [ConsoleColor] $Colour = 'Gray',
        [switch]       $LogOnly = $false
    )
    
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = "${stamp}: $Text"
    Add-Content -Path $LogFile -Value $line
    
    if ($IsInteractive -and -not $LogOnly) { 
        Write-Host $line -ForegroundColor $Colour 
    }
}

function Write-Console {
    param(
        [string]       $Text,
        [ConsoleColor] $Colour = 'Cyan'
    )
    if ($IsInteractive) { Write-Host $Text -ForegroundColor $Colour }
}

function Write-Hash {
    param(
        [string] $Label,
        [string] $Hash,
        [switch] $LogThis = $false
    )
    
    $message = "${Label}: $Hash"
    
    if ($LogThis) {
        Write-Log $message -Colour Gray
    } else {
        if ($IsInteractive) {
            Write-Host "${Label}: " -ForegroundColor Cyan -NoNewline
            Write-Host $Hash -ForegroundColor Yellow
        }
    }
}

function Get-MD5 {
    param([string]$Path)
    (Get-FileHash -Algorithm MD5 -Path $Path).Hash
}
# -------------------------------------------------------------------------

Write-Console "=== SkuSiPolicy Updater Started ===" -Colour Magenta

# Make sure the log folder exists
$null = New-Item -Path (Split-Path $LogFile) -ItemType Directory -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------- validate source -----
if (-not (Test-Path -Path $SystemFile)) {
    Write-Log "ERROR - source file '${SystemFile}' not found." -Colour Red
    exit 1
}

$currHash = Get-MD5 $SystemFile
Write-Console "Source file: $SystemFile" -Colour Cyan
Write-Hash "Source MD5" $currHash

$needCopy = $true

# ------------------------------------ first run (no .last) ----------------
if (-not (Test-Path -Path $StateFile)) {

    Write-Console "First run detected - no state file found" -Colour Yellow
    Write-Log "FIRST RUN - No state file found, checking EFI partition" -Colour Yellow

    # Mount EFI if necessary
    $mounted = $false
    if (-not (Get-PSDrive -Name $EfiLetter -ErrorAction SilentlyContinue)) {
        Write-Console "Mounting EFI System Partition to ${EfiLetter}:" -Colour Gray
        mountvol "${EfiLetter}:" /S | Out-Null
        $mounted = $true
    } else {
        Write-Console "EFI System Partition already mounted at ${EfiLetter}:" -Colour Gray
    }

    if (Test-Path -Path $EfiFile) {
        $efiHash = Get-MD5 $EfiFile
        Write-Console "Existing EFI file found: $EfiFile" -Colour Cyan
        Write-Hash "EFI file MD5" $efiHash

        if ($efiHash -eq $currHash) {
            Write-Console "[OK] Source and EFI files are identical - no copy needed" -Colour Green
            $currHash | Set-Content -Path $StateFile
            Write-Console "Saved current hash to state file" -Colour Gray
            $needCopy = $false
        } else {
            Write-Console "[!] Files differ - copy will be performed" -Colour Yellow
            Write-Log "FIRST RUN - Files differ, copy required" -Colour Yellow
        }
    } else {
        Write-Console "EFI file does not exist - will be created: $EfiFile" -Colour Yellow
        Write-Log "FIRST RUN - EFI file missing, will create: $EfiFile" -Colour Yellow
    }

    if ($mounted) { 
        Write-Console "Unmounting EFI System Partition" -Colour Gray
        mountvol "${EfiLetter}:" /D | Out-Null 
    }
}

# Nothing left to do?  Exit silently
if (-not $needCopy) { 
    Write-Console "[OK] No action required - exiting" -Colour Green
    Write-Console "=== SkuSiPolicy Updater Completed ===" -Colour Magenta
    return 
}

# --------------------------------------- normal run -----------------------
if (Test-Path -Path $StateFile) {
    $prevHash = (Get-Content -Path $StateFile).Trim()
    Write-Console "Previous hash from state file:" -Colour Cyan
    Write-Console "  $prevHash" -Colour DarkYellow
    Write-Hash "Current hash " $currHash
    
    if ($prevHash -eq $currHash) {
        Write-Console "[OK] No changes detected - files are identical" -Colour Green
        Write-Console "=== SkuSiPolicy Updater Completed ===" -Colour Magenta
        return
    } else {
        Write-Console "[CHANGE] CHANGE DETECTED - Source file has been updated!" -Colour Red
        Write-Log "CHANGE DETECTED - Hash changed from $prevHash to $currHash" -Colour Yellow
    }
}

# ------------------------------------ perform copy ------------------------
Write-Console "Preparing to copy updated file to EFI partition..." -Colour Yellow
Write-Log "COPY OPERATION - Starting file copy to EFI partition" -Colour Cyan

$mounted = $false
if (-not (Get-PSDrive -Name $EfiLetter -ErrorAction SilentlyContinue)) {
    Write-Console "Mounting EFI System Partition to ${EfiLetter}:" -Colour Gray
    mountvol "${EfiLetter}:" /S | Out-Null
    $mounted = $true
} else {
    Write-Console "EFI System Partition already mounted at ${EfiLetter}:" -Colour Gray
}

try {
    if ($IsInteractive) {
        Write-Host "Copying: " -ForegroundColor Cyan -NoNewline
        Write-Host "$SystemFile" -ForegroundColor White -NoNewline
        Write-Host " -> " -ForegroundColor DarkGray -NoNewline
        Write-Host "$EfiFile" -ForegroundColor White
    }
    
    Copy-Item -Path $SystemFile -Destination $EfiFile -Force
    Write-Console "[SUCCESS] File successfully copied to EFI partition!" -Colour Green
    Write-Log "SUCCESS - File copied: $SystemFile -> $EfiFile" -Colour Green

    # Verify the copy
    $newEfiHash = Get-MD5 $EfiFile
    Write-Hash "Verification - EFI file MD5" $newEfiHash -LogThis
    
    if ($newEfiHash -eq $currHash) {
        Write-Console "[VERIFIED] Copy successful, hashes match" -Colour Green
        Write-Log "VERIFIED - Copy successful, hash verification passed" -Colour Green
        
        # Suggest reboot
        Write-Console "" # blank line
        Write-Console "[REBOOT RECOMMENDED] Please restart your computer for changes to take effect" -Colour Yellow
        Write-Log "REBOOT RECOMMENDED - Changes require restart to take effect" -Colour Yellow
        
    } else {
        Write-Console "[WARNING] Hash mismatch after copy!" -Colour Red
        Write-Log "WARNING - Hash mismatch after copy! Expected: $currHash, Got: $newEfiHash" -Colour Red
    }

    # Show popup notification with reboot recommendation (works in scheduled tasks too)
    [System.Windows.Forms.MessageBox]::Show(
        "SkuSiPolicy.p7b has been updated and mirrored to the EFI partition.`n`nA system restart is recommended for changes to take effect.",
        'SkuSiPolicy Update - Restart Recommended',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
catch {
    Write-Console "[ERROR] Copy operation failed: $($_.Exception.Message)" -Colour Red
    Write-Log "ERROR - Copy operation failed: $($_.Exception.Message)" -Colour Red
}
finally {
    if ($mounted) { 
        Write-Console "Unmounting EFI System Partition" -Colour Gray
        mountvol "${EfiLetter}:" /D | Out-Null 
    }
}

# ------------------------------------- save new state ---------------------
$currHash | Set-Content -Path $StateFile
Write-Console "Updated state file with new hash" -Colour Gray
Write-Log "STATE UPDATED - New hash saved: $currHash" -Colour Cyan
Write-Console "=== SkuSiPolicy Updater Completed ===" -Colour Magenta
