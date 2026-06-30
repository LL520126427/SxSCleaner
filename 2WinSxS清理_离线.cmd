@echo off
:: 本脚本是为了删除组件的winsxs文件目录

:: 设置常用重定向变量
set "nul1=1>nul"
set "nul2=2>nul"
set "nul6=2^>nul"
set "nul=>nul 2>&1"

chcp 936 %nul1%
setlocal EnableDelayedExpansion

:: 设置环境变量，如果系统中配置不正确会有帮助
set "PathExt=.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC"
set "SysPath=%SystemRoot%\System32"
set "Path=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0\"

if exist "%SystemRoot%\Sysnative\reg.exe" (
    set "SysPath=%SystemRoot%\Sysnative"
    set "Path=%SystemRoot%\Sysnative;%SystemRoot%;%SystemRoot%\Sysnative\Wbem;%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\;%Path%"
)

set "ComSpec=%SysPath%\cmd.exe"
set "PSModulePath=%ProgramFiles%\WindowsPowerShell\Modules;%SysPath%\WindowsPowerShell\v1.0\Modules"

:: 初始化变量和参数处理
set re1=
set re2=
set "_cmdf=%~f0"

for %%# in (%*) do (
    if /i "%%#"=="re1" set re1=1
    if /i "%%#"=="re2" set re2=1
    if /i "%%#"=="-qedit" (set re1=1&set re2=1)
)

:: 如果在64位Windows上由x86进程启动，则以x64进程重新启动脚本
if exist %SystemRoot%\Sysnative\cmd.exe if not defined re1 (
    start %SystemRoot%\Sysnative\cmd.exe /c ""!_cmdf!" %* re1"
    exit /b
)

:: 检查Null服务是否正常运行，这对批处理脚本很重要
sc query Null | find /i "RUNNING"
if %errorlevel% NEQ 0 (
    echo.
    echo Null服务未运行，脚本可能会崩溃...
    echo.
    ping 127.0.0.1 -n 20 %nul1%
)

:: 处理命令行参数
set _args=
set _elev=
set _args=%*
if defined _args set _args=%_args:"=%
if defined _args set _args=%_args:re1=%
if defined _args set _args=%_args:re2=%

if defined _args (
    for %%A in (%_args%) do (
        if /i "%%A"=="-el" set _elev=1
    )
)

:: 调用设置系统变量的子程序
call :dk_setvar

:: 检查操作系统版本兼容性
if %winbuild% LSS 7600 (
    echo 检测到不受支持的操作系统版本 [%winbuild%]。
    echo 仅支持Windows 7/8/8.1/10/11等版本。
    goto dk_done
)

:: 修复路径名称中的特殊字符限制
set "_work=%~dp0"
if "%_work:~-1%"=="\" set "_work=%_work:~0,-1%"

set "_batf=%~f0"
set "_batp=%_batf:'=''%"

set _PSarg="""%~f0""" -el %_args%
set _PSarg=%_PSarg:'=''%


:: 以管理员身份提升脚本权限并传递参数，防止循环
%nul1% fltmc || (
    if not defined _elev (
        %psc% "start cmd.exe -arg '/c \"!_PSarg!\"' -verb runas" && exit /b
    )
    %eline%
    echo 此脚本需要管理员权限。
    echo 请右键单击此脚本并选择"以管理员身份运行"。
    goto dk_done
)

:: 检查PowerShell语言模式
::pstst $ExecutionContext.SessionState.LanguageMode :pstst

for /f "delims=" %%a in ('%psc% "if ($PSVersionTable.PSEdition -ne 'Core') {$f=[System.IO.File]::ReadAllText('!_batp!') -split ':pstst';. ([scriptblock]::Create($f[1]))}" %nul6%') do (
    set tstresult=%%a
)

if /i not "%tstresult%"=="FullLanguage" (
    %eline%
    for /f "delims=" %%a in ('%psc% "$ExecutionContext.SessionState.LanguageMode" %nul6%') do (
        set tstresult2=%%a
    )
    echo 测试 1 - %tstresult%
    echo 测试 2 - !tstresult2!
    echo.
    
    REM 检查LanguageMode
    echo !tstresult2! | findstr /i "ConstrainedLanguage RestrictedLanguage NoLanguage" %nul1% && (
        echo 在PowerShell中未找到FullLanguage模式。正在中止...
        echo 如果您对Powershell应用了限制，请撤销这些更改。
        echo.
        goto dk_done
    )
    
    REM 检查Powershell核心版本
    cmd /c "%psc% "$PSVersionTable.PSEdition"" | find /i "Core" %nul1% && (
        echo 需要Windows Powershell，但似乎被Powershell核心替代。正在中止...
        echo.
        goto dk_done
    )
)

