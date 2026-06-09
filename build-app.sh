#!/bin/bash
set -e
echo "Building wcp-agent-markdown-editor..."

# Create and activate venv
python3 -m venv .venv
source .venv/bin/activate

# Install deps
pip install --upgrade pip
pip install flask flask-cors py2app

# Build .app
python setup.py py2app

echo "✓ App bundle at dist/Markdown Editor Agent.app"
echo ""
echo "Next: bash install.sh"
