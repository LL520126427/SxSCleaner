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
set "LOG_FILE=%~dp0WinSXS_Clean_Offline.log"
call :InitializeLogging

set Path_Helper=%~dp0_Helper

set "sort=%Path_Helper%\sort.exe"
set "grep=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\grep.exe"
set "NSudo=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\NSudo.exe"
set "Dism=Dism.exe /LogLevel:1"
set "wimlib=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\wimlib-imagex.exe"
set "Tweak=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\Tweak.exe"
set "offlinereg=%Path_Helper%\%PROCESSOR_ARCHITECTURE%\offlinereg.exe"

set "_Path_Image=%~dp0Mount_%random%"

:: 测试用
for /d %%i in ("%~dp0Mount_*") do (
    if exist "%%i\Windows\explorer.exe" set "_Path_Image=%%i"
)

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
    timeout /t 3 /NOBREAK
    goto :Exit
)

call :LogInfo 选择的镜像文件: %ImageFile%

set ImageIndex=1
for /f "tokens=2 delims=: " %%a in ('dism /English /Get-WimInfo /WimFile:"%ImageFile%" ^| find /i "Index"') do set ImageIndex=%%a

if %ImageIndex% gtr 1 (
    call :LogInfo 检测到多个镜像索引，当前索引: %ImageIndex%
    dism /Get-Wiminfo /WimFile:"%ImageFile%"
    set /p ImageIndex=请输入映像索引数字[1-%ImageIndex%]回车 直接回车默认索引1：
)

for /f "tokens=1 delims=	 " %%f in ('dism /English /Get-WimInfo /WimFile:"%ImageFile%" /Index:%ImageIndex% ^| find /i "Default"') do set MUI=%%f
for /f "tokens=3 delims= " %%v in ('dism /English /Get-WimInfo /WimFile:"%ImageFile%" /Index:%ImageIndex% ^| findstr /i /c:"Version :"') do set CurBuild=%%v
for /f "tokens=2 delims=: " %%c in ('dism /English /Get-WimInfo /WimFile:"%ImageFile%" /Index:%ImageIndex% ^| findstr /i /c:"Architecture"') do set Arch=%%c
for /f "tokens=3 delims=." %%f in ('echo %CurBuild%') do set "HostBuild=%%f"
for /f "tokens=1-2 delims=." %%f in ('echo %CurBuild%') do set "ShortBuild=%%f.%%g"

pushd "%~dp0WinSxSList"

set _Arch=%Arch%
if %Arch% equ x64 set _Arch=amd64

set _CurBuild=%CurBuild%
set CurBuild=%ShortBuild%
call :fixBuild %HostBuild% _CurBuild

call :LogInfo 获取映像信息. . .
call :LogInfo 目标: %ImageFile%
call :LogInfo 版本: %_CurBuild%
call :LogInfo 语言: %MUI%
call :LogInfo 体系: %Arch%
echo.
pause
if not exist "%_Path_Image%" (
    call :LogInfo 创建挂载目录: "%_Path_Image%"
    md "%_Path_Image%"
)

if not exist "%CurBuild%\ImportList.txt" echo [信息] 移除列表不存在，是否继续 && pause
if not exist "%CurBuild%\RetainList.txt" echo [信息] 保留列表不存在，是否继续 && pause
xcopy /y "%CurBuild%\ImportList.txt" ..\
xcopy /y "%CurBuild%\RetainList.txt" ..\

call :LogInfo 开始挂载映像. . .
if not exist "%_Path_Image%\Windows" call :MountImage "%ImageFile%" %ImageIndex% "%_Path_Image%"

if !errorlevel! neq 0 (
    call :LogError 挂载映像失败，错误代码: !errorlevel!
    goto :Exit
)
call :LogInfo 映像挂载成功

set "EdgePath=%_Path_Image%\Program Files\Microsoft"
if %arch% equ x64 set "EdgePath=%_Path_Image%\Program Files (x86)\Microsoft"
if not exist "%EdgePath%\Edge" set "Flag_Edge=0"

:: 启用和禁用功能
call :LogInfo 开始配置Windows功能. . .
for /f "tokens=* delims=" %%i in ('type Custom\EnFeatureList.txt') do call :EnableFeature %%i
for /f "tokens=* delims=" %%i in ('type Custom\DisFeatureList.txt') do call :DisableFeature %%i
call :LogInfo Windows功能配置完成

