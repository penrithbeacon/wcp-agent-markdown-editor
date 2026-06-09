#!/bin/bash
# Build wcp-agent-markdown-editor.pkg — a macOS installer for the Markdown Editor companion agent.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== wcp-agent-markdown-editor.pkg builder ==="
echo ""

# ── Step 1: Build .app with py2app ──────────────────────────────────────────
echo "→ Step 1: Building .app bundle with py2app..."
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip -q
pip install flask flask-cors py2app -q
python3 setup.py py2app 2>&1 | tail -5
deactivate
if [ ! -d "dist/Markdown Editor Agent.app" ]; then
  echo "✗ Build failed — dist/Markdown Editor Agent.app not found"
  exit 1
fi
echo "✓ App bundle ready: dist/Markdown Editor Agent.app"
echo ""

# ── Step 2: Create staging root ──────────────────────────────────────────────
echo "→ Step 2: Creating staging root..."
PKG_ROOT=/tmp/wcp-agent-pkg-root
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"

# Copy agent .app bundle
cp -r "dist/Markdown Editor Agent.app" "$PKG_ROOT/Applications/"

# py2app builds with drwx------ (700); fix to 755 so the installed app is usable
chmod -R 755 "$PKG_ROOT/Applications/Markdown Editor Agent.app"

# Embed the plist inside the .app Resources so the postinstall script can find it
RESOURCES_DIR="$PKG_ROOT/Applications/Markdown Editor Agent.app/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
cp com.penrithbeacon.markdown-editor-agent.plist "$RESOURCES_DIR/"
echo "✓ Agent app staged"

# ── Step 2b: Build uninstaller .app ──────────────────────────────────────────
echo "→ Step 2b: Building uninstaller app from AppleScript..."
UNINSTALL_TMP="/tmp/Uninstall WCP Markdown Editor Agent.app"
UNINSTALL_DST="$PKG_ROOT/Applications/Uninstall WCP Markdown Editor Agent.app"
rm -rf "$UNINSTALL_TMP"
osacompile -o "$UNINSTALL_TMP" uninstall.applescript
if [ ! -d "$UNINSTALL_TMP" ]; then
  echo "✗ Uninstaller build failed"
  exit 1
fi
cp -r "$UNINSTALL_TMP" "$PKG_ROOT/Applications/"
chmod -R 755 "$UNINSTALL_DST"
echo "✓ Uninstaller app ready: $UNINSTALL_DST"
echo "✓ Staging root ready: $PKG_ROOT"
echo ""

# ── Step 3: Create postinstall script ────────────────────────────────────────
echo "→ Step 3: Creating installer scripts..."
PKG_SCRIPTS=/tmp/wcp-agent-pkg-scripts
rm -rf "$PKG_SCRIPTS"
mkdir -p "$PKG_SCRIPTS"

cat > "$PKG_SCRIPTS/postinstall" << 'ENDSCRIPT'
#!/bin/bash
# Determine the logged-in console user (not root)
LOGGED_IN_USER=$(stat -f%Su /dev/console 2>/dev/null)
if [ -z "$LOGGED_IN_USER" ] || [ "$LOGGED_IN_USER" = "root" ]; then
  LOGGED_IN_USER=$(who | grep console | awk '{print $1}' | head -1)
fi
if [ -z "$LOGGED_IN_USER" ]; then
  echo "postinstall: could not determine logged-in user" >&2
  exit 1
fi
USER_HOME=$(eval echo ~"$LOGGED_IN_USER")
LOGGED_IN_UID=$(id -u "$LOGGED_IN_USER")
echo "postinstall: installing for $LOGGED_IN_USER (uid=$LOGGED_IN_UID, home=$USER_HOME)"

# Create directories
sudo -u "$LOGGED_IN_USER" mkdir -p "$USER_HOME/Library/LaunchAgents"
sudo -u "$LOGGED_IN_USER" mkdir -p "$USER_HOME/Library/Logs/markdown-editor-agent"

# Install launchd plist, substituting actual home path for log files
PLIST_SRC="/Applications/Markdown Editor Agent.app/Contents/Resources/com.penrithbeacon.markdown-editor-agent.plist"
PLIST_DST="$USER_HOME/Library/LaunchAgents/com.penrithbeacon.markdown-editor-agent.plist"
cp "$PLIST_SRC" "$PLIST_DST"
sed -i '' "s|/Users/Shared/Logs|$USER_HOME/Library/Logs|g" "$PLIST_DST"
chown "$LOGGED_IN_USER" "$PLIST_DST"
echo "postinstall: plist installed at $PLIST_DST"

# Fix ownership and permissions on the agent .app bundle.
# pkgbuild preserves source permissions; py2app builds drwx------ (owner-only).
# Without this the logged-in user cannot enter the bundle or execute the binary.
APP="/Applications/Markdown Editor Agent.app"
chown -R "$LOGGED_IN_USER:staff" "$APP"
chmod -R 755 "$APP"
echo "postinstall: fixed ownership and permissions on $APP"

# Fix ownership and permissions on the uninstaller .app.
UNINSTALL_APP="/Applications/Uninstall WCP Markdown Editor Agent.app"
if [ -d "$UNINSTALL_APP" ]; then
  chown -R "$LOGGED_IN_USER:staff" "$UNINSTALL_APP"
  chmod -R 755 "$UNINSTALL_APP"
  echo "postinstall: fixed ownership and permissions on $UNINSTALL_APP"
fi

# Load the LaunchAgent for the logged-in user
launchctl bootstrap "gui/$LOGGED_IN_UID" "$PLIST_DST" 2>/dev/null \
  || sudo -u "$LOGGED_IN_USER" launchctl load "$PLIST_DST" 2>/dev/null \
  || echo "postinstall: note — agent will auto-start on next login"

echo "postinstall: complete"
exit 0
ENDSCRIPT
chmod +x "$PKG_SCRIPTS/postinstall"

cat > "$PKG_SCRIPTS/preinstall" << 'ENDSCRIPT'
#!/bin/bash
# Unload any existing instance before installing
LOGGED_IN_USER=$(stat -f%Su /dev/console 2>/dev/null)
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ]; then
  USER_HOME=$(eval echo ~"$LOGGED_IN_USER")
  PLIST="$USER_HOME/Library/LaunchAgents/com.penrithbeacon.markdown-editor-agent.plist"
  if [ -f "$PLIST" ]; then
    sudo -u "$LOGGED_IN_USER" launchctl unload "$PLIST" 2>/dev/null || true
    echo "preinstall: unloaded existing agent"
  fi
fi
exit 0
ENDSCRIPT
chmod +x "$PKG_SCRIPTS/preinstall"
echo "✓ Scripts ready"
echo ""

# ── Step 4: Build the .pkg ───────────────────────────────────────────────────
echo "→ Step 4: Running pkgbuild..."
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier com.penrithbeacon.markdown-editor-agent \
  --version 1.0.0 \
  --install-location / \
  wcp-agent-markdown-editor.pkg

echo ""
echo "✓ Package built: $SCRIPT_DIR/wcp-agent-markdown-editor.pkg"
echo ""
echo "Next steps:"
echo "  1. Copy to widget installer bundle:"
echo "     mkdir -p ../wcp-widget-markdown-editor/src/installers"
echo "     cp wcp-agent-markdown-editor.pkg ../wcp-widget-markdown-editor/src/installers/"
echo "  2. Rebuild the widget container"
echo "  3. Test: GET /widget/agent/installer should return 200"
