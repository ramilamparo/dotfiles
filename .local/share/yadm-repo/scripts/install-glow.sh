#!/usr/bin/env bash
# Install glow (markdown pager) on Ubuntu

set -euo pipefail

if command -v glow >/dev/null 2>&1; then
  echo "glow is already installed"
  exit 0
fi

echo "Installing glow..."

# Try to install via apt first (available in newer Ubuntu versions)
if apt-cache show glow >/dev/null 2>&1; then
  sudo apt install -y glow
else
  # Fallback: install via Go or download release binary
  if command -v go >/dev/null 2>&1; then
    go install github.com/charmbracelet/glow@latest
    # Move from ~/go/bin to /usr/local/bin if needed
    if [[ -f "$HOME/go/bin/glow" ]]; then
      sudo install -Dm755 "$HOME/go/bin/glow" /usr/local/bin/glow
    fi
  else
    # Download prebuilt binary
    GLOW_VERSION="$(curl -s https://api.github.com/repos/charmbracelet/glow/releases/latest | grep -oP '"tag_name": "\K[^"]+')"
    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64)  ARCH="x86_64" ;;
      aarch64) ARCH="arm64" ;;
      *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    cd "$TMP_DIR"
    curl -fsSL "https://github.com/charmbracelet/glow/releases/download/${GLOW_VERSION}/glow_${GLOW_VERSION#v}_Linux_${ARCH}.tar.gz" -o glow.tar.gz
    tar -xzf glow.tar.gz
    sudo install -Dm755 glow /usr/local/bin/glow
  fi
fi

echo "glow installed successfully"