:: 检查脚本是否在终端应用中运行
if %winbuild% GEQ 17763 (
    set terminal=1
) else (
    set terminal=
)

if defined terminal (
    set lines=0
    for /f "skip=3 tokens=* delims=" %%A in ('mode con') do (
        if "!lines!"=="0" (
            for %%B in (%%A) do set lines=%%B
        )
    )
    if !lines! GEQ 100 set terminal=
)

:: 检查是否需要重新启动以禁用快速编辑
for %%# in (%_args%) do (
    if /i "%%#"=="-qedit" goto :Init_Scr
)

:: 重新启动以在当前会话中禁用快速编辑，并使用conhost.exe而不是终端应用
set resetQE=1
reg query HKCU\Console /v QuickEdit %nul2% | find /i "0x0" %nul1% && set resetQE=0
reg add HKCU\Console /v QuickEdit /t REG_DWORD /d 0 /f %nul1%

if defined terminal (
    start conhost.exe "!_batf!" %_args% -qedit
    start reg add HKCU\Console /v QuickEdit /t REG_DWORD /d %resetQE% /f %nul1%
    exit /b
) else if %resetQE% EQU 1 (
    start cmd.exe /c ""!_batf!" %_args% -qedit"
    start reg add HKCU\Console /v QuickEdit /t REG_DWORD /d %resetQE% /f %nul1%
    exit /b
)

:Init_Scr
for /f "skip=5 tokens=1,2,* delims==" %%a in ('type %~dp0SxSExportConfig.ini') do  (
    set var=%%a
    set !var: =!=%%b
)
cls
:: 初始化日志系统
set "LOG_FILE=%~dp0WinSXS_Clean_Offline.log"
call :InitializeLogging

set Path_Helper=%~dp0_Helper

set "sort=%Path_Helper%\sort.exe"
set "grep=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\grep.exe"
set "NSudo=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\NSudo.exe"
set "Dism=Dism.exe /LogLevel:1"
set "wimlib=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\wimlib-imagex.exe"
set "Tweak=%Path_Helper%\Tweak.exe"

set "_Path_Image=%~dp0Mount_%random%"

:: 测试用
:: set "_Path_Image=%~dp0Mount_29204"

call :LogInfo 脚本版本: %~n0 %Scr_Ver%
call :LogInfo 处理器架构: %PROCESSOR_ARCHITECTURE%
call :LogInfo 辅助工具路径: %Path_Helper%

call %Path_Helper%\definitions-Mod.cmd

title %~n0 %Scr_Ver%

set ImageFile=
set MUI=zh-CN

:: 设置离线参数
set txt1=WinSXSFoldersList
set txt2=WinSxSFilesList
set txt3=WinSXSExclude

:: 选择镜像
:SelectImage
call :LogInfo 开始选择镜像文件. . .
:: 使用 PowerShell 显示文件选择对话框
for /f "usebackq delims=" %%i in (`powershell -sta -command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Filter = '映像文件(*.wim)|*.wim|所有文件(*.*)|*.*'; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $f.FileName } else { '' } "`) do (
    set "ImageFile=%%i"
)

:: echo ============================================================
:: echo [信息] 请输入 镜像文件 路径 例：D:\install.wim
:: echo [信息] 或者将 镜像文件 拖进来
:: echo ============================================================
:: echo [信息] 输入路径，按回车(Enter)
:: set /p ImageFile=:

if "%ImageFile%" equ "" (
    call :LogWarning 未选择镜像文件，退出脚本
    goto :Exit
)

call :LogInfo 选择的镜像文件: %ImageFile%

set ImageIndex=1
for /f "tokens=2 delims=: " %%a in ('dism /English /Get-ImageInfo /ImageFile:"%ImageFile%" ^| find /i "Index"') do set ImageIndex=%%a

if %ImageIndex% gtr 1 (
    call :LogInfo 检测到多个镜像索引，当前索引: %ImageIndex%
    dism /Get-Wiminfo /WimFile:"%ImageFile%"
    set /p ImageIndex=请输入映像索引数字[1-%ImageIndex%]回车 直接回车默认索引1：
)

for /f "tokens=1 delims=	 " %%f in ('dism /English /Get-ImageInfo /ImageFile:"%ImageFile%" /Index:%ImageIndex% ^| find /i "Default"') do set MUI=%%f
for /f "tokens=3 delims= " %%v in ('dism /English /Get-ImageInfo /ImageFile:"%ImageFile%" /Index:%ImageIndex% ^| findstr /i /c:"Version :"') do set CurBuild=%%v
for /f "tokens=2 delims=: " %%c in ('dism /English /Get-ImageInfo /ImageFile:"%ImageFile%" /Index:%ImageIndex% ^| findstr /i /c:"Architecture"') do set Arch=%%c
for /f "tokens=3 delims=." %%f in ('echo %CurBuild%') do set "HostBuild=%%f"
for /f "tokens=1-2 delims=." %%f in ('echo %CurBuild%') do set "ShortBuild=%%f.%%g"

