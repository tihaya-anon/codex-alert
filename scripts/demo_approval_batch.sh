#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

count="${1:-3}"

for index in $(seq 1 "${count}"); do
  "${script_dir}/demo_approval.sh" \
    "functions.exec_command" \
    "demo command ${index}: pnpm test --filter case-${index}" \
    "${repo_root}"
done
