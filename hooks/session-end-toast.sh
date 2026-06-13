#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
payload="$(cat)"
ps_runner="${script_dir}/run-powershell-hook.sh"

printf '%s' "${payload}" |
  CODEX_HOOK_CWD="${PWD}" "${ps_runner}" -NoProfile -ExecutionPolicy Bypass -File "${script_dir}/main.ps1" -Action session
