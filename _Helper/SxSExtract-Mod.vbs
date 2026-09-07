Option Explicit

Const Banner1 = _
"梅琳达 简易和方便的组件提取工具，2013年11月9日"
Const Banner2 = _
"版权所有（C）2012-2013 梅琳达·贝勒莫尔。保留所有权利。"

Const Line79 =_
"-------------------------------------------------------------------------------"
Const Space79 =_
"                                                                               "

Const IdentityPath = "//assembly/assemblyIdentity"
Const DependencyPath = "//assembly/dependency/dependentAssembly/assemblyIdentity"
Const PackagePath = "//assembly/package/update/package/assemblyIdentity"
Const ComponentPath = "//assembly/package/update/component/assemblyIdentity"
Const DriverPath = "//assembly/package/update/driver/assemblyIdentity"

Const ForReading = 1
Const ForWriting = 2
Const ForAppending = 8

Const FileFlagNone = 0
Const FileFlagError = 1
Const FileFlagCompressed = 2

Const MAX_PATH = 260

Dim Shell
Dim FSO

Dim TempFolder
Dim DebugMode
Dim SystemRoot
Dim IncludeRes
Dim ViciousHacks

Dim SxSExpandAvailable
Dim CABArcAvailable

Dim MakingCAB
Dim InputPath
Dim OutputPath

' 组件生成文件列表的参数
Dim InFoldersListName
Dim InFilesListName
Dim MakingFoldersList
Dim MakingFilesList

Dim SwitchLoop
Dim ParamIndex

Dim CopyList

' 简单日志功能。
Sub LogBare(AText)
	WScript.Echo AText
End Sub

Sub LogInfo(AText)
	Call LogBare("[信息] " & AText)
End Sub

Sub LogError(AText)
	Call LogBare("[   错误   ] " & AText)
End Sub

Sub LogFatal(AText)
	Call LogBare("[严重错误] " & AText)	
End Sub

Sub LogDebug(AText)
	If DebugMode Then
		Call LogBare("[   调试   ] " & AText)
	End If
End Sub

' 将文件或文件夹添加到副本列表中，并进行错误检查，以解决VBScript不能多次添加同一“密钥”的问题
Sub CopyListAdd(ASource, ATarget)
	If CopyList Is NOTHING Then
		Exit Sub
	End If

	If CopyList.Exists(ASource) Then
		Call LogDebug("复制列表已存在的密钥：" & ASource)
	Else
		CopyList.Add ASource, ATarget
	End If
End Sub

' 检查文件是否使用Microsoft新的SxS压缩方案压缩。
Function IsCompressed(AFileName)
	Dim File
	Dim Signature

	Set File = FSO.OpenTextFile(AFileName, ForReading)
	Signature = File.Read(4)
	File.Close
	Set File = NOTHING

	' 我已见过这些签名，不知道还有没有？
	If Signature = "DCM" & Chr(1) Then
		IsCompressed = TRUE
	ElseIf Signature = "DCN" & Chr(1) Then
		IsCompressed = TRUE
	ElseIf Signature = "DCS" & Chr(1) Then
		IsCompressed = TRUE
	ElseIf Signature = "PA30" Then
		IsCompressed = TRUE
	Else
		IsCompressed = FALSE
	End If
End Function

