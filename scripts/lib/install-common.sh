#!/usr/bin/env bash
# Reusable helpers for install-from-yaml.sh / install-interactive.sh.
# Source this file; do NOT execute it directly. Strict mode (set -euo pipefail)
# is left to the caller so sourcing is non-opinionated.

# ---------------------------------------------------------------------------
# Color codes / log helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# yq bootstrap (downloads from upstream releases if missing)
# ---------------------------------------------------------------------------
ensure_yq() {
  if command -v yq >/dev/null 2>&1; then
    return 0
  fi

  local arch platform
  arch=$(uname -m)
  case "$arch" in
    x86_64)  platform="linux_amd64" ;;
    aarch64) platform="linux_arm64" ;;
    armv7l)  platform="linux_arm" ;;
    *)       err "Unsupported arch for yq: $arch"; exit 1 ;;
  esac

  info "Installing yq (required to parse packages.yaml)..."
  wget -q "https://github.com/mikefarah/yq/releases/latest/download/yq_${platform}" -O /tmp/yq
  chmod +x /tmp/yq
  sudo mv /tmp/yq /usr/local/bin/yq
}

# ---------------------------------------------------------------------------
# Host detection
# ---------------------------------------------------------------------------
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    case "${ID:-}" in
      arch|manjaro|endeavouros) echo "arch" ;;
      ubuntu|debian|pop|kubuntu) echo "ubuntu" ;;
      *) echo "unknown" ;;
    esac
  else
    echo "unknown"
  fi
}

detect_gpu() {
  if command -v lspci >/dev/null 2>&1; then
    if lspci 2>/dev/null | grep -i vga | grep -iq "nvidia"; then echo "nvidia"
    elif lspci 2>/dev/null | grep -i vga | grep -iq "amd\\|ati"; then echo "amd"
    else echo "unknown"
    fi
  else
    echo "unknown"
  fi
}

# command -v wrapper that returns the path; non-empty arg required.
which_cmd() {
  if [[ -z "${1:-}" ]]; then
    return 1
  fi
  command -v "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Load packages.yaml into caller-scope arrays.
#
# Caller MUST declare these before calling:
#   declare -A P_GROUP P_BINARY P_CONFIG P_COND P_DEPS
#   declare -A P_ARCH_TYPE P_ARCH_PKG P_ARCH_SCRIPT
#   declare -A P_UBU_TYPE P_UBU_PKG P_UBU_SCRIPT
#   NAMES=()
#
# Usage: load_packages <path-to-packages.yaml>
# ---------------------------------------------------------------------------
load_packages() {
  local yaml="$1"
  local -a lines
  local line name group binary config cond deps
  local atype apkg ascript utype upkg uscript

  mapfile -t lines < <(yq -r '
    .packages[] |
    [
      .name,
      (.group // ""),
      (.binary // ""),
      (.config_path // ""),
      (.condition // "always"),
      ((.dependencies // []) | join(",")),
      (.arch.type // ""),
      (.arch.package // ""),
      (.arch.script // ""),
      (.ubuntu.type // ""),
      (.ubuntu.package // ""),
      (.ubuntu.script // "")
    ] | @tsv
  ' "$yaml")

  if [[ ${#lines[@]} -eq 0 ]]; then
    err "No packages found in $yaml"
    return 1
  fi

  for line in "${lines[@]}"; do
    name=$(echo "$line"    | cut -f1)
    group=$(echo "$line"   | cut -f2)
    binary=$(echo "$line"  | cut -f3)
    config=$(echo "$line"  | cut -f4)
    cond=$(echo "$line"    | cut -f5)
    deps=$(echo "$line"    | cut -f6)
    atype=$(echo "$line"   | cut -f7)
    apkg=$(echo "$line"    | cut -f8)
    ascript=$(echo "$line" | cut -f9)
    utype=$(echo "$line"   | cut -f10)
    upkg=$(echo "$line"    | cut -f11)
    uscript=$(echo "$line" | cut -f12)

    NAMES+=("$name")
    P_GROUP[$name]="$group"
    P_BINARY[$name]="$binary"
    P_CONFIG[$name]="$config"
    P_COND[$name]="$cond"
    P_DEPS[$name]="$deps"
    P_ARCH_TYPE[$name]="$atype"
    P_ARCH_PKG[$name]="$apkg"
    P_ARCH_SCRIPT[$name]="$ascript"
    P_UBU_TYPE[$name]="$utype"
    P_UBU_PKG[$name]="$upkg"
    P_UBU_SCRIPT[$name]="$uscript"
  done
}
