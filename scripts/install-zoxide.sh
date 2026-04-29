#!/usr/bin/env bash
# Install zoxide on Ubuntu via the upstream install script.
# Ubuntu's apt package is well behind upstream, so we use install.sh.

set -euo pipefail

if command -v zoxide >/dev/null 2>&1; then
  echo "zoxide is already installed"
  exit 0
fi

echo "Installing zoxide via official install script..."
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh

echo "zoxide installed successfully"
