<#
  AutoUpdate-SkuSiPolicy.ps1
  -----------------------
  Mirrors C:\Windows\System32\SecureBootUpdates\SkuSiPolicy.p7b
  to     EFI\Microsoft\Boot\SkuSiPolicy.p7b
  – but only when contents changed (MD5 comparison).

  • A MessageBox appears every time the file really gets copied.
  • If running as SYSTEM, creates a self-deleting scheduled task for interactive notification.
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

function Test-IsSystemAccount {
    # Check if running as SYSTEM account
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return ($currentUser.Name -eq "NT AUTHORITY\SYSTEM")
}

function New-InteractiveNotificationTask {
    param(
        [string]$Message = "SkuSiPolicy.p7b Updated - Reboot Recommended to Apply Changes"
    )
    
    try {
        # Generate unique task name to avoid conflicts
        $taskName = "SkuSiPolicyNotify_$(Get-Date -Format 'yyyyMMddHHmmss')"
        
        Write-Console "Creating interactive notification task..." -Colour Gray
        Write-Log "Creating interactive notification task: $taskName" -Colour Gray
        
        # Create self-deleting task to notify all users of update
        $taskCommand = 'schtasks /create /tn "{0}" /tr "cmd /c (msg * \`"{1}\`") && (schtasks /delete /tn \`"{0}\`" /f)" /sc once /st 00:00 /ru SYSTEM /rl highest /f' -f $taskName, $Message
        
        # Create the task
        $result = Invoke-Expression $taskCommand 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Console "Notification task created successfully" -Colour Green
            Write-Log "Notification task created: $taskName" -Colour Green
            
            # Run the task immediately
            $runResult = schtasks /run /tn $taskName 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Console "Interactive notification triggered" -Colour Green
                Write-Log "Interactive notification triggered successfully" -Colour Green
                return $true
            } else {
                Write-Console "Failed to trigger notification: $runResult" -Colour Yellow
                Write-Log "Failed to trigger notification: $runResult" -Colour Yellow
                # Try to clean up the task
                schtasks /delete /tn $taskName /f 2>$null | Out-Null
                return $false
            }
        } else {
            Write-Console "Failed to create notification task: $result" -Colour Yellow
            Write-Log "Failed to create notification task: $result" -Colour Yellow
            return $false
        }
    }
    catch {
        Write-Console "Exception creating notification task: $_" -Colour Yellow
        Write-Log "Exception creating notification task: $_" -Colour Yellow
        return $false
    }
}

function Show-UpdateNotification {
    param(
        [string]$Message = "SkuSiPolicy.p7b has been updated and mirrored to the EFI partition.`n`nA system restart is recommended for changes to take effect."
    )
    
    $isSystem = Test-IsSystemAccount
    
    if ($isSystem) {
        Write-Console "Running as SYSTEM - using scheduled task for notification" -Colour Gray
        Write-Log "Running as SYSTEM account, creating interactive notification" -Colour Gray
        
        # Create an interactive notification task
        $notificationSent = New-InteractiveNotificationTask -Message "SkuSiPolicy.p7b Updated - Reboot Recommended to Apply Changes"
        
        if (-not $notificationSent) {
            Write-Console "Failed to create interactive notification, falling back to log entry" -Colour Yellow
            Write-Log "NOTIFICATION: $Message" -Colour Yellow
        }
    } else {
        # Running as regular user - show MessageBox directly (already has no timeout)
        Write-Console "Showing notification dialog..." -Colour Gray
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            'SkuSiPolicy Update - Restart Recommended',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
}
# -------------------------------------------------------------------------

Write-Console "=== SkuSiPolicy Updater Started ===" -Colour Magenta

# Log if running as SYSTEM
if (Test-IsSystemAccount) {
    Write-Console "Running as SYSTEM account" -Colour Gray
    Write-Log "Running as SYSTEM account" -Colour Gray
}

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
        
        # Show notification (handles both SYSTEM and user contexts)
        Show-UpdateNotification
        
    } else {
        Write-Console "[WARNING] Hash mismatch after copy!" -Colour Red
        Write-Log "WARNING - Hash mismatch after copy! Expected: $currHash, Got: $newEfiHash" -Colour Red
    }
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
