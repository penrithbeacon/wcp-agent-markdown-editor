"""py2app build configuration for wcp-agent-markdown-editor."""
from setuptools import setup

APP    = ['agent.py']
DATA   = []
OPTIONS = {
    'argv_emulation': False,
    'plist': {
        'CFBundleName':             'Markdown Editor Agent',
        'CFBundleDisplayName':      'Markdown Editor Agent',
        'CFBundleIdentifier':       'com.penrithbeacon.markdown-editor-agent',
        'CFBundleVersion':          '1.0.0',
        'CFBundleShortVersionString': '1.0.0',
        'LSUIElement':              True,   # no Dock icon — background agent
        'NSHumanReadableCopyright': '© 2026 Penrith Beacon Communications',
    },
    'packages': ['flask', 'flask_cors', 'werkzeug', 'click', 'jinja2', 'markupsafe',
                 'itsdangerous'],
    'includes': ['platform', 'threading', 'urllib'],
}

setup(
    app=APP,
    data_files=DATA,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
