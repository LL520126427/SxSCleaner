#Requires -RunAsAdministrator
# WinDefCtl.ps1 - Windows Defender自动化与控制工具
# PowerShell版 - 实时保护与篡改保护管理
# 作者: Marek Wesolowski - WESMAR - 2025

# 脚本参数定义：
# -Command: 指定要操作的功能 (rtp: 实时保护, tp: 篡改保护, all: 两者)
# -Action: 指定要执行的操作 (on: 开启, off: 关闭, status: 查看状态)
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('rtp', 'tp', 'all')]
    [string]$Command,
    
    [Parameter(Mandatory=$false, Position=1)]
    [ValidateSet('on', 'off', 'status')]
    [string]$Action = 'status'
)

# ============================================================================
# UI Automation Setup - UI自动化设置
# ============================================================================

# 加载UI自动化所需的.NET程序集
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# 定义Windows API函数，用于窗口操作
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);
    
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    public const uint WM_SYSCOMMAND = 0x0112;
    public const uint SC_CLOSE = 0xF060;
    public const uint WM_CLOSE = 0x0010;
    public const int SW_SHOWMINNOACTIVE = 7;
}
"@

# ============================================================================
# Registry Helper Functions - 注册表辅助函数
# ============================================================================

# UAC注册表路径
$UAC_REG_PATH = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
# 易失性注册表键路径，用于检测冷启动
$VOLATILE_KEY_PATH = "HKCU:\Software\Temp"
# 特殊值：表示注册表键不存在
$KEY_NOT_EXISTED = 0xFF

# 读取注册表DWORD值
function Read-RegistryDword {
    param(
        [string]$Path,
        [string]$Name
    )
    
    try {
        if (Test-Path $Path) {
            $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $value) {
                return @{
                    Value = $value.$Name
                    Existed = $true
                }
            }
        }
    }
    catch { }
    
    # 如果读取失败，返回默认值
    return @{
        Value = 0
        Existed = $false
    }
}

# 写入注册表DWORD值
function Write-RegistryDword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
        return $true
    }
    catch {
        return $false
    }
}

# 删除注册表值
function Remove-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )
    
    try {
        if (Test-Path $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        }
        return $true
    }
    catch {
        return $false
    }
}

# ============================================================================
# UAC Management Functions - UAC管理函数
# ============================================================================

# 将UAC状态编码为单个整数值
function Encode-UACStatus {
    param(
        [int]$CPBA,
        [bool]$CPBAExisted,
        [int]$POSD,
        [bool]$POSDExisted
    )
    
    $cpbaValue = if ($CPBAExisted) { $CPBA -band 0xFF } else { $KEY_NOT_EXISTED }
    $posdValue = if ($POSDExisted) { $POSD -band 0xFF } else { $KEY_NOT_EXISTED }
    
    $encoded = $cpbaValue -bor ($posdValue -shl 8)
    
    return $encoded
}

# 从编码值解码UAC状态
function Decode-UACStatus {
    param([int]$Encoded)
    
    $cpbaByte = $Encoded -band 0xFF
    $posdByte = ($Encoded -shr 8) -band 0xFF
    
    return @{
        CPBA = if ($cpbaByte -ne $KEY_NOT_EXISTED) { $cpbaByte } else { 0 }
        CPBAExisted = ($cpbaByte -ne $KEY_NOT_EXISTED)
        POSD = if ($posdByte -ne $KEY_NOT_EXISTED) { $posdByte } else { 0 }
        POSDExisted = ($posdByte -ne $KEY_NOT_EXISTED)
    }
}

