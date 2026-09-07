@echo off
:: 本脚本是为了删除组件的winsxs文件目录

:: 设置常用重定向变量
set "nul1=1>nul"
set "nul2=2>nul"
set "nul6=2^>nul"
set "nul=>nul 2>&1"
set "eline=echo: & echo ==== 错误 ==== & echo:"

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
set "LOG_FILE=%~dp0WinSXS_Clean_Online.log"
:: 第二次重启标志
set Flag_Restart=
if exist "%~dp0WinSxSList\Flag_Restart*" set Flag_Restart=1
::type %LOG_FILE% %nul2% | findstr /i %~n0 && set Flag_Restart=1
if not defined Flag_Restart call :InitializeLogging

set Path_Helper=%~dp0_Helper

set "sort=%Path_Helper%\sort.exe"
set "grep=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\grep.exe"
set "NSudo=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\NSudo.exe"
set "Dism=Dism.exe /NoRestart /LogLevel:1"
set "wimlib=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\wimlib-imagex.exe"
set "FCopy=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\FastCopy.exe"
set "MSEdge=%Path_Helper%\setup.exe"
set "Tweak=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\Tweak.exe"
set "StartCleanup=%Path_Helper%\StartCleanup.cmd"
set "offlinereg=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\offlinereg.exe"

if not defined Flag_Restart (
	call :LogInfo 脚本版本: %~n0 %Scr_Ver%
	call :LogInfo 处理器架构: %PROCESSOR_ARCHITECTURE%
	call :LogInfo 辅助工具路径: %Path_Helper%
)

call %Path_Helper%\definitions-Mod.cmd

title %~n0 %Scr_Ver%

:: 选择目标文件夹【C:】
:InImageSource
set _Path_Image=C:
set MUI=zh-CN

:: 设置在线参数
set txt1=WinSXSFoldersList
set txt2=WinSxSFilesList
set txt3=WinSXSExclude
set ReStart_Num=0
set Flag_UAC=1
set "uacpath=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

for /f "tokens=3 delims= " %%m in ('reg query "HKEY_CURRENT_USER\Control Panel\International" ^|find /i "LocaleName"') do set "MUI=%%m"
for /f "tokens=4-6 delims=[]. " %%s in ('ver') do set CurBuild=%%s.%%t.%%u
for /f "tokens=3 delims=." %%f in ('echo %CurBuild%') do set "HostBuild=%%f"
for /f "tokens=1-2 delims=." %%f in ('echo %CurBuild%') do set "ShortBuild=%%f.%%g"

set "Arch=x86"
if exist "%WinDir%\SysWOW64" set "Arch=x64"

set _CurBuild=%CurBuild%
set CurBuild=%ShortBuild%
call :fixBuild %HostBuild% _CurBuild

set "EdgePath=%ProgramFiles%\Microsoft"
if %arch% equ x64 set "EdgePath=%ProgramFiles(x86)%\Microsoft"
if not exist "%EdgePath%\Edge" set "Flag_Edge=0"

if not defined Flag_Restart (
	call :LogInfo 获取系统信息. . .
	call :LogInfo 目标: %_Path_Image%\
	call :LogInfo 版本: %_CurBuild%
	call :LogInfo 语言: %MUI%
	call :LogInfo 体系: %Arch%
	echo.
)

pushd "%~dp0WinSxSList"

if /i [%_Path_Image%] == [%HOMEDRIVE%] if not exist Flag_Restart* (
    echo 即将开始，请确认. . .
    echo.
    if exist "%_Path_Image%\Windows\System32\SecurityHealthSystray.exe" (
        echo Powershell Add-MpPreference -ExclusionPath "\"%~dp0\""
        Powershell Add-MpPreference -ExclusionPath "\"%~dp0\"" %nul2%
    )
    pause
)
:: 管理员账号 Administrator
if "%username%" equ "Administrator" goto :SkipUAC

for /f "tokens=3" %%c in ('reg query "%uacpath%" /v "ConsentPromptBehaviorAdmin"') do set "uac1=%%c"
for /f "tokens=3" %%d in ('reg query "%uacpath%" /v "PromptOnSecureDesktop"') do set "uac2=%%d"

if "%uac1%"=="0x0" if "%uac2%"=="0x0" goto :SkipUAC

:: 备份UAC, 并调整UAC
if defined Flag_UAC (
    reg export "%uacpath%" "UAC_backup.reg" /y
    reg add "%uacpath%" /f /v "ConsentPromptBehaviorAdmin" /t REG_DWORD /d 0
    reg add "%uacpath%" /f /v "PromptOnSecureDesktop" /t REG_DWORD /d 0
)

:SkipUAC
:: 禁用网络
for /f "tokens=1 delims=," %%a in ('Getmac /v /nh /fo csv') do netsh interface set interface %%a disabled

:: 关闭预留空间
dism /English /Online /Get-ReservedStorageState | find /i "enabled" && dism /Online /Set-ReservedStorageState /State:Disabled %nul%

:: 生成重启标志
if exist Flag_Restart1 goto :Restart1
if exist Flag_Restart2 goto :Restart2

if not exist "%CurBuild%\ImportList.txt" echo [信息] 移除列表不存在，是否继续 && pause
if not exist "%CurBuild%\RetainList.txt" echo [信息] 保留列表不存在，是否继续 && pause
xcopy /y "%CurBuild%\ImportList.txt" ..\
xcopy /y "%CurBuild%\RetainList.txt" ..\

:: 如果移除 Defender 则删除 Windows 安全中心
if /i [%Flag_RemoveC%] == [1] (
type %ImportList% %nul2% |findstr /v ";" |findstr /i "Windows-Defender" && (
    call :LogInfo 删除 Windows 安全中心（SecHealthUI）. . .
    echo "%Path_Helper%\RemoveApp.ps1" -remove_appx SecHealthUI
    %NSudo% cmd /c Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\RemoveApp.ps1" -remove_appx SecHealthUI
    powershell -Command "& {Get-AppxPackage *SecHealthUI* | Remove-AppxPackage -EA SilentlyContinue}"
    if not exist "%_Path_Image%\Program Files\Windows Defender" goto :Restart1
    for /r %%f in (Custom\DefenderRemover\*.reg) do (
        echo "%%f"
        %NSudo% cmd /c regedit.exe /s "%%f"
    )
    for /r %%f in (Custom\DefenderRemover\*.reg) do regedit.exe /s "%%f" %nul2%
    set /a ReStart_Num+=1
) || (
    goto :DisableSecHealth
)
) else (
    goto :DisableSecHealth
)

