@echo off

%1(start /min cmd.exe /c %0 :& exit )

pushd "%~dp0" & reg query "HKU\S-1-5-19">nul 2>&1
if %errorlevel% equ 1 ( cmd /u /c echo. CreateObject^("Shell.Application"^).ShellExecute "%~f0", "", "", "runas", 1 > "%temp%\GetAdmin.vbs"& "%temp%\GetAdmin.vbs" & DEL "%temp%\GetAdmin.vbs" & exit /b )
echo 组件存储清理. . .

dism /Online /Cleanup-Image /StartComponentCleanup

exit