# 备份并临时禁用UAC提示
function Backup-UAC {
    Write-Host "  [*] 备份并禁用UAC提示..."
    
    # 读取当前UAC设置
    $cpba = Read-RegistryDword -Path $UAC_REG_PATH -Name "ConsentPromptBehaviorAdmin"
    $posd = Read-RegistryDword -Path $UAC_REG_PATH -Name "PromptOnSecureDesktop"
    
    # 编码并保存备份
    $encoded = Encode-UACStatus -CPBA $cpba.Value -CPBAExisted $cpba.Existed -POSD $posd.Value -POSDExisted $posd.Existed
    
    if (-not (Write-RegistryDword -Path $UAC_REG_PATH -Name "UACStatus" -Value $encoded)) {
        return $false
    }
    
    # 临时禁用UAC提示
    $success = $true
    $success = $success -and (Write-RegistryDword -Path $UAC_REG_PATH -Name "ConsentPromptBehaviorAdmin" -Value 0)
    $success = $success -and (Write-RegistryDword -Path $UAC_REG_PATH -Name "PromptOnSecureDesktop" -Value 0)
    
    return $success
}

# 恢复原始UAC设置
function Restore-UAC {
    Write-Host "  [*] 恢复原始UAC设置..."
    
    # 读取备份
    $backup = Read-RegistryDword -Path $UAC_REG_PATH -Name "UACStatus"
    
    if (-not $backup.Existed) {
        return $false
    }
    
    # 解码备份值
    $decoded = Decode-UACStatus -Encoded $backup.Value
    
    # 恢复原始设置
    if ($decoded.CPBAExisted) {
        Write-RegistryDword -Path $UAC_REG_PATH -Name "ConsentPromptBehaviorAdmin" -Value $decoded.CPBA | Out-Null
    }
    else {
        Remove-RegistryValue -Path $UAC_REG_PATH -Name "ConsentPromptBehaviorAdmin" | Out-Null
    }
    
    if ($decoded.POSDExisted) {
        Write-RegistryDword -Path $UAC_REG_PATH -Name "PromptOnSecureDesktop" -Value $decoded.POSD | Out-Null
    }
    else {
        Remove-RegistryValue -Path $UAC_REG_PATH -Name "PromptOnSecureDesktop" | Out-Null
    }
    
    # 删除备份标记
    Remove-RegistryValue -Path $UAC_REG_PATH -Name "UACStatus" | Out-Null
    return $true
}

# 检查是否存在不完整的UAC备份
function Test-UACBackupExists {
    $backup = Read-RegistryDword -Path $UAC_REG_PATH -Name "UACStatus"
    return $backup.Existed
}

# 如果需要，恢复UAC设置（处理脚本意外终止的情况）
function Recover-UACIfNeeded {
    if (Test-UACBackupExists) {
        Write-Host "  [恢复] 发现未完成的UAC备份，正在恢复..."
        return Restore-UAC
    }
    return $true
}

# ============================================================================
# Cold Boot Detection (Volatile Registry Marker) - 冷启动检测
# ============================================================================

# 检测是否为冷启动（新会话）
function Test-ColdBoot {
    # 检查易失性注册表键 - 在注销/重启后消失
    try {
        $marker = Get-ItemProperty -Path "$VOLATILE_KEY_PATH" -Name "WinDefCtl_Warmed" -ErrorAction SilentlyContinue
        return ($null -eq $marker)  # 没有标记表示冷启动
    }
    catch {
        return $true
    }
}

# 设置已预热标记
function Set-WarmMarker {
    try {
        # 创建易失性注册表键 - 会话结束时消失
        if (-not (Test-Path $VOLATILE_KEY_PATH)) {
            New-Item -Path $VOLATILE_KEY_PATH -Force | Out-Null
        }
        
        # PowerShell不支持REG_OPTION_VOLATILE，使用reg.exe创建真正的易失性键
        & reg add "HKCU\Software\Temp" /v "WinDefCtl_Warmed" /t REG_DWORD /d 1 /f | Out-Null
        
        return $true
    }
    catch {
        return $false
    }
}

# ============================================================================
# Window Management Functions - 窗口管理函数
# ============================================================================

