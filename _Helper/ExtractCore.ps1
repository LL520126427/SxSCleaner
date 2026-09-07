<#
.SYNOPSIS
裁剪WinSxS组件名称
用法：
.\ExtractCore.ps1 test.txt            # 原地覆盖原文件
.\ExtractCore.ps1 test.txt _test.txt  # 输入test.txt，输出到_test.txt
支持管道：Get-Content test.txt | .\ExtractCore.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Position=0,Mandatory=$false)]
    [string]$Arg1,

    [Parameter(Position=1,Mandatory=$false)]
    [string]$Arg2,

    [Parameter(ValueFromPipeline=$true)]
    [string[]]$InputText
)

begin {
    $buffer = @()

    # PS2.0 / 5.1 输出 UTF‑8‑BOM + 强制CRLF Windows换行
    function Write-Utf8BomFile {
        param(
            [string[]]$ContentLines,
            [string]$Path
        )
        # $false = UTF‑8 无BOM，CMD type不会出现锘縚乱码，CRLF换行不变
        $utf8Bom = New-Object System.Text.UTF8Encoding $false
        # 强制全部使用 Windows CRLF 换行符
        $sb = New-Object System.Text.StringBuilder
        foreach($ln in $ContentLines){
            [void]$sb.Append($ln)
            [void]$sb.Append("`r`n")
        }
        $fullPath = (Resolve-Path -LiteralPath $Path).ProviderPath
        [System.IO.File]::WriteAllText($fullPath, $sb.ToString(), $utf8Bom)
    }
}

process {
    if($PSBoundParameters.ContainsKey('InputText')){
        $buffer += $InputText
    }
}

end {
    $InFile  = $null
    $OutFile = $null

    # 位置参数处理
    if(-not [string]::IsNullOrWhiteSpace($Arg1)){
        $InFile = $Arg1
    }
    if(-not [string]::IsNullOrWhiteSpace($Arg2)){
        $OutFile = $Arg2
    }

    # 如果给了输入文件，读取文件
    if($InFile){
        $buffer = Get-Content -Path $InFile
    }

    $result = @()
    foreach ($line in $buffer) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            $result += ""
            continue
        }
        # 截断版本号后缀
        $parts = $line -split '_'
        $outParts = @()
        foreach ($p in $parts) {
            if ($p -match '^\d+\.\d+') { break }
            $outParts += $p
        }
        $trimmed = $outParts -join '_'

        # 去掉第一个_前面架构前缀，保留开头下划线
        $pos = $trimmed.IndexOf('_')
        if($pos -ge 0){
            $trimmed = $trimmed.Substring($pos)
        }
        $result += $trimmed
    }

    #输出逻辑
    if($OutFile){
        Write-Utf8BomFile -ContentLines $result -Path $OutFile
    }
    elseif($InFile){
        Write-Utf8BomFile -ContentLines $result -Path $InFile
    }
    else{
        # 控制台输出
        $result | Write-Output
    }
}