:: 显示隐藏组件
call :LogInfo 开始处理隐藏组件. . .
call :RegLoad SOFTWARE
set "RegCBS=HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Component Based Servicing"

if exist "%_Path_Image%\Windows\%PathRel_Packages%\*17514*.mum" (
    for /f "tokens=*" %%l in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\*16385*.mum"') do (
        echo [信息] 删除旧版组件 [%%l]
        %NSudo% reg delete "%RegCBS%\PackagesPending\%%~nl" /f
        %NSudo% reg delete "%RegCBS%\Packages\%%~nl" /f
        %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\%PathRel_Packages%\%%~nl.*"
        %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\System32\catroot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}\%%~nl.*"
    )
)

dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\Microsoft-Windows-Internet-Browser-Package*" %nul2% | findstr /i "Browser" && (
    call :LogInfo 配置Edge浏览器设置. . .
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\EdgeUpdate" /f /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d 1
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Explorer" /f /v "DisableEdgeDesktopShortcutCreation" /t REG_DWORD /d 1
    %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\Installed\Microsoft.Edge.Stable.%_Arch%" /f
    %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\SideBySide\Winners\%_Arch%_microsoft-windows-u..argeting-edgestable_31bf3856ad364e35_none_bbc84ae9390a68c3" /f 
)

dir /b /a-d "%_Path_Image%\Windows\System32\smartscreen.exe" %nul2% | findstr /i "smartscreen" && (
    call :LogInfo 禁用SmartScreen. . .
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Explorer" /f /v "SmartScreenEnabled" /t REG_SZ /d "Off"
    reg add "HKLM\%TMP_SOFTWARE%\Policies\Microsoft\Windows Defender\SmartScreen" /f /v "ConfigureAppInstallControlEnabled" /t REG_DWORD /d 1
    reg add "HKLM\%TMP_SOFTWARE%\Policies\Microsoft\Windows Defender\SmartScreen" /f /v "ConfigureAppInstallControl" /t REG_SZ /d "Anywhere"
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
    echo reg delete "HKLM\%TMP_SOFTWARE%\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f
    %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f
    echo reg delete "HKLM\%TMP_SOFTWARE%\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    echo reg delete "HKLM\%TMP_SOFTWARE%\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" /f
    %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" /f
    echo reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f
    echo reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f
    echo reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" /f
    %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" /f
    echo rd /s /q "%EdgePath%"
    %NSudo% cmd /c rd /s /q "%EdgePath%"
)

:: 关闭预留空间
reg add "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\ReserveManager" /f /v "ShippedWithReserves" /t REG_DWORD /d 0

:: 关闭恶意软件MRT删除工具自动安装
%NSudo% reg add "HKLM\%TMP_SOFTWARE%\Policies\Microsoft\MRT" /f /v "DontOfferThroughWUAU" /t REG_DWORD /d 1

:: 如果移除 Defender 则删除 Windows 安全中心 启动项
if /i [%Flag_RemoveC%] == [1] (
    type %ImportList% %nul2% |findstr /i "Windows-Defender" |findstr ";" || (
        echo reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Run" /f /v "SecurityHealth"
        %NSudo% cmd /c reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Run" /f /v "SecurityHealth"
    )
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
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\WindowsUpdate\UX\Settings" /f /v "FlightSettingsMaxPauseDays" /t REG_DWORD /d %MaxPauseDays%
    :: 功能更新
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseFeatureUpdatesStartTime" /t REG_SZ /d "%curdate%T%curtime%Z"
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseFeatureUpdatesEndTime" /t REG_SZ /d "%DstDate%T%curtime%Z"
    :: 质量更新
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseQualityUpdatesStartTime" /t REG_SZ /d "%curdate%T%curtime%Z"
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseQualityUpdatesEndTime" /t REG_SZ /d "%DstDate%T%curtime%Z"
    :: 通用更新
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseUpdatesStartTime" /t REG_SZ /d "%curdate%T%curtime%Z"
    reg add "HKLM\%TMP_SOFTWARE%\Microsoft\WindowsUpdate\UX\Settings" /f /v "PauseUpdatesExpiryTime" /t REG_SZ /d "%DstDate%T%curtime%Z"
    echo 更新已暂停，直到 %DstDate%
)

reg unload HKLM\%TMP_SOFTWARE% %nul%

:: 关闭休眠
%offlinereg% "%_Path_Image%\Windows\System32\config\SOFTWARE" "ControlSet001\Control\Power" setvalue HibernateEnabledDefault 0
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