# 查找Windows安全窗口
function Find-SecurityWindow {
    param([int]$MaxRetries = 10)
    
    $script:foundWindow = $null
    
    # 多次尝试查找窗口
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        # 枚举所有窗口的回调函数
        $callback = [WinAPI+EnumWindowsProc] {
            param($hwnd, $lParam)
            
            $className = New-Object System.Text.StringBuilder 256
            [WinAPI]::GetClassName($hwnd, $className, 256) | Out-Null
            
            # 查找应用框架窗口（Windows Security使用）
            if ($className.ToString() -eq "ApplicationFrameWindow" -and [WinAPI]::IsWindowVisible($hwnd)) {
                $script:foundWindow = $hwnd
                return $false  # 停止枚举
            }
            return $true  # 继续枚举
        }
        
        [WinAPI]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
        
        if ($script:foundWindow) {
            return $script:foundWindow
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    return $null
}

# 关闭安全窗口
function Close-SecurityWindow {
    param([IntPtr]$WindowHandle)
    
    if ($WindowHandle -eq [IntPtr]::Zero -or -not [WinAPI]::IsWindow($WindowHandle)) {
        return
    }
    
    # 尝试SetForegroundWindow + SC_CLOSE组合关闭
    [WinAPI]::SetForegroundWindow($WindowHandle) | Out-Null
    Start-Sleep -Milliseconds 100
    [WinAPI]::SendMessage($WindowHandle, [WinAPI]::WM_SYSCOMMAND, [IntPtr][WinAPI]::SC_CLOSE, [IntPtr]::Zero) | Out-Null
    
    # 等待窗口关闭
    $closed = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (-not [WinAPI]::IsWindow($WindowHandle)) {
            $closed = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }
    
    # 备用方法：使用WM_CLOSE消息
    if (-not $closed) {
        [WinAPI]::SendMessage($WindowHandle, [WinAPI]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 1000
    }
}

# ============================================================================
# Pre-Warming for Cold Boot - 冷启动预热
# ============================================================================

# 执行Defender预热（解决首次启动慢的问题）
function Invoke-PreWarmDefender {
    Write-Host "  [*] 检测到冷启动 - 正在预热Windows Defender..."
    
    # 启动Windows Defender（隐藏窗口）
    Start-Process "windowsdefender://threatsettings" -WindowStyle Hidden
    Start-Sleep -Milliseconds 800
    
    # 查找安全窗口
    $hwnd = Find-SecurityWindow -MaxRetries 10
    
    if ($hwnd) {
        Write-Host "  [*] 找到预热窗口，等待完全初始化..."
        Start-Sleep -Milliseconds 800
        
        Write-Host "  [*] 关闭预热窗口..."
        Close-SecurityWindow -WindowHandle $hwnd
        
        # 设置已预热标记
        Set-WarmMarker | Out-Null
        Write-Host "  [*] 预热完成"
        return $true
    }
    
    Write-Host "  [警告] 未找到预热窗口，继续执行..."
    return $false
}

# ============================================================================
# UI Automation Functions - UI自动化函数
# ============================================================================

# 等待UI完全加载
function Wait-UILoaded {
    param(
        [System.Windows.Automation.AutomationElement]$RootElement,
        [int]$MaxRetries = 50
    )
    
    # 多次检查UI元素数量
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            # 查找所有后代元素
            $descendants = $RootElement.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                [System.Windows.Automation.Condition]::TrueCondition
            )
            
            # 如果有足够多的元素，认为UI已加载
            if ($descendants.Count -gt 10) {
                return $true
            }
        }
        catch { }
        
        Start-Sleep -Milliseconds 100
    }
    
    return $false
}

# 获取UI元素数量
function Get-ElementCount {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    try {
        $descendants = $RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        return $descendants.Count
    }
    catch {
        return 0
    }
}

