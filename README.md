-
---

# Auto-Updaters

**Windows Auto-Updater Scripts**

## Overview

This repository contains PowerShell scripts designed to automate the process of updating software and system components on Windows machines. These scripts help keep your system and applications up-to-date without manual intervention.

## Features

- Automates the download and installation of updates
- Designed for use with Windows systems
- Fully written in PowerShell for easy customization and integration

## Getting Started

1. **Clone or Download the Repository**

   ```sh
   git clone https://github.com/rugabunda/Auto-Updaters.git
   ```

2. **Review and Customize Scripts**

   - Open the PowerShell scripts in your preferred editor.
   - Adjust any variables or paths as needed to fit your environment.

3. **Run a Script Manually**

   - Right-click the script and select “Run with PowerShell”  
     **or**
   - Open PowerShell and run:
     ```sh
     .\YourScriptName.ps1
     ```

## Scheduling Auto-Updaters

To ensure updates are applied regularly, it’s recommended to add the updater scripts as scheduled tasks in Windows. This automates execution without user input.

### How to Add as a Scheduled Task

1. Open **Task Scheduler** (`taskschd.msc`).
2. Click **Create Task**.
3. Set a descriptive **Name** (e.g., “Auto-Updater”).
4. Under the **Triggers** tab, click **New…** and set the frequency (e.g., daily or weekly).
5. Under the **Actions** tab, click **New…**
   - **Action:** Start a program
   - **Program/script:** `powershell.exe`
   - **Add arguments:** `-ExecutionPolicy Bypass -File "C:\Path\To\YourScript.ps1"`
6. Adjust **Conditions** and **Settings** as needed.
7. Click **OK** to save.

> #### Create a Scheduled Task Using CMD

You can also create a scheduled task that runs every 12 hours with system privileges from the command line (customize the script path and task name as needed):

```cmd
SCHTASKS /Create /SC HOURLY /MO 12 /TN "Auto-Updater-Name" /TR "powershell.exe -ExecutionPolicy Bypass -File \"C:\Path\To\YourScript.ps1\"" /RU "SYSTEM"
```

- `/SC HOURLY /MO 12` — Schedule to run every 12 hours  
- `/TN "Auto-Updater-Name"` — The name of your task  
- `/TR ...` — Command to run (your PowerShell script)  
- `/RU "SYSTEM"` — Runs the task with system privileges


## Requirements

- Windows 10 or newer (recommended)
- PowerShell 5.1 or later
- Appropriate permissions to run scripts and install updates

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests for new features, enhancements, or bug fixes.

## License

This project is licensed under the [MIT License](LICENSE).

---

Let me know if you’d like any specific instructions or examples included in the README!
