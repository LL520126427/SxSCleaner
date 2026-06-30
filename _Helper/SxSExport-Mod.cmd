REM
REM Autor: KNARZ
REM Purpose: Export Windows Packages (the easy way)
REM          The script is intended to work with default system UI language.
REM Credits and best whishes to Melinda / Aunty Mel.
REM Also some credit to Alex Ionescu
REM
REM V.1
REM

@echo off & cls
setlocal EnableDelayedExpansion

pushd %~dp0
call definitions-Mod.cmd

:: 选择目标位置
:InImageSource
if "%_Path_Image%" equ "" exit

if /i [%_Path_Image%] == [%HOMEDRIVE%] (
	set Flag_Online=1
	set Online=/Online
	set SOFTWARE=SOFTWARE
	for /f "tokens=6" %%m in ('dism /English /Online /Get-Intl ^| find /i "Default system UI language"') do set "MUI=%%m"
	for /f "tokens=4-6 delims=[]. " %%s in ('ver') do set CurBuild=%%s.%%t.%%u
	set "Arch=x86"
	if exist "%WinDir%\SysWOW64" set "Arch=x64"
) else (
	set Flag_Online=0
	set Online=/Image:"%_Path_Image%"
	set SOFTWARE=TMP_SOFTWARE
	for /f "tokens=*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\WIMMount\Mounted Images"') do (
		for /f "tokens=*" %%b in ('reg query "%%a"^|findstr /i "%_Path_Image%"') do set MountPath=%%a
	)
	for /f "tokens=4*" %%i in ('reg query "!MountPath!" /v "WIM Path"') do set wimpath=%%i
	for /f "tokens=4*" %%i in ('reg query "!MountPath!" /v "Image Index"') do set /a ImageIndex= %%i
	for /f "tokens=1 delims=	 " %%m in ('dism /English /Get-ImageInfo /ImageFile:"!wimpath!" /Index:!ImageIndex! ^| find /i "Default"') do set MUI=%%m
	for /f "tokens=3 delims= " %%v in ('dism /English /Get-ImageInfo /ImageFile:"!wimpath!" /Index:!ImageIndex! ^| findstr /i /c:"Version :"') do set CurBuild=%%v
	for /f "tokens=2 delims=: " %%c in ('dism /English /Get-ImageInfo /ImageFile:"!wimpath!" /Index:!ImageIndex! ^| findstr /i /c:"Architecture"') do set Arch=%%c
	dism /Get-MountedImageInfo | findstr /i "%_Path_Image%" || exit
)

set RegCBS=HKLM\%SOFTWARE%\Microsoft\Windows\CurrentVersion\Component Based Servicing
set "_Null=1>nul 2>nul"

echo.
echo 位置: %_Path_Image% 版本: %CurBuild% 语言: %MUI% 类型: %Arch%

rem if /i [%_Path_Image%] == [%HOMEDRIVE%\] if /i [%Flag_Plus%] == [1] pause
set "Path_Image=%_Path_Image%\Windows"

:: 工作流程
if /i [%Flag_Plus%] == [1] (
	if /i %Flag_Retain%==1 (
		del /f /q "..\WinSxSList\%txt3%.txt" 2>nul
		call :AutoExportCheck %RetainList% "%txt3%"
	)
	if /i %Flag_Import%==1 (
		del /f /q "..\WinSxSList\%txt1%.txt" 2>nul
		del /f /q "..\WinSxSList\%txt2%.txt" 2>nul
		call :AutoExportCheck %ImportList% "%txt1%" "%txt2%"
	)
	exit /b
)
call :AutoExportCheck %ImportList%
call :AskImagePath Path_Image
call :PackagesEnum "BaseMUM"

:Loop
call :SelectItem		"BaseMUM"
call :PackageExport		"%BaseMUM%"
if /i [%Flag_NoAutoMUI%] == [1] (
if NOT defined FirstRun	(call :PackagesEnum	MuiMUM "%MUI%")
	call :SelectItem	"MuiMUM"
	call :PackageExport	"!MuiMUM!"
) else (
	call :ShortBasicName	BaseMUM
	call :PackageAutoSearch	"!BaseMUM!" "~%MUI%~"
)
set FirstRun=1
call :VarClear BaseMUM
call :VarClear MuiMUM

if defined Loop goto :Loop
call :TextIntro "全部完成..."

popd
endlocal
exit

::------------------------------------------------------------------------------
::预先定义
::------------------------------------------------------------------------------
:AskImagePath
if NOT defined Path_Image if /i [%Flag_AskImage%] == [1] (
	call :TextIntro	"请键入要使用的Windows映像路径，例如："
	call :TextInfo	"'D:\Mount\Enterprise'"
	call :TextInfo	"C: &echo."
	call :TextInfo	"如果要从装载的映像导出匹配的语言包"
	call :TextOutro	"比如：'D:\Mount\Enterprise en-US'
	call :InImageSource	"%~1"
)
if NOT [%~2] == []	(set "MUI=%~2")
if NOT exist "%Path_Image%" (call :ThrowMessage "NotFound" "%Path_Image%")
goto :EOF

:AutoExportCheck
if exist "%~1" (
	call :TextIntro	"自动导出模式..."
	call :TextOutro	"仅找到并导出显示的包。"
	for /f %%i in (%~1) do (
		call :PackageAutoSearch "%%i" "~~" "%~2" "%~3"
		call :PackageAutoSearch "%%i" "~%MUI%~" "%~2" "%~3"
	)
	call :ThrowMessage "完成"
)
goto :EOF

