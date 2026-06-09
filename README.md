# wcp-agent-markdown-editor

Companion macOS agent for `wcp-widget-markdown-editor`.

Runs natively on the host machine and extends the widget with host filesystem capabilities:
folder browsing, drive enumeration, path validation, and directory creation.

---

## What it does

The agent exposes a local HTTP API on `127.0.0.1:3749`. The widget container reaches it
via `host.docker.internal:3749`. Without the agent, the widget operates in volume-only
mode (all file operations confined to the Docker volume). With the agent, users can browse
the host filesystem and set any folder as the working root.

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Agent health check |
| `GET` | `/agent/wcp` | WCP agent manifest |
| `GET` | `/agent/logs` | WCP logs protocol (`?limit=`, `?level=`, `?since=`) |
| `GET` | `/files/browse?path=` | List directories and files at host path |
| `GET` | `/files/drives` | Enumerate `/Volumes/*` + home directory |
| `GET` | `/files/validate?path=` | Check path exists and is readable |
| `POST` | `/files/mkdir` | Create a directory (`{"path":"..."}`) |

---

## Installation

### Requirements

- macOS (Apple Silicon or Intel via Rosetta 2)
- Python 3.11+ (for development build)

### From installer (recommended)

Download the `.pkg` from
[GitHub Releases](https://github.com/penrithbeacon/wcp-agent-markdown-editor/releases)
and double-click to install. The agent starts automatically at login.

Or from the widget itself: **Settings → Download Agent Installer**.

### From source

```bash
git clone https://github.com/HarrisonOfTheNorth/wcp-agent-markdown-editor
cd wcp-agent-markdown-editor
bash build-app.sh    # creates dist/Markdown Editor Agent.app
bash install.sh      # installs to /Applications + loads LaunchAgent
```

Verify:
```bash
curl -s http://127.0.0.1:3749/health | python3 -m json.tool
```

### Uninstall

```bash
bash uninstall.sh
```

---

## Bonjour Registration

The agent automatically registers itself with the WCP Bonjour Proxy at
`http://127.0.0.1:3746/agent/register` on startup. Registration is retried with
exponential backoff (up to 10 attempts). The proxy is optional — the agent operates
fully without it.

---

## Logs

```
~/Library/Logs/markdown-editor-agent/agent.log
```

Or via the API: `curl -s http://127.0.0.1:3749/agent/logs | python3 -m json.tool`

---

## Auto-start

The agent registers as a macOS LaunchAgent and starts at user login:

```
~/Library/LaunchAgents/com.penrithbeacon.markdown-editor-agent.plist
```

---

## Security

The agent binds to `127.0.0.1` only. It is never reachable from the network. Widget
containers reach it via `host.docker.internal`, which resolves to the host loopback.

---

## Author

Anthony Harrison · [widgets@penrithbeacon.com](mailto:widgets@penrithbeacon.com) · [penrithbeacon.com](https://penrithbeacon.com)

Companion widget: [penrithbeacon/wcp-widget-markdown-editor](https://github.com/penrithbeacon/wcp-widget-markdown-editor)
