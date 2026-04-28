#!/usr/bin/env bash
# Install Starship prompt on Ubuntu

set -euo pipefail

if command -v starship >/dev/null 2>&1; then
  echo "starship is already installed"
  exit 0
fi

echo "Installing starship via official install script..."
curl -sS https://starship.rs/install.sh | sh -s -- -y

echo "starship installed successfully"