:PackageAutoSearch
for /f "tokens=*" %%l in ('dir /b /o-d "%Path_Image%\%PathRel_Packages%\%~1~*%~2*.mum" 2^>nul ^|findstr /v "16385"') do (
	REM 没有“for”项目会立即停止。
	if ErrorLevel 1 (goto :EOF)
	call :PackageExport "%%~nl" "%~3" "%~4"
)
goto :EOF

:PackageExport
for /f "tokens=1,3,4,5 delims=~" %%i in ("%~1") do (
	if [%%l] == [] (
	set Folder_PathExport=%%j\%%k
	set File_ExportName=%%i-%%j-%%k
	set "PackageName=%%i"
	) else (
	set Folder_PathExport=%%j\%%l\%%k
	set File_ExportName=%%i-%%j-%%l-%%k
	set "PackageName=%%i (%%k)"
	)
	echo 组件：!PackageName!
)

if /i [%Flag_CAB%] == [1] (
	if not exist "%Path_Export%\%Folder_PathExport%" md "%Path_Export%\%Folder_PathExport%"
	set "Path_ExportFile=%Path_Export%\%Folder_PathExport%\%File_ExportName%.cab"
	) else (set "Path_ExportFile=%Path_Export%\%Folder_PathExport%\%File_ExportName%")
if /i [%Flag_Log%] == [1] (
	if not exist "%Path_Export%\%Folder_PathExport%" md "%Path_Export%\%Folder_PathExport%"
	set "LogFile=%Path_Export%\%Folder_PathExport%\%File_ExportName%.log"
	) else (set "LogFile=nul")
if [%~2] neq [] set "ExportFolder=%~2.txt"
if [%~3] neq [] set "ExportFile=%~3.txt"
%Tool_SxSExtract% /IMAGE:"%Path_Image%" %Parameter_SxSExtract% "%Path_Image%\%PathRel_Packages%\%~1.mum" "%Path_ExportFile%" "%ExportFolder%" "%ExportFile%"> %LogFile%
timeout.exe /t 2 > nul
if exist "%File_ExportName%" (
	ren "%File_ExportName%" "del0"
	%NSudo% cmd /c rd /s /q "del0" 2>nul
)
set "ExportFolder=%~2"
set "ExportFile=%~3"
goto :EOF

:PackagesEnum
set Tip=
set Search=
if /i [%~1] == [BaseMUM] (
	set "Tip=Base-Package/s"
	set "Search=dir /b /o-d "%Path_Image%\%PathRel_Packages%\*~*~~*.mum^""
	set "File_PackageList=%Path_Root%\_Packagelist_Base.txt"
	call :TextIntro	"生成基本包列表..."
)
if /i [%~1] == [MuiMUM] (
	set "Tip=MUI-Package/s"
	set "Search=dir /b /o-d "%Path_Image%\%PathRel_Packages%\*~%MUI%~*.mum^""
	set "File_PackageList=%Path_Root%\Packagelist_%MUI%.txt"
	call :TextIntro	" 正在生成（%MUI%）包列表..."
)
call :Selection	"%~1" "!Search!"
call :TextInfo	"请看："
call :TextInfo	"'%File_PackageList%'"
call :TextOutro	"然后输入要导出组件的数字。"
goto :EOF

:Selection
type nul > %File_PackageList%
set /a CNT=0
for /f "tokens=*" %%f in ('%~2 ^| findstr.exe /i /v "_for_KB 16385" ^| sort') do (
	set /a CNT+=1
	set "%~1!CNT!=%%~nf"
		for /f "tokens=1 delims=~" %%i in ("%%~f") do (
		REM echo 	!CNT!^) %%~i
		echo !CNT!;	%%~i>> %File_PackageList%
	)
)
echo.
goto :EOF

:SelectImageSource
set /p Imagepath=^>
if /i [%Imagepath%] == []		(call :ThrowMessage "Invalid")
set "%~1=%Imagepath%\Windows"
goto :EOF

:SelectItem
set /p SelNum=^>
if /i [%SelNum%] == []		(call :ThrowMessage "Invalid")
if /i [%SelNum%] == [X]		(call :ThrowMessage "Abort")
if %SelNum% LEQ 0			(call :ThrowMessage "Range")
if %SelNum% GTR %CNT%		(call :ThrowMessage "Range")
set "%~1=!%~1%SelNum%!"
set "SKIP="
REM timeout.exe /t 2 >nul
goto :EOF

:ShortBasicName
for /f "tokens=1 delims=~" %%i in ("!%~1!") do (set "%~1=%%i")
goto :EOF

:VarClear
set "%~1="
goto :EOF

:TextIntro
echo.
echo       %~1
echo %Line%
goto :EOF

:TextOutro
echo       %~1
echo %Line%
echo.
goto :EOF

:TextInfo
echo       %~1
goto :EOF

:ThrowMessage
echo.
if /i [%~1] == [Done] (
	echo 所有操作均已完成。
)
if /i [%~1] == [NotFound] (
	echo %~2 未找到。
)
if /i [%~1] == [Invalid] (
	echo 输入无效。
)
if /i [%~1] == [Abort] (
	echo 用户中止进程。
)
if /i [%~1] == [Range] (
	echo 所选数字超出范围。
)
echo.
if /i [%Flag_Plus%] == [1] goto :EOF
echo 按任意键终止窗口...
pause >nul
exit