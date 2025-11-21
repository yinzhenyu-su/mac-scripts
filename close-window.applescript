-- ===========================
-- ⚙️ 配置区域 (Configuration)
-- ===========================

-- 1. 调试开关: 设置为 true 会在桌面生成 btt_debug_log.txt，日常使用建议设为 false
set debugMode to true 

-- 2. 白名单: 这些应用只关闭窗口，永远不自动退出
set keepAliveApps to {"WeChat", "QQ", "QQMusic", "Finder", "Electron", "Hammerspoon", "Swish", "Bob", "Ice", "PopClip", "ZeroTier", "ClashX Meta", "ClashX Pro", "Longshot", "BetterTouchTool", "Telegram", "Spotify", "Music", "DingTalk", "Obsidian"}

-- 2.1 特殊进程名列表: 这些进程名需要特殊处理（使用 Bundle ID 精确定位避免混淆）
set specialProcNames to {"Electron"}

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
        delay 0.1

        -- 检查应用是否已退出
        tell application "System Events"
            if not (exists application process appName) then
                my logInfo("✅ 应用已成功退出: " & appName, debugMode)
                return true
            end if

            -- 应用仍在运行，检查是否有对话框
            try
                tell application process appName
                    if exists window 1 then
                        set windowTitle to title of window 1
                        my logInfo("🪟 发现窗口: " & windowTitle, debugMode)

                        -- 检测保存对话框，让用户自己处理
                        if windowTitle contains "保存" or windowTitle contains "Save" then
                            my logInfo("💾 发现保存对话框，让用户自行处理", debugMode)
                            return false -- 让用户选择如何处理退出逻辑
                        end if
                    end if
                end tell
            end try
        end tell

        -- 第二次尝试退出
        tell application id appID to quit
        delay 0.1

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

my logInfo("----------------------------------------", debugMode)
my logInfo("🚀 脚本开始执行...", debugMode)

tell application "System Events"
    try
    -- 1. 获取前台应用信息
        set frontProcess to first application process whose frontmost is true
        set procName to name of frontProcess
        set appPath to ""
        
        try
            set appPath to posix path of application file of frontProcess
        on error
            set appPath to ""
        end try
        
        try
            set targetAppID to bundle identifier of frontProcess
        on error
            set targetAppID to "Unknown"
        end try
        
        my logInfo("📱当前应用: " & procName & " (" & targetAppID & ") Path: " & appPath, debugMode)

        -- 2. 特殊进程名检查优先（确保这些应用永远不关闭窗口）
        if specialProcNames contains procName then
            -- 特殊进程名处理：发送通知并退出脚本，不做任何窗口操作
            my logInfo("⚡ 检测到特殊进程名应用: " & procName & " (" & targetAppID & ")", debugMode)

            -- 发送通知（带错误处理）
            try
                display notification "无法处理当前应用「" & procName & "」，请加入到 btt 触发白名单" with title "BTT 窗口管理"
                my logInfo("📢 通知已发送", debugMode)
            on error errMsg
                my logInfo("❌ 通知发送失败: " & errMsg, debugMode)
                -- 备用方案：在日志中提醒
                my logInfo("⚠️ 请手动将 " & procName & " 添加到 BTT 触发白名单", debugMode)
            end try

            my logInfo("🏁 脚本结束（特殊进程名应用，仅通知）", debugMode)
            return
        else if keepAliveApps contains procName then
            -- 白名单应用：只关闭窗口，永远不自动退出
            set shouldQuit to false
            my logInfo("🛡️ 命中白名单，强制不退出", debugMode)
        else
            -- 3. 窗口计数逻辑 (基于 AXStandardWindow)
            -- 既然 VS Code 已开启 Native Title Bar，它就像原生应用一样拥有标准窗口属性
            -- 这能精确区分主窗口和隐藏窗口/弹窗
            
            try
                set standardWindowCount to count of (windows of frontProcess where subrole is "AXStandardWindow")
            on error
                set standardWindowCount to 999 -- 获取失败防止误退
            end try
            
            my logInfo("🪟 标准窗口数量: " & standardWindowCount, debugMode)
            
            -- 只有当标准窗口数量 <= 1 时，才退出
            if standardWindowCount is less than or equal to 1 then
                set shouldQuit to true
                my logInfo("✅ 判定: 最后一个窗口，准备退出", debugMode)
            else
                set shouldQuit to false
                my logInfo("❌ 判定: 还有其他窗口 (" & standardWindowCount & "个)，仅关闭当前", debugMode)
            end if
            
        end if
        
    on error errMsg
        set shouldQuit to false
        my logInfo("🔥 严重错误: " & errMsg, debugMode)
    end try
