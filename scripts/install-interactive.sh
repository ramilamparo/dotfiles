#!/usr/bin/env bash
# Interactive package picker.
# Lets you tab-select packages from packages.yaml via fzf, then hands the
# selection off to install-from-yaml.sh as --only <names>. Dependencies of
# selected packages are auto-included by the worker.
#
# Usage:
#   ./scripts/install-interactive.sh [packages.yaml] [-- <passthrough flags>]
#
# Examples:
#   ./scripts/install-interactive.sh                     # default packages.yaml
#   ./scripts/install-interactive.sh -- --dry-run        # preview install
#   ./scripts/install-interactive.sh -- --yes            # skip confirmation
#
# Anything after `--` is forwarded verbatim to install-from-yaml.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/install-common.sh
source "$SCRIPT_DIR/lib/install-common.sh"

# ---------------------------------------------------------------------------
# Args: optional packages.yaml positional, then `--` passthrough.
# ---------------------------------------------------------------------------
PACKAGES_YAML=""
PASSTHROUGH=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift; PASSTHROUGH=("$@"); break ;;
    -h|--help)
      # Print the leading comment block (everything from line 2 up to the
      # first blank line), with the leading "# " stripped.
      awk 'NR==1{next} /^[[:space:]]*$/{exit} {sub(/^# ?/,""); print}' \
        "${BASH_SOURCE[0]}"
      exit 0 ;;
    *)
      if [[ -z "$PACKAGES_YAML" ]]; then
        PACKAGES_YAML="$1"
      else
        err "Unexpected argument: $1"; exit 1
      fi
      shift ;;
  esac
done

PACKAGES_YAML="${PACKAGES_YAML:-$SCRIPT_DIR/../packages.yaml}"

if [[ ! -f "$PACKAGES_YAML" ]]; then
  err "packages.yaml not found: $PACKAGES_YAML"
  exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
  err "fzf is required for interactive mode."
  err "Install: 'sudo apt install fzf' (Ubuntu) or 'sudo pacman -S fzf' (Arch)."
  exit 1
fi

ensure_yq

# ---------------------------------------------------------------------------
# Load metadata
# ---------------------------------------------------------------------------
DISTRO="$(detect_distro)"
GPU="$(detect_gpu)"

if [[ "$DISTRO" == "unknown" ]]; then
  err "Unsupported distribution. Supports Arch and Ubuntu families."
  exit 1
fi

declare -A P_GROUP P_BINARY P_CONFIG P_COND P_DEPS
declare -A P_ARCH_TYPE P_ARCH_PKG P_ARCH_SCRIPT
declare -A P_UBU_TYPE P_UBU_PKG P_UBU_SCRIPT
NAMES=()
load_packages "$PACKAGES_YAML"

# ---------------------------------------------------------------------------
# Build picker rows. Tab-separated:
#   <status>\t<name>\t<group>\t<hint>
# Status legend (also shown in fzf header):
#   available   eligible to install on this host
#   installed   binary already on PATH (selecting → no-op)
#   unavail     filtered out (wrong distro / GPU); not selectable
# ---------------------------------------------------------------------------
classify() {
  local name="$1"
  local binary path cond dtype

  binary="${P_BINARY[$name]}"
  [[ -z "$binary" ]] && binary="$name"
  cond="${P_COND[$name]}"

  if [[ "$DISTRO" == "arch" ]]; then
    dtype="${P_ARCH_TYPE[$name]}"
  else
    dtype="${P_UBU_TYPE[$name]}"
  fi

  if [[ -z "$dtype" ]]; then
    echo -e "unavail\tnot on $DISTRO"; return
  fi
  if [[ "$cond" == "gpu_amd"    && "$GPU" != "amd"    ]]; then
    echo -e "unavail\tneeds amd GPU (got $GPU)"; return
  fi
  if [[ "$cond" == "gpu_nvidia" && "$GPU" != "nvidia" ]]; then
    echo -e "unavail\tneeds nvidia GPU (got $GPU)"; return
  fi
  if path=$(which_cmd "$binary"); then
    echo -e "installed\t$path"; return
  fi
  echo -e "available\t$dtype"
}

# Build rows; keep the original yaml order for predictable scrolling.
ROWS=()
for name in "${NAMES[@]}"; do
  IFS=$'\t' read -r status hint < <(classify "$name")
  group="${P_GROUP[$name]}"
  printf -v row "%-9s\t%-20s\t%-9s\t%s" "$status" "$name" "$group" "$hint"
  ROWS+=("$row")
done

# ---------------------------------------------------------------------------
# fzf picker
# ---------------------------------------------------------------------------
HEADER='[available] = will install   [installed] = no-op   [unavail] = ineligible
TAB to multi-select   ENTER to confirm   ESC to abort'

SELECTION=$(printf '%s\n' "${ROWS[@]}" \
  | fzf --multi \
        --header="$HEADER" \
        --prompt='packages> ' \
        --reverse \
        --height=80% \
        --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
  ) || true

if [[ -z "$SELECTION" ]]; then
  warn "Nothing selected. Aborting."
  exit 0
fi

# Extract column 2 (name) from each selected row. Fields are tab-separated
# but space-padded for fzf alignment, so strip whitespace from the bits we
# care about (status / name have no internal whitespace).
SELECTED=()
SKIPPED_UNAVAIL=()
while IFS= read -r line; do
  IFS=$'\t' read -r status name _group _hint <<< "$line"
  status="${status//[[:space:]]/}"
  name="${name//[[:space:]]/}"
  if [[ "$status" == "unavail" ]]; then
    SKIPPED_UNAVAIL+=("$name")
    continue
  fi
  SELECTED+=("$name")
done <<< "$SELECTION"

if (( ${#SKIPPED_UNAVAIL[@]} > 0 )); then
  warn "Dropping ineligible selections: ${SKIPPED_UNAVAIL[*]}"
fi

if (( ${#SELECTED[@]} == 0 )); then
  warn "No installable packages selected."
  exit 0
fi

ONLY_LIST="$(IFS=,; echo "${SELECTED[*]}")"
info "Selected: $ONLY_LIST"

# ---------------------------------------------------------------------------
# Hand off to the worker. exec replaces this process so signals/exit codes
# pass through cleanly.
# ---------------------------------------------------------------------------
exec "$SCRIPT_DIR/install-from-yaml.sh" "$PACKAGES_YAML" \
  --only "$ONLY_LIST" \
  "${PASSTHROUGH[@]}"
