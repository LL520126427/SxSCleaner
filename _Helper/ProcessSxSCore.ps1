<#
.SYNOPSIS
提取Windows组件包名称（去除GUID和版本号部分）
.DESCRIPTION
支持通过参数传入文件路径（绝对/相对均可），完美兼容Windows 7 PowerShell 2.0，修复UTF8 BOM乱码问题
.PARAMETER FilePath
要处理的WinSxSExclude.txt文件路径（绝对/相对均可，默认：脚本同目录下的WinSxSExclude.txt）
.EXAMPLE
.\ProcessSxSCore.ps1
（无参数，处理脚本同目录的WinSxSExclude.txt）
.EXAMPLE
.\ProcessSxSCore.ps1 D:\WinSxSExclude.txt
（传入绝对路径）
.EXAMPLE
.\ProcessSxSCore.ps1 .\WinSxSExclude.txt
（传入相对当前目录的路径）
#>

# 参数定义（Win7兼容的PowerShell 2.0语法）
param(
    [Parameter(Position=0)]
    [string]$FilePath
)

# 1. 自动设置默认路径（无参数时使用脚本同目录的WinSxSExclude.txt）
if ([string]::IsNullOrEmpty($FilePath)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $FilePath = Join-Path $scriptDir "WinSxSExclude.txt"
}

# 2. 将相对路径转换为绝对路径（Win7兼容方案：使用.NET原生方法）
$absoluteFilePath = [System.IO.Path]::GetFullPath($FilePath)

# 3. 检查文件是否存在
if (-not (Test-Path $absoluteFilePath -PathType Leaf)) {
    Write-Error "错误：文件不存在 - $absoluteFilePath"
    Write-Host "使用方法："
    Write-Host "  1. 直接传路径： .\ProcessSxSCore.ps1 D:\WinSxSExclude.txt"
    Write-Host "  2. 相对路径：   .\ProcessSxSCore.ps1 .\WinSxSExclude.txt"
    Write-Host "  3. 无参数：      .\ProcessSxSCore.ps1（处理脚本同目录的WinSxSExclude.txt）"
    exit 1
}

# ===================== 重点修改区域 =====================
# PS2.0 抛弃Get-Content/Set-Content，改用.NET读写，输出【无BOM UTF8】
# ========================================================
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
# 读取全部文本
$textContent = [System.IO.File]::ReadAllText($absoluteFilePath, $utf8NoBom)
$lines = $textContent -split "`r`n"

# 4. 处理每一行：提取包名正则
$processedLines = $lines | ForEach-Object {
    if ([string]::IsNullOrEmpty($_)) { return $_ }
    $_ -replace '^.*?_' , '_' `
       -replace '^(.+?)_[0-9a-fA-F]{8}.*$', '$1'
}

# 拼接换行写回（Windows标准CRLF换行）
$outputText = $processedLines -join "`r`n"
[System.IO.File]::WriteAllText($absoluteFilePath, $outputText, $utf8NoBom)

Write-Host "$absoluteFilePath"