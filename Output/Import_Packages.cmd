@net.exe session >nul 2>&1
@if ErrorLevel 1 (echo "Run as Administrator" & pause && exit)

DISM.exe /online /Add-Package /PackagePath:C:\Temp /NoRestart