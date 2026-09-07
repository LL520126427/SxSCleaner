rem 设置当前工作目录
set WD=%~dp0
call :EnumRootPath "Path_Root" "SxSExportConfig.ini"

set Path_Helper=%WD:~0,-1%
set Path_Export=%Path_Root%\Output
set PathRel_Packages=Servicing\Packages
set Tool_SxSExpand=%Path_Helper%\SxSExpand.exe
set Tool_SxSExtract="%SystemRoot%\System32\cscript.exe" //NoLogo "%Path_Helper%\SxSExtract-Mod.vbs"
set Tool_TIWorker=%Path_Helper%\nsudoc.exe
REM set Tool_CabDir=%Path_Helper%\cabdir.exe
set Tool_CabArc=%Path_Helper%\cabarc.exe
set sort=%Path_Helper%\sort.exe
set Script_Export=%Path_Helper%\export.cmd
set Parameter_SxSExtract=/VICIOUSHACKS
set ImportList=%Path_Root%\ImportList.txt
set RetainList=%Path_Root%\RetainList.txt
set ExtraList=%Path_Root%\ExtraList.txt
set AppxList=%Path_Root%\AppxList.txt
set FunctionList=%Path_Root%\FunctionList.txt
set Line=------------------------------------------------------------------------------

REM set MUI=en-US
REM call :EnumPrefLanguage MUI
exit /b

::------------------------------------------------------------------------------
::Subroutine
::------------------------------------------------------------------------------
:EnumPrefLanguage
REM for /f "tokens=6" %%m in ('dism.exe /English /Online /Get-Intl ^| find.exe /i "Default system UI language"') do ( set "%~1=%%m" )
REM echo Language: !%~1!
goto :EOF

:EnumRootPath
for /f %%i in ('dir /b /s "%WD%..\%~2"') do ( 
set "%~1=%%~dpi" 
set %~1=!%~1:~0,-1!
)
goto :EOF