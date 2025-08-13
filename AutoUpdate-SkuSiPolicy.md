# AutoUpdate-SkuSiPolicy.ps1

Mirrors the Windows SkuSiPolicy.p7b to the EFI System Partition if not already or upon update, (MD5 check). Update takes effect after reboot.
Tested: Windows 11, PowerShell 5.1.

## Quick Facts
- Source → C:\Windows\System32\SecureBootUpdates\SkuSiPolicy.p7b
- Target → <ESP>:\EFI\Microsoft\Boot\SkuSiPolicy.p7b (ESP auto-mounted, default Z:)
- Logs only changes/errors → C:\Log\Update.log
- Popup + coloured console when run interactively as admin on login. Popup when run as system + system startup or + upon (any) user login.
- Verifies copy, then suggests reboot

## Configurable top-of-script variables

| Var           | Default path / value                          | Purpose           |
|---------------|-----------------------------------------------|-------------------|
| $SystemFile   | …\SecureBootUpdates\SkuSiPolicy.p7b           | Source file       |
| $StateFile    | C:\Log\SkuSiPolicy.last                       | Stored MD5        |
| $LogFile      | C:\Log\Update.log                             | Log file          |
| $EfiLetter    | Z                                             | ESP mount letter  |
| $EfiFile      | Z:\EFI\Microsoft\Boot\SkuSiPolicy.p7b         | Target on ESP     |

## Usage
```powershell
# elevated PowerShell
Set-ExecutionPolicy -Scope Process Bypass   # if needed
.\AutoUpdate-SkuSiPolicy.ps1
```

## Create scheduled task (one-liner)...
CMD: System user, /w notification. Update \path\to\.  CMD command:

```cmd
schtasks /Create /TN "AutoUpdate-SkuSiPolicy" /RU SYSTEM /RL HIGHEST /SC ONSTART /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\path\to\AutoUpdate-SkuSiPolicy.ps1\"" /F
```
or:

Powershell: Run Silent as admin. Update \path\to\.

```ps1
Register-ScheduledTask -TaskName 'Auto-Update SkuSiPolicy' -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\path\to\SkuSiPolicy-Updater.ps1"') -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal (New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest) -Force
```

Notes:
- Runs as the current user, highest privileges, interactive. Replace /RU SYSTEM with /IT (for admin + traditional popup).
- If CMD has delayed expansion enabled, the “!” in the task path may need escaping; or run the command from PowerShell.

⚠️ Writes to the EFI System Partition—use with care. A reboot is recommended after a successful copy.
