#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_runner="${script_dir}/../scripts/run_powershell_from_wsl.sh"

if [[ -x "${repo_runner}" ]]; then
  exec "${repo_runner}" "$@"
fi

resolve_powershell() {
  if command -v powershell.exe >/dev/null 2>&1; then
    command -v powershell.exe
    return 0
  fi

  local candidates=(
    "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    "/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe"
    "/mnt/c/Program Files/PowerShell/7/pwsh.exe"
    "/mnt/c/Program Files/PowerShell/7-preview/pwsh.exe"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

powershell_path="$(resolve_powershell || true)"
if [[ -z "${powershell_path}" ]]; then
  echo "Unable to locate Windows PowerShell from WSL." >&2
  exit 1
fi

exec "${powershell_path}" "$@"
