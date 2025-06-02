Here’s a README.md tailored for your AIO-Visual-C-Redist-Auto-Updater.ps1 script, including usage instructions, description, and relevant details:

---

# AIO-Visual-C-Redist-Auto-Updater

**Windows Auto-Updater Script for Visual C++ Redistributable AIO**

This PowerShell script automatically downloads and installs the latest [VisualCppRedist AIO](https://github.com/abbodi1406/vcredist) package from GitHub, ensuring your system always has up-to-date Visual C++ Redistributables.

## Features

- Checks for the latest release of VisualCppRedist AIO from GitHub.
- Downloads and silently installs the latest version if an update is available.
- Cleans up after installation by removing the installer.
- Prevents unnecessary downloads if the current version is already installed.

## Usage

1. **Download** the script [`AIO-Visual-C-Redist-Auto-Updater.ps1`](AIO-Visual-C-Redist-Auto-Updater.ps1).
2. **Run the script** with PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\AIO-Visual-C-Redist-Auto-Updater.ps1
   ```

   > **Note:** Administrator privileges may be required for installation.

3. The script will:
   - Check for a new VisualCppRedist AIO version.
   - Download and silently install if a new version is found.
   - Remove the installer after execution.

## Silent Install Options

You can customize the installer by editing the script's `Start-Process` line or running `VisualCppRedist_AIO_x86_x64.exe` manually.  
Here are some useful command-line arguments:

- **Install all packages and display progress:**  
  `VisualCppRedist_AIO_x86_x64.exe /y`

- **Silently install all packages (no progress):**  
  `VisualCppRedist_AIO_x86_x64.exe /ai /gm2`

- **Silently install 2022 package only:**  
  `VisualCppRedist_AIO_x86_x64.exe /ai9`

- **Silently install 2010/2012/2013/2022 packages:**  
  `VisualCppRedist_AIO_x86_x64.exe /aiX239`

- **Silently install VSTOR and Extra VB/C packages:**  
  `VisualCppRedist_AIO_x86_x64.exe /aiTE`

- **Silently install all and hide ARP entries:**  
  `VisualCppRedist_AIO_x86_x64.exe /aiA /gm2`

## How It Works

1. Fetches the latest release tag from the [abbodi1406/vcredist](https://github.com/abbodi1406/vcredist) GitHub API.
2. Compares it with the previously installed version (stored in `latest_tag.txt`).
3. Downloads and runs the new installer if an update is available.
4. Deletes the installer after completion.

## Requirements

- PowerShell 5.1 or newer (Windows 7/8/10/11)
- Internet connection (to fetch releases and download installer)

## License

This script is provided as-is, without warranty.  
Refer to the [abbodi1406/vcredist](https://github.com/abbodi1406/vcredist) repository for licensing of the VisualCppRedist AIO package.

---

**Windows Auto-Updater Scripts**  
By [rugabunda](https://github.com/rugabunda)
