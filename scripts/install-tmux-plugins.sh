#!/usr/bin/env bash
set -euo pipefail
[[ -d ~/.tmux/plugins/tpm ]] && exit 0
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
