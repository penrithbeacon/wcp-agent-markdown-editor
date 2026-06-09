"""
wcp-agent-markdown-editor — Companion host agent for the Markdown Editor widget.
Exposes host filesystem browsing via a local HTTP API on 127.0.0.1.
Registers with the WCP Bonjour proxy on startup.
"""

import os
import json
import platform
import subprocess
import threading
import time
import urllib.request
import urllib.error
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

PORT           = int(os.environ.get('AGENT_PORT', 3749))
BONJOUR_PORT   = int(os.environ.get('BONJOUR_PORT', 3746))  # proxy stub port
VERSION        = '1.0.0'
AGENT_NAME     = 'wcp-agent-markdown-editor'
LOG_DIR        = os.path.expanduser(f'~/Library/Logs/{AGENT_NAME}')
LOG_FILE       = os.path.join(LOG_DIR, 'agent.log')

# In-memory log buffer for GET /agent/logs
_log_entries = []

def log(level, message, source=None):
    entry = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'level':     level,
        'message':   message
    }
    if source:
        entry['source'] = source
    _log_entries.append(entry)
    if len(_log_entries) > 500:
        _log_entries.pop(0)
    line = f"[{entry['timestamp']}] {level.upper():5} {message}"
    print(line, flush=True)
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(LOG_FILE, 'a') as f:
            f.write(line + '\n')
    except Exception:
        pass

# ── Health ────────────────────────────────────────────────────────────────────

@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'name': AGENT_NAME, 'version': VERSION,
                    'platform': platform.system()})

# ── Agent manifest (GET /agent/wcp) ──────────────────────────────────────────

@app.route('/agent/wcp')
def agent_manifest():
    return jsonify({
        'wcp':              '2.1.0',
        'name':             AGENT_NAME,
        'version':          VERSION,
        'port':             PORT,
        'health':           '/health',
        'companion_widget': 'wcp-widget-markdown-editor',
        'description':      'Host filesystem agent for the Markdown Editor widget.',
        'platform':         platform.system()
    })

# ── Logs (WCP logs protocol) ──────────────────────────────────────────────────

@app.route('/agent/logs')
def logs():
    limit  = int(request.args.get('limit', 100))
    level  = request.args.get('level')
    since  = request.args.get('since')
    entries = _log_entries[-limit:]
    if level:
        entries = [e for e in entries if e['level'] == level]
    if since:
        entries = [e for e in entries if e['timestamp'] > since]
    return jsonify({
        'wcp_logs':  '1.0',
        'component': {'type': 'agent', 'name': AGENT_NAME, 'version': VERSION},
        'schema': {
            'fields': [
                {'name': 'timestamp', 'type': 'iso8601',  'required': True},
                {'name': 'level',     'type': 'enum',
                 'values': ['debug','info','warn','error'], 'required': True},
                {'name': 'message',   'type': 'string',    'required': True},
                {'name': 'source',    'type': 'string',    'required': False}
            ]
        },
        'entries': entries
    })

# ── File system endpoints ─────────────────────────────────────────────────────

def safe_path(path):
    """Reject obviously dangerous paths; return realpath."""
    real = os.path.realpath(os.path.expanduser(path))
    return real

@app.route('/files/browse')
def files_browse():
    """List directories and .md files at a given host path."""
    path = request.args.get('path', os.path.expanduser('~'))
    real = safe_path(path)
    if not os.path.isdir(real):
        return jsonify({'error': 'not a directory', 'path': path}), 400
    try:
        entries = []
        for name in sorted(os.listdir(real)):
            full = os.path.join(real, name)
            try:
                is_dir = os.path.isdir(full)
                entries.append({
                    'name': name,
                    'path': full,
                    'type': 'dir' if is_dir else 'file',
                    'ext':  os.path.splitext(name)[1].lower()
                })
            except PermissionError:
                pass
        log('debug', f'browse {real} → {len(entries)} entries', 'files')
        return jsonify({'path': real, 'entries': entries})
    except PermissionError:
        return jsonify({'error': 'permission denied', 'path': real}), 403

@app.route('/files/drives')
def files_drives():
    """List available mount points / drives on the host."""
    drives = []
    if platform.system() == 'Darwin':
        home = os.path.expanduser('~')
        drives.append({'name': 'Home', 'path': home, 'type': 'home'})
        if os.path.isdir('/Volumes'):
            vols = []
            for name in os.listdir('/Volumes'):
                # Filter hidden volumes (dot-prefix) and Apple-internal volumes (com.apple.*)
                if name.startswith('.') or name.startswith('com.apple'):
                    continue
                full = os.path.join('/Volumes', name)
                if os.path.isdir(full):
                    vols.append({'name': name, 'path': full, 'type': 'volume'})
            # Sort alphabetically; entries starting with a digit sort before letters
            vols.sort(key=lambda v: (0 if v['name'][0].isdigit() else 1, v['name'].lower()))
            drives.extend(vols)
    else:
        drives.append({'name': 'Root', 'path': '/', 'type': 'root'})
        drives.append({'name': 'Home', 'path': os.path.expanduser('~'), 'type': 'home'})
    log('debug', f'drives → {len(drives)} found', 'files')
    return jsonify({'drives': drives})