call :LogInfo 设置第%ReStart_Num%次重启后自动运行. . .
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /f /v "%~n0" /t REG_SZ /d "%~0"
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" | findstr /i "%~n0" && echo.>Flag_Restart%ReStart_Num%

call :LogInfo %~n0 准备第%ReStart_Num%次重启系统. . .
shutdown -r -t 6 -c "稍后自动重启系统. . ."
exit

:DisableSecHealth
if exist "%_Path_Image%\Windows\System32\SecurityHealthSystray.exe" (
    echo [信息] 您的Defender防病毒软件可能会阻止脚本. . .
    echo [信息] 临时关闭 Windows 安全中心 的【实时防护】和【篡改防护】. . .
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\WinDefCtl-v2.ps1" rtp off %nul2%
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\WinDefCtl-v2.ps1" tp off %nul2%
    taskkill /f /im SecHealthUI* %nul2%
)
    
:Restart1
if exist Flag_Restart1 (set /a ReStart_Num+=2) else (set /a ReStart_Num+=1)
:: 杀毒单独处理，移除 Defender 文件
if /i [%Flag_RemoveC%] == [1] (
type %ImportList% %nul2% |findstr /v ";" |findstr /i "Windows-Defender" && (
    echo rd /s /q "C:\ProgramData\Microsoft\Windows Defender"
    %NSudo% cmd /c rd /s /q "C:\ProgramData\Microsoft\Windows Defender"
    echo rd /s /q "C:\Program Files\Windows Defender"
    %NSudo% cmd /c rd /s /q "C:\Program Files\Windows Defender"
    echo rd /s /q "C:\Program Files (x86)\Windows Defender"
    %NSudo% cmd /c rd /s /q "C:\Program Files (x86)\Windows Defender"
    echo rd /s /q "C:\Program Files\Windows Defender Advanced Threat Protection"
    %NSudo% cmd /c rd /s /q "C:\Program Files\Windows Defender Advanced Threat Protection"
)
)

:: 系统服务调整
if not defined Flag_Restart call :LogInfo 开始调整系统服务和安全设置. . .

call :LogInfo 配置Windows功能. . .
for /f "tokens=* delims=" %%i in ('type Custom\EnFeatureList.txt') do call :EnableFeature %%i
for /f "tokens=* delims=" %%i in ('type Custom\DisFeatureList.txt') do call :DisableFeature %%i
call :LogInfo Windows功能配置完成

:: 安全中心（默认3）
:: 服务说明：Start 禁用（4）、手动（3）、自动（2）
:: 延迟启动 ：Start=2，DelayedAutoStart=1
dir /b /a-d "%_Path_Image%\Windows\System32\SecurityHealthSystray.exe" %nul2% | findstr /i "SecurityHealthSystray" && (
    call :LogInfo 禁用安全中心服务. . .
    taskkill /f /im SecurityHealthSystray.exe /t %nul2%
    %NSudo% reg add "HKLM\SYSTEM\CurrentControlSet\Services\SecurityHealthService" /f /v "Start" /t REG_DWORD /d 4
)

:: 关闭恶意软件MRT删除工具自动安装
%NSudo% reg add "HKLM\SOFTWARE\Policies\Microsoft\MRT" /f /v "DontOfferThroughWUAU" /t REG_DWORD /d 1

:: WinDefend（默认2）
%NSudo% reg add "HKLM\SYSTEM\CurrentControlSet\Services\WinDefend" /f /v "Start" /t REG_DWORD /d 4
:: wscsvc（默认2）
sc stop wscsvc %nul%
%NSudo% reg add "HKLM\SYSTEM\CurrentControlSet\Services\wscsvc" /f /v "Start" /t REG_DWORD /d 4

:: Edge 任务计划、服务禁用
taskkill /f /im MicrosoftEdgeUpdate.exe /t %nul2% && (
    call :LogInfo 禁用Edge更新服务. . .
    for /f "tokens=1 delims=," %%t in ('schtasks /query /fo csv ^|find /i "edgeupdate"') do %NSudo% cmd /c SchTasks /change /TN "%%t" /disable
    %NSudo% reg add "HKLM\SYSTEM\CurrentControlSet\Services\edgeupdate" /f /v "Start" /t REG_DWORD /d 4
    %NSudo% reg add "HKLM\SYSTEM\CurrentControlSet\Services\edgeupdatem" /f /v "Start" /t REG_DWORD /d 4
)

:: 云盘
type %ImportList% %nul2% |findstr /v ";" |findstr /i "OneDrive-Setup" && (
    call :LogInfo 卸载OneDrive. . .
    taskkill /f /im OneDrive* /t %nul2%
    for /f "delims=" %%o in ('dir /b /s /a-d "%LOCALAPPDATA%\Microsoft\OneDrive\OneDriveSetup.exe"') do %NSudo% cmd /c "%%o" /uninstall
    echo %SystemRoot%\System32\OneDriveSetup.exe /uninstall
    call %SystemRoot%\System32\OneDriveSetup.exe /uninstall %nul2%
    echo %SystemRoot%\SysWOW64\OneDriveSetup.exe /uninstall
    if %arch% equ x64 call %SystemRoot%\SysWOW64\OneDriveSetup.exe /uninstall %nul2%
    if exist "%ProgramFiles%\Microsoft OneDrive" %NSudo% cmd /c rd /s /q "%ProgramFiles%\Microsoft OneDrive"
    if exist "%ProgramFiles%\Microsoft\OneDrive" %NSudo% cmd /c rd /s /q "%ProgramFiles%\Microsoft\OneDrive"
    if exist "%LOCALAPPDATA%\Microsoft\OneDrive" %NSudo% cmd /c rd /s /q "%LOCALAPPDATA%\Microsoft\OneDrive"
    %NSudo% cmd /c reg delete "HKU\DEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /f /v "OneDriveSetup"
)

:: 显示隐藏组件
call :LogInfo 处理隐藏组件. . .
set "RegCBS=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"

:: 禁用 Edge 浏览器自动更新
dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\Microsoft-Windows-Internet-Browser-Package*" %nul2% | findstr /i "Browser" && (
    call :LogInfo 配置Edge浏览器设置. . .
    reg add "HKLM\SOFTWARE\Microsoft\EdgeUpdate" /f /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d 1
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /f /v "DisableEdgeDesktopShortcutCreation" /t REG_DWORD /d 1
    %NSudo% reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\Microsoft.Edge.Stable.%PROCESSOR_ARCHITECTURE%" /f
    %NSudo% reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\%PROCESSOR_ARCHITECTURE%_microsoft-windows-u..argeting-edgestable_31bf3856ad364e35_none_bbc84ae9390a68c3" /f 
)

