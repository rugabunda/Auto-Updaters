---

# UCheck Auto-Updater Script

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)

This PowerShell script automates the process of keeping Adlice UCheck up-to-date on a Windows system. It intelligently checks for the latest version, compares it with the currently installed version, and performs a silent download and installation only when an update is needed.

The script also includes a powerful scheduling feature to create a "set and forget" automated task that handles the entire update process in the background.

## Key Features

-   **Smart Version Check**: Compares the installed version (from the registry) against the latest version available in the official UCheck changelog.
-   **Efficient Updates**: Only downloads and installs if UCheck is not installed or if a newer version is available, saving bandwidth and system resources.
-   **Silent Installation**: Utilizes UCheck's silent command-line switches (`/verysilent /norestart /suppressmsgboxes`) for a completely non-interactive, background installation.
-   **Robust Scheduling**: With a single command, creates a Windows Scheduled Task to run the update check automatically.
    -   Runs every 6 hours.
    -   Includes a random 2-hour delay to prevent simultaneous network load from multiple machines.
    -   Runs as the `SYSTEM` user to ensure it works even when no one is logged in.
-   **Admin-Aware**: The script automatically checks if it has the required administrator privileges before attempting to create a scheduled task.
-   **Verbose Logging**: Use the `-Verbose` switch to see detailed step-by-step output of the script's actions.

## Requirements

-   **Operating System**: Windows 10 / Windows 11 / Windows Server 2016 or newer.
-   **PowerShell**: Version 5.1 or later (this is standard on modern Windows systems).
-   **Administrator Privileges**: Required **only** for creating the scheduled task (`-Schedule` flag). The one-time update check can be run by a standard user.

## Setup

1.  **Save the Script**: Save the script file as `AutoUpdate-UCheck.ps1` in a stable location on your computer (e.g., `C:\Scripts`).
2.  **Set Execution Policy (One-Time Setup)**: If you haven't run PowerShell scripts before, you may need to adjust the execution policy. Open PowerShell **as an Administrator** and run the following command to allow scripts to run:
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
    ```
    Alternatively, for a less permanent change, you can bypass the policy for a single session by running `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process` in your PowerShell window.

## Usage

Open a PowerShell terminal and navigate to the directory where you saved `AutoUpdate-UCheck.ps1`.

### Running a One-Time Check

To perform a single, immediate check for UCheck updates, simply run the script.

```powershell
.\AutoUpdate-UCheck.ps1
```

For more detailed output on what the script is doing, use the `-Verbose` flag.

```powershell
.\AutoUpdate-UCheck.ps1 -Verbose
```

### Automating Updates with a Scheduled Task

To create a scheduled task that runs this script automatically, you **must run PowerShell as an Administrator**.

**Option 1: Create a task with the default name (`UCheck-AutoUpdater`)**

```powershell
# You must be running as Administrator for this command
.\AutoUpdate-UCheck.ps1 -Schedule
```
*You can also use the alias `-s`.*
```powershell
.\AutoUpdate-UCheck.ps1 -s
```

**Option 2: Create a task with a custom name**

```powershell
# You must be running as Administrator for this command
.\AutoUpdate-UCheck.ps1 -Schedule -Name "My Custom UCheck Task"
```

After the task is created, the script will confirm its creation and exit. The task will now run in the background according to its schedule.

## How It Works

1.  **Version Check**:
    -   The script scans the Windows Registry (`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`) to find the `DisplayVersion` of the currently installed UCheck.
    -   It then downloads the `Changelog.txt` from the Adlice server and parses the top-most version number (e.g., `V6.3.1`).
2.  **Comparison**:
    -   It compares the installed version to the latest version.
    -   If the latest version is greater than the installed version, or if UCheck is not installed at all, it proceeds to the next step.
3.  **Download & Install**:
    -   The script downloads the `ucheck_setup.exe` to the temporary user folder (`$env:TEMP`).
    -   It executes the installer with silent arguments, ensuring no pop-ups or user interaction is required.
    -   Finally, it cleans up the downloaded installer file.
4.  **Scheduling (`-Schedule` flag)**:
    -   When you use the `-Schedule` flag, the script creates a new task in the Windows **Task Scheduler**.
    -   **Action**: The task is configured to run `powershell.exe` with arguments pointing it to execute this very `AutoUpdate-UCheck.ps1` script file.
    -   **Trigger**: It's set to run every 6 hours with a random delay of up to 2 hours.
    -   **Principal**: It runs as the `NT AUTHORITY\SYSTEM` account, giving it high-level permissions to install software without needing a user to be logged in.

## Troubleshooting

-   **"Access is Denied" when using `-Schedule`**: You did not run PowerShell as an Administrator. Right-click the PowerShell icon and select "Run as administrator".
-   **"Running scripts is disabled on this system"**: You need to set the PowerShell execution policy. See the [Setup](#setup) section for the command.
-   **How do I see or delete the scheduled task?**:
    1.  Press `Win + R`, type `taskschd.msc`, and press Enter to open the Task Scheduler.
    2.  In the left-hand pane, click on "Task Scheduler Library".
    3.  You will find the task listed there (e.g., "UCheck-AutoUpdater"). You can right-click it to run, disable, or delete it.

## License

This project is licensed under the MIT License.
