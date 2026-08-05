Dim FSO, InFile, OutFile, line, FilePath

If WScript.Arguments.Count < 2 Then
WScript.Echo "请指定输入文件和输出文件路径。"
WScript.Quit 1
End If

If WScript.Arguments.Count > 2 Then
WScript.Echo "参数过多！"
WScript.Quit 1
End If

InFilePath = WScript.Arguments(0)
OutFilePath = WScript.Arguments(1)

Set FSO = CreateObject("Scripting.FileSystemObject")
Set InFile = FSO.OpenTextFile(InFilePath, 1) ' 1 表示只读
Set OutFile = FSO.CreateTextFile(OutFilePath, True) ' True 表示覆盖

Do While Not InFile.AtEndOfStream
    line = InFile.ReadLine
    If InStr(line, "\") > 0 Then
        FilePath = Left(line, InStrRev(line, "\") - 1)
    Else
        FilePath = line
    End If
    OutFile.WriteLine FilePath
Loop

InFile.Close
OutFile.Close
