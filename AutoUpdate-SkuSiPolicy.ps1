<#
  AutoUpdate-SkuSiPolicy.ps1
  -----------------------
  Mirrors C:\Windows\System32\SecureBootUpdates\SkuSiPolicy.p7b
  to     EFI\Microsoft\Boot\SkuSiPolicy.p7b
  – if none found or on file change.

  • A MessageBox appears every time SkuSiPolicy.p7b is updated (when interactive).
  • If running as SYSTEM, creates a self-deleting scheduled task for interactive notification.
  • Console output is colourful when run interactively; minimal logging when quiet.
  • Only logs significant events (changes, copies, errors) to reduce log verbosity.

  Tested on Windows 11 / PowerShell 5.1
#>

# Needed for [System.Windows.Forms.MessageBox]
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

# ------------------------------------------------------------ CONFIG ------
$SystemFile = 'C:\Windows\System32\SecureBootUpdates\SkuSiPolicy.p7b'
$StateFile  = 'C:\Log\SkuSiPolicy.last'     # will contain the last MD5 hash
$LogFile    = 'C:\Log\Update.log'
# Drive letters to try when mounting the EFI System Partition (ESP) if not already mounted
$EfiLetters = @('S','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')
# -------------------------------------------------------------------------

# ---------- helpers -------------------------------------------------------
$IsInteractive = [Environment]::UserInteractive

function Write-SessionStatus {
    if (Test-IsSystemAccount) {
        Write-Console "Running as SYSTEM account" -Colour Gray
        Write-Log "Running as SYSTEM account" -Colour Gray
    }
    if (-not $IsInteractive) {
        Write-Log "Running in non-interactive mode" -Colour Gray
    }
}