' 调用我的工具来扩展由Microsoft新的SxS压缩方案压缩的文件。
Function SxSExpand(AFileName)
	Dim TheCommand
	Dim WinStyle
	Dim ReturnCode

	Dim TempFileName

	SxSExpand = EMPTY

	' 如果SxS Expand不可用，则退出。
	If Not SxSExpandAvailable Then
		Exit Function
	End If

	' 创建一个临时文件，方便导出。
	Do
		TempFileName = FSO.BuildPath(TempFolder, FSO.GetTempName)
	Loop Until _
		(Not FSO.FileExists(TempFileName))

	If DebugMode Then
		WinStyle = 1
		TheCommand = "SXSEXPAND.EXE /DEBUG """ & AFileName & """ """ & _
			TempFileName & """"
	Else
		WinStyle = 0
		TheCommand = "SXSEXPAND.EXE """ & AFileName & """ """ & _
			TempFileName & """"
	End If
	Call LogDebug("执行： " & TheCommand)

	ReturnCode = Shell.Run(TheCommand, WinStyle, TRUE)
	If ReturnCode = 0 Then
		SxSExpand = TempFileName
	Else
		Call LogError("SxSExpand 调用失败-错误代码： " & _
			CStr(ReturnCode))
	End If
End Function

' 检查外部工具是否可用。
Sub CheckExternals
	Dim ReturnCode

	Call LogDebug("正在检查外部工具-SXSEXPAND.EXE和CABARC.EXE。")

	' 使用返回代码来确认。
	ReturnCode = -1.17
	On Error Resume Next
	ReturnCode = Shell.Run("SXSEXPAND.EXE", 0, TRUE)
	On Error Goto 0
	If ReturnCode = -1.17 Then
		SxSExpandAvailable = FALSE
	Else
		SxSExpandAvailable = TRUE
	End If
	ReturnCode = -3.14
	On Error Resume Next
	ReturnCode = Shell.Run("CABARC.EXE", 0, TRUE)
	On Error Goto 0
	If ReturnCode = -3.14 Then
		CABArcAvailable = FALSE
	Else
		CABArcAvailable = TRUE
	End If
End Sub

' 使用SUBST.EXE缩短路径。VBScript对路径长度有严格限制（260个字符）。
Function Subst(APath)
	Dim TheCommand
	Dim WinStyle
	Dim ReturnCode

	Dim FoundDrive
	Dim Drive

	Subst = EMPTY

	' 查找未使用的驱动器。
	Drive = "A"
	Do While ((FSO.DriveExists(Drive)) And (Asc(Drive) < (Asc("Z") + 1)))
		Drive = Chr(Asc(Drive) + 1)
	Loop

	' 可能正在使用所有驱动器。
	If Asc(Drive) = (Asc("Z") + 1) Then
		Call LogError("找不到未使用的驱动器号-将执行 " & _
			"使用完整路径复制文件。")
		Subst = APath
		Exit Function
	End If

	' 调用SUBST。
	If DebugMode Then
		WinStyle = 1
	Else
		WinStyle = 0
	End If
	TheCommand = "SUBST.EXE " & Drive & ": """ & APath & """"

	Call LogDebug("执行： " & TheCommand)
	ReturnCode = Shell.Run(TheCommand, WinStyle, TRUE)
	If ReturnCode = 0 Then
		Subst = Drive & ":\"
		Call LogInfo("调用SUBST：" & APath & " 关联 " & _
			Subst & "。")
	Else
		Call LogError("SUBST失败-将使用full命令执行文件复制 " & _
			"路径。错误代码：" & CStr(ReturnCode))
		Subst = APath
	End If
End Function

Sub UnSubst(APath)
	Dim TheCommand
	Dim WinStyle
	Dim ReturnCode

	If DebugMode Then
		WinStyle = 1
	Else
		WinStyle = 0
	End If
	TheCommand = "SUBST.EXE " & Left(APath, 2) & " /D"

	Call LogDebug("执行：" & TheCommand)
	ReturnCode = Shell.Run(TheCommand, WinStyle, TRUE)
	If ReturnCode = 0 Then
		Call LogInfo("调用 SUBST /D：" & APath & " 解除关联。")
	Else
		Call LogError("SUBST /D 调用失败-错误代码：" & CStr(ReturnCode))
	End If
End Sub

Function CreatePackageID(APackageName, APublicKeyToken, AArch, ALang, _
	AVersion)
	CreatePackageID = APackageName
	CreatePackageID = CreatePackageID & "~"

	CreatePackageID = CreatePackageID & APublicKeyToken
	CreatePackageID = CreatePackageID & "~"

	CreatePackageID = CreatePackageID & AArch
	CreatePackageID = CreatePackageID & "~"

	If (Not (StrComp(ALang, "neutral", vbTextCompare) = 0)) And _
		(Not (StrComp(ALang, "none", vbTextCompare) = 0))Then
		CreatePackageID = CreatePackageID & ALang
	End If
	CreatePackageID = CreatePackageID & "~"

	CreatePackageID = CreatePackageID & AVersion
End Function

Function CreateAssemblyIDWildcard(APackageName, APublicKeyToken, AArch, _
	ALang, AVersion)
	Const HashWildcard = "????????????????"

	CreateAssemblyIDWildcard = AArch
	CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & "_"

	If Len(APackageName) > 40 Then
		CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & _
			Left(APackageName, 19) & ".." & Right(APackageName, 19)
	Else
		CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & APackageName
	End If
	CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & "_"

	CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & APublicKeyToken
	CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & "_"

	CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & AVersion
	CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & "_"

	If (ALang = "") Or (IsEmpty(ALang)) Or (StrComp(ALang, "neutral", _
		vbTextCompare) = 0) Then
		CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & "none"
	Else
		CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & ALang
	End If
	CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & "_"
	CreateAssemblyIDWildcard = CreateAssemblyIDWildcard & HashWildcard
End Function


Function MatchWildcard(AFileName)
	Dim ThePath
	Dim Pattern
	Dim TheCommand
	Dim WinStyle

	Dim TempFileName
	Dim ReturnCode
	Dim DIROutput

	Dim Matches()
	Dim MatchIndex

	Dim BackslashPosition

	MatchWildcard = EMPTY
	MatchIndex = 0

	' 没有通配符。快速退出。
	If (InStr(1, AFileName, "*", vbTextCompare) = 0) And _
		(InStr(1, AFileName, "?", vbTextCompare) = 0) Then
		Call LogDebug("使用非通配符模式调用匹配通配符： " & _
			AFileName)
		If (FSO.FileExists(AFileName)) Or (FSO.FolderExists(AFileName)) Then
			' 将返回值转换为数组。
			ReDim Matches(0)
			Matches(0) = AFileName
			MatchWildcard = Matches
		End If

		Exit Function
	End If

	' 除最后一个path外，任何内容都不能包含通配符。
	BackslashPosition = InStrRev(AFileName, "\", -1, vbTextCompare)
	If BackslashPosition = 0 Then
		' 若没有路径 使用当前文件夹。
		ThePath = FSO.GetFolder(".")
	Else
		If (Not (InStrRev(AFileName, "*", BackslashPosition, _
			vbTextCompare) = 0)) Or (Not (InStrRev(AFileName, "?", _
			BackslashPosition, vbTextCompare) = 0)) Then
			Call LogError("无效的通配符：" & AFileName)
			Exit Function
		End If
		ThePath = FSO.GetParentFolderName(AFileName)
	End If

	' 获取模式-如果没有，请使用 “*”。
	Pattern = Mid(AFileName, BackslashPosition + 1)
	If Pattern = "" Then
		Pattern = "*"
	End If

	' 解释：我开始编写自己的通配符匹配程序。尽管我非常懒惰，但在遇到麻烦的那一刻，我又开始使用DIR。在检查数千个文件方面也比解释语言快得多。
	Call LogDebug("匹配通配符：" & FSO.BuildPath(ThePath, Pattern))
	Do
		TempFileName = FSO.BuildPath(TempFolder, FSO.GetTempName)
	Loop Until _
		(Not FSO.FileExists(TempFileName))

	If DebugMode Then
		WinStyle = 1
	Else
		WinStyle = 0
	End If
	TheCommand = "CMD.EXE /C DIR /A /B """ & FSO.BuildPath(ThePath, _
		Pattern) & """ > """ & TempFileName & """"
	Call LogDebug("执行：" & TheCommand)
	ReturnCode = Shell.Run(TheCommand, WinStyle, TRUE)

	' 错误检查。
	If Not (FSO.FileExists(TempFileName)) Then
		Call LogError("无法读取文件夹内容：" & ThePath)
		Exit Function
	End If

	' 如果DIR输出不是零，开始解析！
	If Not (FSO.GetFile(TempFileName).Size = 0) Then
		Set DIROutput = FSO.OpenTextFile(TempFileName, ForReading)
		Do While (Not DIROutput.AtEndOfStream)
			ReDim Preserve Matches(MatchIndex)
			Matches(MatchIndex) = FSO.BuildPath(ThePath, DIROutput.ReadLine)
			Call LogDebug("通配符匹配：" & Matches(MatchIndex))
			MatchIndex = MatchIndex + 1
		Loop
		DIROutput.Close
		Set DIROutput = NOTHING
	End If

	' 删除临时文件。
	FSO.GetFile(TempFileName).Delete TRUE

	' 任何匹配项都将作为数组返回，即使只有一个匹配项，这使得主循环更容易进行。
	If Not (MatchIndex = 0) Then
		MatchWildcard = Matches
	End If
End Function

Function FindPossibleManifestFiles(APackageName, APublicKeyToken, AArch, _
	ALang, AVersion)
	Dim WorkPath
	Dim TempArray

	FindPossibleManifestFiles = EMPTY
	Call LogInfo("正在查找程序集引用的匹配清单： " & _
		APackageName & "," & APublicKeyToken & "," & AArch & "," & ALang & _
		"," & AVersion)

	' 首先尝试使用包文件夹。
	WorkPath = FSO.BuildPath(SystemRoot, "\Servicing\Packages")
	FindPossibleManifestFiles = FSO.BuildPath(WorkPath, _
		CreatePackageID(APackageName, APublicKeyToken, AArch, ALang, _
		AVersion) & ".mum")

	Call LogDebug("正在尝试使用文件名： " & FindPossibleManifestFiles)
	If FSO.FileExists(FindPossibleManifestFiles) Then
		' 将返回值转换为数组。
		ReDim TempArray(0)
		TempArray(0) = FindPossibleManifestFiles
		FindPossibleManifestFiles = TempArray
		Exit Function
	End If

	' 尝试SxS清单文件夹（由于这些散列，使用通配符）。
	WorkPath = FSO.BuildPath(SystemRoot, "\WinSxS\Manifests")
	FindPossibleManifestFiles = FSO.BuildPath(WorkPath, _
		CreateAssemblyIDWildcard(APackageName, APublicKeyToken, AArch, _
		ALang, AVersion) & ".manifest")

	Call LogDebug("正在尝试通配符匹配：" & FindPossibleManifestFiles)
	FindPossibleManifestFiles = MatchWildcard(FindPossibleManifestFiles)
End Function

Sub FindReferencedAssemblies(AXML, APath, AInFoldersListName)
	Dim ElementList
	Dim CurrentElement

	Dim ReferencedAssemblyName
	Dim ReferencedPublicKeyToken
	Dim ReferencedArch
	Dim ReferencedLang
	Dim ReferencedVersion

	Call LogDebug("正在检查程序集引用的XML路径：" & APath)

	Set ElementList = AXML.DocumentElement.SelectNodes(APath)
	For Each CurrentElement In ElementList
		ReferencedAssemblyName = CurrentElement.GetAttribute("name")
		ReferencedPublicKeyToken = CurrentElement.GetAttribute("publicKeyToken")
		ReferencedArch = CurrentElement.GetAttribute("processorArchitecture")
		ReferencedLang = CurrentElement.GetAttribute("language")
		ReferencedVersion = CurrentElement.GetAttribute("version")

		If (ReferencedLang = "*") And (Not IncludeRes) Then
			' 通过跳过此引用来处理 “/INCLUDERES” 开关。
			Call LogError("似乎是MUI引用-正在跳过：" & _
				ReferencedAssemblyName)
		Else
			Call RecurseManifestHierarchy(ReferencedAssemblyName, _
				ReferencedPublicKeyToken, ReferencedArch, ReferencedLang, _
				ReferencedVersion, AInFoldersListName)
		End If
	Next
End Sub

Sub ExtractPossibleAssemblyFolders(AWildcard)
	Dim Loop2

	Dim SourceList
	Dim TargetFolder
	
	SourceList = MatchWildcard(AWildcard)
	If Not IsEmpty(SourceList) Then
		For Loop2 = 0 To UBound(SourceList)
			' 仅复制文件夹（因此需要额外检查）。
			If FSO.FolderExists(SourceList(Loop2)) Then
				Call LogInfo("找到关联的程序集文件夹：" & _
					FSO.GetFileName(SourceList(Loop2)))
				TargetFolder = FSO.GetFileName(SourceList(Loop2))
				Call CopyListAdd(SourceList(Loop2), TargetFolder)
			End If
		Next
	End If
End Sub

Function RecurseManifestHierarchy(APackageName, APublicKeyToken, AArch, ALang, AVersion, AInFoldersListName)
	Dim Loop1

	Dim XML

	Dim FirstFile
	Dim FileList

	Dim ElementList
	Dim CurrentElement

	Dim AssemblyName
	Dim AssemblyPublicKeyToken
	Dim AssemblyArch
	Dim AssemblyLang
	Dim AssemblyVersion

	Dim SourceFile
	Dim TargetFile

	Dim SxSPath

	Dim CurrentManifest
	Dim FileFlag
	Dim ArraySize
	
	' 生成组件的winsxs文件夹列表
	Dim FoldersListPath
	Dim FoldersList
	Dim WinStyle
	Dim TheCommand
	' 当前脚本的上级目录 WinSxSList 生成 winsxs文件夹列表
	FoldersListPath = FSO.BuildPath(FSO.GetFolder(".."&"\WinSxSList").Path, AInFoldersListName)

	SxSPath = FSO.BuildPath(SystemRoot, "\WinSxS")
	RecurseManifestHierarchy = FALSE

	Set XML = CreateObject("MSXML2.DOMDocument")
	If Err.Number <> 0 Then
		Call LogFatal("无法初始化MSXML。错误代码：" & _
			CStr(Err.Number))
		WScript.Quit 1
	End If

	' 第一次调用时，大部分内容都是空的。只需使用 PackageName 参数作为文件名。
	If IsEmpty(APublicKeyToken) And IsEmpty(AArch) And IsEmpty(ALang) And _
		IsEmpty(AVersion) Then
		FirstFile = TRUE
		If FSO.FileExists(APackageName) Then
			ReDim FileList(0)
			FileList(0) = APackageName
		Else
			FileList = EMPTY
		End If
	Else
		' 生成清单文件名。
		FileList = FindPossibleManifestFiles(APackageName, APublicKeyToken, _
			AArch, ALang, AVersion)
		FirstFile = FALSE
	End If

	' 如果找不到就退出。
	If IsEmpty(FileList) Then
		Call LogError("找不到匹配的清单。")
		Exit Function
	End If

	For Loop1 = 0 To UBound(FileList)
		FileFlag = FileFlagNone
		CurrentManifest = FileList(Loop1)

		' 如果是压缩的，则解压缩到临时文件夹进行解析。
		If IsCompressed(CurrentManifest) Then
			If Not SxSExpandAvailable Then
				Call LogError("SxS文件扩展器不可用-无法 " & _
					"访问压缩文件。")
				FileFlag = FileFlag Or FileFlagError
			Else
				CurrentManifest = SxSExpand(CurrentManifest)
				If IsEmpty(CurrentManifest) Then
					Call LogError("无法解压缩清单。")
					FileFlag = FileFlag Or FileFlagError
				Else
					Call LogDebug("将清单解压缩为临时清单" & _
						"文件：" & CurrentManifest)
					FileFlag = FileFlag Or FileFlagCompressed
				End If
			End If
		End If

		If (FileFlag And FileFlagError) = 0 Then
			' 加载manifest，如果有错就退出。
			Call LogInfo("加载清单：" & FileList(Loop1))
			XML.Async = FALSE
			XML.Load CurrentManifest
			
			If Err.Number <> 0 Then
				Call LogError("无法加载清单。错误：=" & Err.Number)
				FileFlag = FileFlag Or FileFlagError
			End If
		End If

		If (FileFlag And FileFlagError) = 0 Then
			If XML.DocumentElement Is NOTHING Then
				Call LogError("无法加载清单-可能丢失或损坏。")
				FileFlag = FileFlag Or FileFlagError
			End If
		End If

		If (FileFlag And FileFlagError) = 0 Then
			' 获取所需的所有信息
			Set CurrentElement = XML.DocumentElement.SelectSingleNode(IdentityPath)
			AssemblyName = CurrentElement.GetAttribute("name")
			AssemblyPublicKeyToken = CurrentElement.GetAttribute("publicKeyToken")
			AssemblyArch = CurrentElement.GetAttribute("processorArchitecture")
			AssemblyLang = CurrentElement.GetAttribute("language")
			AssemblyVersion =  CurrentElement.GetAttribute("version")
			' 安全检查
			If Not FirstFile Then
				If (APackageName = AssemblyName) And _
					(APublicKeyToken = AssemblyPublicKeyToken) And _
					(AArch = AssemblyArch) And _
					(AVersion = AssemblyVersion) Then
					' 处理通配符语言引用。允许提取剪贴工具。
					If Not (ALang = "*") Then
						If Not (ALang = AssemblyLang) Then
							FileFlag = FileFlag Or FileFlagError
						End If
					End If
				Else
					FileFlag = FileFlag Or FileFlagError
				End If

				If (FileFlag And FileFlagError) = 0 Then
					Call LogDebug("清单与父程序集引用匹配。")
				Else
					Call LogError("似乎加载了错误的 " & _
						"清单-开始跳过。")
				End If
			End If
		End If

		If (FileFlag And FileFlagError) = 0 Then
			' 为用户提供一些信息以便于抓包。
			Call LogBare("")
			Call LogBare(AssemblyName)
			Call LogBare(Line79)
			Call LogBare(Left("版本：          " & AssemblyVersion & _
				Space79, 39) & "架构：     " & AssemblyArch)
			Call LogBare(Left("语言：         " & AssemblyLang & _
				Space79, 39) & "公钥令牌： " & AssemblyPublicKeyToken)
			Call LogBare("")

			' 用要复制的文件（和文件夹）填充关联数组。
			If StrComp(FSO.GetExtensionName(FileList(Loop1)), "mum", vbTextCompare) = 0 Then
				' 如果是.mum文件，还可以复制相关的目录文件。
				SourceFile = Replace(FileList(Loop1), ".mum", ".cat", 1, -1, vbTextCompare)
				If FirstFile Then
					' 第一个文件始终称为 “update.cat”。
					TargetFile = "update.cat"
				Else
					TargetFile = FSO.GetFileName(SourceFile)
				End If
				If FSO.FileExists(SourceFile) Then
					Call CopyListAdd(SourceFile, TargetFile)
				End If
			End If

			' 第一个文件始终称为 “update.mum”。
			SourceFile = FileList(Loop1)
			If FirstFile Then
				TargetFile = "update.mum"
			Else
				TargetFile = FSO.GetFileName(SourceFile)
			End If

			If FSO.FileExists(SourceFile) Then
				Call CopyListAdd(SourceFile, TargetFile)
			End If

			' 开始生成 winsxs 文件夹列表 2026.4.27
			If MakingFoldersList then
				If Not FSO.FileExists(FoldersListPath) Then
					Set FoldersList = FSO.CreateTextFile(FoldersListPath, TRUE, FALSE)
				End If
				If DebugMode Then
					WinStyle = 1
				Else
					WinStyle = 0
				End If
				If Right(TargetFile, 4) = ".mum" Then
				Else
					TheCommand = "CMD.EXE /C echo " & Replace(TargetFile, ".manifest", "") & ">>" & FoldersListPath
					Call LogDebug("执行：" & TheCommand)
					Shell.Run TheCommand, WinStyle, TRUE
				End If
			End If

			' 复制任何SxS程序集文件夹（当然）。如果是.mum文件，请将文件名转换为程序集ID格式。清单已经是程序集ID格式，但我仍然要与它们进行前缀匹配。
			Call LogInfo("正在查找可能的关联程序集文件夹。")
			ArraySize = CopyList.Count
			Call ExtractPossibleAssemblyFolders(FSO.BuildPath(SxSPath, _
				CreateAssemblyIDWildcard(AssemblyName, AssemblyPublicKeyToken, _
				AssemblyArch, AssemblyLang, AssemblyVersion)))

			If ViciousHacks Then
				' 允许提取TFTP客户端
				If StrComp(Replace(AssemblyName, "-Package", "", 1, -1, _
					vbTextCompare), AssemblyName) = 0 Then
					Call LogInfo("将 “-Package” 添加到" & _
						"程序集名称。")
					Call ExtractPossibleAssemblyFolders(FSO.BuildPath(SxSPath, _
						CreateAssemblyIDWildcard(AssemblyName & "-Package", _
						AssemblyPublicKeyToken, AssemblyArch, AssemblyLang, _
						AssemblyVersion)))
				End If

				' 允许提取适用于 Windows 8.x 的Adobe Flash。
				If Not (StrComp(Replace(AssemblyName, "-Package", "", 1, _
					-1, vbTextCompare), AssemblyName) = 0) Then
					Call LogInfo("将 “-Package” " & _
						"从程序集移除。")
					Call ExtractPossibleAssemblyFolders(FSO.BuildPath(SxSPath, _
						CreateAssemblyIDWildcard(Replace(AssemblyName, _
						"-Package", "", 1, -1, vbTextCompare), _
						AssemblyPublicKeyToken, AssemblyArch, AssemblyLang, _
						AssemblyVersion)))
				End If
			End If

			' 如果未复制任何内容，提供消息。
			If ArraySize = CopyList.Count Then
				Call LogInfo("找不到任何关联的程序集文件夹。")
			End If

			' 并（可能）向下递归以获取更多引用。
			Call FindReferencedAssemblies(XML, DependencyPath, AInFoldersListName)
			Call FindReferencedAssemblies(XML, PackagePath, AInFoldersListName)
			Call FindReferencedAssemblies(XML, ComponentPath, AInFoldersListName)
			Call FindReferencedAssemblies(XML, DriverPath, AInFoldersListName)
		End If

		' 如果这是压缩清单，删除临时清单。
		If Not (FileFlag And FileFlagCompressed) = 0 Then
			Call LogDebug("正在删除临时清单文件：" & CurrentManifest)
			FSO.GetFile(CurrentManifest).Delete TRUE
		End If
	Next

	' 成功！
	Set XML = NOTHING
	RecurseManifestHierarchy = TRUE
End Function


' 文件复制助手。
Function CopyObject(ASource, ATarget, AInFilesListName)
	Dim TargetFolder

	Dim SourceObj

	Dim SourcePath
	Dim TargetPath

	Dim FileCompressed
	Dim UncompSource
	
	' 组件生成 winsxs文件列表参数
	Dim FilesListPath
	Dim FilesList
	Dim WinStyle
	Dim TheCommand
	FilesListPath = FSO.BuildPath(FSO.GetFolder(".."&"\WinSxSList").Path, AInFilesListName)

	CopyObject = EMPTY

	' 确保路径不要太长。
	If Len(ASource) > MAX_PATH Then
		CopyObject = "路径太长：" & ASource
		Exit Function
	End If
	If Len(ATarget) > MAX_PATH Then
		CopyObject = "路径太长：" & ATarget
		Exit Function
	End If

	If FSO.FolderExists(ASource) Then
		If MakingCAB THEN
			' 创建目标文件夹。
			If NOT FSO.FolderExists(ATarget) THEN
				Set TargetFolder = FSO.CreateFolder(ATarget)
				Call LogDebug("创建文件夹： " & TargetFolder.Path)
			End If
		End If

		' 将文件夹复制到目标。
		For Each SourceObj In FSO.GetFolder(ASource).Files
			SourcePath = SourceObj.Path

			' 开始生成组件的 winsxs 文件列表
			If DebugMode Then
				WinStyle = 1
			Else
				WinStyle = 0
			End If
			If MakingFilesList then
				If Not FSO.FileExists(FilesListPath) Then
					Set FilesList = FSO.CreateTextFile(FilesListPath, TRUE, FALSE)
				End If
				TheCommand = "CMD.EXE /C echo \" & SourceObj.Name & ">>" & FilesListPath
				Call LogDebug("执行：" & TheCommand)
				Shell.Run TheCommand, WinStyle, TRUE
			End If

			IF MakingCAB THEN
				TargetPath = FSO.BuildPath(TargetFolder.Path, SourceObj.Name)
				CopyObject = CopyObject(SourcePath, TargetPath, AInFilesListName)
			ELSE 
				CopyObject = CopyObject(SourcePath, EMPTY, AInFilesListName)
			End If

			If Not IsEmpty(CopyObject) Then
				Exit Function
			End If
		Next
		For Each SourceObj In FSO.GetFolder(ASource).SubFolders
			SourcePath = SourceObj.Path

			' 如果存在二级目录，开始生成组件的 winsxs 文件列表
	
			IF MakingCAB THEN
				TargetPath = FSO.BuildPath(TargetFolder.Path, SourceObj.Name)
				CopyObject = CopyObject(SourcePath, TargetPath, AInFilesListName)
			ELSE
				CopyObject = CopyObject(SourcePath, EMPTY, AInFilesListName)
			End If

			If Not IsEmpty(CopyObject) Then
				Exit Function
			End If
		Next

	ElseIf FSO.FileExists(ASource) Then
		' 将文件源复制到目标。
		If MakingCAB Then
			FileCompressed = IsCompressed(ASource)
			If FileCompressed Then
				Call LogInfo("解压缩和复制文件：" & ASource & _
					" --> " & ATarget)

				' 解压缩源文件。
				UncompSource = SxSExpand(ASource)
				If IsEmpty(UncompSource) Then
					FileCompressed = FALSE
					UncompSource = ASource
					Call LogDebug("无法解压缩文件-正在将其复制以 " & _
						"压缩形式。")
				End If
			Else
				Call LogInfo("复制文件：" & ASource & " --> " & ATarget)
				UncompSource = ASource
			End If
		
			On Error Resume Next
			FSO.GetFile(UncompSource).Copy ATarget, TRUE
			If Not (Err.Number = 0) Then
				CopyObject = Err.Description
				Exit Function
			End If
			On Error GoTo 0

			' 删除可能的临时未压缩文件。
			If FileCompressed Then
				Call LogDebug("正在删除临时解压缩文件：" & _
					UncompSource)
				FSO.GetFile(UncompSource).Delete TRUE
			End If
			CopyObject = EMPTY
		End If
	Else
		' 文件不存在。
		Call LogDebug("对不存在/无效的文件/文件夹调用CopyObject: " & _
			ASource)
		CopyObject = EMPTY
	End If
End Function

Sub CopyPackage(AOutputPath, AInFilesListName)
	Dim Loop1

	Dim CopyKeys
	Dim CopyItems

	Dim COResult
	Dim OutputPath

	Dim Folder
	Dim Source
	Dim ObjType

	Dim BatchFileName
	Dim BatchFile
	Dim TheCommand
	Dim WinStyle

	Call LogInfo("正在创建包。文件/文件夹数：" & _
		CStr(CopyList.Count))

	' 创建（可能是临时）目标文件夹。
	If MakingCAB Then
		Set Folder = FSO.CreateFolder(FSO.GetBaseName(AOutputPath))
		Call LogDebug("创建临时目标文件夹：" & Folder.Path)
		OutputPath = Subst(Folder.Path)
	End If

	CopyKeys = CopyList.Keys
	CopyItems = CopyList.Items
	For Loop1 = 0 To CopyList.Count - 1
		If FSO.FileExists(CopyKeys(Loop1)) Then
			Set Source = FSO.GetFile(CopyKeys(Loop1))
		ElseIf FSO.FolderExists(CopyKeys(Loop1)) Then
			Set Source = FSO.GetFolder(CopyKeys(Loop1))
		End If
		If MakingCAB Then
			COResult = CopyObject(Source, FSO.BuildPath(OutputPath, _
				CopyItems(Loop1)), AInFilesListName)
		ELSE 
			COResult = CopyObject(Source, EMPTY, AInFilesListName)
		End If

		If Not IsEmpty(COResult) Then
			Call LogFatal("复制失败 - " & COResult)

			' 删除部分目标文件夹。
			If MakingCAB Then
				Call UnSubst(OutputPath)
			End If
			Call LogInfo("正在删除不完整的目标文件夹：" & Folder.Path)
			Folder.Delete TRUE
			WScript.Quit 1
		End If
	Next

	' 制作一个 cab 文件。
	If MakingCAB Then
		Call LogInfo("将文件夹压缩成CAB文件：" & AOutputPath)

		' 为CABARC.EXE生成命令行参数。
		TheCommand = "-m LZX:21 -r -p N """ & _
			FSO.GetAbsolutePathName(AOutputPath) & """ *.*"
		Call LogDebug("CABARC.EXE的命令行参数：" & TheCommand)

		' 编写批处理文件以调用CABARC.EXE。
		Do
			BatchFileName = FSO.BuildPath(TempFolder, FSO.GetTempName + ".BAT")
		Loop Until _
			(Not FSO.FileExists(BatchFileName))
		Set BatchFile = FSO.CreateTextFile(BatchFileName, TRUE, FALSE)
		BatchFile.WriteLine("@ECHO OFF")
		BatchFile.WriteLine("CD /D " & OutputPath)
		BatchFile.WriteLine("CABARC.EXE " & TheCommand)
		BatchFile.WriteLine("IF ERRORLEVEL 9009 GOTO RETRY")
		BatchFile.WriteLine("GOTO END")
		BatchFile.WriteLine(":RETRY")
		BatchFile.WriteLine("""" & FSO.BuildPath(FSO.GetFolder(".").Path, _
			"CABARC.EXE") & """ " & TheCommand)
		BatchFile.WriteLine(":END")
		BatchFile.Close
		Set BatchFile = NOTHING
		Call LogDebug("创建批处理文件调用CABARC.EXE： " & _
			BatchFileName)

		' 调用创建的批处理文件。
		If DebugMode Then
			WinStyle = 1
		Else
			WinStyle = 0
		End If
		TheCommand = "CMD.EXE /C """ & BatchFileName & """"
		Call LogDebug("执行：" & TheCommand)

		' 独立运行，不检查返回代码。
		Shell.Run TheCommand, WinStyle, TRUE

		'If MakingCAB Then
			Call UnSubst(OutputPath)
		'End If
		If Not FSO.FileExists(AOutputPath) Then
			' 创建 cab 文件柜时出错。将目标文件夹留给用户保存处理。
			Call LogError("无法创建目标cab文件-未删除 " & _
				"临时目标文件夹：" & Folder.Path)
		Else
			' 删除目标文件夹，只保留 cab 文件。
			Call LogDebug("正在删除临时目标文件夹：" & Folder.Path)
			Folder.Delete TRUE
		End If

		' 删除调用批处理文件。
		Call LogDebug("正在删除调用CABARC.EXE的批处理文件：" & _
			BatchFileName)
		FSO.GetFile(BatchFileName).Delete TRUE
	Else
		Call UnSubst(OutputPath)
	End If

	Set Folder = NOTHING
End Sub


' 整洁的例程，它不仅匹配开关，而且在正确设置为switchlength时将返回开关指定的参数。
Function MatchSwitch(AIndex, ASwitch, ASwitchLength)
	Dim SwitchText

	MatchSwitch = EMPTY

	' 如果开关不存在，它显然无法匹配。
	If AIndex < WScript.Arguments.Count Then
		SwitchText = WScript.Arguments(AIndex)
		
		' 必须以参数开头
		If (Not (Left(SwitchText, 1) = "/")) And _
			(Not (Left(SwitchText, 1) = "-")) Then
			Exit Function
		End If

		' 分离开关字符以进行比较。
		SwitchText = Mid(SwitchText, 2)

		If ASwitchLength = -1 Then
			' 简单。
			If StrComp(SwitchText, ASwitch, vbTextCompare) = 0 Then
				MatchSwitch = ASwitch
				Exit Function
			End If
		Else
			' 困难。
			If StrComp(Left(SwitchText, ASwitchLength), ASwitch, _
				vbTextCompare) = 0 Then
				MatchSwitch = Mid(SwitchText, ASwitchLength + 1)
				Exit Function
			End If
		End If
	End If
End Function


' 大的符号用来提示用户。
Sub DisplayBanner
	Call LogBare(Banner1)
	Call LogBare(Banner2)
	Call LogBare("")
End Sub

' 帮助信息
Sub DisplayHelp
	Call LogBare("CSCRIPT.EXE SXSEXTRACT.VBS [/?,/H,/HELP] [/DEBUG,/V] </ONLINE|/IMAGE:<folder>>")
	Call LogBare("  [/INCLUDERES] [/VICIOUSHACKS] <source>.mum [<target>[.cab]]")
	Call LogBare("")
	Call LogBare("解析Windows并排包清单文件，查找所有引用，并复制与包关联的所有文件。")
	Call LogBare("")
	Call LogBare("  /?,/H,/HELP      显示帮助信息。")
	Call LogBare("  /DEBUG,/V        启用详细调试输出。")
	Call LogBare("  /ONLINE          使用%SYSTEMROOT%（通常为C:\Windows）作为根文件夹，搜索相关文件。")
	Call LogBare("  /IMAGE:<folder>  使用<folder>作为根文件夹搜索关联，而不是文件。")
	Call LogBare("  /INCLUDERES      对于没有关联语言包的组件，也提取MUI资源。")
	Call LogBare("  /VICIOUSHACKS    激活对脚本的一些操作，以提取不按确切名称引用程序集复杂的组件。")
	Call LogBare("  <source>.mum     指定包清单文件。不允许使用通配符。")
	Call LogBare("  <target>[.cab]   指定提取文件的目标文件夹。如果指定了扩展名“.cab”，则脚本将调用CABARC.EXE来创建cab文件。")
	Call LogBare("")
	Call LogBare("此脚本需要SXSEXPAND.EXE和CABARC.EXE（位于当前文件夹或系统路径中）才能实现完整功能。")
End Sub


' 脚本开始。
Call DisplayBanner

ParamIndex = 0
MakingCAB = FALSE
SystemRoot = EMPTY
DebugMode = FALSE
IncludeRes = FALSE
ViciousHacks = FALSE

' 创建对象。
Set Shell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

' 检查外部工具。
Call CheckExternals

' 定义变量。
TempFolder = Shell.ExpandEnvironmentStrings("%TEMP%")

' 解析命令行。
For SwitchLoop = 0 To WScript.Arguments.Count - 1
	If (Not IsEmpty(MatchSwitch(SwitchLoop, "?", -1))) Or _
		(Not IsEmpty(MatchSwitch(SwitchLoop, "h", -1))) Or _
		(Not IsEmpty(MatchSwitch(SwitchLoop, "help", -1))) Then
		Call DisplayHelp
		WScript.Quit 0

	ElseIf (Not IsEmpty(MatchSwitch(SwitchLoop, "debug", -1))) Or _
		(Not IsEmpty(MatchSwitch(SwitchLoop, "v", -1))) Then
		DebugMode = TRUE

	ElseIf Not IsEmpty(MatchSwitch(SwitchLoop, "online", -1)) Then
		If Not IsEmpty(SystemRoot) Then
			Call LogFatal("参数错误：" & WScript.Arguments(SwitchLoop))
			WScript.Quit 1
		End If
		SystemRoot = Shell.ExpandEnvironmentStrings("%SYSTEMROOT%")

	ElseIf Not IsEmpty(MatchSwitch(SwitchLoop, "image:", 6)) Then
		If Not IsEmpty(SystemRoot) Then
			Call LogFatal("参数错误：" & WScript.Arguments(SwitchLoop))
			WScript.Quit 1
		End If
		SystemRoot = MatchSwitch(SwitchLoop, "image:", 6)

	ElseIf Not IsEmpty(MatchSwitch(SwitchLoop, "includeres", -1)) Then
		IncludeRes = TRUE

	ElseIf Not IsEmpty(MatchSwitch(SwitchLoop, "vicioushacks", -1)) Then
		ViciousHacks = TRUE

	Else
		' 参数检查完毕
		If (Left(WScript.Arguments(SwitchLoop), 1) = "/") Or _
			(Left(WScript.Arguments(SwitchLoop), 1) = "-") Then
			' 没有相关参数
			Call LogFatal("未知参数： " & WScript.Arguments(SwitchLoop))
			WScript.Quit 1
		Else
			' 向后移动参数指针，退出循环。
			ParamIndex = ParamIndex - 1
			SwitchLoop = WScript.Arguments.Count - 1
		End If
	End If
	ParamIndex = ParamIndex + 1
Next

' 开关解析完成。解析参数。
If ParamIndex = WScript.Arguments.Count Then
	' 没有参数。
	Call LogFatal("未指定包文件。")
	WScript.Quit 1
ElseIf (ParamIndex + 1) = WScript.Arguments.Count Then
	' 一个参数。假设它是源程序包文件，并以此为基础创建目标。
	InputPath = WScript.Arguments(ParamIndex)
	OutputPath = FSO.GetBaseName(InputPath)
	Call LogError("未指定目标文件夹/文件，假设：" & OutputPath)
ElseIf (ParamIndex + 2) = WScript.Arguments.Count Then
	' 两个参数：源程序包文件和目标路径。
	InputPath = WScript.Arguments(ParamIndex)
	OutputPath = WScript.Arguments(ParamIndex + 1)
ElseIf (ParamIndex + 3) = WScript.Arguments.Count Then
	' 三个参数：源程序包文件和目标路径、导出txt1
	InputPath = WScript.Arguments(ParamIndex)
	OutputPath = WScript.Arguments(ParamIndex + 1)
	InFoldersListName =  WScript.Arguments(ParamIndex + 2)
ElseIf (ParamIndex + 4) = WScript.Arguments.Count Then
	' 四个参数：源程序包文件和目标路径、导出txt1、导出txt2
	InputPath = WScript.Arguments(ParamIndex)
	OutputPath = WScript.Arguments(ParamIndex + 1)
	InFoldersListName =  WScript.Arguments(ParamIndex + 2)
	InFilesListName =  WScript.Arguments(ParamIndex + 3)
Else
	' 参数过多！
	Call LogFatal("参数过多。")
	WScript.Quit 1
End If

' 检查明显错误/过长的文件名。
If (Not (InStr(InputPath, "*") = 0)) Or _
	(Not (InStr(InputPath, "?") = 0)) Or _
	(Len(InputPath) > MAX_PATH) Then
	Call LogFatal("无效的包文件名：" & InputPath)
	WScript.Quit 1
End If
If (Not (InStr(OutputPath, "*") = 0)) Or _
	(Not (InStr(OutputPath, "?") = 0)) Or _
	(Len(OutputPath) > MAX_PATH) Then
	Call LogFatal("无效的目标文件夹：" & OutputPath)
	WScript.Quit 1
End If

' 检查包文件是否存在。
If Not FSO.FileExists(InputPath) Then
	Call LogFatal("包文件不存在：" & InputPath)
	WScript.Quit 1
End If

' 标记脚本是否生成 cab 文件。
If StrComp(FSO.GetExtensionName(OutputPath), "cab", vbTextCompare) = 0 Then
	If Not CABArcAvailable Then
		Call LogError("MS CAB工具不可用-无法创建CAB文件。")
		MakingCAB = FALSE
	Else
		MakingCAB = TRUE
	End If
Else
	MakingCAB = FALSE
End If
' 标记脚本是否生成 txt1 文件。
If StrComp(FSO.GetExtensionName(InFoldersListName), "txt", vbTextCompare) = 0 Then
	MakingFoldersList = TRUE
Else
	MakingFoldersList = FALSE
End If
' 标记脚本是否生成 txt2 文件。
If StrComp(FSO.GetExtensionName(InFilesListName), "txt", vbTextCompare) = 0 Then
	MakingFilesList = TRUE
Else
	MakingFilesList = FALSE
End If

' 确保目标cab文件和/或文件夹不存在。
If MakingCAB Then
	If FSO.FileExists(OutputPath) Then
		Call LogFatal("目标文件已存在：" & OutputPath)
		WScript.Quit 1
	End If
	If FSO.FolderExists(FSO.GetBaseName(OutputPath)) Then
		Call LogFatal("临时目标文件夹已存在：" & _
			FSO.GetBaseName(OutputPath))
		WScript.Quit 1
	End If
Else
	If FSO.FolderExists(OutputPath) Then
		Call LogFatal("目标文件夹已存在：" & OutputPath)
		WScript.Quit 1
	End If
End If

' 检查外部工具是否可用。
Call CheckExternals

' 开始复制。
Set CopyList = CreateObject("Scripting.Dictionary")

Call RecurseManifestHierarchy(InputPath, EMPTY, EMPTY, EMPTY, EMPTY, InFoldersListName)
IF MakingCAB OR MakingFilesList THEN
	Call CopyPackage(OutputPath, InFilesListName)
END IF

Set CopyList = NOTHING

Set FSO = NOTHING
Set Shell = NOTHING

WScript.Quit 0