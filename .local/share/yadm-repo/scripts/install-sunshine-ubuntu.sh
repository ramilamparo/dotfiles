#!/usr/bin/env bash
# Install Sunshine game streaming server on Ubuntu

set -euo pipefail

if command -v sunshine >/dev/null 2>&1; then
  echo "sunshine is already installed"
  exit 0
fi

echo "Installing Sunshine on Ubuntu..."

# Sunshine provides official Ubuntu packages
# See: https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html

# Add Sunshine repository
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-repo.key | sudo tee /etc/apt/keyrings/sunshine-repo.key > /dev/null

# Determine Ubuntu codename
UBUNTU_CODENAME="$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)"

echo "deb [signed-by=/etc/apt/keyrings/sunshine-repo.key] https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-ubuntu-${UBUNTU_CODENAME}.deb ${UBUNTU_CODENAME} main" | sudo tee /etc/apt/sources.list.d/sunshine.list

sudo apt update
sudo apt install -y sunshine

echo "Sunshine installed successfully"
echo "You may need to run: sudo systemctl enable --now sunshine"