call :LogInfo 获取映像信息. . .
call :LogInfo 目标: %ImageFile%
call :LogInfo 版本: %CurBuild%
call :LogInfo 语言: %MUI%
call :LogInfo 体系: %Arch%
echo.

set _Arch=%Arch%
if %Arch% equ x64 set _Arch=amd64

if not exist %_Path_Image% (
    call :LogInfo 创建挂载目录: %_Path_Image%
    md %_Path_Image%
)

call :LogInfo 开始挂载映像. . .
if not exist "%_Path_Image%\Windows" call :MountImage "%ImageFile%", %ImageIndex%, "%_Path_Image%"

if !errorlevel! neq 0 (
    call :LogError 挂载映像失败，错误代码: !errorlevel!
    goto :Exit
)
call :LogInfo 映像挂载成功

pushd "%~dp0WinSxSList"

:: 启用和禁用功能
call :LogInfo 开始配置Windows功能. . .
for /f "tokens=* delims=" %%i in ('type Custom\EnFeatureList.txt') do call :EnableFeature %%i
for /f "tokens=* delims=" %%i in ('type Custom\DisFeatureList.txt') do call :DisableFeature %%i
call :LogInfo Windows功能配置完成

:: 显示隐藏组件
call :LogInfo 开始处理隐藏组件. . .
set "RegCBS=HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"
reg load HKLM\TMP_SOFTWARE "%_Path_Image%\Windows\System32\config\SOFTWARE" %nul%
for /f "tokens=*" %%l in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\*16385*.mum"') do (
    %NSudo% reg delete "%RegCBS%\PackagesPending\%%~nl" /f
    %NSudo% reg delete "%RegCBS%\Packages\%%~nl" /f
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\%PathRel_Packages%\%%~nl.*"
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\System32\catroot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}\%%~nl.*"
)

dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\Microsoft-Windows-Internet-Browser-Package*" | findstr /i "Browser" && (
    call :LogInfo 配置Edge浏览器设置. . .
    reg add "HKLM\TMP_SOFTWARE\Microsoft\EdgeUpdate" /f /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d 1
    reg add "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /f /v "DisableEdgeDesktopShortcutCreation" /t REG_DWORD /d 1
    %NSudo% reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\Microsoft.Edge.Stable.%_Arch%" /f
    %NSudo% reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\%_Arch%_microsoft-windows-u..argeting-edgestable_31bf3856ad364e35_none_bbc84ae9390a68c3" /f 
)

dir /b /a-d "%_Path_Image%\Windows\System32\smartscreen.exe" | findstr /i "smartscreen" && (
    call :LogInfo 配置SmartScreen设置. . .
    reg add "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /f /v "SmartScreenEnabled" /t REG_SZ /d "Off"
    reg add "HKLM\TMP_SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" /f /v "ConfigureAppInstallControlEnabled" /t REG_DWORD /d 1
    reg add "HKLM\TMP_SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" /f /v "ConfigureAppInstallControl" /t REG_SZ /d "Anywhere"
)

:: 检测是否安装 .NET Framework 4.0 以上的框架
if [%Flag_REMode%] == [2] (
    set "NetPath=%SystemRoot%\Microsoft.NET\Framework"
    for /f "delims=" %%n in ('dir /ad /b "%NetPath%\v4.*"') do if not exist "%NetPath%\%%n\csc.exe" set Flag_REMode=1
)

::优先 使用预置列表
if exist %CurBuild%\%Arch%\%txt3%.txt (
    set Flag_Retain=0
    xcopy /y "%CurBuild%\%Arch%\%txt3%.txt" .\
)
if exist %CurBuild%\%Arch%\%txt1%.txt if exist %CurBuild%\%Arch%\%txt2%.txt (
   set Flag_Import=0
   xcopy /y "%CurBuild%\%Arch%\%txt1%.txt" .\
   xcopy /y "%CurBuild%\%Arch%\%txt2%.txt" .\
)
xcopy /y "%CurBuild%\*.txt" ..\

if /i [%Flag_REMode%] == [1] (
    for /f %%i in (%ImportList%) do call :ShowComponent "%%i"
)

set "EdgePath=%_Path_Image%\Program Files\Microsoft"
if %arch% equ x64 set "EdgePath=%_Path_Image%\Program Files (x86)\Microsoft"
if not exist "%EdgePath%\Edge" set "Flag_Edge=0"

