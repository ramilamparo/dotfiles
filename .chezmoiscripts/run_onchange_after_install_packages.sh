#!/usr/bin/env bash
# chezmoi-managed package installer trigger.
#
# Runs during `chezmoi apply` when this script's content changes
# (run_onchange_ contract). To force re-run after packages.yaml changes,
# modify this script or bump the counter below.
#
# Trigger rev: 2
#
# Behavior:
#   - With a TTY and fzf installed: launch the interactive picker so the
#     user explicitly chooses which packages to install.
#   - Otherwise (bootstrap, CI, no fzf): fall through to the non-interactive
#     worker, which installs everything not already on PATH.
#
# DOTFILES_* env vars (SKIP / SKIP_GROUP / ONLY / ONLY_GROUP / FORCE /
# DRY_RUN / YES) are read by the worker either way.

set -euo pipefail

SRC="$HOME/.local/share/chezmoi"
WORKER="$SRC/scripts/install-from-yaml.sh"
PICKER="$SRC/scripts/install-interactive.sh"
YAML="$SRC/packages.yaml"

if [[ ! -f "$WORKER" ]]; then
  echo "[ERR] Installer missing in source dir: $WORKER" >&2
  exit 1
fi

if [[ ! -f "$YAML" ]]; then
  echo "[ERR] packages.yaml missing in source dir: $YAML" >&2
  exit 1
fi

if [[ -t 0 && -t 1 ]] && [[ -f "$PICKER" ]] && command -v fzf >/dev/null 2>&1; then
  exec bash "$PICKER" "$YAML"
fi

exec bash "$WORKER" "$YAML"
