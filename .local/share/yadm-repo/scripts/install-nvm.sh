#!/usr/bin/env bash
# Install nvm (Node Version Manager)

set -euo pipefail

if [[ -d "$HOME/.nvm" ]]; then
  echo "nvm is already installed"
  exit 0
fi

echo "Installing nvm..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

echo "nvm installed successfully"
echo "Restart your shell or run: export NVM_DIR=\"\$HOME/.nvm\" && [ -s \"\$NVM_DIR/nvm.sh\" ] \&\& \\. \"\$NVM_DIR/nvm.sh\""
