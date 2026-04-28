#!/usr/bin/env bash
# Install yay AUR helper on Arch Linux

set -euo pipefail

if command -v yay >/dev/null 2>&1; then
  echo "yay is already installed"
  exit 0
fi

echo "Installing yay..."

# Install dependencies
sudo pacman -S --needed --noconfirm git base-devel

# Build yay in a temp directory
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$BUILD_DIR"
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

echo "yay installed successfully"
