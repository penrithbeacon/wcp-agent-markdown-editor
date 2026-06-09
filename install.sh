#!/bin/bash
set -e
echo "Installing wcp-agent-markdown-editor..."

PLIST="com.penrithbeacon.markdown-editor-agent.plist"
APP="Markdown Editor Agent.app"
LOG_DIR="$HOME/Library/Logs/markdown-editor-agent"

# Copy app
if [ -d "dist/$APP" ]; then
  cp -r "dist/$APP" "/Applications/$APP"
  echo "✓ App installed to /Applications"
else
  echo "✗ dist/$APP not found — run build-app.sh first"
  exit 1
fi

# LaunchAgent
mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST" "$HOME/Library/LaunchAgents/$PLIST"
echo "✓ LaunchAgent plist installed"

# Fix log path in plist to use actual home dir
sed -i '' "s|/Users/Shared/Logs|$HOME/Library/Logs|g" \
  "$HOME/Library/LaunchAgents/$PLIST"

# Log dir
mkdir -p "$LOG_DIR"
echo "✓ Log directory created at $LOG_DIR"

# Load
launchctl load "$HOME/Library/LaunchAgents/$PLIST"
echo "✓ Agent loaded and started"
echo ""
echo "Verify: curl -s http://127.0.0.1:3749/health | python3 -m json.tool"
