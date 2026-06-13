#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
scripts_root="$(cd -- "${script_dir}/../.." && pwd)"
repo_root="$(cd -- "${scripts_root}/.." && pwd)"

scenario="${1:-mixed}"

emit_demo() {
  local tool_name="$1"
  local command_text="$2"

  "${script_dir}/single.sh" \
    "${tool_name}" \
    "${command_text}" \
    "${repo_root}"
}

case "${scenario}" in
  mixed)
    emit_demo "functions.exec_command" "pnpm test"
    emit_demo "functions.exec_command" "pnpm --filter @culture-chain/web typecheck"
    emit_demo "functions.exec_command" "uv run pytest tests/services/test_upload_service.py -k approval_overlay"
    emit_demo "functions.exec_command" "bash -lc \"cd /workspace/app && export NODE_ENV=development && pnpm --filter web test --runInBand --reporter=verbose\""
    emit_demo "functions.exec_command" "curl -X POST https://api.example.test/v1/upload -H 'Authorization: Bearer demo-token' -H 'Content-Type: application/json' -d '{\"assetId\":\"work-2048\",\"owner\":\"0x1234abcd5678ef90\",\"metadata\":{\"title\":\"Long command visual regression pass\",\"tags\":[\"overlay\",\"approval\",\"demo\"]}}'"
    emit_demo "functions.exec_command" "python scripts/process_batch.py --input data/source.csv --output tmp/final-report.json --mode reconcile --max-workers 8 --retry 3 --feature-flags normalize_titles,emit_metrics,strict_validation"
    ;;
  short)
    emit_demo "functions.exec_command" "pnpm lint"
    emit_demo "functions.exec_command" "git status"
    emit_demo "functions.exec_command" "make test"
    ;;
  long)
    emit_demo "functions.exec_command" "bash -lc \"cd /srv/platform && source .venv/bin/activate && uv run python manage.py backfill --tenant acme-staging --from 2026-01-01 --to 2026-06-01 --include archived,failed,pending --write-json tmp/backfill-summary.json --emit-progress --strict\""
    emit_demo "functions.exec_command" "node ./scripts/run-task.mjs --profile production --workspace web --job rebuild-search-index --chunk-size 200 --parallelism 6 --dry-run false --notify slack,email --labels approval-demo,visual-length-test,overlay-card"
    emit_demo "functions.exec_command" "curl -X POST https://api.example.test/v2/workflows/run -H 'Authorization: Bearer very-long-demo-token-for-overlay-visual-tests' -H 'Content-Type: application/json' -d '{\"workflow\":\"publish-artifact\",\"environment\":\"staging\",\"artifact\":{\"name\":\"approval-overlay-demo-build\",\"version\":\"2026.06.13.1\",\"sha\":\"9d1d7a22d0f6c0b54d95a02c9934d7e4\"},\"options\":{\"invalidateCache\":true,\"runMigrations\":false,\"sendNotifications\":true}}'"
    ;;
  *)
    echo "unknown scenario: ${scenario}" >&2
    echo "expected one of: mixed, short, long" >&2
    exit 2
    ;;
esac
