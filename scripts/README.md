## SVG to PNG

Render the Codex SVG into the PNG used by the Windows toast hook:

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

This installs the approval-request toast hook and a `Stop` hook that shows the
Codex working directory when a conversation turn ends.

Use logging while developing the hook:

```bash
./sync_hooks.sh --logging on
```

For local development and testing, do not sync into `~/.codex`. Point Codex at
this repository's hook files instead:

```bash
CODEX_HOOKS_DIR=/path/to/codex-alert/hooks
```

The shell wrappers resolve `approval-toast.ps1` from their own directory, so
running `hooks/clear-approval-toast-if-active.sh` or `hooks/session-end-toast.sh`
locally uses the repository files and repository-local toast state.
