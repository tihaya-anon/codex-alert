#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
payload="$(cat)"

printf '%s' "${payload}" |
  CODEX_HOOK_CWD="${PWD}" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${script_dir}/main.ps1" -Action session