if /i [%Flag_Edge%] == [1] (
    call :LogInfo 删除新版Edge浏览器. . .
    echo reg delete "HKLM\TMP_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f
    %NSudo% reg delete "HKLM\TMP_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f
    echo reg delete "HKLM\TMP_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    %NSudo% reg delete "HKLM\TMP_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    echo reg delete "HKLM\TMP_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" /f
    %NSudo% reg delete "HKLM\TMP_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" /f
    echo reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    %NSudo% reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f
    echo reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    %NSudo% reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    echo reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" /f
    %NSudo% reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" /f
    echo rd /s /q "%EdgePath%"
    %NSudo% cmd /c rd /s /q "%EdgePath%"
)

:: 如果移除 Defender 则删除 Windows 安全中心 启动项
type %ImportList% %nul2% | findstr /i "Windows-Defender" |findstr ";" || (
    echo reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /f /v "SecurityHealth"
    %NSudo% cmd /c reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /f /v "SecurityHealth"
)

:: 关闭预留空间
reg add "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" /f /v "ShippedWithReserves" /t REG_DWORD /d 0

:: 关闭恶意软件MRT删除工具自动安装
%NSudo% reg add "HKLM\TMP_SOFTWARE\Policies\Microsoft\MRT" /f /v "DontOfferThroughWUAU" /t REG_DWORD /d 1

reg unload HKLM\TMP_SOFTWARE %nul%
reg load HKLM\TMP_SYSTEM "%_Path_Image%\Windows\System32\config\SYSTEM" %nul%
:: 关闭休眠
reg add "HKLM\TMP_SYSTEM\ControlSet001\Control\Power" /f /v "HibernateEnabledDefault" /t REG_DWORD /d 0
reg unload HKLM\TMP_SYSTEM %nul%
call :LogInfo 隐藏组件处理完成

:: 处理开始菜单中的 入门 和 Windows备份 图标
if not exist "%_Path_Image%\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\appxmanifestbak.xml" if %HostBuild% geq 22000 (
    call :LogInfo 隐藏开始菜单中的 入门 和 Windows备份 图标. . .
    xcopy /y "%_Path_Image%\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\appxmanifest.xml" .\
    echo "%Path_Helper%\RemoveAppxManifest.ps1" "appxmanifest.xml"
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\RemoveAppxManifest.ps1" "appxmanifest.xml"
    %NSudo% cmd /c move /y appxmanifest.xml "%_Path_Image%\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\appxmanifest.xml"
)

:: 组件列表导出
call "%Path_Helper%\SxSExport-Mod.cmd"
:: 去掉 WinSxSFoldersList.txt 中的版本号
powershell -Command "Get-Content %txt1%.txt | ForEach-Object { ($_ -split "%ShortBuild%")[0] }| Out-File -Encoding Default _%txt1%.txt"
move _%txt1%.txt %txt1%.txt

if %HostBuild% leq 7601 (
    set Flag_RemoveA=0
    set Flag_RemoveF=0
)

:: 预装应用移除
if /i [%Flag_RemoveA%] == [1] (
    call :LogInfo 开始移除预装应用. . .
    for /f %%i in (%AppxList%) do (
        call :RemoveAppx "%%i"
    )
    call :LogInfo 预装应用移除完成
)

:: 如果移除 商店 则删除 DesktopAppInstaller
type %AppxList% %nul2% | findstr /i "Microsoft.WindowsStore" |findstr ";" || (
    call :LogInfo 移除 桌面应用安装器（DesktopAppInstaller）. . .
    call :RemoveAppx DesktopAppInstaller %nul%
)

:: 如果移除 Defender 则删除 Windows 安全中心
type %ImportList% %nul2% | findstr /i "Windows-Defender" |findstr ";" || (
    call :LogInfo 移除 Windows 安全中心（SecHealthUI）. . .
    call :RemoveAppx SecHealthUI %nul%
)

:: 可选功能移除
if /i [%Flag_RemoveF%] == [1] (
    call :LogInfo 开始移除可选功能. . .
    for /f %%i in (%FunctionList%) do (
        call :RemoveFunction%Flag_REMode% "%%i"
    )
    call :LogInfo 可选功能移除完成
)

:: 组件移除
if /i [%Flag_RemoveC%] == [1] (
    call :LogInfo 开始移除系统组件. . .
    for /f %%i in (%ImportList%) do (
        call :RemoveComponent%Flag_REMode% "%%i"
    )
    rem if %HostBuild% geq 28000 call :FastRemove
    call :LogInfo 系统组件移除完成
)

:: 删除多语言文件夹
call :LogInfo 开始处理多语言文件. . .
del /f /q multilang.txt multilangFolder.txt %nul2%
for /f "tokens=*" %%i in ('dir /b /ad "%_Path_Image%\Windows\System32\*??-??*" %nul6% ^|findstr /v /i "en-US zh-CHS zh-HANS qps %MUI%"') do (
    echo %%i
    echo \%%i>>multilangFolder.txt
)