:: 生成映像的文件列表
call :LogInfo 生成映像文件列表. . .
%wimlib% dir "%ImageFile%" %ImageIndex% > ImageList.txt

:: 生成映像的文件夹列表
cscript //NoLogo %Path_Helper%\PathExtract.vbs ImageList.txt ImageFolderList.txt
call :sort ImageFolderList.txt

:: 1.匹配 映像文件夹/文件 路径
:: 删除组件中的文件及文件夹列表
del /f /q WinSxSFiles.txt %nul2%
call :MatchList%Flag_REMode%

:: 保留列表排除
call :vfindstr "Custom\FolderRetainList.txt" WinSxSFiles.txt
:: 生成最小列表
copy /y "Custom\MiniList.txt" MiniList.txt
if NOT [%MUI%] == [zh-CN] powershell -Command "$content = [System.IO.File]::ReadAllText('MiniList.txt', [System.Text.Encoding]::Default); $newContent = $content.Replace('zh-CN', '%MUI%'); [System.IO.File]::WriteAllText('MiniList.txt', $newContent, [System.Text.Encoding]::Default)"
:: 最小列表排除
%grep% -ixv -Ff MiniList.txt WinSxSFiles.txt > _WinSxSFiles.txt
move _WinSxSFiles.txt WinSxSFiles.txt %nul1%
call :sort WinSxSFiles.txt

if /i [%Flag_REMode%] == [3] (
    xcopy /y %txt2%.txt "%CurBuild%\"
    call :RegLoad SOFTWARE
)
:: 跳过 Win7 应用和可选功能移除
if %HostBuild% leq 7601 goto :NoAPPList