# 等待UI结构变化（用于检测开关状态变化）
function Wait-StructureChange {
    param(
        [System.Windows.Automation.AutomationElement]$RootElement,
        [int]$BaselineCount,
        [bool]$ExpectIncrease,
        [int]$TimeoutSeconds = 10
    )
    
    Write-Host "  [*] 等待UI更新..." -NoNewline
    $maxLoops = $TimeoutSeconds * 10
    
    for ($i = 0; $i -lt $maxLoops; $i++) {
        $currentCount = Get-ElementCount -RootElement $RootElement
        
        # 检查结构是否按预期变化
        $structureChanged = if ($ExpectIncrease) { 
            $currentCount -gt $BaselineCount 
        } else { 
            $currentCount -lt $BaselineCount 
        }
        
        if ($structureChanged) {
            Start-Sleep -Milliseconds 200
            $recheckCount = Get-ElementCount -RootElement $RootElement
            
            # 确认变化稳定
            $stable = if ($ExpectIncrease) { 
                $recheckCount -gt $BaselineCount 
            } else { 
                $recheckCount -lt $BaselineCount 
            }
            
            if ($stable) {
                Write-Host " [完成]"
                return $true
            }
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    Write-Host " [超时]"
    return $false
}

# 查找第一个切换开关（用于实时保护）
function Find-FirstToggleSwitch {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    # 创建条件：查找所有按钮元素
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button
    )
    
    $buttons = $RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
    
    # 查找支持TogglePattern的第一个按钮（切换开关）
    foreach ($button in $buttons) {
        try {
            $togglePattern = $button.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if ($togglePattern) {
                return $button
            }
        }
        catch { }
    }
    
    return $null
}

# 查找最后一个切换开关（用于篡改保护）
function Find-LastToggleSwitch {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button
    )
    
    $buttons = $RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
    $lastToggle = $null
    
    # 查找支持TogglePattern的最后一个按钮
    foreach ($button in $buttons) {
        try {
            $togglePattern = $button.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if ($togglePattern) {
                $lastToggle = $button
            }
        }
        catch { }
    }
    
    return $lastToggle
}

# ============================================================================
# Real-Time Protection Functions - 实时保护函数
# ============================================================================

# 获取实时保护状态
function Get-RTPStatus {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    $button = Find-FirstToggleSwitch -RootElement $RootElement
    if (-not $button) {
        return $null
    }
    
    try {
        $togglePattern = $button.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $state = $togglePattern.Current.ToggleState
        $isEnabled = ($state -eq [System.Windows.Automation.ToggleState]::On)
        
        Write-Host "  [*] 实时保护状态: $(if ($isEnabled) { '已启用' } else { '已禁用' })"
        return $isEnabled
    }
    catch {
        return $null
    }
}

# 启用实时保护
function Enable-RTP {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    # 备份并禁用UAC
    if (-not (Backup-UAC)) {
        return $false
    }
    
    $button = Find-FirstToggleSwitch -RootElement $RootElement
    if (-not $button) {
        Restore-UAC | Out-Null
        return $false
    }
    
    try {
        $togglePattern = $button.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $state = $togglePattern.Current.ToggleState
        
        # 如果当前是关闭状态，则开启
        if ($state -eq [System.Windows.Automation.ToggleState]::Off) {
            $baseline = Get-ElementCount -RootElement $RootElement
            $togglePattern.Toggle()  # 切换开关状态
            $result = Wait-StructureChange -RootElement $RootElement -BaselineCount $baseline -ExpectIncrease $false
        }
        else {
            Write-Host "  [*] 实时保护已启用"
            $result = $true
        }
        
        # 恢复UAC设置
        Restore-UAC | Out-Null
        return $result
    }
    catch {
        Restore-UAC | Out-Null
        return $false
    }
}

# 禁用实时保护
function Disable-RTP {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    if (-not (Backup-UAC)) {
        return $false
    }
    
    $button = Find-FirstToggleSwitch -RootElement $RootElement
    if (-not $button) {
        Restore-UAC | Out-Null
        return $false
    }
    
    try {
        $togglePattern = $button.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $state = $togglePattern.Current.ToggleState
        
        # 如果当前是开启状态，则关闭
        if ($state -eq [System.Windows.Automation.ToggleState]::On) {
            $baseline = Get-ElementCount -RootElement $RootElement
            $togglePattern.Toggle()
            $result = Wait-StructureChange -RootElement $RootElement -BaselineCount $baseline -ExpectIncrease $true
        }
        else {
            Write-Host "  [*] 实时保护已禁用"
            $result = $true
        }
        
        Restore-UAC | Out-Null
        return $result
    }
    catch {
        Restore-UAC | Out-Null
        return $false
    }
}

