#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
hooks_dir="${CODEX_HOOKS_DIR:-${repo_root}/hooks}"

tool_name="${1:-functions.exec_command}"
command_text="${2:-pnpm --filter web test}"
cwd_path="${3:-${repo_root}}"

payload=$(cat <<EOF
{"tool_name":"${tool_name}","cwd":"${cwd_path}","tool_input":{"command":"${command_text}"}}
EOF
)

printf '%s' "${payload}" |
  CODEX_HOOK_CWD="${cwd_path}" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${hooks_dir}/main.ps1" -Action approval