:: 禁用 SmartScreen
dir /b /a-d "%_Path_Image%\Windows\System32\smartscreen.exe" %nul2% | findstr /i "smartscreen" && (
    call :LogInfo 禁用SmartScreen. . .
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /f /v "SmartScreenEnabled" /t REG_SZ /d "Off"
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" /f /v "ConfigureAppInstallControlEnabled" /t REG_DWORD /d 1
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" /f /v "ConfigureAppInstallControl" /t REG_SZ /d "Anywhere"
    taskkill /f /im smartscreen.exe /t %nul2%
    %NSudo% cmd /c ren "%_Path_Image%\Windows\System32\smartscreen.exe" smartscreen.bak
)

:: 预置列表 MD5Hash.txt
set "MD5HashPath=%CurBuild%\MD5Hash.txt"

:: 校验列表 MD5 与预置 是否匹配
set MD5Hash_Retain=
set MD5Hash_Import=

if /i [%Flag_Retain%] == [1] (
    for /f "delims=" %%i in ('powershell -command "(certutil -hashfile '%CurBuild%\RetainList.txt' MD5)[1] -replace '\s',''"') do set "MD5Hash_Retain=%%i"
    type "%MD5HashPath%" | find "!MD5Hash_Retain!" && (
        del /f /q %txt3%.txt %nul2%
        set Flag_Retain=0
        if exist %CurBuild%\%txt3%.txt xcopy /y "%CurBuild%\%txt3%.txt" .\
    )
    if not exist "%txt3%.txt" set Flag_Retain=1
)

if /i [%Flag_Import%] == [1] (
    for /f "delims=" %%i in ('powershell -command "(certutil -hashfile '%CurBuild%\ImportList.txt' MD5)[1] -replace '\s',''"') do set "MD5Hash_Import=%%i"
    type "%MD5HashPath%" | find "!MD5Hash_Import!" && (
        del /f /q %txt1%.txt %nul2%
        set Flag_Import=0
        if exist %CurBuild%\%txt1%.txt xcopy /y "%CurBuild%\%txt1%.txt" .\
        if exist %CurBuild%\%txt2%.txt xcopy /y "%CurBuild%\%txt2%.txt" .\
    )
    if not exist "%txt1%.txt" set Flag_Import=1
    if not exist "%txt2%.txt" set Flag_Import=1
)

if defined MD5Hash_Retain if defined MD5Hash_Import echo %MD5Hash_Retain% %MD5Hash_Import% > "%MD5HashPath%"

:: dism 模式移除组件
if /i [%Flag_REMode%] == [1] (
    for /f %%i in (%ImportList%) do call :ShowComponent "%%i"
)

if /i [%Flag_Edge%] == [1] (
    call :LogInfo 删除新版Edge浏览器. . .
    echo %MSEdge% --uninstall --system-level --force-uninstall
    start /w %MSEdge% --uninstall --system-level --force-uninstall
    echo %MSEdge% --uninstall --msedgewebview --system-level --force-uninstall
    start /w %MSEdge% --uninstall --msedgewebview --system-level --force-uninstall
    %NSudo% cmd /c del /f /q "%HOMEPATH%\Desktop\Microsoft Edge.lnk"
    %NSudo% cmd /c del /f /q "%PUBLIC%\Desktop\Microsoft Edge.lnk"
    echo rd /s /q "%EdgePath%\EdgeCore"
    %NSudo% cmd /c rd /s /q "%EdgePath%\EdgeCore"
    echo rd /s /q "%EdgePath%\Temp"
    %NSudo% cmd /c rd /s /q "%EdgePath%\Temp"
)

:: 暂停更新天数，默认1000周, 即7000天
set MaxPauseDays=7000
set "datepath=HKCU\Control Panel\International"
reg export "%datepath%" "date_backup.reg" /y

::设置日期格式
reg add "%datepath%" /v sShortDate /t REG_SZ /d yyyy-MM-dd /f 2>nul
set curtime=00:00:00
set curyear=%date:~0,4%
set curmonth=%date:~5,2%
set curday=%date:~8,2%

:: 当前日期
set curdate=%curyear%-%curmonth%-%curday%

call :DateToDays %curyear% %curmonth% %curday% CurDateDays

:: 恢复原有日期格式
if exist "date_backup.reg" (
    reg import "date_backup.reg"
    del /f /q "date_backup.reg"
)

set /a PauseEndDays=%CurDateDays%+%MaxPauseDays%

call :DaysToDate %PauseEndDays% DstYear DstMonth DstDay

:: 暂停更新日期
set DstDate=%DstYear%-%DstMonth%-%DstDay%
if %HostBuild% geq 17763 (
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /f /v "FlightSettingsMaxPauseDays" /t REG_DWORD /d %MaxPauseDays%
    :: 功能更新
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseFeatureUpdatesStartTime" /t REG_SZ /d "%curdate%T%curtime%Z"
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseFeatureUpdatesEndTime" /t REG_SZ /d "%DstDate%T%curtime%Z"
    :: 质量更新
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseQualityUpdatesStartTime" /t REG_SZ /d "%curdate%T%curtime%Z"
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseQualityUpdatesEndTime" /t REG_SZ /d "%DstDate%T%curtime%Z"
    :: 通用更新
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseUpdatesStartTime" /t REG_SZ /d "%curdate%T%curtime%Z"
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseUpdatesExpiryTime" /t REG_SZ /d "%DstDate%T%curtime%Z"
    echo 更新已暂停，直到 %DstDate%
)

:: 组件列表导出
if /i [%Flag_Retain%] == [1] (
    del /f /q %txt3%.txt %nul2%
    call :MergeList %CurBuild%\RetainList.txt v %txt3% %RetainList%
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\ProcessSxSCore.ps1" "%txt3%.txt"
    call :sort %txt3%.txt
    xcopy /y "%CurBuild%\RetainList.txt" ..\
)

if /i [%Flag_RemoveF%] == [1] (
    del /f /q FunctionFoldersList.txt FunctionFilesList.txt %nul2%
    call :MergeList %FunctionList% v FunctionFoldersList %ImportList%
    call :MergeList %FunctionList% i FunctionFilesList %ImportList% 
)

