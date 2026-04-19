#!/usr/bin/env bash
# Dotfiles Install Script
# Supports Arch Linux and Ubuntu
#
# Usage:
#   ./install.sh              # Full install (packages + dotfiles)
#   ./install.sh --packages   # Install packages only
#   ./install.sh --dotfiles   # Install dotfiles only
#   ./install.sh --dry-run    # Show what would be installed without doing it

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Script directory
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_YAML="${SCRIPT_DIR}/packages.yaml"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
DO_PACKAGES=false
DO_DOTFILES=false
DRY_RUN=false

if [[ $# -eq 0 ]]; then
  DO_PACKAGES=true
  DO_DOTFILES=true
else
  for arg in "$@"; do
    case "$arg" in
      --packages) DO_PACKAGES=true ;;
      --dotfiles) DO_DOTFILES=true ;;
      --dry-run)  DRY_RUN=true ;;
      *) err "Unknown argument: $arg"; exit 1 ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# Detect distro
# ---------------------------------------------------------------------------
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    case "$ID" in
      arch|manjaro|endeavouros) echo "arch" ;;
      ubuntu|debian|pop)        echo "ubuntu" ;;
      *)                        echo "unknown" ;;
    esac
  else
    echo "unknown"
  fi
}

DISTRO="$(detect_distro)"
if [[ "$DISTRO" == "unknown" ]]; then
  err "Unsupported distribution. This script supports Arch Linux and Ubuntu."
  exit 1
fi
ok "Detected distribution: $DISTRO"

# ---------------------------------------------------------------------------
# Detect GPU
# ---------------------------------------------------------------------------
detect_gpu() {
  if command -v lspci >/dev/null 2>&1; then
    if lspci | grep -i vga | grep -iq "nvidia"; then
      echo "nvidia"
    elif lspci | grep -i vga | grep -iq "amd\|ati"; then
      echo "amd"
    else
      echo "unknown"
    fi
  else
    echo "unknown"
  fi
}

GPU="$(detect_gpu)"
if [[ "$GPU" != "unknown" ]]; then
  ok "Detected GPU: $GPU"
else
  warn "Could not detect GPU vendor. GPU-specific packages will be skipped."
fi

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
check_deps() {
  local missing=()
  for cmd in git curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    info "Please install them first."
    exit 1
  fi

  # Need yq or python to parse YAML
  if command -v yq >/dev/null 2>&1; then
    YAML_PARSER="yq"
  elif command -v python3 >/dev/null 2>&1; then
    YAML_PARSER="python3"
  else
    err "Need either 'yq' or 'python3' to parse packages.yaml"
    exit 1
  fi
  ok "YAML parser: $YAML_PARSER"
}

# ---------------------------------------------------------------------------
# YAML parsing helpers
# ---------------------------------------------------------------------------
parse_yaml() {
  local yaml_file="$1"

  if [[ "$YAML_PARSER" == "yq" ]]; then
    yq -o=json "$yaml_file"
  else
    python3 -c '
import sys, json, yaml
try:
    from yaml import safe_load
except ImportError:
    import subprocess, os
    # Try to install pyyaml
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "pyyaml"])
    from yaml import safe_load
data = safe_load(sys.stdin)
json.dump(data, sys.stdout)
' < "$yaml_file"
  fi
}

# ---------------------------------------------------------------------------
# Package installation
# ---------------------------------------------------------------------------
install_pkg_pacman() {
  local pkg="$1"
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would install via pacman: $pkg"
    return 0
  fi
  info "Installing via pacman: $pkg"
  sudo pacman -S --needed --noconfirm "$pkg"
}

install_pkg_yay() {
  local pkg="$1"
  if ! command -v yay >/dev/null 2>&1; then
    warn "yay not found, skipping AUR package: $pkg"
    return 1
  fi
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would install via yay: $pkg"
    return 0
  fi
  info "Installing via yay: $pkg"
  yay -S --needed --noconfirm "$pkg"
}

install_pkg_apt() {
  local pkg="$1"
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would install via apt: $pkg"
    return 0
  fi
  info "Installing via apt: $pkg"
  sudo apt update
  sudo apt install -y "$pkg"
}

run_script() {
  local script_path="$1"
  local full_path="${SCRIPT_DIR}/${script_path}"

  if [[ ! -f "$full_path" ]]; then
    err "Script not found: $full_path"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would run script: $script_path"
    return 0
  fi

  info "Running script: $script_path"
  bash "$full_path"
}

