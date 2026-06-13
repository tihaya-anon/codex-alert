#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
approval_dir="$(cd -- "${script_dir}/../approval" && pwd)"
session_dir="$(cd -- "${script_dir}/../session" && pwd)"

"${approval_dir}/single.sh" "functions.exec_command" "pnpm --filter web test" "/home/labuser/code/codex_alert"
"${approval_dir}/single.sh" "functions.exec_command" "uv run pytest tests/services/test_upload_service.py" "/home/labuser/code/infra_tools"
"${session_dir}/stop.sh" "/home/labuser/code/codex_alert"
