#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: run_powershell_from_wsl.sh <powershell-args...>" >&2
  exit 2
fi

powershell.exe "$@"
