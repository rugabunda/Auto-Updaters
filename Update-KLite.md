# K-Lite Codec Pack PowerShell Updater (v1.9.3)

## Overview

This PowerShell script automates the process of keeping your K-Lite Codec Pack installation up-to-date. It can:

*   Detect your currently installed K-Lite Codec Pack variant (Basic, Standard, Full, or Mega) and its version.
*   If K-Lite is not installed, prompt you to choose which variant you'd like to install.
*   Check the official Codec Guide website for the latest version of your specific K-Lite variant.
*   Check for universal incremental updates that can be applied to your installed version.
*   Prioritize updates:
    1.  A full installer for your specific variant if it's newer.
    2.  An incremental update if it's applicable and newer.
*   Perform unattended (silent) installations:
    *   For **Basic, Standard, Full, and Mega** variants:
        *   If a corresponding `klcp_[variant]_unattended.ini` file (e.g., `klcp_full_unattended.ini`) is present in the script's directory, it will be used for a fully customized silent installation via a temporary batch file.
        *   If the INI file for a specific variant is *not* found, the script will attempt a standard silent installation for that variant (without INI customization) and issue a warning.
    *   For **Incremental** updates: These are always installed silently without an INI file.
*   Use the `/FORCEUPGRADE` switch during installation to prevent the process from being aborted if applications are found to be using codec files.
*   After a fresh installation of any K-Lite variant, the script performs an immediate "second pass" check to see if any incremental updates can be applied to the just-installed version.
*   Clean up downloaded installer files and temporary batch files after installation attempts.

## Prerequisites

1.  **PowerShell Version:** 5.1 or higher.
2.  **Administrator Privileges:** The script must be run as an Administrator to install software.
3.  **Internet Connection:** Required to check for updates and download installers.
4.  **Unattended INI Files (Optional but Recommended for Full Customization):**
    *   For a fully customized silent installation of a specific K-Lite variant (Basic, Standard, Full, or Mega), you need to create an unattended INI file for that variant. For automated or silent installations of K-Lite Codec Pack, it’s strongly recommended to follow the official unattended installation instructions provided by the developers: https://www.codecguide.com/silentinstall.htm
    *   Name your INI files as follows and place them in the **same directory** as the `Auto-Update-KLite.ps1` script:
        *   `klcp_basic_unattended.ini`
        *   `klcp_standard_unattended.ini`
        *   `klcp_full_unattended.ini`
        *   `klcp_mega_unattended.ini`
    *   You can generate these INI files by running the *OFFICIAL* K-Lite installer once with the `INSTALLERFILENAME /unattended` command-line switch, going through the setup options you want, and then copying the saved INI.
    *   If an INI file for a specific variant (Basic, Standard, Mega, or even Full if its INI is missing) is not found, the script will attempt a generic silent installation for that variant, which might not include all your preferred component selections or settings.

## How to Use

1.  **Download/Save the Script:** Save the PowerShell script as `Auto-Update-KLite.ps1`.
2.  **Prepare INI Files (Optional):**
    *   If you want customized silent installations for specific K-Lite variants, create your `klcp_[variant]_unattended.ini` files as described in "Prerequisites."
    *   Place these INI files in the **same directory** as `Auto-Update-KLite.ps1`.
3.  **Run the Script:**
    *   Right-click on `Auto-Update-KLite.ps1` and select "Run with PowerShell".
    *   Alternatively, open PowerShell as an Administrator, navigate to the directory where you saved the script, and run it:
        ```powershell
        .\Auto-Update-KLite.ps1
        ```
4.  **Follow Prompts (If Any):**
    *   If K-Lite is not installed, you will be prompted to choose which variant (Basic, Standard, Full, Mega) you wish to install. The options will be displayed in an ordered list.

## Script Logic Flow

1.  **Initial Setup:**
    *   Determines script directory and paths for downloads and temporary files.
    *   Checks PowerShell version and administrator privileges.
