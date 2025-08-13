# AutoUpdate-SkuSiPolicy.ps1

Mirrors the Windows SkuSiPolicy.p7b to the EFI System Partition only when the file changed (MD5 check). Update takes effect after reboot.

Tested: Windows 11, PowerShell 5.1.

## Quick Facts
- Source → C:\Windows\System32\SecureBootUpdates\SkuSiPolicy.p7b
- Target → <ESP>:\EFI\Microsoft\Boot\SkuSiPolicy.p7b (ESP auto-mounted, default Z:)
- Logs only changes/errors → C:\Log\Update.log
- Popup + coloured console when run interactively as admin. Popup when run as system, at system startup, or upon (any) user login.
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

## Create scheduled task (one-liner)
Triggers on system startup

```cmd, Update \path\to\.
schtasks /Create /TN "AutoUpdate-SkuSiPolicy" /RU SYSTEM /RL HIGHEST /SC ONSTART /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\path\to\AutoUpdate-SkuSiPolicy.ps1\"" /F
```
Notes:
- Runs as the current user, highest privileges, interactive. To run headless, replace /IT with /RU SYSTEM (popup won’t be visible).
- If CMD has delayed expansion enabled, the “!” in the task path may need escaping; or run the command from PowerShell.

⚠️ Writes to the EFI System Partition—use with care. A reboot is recommended after a successful copy.