if /i [%Flag_Import%] == [1] (
    del /f /q %txt1%.txt %txt2%.txt %nul2%
    call :MergeList %CurBuild%\ImportList.txt v %txt1% %ImportList%
    call :MergeList %CurBuild%\ImportList.txt i %txt2% %ImportList%
    xcopy /y "%CurBuild%\ImportList.txt" ..\
)

:: 合并可选功能、移除列表的文件夹列表
if exist FunctionFoldersList.txt type FunctionFoldersList.txt>>%txt1%.txt
if exist FunctionFilesList.txt type FunctionFilesList.txt>>%txt2%.txt
del /f /q FunctionFoldersList.txt FunctionFilesList.txt %nul2%

:: 生成最小列表
copy /y "Custom\MiniList.txt" MiniList.txt
if NOT [%MUI%] == [zh-CN] powershell -Command "$content = [System.IO.File]::ReadAllText('MiniList.txt', [System.Text.Encoding]::Default); $newContent = $content.Replace('zh-CN', '%MUI%'); [System.IO.File]::WriteAllText('MiniList.txt', $newContent, [System.Text.Encoding]::Default)"

:: 添加磁盘路径
powershell -NoProfile -command "(Get-Content 'MiniList.txt') -replace '^', 'C:' | Set-Content 'MiniList.txt'"

:: 排除保留的文件夹
call :sort WinSxSFoldersList.txt
call :vfindstr "Custom\FolderRetainList.txt" WinSxSFoldersList.txt
call :vfindstr WinSxSExclude.txt WinSxSFoldersList.txt
call :vfindstr "Custom\ExtraWinSxSList.txt" WinSxSFoldersList.txt

:: 备份重新生成的组件列表，不含IIS组件
if exist %RetainList% if exist %ImportList% (
    xcopy /y %txt1%.txt "%CurBuild%\"
    xcopy /y %txt3%.txt "%CurBuild%\"
)

:: 添加预置的IIS组件列表
if /i [%Flag_Import%] == [1] (
    type %ImportList% %nul2% |findstr /v ";" |findstr /i "IIS-WebServer" && (
        type "Custom\IISFoldersList.txt" >>%txt1%.txt
        type "Custom\IISFilesList.txt" >>%txt2%.txt
    )
)
if /i [%Flag_Retain%] == [1] (  
    type %RetainList% %nul2% |findstr /v ";" |findstr /i "IIS-WebServer" && (
        type "Custom\IISFoldersList.txt" >>%txt3%.txt
    )  
)

:: 生成文件列表
call :LogInfo 生成系统文件列表. . .
dir /a /b /s "%_Path_Image%\" > ImageList.txt
:: 生成文件夹列表
dir /a /b /ad /s "%_Path_Image%\" > ImageFolderList.txt

:: 1.匹配 映像文件夹/文件 路径

:: 删除组件中的文件及文件夹列表

del /f /q WinSxSFiles.txt %nul2%
call :MatchList%Flag_REMode%

:: 保留列表排除
call :vfindstr "Custom\FolderRetainList.txt" WinSxSFiles.txt
:: 最小列表排除
%grep% -ixv -Ff MiniList.txt WinSxSFiles.txt > _WinSxSFiles.txt
move _WinSxSFiles.txt WinSxSFiles.txt %nul1%
:: 列表文件 “永远不为 0 字节”
echo ;; FastCopy List - Empty >> WinSxSFiles.txt
call :sort WinSxSFiles.txt

if /i [%Flag_REMode%] == [3] (
    xcopy /y %txt2%.txt "%CurBuild%\"
)
:: 跳过 Win7 应用和可选功能移除 
if %HostBuild% leq 7601 goto :NoAPPList

:: 预装应用移除
if /i [%Flag_RemoveA%] == [1] (
    call :LogInfo 开始移除预装应用. . .
    :: 如果移除 商店 则删除 DesktopAppInstaller
    type %AppxList% %nul2% |findstr /i "Microsoft.WindowsStore" |findstr ";" || (
        call :LogInfo 移除 桌面应用安装器（DesktopAppInstaller）. . .
        %NSudo% cmd /c Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\RemoveApp.ps1" -remove_appx DesktopAppInstaller
        powershell -Command "Get-AppxPackage *DesktopAppInstaller* -AllUsers | Remove-AppxPackage -AllUsers" %nul%
        powershell -Command "Get-AppxPackage *DesktopAppInstaller* -AllUsers | Remove-AppxPackage" %nul%
    )
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\RemoveApp.ps1" -remove_appx MicrosoftEdge
    for /f %%i in (%AppxList%) do (
        call :RemoveAppx "%%i"
    )
    call :LogInfo 预装应用移除完成
)

:: 可选功能移除
if /i [%Flag_RemoveF%] == [1] (
    call :LogInfo 开始移除可选功能. . .
    del /f /q ChildList.txt %nul2%
    if /i [%Flag_REMode%] == [3] call :GetChildPackages %FunctionList% ChildList.txt
    for /f %%i in (%FunctionList%) do (
        call :RemoveFunction%Flag_REMode% "%%i"
    )
    if exist ChildList.txt for /f %%i in (ChildList.txt) do call :FastRemove "%%i" "可选功能子包"
    call :LogInfo 可选功能移除完成
)

:NoAPPList
:: 组件移除
if /i [%Flag_RemoveC%] == [1] (
    call :LogInfo 开始移除系统组件. . .
    del /f /q ChildList.txt %nul2%
    if /i [%Flag_REMode%] == [3] call :GetChildPackages %ImportList% ChildList.txt
    for /f %%i in (%ImportList%) do (
        call :RemoveComponent%Flag_REMode% "%%i"
    )
    if exist ChildList.txt for /f %%i in (ChildList.txt) do call :FastRemove "%%i" "系统组件子包"
    call :LogInfo 系统组件移除完成
)

