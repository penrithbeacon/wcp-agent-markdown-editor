#!/bin/bash
# Build wcp-agent-markdown-editor.pkg — a macOS installer for the Markdown Editor companion agent.
# Uses productbuild (not pkgbuild) so the installer wizard shows a welcome screen with version info.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

AGENT_VERSION="1.0.2"
PKG_IDENTIFIER="com.penrithbeacon.markdown-editor-agent"

echo "=== wcp-agent-markdown-editor.pkg builder v${AGENT_VERSION} ==="
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

# Embed the Penrith Beacon icon into the uninstaller app.
# osacompile produces a generic AppScript icon ("applet.icns" in Resources).
# Replacing it with the PB icon makes the app identifiable in Finder / Spotlight.
# CFBundleIconFile in osacompile'd apps defaults to "applet", so overwriting
# applet.icns is all that is needed — no Info.plist change required.
PB_ICON="/Volumes/dashboard/src/electron/assets/icon.icns"
if [ -f "$PB_ICON" ]; then
  cp "$PB_ICON" "$UNINSTALL_TMP/Contents/Resources/applet.icns"
  echo "✓ Penrith Beacon icon embedded in uninstaller app"
else
  echo "⚠ PB icon not found at $PB_ICON — uninstaller will use generic AppScript icon"
fi

cp -r "$UNINSTALL_TMP" "$PKG_ROOT/Applications/"
chmod -R 755 "$UNINSTALL_DST"
echo "✓ Uninstaller app ready: $UNINSTALL_DST"
echo "✓ Staging root ready: $PKG_ROOT"
echo ""

# ── Step 3: Create installer scripts ─────────────────────────────────────────
echo "→ Step 3: Creating installer scripts..."
PKG_SCRIPTS=/tmp/wcp-agent-pkg-scripts
rm -rf "$PKG_SCRIPTS"
mkdir -p "$PKG_SCRIPTS"

cat > "$PKG_SCRIPTS/preinstall" << 'ENDSCRIPT'
#!/bin/bash
# Stop any running instance before installing so the new binary can replace it.
LOGGED_IN_USER=$(stat -f%Su /dev/console 2>/dev/null)
if [ -z "$LOGGED_IN_USER" ] || [ "$LOGGED_IN_USER" = "root" ]; then
  LOGGED_IN_USER=$(who | grep console | awk '{print $1}' | head -1)
fi
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ]; then
  USER_HOME=$(eval echo ~"$LOGGED_IN_USER")
  LOGGED_IN_UID=$(id -u "$LOGGED_IN_USER")
  PLIST="$USER_HOME/Library/LaunchAgents/com.penrithbeacon.markdown-editor-agent.plist"

  # Unload via modern bootout first, then legacy fallback
  if [ -f "$PLIST" ]; then
    launchctl bootout "gui/$LOGGED_IN_UID" "$PLIST" 2>/dev/null \
      || sudo -u "$LOGGED_IN_USER" launchctl unload "$PLIST" 2>/dev/null \
      || true
    echo "preinstall: unloaded existing LaunchAgent"
  fi

  # Kill any lingering process by name (handles the case where launchctl did not
  # terminate the process — e.g. first install, stale pid, or launchctl context mismatch)
  if pkill -u "$LOGGED_IN_USER" -f "Markdown Editor Agent" 2>/dev/null; then
    echo "preinstall: killed running Markdown Editor Agent process"
    sleep 1  # brief pause so the port (3749) is released before postinstall loads the new one
  fi
fi
exit 0
ENDSCRIPT
chmod +x "$PKG_SCRIPTS/preinstall"

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
sudo -u "$LOGGED_IN_USER" mkdir -p "$USER_HOME/Library/Logs/wcp-agent-markdown-editor"

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

# Load the LaunchAgent for the logged-in user.
# Use modern bootstrap (macOS 10.15+) first, fall back to legacy load.
launchctl bootstrap "gui/$LOGGED_IN_UID" "$PLIST_DST" 2>/dev/null \
  || sudo -u "$LOGGED_IN_USER" launchctl load "$PLIST_DST" 2>/dev/null \
  || echo "postinstall: note — agent will auto-start on next login"

echo "postinstall: complete"
exit 0
ENDSCRIPT
chmod +x "$PKG_SCRIPTS/postinstall"
echo "✓ Scripts ready"
echo ""

# ── Step 4: Build the component .pkg with pkgbuild ────────────────────────────
echo "→ Step 4: Building component package with pkgbuild..."
COMPONENT_PKG=/tmp/wcp-agent-component.pkg
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier "$PKG_IDENTIFIER" \
  --version "$AGENT_VERSION" \
  --install-location / \
  "$COMPONENT_PKG"
echo "✓ Component package: $COMPONENT_PKG"
echo ""

# ── Step 5: Create welcome screen resources ────────────────────────────────────
# productbuild wraps the component package in a wizard with a welcome screen.
# The welcome screen must display both the product name and version number.
echo "→ Step 5: Creating installer resources (welcome screen)..."
PKG_RESOURCES=/tmp/wcp-agent-pkg-resources
rm -rf "$PKG_RESOURCES"
mkdir -p "$PKG_RESOURCES"

cat > "$PKG_RESOURCES/welcome.html" << ENDHTML
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
  body { font-family: -apple-system, Helvetica, Arial, sans-serif;
         font-size: 13px; color: #1d1d1f; margin: 0; padding: 16px 20px; }
  h1   { font-size: 17px; font-weight: 600; margin: 0 0 8px; }
  .ver { font-size: 12px; color: #6e6e73; margin-bottom: 16px; }
  p    { line-height: 1.5; margin: 0 0 10px; }
</style></head>
<body>
  <h1>WCP Agent — Markdown Editor</h1>
  <div class="ver">Version ${AGENT_VERSION}</div>
  <p>This installer will install the <strong>WCP Markdown Editor companion agent</strong>
     on your Mac.</p>
  <p>The agent runs in the background at login and gives the Markdown Editor widget
     access to your local file system — so you can browse, open, and save files
     directly from the widget.</p>
  <p>After installation the agent starts automatically.
     You can remove it at any time using
     <strong>Uninstall WCP Markdown Editor Agent</strong> in your Applications folder.</p>
</body>
</html>
ENDHTML

echo "✓ welcome.html written (version ${AGENT_VERSION})"

# ── Step 6: Write Distribution XML ────────────────────────────────────────────
echo "→ Step 6: Writing Distribution.xml..."
DIST_XML=/tmp/wcp-agent-distribution.xml
cat > "$DIST_XML" << ENDXML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>WCP Agent — Markdown Editor</title>
    <welcome    file="welcome.html"    mime-type="text/html"/>
    <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
    <pkg-ref id="${PKG_IDENTIFIER}"/>
    <choices-outline>
        <line choice="${PKG_IDENTIFIER}"/>
    </choices-outline>
    <choice id="${PKG_IDENTIFIER}" visible="false">
        <pkg-ref id="${PKG_IDENTIFIER}"/>
    </choice>
    <pkg-ref id="${PKG_IDENTIFIER}" version="${AGENT_VERSION}"
             onConclusion="none">wcp-agent-component.pkg</pkg-ref>
</installer-gui-script>
ENDXML
echo "✓ Distribution.xml written"
echo ""

# ── Step 7: Build the final .pkg with productbuild ────────────────────────────
echo "→ Step 7: Building final installer with productbuild..."
productbuild \
  --distribution "$DIST_XML" \
  --resources    "$PKG_RESOURCES" \
  --package-path /tmp \
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
