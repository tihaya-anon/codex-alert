#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
scripts_root="$(cd -- "${script_dir}/../.." && pwd)"
repo_root="$(cd -- "${scripts_root}/.." && pwd)"
hooks_dir="${CODEX_HOOKS_DIR:-${repo_root}/hooks}"
ps_runner="${scripts_root}/run_powershell_from_wsl.sh"
cwd_path="${1:-${repo_root}}"

payload=$(cat <<EOF
{"tool_name":"Stop","cwd":"${cwd_path}","tool_input":{"command":"Codex turn finished"}}
EOF
)

if ! [[ -x "${ps_runner}" ]]; then
  echo "missing PowerShell runner: ${ps_runner}" >&2
  exit 1
fi

printf '%s' "${payload}" |
  CODEX_HOOK_CWD="${cwd_path}" "${ps_runner}" -NoProfile -ExecutionPolicy Bypass -File "${hooks_dir}/main.ps1" -Action session
