#!/usr/bin/env bash
# Install Ghostty terminal on Ubuntu
# Ghostty is not in Ubuntu repos yet, so we build from source or use the official method

set -euo pipefail

if command -v ghostty >/dev/null 2>&1; then
  echo "ghostty is already installed"
  exit 0
fi

echo "Installing Ghostty on Ubuntu..."

# Ghostty provides an install script for Linux
# See: https://ghostty.org/docs/install/build

# Option 1: Try the official install script if available
if curl -sI https://ghostty.org/install.sh >/dev/null 2>&1; then
  curl -fsSL https://ghostty.org/install.sh | bash
else
  # Option 2: Build from source
  echo "Building Ghostty from source..."

  sudo apt update
  sudo apt install -y \
    libgtk-4-dev libadwaita-1-dev \
    git zig

  BUILD_DIR="$(mktemp -d)"
  trap 'rm -rf "$BUILD_DIR"' EXIT

  cd "$BUILD_DIR"
  git clone https://github.com/ghostty-org/ghostty.git
  cd ghostty
  zig build -Doptimize=ReleaseFast

  # Install binary
  sudo install -Dm755 zig-out/bin/ghostty /usr/local/bin/ghostty

  # Install desktop file and resources
  if [[ -d zig-out/share ]]; then
    sudo cp -r zig-out/share/* /usr/local/share/
  fi
fi

echo "Ghostty installed successfully"