# ============================================================================
# Tamper Protection Functions - 篡改保护函数
# ============================================================================

# 获取篡改保护状态
function Get-TPStatus {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    $button = Find-LastToggleSwitch -RootElement $RootElement
    if (-not $button) {
        return $null
    }
    
    try {
        $togglePattern = $button.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $state = $togglePattern.Current.ToggleState
        $isEnabled = ($state -eq [System.Windows.Automation.ToggleState]::On)
        
        Write-Host "  [*] 篡改保护状态: $(if ($isEnabled) { '已启用' } else { '已禁用' })"
        return $isEnabled
    }
    catch {
        return $null
    }
}

# 启用篡改保护
function Enable-TP {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    if (-not (Backup-UAC)) {
        return $false
    }
    
    $button = Find-LastToggleSwitch -RootElement $RootElement
    if (-not $button) {
        Restore-UAC | Out-Null
        return $false
    }
    
    try {
        $togglePattern = $button.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $state = $togglePattern.Current.ToggleState
        
        if ($state -eq [System.Windows.Automation.ToggleState]::Off) {
            $baseline = Get-ElementCount -RootElement $RootElement
            $togglePattern.Toggle()
            $result = Wait-StructureChange -RootElement $RootElement -BaselineCount $baseline -ExpectIncrease $false
        }
        else {
            Write-Host "  [*] 篡改保护已启用"
            $result = $true
        }
        
        Restore-UAC | Out-Null
        return $result
    }
    catch {
        Restore-UAC | Out-Null
        return $false
    }
}

# 禁用篡改保护
function Disable-TP {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    
    if (-not (Backup-UAC)) {
        return $false
    }
    
    $button = Find-LastToggleSwitch -RootElement $RootElement
    if (-not $button) {
        Restore-UAC | Out-Null
        return $false
    }
    
    try {
        $togglePattern = $button.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $state = $togglePattern.Current.ToggleState
        
        if ($state -eq [System.Windows.Automation.ToggleState]::On) {
            $baseline = Get-ElementCount -RootElement $RootElement
            $togglePattern.Toggle()
            $result = Wait-StructureChange -RootElement $RootElement -BaselineCount $baseline -ExpectIncrease $true
        }
        else {
            Write-Host "  [*] 篡改保护已禁用"
            $result = $true
        }
        
        Restore-UAC | Out-Null
        return $result
    }
    catch {
        Restore-UAC | Out-Null
        return $false
    }
}

# ============================================================================
# Process Single Command - 处理单个命令
# ============================================================================

