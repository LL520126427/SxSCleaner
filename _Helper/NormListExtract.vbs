Dim FSO, InFilePath, OutFilePath, varstr

If WScript.Arguments.Count < 3 Then
WScript.Echo "参数不够！"
WScript.Quit 1
End If

If WScript.Arguments.Count > 3 Then
WScript.Echo "参数过多！"
WScript.Quit 1
End If

InFilePath = WScript.Arguments(0)
OutFilePath = WScript.Arguments(1)
varstr = WScript.Arguments(2)

Set FSO = CreateObject("Scripting.FileSystemObject")
text = FSO.OpenTextFile(InFilePath,1).ReadAll()
arr = Split(text,vbCrLf)
For i=0 To UBound(arr)
   If Len(arr(i)) Then arr(i)=varstr & " """ & arr(i) &""""
Next
text = Join(arr,vbCrLf)
FSO.CreateTextFile(OutFilePath,True).Write(text)

