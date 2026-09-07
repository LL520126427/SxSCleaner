@echo off

set "base_keyboard=00409 kbdus"
set "base_lang=en-US qps"

if /i [%~1]==[zh-CN] (
	set "cur_keyboard=00804"
	set "cur_lang=zh-CHS zh-HANS %~1"
)

exit /b