2.  **Detect Installed K-Lite:**
    *   Checks the registry for an existing K-Lite installation.
    *   If found, determines the installed version and variant (Basic, Standard, Full, Mega).
    *   If not found, sets a flag for a fresh install scenario.
3.  **Variant Selection (for Fresh Installs):**
    *   If K-Lite is not installed, prompts the user to select a variant from an ordered menu.
    *   If K-Lite is installed but the variant couldn't be determined from the registry, it defaults to checking/updating the "Full" variant.
4.  **Fetch Latest Version Information:**
    *   Fetches the latest version details for the target K-Lite variant installer from its specific page on `codecguide.com`.
    *   Fetches the latest universal incremental update details from `codecguide.com/klcp_update.htm`.
5.  **Decision Making (Update or Install):**
    *   **Fresh Install:** If K-Lite is not installed, it will proceed to download and install the chosen variant.
    *   **Update Existing:**
        *   It prioritizes the full installer for the detected/target variant if it's newer than the installed version.
        *   If the variant's full installer isn't newer, it checks if the incremental update is applicable and newer.
            *   The script attempts to parse the "From" version of the incremental package from the website.
            *   If the "From" version is known and matches, it uses the incremental.
            *   If the "From" version is *unknown* but the "To" version is newer, it will proceed with the incremental update with a warning.
        *   If no suitable update is found, it reports that K-Lite is up-to-date.
6.  **Download and Install:**
    *   If an update/install is needed, the appropriate installer (`.exe`) is downloaded to a subfolder named `Klite_Downloads` (created in the script's directory).
    *   **For Basic, Standard, Full, or Mega variants:**
        *   Checks for a corresponding `klcp_[variant]_unattended.ini` file in the script's directory.
        *   If the INI exists: The INI is copied to the download folder, a temporary batch file (`_temp_klcp_variant_install.bat`) is created, and the installer is run via this batch file using the INI.
        *   If the INI does NOT exist: A warning is issued, and the installer is executed directly with generic silent switches (no INI customization).
    *   **For Incremental updates:** The installer is executed directly with generic silent switches (no INI, no batch file).
    *   All installations use `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /FORCEUPGRADE`.
7.  **Post-Fresh-Install Incremental Check:**
    *   If a fresh installation of a K-Lite variant was just performed successfully, the script immediately re-checks if any incremental updates can be applied to this newly installed version.
    *   If an applicable incremental update is found, it's downloaded and installed.
8.  **Cleanup:**
    *   After an installation attempt, the downloaded installer `.exe` file is deleted.
    *   If a temporary batch file and copied INI were used, they are also deleted from the download subfolder.
    *   The `Klite_Downloads` folder itself is kept.
9.  **Finish:** Reports script completion status.

## Troubleshooting

*   **"Must run as Administrator":** Ensure you are running the script with administrator privileges.
*   **"Failed to fetch page":**
    *   Check your internet connection.
*   **Version Parsing Warnings/Errors:** The K-Lite website structure can change. If the script consistently fails to parse version information (especially the "From" version for incremental updates), the regular expressions within the script may need updating.
*   **Installation Fails (Non-zero Exit Code):**
    *   The exit code from the K-Lite installer will be displayed. Some non-zero codes might indicate a reboot is required.
    *   If a temporary batch file was used (for Basic/Standard/Full/Mega with an INI), check the console output for any messages from the batch script, including a directory listing which can help verify if the installer was present.
    *   Ensure your unattended INI file (if used) is correctly configured.
*   **Path Issues:** The script is designed to create a `Klite_Downloads` subfolder within the directory where `Auto-Update-KLite.ps1` is located. If downloads go elsewhere, check the `$ScriptDir` initialization at the top of the script.

## Disclaimer

This script interacts with third-party websites and software. Website structures can change, potentially breaking the script's ability to fetch information. Always use such automation tools responsibly and understand what they are doing. The authors of K-Lite Codec Pack are not affiliated with this script.