:: 预装应用移除
if /i [%Flag_RemoveA%] == [1] (
    call :LogInfo 开始移除预装应用. . .
    :: 如果移除 商店 则删除 DesktopAppInstaller
    type %AppxList% %nul2% |findstr /i "Microsoft.WindowsStore" |findstr ";" || (
        call :LogInfo 移除 桌面应用安装器（DesktopAppInstaller）. . .
        call :RemoveAppx%Flag_REMode% DesktopAppInstaller %nul%
    )
    :: 如果移除 Defender 则删除 Windows 安全中心
    type %ImportList% %nul2% |findstr /i "Windows-Defender" |findstr ";" || (
        call :LogInfo 移除 Windows 安全中心（SecHealthUI）. . .
        call :RemoveAppx%Flag_REMode% SecHealthUI %nul%
    )  
    for /f %%i in (%AppxList%) do (
        call :RemoveAppx%Flag_REMode% "%%i"
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
del /f /q ChildList.txt %nul2%
reg unload HKLM\%TMP_SOFTWARE% %nul%
:: 经测试，集成补丁【KB5027574】之后，移除组件时会导致 install.wim 打印扫描功能 无法正常启用或禁用，建议不集成
:: 无论是否集成补丁【KB5027574】，已部署的操作系统 移除Microsoft-Windows-BusinessScanning-Feature-Package和Microsoft-Windows-Printer-Drivers-Package，会导致 打印功能无法正常启用或禁用

for /f "tokens=6,7 delims=_." %%i in ('dir /b /a:-d /od "%_Path_Image%\Windows\WinSxS\Manifests\%_Arch%_microsoft-windows-servicingstack_*"') do set ssuver=%%j

if %HostBuild% equ 9600 if %ssuver% gtr 17031 (
    set Flag_Import=1
    echo Microsoft-Windows-BusinessScanning-Feature-Package > %ImportList%
    echo Microsoft-Windows-Printer-Drivers-Package >> %ImportList%
    call :MergeList %CurBuild%\ImportList.txt %txt1% %ImportList%
    call :RegLoad SOFTWARE
    call :Removemum "Microsoft-Windows-BusinessScanning-Feature-Package"
    call :Removemum "Microsoft-Windows-Printer-Drivers-Package"
    reg unload HKLM\%TMP_SOFTWARE% %nul%
)

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
:: NET assembly 缓存
dir /b /ad "%_Path_Image%\Windows\assembly"|findstr /i "NativeImages_">>multilangFolder.txt
:: SystemApps
for /f "tokens=*" %%i in ('type "Custom\SystemApps.txt"') do (
    for /f "tokens=* delims=" %%j in ('dir /b /ad "%_Path_Image%\Windows\SystemApps" %nul6% ^|findstr /i "%%i"') do (
        echo %%j>>multilangFolder.txt
    )
)

:: 生成相关 文件夹 列表
%offlinereg% "%_Path_Image%\Windows\System32\config\COMPONENTS" "DerivedData\Components" enumkeys | findstr /i /v /C:"-keyboard-" > DelWinSxSFolders.txt
copy /y DelWinSxSFolders.txt DelVerWinSxSFolders.txt
copy /y DelWinSxSFolders.txt DelUltWinSxS.txt

:: 极致精简列表
if /i [%Flag_UltraLite%] == [1] (
    dir /b /a-d "%_Path_Image%\Windows\WinSxS\Manifests" | findstr /i /v /C:"-keyboard-" >DelUltManifests.txt
    dir /b /a-d "%_Path_Image%\Windows\WinSxS\Manifests\*resources*_???*-*??_*" | findstr /i /v "en-US %MUI%">DelUltManifestsLang.txt
    dir /b /a-d "%_Path_Image%\Windows\WinSxS\Manifests\*-keyboard-*" | findstr /v "%base_keyboard% %cur_keyboard%" >>DelUltManifestsLang.txt
)

:: 删除 相关 文件/文件夹
%NSudo% cmd /c rd /s /q "%_Path_Image%\Windows\WinSxS\Backup"
%NSudo% cmd /c del /f /q "%_Path_Image%\Windows\WinSxS\Catalogs\*.*"
%NSudo% cmd /c del /f /q "%_Path_Image%\Windows\WinSxS\FileMaps\*.*"
%NSudo% cmd /c del /f /q "%_Path_Image%\Windows\WinSxS\pending.xml"
%NSudo% cmd /c del /f /q "%_Path_Image%\Windows\WinSxS\ManifestCache\*blobs.bin"

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
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\SxSVerCleanup.ps1" "DelUltWinSxS.txt"
    %grep% -v -Ff "Custom\FolderRetainList.txt" DelUltWinSxS.txt >> _DelUltWinSxS.txt
    move /y _DelUltWinSxS.txt DelUltWinSxS.txt %nul1%
    Powershell -noprofile -executionpolicy bypass -file "%Path_Helper%\SxSVerCleanup.ps1" "DelUltManifests.txt"
    %grep% -v -Ff "Custom\FolderRetainList.txt" DelUltManifests.txt >> _DelUltManifests.txt
    move /y _DelUltManifests.txt DelUltManifests.txt %nul1%
    type DelUltManifestsLang.txt>>DelUltManifests.txt
    call :xfindstr DelUltManifests.txt ImageList.txt
    set Flag_Empty=0
    set Flag_ComCleanup=0
)

:: 2.匹配 映像文件夹/文件 路径

:: 合并多语言文件、文件夹
:: 处理开始菜单中的 入门 和 Windows备份 文件
%wimlib% dir "%ImageFile%" %ImageIndex% --path=Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy | findstr /i "appxmanifestbak.xml" && (
    call :grep "WebExperienceHost.dll" ImageList.txt multilang.txt
    call :grep "WebExperienceHostApp.exe" ImageList.txt multilang.txt
    call :grep "WindowsBackup.dll" ImageList.txt multilang.txt
    call :grep "WindowsBackupClient.exe" ImageList.txt multilang.txt
    call :grep "WindowsBackup$" ImageFolderList.txt multilangFolder.txt   
)
%grep% -iFf multilang.txt ImageList.txt | findstr /i /v "winsxs" >> _multilang.txt
move _multilang.txt multilang.txt %nul1%
call :xfindstr multilangFolder.txt ImageFolderList.txt
type multilangFolder.txt >> multilang.txt
del /f /q multilangFolder.txt %nul2%
call :sort multilang.txt
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
    if /i [%Flag_SuperLite%] == [0] del /f /q DelWinSxSFolders.txt %nul2%
)
if exist DelVerWinSxSFolders.txt (
    call :xfindstr DelVerWinSxSFolders.txt ImageFolderList.txt
    call :sort DelVerWinSxSFolders.txt
    if /i [%Flag_SxSVerCleanup%] == [0] del /f /q DelVerWinSxSFolders.txt %nul2%
)
if exist DelUltWinSxS.txt (
    call :xfindstr DelUltWinSxS.txt ImageFolderList.txt
    type DelUltManifests.txt>>DelUltWinSxS.txt
    call :sort DelUltWinSxS.txt
    del /f /q DelUltManifests.txt DelUltManifestsLang.txt %nul2%
    if /i [%Flag_UltraLite%] == [0] del /f /q DelUltWinSxS.txt %nul2%
)
:: 可能存在的空目录
if /i [%Flag_Empty%] == [1] (
    type WinSxSFiles.txt|findstr /i /v "winsxs">DelEmptyFolders.txt
    cscript //NoLogo %Path_Helper%\PathExtract.vbs DelEmptyFolders.txt _DelEmptyFolders.txt
    move _DelEmptyFolders.txt DelEmptyFolders.txt %nul1%
    call :sort DelEmptyFolders.txt
)

