TV kit for a Hisense Android TV. Windows PowerShell.

Setup once
1. On the TV: Settings, Device Preferences, About, press OK on Build seven times.
2. Settings, Device Preferences, Developer options, turn on USB debugging and Network debugging.
3. Unzip this folder on a Windows PC on the same Wi-Fi or router as the TV.
4. Open PowerShell in the folder and run:
   Set-ExecutionPolicy -Scope Process Bypass

Run in order
   .\1-connect.ps1      Finds the TV, connects over ADB, takes a screenshot.
   .\2-backup.ps1       Saves package states, settings and the stock home before any change.
   .\3-debloat.ps1      Disables ads, telemetry and junk. Asks first. Never uninstalls.
   .\4-wallpapers.ps1   Downloads nature wallpapers on the PC.
   .\5-launcher.ps1     Builds and installs the minimal home screen with a dock.
   .\restore.ps1        Undoes everything.

Screenshots
Each step saves a TV screenshot to %USERPROFILE%\tv-kit-data\screenshots and opens it.
Attach the screenshots in chat after each step.

If the home screen breaks
Run .\restore.ps1 from the PC. ADB works even when the TV screen looks wrong.

Data folder
%USERPROFILE%\tv-kit-data holds backups, logs, wallpapers, the built APK and screenshots.
Every disabled package is logged in the backup folder as disabled.log.

Dock controls on the TV
Left and right move. OK opens an app. Hold OK on a dock app removes it.
Open the All apps tile and hold OK on any app to add it to the dock.
The Menu key opens All apps if the remote has one.