# 处理单个命令（rtp或tp）
function Process-SingleCommand {
    param(
        [string]$Cmd,
        [string]$Act
    )
    
    Write-Host ""
    Write-Host "=== Windows Defender $(if ($Cmd -eq 'rtp') { '实时保护' } else { '篡改保护' })控制 ===" -ForegroundColor Cyan
    Write-Host ""

    # 检查并恢复之前可能不完整的UAC备份（防止脚本意外终止）
    Recover-UACIfNeeded | Out-Null

    Write-Host "  [*] 正在打开Windows Defender..."

    # 冷启动时进行预热
    if (Test-ColdBoot) {
        Invoke-PreWarmDefender | Out-Null
        Start-Sleep -Milliseconds 800
    }

    # 打开Windows安全设置
    Start-Process "windowsdefender://threatsettings" -WindowStyle Hidden
    $hwndSecurity = Find-SecurityWindow -MaxRetries 10

    if (-not $hwndSecurity) {
        Write-Host "  [错误] 未能找到Windows安全窗口" -ForegroundColor Red
        return $false
    }

    # 获取UI自动化根元素
    try {
        $rootElement = [System.Windows.Automation.AutomationElement]::FromHandle($hwndSecurity)
    }
    catch {
        Write-Host "  [错误] 无法获取自动化元素" -ForegroundColor Red
        Close-SecurityWindow -WindowHandle $hwndSecurity
        return $false
    }

    # 等待UI加载
    if (-not (Wait-UILoaded -RootElement $rootElement -MaxRetries 50)) {
        Write-Host "  [错误] 加载UI失败（系统响应缓慢，超时）" -ForegroundColor Red
        Close-SecurityWindow -WindowHandle $hwndSecurity
        return $false
    }

    # 执行请求的操作
    $result = $false

    if ($Cmd -eq 'rtp') {
        switch ($Act) {
            'status' { 
                $result = (Get-RTPStatus -RootElement $rootElement) -ne $null
            }
            'on' { 
                $result = Enable-RTP -RootElement $rootElement
            }
            'off' { 
                $result = Disable-RTP -RootElement $rootElement
            }
        }
    }
    elseif ($Cmd -eq 'tp') {
        switch ($Act) {
            'status' { 
                $result = (Get-TPStatus -RootElement $rootElement) -ne $null
            }
            'on' { 
                $result = Enable-TP -RootElement $rootElement
            }
            'off' { 
                $result = Disable-TP -RootElement $rootElement
            }
        }
    }

    # 关闭安全窗口
    Close-SecurityWindow -WindowHandle $hwndSecurity

    return $result
}

# ============================================================================
# Main Execution Flow - 主执行流程
# ============================================================================

$overallResult = $true

# 处理"all"命令（同时操作RTP和TP）
if ($Command -eq 'all') {
    Write-Host ""
    Write-Host "=== Windows Defender 全面控制 ($Action) ===" -ForegroundColor Cyan
    Write-Host ""
    
    if ($Action -eq 'status') {
        # 查看RTP状态
        $rtpResult = Process-SingleCommand -Cmd 'rtp' -Act 'status'
        
        Write-Host ""
        Write-Host "---" -ForegroundColor DarkGray
        
        # 查看TP状态
        $tpResult = Process-SingleCommand -Cmd 'tp' -Act 'status'
        
        $overallResult = $rtpResult -and $tpResult
    }
    else {
        # 处理RTP操作
        Write-Host "[1/2] 处理实时保护 ($Action)..." -ForegroundColor Cyan
        $rtpResult = Process-SingleCommand -Cmd 'rtp' -Act $Action
        
        Write-Host ""
        Write-Host "--- 等待1秒 ---" -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
        
        # 处理TP操作
        Write-Host "[2/2] 处理篡改保护 ($Action)..." -ForegroundColor Cyan
        $tpResult = Process-SingleCommand -Cmd 'tp' -Act $Action
        
        $overallResult = $rtpResult -and $tpResult
        
        # 显示执行摘要
        Write-Host ""
        Write-Host "=== 执行摘要 ===" -ForegroundColor Cyan
        Write-Host "  [*] 实时保护 ($Action): $(if ($rtpResult) { '成功' } else { '失败' })" -ForegroundColor $(if ($rtpResult) { 'Green' } else { 'Red' })
        Write-Host "  [*] 篡改保护 ($Action): $(if ($tpResult) { '成功' } else { '失败' })" -ForegroundColor $(if ($tpResult) { 'Green' } else { 'Red' })
    }
}
else {
    # 处理单个命令
    $overallResult = Process-SingleCommand -Cmd $Command -Act $Action
}

# 显示最终结果
Write-Host ""
Write-Host "  [*] 操作完成。" -ForegroundColor $(if ($overallResult) { 'Green' } else { 'Yellow' })
Write-Host ""

# 返回退出码：0=成功，1=失败
exit $(if ($overallResult) { 0 } else { 1 })