:: 生成 wimlib 统一规范
set wimupdate="delete --force --recursive"

call :LogInfo 开始执行文件删除操作. . .
:: 开始删除

if exist WinSxSFiles.txt (
    call :LogInfo 删除WinSxS文件. . .
    call :NormList WinSxSFiles.txt %wimupdate%
    %wimlib% update "%ImageFile%" %ImageIndex% < WinSxSFiles.txt
)

if exist multilang.txt (
    call :LogInfo 删除多语言文件. . .
    call :NormList multilang.txt %wimupdate%
    %wimlib% update "%ImageFile%" %ImageIndex% < multilang.txt
)

if exist DelFiles.txt (
    call :LogInfo 删除其他文件. . .
    call :NormList DelFiles.txt %wimupdate%
    %wimlib% update "%ImageFile%" %ImageIndex% < DelFiles.txt
)

if exist DelWinSxSFolders.txt (
    call :LogInfo 删除WinSxS文件夹. . .
    call :NormList DelWinSxSFolders.txt %wimupdate%
    %wimlib% update "%ImageFile%" %ImageIndex% < DelWinSxSFolders.txt
)

:: 低版本组件文件夹清理
if exist DelVerWinSxSFolders.txt (
    call :LogInfo 删除低版本WinSxS文件夹. . .
    call :NormList DelVerWinSxSFolders.txt %wimupdate%
    %wimlib% update "%ImageFile%" %ImageIndex% < DelVerWinSxSFolders.txt
)

:: 极致 WinSxS 清理
if exist DelUltWinSxS.txt (
    call :LogInfo 删除更多WinSxS文件夹，功能不可正常打开或关闭. . .
    call :NormList DelUltWinSxS.txt %wimupdate%
    %wimlib% update "%ImageFile%" %ImageIndex% < DelUltWinSxS.txt
)

:: 删除空目录
if /i [%Flag_Empty%] == [1] (
    call :LogInfo 开始删除空目录. . .
    del /f /q _DelEmptyFolders.txt %nul2%
    if not exist "%_Path_Image%\Windows" call :MountImage "%ImageFile%", %ImageIndex%, "%_Path_Image%"
    for /f "delims=" %%j in (DelEmptyFolders.txt) do (
        rd "%_Path_Image%%%j"
        %NSudo% cmd /c rd "%_Path_Image%%%j"
        if not exist "%_Path_Image%%%j" echo "%%j">>_DelEmptyFolders.txt
    )
    move _DelEmptyFolders.txt DelEmptyFolders.txt %nul1% 
    call :sort DelEmptyFolders.txt
    call :LogInfo 空目录删除完成
)

:: dism 组件存储清理，进一步减少 WinSxS 文件夹占用
if /i [%Flag_ComCleanup%] == [1] if %HostBuild% geq 9600 (
    call :LogInfo 组件存储清理. . .
    if not exist "%_Path_Image%\Windows" call :MountImage "%ImageFile%", %ImageIndex%, "%_Path_Image%"
    echo dism /Image:"%_Path_Image%" /Cleanup-Image /AnalyzeComponentStore
    dism /English /Image:"%_Path_Image%" /Cleanup-Image /AnalyzeComponentStore | find /i "Yes" && dism /Image:"%_Path_Image%" /Cleanup-Image /StartComponentCleanup
)

:SkipClean
:: 如果存在挂载映像，卸载并保存映像
if exist "%_Path_Image%\Windows" call :UnMountImage "%_Path_Image%", "Commit"

REM del /f /q ImageList.txt ImageFolderList.txt %nul2%
del /f /q WinSxSFilesList.txt WinSxSFoldersList.txt WinSxSExclude.txt MiniList.txt %nul2%
del /f /q %ImportList% %RetainList% %nul2%
if /i [%Flag_Empty%] == [0] del /f /q DelEmptyFolders.txt %nul2%