function Write-Log {
    param(
        [string]       $Text,
        [ConsoleColor] $Colour = 'Gray',
        [switch]       $LogOnly = $false
    )
    # Dates only in log file; do not echo timestamps to console
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = "${stamp}: $Text"
    Add-Content -Path $LogFile -Value $line
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
        [string]$Message = "SkuSiPolicy.p7b has been updated and mirrored to the EFI partition."
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
    } elseif ($IsInteractive) {
        # Running as regular user in interactive session - show MessageBox directly
        try {
            Write-Console "Showing notification dialog..." -Colour Gray
            [System.Windows.Forms.MessageBox]::Show(
                $Message,
                'SkuSiPolicy Update - Restart Recommended',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        catch {
            Write-Console "Could not show interactive dialog: $_" -Colour Yellow
            Write-Log "NOTIFICATION (could not display): $Message" -Colour Yellow
        }
    } else {
        # Non-interactive session (like S4U task)
        Write-Log "$Message" -Colour Yellow
    }
}

# --- TRUE when drive looks like Windows install ISO / USB ----------------
function Find-Or-MountEfi {
    param([string[]]$Letters = $EfiLetters)

    # 1) Already mounted? Use it (exclude Windows install media)
    $existing = gdr -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object {
            $r = $_.Root
            $hasEfi = Test-Path ($r + 'EFI')
            $isIso  = (Test-Path ($r + 'setup.exe')) -or
                      (Test-Path ($r + 'sources\install.wim')) -or
                      (Test-Path ($r + 'sources\install.esd'))
            $hasEfi -and -not $isIso
        } | Select-Object -First 1

    if ($existing) {
        return [pscustomobject]@{ Letter = $existing.Name; MountedByUs = $false }
    }

    # 2) Not mounted: try to mount to the first free letter in $Letters
    foreach ($l in $Letters) {
        if (-not (Get-PSDrive -Name $l -ErrorAction SilentlyContinue)) {
            try { mountvol "$($l):" /S | Out-Null } catch {}

            $root   = "$($l):\"
            $hasEfi = Test-Path ($root + 'EFI')
            $isIso  = (Test-Path ($root + 'setup.exe')) -or
                      (Test-Path ($root + 'sources\install.wim')) -or
                      (Test-Path ($root + 'sources\install.esd'))

            if ($hasEfi -and -not $isIso) {
                return [pscustomobject]@{ Letter = $l; MountedByUs = $true }
            }

            # Clean up if the mount didn't result in the ESP or was an ISO
            try { mountvol "$($l):" /D | Out-Null } catch {}
        }
    }

    $null
}
# -------------------------------------------------------------------------

Write-Console "=== SkuSiPolicy Updater Started ===" -Colour Magenta

# Make sure the log folder exists as early as possible
$null = New-Item -Path (Split-Path $LogFile) -ItemType Directory -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------- validate source -----
if (-not (Test-Path -Path $SystemFile)) {
    Write-Log "ERROR - source file '${SystemFile}' not found." -Colour Red
    exit 1
}

$currHash = Get-MD5 $SystemFile
Write-Console "Source file: $SystemFile" -Colour Cyan
Write-Hash "Source MD5" $currHash

# Mount or find EFI partition
$esp = Find-Or-MountEfi
if (-not $esp) {
    Write-Console "[ERROR] Could not locate or mount the EFI System Partition" -Colour Red
    Write-Log "ERROR - Could not locate or mount the EFI System Partition" -Colour Red
    exit 2
}

$EfiLetter = $esp.Letter
$EfiFile   = "${EfiLetter}:\EFI\Microsoft\Boot\SkuSiPolicy.p7b"

if ($esp.MountedByUs) {
    Write-Log "Mounted EFI System Partition at ${EfiLetter}:" -Colour Gray
} else {
    Write-Log "EFI System Partition already mounted at ${EfiLetter}:" -Colour Gray
}

$needCopy = $false

if (-not (Test-Path -Path $EfiFile)) {
    Write-Console "EFI file missing - copy required: $EfiFile" -Colour Yellow
    Write-Log "EFI file missing - will create: $EfiFile" -Colour Yellow
    Write-SessionStatus
    $needCopy = $true
} else {
    $efiHash = Get-MD5 $EfiFile
    Write-Console "Checking EFI file: $EfiFile" -Colour Cyan
    Write-Hash "EFI file MD5" $efiHash

    if ($efiHash -ne $currHash) {
        Write-Console "[CHANGE] Files differ - copy required" -Colour Yellow
        Write-Log "CHANGE DETECTED - Files differ, copy required" -Colour Yellow
        Write-SessionStatus
        $needCopy = $true
    } else {
        Write-Console "[OK] Source and EFI files are identical" -Colour Green
        if ($esp.MountedByUs) { 
            mountvol "${EfiLetter}:" /D | Out-Null 
        }
        Write-Console "=== SkuSiPolicy Updater Completed ===" -Colour Magenta
        exit 0
    }
}

# Perform copy if needed
if ($needCopy) {
    
    Write-Console "Copying updated file to EFI partition..." -Colour Yellow
    Write-Log "Copying updated file to EFI partition..." -Colour Cyan

    $copySuccess = $false

    try {
        if ($IsInteractive) {
            Write-Host "Copying: " -ForegroundColor Cyan -NoNewline
            Write-Host "$SystemFile" -ForegroundColor White -NoNewline
            Write-Host " -> " -ForegroundColor DarkGray -NoNewline
            Write-Host "$EfiFile" -ForegroundColor White
        }
        
        # Ensure target directory exists
        $targetDir = Split-Path -Path $EfiFile -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Copy-Item -Path $SystemFile -Destination $EfiFile -Force
        Write-Console "[SUCCESS] File successfully copied to EFI partition!" -Colour Green
        Write-Log "File copied: $SystemFile -> $EfiFile" -Colour Green

        # Verify the copy
        $newEfiHash = Get-MD5 $EfiFile
        Write-Hash "Verification - EFI file MD5" $newEfiHash -LogThis
        
        if ($newEfiHash -eq $currHash) {
            Write-Console "[VERIFIED] Copy successful, hashes match" -Colour Green
            Write-Log "Copy successful, hash verification passed" -Colour Green
            $copySuccess = $true
            
            # Set registry to provision the update on reboot
            try {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot" -Name "AvailableUpdates" -Value 0x20
                Write-Console "[REGISTRY] Set AvailableUpdates flag for provisioning on reboot" -Colour Green
                Write-Log "Registry: Set AvailableUpdates=0x20 for provisioning on reboot" -Colour Green
                
                # Run Secure Boot Update task to register and apply the update
                try {
                    Start-ScheduledTask -TaskName "\Microsoft\Windows\PI\Secure-Boot-Update"
                    Write-Console "[TASK] Started Secure-Boot-Update task to register updates" -Colour Green
                    Write-Log "Task Started: \Microsoft\Windows\PI\Secure-Boot-Update to register Secure Boot updates" -Colour Green
                }
                catch {
                    Write-Console "[WARNING] Could not start Secure-Boot-Update task: $($_.Exception.Message)" -Colour Yellow
                    Write-Log "WARNING - Could not start Secure-Boot-Update task: $($_.Exception.Message)" -Colour Yellow
                }
            }
            catch {
                Write-Console "[WARNING] Could not set registry flag: $($_.Exception.Message)" -Colour Yellow
                Write-Log "WARNING - Could not set registry flag: $($_.Exception.Message)" -Colour Yellow
            }
            
            # Suggest reboot
            Write-Console "" # blank line
            Write-Console "[REBOOT RECOMMENDED] Please restart your computer for changes to take effect" -Colour Yellow
            Write-Log "REBOOT RECOMMENDED - Changes require restart to take effect" -Colour Yellow
            
            # Show notification (handles SYSTEM, interactive, and non-interactive contexts)
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
        if ($esp.MountedByUs) { 
            Write-Log "Unmounting EFI System Partition" -Colour Gray
            mountvol "${EfiLetter}:" /D | Out-Null 
        }
    }

    # ------------------------------------- save new state ---------------------
    # Only update state if copy was successful
    if ($copySuccess) {
        $currHash | Set-Content -Path $StateFile
        Write-Console "Updated state file with new hash" -Colour Gray
        Write-Log "STATE UPDATED - New hash saved: $currHash" -Colour Cyan
    } else {
        Write-Console "[WARNING] State file NOT updated due to copy failure" -Colour Yellow
        Write-Log "WARNING - State file not updated due to copy failure" -Colour Yellow
    }

    Write-Console "=== SkuSiPolicy Updater Completed ===" -Colour Magenta
}