:: 删除多语言键盘布局
for /f "tokens=*" %%i in ('dir /b /a-d "%_Path_Image%\Windows\WinSxS\Manifests\*-keyboard-*" %nul6% ^|findstr /v "00409 00804 kbdus"') do (
        echo %%~ni
        echo %%i>>multilang.txt
        echo %%~ni>>multilangFolder.txt
    )
)

:: 排除列表
for /f "tokens=1,2,3 delims=_" %%i in ('type WinSxSExclude.txt') do (
    if "%%k" neq "" (echo %%i_%%j_%%k>>_WinSxSExclude.txt) else (echo %%i_%%j>>_WinSxSExclude.txt)
)
move _WinSxSExclude.txt WinSxSExclude.txt
call :sort WinSxSExclude.txt

call :sort WinSxSFoldersList.txt
call :vfindstr "Custom\FileRetainList.txt" WinSxSFoldersList.txt
call :vfindstr WinSxSExclude.txt WinSxSFoldersList.txt
call :vfindstr "Custom\ExtraWinSxSList.txt" WinSxSFoldersList.txt

call :sort WinSxSFilesList.txt
call :vfindstr "Custom\FileRetainList.txt" WinSxSFilesList.txt

:: 多语言文件夹
dir /b /ad "%_Path_Image%\Windows\WinSxS\*_??-*??_*"|findstr /i /v "en-US %MUI%">>multilangFolder.txt
:: NET assembly 缓存
dir /b /ad "%_Path_Image%\Windows\assembly"|findstr /i "NativeImages_">>multilangFolder.txt
:: SystemApps
for /f "tokens=*" %%i in ('type "Custom\SystemApps.txt"') do (
    for /f "tokens=* delims=" %%j in ('dir /b /ad "%_Path_Image%\Windows\SystemApps" %nul6% ^|findstr /i "%%i"') do (
        echo %%j>>multilangFolder.txt
    )
)

echo \Backup>>multilangFolder.txt
dir /b /a-d "%_Path_Image%\Windows\WinSxS\Catalogs">>multilang.txt
dir /b /a-d "%_Path_Image%\Windows\WinSxS\FileMaps">>multilang.txt
call :LogInfo 多语言文件处理完成

:: 映像保存并卸载
call :LogInfo 开始卸载并提交映像更改. . .
call :UnMountImage "%_Path_Image%", "Commit"

if !errorlevel! neq 0 (
    call :LogError 卸载映像失败，错误代码: !errorlevel!
    goto :Exit
)
call :LogInfo 映像卸载成功

:: 生成映像的文件列表
call :LogInfo 生成映像文件列表. . .
%wimlib% dir "%ImageFile%" %ImageIndex% > ImageList.txt

:: 生成映像的文件夹列表
cscript //NoLogo %Path_Helper%\PathExtract.vbs ImageList.txt ImageFolderList.txt
call :sort ImageFolderList.txt

:: 驱动程序的预编译文件
call :grep "*.PNF" ImageList.txt multilang.txt

:: 删除组件中WinSxS下的文件夹列表
type WinSxSFoldersList.txt > WinSxSFiles.txt
call :xfindstr WinSxSFiles.txt ImageFolderList.txt
:: %grep% -Ff WinSxSFoldersList.txt ImageList.txt | findstr /i "Manifests" >> WinSxSFiles.txt

:: 删除组件中除WinSxS目录以外的文件列表
%grep% -Ff WinSxSFilesList.txt ImageList.txt | findstr /i /v "winsxs" >> WinSxSFiles.txt
call :vfindstr "Custom\FileRetainList.txt" WinSxSFiles.txt
call :vfindstr WinSxSExclude.txt WinSxSFiles.txt
call :vfindstr "Custom\ExtraWinSxSList.txt" WinSxSFiles.txt


:: 未包含组件的文件夹/文件列表
del /f /q DelFiles.txt %nul2%
for /f "tokens=*" %%j in ('type Custom\DelFilesList.txt') do (
    echo %%j
    call :grep "%%j" ImageList.txt DelFiles.txt
)

call :vfindstr "Custom\FileRetainList.txt" DelFiles.txt
call :vfindstr WinSxSExclude.txt DelFiles.txt
call :vfindstr "Custom\ExtraWinSxSList.txt" DelFiles.txt
%grep% -ixv -Ff "Custom\EmptyFolders.txt" DelFiles.txt >> _DelFiles.txt
move /y _DelFiles.txt DelFiles.txt %nul1%
call :sort DelFiles.txt

