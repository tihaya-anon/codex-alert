#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"${script_dir}/single.sh" "functions.exec_command" "pnpm --filter web test" "/home/labuser/code/codex_alert"
"${script_dir}/single.sh" "functions.exec_command" "uv run pytest tests/services/test_upload_service.py" "/home/labuser/code/infra_tools"
"${script_dir}/single.sh" "functions.exec_command" "node scripts/rebuild-search-index.mjs --tenant demo" "/home/labuser/code/customer_portal"
