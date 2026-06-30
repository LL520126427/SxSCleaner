# 定义要卸载的AppX应用列表
# $remove_appx = @("SecHealthUI")
# 接收参数：传入要卸载的AppX列表
param(
    [Parameter(Mandatory=$true)]
    [string[]]$remove_appx
)

# 获取系统预配的AppX包和所有用户已安装的AppX包
$provisioned = get-appxprovisionedpackage -online
$appxpackage = get-appxpackage -allusers
$eol = @()  # 存储已处理的应用包名称

# AppX应用商店注册表路径
$store = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore'

# 获取所有用户SID列表（包括系统账户和普通用户）
$users = @('S-1-5-18')
if (test-path $store) {
    $users += $((dir $store -ea 0 | where { $_ -like '*S-1-5-21*' }).PSChildName)
}

# 主循环：处理每个要卸载的应用
foreach ($choice in $remove_appx) {
    # 跳过空项
    if ('' -eq $choice.Trim()) {
        continue
    }

    # 处理系统预配的AppX包
    foreach ($appx in $($provisioned | where { $_.PackageName -like "*$choice*" })) {
        # 检查是否跳过当前包（使用未定义的$skip变量）
        $next = !1
        foreach ($no in $skip) {
            if ($appx.PackageName -like "*$no*") {
                $next = !0
            }
        }
        if ($next) {
            continue
        }

        # 获取包名称和包系列名称
        $PackageName = $appx.PackageName
        $PackageFamilyName = ($appxpackage | where { $_.Name -eq $appx.DisplayName }).PackageFamilyName

        # 在注册表中标记应用为停用状态
        ni "$store\Deprovisioned\$PackageFamilyName" -force >''

        # 为所有用户标记应用为停用
        foreach ($sid in $users) {
            ni "$store\EndOfLife\$sid\$PackageName" -force >''
        }
        $eol += $PackageName

        # 设置应用为可移除
        dism /online /set-nonremovableapppolicy /packagefamily:$PackageFamilyName /nonremovable:0 >''

        # 移除系统预配包
        remove-appxprovisionedpackage -packagename $PackageName -online -allusers >''
    }

    # 处理已安装的AppX包
    foreach ($appx in $($appxpackage | where { $_.PackageFullName -like "*$choice*" })) {
        # 检查是否跳过当前包（使用未定义的$skip变量）
        $next = !1
        foreach ($no in $skip) {
            if ($appx.PackageFullName -like "*$no*") {
                $next = !0
            }
        }
        if ($next) {
            continue
        }

        # 获取完整包名称
        $PackageFullName = $appx.PackageFullName

        # 在注册表中标记应用为停用状态
        ni "$store\Deprovisioned\$appx.PackageFamilyName" -force >''

        # 为所有用户标记应用为停用
        foreach ($sid in $users) {
            ni "$store\EndOfLife\$sid\$PackageFullName" -force >''
        }
        $eol += $PackageFullName

        # 设置应用为可移除
        dism /online /set-nonremovableapppolicy /packagefamily:$PackageFamilyName /nonremovable:0 >''

        # 移除用户已安装的应用包
        remove-appxpackage -package $PackageFullName -allusers >''
    }
}