-- ===========================
-- ⚙️ 配置区域 (Configuration)
-- ===========================

-- 1. 调试开关: 设置为 true 会在桌面生成 btt_debug_log.txt，日常使用建议设为 false
set debugMode to true 

-- 2. 白名单配置 (Whitelist Configuration)
-- ===================================
-- 2.1 基于 Bundle ID 的白名单 (推荐，最精确)
-- 如何找到 Bundle ID? 开启 debugMode，日志中会打印 "当前应用: ... (com.xx.yy)"，括号中的就是 ID
set keepAliveAppIDs to {"com.tencent.xinwei", "com.tencent.qq", "com.tencent.qqmusic", "com.spotify.client", "com.apple.Music", "com.meta.Telegram", "md.obsidian"}

-- 2.2 基于进程名的白名单 (备用)
-- 适用于没有固定 Bundle ID 或不方便查询的传统应用
set keepAliveApps to {"Finder", "OrbStack", "QSpace Pro", "WeChat", "QQ", "QQMusic", "WeType", "Hammerspoon", "Swish", "Bob", "Ice", "PopClip", "Pixelmator Pro", "Sketch", "ZeroTier", "ClashX Meta", "v2rayN", "ClashX Pro", "Longshot", "BetterTouchTool", "DingTalk"}



-- ===========================
-- 📝 日志处理程序
-- ===========================
on logInfo(msg, debugMode)
    if debugMode is true then
        try
            set logPath to (path to desktop as text) & "btt_debug_log.txt"
            set logText to (do shell script "date '+%Y-%m-%d %H:%M:%S' ") & " | " & msg & return

            -- 使用 shell 命令以 UTF-8 编码写入，避免 AppleScript 的编码问题
            do shell script "echo " & quoted form of logText & " >> " & quoted form of (POSIX path of logPath)

        on error errMsg
            -- 备用方案：如果 shell 命令失败，使用原来的方法
            try
                set logPath to (path to desktop as text) & "btt_debug_log.txt"
                set fileRef to open for access file logPath with write permission
                write logText to fileRef starting at eof
                close access fileRef
            on error
                try
                    close access file logPath
                end try
            end try
        end try
    end if
end logInfo

-- ===========================
-- 🚀 增强的退出函数
-- ===========================
on quitApplicationSafely(appID, appName, debugMode)
    try
        my logInfo("🔄 开始退出应用: " & appName, debugMode)

        -- 第一次尝试退出
        tell application id appID to quit

        -- 等待应用响应
        delay 0.3

        -- 检查应用是否已退出
        tell application "System Events"
            if not (exists application process appName) then
                my logInfo("✅ 应用已成功退出: " & appName, debugMode)
                return true
            end if

            -- 应用仍在运行，检查是否有对话框 (改进：检查 sheet)
            try
                tell application process appName
                    if exists sheet 1 of window 1 then
                        my logInfo("💾 发现 sheet 对话框（很可能是保存提示），让用户自行处理", debugMode)
                        return false -- 发现未保存对话框，让用户选择如何处理
                    end if
                end tell
            end try
        end tell

        -- 第二次尝试退出
        tell application id appID to quit
        delay 0.3

        -- 最终检查
        tell application "System Events"
            if not (exists application process appName) then
                my logInfo("✅ 应用最终退出成功: " & appName, debugMode)
                return true
            else
                my logInfo("⚠️ 应用仍在运行，退出失败: " & appName, debugMode)
                return false
            end if
        end tell

    on error errMsg
        my logInfo("❌ 退出过程出错: " & errMsg, debugMode)
        return false
    end try
end quitApplicationSafely

-- ===========================
-- 🚀 核心逻辑
-- ===========================
set shouldQuit to false
set targetAppID to ""
set procName to ""
set bundleID_from_btt to ""

my logInfo("----------------------------------------", debugMode)
my logInfo("🚀 脚本开始执行...", debugMode)

-- 主动从 BTT 获取 Bundle ID
try
	tell application "BetterTouchTool"
		set bundleID_from_btt to get_string_variable "BTTActiveAppBundleIdentifier"
	end tell
on error
	my logInfo("❌ 错误：无法连接到 BetterTouchTool 或获取 BTTActiveAppBundleIdentifier 变量。", debugMode)
	return
end try

if bundleID_from_btt is "" then
	my logInfo("❌ 错误：从 BTT 获取的 Bundle ID 为空，脚本终止。", debugMode)
	return
end if
my logInfo("👉 BTT 变量 BTTActiveAppBundleIdentifier: " & bundleID_from_btt, debugMode)


