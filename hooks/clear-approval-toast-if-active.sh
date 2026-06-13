#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ps_runner="${script_dir}/run-powershell-hook.sh"
legacy_state_path="${script_dir}/approval-toast-active.json"
state_dir="${script_dir}/overlay-active"
has_state=false

if [[ -f "${legacy_state_path}" ]]; then
  has_state=true
elif [[ -d "${state_dir}" ]]; then
  while IFS= read -r -d '' _; do
    has_state=true
    break
  done < <(find "${state_dir}" -maxdepth 1 -type f -name 'codex-approval-*.json' -print0)
fi

if [[ "${has_state}" != true ]]; then
  exit 0
fi

payload="$(cat)"
printf '%s' "${payload}" |
  "${ps_runner}" -NoProfile -ExecutionPolicy Bypass -File "${script_dir}/main.ps1" -Action clear