end tell

-- ===========================
-- 💥 执行动作
-- ===========================

if shouldQuit is true then
    my logInfo("💀 执行动作: QUIT Application", debugMode)

    -- 安全验证：再次确认当前前台应用是否仍然是目标应用
    tell application "System Events"
        try
            set currentFrontProcess to first application process whose frontmost is true
            set currentProcName to name of currentFrontProcess
            set currentAppID to bundle identifier of currentFrontProcess

            my logInfo("🔍 安全验证 - 当前前台: " & currentProcName & " (" & currentAppID & ")", debugMode)
            my logInfo("🎯 目标应用: " & procName & " (" & targetAppID & ")", debugMode)

            -- 验证应用身份是否匹配
            if currentProcName is procName and currentAppID is targetAppID then
                my logInfo("✅ 身份验证通过，安全退出应用", debugMode)

                -- 使用增强的退出函数
                if targetAppID is not "Unknown" and targetAppID is not "" then
                    set quitSuccess to my quitApplicationSafely(targetAppID, procName, debugMode)
                else
                    my logInfo("⚠️ Bundle ID 未知，使用进程名退出: " & procName, debugMode)
                    set quitSuccess to my quitApplicationSafely(procName, procName, debugMode)
                end if

                -- 如果退出函数返回 false（通常是因为有保存对话框），不强制退出
                if quitSuccess is false then
                    my logInfo("⚠️ 应用退出受阻，可能存在保存对话框，让用户处理", debugMode)
                end if
            else
                my logInfo("🚨 安全验证失败！前台应用已改变，取消退出操作", debugMode)
                my logInfo("🔄 可能的原因：用户切换了应用或系统延迟", debugMode)
            end if

        on error errMsg
            my logInfo("🔥 安全验证过程出错: " & errMsg, debugMode)
            my logInfo("🔄 为安全起见，取消退出操作", debugMode)
        end try
    end tell

else
    my logInfo("👋 执行动作: Close Window (Cmd+W)", debugMode)
    -- 仅关闭窗口（使用系统级窗口关闭命令，避免标签页问题）
    tell application "System Events"
        -- 确保焦点
        try
            set frontmost of application process procName to true
        end try

        -- 使用系统级窗口关闭，而不是键盘快捷键
        try
            tell application process procName
                if exists window 1 then
                    -- 尝试方法1：使用 AppleScript 的 close 命令
                    try
                        close window 1
                        my logInfo("✅ 使用 close 命令成功关闭窗口", debugMode)
                    on error
                        -- 尝试方法2：点击窗口的关闭按钮
                        try
                            click button 1 of window 1 where subrole is "AXCloseButton"
                            my logInfo("✅ 使用点击关闭按钮成功关闭窗口", debugMode)
                        on error
                            -- 备用方案：使用键盘快捷键
                            my logInfo("⚠️ 备用方案：使用 Cmd+W", debugMode)
                            keystroke "w" using command down
                        end try
                    end try
                else
                    my logInfo("⚠️ 没有找到可关闭的窗口", debugMode)
                end if
            end tell
        on error errMsg
            my logInfo("❌ 窗口关闭失败: " & errMsg, debugMode)
            -- 最后的备用方案
            try
                keystroke "w" using command down
            end try
        end try
    end tell
end if

my logInfo("🏁 脚本结束", debugMode)