:: 清理多余的开始菜单
call :LogInfo 清理多余的开始菜单. . .
if not exist "%LOCALAPPDATA%\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2bak.bin" (
    copy /y "%LOCALAPPDATA%\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin" "%LOCALAPPDATA%\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2bak.bin"
    copy /y "%Path_Helper%\start2.bin" "%LOCALAPPDATA%\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\"
)
for /f "tokens=* delims=" %%i in ('reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount" %nul6% ^|findstr /i "start.tilegrid"') do (
  %NSudo% reg export "%%i\Current" %LOCALAPPDATA%\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\StartLayout.reg
  reg add "%%i\Current" /f /v "Data" /t REG_BINARY /d 02000000bf33a44a2af9db0100000000434201000a0a00d0140cca3200e22c010100cd14120a01267b00380038003000310042003400390035002d0045003000370034002d0034004400370033002d0039003300370041002d003100340030003700320043003000360045003000370033007d000a0595e986c00824f4c00344f39a016693f5d1b8c0c581f07300ca1e100400ca5010043004000000
)
:: 删除第一次重启标志
del /f /q Flag_Restart1 %nul2%

call :LogInfo 设置第%ReStart_Num%次重启后自动运行. . .
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /f /v "%~n0" /t REG_SZ /d "%~0"
reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" | findstr /i "%~n0" && echo.>Flag_Restart2

:: 关闭休眠
powercfg.exe -h off
:: 关闭预留空间
dism /English /Online /Get-ReservedStorageState | find /i "enabled" && dism /Online /Set-ReservedStorageState /State:Disabled %nul2%

call :LogInfo %~n0 准备第%ReStart_Num%次重启系统. . .
shutdown -r -t 6 -c "稍后自动重启系统. . ."
exit

:Restart2
call :LogInfo 第二阶段开始执行. . .

:: 如果排除列表不存在，WinSxS 不进行极限精简
if not exist %RetainList% set Flag_SuperLite=0

:: 关闭预留空间
dism /English /Online /Get-ReservedStorageState | find /i "enabled" && dism /Online /Set-ReservedStorageState /State:Disabled %nul%

:: 删除多语言文件夹
call "%Path_Helper%\LangCode.cmd" %MUI%
call :LogInfo 开始处理多语言文件. . .
del /f /q multilang.txt multilangFolder.txt %nul2%
for /f "tokens=*" %%i in ('dir /b /ad "%_Path_Image%\Windows\System32\*??-??*" %nul6% ^|findstr /i /v "%base_lang% %cur_lang%"') do (
    echo %%i
    echo \%%i>>multilangFolder.txt
)
for /f "tokens=*" %%i in ('dir /b /ad "%_Path_Image%\Windows\SysWOW64\*??-??*" %nul6% ^|findstr /i /v "%base_lang% %cur_lang%"') do (
    echo %%i
    echo \%%i>>multilangFolder.txt
)

:: 删除多语言键盘布局
for /f "tokens=*" %%i in ('dir /b /a-d "%_Path_Image%\Windows\WinSxS\Manifests\*-keyboard-*" %nul6% ^|findstr /i /v "%base_keyboard% %cur_keyboard%"') do (
	echo %%~ni
    echo %%~ni>>multilangFolder.txt
    for /f "tokens=*" %%j in ('dir /b /a-d "%_Path_Image%\Windows\WinSxS\%%~ni" %nul6%') do (
        echo \%%j>>multilang.txt
    )
)

:: 多语言文件夹
dir /b /ad "%_Path_Image%\Windows\WinSxS\*resources*_??*-*??_*"|findstr /i /v "en-US %MUI%">>multilangFolder.txt
:: SystemApps
for /f "tokens=*" %%i in ('type "Custom\SystemApps.txt"') do (
    for /f "tokens=* delims=" %%j in ('dir /b /ad "%_Path_Image%\Windows\SystemApps" %nul6% ^|findstr /i "%%i"') do (
        echo %%j>>multilangFolder.txt
    )
)
:: 生成相关 文件夹 列表
del /f /q DelWinSxSFolders.txt %nul2%
reg query "HKLM\COMPONENTS" >nul 2>&1 && (
    for /f "tokens=5 delims=\" %%c in ('reg query "HKLM\COMPONENTS\DerivedData\Components"') do echo %%c| findstr /i /v /C:"-keyboard-">>DelWinSxSFolders.txt
) || (
    %offlinereg% "%_Path_Image%\Windows\System32\config\COMPONENTS" "DerivedData\Components" enumkeys| findstr /i /v /C:"-keyboard-">DelWinSxSFolders.txt
)
copy /y DelWinSxSFolders.txt DelVerWinSxSFolders.txt
copy /y DelWinSxSFolders.txt DelUltWinSxS.txt

:: 生成相关 文件 列表
dir /b /a-d "%_Path_Image%\Windows\*.log">>multilang.txt
dir /b /a-d /s "%_Path_Image%\Windows\SoftwareDistribution">>multilang.txt
dir /b /a-d /s "%_Path_Image%\Windows\Temp">>multilang.txt
dir /b /a-d /s "%_Path_Image%\Windows\System32\LogFiles">>multilang.txt
dir /b /a-d /s "%LOCALAPPDATA%\Temp">>multilang.txt
:: 删除 相关 文件/文件夹
%NSudo% cmd /c rd /s /q "%_Path_Image%\Windows\WinSxS\Backup"
%NSudo% cmd /c del /f /q "%_Path_Image%\Windows\WinSxS\Catalogs\*.*"
%NSudo% cmd /c del /f /q "%_Path_Image%\Windows\WinSxS\FileMaps\*.*"
if %HostBuild% gtr 7601 (
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\WinSxS\pending.xml"
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\WinSxS\ManifestCache\*blobs.bin"
)

call :LogInfo 多语言文件处理完成

:: 生成文件列表
call :LogInfo 生成系统文件列表. . .
dir /a /b /s "%_Path_Image%\" > ImageList.txt
:: 生成文件夹列表
dir /a /b /ad /s "%_Path_Image%\" > ImageFolderList.txt

:: 在保证【Windows 功能打开或关闭】正常的情况下，极限精简 WinSxS
if /i [%Flag_SuperLite%] == [1] (
    call :LogInfo 生成WinSxS精简列表. . .
    %grep% -v -Ff "Custom\FolderRetainList.txt" DelWinSxSFolders.txt >> _DelWinSxSFolders.txt
    move /y _DelWinSxSFolders.txt DelWinSxSFolders.txt %nul1%
    call :vfindstr WinSxSExclude.txt DelWinSxSFolders.txt
    call :vfindstr "Custom\ExtraWinSxSList.txt" DelWinSxSFolders.txt
)

:: 低版本组件文件夹清理
if /i [%Flag_SxSVerCleanup%] == [1] (
    call :vfindstr "Custom\FolderRetainList.txt" DelVerWinSxSFolders.txt
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\SxSVerCleanup.ps1" "DelVerWinSxSFolders.txt"
    move /y _DelVerWinSxSFolders.txt DelVerWinSxSFolders.txt %nul1%
)

