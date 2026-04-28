#!/usr/bin/env bash
# chezmoi-managed package installer trigger.
#
# Runs during `chezmoi apply` when this script's content changes
# (run_onchange_ contract). To force re-run after packages.yaml changes,
# modify this script or bump the counter below.
#
# Trigger rev: 1

set -euo pipefail

SRC="$HOME/.local/share/chezmoi"
WORKER="$SRC/scripts/install-from-yaml.sh"
YAML="$SRC/packages.yaml"

if [[ ! -f "$WORKER" ]]; then
  echo "[ERR] Installer missing in source dir: $WORKER" >&2
  exit 1
fi

if [[ ! -f "$YAML" ]]; then
  echo "[ERR] packages.yaml missing in source dir: $YAML" >&2
  exit 1
fi

# DOTFILES_* env vars are read by the worker (see scripts/install-from-yaml.sh).
exec bash "$WORKER" "$YAML"
