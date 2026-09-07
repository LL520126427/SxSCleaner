<#
Windows组件版本清理工具 - 手动分组版，兼容 PowerShell 2.0
输出：需要删除的旧版本组件列表（每个组件组/主版本号下，仅保留最新版本）
用法：Powershell -noprofile -executionpolicy bypass -file "SxSVerCleanup.ps1" "DelVerWinSxSFolders.txt"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath
)

# 处理输入路径
if ([System.IO.Path]::IsPathRooted($InputPath)) {
    $InputFullPath = $InputPath
} else {
    $InputFullPath = Join-Path $PWD.Path $InputPath
}

# 输出路径
$directory = [System.IO.Path]::GetDirectoryName($InputFullPath)
$filename = [System.IO.Path]::GetFileName($InputFullPath)
$OutputFullPath = Join-Path $directory "_$filename"

# 读取所有行（使用 .NET 方式，避免 PS 2.0 编码问题）
$lines = [System.IO.File]::ReadAllLines($InputFullPath, [System.Text.Encoding]::UTF8)

# 存储解析后的对象：每个元素为 Hashtable，包含 Group, MajorVer, Version, Line
$components = @()

foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "") { continue }
    # if ($trimmed -match '\.resources') { continue }
    
    # 正则提取：贪婪匹配组件名前缀，捕获版本号
    if ($trimmed -match '^(.+)_(\d+\.\d+\.\d+\.\d+)_') {
        $groupName = $matches[1]
        $verStr = $matches[2]
        try {
            $version = [Version]$verStr
        } catch {
            Write-Warning "跳过无法解析版本的行: $trimmed"
            continue
        }
        $majorVer = "$($version.Major).$($version.Minor)"
        
        # 存储为 Hashtable 以便后续操作
        $components += @{
            Group    = $groupName
            MajorVer = $majorVer
            Version  = $version
            Line     = $trimmed
        }
    }
}

# 手动分组：使用嵌套的 Hashtable
# 结构：$groups[$groupName][$majorVer] = 该组下所有组件的数组
$groups = @{}
foreach ($comp in $components) {
    $g = $comp.Group
    $m = $comp.MajorVer
    if (-not $groups.ContainsKey($g)) {
        $groups[$g] = @{}
    }
    if (-not $groups[$g].ContainsKey($m)) {
        $groups[$g][$m] = @()
    }
    $groups[$g][$m] += $comp
}

# 收集需要删除的行
$deleteLines = @()
foreach ($g in $groups.Keys) {
    foreach ($m in $groups[$g].Keys) {
        $items = $groups[$g][$m]
        if ($items.Count -gt 1) {
            # 手动找出最大版本号（兼容 PowerShell 2.0）
            $maxVersion = $items[0].Version
            foreach ($item in $items) {
                if ($item.Version -gt $maxVersion) {
                    $maxVersion = $item.Version
                }
            }
            # 只删除版本号小于最大版本的组件
            foreach ($item in $items) {
                if ($item.Version -lt $maxVersion) {
                    $deleteLines += $item.Line
                }
            }
        }
    }
}

# 写入输出文件（使用 UTF8 无 BOM，避免乱码）
if ($deleteLines.Count -gt 0) {
    [System.IO.File]::WriteAllLines($OutputFullPath, $deleteLines, [System.Text.Encoding]::UTF8)
} else {
    [System.IO.File]::WriteAllText($OutputFullPath, "", [System.Text.Encoding]::UTF8)
}

Write-Host "$OutputFullPath"