call :xfindstr multilangFolder.txt ImageFolderList.txt
%grep% -iFf multilang.txt ImageList.txt | findstr /i /v "winsxs" >> _multilang.txt
move _multilang.txt multilang.txt %nul1%
type ImageList.txt|findstr /i "pending.xml" >multilang.txt
type ImageList.txt|findstr /i "blobs.bin" >>multilang.txt
type multilangFolder.txt >> multilang.txt
del /f /q multilangFolder.txt %nul2%
call :sort multilang.txt

:: 在保证【Windows 功能打开或关闭】正常的情况下，极限精简 WinSxS
call :LogInfo 生成WinSxS精简列表. . .
if /i [%Flag_SuperLite%] == [1] (
    type ImageFolderList.txt|findstr /i "winsxs" >DelWinSxSFolders.txt
)

call :vfindstr "Custom\FileRetainList.txt" DelWinSxSFolders.txt
call :vfindstr WinSxSFoldersList.txt DelWinSxSFolders.txt
call :vfindstr WinSxSExclude.txt DelWinSxSFolders.txt
call :vfindstr multilang.txt DelWinSxSFolders.txt
call :vfindstr "Custom\ExtraWinSxSList.txt" DelWinSxSFolders.txt
%grep% -ixv -Ff "Custom\EmptyFolders.txt" DelWinSxSFolders.txt >> _DelWinSxSFolders.txt
move /y _DelWinSxSFolders.txt DelWinSxSFolders.txt %nul1%
call :sort DelWinSxSFolders.txt

:: 删除空目录
type WinSxSFiles.txt|findstr /i /v "winsxs">DelEmptyFolders.txt
cscript //NoLogo %Path_Helper%\PathExtract.vbs DelEmptyFolders.txt _DelEmptyFolders.txt
call :vfindstr "Custom\FileRetainList.txt" _DelEmptyFolders.txt
%grep% -ixv -Ff "Custom\EmptyFolders.txt" _DelEmptyFolders.txt > DelEmptyFolders.txt
call :sort DelEmptyFolders.txt

:: 生成 wimlib 统一规范
call :LogInfo 开始执行文件删除操作. . .
set wimupdate="delete --force --recursive"
call :NormList WinSxSFiles.txt %wimupdate%
call :NormList multilang.txt %wimupdate%
call :NormList DelFiles.txt %wimupdate%
call :NormList DelWinSxSFolders.txt %wimupdate%

:: 删除操作
call :LogInfo 删除WinSxS文件. . .
if exist WinSxSFiles.txt %wimlib% update "%ImageFile%" %ImageIndex% < WinSxSFiles.txt

call :LogInfo 删除多语言文件. . .
if exist multilang.txt %wimlib% update "%ImageFile%" %ImageIndex% < multilang.txt

call :LogInfo 删除其他文件. . .
if exist DelFiles.txt %wimlib% update "%ImageFile%" %ImageIndex% < DelFiles.txt

call :LogInfo 删除WinSxS文件夹. . .
if exist DelWinSxSFolders.txt %wimlib% update "%ImageFile%" %ImageIndex% < DelWinSxSFolders.txt

if /i [%Flag_Empty%] == [1] (
    call :LogInfo 开始删除空目录. . .
    del /f /q _DelEmptyFolders.txt %nul2%
    if not exist "%_Path_Image%\Windows" call :MountImage "%ImageFile%", %ImageIndex%, "%_Path_Image%"
    for /f "tokens=*" %%j in ('type DelEmptyFolders.txt') do (
        %NSudo% cmd /c rd "%_Path_Image%%%j"
        if not exist "%_Path_Image%%%j" echo "%%j">>_DelEmptyFolders.txt
    )
    if /i [%Flag_ComCleanup%] == [0] call :UnMountImage "%_Path_Image%", "Commit"
    move _DelEmptyFolders.txt DelEmptyFolders.txt
    call :sort DelEmptyFolders.txt
    call :LogInfo 空目录删除完成
)

if /i [%Flag_ComCleanup%] == [1] if %HostBuild% geq 9600 (
    call :LogInfo 组件存储清理. . .
    if not exist "%_Path_Image%\Windows" call :MountImage "%ImageFile%", %ImageIndex%, "%_Path_Image%"
    echo dism /Image:"%_Path_Image%" /Cleanup-Image /AnalyzeComponentStore
    dism /English /Image:"%_Path_Image%" /Cleanup-Image /AnalyzeComponentStore | find /i "Yes" && dism /Image:"%_Path_Image%" /Cleanup-Image /StartComponentCleanup
)
if exist "%_Path_Image%\Windows" call :UnMountImage "%_Path_Image%", "Commit"   
rem del /f /q ImageList.txt ImageFolderList.txt %nul2%

xcopy /y %txt1%.txt "%CurBuild%\%Arch%\"
xcopy /y %txt2%.txt "%CurBuild%\%Arch%\"
xcopy /y %txt3%.txt "%CurBuild%\%Arch%\"
xcopy /y %RetainList% "%CurBuild%\"
xcopy /y %ImportList% "%CurBuild%\"

