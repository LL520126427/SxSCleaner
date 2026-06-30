# 传递 appxmanifest.xml 路径
param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

# 使用 .NET 方法读取整个文件内容为字符串（UTF-8 编码）
$content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)

# 删除指定的 <Application> 块
$newContent = $content -replace '(?s)<Application Id="(WebExperienceHost|WindowsBackup)"[^>]*>.*?</Application>', ''

# 按行拆分，过滤空行，再用系统换行符重新连接
$lines = $newContent -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
$finalContent = [string]::Join([Environment]::NewLine, $lines)

# 将处理后的内容写回原文件（UTF-8 编码）
[System.IO.File]::WriteAllText($Path, $finalContent, [System.Text.Encoding]::UTF8)