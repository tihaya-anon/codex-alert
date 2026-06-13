#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
scripts_root="$(cd -- "${script_dir}/../.." && pwd)"
repo_root="$(cd -- "${scripts_root}/.." && pwd)"
state_dir="${CODEX_HOOKS_DIR:-${repo_root}/hooks}/approval-toast-active"
legacy_state_path="${CODEX_HOOKS_DIR:-${repo_root}/hooks}/approval-toast-active.json"

rm -f "${legacy_state_path}"

if [[ -d "${state_dir}" ]]; then
  find "${state_dir}" -maxdepth 1 -type f -name '*.json' -delete
fi

echo "Cleared approval demo state from ${state_dir}"