@app.route('/files/validate')
def files_validate():
    """Check whether a path exists and is accessible."""
    path = request.args.get('path', '')
    if not path:
        return jsonify({'valid': False, 'reason': 'no path provided'})
    real   = safe_path(path)
    exists = os.path.exists(real)
    is_dir = os.path.isdir(real) if exists else False
    try:
        readable = os.access(real, os.R_OK) if exists else False
    except Exception:
        readable = False
    return jsonify({'valid': exists and readable, 'path': real,
                    'exists': exists, 'is_dir': is_dir, 'readable': readable})

@app.route('/files/mkdir', methods=['POST'])
def files_mkdir():
    """Create a directory on the host."""
    data = request.get_json(force=True, silent=True) or {}
    path = data.get('path', '')
    if not path:
        return jsonify({'error': 'path required'}), 400
    real = safe_path(path)
    try:
        os.makedirs(real, exist_ok=True)
        log('info', f'mkdir {real}', 'files')
        return jsonify({'status': 'ok', 'path': real})
    except PermissionError:
        return jsonify({'error': 'permission denied'}), 403
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/files/read')
def files_read():
    """Read a file's content from the host filesystem."""
    path = request.args.get('path', '')
    if not path:
        return jsonify({'error': 'path required'}), 400
    real = safe_path(path)
    if not os.path.isfile(real):
        return jsonify({'error': 'not a file', 'path': real}), 404
    try:
        try:
            with open(real, 'r', encoding='utf-8-sig') as f:
                content = f.read()
        except UnicodeDecodeError:
            with open(real, 'r', encoding='latin-1') as f:
                content = f.read()
        log('debug', f'read {real}', 'files')
        return jsonify({'path': real, 'content': content})
    except PermissionError:
        return jsonify({'error': 'permission denied'}), 403
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/files/write', methods=['POST'])
def files_write():
    """Write content to a file on the host filesystem."""
    data    = request.get_json(force=True, silent=True) or {}
    path    = data.get('path', '')
    content = data.get('content', '')
    if not path:
        return jsonify({'error': 'path required'}), 400
    real = safe_path(path)
    try:
        os.makedirs(os.path.dirname(real), exist_ok=True)
        with open(real, 'w') as f:
            f.write(content)
        log('info', f'write {real}', 'files')
        return jsonify({'status': 'ok', 'path': real})
    except PermissionError:
        return jsonify({'error': 'permission denied'}), 403
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/files/delete', methods=['POST'])
def files_delete():
    """Delete a file or directory on the host filesystem."""
    import shutil
    data = request.get_json(force=True, silent=True) or {}
    path = data.get('path', '')
    if not path:
        return jsonify({'error': 'path required'}), 400
    real = safe_path(path)
    if not os.path.exists(real):
        return jsonify({'error': 'not found'}), 404
    try:
        if os.path.isdir(real):
            shutil.rmtree(real)
        else:
            os.remove(real)
        log('info', f'delete {real}', 'files')
        return jsonify({'status': 'ok'})
    except PermissionError:
        return jsonify({'error': 'permission denied'}), 403
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/files/rename', methods=['POST'])
def files_rename():
    """Rename or move a file or directory on the host filesystem."""
    data     = request.get_json(force=True, silent=True) or {}
    old_path = data.get('old', '')
    new_path = data.get('new', '')
    if not old_path or not new_path:
        return jsonify({'error': 'old and new paths required'}), 400
    old_real = safe_path(old_path)
    new_real = safe_path(new_path)
    if not os.path.exists(old_real):
        return jsonify({'error': 'source not found'}), 404
    try:
        os.makedirs(os.path.dirname(new_real), exist_ok=True)
        os.rename(old_real, new_real)
        log('info', f'rename {old_real} → {new_real}', 'files')
        return jsonify({'status': 'ok'})
    except PermissionError:
        return jsonify({'error': 'permission denied'}), 403
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ── Bonjour proxy registration ─────────────────────────────────────────────────

def register_with_bonjour():
    """Attempt to register this agent with the Bonjour proxy stub on startup."""
    manifest = {
        'name':             AGENT_NAME,
        'version':          VERSION,
        'port':             PORT,
        'health':           '/health',
        'companion_widget': 'wcp-widget-markdown-editor',
        'description':      'Host filesystem agent for the Markdown Editor widget.',
        'platform':         platform.system()
    }
    payload = json.dumps(manifest).encode()
    url     = f'http://127.0.0.1:{BONJOUR_PORT}/agent/register'
    for attempt in range(1, 11):
        try:
            req = urllib.request.Request(url, data=payload,
                                         headers={'Content-Type': 'application/json'},
                                         method='POST')
            with urllib.request.urlopen(req, timeout=3):
                log('info', f'Registered with Bonjour proxy at port {BONJOUR_PORT}', 'bonjour')
                return
        except Exception as e:
            log('warn', f'Bonjour registration attempt {attempt} failed: {e}', 'bonjour')
            time.sleep(min(2 ** attempt, 60))
    log('warn', 'Bonjour proxy not reachable — running without registration.', 'bonjour')

# ── Boot ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    os.makedirs(LOG_DIR, exist_ok=True)
    log('info', f'{AGENT_NAME} v{VERSION} starting on 127.0.0.1:{PORT}', 'boot')
    threading.Thread(target=register_with_bonjour, daemon=True).start()
    app.run(host='127.0.0.1', port=PORT, debug=False)