tell application "System Events"
	try
		-- 恢复被删除的逻辑：通过 Bundle ID 查找进程
		set matchingProcesses to (application processes where bundle identifier is bundleID_from_btt)
		if (count of matchingProcesses) is 0 then
			my logInfo("❌ 错误：未找到 Bundle ID 为 " & bundleID_from_btt & " 的应用进程，脚本终止。", debugMode)
			return
		end if
		set frontProcess to first item of matchingProcesses
		
		-- 获取应用信息
		set procName to name of frontProcess
		set appPath to ""
		set targetAppID to bundle identifier of frontProcess
		set appVersion to "Unknown"
		
		try
			set appPath to posix path of application file of frontProcess
		on error
			set appPath to ""
		end try
		
		-- 获取应用版本 (更可靠的方法)
		if appPath is not "" then
			try
				set plistPath to quoted form of (appPath & "/Contents/Info.plist")
				set appVersion to do shell script "defaults read " & plistPath & " CFBundleShortVersionString"
			on error
				-- 如果获取 CFBundleShortVersionString 失败，尝试 CFBundleVersion
				try
					set plistPath to quoted form of (appPath & "/Contents/Info.plist")
					set appVersion to do shell script "defaults read " & plistPath & " CFBundleVersion"
				on error
					set appVersion to "Not Available"
				end try
			end try
		else
			set appVersion to "Not Available"
		end if
		
		my logInfo("📱 目标应用信息: " & procName & " (ID: " & targetAppID & ", Version: " & appVersion & ") Path: " & appPath, debugMode)
		
		-- 决策逻辑
		if targetAppID is not "Unknown" and keepAliveAppIDs contains targetAppID then
			set shouldQuit to false
			my logInfo("🛡️ 命中 Bundle ID 白名单 (" & targetAppID & ")，强制不退出", debugMode)
		else if keepAliveApps contains procName then
			set shouldQuit to false
			my logInfo("🛡️ 命中进程名白名单 (" & procName & ")，强制不退出", debugMode)
		else
			-- 检查当前窗口是否为非标准窗口 (如偏好设置、关于等)
			set isNonStandardWindow to false
			try
				tell frontProcess
					if exists window 1 then
						if subrole of window 1 is not "AXStandardWindow" then
							set isNonStandardWindow to true
						end if
					end if
				end tell
			on error
				set isNonStandardWindow to false
			end try

			if isNonStandardWindow is true then
				set shouldQuit to false
				my logInfo("🛡️ 当前窗口非标准窗口 (非 AXStandardWindow)，仅关闭不退出", debugMode)
			else
				try
					set standardWindowCount to count of (windows of frontProcess where subrole is "AXStandardWindow")
				on error
					set standardWindowCount to 999
				end try
				
				my logInfo("🪟 标准窗口数量: " & standardWindowCount, debugMode)
				
				if standardWindowCount is less than or equal to 1 then
					set shouldQuit to true
					my logInfo("✅ 判定: 最后一个窗口，准备退出", debugMode)
				else
					set shouldQuit to false
					my logInfo("❌ 判定: 还有其他窗口 (" & standardWindowCount & "个)，仅关闭当前", debugMode)
				end if
			end if
		end if
		
		-- ===========================
		-- 💥 执行动作 (已移入此块)
		-- ===========================
		
		if shouldQuit is true then
			my logInfo("💀 执行动作: QUIT Application", debugMode)
			
			-- 使用增强的退出函数
			if targetAppID is not "Unknown" and targetAppID is not "" then
				set quitSuccess to my quitApplicationSafely(targetAppID, procName, debugMode)
			else
				my logInfo("⚠️ Bundle ID 未知，使用进程名退出: " & procName, debugMode)
				set quitSuccess to my quitApplicationSafely(procName, procName, debugMode)
			end if
			
			-- 如果退出函数返回 false，记录日志
			if quitSuccess is false then
				my logInfo("⚠️ 应用退出受阻，可能存在保存对话框，让用户处理", debugMode)
			end if
			
		else -- shouldQuit is false (meaning close current window)
			my logInfo("👋 执行动作: Close Window", debugMode)
			
			-- frontProcess 变量在此处可用
			tell frontProcess
				if exists window 1 then
					set windowClosed to false
					
					-- 方法1: 尝试点击标准的关闭按钮
					try
						if exists (button 1 of window 1 where subrole is "AXCloseButton") then
							click (button 1 of window 1 where subrole is "AXCloseButton")
							set windowClosed to true
							my logInfo("✅ 方法1: 点击关闭按钮成功", debugMode)
						end if
					end try
					
					-- 方法2: 尝试 close 命令
					if windowClosed is false then
						try
							close window 1
							set windowClosed to true
							my logInfo("✅ 方法2: 使用 'close' 命令成功", debugMode)
						on error
							my logInfo("⚠️ 'close' 命令失败", debugMode)
						end try
					end if
					
					-- 方法3: 使用键盘快捷键
					if windowClosed is false then
						my logInfo("⚠️ 备用方案: 使用 Cmd+W", debugMode)
						keystroke "w" using command down
					end if
				else
					my logInfo("⚠️ 没有找到可关闭的窗口", debugMode)
				end if
			end tell -- end tell frontProcess
		end if
		
	on error errMsg
		set shouldQuit to false
		my logInfo("🔥 严重错误: " & errMsg, debugMode)
	end try
end tell

my logInfo("🏁 脚本结束", debugMode)
