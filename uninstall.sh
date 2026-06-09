#!/bin/bash
PLIST="com.penrithbeacon.markdown-editor-agent.plist"
launchctl unload "$HOME/Library/LaunchAgents/$PLIST" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$PLIST"
rm -rf "/Applications/Markdown Editor Agent.app"
echo "wcp-agent-markdown-editor uninstalled."