:: 极致 WinSxS 清理，后遗症：每种功能不可正常打开或关闭
if /i [%Flag_UltraLite%] == [1] (
    dir /b /a-d "%_Path_Image%\Windows\WinSxS\Manifests" |findstr /i /v /C:"-keyboard-">DelUltManifests.txt
    dir /b /a-d "%_Path_Image%\Windows\WinSxS\Manifests\*resources*_???*-*??_*" |findstr /i /v "en-US %MUI%">DelUltManifestsLang.txt
    dir /b /a-d "%_Path_Image%\Windows\WinSxS\Manifests\*-keyboard-*" |findstr /v "%base_keyboard% %cur_keyboard%">>DelUltManifestsLang.txt
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\SxSVerCleanup.ps1" "DelUltWinSxS.txt"
    %grep% -v -Ff "Custom\FolderRetainList.txt" DelUltWinSxS.txt >> _DelUltWinSxS.txt
    move /y _DelUltWinSxS.txt DelUltWinSxS.txt %nul1%
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\SxSVerCleanup.ps1" "DelUltManifests.txt"
    %grep% -v -Ff "Custom\FolderRetainList.txt" DelUltManifests.txt >> _DelUltManifests.txt
    move /y _DelUltManifests.txt DelUltManifests.txt %nul1%
    type DelUltManifestsLang.txt>>DelUltManifests.txt
    call :xfindstr DelUltManifests.txt ImageList.txt
    set Flag_ComCleanup=0
)

:: 2.匹配 映像文件夹/文件 路径

:: 合并多语言文件夹
%grep% -iFf multilang.txt ImageList.txt | findstr /i /v "winsxs" >> _multilang.txt
move _multilang.txt multilang.txt %nul1%
call :xfindstr multilangFolder.txt ImageFolderList.txt
type multilangFolder.txt >>multilang.txt
del /f /q multilangFolder.txt %nul2%
call :sort multilang.txt
echo ;; FastCopy List - Empty >> multilang.txt
if /i [%Flag_Lang%] == [0] del /f /q multilang.txt %nul2%

:: 未包含组件的文件夹/文件列表
del /f /q DelFiles.txt %nul2%
for /f "tokens=*" %%j in ('type Custom\DelFilesList.txt') do (
    echo %%j
    call :grep "%%j" ImageList.txt DelFiles.txt
)
call :vfindstr "Custom\FileRetainList.txt" DelFiles.txt
call :vfindstr "Custom\FolderRetainList.txt" DelFiles.txt
call :sort DelFiles.txt
if /i [%Flag_DelFiles%] == [0] del /f /q DelFiles.txt %nul2%

:: 匹配 WinSxS 路径
if exist DelWinSxSFolders.txt (
    call :xfindstr DelWinSxSFolders.txt ImageFolderList.txt
    call :sort DelWinSxSFolders.txt
    echo ;; FastCopy List - Empty >> DelWinSxSFolders.txt
    if /i [%Flag_SuperLite%] == [0] del /f /q DelWinSxSFolders.txt %nul2%
)
if exist DelVerWinSxSFolders.txt (
    call :xfindstr DelVerWinSxSFolders.txt ImageFolderList.txt
    call :sort DelVerWinSxSFolders.txt
    echo ;; FastCopy List - Empty >> DelVerWinSxSFolders.txt
    if /i [%Flag_SxSVerCleanup%] == [0] del /f /q DelVerWinSxSFolders.txt %nul2%
)
if exist DelUltWinSxS.txt (
    call :xfindstr DelUltWinSxS.txt ImageFolderList.txt
    type DelUltManifests.txt>>DelUltWinSxS.txt
    call :sort DelUltWinSxS.txt
    del /f /q DelUltManifests.txt DelUltManifestsLang.txt %nul2%
    echo ;; FastCopy List - Empty >> DelUltWinSxS.txt
    if /i [%Flag_UltraLite%] == [0] del /f /q DelUltWinSxS.txt %nul2%
)

call :LogInfo 开始执行文件删除操作. . .
:: 开始删除

type %ImportList% %nul2% |findstr /v ";" |findstr /i "OneDrive-Setup" && (
    taskkill /f /im OneDrive* /t %nul2%
    for /f "delims=" %%o in ('dir /b /s /a-d "%LOCALAPPDATA%\Microsoft\OneDrive\OneDriveSetup.exe"') do %NSudo% cmd /c "%%o" /uninstall
    echo rd /s /q "%ProgramFiles%\Microsoft OneDrive"
    %NSudo% cmd /c rd /s /q "%ProgramFiles%\Microsoft OneDrive"
    echo rd /s /q "%ProgramFiles%\Microsoft\OneDrive"
    %NSudo% cmd /c rd /s /q "%ProgramFiles%\Microsoft\OneDrive"
    echo rd /s /q "%LOCALAPPDATA%\Microsoft\OneDrive"
    %NSudo% cmd /c rd /s /q "%LOCALAPPDATA%\Microsoft\OneDrive"
)
   
if /i [%Flag_Edge%] == [1] (
    %NSudo% cmd /c del /f /q "%HOMEPATH%\Desktop\Microsoft Edge.lnk"
    %NSudo% cmd /c del /f /q "%PUBLIC%\Desktop\Microsoft Edge.lnk"
    echo rd /s /q "%EdgePath%\Edge"
    %NSudo% cmd /c rd /s /q "%EdgePath%\Edge"
    echo rd /s /q "%EdgePath%\EdgeCore"
    %NSudo% cmd /c rd /s /q "%EdgePath%\EdgeCore"
    echo rd /s /q "%EdgePath%\Temp"
    %NSudo% cmd /c rd /s /q "%EdgePath%\Temp"
)

if exist WinSxSFiles.txt (
    call :LogInfo 删除WinSxS文件. . .
    call :FastCopy "WinSxSFiles.txt"
)

if exist multilang.txt (
    call :LogInfo 删除多语言文件. . .
    call :FastCopy "multilang.txt"
)

if exist DelFiles.txt (
    call :LogInfo 删除其他文件. . .
    call :FastCopy "DelFiles.txt"
)

if exist DelWinSxSFolders.txt (
    call :LogInfo 删除WinSxS文件夹. . .
    call :FastCopy "DelWinSxSFolders.txt"
    del /f /q Flag_Restart2 %nul2%
)

