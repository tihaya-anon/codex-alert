# Repository Guidelines

## Project Structure & Module Organization
This repository packages Codex hook integrations and helper scripts.

- `hooks/`: runtime hook assets, including `main.ps1`, `lib/*.ps1`, shell wrappers, the WPF overlay script, and icon files.
- `scripts/`: Python utilities and repo-local tooling. `svg_to_png.py` rebuilds the overlay icon; `sync_hooks.sh` installs hooks into `~/.codex`.
- `scripts/README.md`: operational notes and local development examples.

Keep new hook behavior in `hooks/` and supporting automation in `scripts/`.

## Build, Test, and Development Commands
- `cd scripts && uv run python svg_to_png.py`: regenerate `hooks/codex-approval-toast-icon.png` from `hooks/codex.svg`.
- `cd scripts && uv run python svg_to_png.py --size 256 --foreground '#FFFFFF' --background '#111827' --padding 2`: example custom render.
- `cd scripts && ./sync_hooks.sh --logging off`: install this repo’s hooks into `~/.codex`.
- `CODEX_HOOKS_DIR=/path/to/codex_alert/hooks`: point Codex at the repo-local hooks during development instead of syncing.

If you add Python dependencies, update `scripts/pyproject.toml` and keep commands runnable through `uv run`.

## Coding Style & Naming Conventions
Use 4 spaces in Python and 2 spaces in shell/JSON where the file already follows that style. Prefer type hints in Python, `snake_case` for Python functions and variables, and descriptive kebab-case filenames for shell scripts. Keep PowerShell functions verb-noun styled, matching the existing `Get-*`, `Write-*`, and `Start-*` patterns.

Favor small single-purpose scripts. Preserve UTF-8 text handling and explicit paths with `pathlib.Path` in Python.

## Testing Guidelines
There is no formal test suite yet. Validate changes by running the affected script directly and exercising the local hook flow.

- Script changes: run the relevant `uv run python ...` command.
- Hook changes: test with `CODEX_HOOKS_DIR` pointed at this repo and confirm state files and notifications behave correctly.

When adding tests, place them under `scripts/tests/` and name files `test_*.py`.

## Commit & Pull Request Guidelines
Recent history uses Conventional Commit style, for example `feat(hooks): play alert sounds from overlay` and `chore: initial commit`. Follow `type(scope): summary` where possible.

Pull requests should include a concise description, the scenario tested locally, and screenshots or short recordings for overlay/UI changes. Link related issues when applicable and note any Windows-specific setup assumptions.
