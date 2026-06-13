## SVG to PNG

Render the Codex SVG into the PNG used by the overlay window:

```bash
uv run python svg_to_png.py
```

Useful options:

```bash
uv run python svg_to_png.py --size 256 --foreground '#FFFFFF' --background '#111827' --padding 2
```

## Sync Hooks

Sync the hook files in this repository into `~/.codex`:

```bash
./sync_hooks.sh --logging off
```

This installs the approval-request hook, a WPF overlay that stacks pending
approval requests, and a `Stop` hook that shows the Codex working directory when
a conversation turn ends.

Use logging while developing the hook:

```bash
./sync_hooks.sh --logging on
```

## Demo Approval UI

Trigger the overlay directly from this repository without waiting for a real
Codex approval:

```bash
./demo_approval.sh
./demo_approval_batch.sh 3
./demo_clear_approvals.sh
```

`demo_approval.sh` accepts optional `tool_name`, `command`, and `cwd`
arguments. `demo_approval_batch.sh` is useful for checking stacked approval
cards.

For local development and testing, do not sync into `~/.codex`. Point Codex at
this repository's hook files instead:

```bash
CODEX_HOOKS_DIR=/path/to/codex-alert/hooks
```

The shell wrappers resolve `main.ps1` from their own directory, so
running `hooks/clear-approval-toast-if-active.sh` or `hooks/session-end-toast.sh`
locally uses the repository files and repository-local overlay state.

Approval requests are written to `approval-toast-active/*.json`. The WPF overlay
is started by `main.ps1`, polls that directory, and renders the pending requests
in timestamp order. `PostToolUse` removes matching state files after a tool
finishes.