:: 低版本组件文件夹清理
if /i [%Flag_SxSVerCleanup%] == [1] if %HostBuild% leq 7601 (
    call :LogInfo 删除低版本WinSxS文件夹. . .
    call :FastCopy "DelVerWinSxSFolders.txt"
)

:: 极致 WinSxS 清理
if /i [%Flag_UltraLite%] == [1] if exist DelUltWinSxS.txt (
    call :LogInfo 删除更多WinSxS文件夹，功能不可正常打开或关闭. . .
    call :FastCopy "DelUltWinSxS.txt"
)

:: 删除空目录
type WinSxSFiles.txt|findstr /i /v "winsxs">DelEmptyFolders.txt
cscript //NoLogo %Path_Helper%\PathExtract.vbs DelEmptyFolders.txt _DelEmptyFolders.txt
move _DelEmptyFolders.txt DelEmptyFolders.txt %nul1%
call :sort DelEmptyFolders.txt
call :LogInfo 删除空目录. . .
for /f "delims=" %%j in (DelEmptyFolders.txt) do (
    echo rd "%%j"
    %NSudo% cmd /c rd "%%j"
    if not exist "%%j" echo "%%j">>_DelEmptyFolders.txt
)

move _DelEmptyFolders.txt DelEmptyFolders.txt %nul1% 
call :sort DelEmptyFolders.txt
call :LogInfo 空目录删除完成

:: 启用网络
for /f "tokens=1 delims=," %%a in ('Getmac /v /nh /fo csv') do netsh interface set interface %%a enabled
:: 恢复原始UAC设置
if exist "UAC_backup.reg" (
    reg import "UAC_backup.reg"
    del /f /q "UAC_backup.reg"
)

REM del /f /q ImageList.txt ImageFolderList.txt %nul2%
del /f /q WinSxSFilesList.txt WinSxSFoldersList.txt WinSxSExclude.txt MiniList.txt %nul2%
del /f /q %ImportList% %RetainList% %nul2%

timeout /t 3 %nul1%
taskkill /f /im FastCopy.exe /t %nul2%
del /f /q "%Path_Helper%\%PROCESSOR_ARCHITECTURE%\fastcopy_*.*" %nul2%

:: dism 组件存储清理，进一步减少 WinSxS 文件夹占用
if /i [%Flag_ComCleanup%] == [1] if %HostBuild% geq 9600 (
    call :LogInfo 组件存储清理. . .
    echo dism /Online /Cleanup-Image /StartComponentCleanup
    dism /English /Online /Cleanup-Image /StartComponentCleanup |find /i "pending" && reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /f /v "%~n0" /t REG_SZ /d "C:\Windows\system32\cmd.exe /c \"%StartCleanup%\""
    shutdown -r -t 6 -c "稍后自动重启系统 清理组件存储. . ." 
)

call :LogInfo 在线清理完成
:: choice /T 6 /C yn /M "重启请按 y，否请按 n，不选默认重启。" /D y
:exit
call :LogInfo 脚本执行完成
exit

:MatchList1
type %txt1%.txt > %txt2%.txt
%grep% -iFf %txt2%.txt ImageList.txt | findstr /i /v "Manifests" >> _%txt2%.txt
move _%txt2%.txt %txt2%.txt %nul1%
del /f /q WinSxSFiles.txt %nul2%
for /f "delims=" %%i in (%txt2%.txt) do call :fsutil "%%i"
call :vfindstr "Custom\FileRetainList.txt" WinSxSFiles.txt
:: 添加磁盘路径
powershell -NoProfile -command "(Get-Content 'WinSxSFiles.txt') -replace '^', 'C:' | Set-Content 'WinSxSFiles.txt'"
type %txt2%.txt >> WinSxSFiles.txt
exit /b

:MatchList2
call :MatchList1
exit /b

:MatchList3
:: 删除组件中除WinSxS目录以外的文件列表
%grep% -iFf %txt2%.txt ImageList.txt | findstr /i /v "winsxs" >> WinSxSFiles.txt
call :vfindstr "Custom\FileRetainList.txt" WinSxSFiles.txt
call :xfindstr %txt1%.txt ImageFolderList.txt
type %txt1%.txt >> WinSxSFiles.txt
exit /b

:: 生成 组件列表的子包 [ %~1 ：组件列表、%~2 ：子包列表 ]
:GetChildPackages
type %~1 | findstr /v ; > PackageList.txt
"%Path_Helper%\GetChildPackages.exe" --dir "%_Path_Image%\Windows\%PathRel_Packages%" --list PackageList.txt --subpackages %~2
del /f /q PackageList.txt %nul2%
exit /b

:: 查找文件包含的硬链接
:fsutil
echo %~1
if exist "%~1" fsutil hardlink list "%~1" |findstr /i /v "WinSxS">>WinSxSFiles.txt
exit /b

:: 合并列表 %~2=i 表示合并文件；%~2=v 表示合并文件夹
:MergeList
for /f %%i in ('type %~1 ^|findstr /i /v "IIS-WebServer"') do (
	if exist %CurBuild%\Package\%%i.txt (
	    echo %%i
		type %CurBuild%\Package\%%i.txt | findstr /%~2 \ >>%~3.txt
	) else (
	    if exist "%_Path_Image%\Windows\%PathRel_Packages%\%%i~*.mum" (
            echo %%i
            echo %%i>%~4
            call "%Path_Helper%\SxSExport-Mod.cmd" %~4
            type %%i.txt | findstr /v \ > _%%i.txt
            Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\ExtractCore.ps1" _%%i.txt
            type %%i.txt | findstr /i \ >>  _%%i.txt
            type _%%i.txt |%sort% -u> %%i.txt
            del /f /q _%%i.txt %nul2%
            type %%i.txt | findstr /%~2 \ >>%~3.txt
            move /y %%i.txt %CurBuild%\Package\%%i.txt    
	    )
	)
)
exit /b

:: 统一版本
:fixBuild
if %1 geq 18362 if %1 lss 19041 set %~2=%ShortBuild%.1836X
if %1 geq 19041 if %1 lss 22000 set %~2=%ShortBuild%.1904X
if %1 geq 22621 if %1 lss 26100 set %~2=%ShortBuild%.226X1
if %1 geq 26100 if %1 lss 28000 set %~2=%ShortBuild%.26X00
if %~1 geq 22000 set CurBuild=11.0
exit /b