for /f "tokens=*" %%i in ('dir /b /ad /s "%~dp0Mount*"') do %NSudo% cmd /c rd /s /q "%%i"
if exist "%_Path_Image%\Windows" goto :exit
:: 优化映像文件
call :LogInfo 开始优化映像文件. . .
if not exist %wimlib% set Flag_optimize=1
call :OptimizeImage%Flag_optimize%
if !errorlevel! neq 0 (
    call :LogError 映像优化失败，错误代码: !errorlevel!
) else (
    call :LogInfo 映像优化完成
)
:exit
call :LogInfo 脚本执行完成
exit

:: 挂载映像
:: 输入参数 [ %~1 ：映像文件名称、%~2 ：映像索引编号、%~3 ：映像安装文件夹 ]
:MountImage
dism /Mount-Image /ImageFile:%~1 /Index:%~2 /MountDir:%~3
goto :EOF

:: 卸载映像
:: 输入参数 [ %~1 ：映像安装文件夹、%~2 ：映像提交 / 丢弃选项 ]
:UnMountImage
echo dism /Unmount-Image /MountDir:"%~1" /%~2
dism /Unmount-Image /MountDir:"%~1" /%~2
goto :EOF

:: 优化映像文件
:OptimizeImage1
set "Index=1"
set "Dest_wim=%ImageFile%%random%"
:NextImage
dism /Get-Wiminfo /WimFile:"%ImageFile%" /Index:%Index% %nul% || (
    move /y "%Dest_wim%" "%ImageFile%"
    ping -n 3 127.1 %nul1%
    exit /b
)
dism /Export-Image /SourceImageFile:"%ImageFile%" /SourceIndex:%Index% /DestinationImageFile:"%Dest_wim%" /Compress:max
set /a Index+=1
goto :NextImage

:OptimizeImage2
%wimlib% optimize %ImageFile% --recompress
goto :EOF

:dk_done
echo 任意键退出
pause %nul1%
exit /b

:dk_setvar
set ps=%SysPath%\WindowsPowerShell\v1.0\powershell.exe
set psc=%ps% -nop -c
set winbuild=1
for /f "tokens=2 delims=[]" %%G in ('ver') do for /f "tokens=2,3,4 delims=. " %%H in ("%%~G") do set "winbuild=%%J"
exit /b

:: 日志系统初始化
:InitializeLogging
echo ========================================= > "%LOG_FILE%"
echo WinSXS清理脚本日志 - 开始时间: %date% %time% >> "%LOG_FILE%"
echo ========================================= >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"
goto :EOF

:: 日志记录函数
:LogInfo
echo [信息] %date% %time% - %* >> "%LOG_FILE%"
echo [信息] %*
goto :EOF

:LogWarning
echo [警告] %date% %time% - %* >> "%LOG_FILE%"
echo [警告] %*
goto :EOF

:LogError
echo [错误] %date% %time% - %* >> "%LOG_FILE%"
echo [错误] %*
goto :EOF

:: 规范列表
:NormList
cscript //NoLogo %Path_Helper%\NormListExtract.vbs "%~1" "_%~1" "%~2" %nul2%
move "_%~1" "%~1" %nul1%
goto :EOF

:: 启用功能
:EnableFeature
for /f "tokens=4" %%f in ('dism /English /Image:"%_Path_Image%" /Get-Features ^| findstr Feature ^| findstr /i "%~1"') do (
    dism /English /Image:"%_Path_Image%" /Get-FeatureInfo /FeatureName:%~1 |findstr /c:"State : Disable" && (
        call :LogInfo 启用功能 [%~1]
        dism /image:"%_Path_Image%" /Enable-feature /Featurename:"%~1"
    )
)
goto :EOF

:: 禁用功能
:DisableFeature
for /f "tokens=4" %%f in ('dism /English /Image:"%_Path_Image%" /Get-Features ^| findstr /c:"Feature Name" ^| findstr /i "%~1"') do (
    dism /English /Image:"%_Path_Image%" /Get-FeatureInfo /FeatureName:%~1 |findstr /c:"State : Enable" && (
        call :LogInfo 禁用功能 [%~1]
        dism /image:"%_Path_Image%" /Disable-Feature /Featurename:"%~1"
    )
)
goto :EOF

