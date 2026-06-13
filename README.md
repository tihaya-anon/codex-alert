# codex_alert

Windows overlay notifications for Codex approval requests and turn completion.

## What It Does

This repository provides a PowerShell/WPF overlay that runs from WSL-hosted
Codex hooks and surfaces a unified notification feed:

- approval items stay visible until Codex clears them after the tool flow
- session-stop items stay visible until manually closed
- both item types share one overlay window, one position, and one state feed

## Layout

- `hooks/`: runtime hook assets installed into `~/.codex/hooks`
- `hooks/main.ps1`: single PowerShell entrypoint for `approval`, `clear`, and `session`
- `hooks/approval-overlay.ps1`: the WPF overlay window
- `hooks/lib/*.ps1`: context parsing, state management, logging, and overlay startup
- `scripts/`: local tooling, sync script, icon generation, and demo scripts
- `scripts/demo/`: approval, session, and mixed-feed demo triggers

## Setup

1. Keep Windows binary interop enabled in WSL.
2. `appendWindowsPath=true` is optional.
3. Sync hooks:

```bash
cd scripts
./sync_hooks.sh --logging off
```

The hook runner resolves PowerShell explicitly, so `appendWindowsPath=false`
still works if PowerShell exists in a standard `/mnt/c/...` location.

## Development

- Point Codex at repo-local hooks during development:

```bash
CODEX_HOOKS_DIR=/path/to/codex_alert/hooks
```

- Enable hook logging while debugging:

```bash
cd scripts
./sync_hooks.sh --logging on
```

- Regenerate the overlay icon only when `hooks/codex.svg` changes:

```bash
cd scripts
uv run python svg_to_png.py
```

## Demo Scripts

```bash
bash scripts/demo/approval/single.sh
bash scripts/demo/approval/batch.sh
bash scripts/demo/approval/paths.sh
bash scripts/demo/feed/mixed.sh
bash scripts/demo/session/stop.sh
```

Clear demo state with:

```bash
bash scripts/demo/approval/clear.sh
bash scripts/demo/session/clear.sh
```

## Notes

- Approval/session state is stored in `hooks/overlay-active/`.
- Runtime window position is stored in `hooks/overlay-window-state.json`.
- Logs are written to the Windows temp directory as
  `codex-approval-toast-debug.log` when logging is enabled.
