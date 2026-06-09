-- Uninstall WCP Markdown Editor Agent
-- Removes the agent app, LaunchAgent plist, log files, and this uninstaller.

on run
    set agentApp      to "/Applications/Markdown Editor Agent.app"
    set uninstallerApp to "/Applications/Uninstall WCP Markdown Editor Agent.app"
    set plistLabel    to "com.penrithbeacon.markdown-editor-agent"
    set logsDir       to (POSIX path of (path to home folder)) & "Library/Logs/markdown-editor-agent"
    set launchAgentDir to (POSIX path of (path to home folder)) & "Library/LaunchAgents/"
    set plistPath     to launchAgentDir & plistLabel & ".plist"

    -- Confirmation dialog
    set msg to "This will uninstall the Markdown Editor Agent.

The following will be removed:
  • Markdown Editor Agent.app
  • LaunchAgent: " & plistLabel & "
  • Log files in ~/Library/Logs/markdown-editor-agent
  • This uninstaller app

Continue?"

    try
        set choice to button returned of (display dialog msg ¬
            buttons {"Cancel", "Uninstall"} ¬
            default button "Uninstall" ¬
            cancel button "Cancel" ¬
            with icon caution ¬
            with title "Uninstall WCP Markdown Editor Agent")
    on error
        -- User cancelled
        return
    end try

    if choice is not "Uninstall" then return

    -- Build the shell script that does the actual removal
    set shellScript to "
set -e

# Stop and remove LaunchAgent
if [ -f '" & plistPath & "' ]; then
    launchctl unload '" & plistPath & "' 2>/dev/null || true
    rm -f '" & plistPath & "'
fi

# Remove log files (no admin needed — user-owned)
rm -rf '" & logsDir & "'

# Remove app bundles from /Applications (requires admin)
rm -rf '" & agentApp & "'
rm -rf '" & uninstallerApp & "'
"

    try
        do shell script shellScript with administrator privileges
    on error errMsg number errNum
        if errNum is -128 then
            -- User cancelled the admin password prompt
            return
        end if
        display dialog "Uninstall failed: " & errMsg ¬
            buttons {"OK"} default button "OK" ¬
            with icon stop ¬
            with title "Uninstall Failed"
        return
    end try

    display dialog "Markdown Editor Agent has been successfully uninstalled." ¬
        buttons {"OK"} default button "OK" ¬
        with title "Uninstall Complete"
end run
