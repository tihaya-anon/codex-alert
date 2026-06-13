#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
scripts_root="$(cd -- "${script_dir}/../.." && pwd)"
repo_root="$(cd -- "${scripts_root}/.." && pwd)"
state_dir="${CODEX_HOOKS_DIR:-${repo_root}/hooks}/overlay-active"

if [[ -d "${state_dir}" ]]; then
  find "${state_dir}" -maxdepth 1 -type f -name 'codex-session-end-*.json' -delete
fi

echo "Cleared session demo state from ${state_dir}"