# ---------------------------------------------------------------------------
# Process packages from YAML
# ---------------------------------------------------------------------------
install_packages() {
  if [[ ! -f "$PACKAGES_YAML" ]]; then
    err "packages.yaml not found at $PACKAGES_YAML"
    exit 1
  fi

  info "Parsing packages.yaml..."

  local json_data
  json_data="$(parse_yaml "$PACKAGES_YAML")"

  # Get number of packages
  local count
  count="$(echo "$json_data" | python3 -c 'import sys, json; print(len(json.load(sys.stdin).get("packages", [])))')"

  info "Found $count package entries"

  for ((i=0; i<count; i++)); do
    local pkg_json
    pkg_json="$(echo "$json_data" | python3 -c "import sys, json; import json; d=json.load(sys.stdin); print(json.dumps(d['packages'][$i]))")"

    local name
    name="$(echo "$pkg_json" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("name", ""))')"

    local condition
    condition="$(echo "$pkg_json" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("condition", "always"))')"

    # Check condition
    case "$condition" in
      gpu_amd)
        if [[ "$GPU" != "amd" ]]; then
          info "Skipping $name (condition: gpu_amd, detected: $GPU)"
          continue
        fi
        ;;
      gpu_nvidia)
        if [[ "$GPU" != "nvidia" ]]; then
          info "Skipping $name (condition: gpu_nvidia, detected: $GPU)"
          continue
        fi
        ;;
    esac

    # Get distro-specific config
    local distro_config
    distro_config="$(echo "$pkg_json" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d.get('$DISTRO')))")"

    if [[ "$distro_config" == "null" ]]; then
      info "Skipping $name (not available on $DISTRO)"
      continue
    fi

    local install_type
    install_type="$(echo "$distro_config" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("type", "")) if isinstance(d, dict) else ""')"

    local package_name
    package_name="$(echo "$distro_config" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("package", "")) if isinstance(d, dict) else ""')"

    local script_path
    script_path="$(echo "$distro_config" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("script", "")) if isinstance(d, dict) else ""')"

    # Default package name to entry name if not specified
    if [[ -z "$package_name" ]]; then
      package_name="$name"
    fi

    case "$install_type" in
      pacman)
        install_pkg_pacman "$package_name" || warn "Failed to install $name"
        ;;
      yay)
        install_pkg_yay "$package_name" || warn "Failed to install $name"
        ;;
      apt)
        install_pkg_apt "$package_name" || warn "Failed to install $name"
        ;;
      script)
        if [[ -n "$script_path" ]]; then
          run_script "$script_path" || warn "Failed to run script for $name"
        else
          warn "Script type specified but no script path for $name"
        fi
        ;;
      *)
        warn "Unknown install type '$install_type' for $name"
        ;;
    esac
  done

  ok "Package installation complete"
}

# ---------------------------------------------------------------------------
# Dotfiles installation via yadm
# ---------------------------------------------------------------------------
install_dotfiles() {
  info "Setting up dotfiles with yadm..."

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would clone yadm repo and checkout dotfiles"
    return 0
  fi

  # Install yadm if missing
  if ! command -v yadm >/dev/null 2>&1; then
    info "Installing yadm..."
    case "$DISTRO" in
      arch)
        sudo pacman -S --needed --noconfirm yadm
        ;;
      ubuntu)
        sudo apt install -y yadm
        ;;
    esac
  fi

  # Check if yadm is already initialized
  if [[ -d "$HOME/.local/share/yadm/repo.git" ]]; then
    warn "Yadm repo already exists. Pulling latest changes..."
    yadm pull || warn "Could not pull changes"
  else
    info "Cloning dotfiles repository..."
    read -rp "Enter your dotfiles repo URL (e.g., https://github.com/username/dotfiles.git): " repo_url
    yadm clone "$repo_url"
  fi

  # Ensure ~/.local/bin is in PATH
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    warn "~/.local/bin is not in PATH. Add the following to your shell rc file:"
    echo 'export PATH="$HOME/.local/bin:$PATH"'
  fi

  ok "Dotfiles setup complete"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  info "Dotfiles Installer"
  info "=================="
  info "Distro: $DISTRO"
  info "GPU:    $GPU"
  if [[ "$DRY_RUN" == true ]]; then
    warn "DRY RUN MODE - no changes will be made"
  fi
  echo

  check_deps

  if [[ "$DO_PACKAGES" == true ]]; then
    install_packages
  fi

  if [[ "$DO_DOTFILES" == true ]]; then
    install_dotfiles
  fi

  ok "All done!"
}

main "$@"
