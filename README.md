Stargate for the MEGA65
Stargate is a fast-paced 1981 arcade shooter where players defend humanoids from waves of relentless alien attackers across a horizontally scrolling landscape, using a complex control scheme to navigate and survive.

This core is based on the MiSTer Arcade-Robotron_MiSTer core which itself is based on the work of many others.

Muse aka sho3string ported the core to the MEGA65 in 2024.

The core uses the MiSTer2MEGA65 V2 framework and QNICE-FPGA for FAT32 support (loading ROMs, mounting disks) and for the on-screen-menu.

How to install Stargate core on your MEGA65
Download ROM: Download the MAME ROM ZIP file.

Download the powershell or shell script depending on your preferred platform ( Windows, Linux/Unix and MacOS supported )

Run the script: a) First extract all the files within the zip to any working folder.

b) Copy the powershell or shell script to the same folder and execute it to create the following files.

image

For Windows run the script via PowerShell SG_rom_installer.ps1

For Unix/Linux/MacOS ./SG_rom_installer.sh

The script will automatically create the /arcade/stargate folder where the generated ROMs will reside.

Copy or move the arcade/gng folder to your MEGA65 SD card: You may either use the bottom SD card tray of the MEGA65 or the tray at the backside of the computer (the latter has precedence over the first).