:: 移除自带应用 [ %~1 : 应用名称 ]
:RemoveAppx
for /f "tokens=2 delims=: " %%f in ('%Dism% /English /Image:"%_Path_Image%" /Get-ProvisionedAppxPackages ^| findstr PackageName ^| findstr /i "%~1"') do (
    call :LogInfo 移除预装应用 [%~1]
    %Dism% /Image:"%_Path_Image%" /Remove-ProvisionedAppxPackage /PackageName:"%%f"
    reg load HKLM\TMP_SOFTWARE "%_Path_Image%\Windows\System32\config\SOFTWARE" %nul%
    reg query "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications" %nul2% | find "%%f" %nul% && (
        %NSudo% reg delete "HKLM\TMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications\%%f" /f
        %NSudo% cmd /c rd /s /q "%_Path_Image%\Program Files\WindowsApps\%%f"
        %NSudo% cmd /c rd /s /q "%_Path_Image%\Program Files\WindowsApps\*%~1*"
    )
    reg unload HKLM\TMP_SOFTWARE %nul%
)
goto :EOF

:: 移除可选功能 [ %~1 : 功能名称 ]
:RemoveFunction1
:: for /f "tokens=3 delims=: " %%f in ('%Dism% /English /Image:"%_Path_Image%" /Get-Packages ^| find /i "%~1" ^|find "%_Arch%" ^|find /v "%MUI%"') do (
for /f "tokens=*" %%f in ('dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul6% ^|find "%_Arch%" ^|find /v "%MUI%"') do ( 
    call :LogInfo 移除可选功能 [%%~nf]
    %Dism% /Image:"%_Path_Image%" /Remove-Package /PackageName:"%%~nf" && goto :EOF
)
goto :EOF

:RemoveFunction2
:: dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul2% && (
for /f "tokens=*" %%f in ('dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul6% ^|find "%_Arch%" ^|find /v "%MUI%"') do ( 
    call :LogInfo 移除可选功能 [%%~nf]
    %Tweak% /n /p "%_Path_Image%" /r /c "%%~nf"
)
goto :EOF

:: 移除组件的mum文件
:FastRemove
reg load HKLM\TMP_SOFTWARE "%_Path_Image%\Windows\System32\config\SOFTWARE" %nul%
for /f %%i in (%ImportList%) do call :Removemum "%%i"
reg unload HKLM\TMP_SOFTWARE %nul%
goto :EOF

:Removemum
for /f "tokens=*" %%l in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul6%') do (
    %NSudo% reg delete "%RegCBS%\Packages\%%~nl" /f
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\%PathRel_Packages%\%%~nl.*"
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\System32\catroot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}\%%~nl.*"
)
goto :EOF

:: 显示隐藏组件 [ %~1 : 组件名称 ]
:ShowComponent
for /f "tokens=*" %%l in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul6% ^|find /i "%PROCESSOR_ARCHITECTURE%" ^| find /v "%MUI%"') do (
    echo [信息] 显示隐藏组件 [%%~nl]
    %NSudo% reg add "%RegCBS%\Packages\%%~nl" /v Visibility /t REG_DWORD /d 1 /f
    %NSudo% reg add "%RegCBS%\Packages\%%~nl" /v DefVis /t REG_DWORD /d 2 /f
    %NSudo% reg delete "%RegCBS%\Packages\%%~nl\Owners" /f
    %NSudo% reg delete "%RegCBS%\PackagesPending\%%~nl" /f
)
goto :EOF

:: 移除系统组件 [ %~1 : 组件名称 ]
:RemoveComponent1
for /f "tokens=3 delims=: " %%f in ('%Dism% /English /Image:"%_Path_Image%" /Get-Packages ^| findstr /i "%~1" ^| findstr /i /v "%MUI%" ^| findstr /i "%_Arch%"') do (
    call :LogInfo 移除系统组件 [%%f]
    %Dism% /Image:"%_Path_Image%" /Remove-Package /PackageName:"%%f" /Quiet
)
goto :EOF

:RemoveComponent2
:: dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul2% && (
for /f "tokens=*" %%f in ('dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul6% ^|find "%_Arch%" ^|find /v "%MUI%"') do ( 
    call :LogInfo 移除系统组件 [%%~nf]
    %Tweak% /n /p "%_Path_Image%" /r /c "%%~nf"
)
goto :EOF

:: 查找文件或文件夹
:grep
%grep% -iE "\\%~1" "%~2" %nul2% | findstr /i /v "winsxs" >> "%~3"
goto :EOF

:: 匹配文本
:xfindstr
%grep% -Ff "%~1" "%~2" >> "_%~1"
move "_%~1" "%~1" %nul1%
goto :EOF

:: 排除文本
:vfindstr
%grep% -iv -Ff "%~1" "%~2" %nul2% >> "_%~2"
move "_%~2" "%~2" %nul1%
goto :EOF

:: 文本去重
:sort
type %~1 |%sort% -u -r>_%~1
move _%~1 %~1 %nul1%
goto :EOF

:Exit
call :LogInfo 脚本退出
exit /b