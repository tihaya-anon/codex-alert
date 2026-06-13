#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
scripts_root="$(cd -- "${script_dir}/../.." && pwd)"
repo_root="$(cd -- "${scripts_root}/.." && pwd)"
hooks_dir="${CODEX_HOOKS_DIR:-${repo_root}/hooks}"
ps_runner="${scripts_root}/run_powershell_from_wsl.sh"

tool_name="${1:-functions.exec_command}"
command_text="${2:-pnpm --filter web test}"
cwd_path="${3:-${repo_root}}"

payload=$(cat <<EOF
{"tool_name":"${tool_name}","cwd":"${cwd_path}","tool_input":{"command":"${command_text}"}}
EOF
)

if ! [[ -x "${ps_runner}" ]]; then
  echo "missing PowerShell runner: ${ps_runner}" >&2
  exit 1
fi

printf '%s' "${payload}" |
  CODEX_HOOK_CWD="${cwd_path}" "${ps_runner}" -NoProfile -ExecutionPolicy Bypass -File "${hooks_dir}/main.ps1" -Action approval