:: 日期转换为天数 %yy% %mm% %dd% days
:DateToDays
setlocal ENABLEEXTENSIONS
set yy=%1&set mm=%2&set dd=%3
if 1%yy% LSS 200 if 1%yy% LSS 170 (set yy=20%yy%) else (set yy=19%yy%)
set /a dd=100%dd%%%100,mm=100%mm%%%100
set /a z=14-mm,z/=12,y=yy+4800-z,m=mm+12*z-3,j=153*m+2
set /a j=j/5+dd+y*365+y/4-y/100+y/400-2472633
endlocal&set %4=%j%&goto :EOF

:: 天数转换为日期 %days% yy mm dd
:DaysToDate 
setlocal ENABLEEXTENSIONS
set /a a=%1+2472632,b=4*a+3,b/=146097,c=-b*146097,c/=4,c+=a
set /a d=4*c+3,d/=1461,e=-1461*d,e/=4,e+=c,m=5*e+2,m/=153,dd=153*m+2,dd/=5
set /a dd=-dd+e+1,mm=-m/10,mm*=12,mm+=m+3,yy=b*100+d-4800+m/10
(if %mm% LSS 10 set mm=0%mm%)&(if %dd% LSS 10 set dd=0%dd%)
endlocal&set %2=%yy%&set %3=%mm%&set %4=%dd%&goto :EOF

:: FastCopy 快速删除
:FastCopy
%NSudo% cmd /c %FCopy% /cmd=delete /no_confirm_del /log=FALSE /error_stop=FALSE /balloon=FALSE /force_close /srcfile=%~1
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
echo WinSXS在线清理脚本日志 - 开始时间: %date% %time% >> "%LOG_FILE%"
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

:: 启用功能
:EnableFeature
for /f "tokens=4" %%f in ('dism /English /Online /Get-Features ^| findstr Feature ^| findstr /i "%~1"') do (
    dism /English /Online /Get-FeatureInfo /FeatureName:%~1 |findstr /c:"State : Disable" && (
        call :LogInfo 启用功能 [%~1]
        %Dism% /Online /Enable-feature /Featurename:"%~1"
    )
)
goto :EOF

:: 禁用功能
:DisableFeature
for /f "tokens=4" %%f in ('dism /English /Online /Get-Features ^| findstr /c:"Feature Name" ^| findstr /i "%~1"') do (
    dism /English /Online /Get-FeatureInfo /FeatureName:%~1 |findstr /c:"State : Enable" && (
        call :LogInfo 禁用功能 [%~1]
        %Dism% /Online /Disable-Feature /Featurename:"%~1"
    )
)
goto :EOF

:: 移除自带应用 [ %~1 : 应用名称 ]
:RemoveAppx
for /f "tokens=2 delims=: " %%f in ('dism /English /online /Get-ProvisionedAppxPackages ^| findstr PackageName ^| findstr /i "%~1"') do (
    call :LogInfo 移除预装应用 [%~1]
    %Dism% /online /Remove-ProvisionedAppxPackage /PackageName:"%%f"
    powershell -Command "& {Remove-AppxPackage -Package "%%f" -EA SilentlyContinue}"
)
for /f "tokens=*" %%f in ('dir /b /ad "%_Path_Image%\Program Files\WindowsApps\*%~1*" %nul6%') do (
    powershell -Command "& {Remove-AppxPackage -Package "%%f" -EA SilentlyContinue}"
    powershell Remove-AppxPackage -AllUsers "%%f" %nul%
    powershell Remove-AppxPackage "%%f" %nul%
    %NSudo% cmd /c rd /s /q "%_Path_Image%\Program Files\WindowsApps\%%f"
    %NSudo% cmd /c rd /s /q "%_Path_Image%\Program Files\WindowsApps\*%~1*"
)
goto :EOF

:: 移除可选功能 [ %~1 : 功能名称 ]
:RemoveFunction1
for /f "tokens=*" %%f in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul6% ^|find /i "%PROCESSOR_ARCHITECTURE%" ^|find /v "%MUI%"') do (
    reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages\%%~nf" /v "CurrentState" %nul2% | find "0x70" %nul% && (
        call :LogInfo 移除可选功能 [%%~nf]
        %Dism% /Online /Remove-Package /PackageName:"%%~nf"
    )
)
goto :EOF

:RemoveFunction2
for /f "tokens=*" %%f in ('dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1*.mum" %nul6% ^|find /i "%PROCESSOR_ARCHITECTURE%" ^|find /v "%MUI%"') do (
    call :LogInfo 移除可选功能 [%%~nf]
    %Tweak% /o /c "%%~nf" /r
)
goto :EOF

:RemoveFunction3
call :Removemum %~1 "可选功能"
goto :EOF

:: 移除组件的mum文件
:FastRemove
for /f "tokens=*" %%l in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1*.mum" %nul6%') do (
    %NSudo% reg delete "%RegCBS%\Packages\%%~nl" /f
    %NSudo% reg delete "%RegCBS%\PackagesPending\%%~nl" /f
    echo [信息] 快速移除%~2 [%%~nl]
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\%PathRel_Packages%\%%~nl.*"
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\System32\catroot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}\%%~nl.*"
)
goto :EOF

:Removemum
for /f "tokens=*" %%l in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1*.mum" %nul6%') do (
    %NSudo% reg delete "%RegCBS%\Packages\%%~nl" /f
    %NSudo% reg delete "%RegCBS%\PackagesPending\%%~nl" /f
    call :LogInfo 快速移除%~2 [%%~nl]
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
dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul% || goto :EOF 
for /f "tokens=3 delims=: " %%f in ('dism /English /Online /Get-Packages ^| findstr /i "%~1" ^|find /i "%PROCESSOR_ARCHITECTURE%" ^| findstr /v "%MUI%"') do (
    call :LogInfo 移除系统组件 [%%f]
    %Dism% /Online /Remove-Package /PackageName:"%%f" /Quiet %nul%
)
goto :EOF

:RemoveComponent2
for /f "tokens=*" %%f in ('dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1*.mum" %nul6% ^|find /i "%PROCESSOR_ARCHITECTURE%" ^|find /v "%MUI%"') do (
    call :LogInfo 移除系统组件 [%%~nf]
    %Tweak% /o /c "%%~nf" /r
)
goto :EOF

:RemoveComponent3
call :Removemum %~1 "系统组件"
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
if exist %~1 %sort% -u -r %~1 -o %~1
goto :EOF

:Exit
call :LogInfo 脚本退出
exit /b