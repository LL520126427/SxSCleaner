@echo off

pushd "%~dp0" && Dism 1>nul 2>nul || mshta vbscript:CreateObject("Shell.Application").ShellExecute("cmd.exe","/c %~s0 "%*"","","runas",1)(window.close) && Exit /B 1

title %~n0

set "Path_Helper=%~dp0_Helper"
set "wimlib=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\wimlib-imagex.exe"

:targetmenu
echo ============================================================
echo 给离线映像添加 无人值守 OriginSetup 简化部署脚本
echo:
echo - 例：D:\install.wim
echo:
echo 输入 install.wim 路径
echo:
echo 或 直接拖拽映像文件进来 按下‘Enter’键开始
echo ============================================================
echo:

set /p ImageFile=映像文件:
echo:
set ImageIndex=1
for /f "tokens=2 delims=: " %%a in ('dism /English /Get-WimInfo /WimFile:"%ImageFile%" ^| find /i "Index"') do set ImageIndex=%%a

if %ImageIndex% gtr 1 (
    echo 检测到多个镜像索引，当前索引: %ImageIndex%
    dism /Get-Wiminfo /WimFile:"%ImageFile%"
    set /p ImageIndex=请输入映像索引数字[1-%ImageIndex%]回车 直接回车默认索引1：
)

if exist "%~dp0Setup\OriginSetup.cmd" (
    echo 添加 无人值守 unattend.xml . . .
    %wimlib% update %ImageFile% %ImageIndex% --command="add 'Setup\Scripts\XML\unattend.xml' '\Windows\Panther\unattend.xml'"
    echo 添加 无人值守 OriginSetup 简化部署脚本 . . .
    %wimlib% update %ImageFile% %ImageIndex% --command="add 'Setup' '\Windows\Setup'"
)

timeout /t 3 /nobreak
exit
