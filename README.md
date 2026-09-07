# SxSCleaner 一个高度自由定制化的系统精简工具。
## 旨在保证 Windows 功能可正常启用或禁用的前提下，有效减少 install.wim 或在线系统的占用。移除的方式：组件移除+直接删除（不存在组件的情况）

## 使用说明

运行以下cmd，即可全自动处理 离线镜像 或者 在线系统

* 1WinSxS清理_在线.cmd      处理在线系统
* 2WinSxS清理_离线.cmd      处理离线镜像
* 3离线添加OriginSetup.cmd  添加无人值守 部署脚本 OriginSetup （可选）

## 使用配置

* SxSExportConfig.ini              配置文件
* AppxList.txt                     预装应用列表
* FunctionList.txt                 可选功能列表
* WinSxSList\XXX\ImportList.txt    移除组件列表
* WinSxSList\XXX\RetainList.txt    保留组件列表

* 其中 XXX 代表版本号，比如6.1、10.0等

## 目录说明

* WinSxSList\Custom：定制专属的List, 可以按需修改
	```
	DisFeatureList.txt：    Windows 功能禁用
	EnFeatureList.txt：     Windows 功能启用
	
	ExtraWinSxSList.txt：   额外保留的 WinSxS 文件夹
	FileRetainList.txt：    保留必要的文件
	FolderRetainList.txt：  保留必要的文件夹
	
	DelFilesList.txt：      删除 非组件 的文件夹或文件

	IISFilesList.txt：      IIS 组件包含的文件
	IISFoldersList.txt：    IIS 组件包含的WinSxS文件夹
	            
	SystemApps.txt：        Windows 10中，可以删除的 SystemApps
	```

* WinSxSList：以下列表是自动生成，无需修改。这里只是作一下解释说明，可不必理会

	```  
	1.WinSxSFiles.txt：         由 ImportList.txt 生成的 可移除文件夹和文件（组件形式）
	
	2.multilang.txt：           多语言、键盘布局的文件夹及文件等
	
	3.DelFiles.txt：            由 Custom\DelFilesList.txt 生成的 可移除文件夹和文件（非组件形式）

	4.DelWinSxSFolders.txt：    保留需要的功能列表，进行WinSxS文件夹精简，Windows 功能可正常启用或禁用
	5.DelVerWinSxSFolders.txt： 在 DelWinSxSFolders.txt 的基础上，清理低版本的组件，Windows 功能可正常启用或禁用
	
	6.DelUltWinSxS.txt：        最小WinSxS文件夹占用列表，Windows 功能不可正常启用或禁用
	
	7.DelEmptyFolders.txt：     由 WinSxSFiles.txt 生成的 空文件夹
	```

* WinSXS_Clean_Offline.log  离线日志
* WinSXS_Clean_Online.log   在线日志
