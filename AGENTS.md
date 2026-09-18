# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `homebrew.onActivation.cleanup = "none"` in `configuration.nix` is intentional, and sits alongside `onActivation.upgrade = false` and `onActivation.autoUpdate = false`: activation installs what the config declares and never removes, upgrades, or updates anything behind your back. Homebrew packages installed by hand survive a switch, so `brews` and `casks` are not a full inventory of what is on the machine - that drift is the accepted cost of a non-destructive activation. The upstream repo this one is derived from sets `"zap"`; do not "restore" that here. README.md describes the effect for users; this note is for anyone tempted to change the setting itself.
- `home.nix` links `home/.config/` and `home/.claude/` into `$HOME` with `mkOutOfStoreSymlink`, so those tools write straight back into this working tree. Tracked files they rewrite at runtime - `home/.config/nvim/lazy-lock.json` (lazy.nvim) and `home/.pi/agent/settings.json` (Pi) - surface as unrelated diffs. Leave them out of your commits unless the task is about them.
- `programs.zsh.shellInit` in `configuration.nix` is a self-healing guard, not decoration: it re-applies nix-darwin's set-environment when a zsh inherits `__NIX_DARWIN_SET_ENVIRONMENT_DONE=1` without `/run/current-system/sw/bin` on PATH (a GUI app relaunched from an agent shell hands exactly that to every window it opens). It must stay in `/etc/zshenv`, before `~/.zshenv` and `~/.zshrc`; `tests/path-guard.test.sh` is its regression test and `~/.local/state/nix-darwin-path-guard.log` records every repair.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