for /f "tokens=*" %%i in ('dir /b /ad /s "%~dp0Mount*"') do %NSudo% cmd /c rd /s /q "%%i"
if exist "%_Path_Image%\Windows" call :UnMountImage "%_Path_Image%", "Discard"

pushd ..
if exist "Setup\OriginSetup.cmd" (
    call :LogInfo 添加 无人值守 unattend.xml . . .
    %wimlib% update %ImageFile% %ImageIndex% --command="add 'Setup\Scripts\XML\unattend.xml' '\Windows\Panther\unattend.xml'"
    call :LogInfo 添加 无人值守 OriginSetup 简化部署脚本 . . .
    %wimlib% update %ImageFile% %ImageIndex% --command="add 'Setup' '\Windows\Setup'"
)

:: 优化映像文件
call :LogInfo 开始优化映像文件. . .
if not exist %wimlib% set Flag_optimize=1
ver | find "6.1" && set Flag_optimize=2
call :OptimizeImage%Flag_optimize%
if !errorlevel! neq 0 (
    call :LogError 映像优化失败，错误代码: !errorlevel!
) else (
    call :LogInfo 映像优化完成
)

call :LogInfo 离线清理完成
:exit
call :LogInfo 脚本执行完成
exit

:MatchList1
type %txt1%.txt > %txt2%.txt
%grep% -iFf %txt2%.txt ImageList.txt | findstr /i /v "Manifests">> _%txt2%.txt
move _%txt2%.txt %txt2%.txt %nul1%
del /f /q WinSxSFiles.txt %nul2%
for /f "delims=" %%i in (%txt2%.txt) do call :fsutil "%%i"
call :vfindstr "Custom\FileRetainList.txt" WinSxSFiles.txt
:: 去除列表中的路径
set "FilePath=%_Path_Image:*:=%"
powershell -Command "$content = [System.IO.File]::ReadAllText('WinSxSFiles.txt', [System.Text.Encoding]::Default); $newContent = $content.Replace('%FilePath%', ''); [System.IO.File]::WriteAllText('WinSxSFiles.txt', $newContent, [System.Text.Encoding]::Default)"
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
if exist "%_Path_Image%%~1" fsutil hardlink list "%_Path_Image%%~1" |findstr /i /v "WinSxS">>WinSxSFiles.txt
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

:RegLoad
set "TMP_%~1={bf1a281b-ad7b-4476-ac95-f47682990ce7}%_Path_Image%\Windows\System32\config\%~1"
set "TMP_%~1=!TMP_%~1:\=/!"
reg load HKLM\!TMP_%~1! "%_Path_Image%\Windows\System32\config\%~1" %nul%
exit /b

:: 统一版本
:fixBuild
if %~1 geq 18362 if %~1 lss 19041 set %~2=%ShortBuild%.1836X
if %~1 geq 19041 if %~1 lss 22000 set %~2=%ShortBuild%.1904X
if %~1 geq 22621 if %~1 lss 26100 set %~2=%ShortBuild%.226X1
if %~1 geq 26100 if %~1 lss 28000 set %~2=%ShortBuild%.26X00
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

:: 挂载映像
:: 输入参数 [ %~1 ：映像文件名称、%~2 ：映像索引编号、%~3 ：映像安装文件夹 ]
:MountImage
echo dism /Mount-Wim /WimFile:%~1 /Index:%~2 /MountDir:%~3
dism /Mount-Wim /WimFile:%~1 /Index:%~2 /MountDir:%~3
goto :EOF

:: 卸载映像
:: 输入参数 [ %~1 ：映像安装文件夹、%~2 ：映像提交 Commit / 丢弃选项 Discard ]
:UnMountImage
echo dism /Unmount-Wim /MountDir:"%~1" /%~2
dism /Unmount-Wim /MountDir:"%~1" /%~2
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
echo WinSXS离线清理脚本日志 - 开始时间: %date% %time% >> "%LOG_FILE%"
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
:RemoveAppx1
for /f "tokens=2 delims=: " %%f in ('%Dism% /English /Image:"%_Path_Image%" /Get-ProvisionedAppxPackages ^| findstr PackageName ^| findstr /i "%~1"') do (
    call :LogInfo 移除预装应用 [%~1]
    %Dism% /Image:"%_Path_Image%" /Remove-ProvisionedAppxPackage /PackageName:"%%f"
)
for /f "tokens=*" %%f in ('dir /b /ad "%_Path_Image%\Program Files\WindowsApps\*%~1*" %nul6%') do (
    %Dism% /Image:"%_Path_Image%" /Remove-ProvisionedAppxPackage /PackageName:"%%f"
    call :RegLoad SOFTWARE
    reg query "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications" | find "%%f" %nul% && (
        %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications\%%f" /f
        %NSudo% cmd /c rd /s /q "%_Path_Image%\Program Files\WindowsApps\%%f"
    )
    %NSudo% cmd /c rd /s /q "%_Path_Image%\Program Files\WindowsApps\*%~1*"
    reg unload HKLM\%TMP_SOFTWARE% %nul%
)
goto :EOF

