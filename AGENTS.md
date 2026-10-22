# Agent Guidelines

## Agent skills

### Issue tracker

GitHub issues via `gh` CLI (`guillaumeslash/folderDock`). See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical 5-role triage vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (`CONTEXT.md` + `docs/adr/`). See `docs/agents/domain.md`.

## Post-Modification Workflow

At the end of every code change/modification:
1. Compile, install to `/Applications`, and restart:
   ```bash
   ./scripts/build_app.sh install
   ```
   This automatically compiles the release bundle, replaces `/Applications/FoldyDock.app`, terminates any older running process, and relaunches the application from `/Applications/FoldyDock.app`.

## Testing

Run `./scripts/run_tests.sh` (never raw `swift test`: it silently skips XCTest cases). `--filter <Suite>` works for both Swift Testing suites and XCTest classes.

## Documentation & Releases Guidelines

- **Conciseness**: Keep feature descriptions, changelogs, and release notes concise, direct, and focused on essential value without unnecessary fluff.
- **French Translation**: Always provide a French translation for releases and the app README (bilingual EN/FR or paired concise translations).
- **Website check**: At every release, check that https://guillaume-murat.github.io/foldyDock/ reflects the new version and features. The site is published by GitHub Pages from `docs/` on `main` (`docs/index.html`). If it is out of date, update it using the `apple-design` skill, then push with the release.


