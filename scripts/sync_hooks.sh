#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sync_hooks.sh [--logging on|off] [--log] [--no-log]

Sync this repository's Codex hook files into ~/.codex.

Options:
  --logging on|off   Enable or disable hook debug logging. Defaults to off.
  --log              Shortcut for --logging on.
  --no-log           Shortcut for --logging off.
  -h, --help         Show this help.
EOF
}

logging="off"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --logging)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --logging" >&2
        exit 2
      fi
      case "$2" in
        on|true|1|yes) logging="on" ;;
        off|false|0|no) logging="off" ;;
        *)
          echo "invalid --logging value: $2" >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    --log)
      logging="on"
      shift
      ;;
    --no-log)
      logging="off"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
codex_home="${CODEX_HOME:-${HOME}/.codex}"
codex_hooks_dir="${codex_home}/hooks"

mkdir -p "${codex_hooks_dir}"

install -d "${codex_hooks_dir}/lib"
install -m 0644 "${repo_root}/hooks/main.ps1" "${codex_hooks_dir}/main.ps1"
install -m 0644 "${repo_root}/hooks/approval-overlay.ps1" "${codex_hooks_dir}/approval-overlay.ps1"
install -m 0644 "${repo_root}/hooks/lib/paths.ps1" "${codex_hooks_dir}/lib/paths.ps1"
install -m 0644 "${repo_root}/hooks/lib/logging.ps1" "${codex_hooks_dir}/lib/logging.ps1"
install -m 0644 "${repo_root}/hooks/lib/context.ps1" "${codex_hooks_dir}/lib/context.ps1"
install -m 0644 "${repo_root}/hooks/lib/state.ps1" "${codex_hooks_dir}/lib/state.ps1"
install -m 0644 "${repo_root}/hooks/lib/overlay.ps1" "${codex_hooks_dir}/lib/overlay.ps1"
install -m 0644 "${repo_root}/hooks/lib/actions.ps1" "${codex_hooks_dir}/lib/actions.ps1"
install -m 0755 "${repo_root}/hooks/clear-approval-toast-if-active.sh" "${codex_hooks_dir}/clear-approval-toast-if-active.sh"
install -m 0755 "${repo_root}/hooks/session-end-toast.sh" "${codex_hooks_dir}/session-end-toast.sh"
install -m 0644 "${repo_root}/hooks/codex.svg" "${codex_hooks_dir}/codex.svg"
install -m 0644 "${repo_root}/hooks/codex-approval-toast-icon.png" "${codex_hooks_dir}/codex-approval-toast-icon.png"

cat > "${codex_home}/hooks.json" <<EOF
{
  "hooks": {
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"${codex_hooks_dir}/main.ps1\" -Action approval",
            "timeout": 15,
            "statusMessage": "Notifying approval request"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${codex_hooks_dir}/clear-approval-toast-if-active.sh\"",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${codex_hooks_dir}/session-end-toast.sh\"",
            "timeout": 15,
            "statusMessage": "Notifying conversation end"
          }
        ]
      }
    ]
  }
}
EOF

if [[ "${logging}" == "on" ]]; then
  logging_json=true
else
  logging_json=false
fi

cat > "${codex_hooks_dir}/approval-toast-config.json" <<EOF
{
  "logging": ${logging_json}
}
EOF

echo "Synced Codex hooks to ${codex_home} (logging=${logging})."