:RemoveAppx2
call :RemoveAppx1 %~1
goto :EOF

:RemoveAppx3
for /f "tokens=*" %%f in ('dir /b /ad "%_Path_Image%\Program Files\WindowsApps\*%~1*" %nul6%') do (
    call :LogInfo 快速移除预装应用 [%%f]
    reg query "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications" | find "%%f" %nul% && (
        %NSudo% reg delete "HKLM\%TMP_SOFTWARE%\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications\%%f" /f
        %NSudo% cmd /c rd /s /q "%_Path_Image%\Program Files\WindowsApps\%%f"
    )
    %NSudo% cmd /c rd /s /q "%_Path_Image%\Program Files\WindowsApps\%%f"
    %NSudo% cmd /c del /f /q "%_Path_Image%\ProgramData\Microsoft\Windows\ClipSVC\Install\Apps\*%~1*.xml
)
goto :EOF

:: 移除可选功能 [ %~1 : 功能名称 ]
:RemoveFunction1
for /f "tokens=*" %%f in ('dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1~*.mum" %nul6% ^|find "%_Arch%" ^|find /v "%MUI%"') do ( 
    call :LogInfo 移除可选功能 [%%~nf]
    %Dism% /Image:"%_Path_Image%" /Remove-Package /PackageName:"%%~nf" && goto :EOF
)
goto :EOF

:RemoveFunction2
for /f "tokens=*" %%f in ('dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1*.mum" %nul6% ^|find "%_Arch%" ^|find /v "%MUI%"') do ( 
    call :LogInfo 移除可选功能 [%%~nf]
    %Tweak% /n /p "%_Path_Image%" /r /c "%%~nf"
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
)
goto :EOF

:Removemum
for /f "tokens=*" %%l in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1*.mum" %nul6%') do (
    %NSudo% reg delete "%RegCBS%\Packages\%%~nl" /f
    %NSudo% reg delete "%RegCBS%\PackagesPending\%%~nl" /f
    if NOT [%~2] == [] call :LogInfo 快速移除%~2 [%%~nl]
    %NSudo% cmd /c del /f /q "%_Path_Image%\Windows\%PathRel_Packages%\%%~nl.*"
)
goto :EOF

:: 显示隐藏组件 [ %~1 : 组件名称 ]
:ShowComponent
for /f "tokens=*" %%l in ('dir /b /a-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1*.mum" %nul6% ^| findstr /i "%_Arch%" ^| findstr /i /v "%MUI% en-US"') do (
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
for /f "tokens=3 delims=: " %%f in ('%Dism% /English /Image:"%_Path_Image%" /Get-Packages ^| findstr /i "%~1" ^| findstr /i "%_Arch%" ^| findstr /i /v "%MUI%" ') do (
    call :LogInfo 移除系统组件 [%%f]
    %Dism% /Image:"%_Path_Image%" /Remove-Package /PackageName:"%%f" /Quiet %nul%
)
goto :EOF

:RemoveComponent2
for /f "tokens=*" %%f in ('dir /b /o-d "%_Path_Image%\Windows\%PathRel_Packages%\%~1*.mum" %nul6% ^| findstr /i "%_Arch%" ^| findstr /i /v "%MUI% en-US"') do ( 
    call :LogInfo 移除系统组件 [%%~nf]
    %Tweak% /n /p "%_Path_Image%" /r /c "%%~nf"
)
goto :EOF

:RemoveComponent3
call :Removemum %~1 "系统组件"
goto :EOF

:: 查找文件或文件夹
:grep
%grep% -iE "\\%~1" "%~2" %nul2% |findstr /i /v "winsxs" >> "%~3"
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