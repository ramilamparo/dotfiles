#!/usr/bin/env bash
# Install packages declared in packages.yaml.
#
# Invoked by chezmoi (run_onchange_after_install_packages.sh) on apply,
# or directly from the source dir:
#   cd "$(chezmoi source-path)"
#   ./scripts/install-from-yaml.sh ./packages.yaml \\
#       [--dry-run] [--skip a,b] [--skip-group sway,gpu] \\
#       [--only c,d] [--only-group shell] \\
#       [--force chromium] [--yes]
#
# Env vars (read first, CLI flags override):
#   DOTFILES_SKIP         comma-separated names to skip
#   DOTFILES_SKIP_GROUP   comma-separated groups to skip
#   DOTFILES_ONLY         comma-separated names to allow (others skipped)
#   DOTFILES_ONLY_GROUP   comma-separated groups to allow
#   DOTFILES_FORCE        comma-separated names to force-install
#                         (overrides SKIP, SKIP_GROUP, ONLY, ONLY_GROUP)
#   DOTFILES_DRY_RUN      "1" -> preview only
#   DOTFILES_YES          "1" -> auto-confirm action plan
#
# Skip rule per entry (FORCE overrides every rule below):
#   1. Distro / GPU condition does not match host.
#   2. Listed in SKIP, or group listed in SKIP_GROUP.
#   3. ONLY-mode active (ONLY or ONLY_GROUP non-empty) AND entry is
#      neither in the allowlist nor a transitive dep of an allowlisted
#      entry. Deps of allowlisted packages are auto-included.
#   4. Any dep is in the skip set (transitive propagation).
#   5. `command -v <binary>` succeeds (already installed).
#   6. No binary defined AND config_path exists.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/install-common.sh
source "$SCRIPT_DIR/lib/install-common.sh"

ensure_yq

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
PACKAGES_YAML="${1:-}"
shift || true

SKIP_LIST="${DOTFILES_SKIP:-}"
SKIP_GROUP_LIST="${DOTFILES_SKIP_GROUP:-}"
ONLY_LIST="${DOTFILES_ONLY:-}"
ONLY_GROUP_LIST="${DOTFILES_ONLY_GROUP:-}"
FORCE_LIST="${DOTFILES_FORCE:-}"
DRY_RUN="${DOTFILES_DRY_RUN:-0}"
YES="${DOTFILES_YES:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=1; shift ;;
    --yes)            YES=1; shift ;;
    --skip)           SKIP_LIST="${SKIP_LIST:+$SKIP_LIST,}$2"; shift 2 ;;
    --skip=*)         SKIP_LIST="${SKIP_LIST:+$SKIP_LIST,}${1#--skip=}"; shift ;;
    --skip-group)     SKIP_GROUP_LIST="${SKIP_GROUP_LIST:+$SKIP_GROUP_LIST,}$2"; shift 2 ;;
    --skip-group=*)   SKIP_GROUP_LIST="${SKIP_GROUP_LIST:+$SKIP_GROUP_LIST,}${1#--skip-group=}"; shift ;;
    --only)           ONLY_LIST="${ONLY_LIST:+$ONLY_LIST,}$2"; shift 2 ;;
    --only=*)         ONLY_LIST="${ONLY_LIST:+$ONLY_LIST,}${1#--only=}"; shift ;;
    --only-group)     ONLY_GROUP_LIST="${ONLY_GROUP_LIST:+$ONLY_GROUP_LIST,}$2"; shift 2 ;;
    --only-group=*)   ONLY_GROUP_LIST="${ONLY_GROUP_LIST:+$ONLY_GROUP_LIST,}${1#--only-group=}"; shift ;;
    --force)          FORCE_LIST="${FORCE_LIST:+$FORCE_LIST,}$2"; shift 2 ;;
    --force=*)        FORCE_LIST="${FORCE_LIST:+$FORCE_LIST,}${1#--force=}"; shift ;;
    *) err "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$PACKAGES_YAML" || ! -f "$PACKAGES_YAML" ]]; then
  err "Usage: $0 <packages.yaml> [flags]"
  err "packages.yaml not found: ${PACKAGES_YAML:-<empty>}"
  exit 1
fi

DISTRO="$(detect_distro)"
GPU="$(detect_gpu)"

if [[ "$DISTRO" == "unknown" ]]; then
  err "Unsupported distribution. Supports Arch and Ubuntu families."
  exit 1
fi

ok "Distro: $DISTRO  GPU: $GPU"
[[ "$DRY_RUN" == "1" ]] && warn "DRY-RUN MODE — no changes will be made"

# ---------------------------------------------------------------------------
# Load packages.yaml into bash arrays via the shared library
# ---------------------------------------------------------------------------
declare -A P_GROUP P_BINARY P_CONFIG P_COND P_DEPS
declare -A P_ARCH_TYPE P_ARCH_PKG P_ARCH_SCRIPT
declare -A P_UBU_TYPE P_UBU_PKG P_UBU_SCRIPT
NAMES=()
load_packages "$PACKAGES_YAML"

# ---------------------------------------------------------------------------
# Build skip / install sets
# ---------------------------------------------------------------------------
# Normalise env vars into bash arrays
IFS=',' read -ra SKIP_ARR     <<< "$SKIP_LIST"
IFS=',' read -ra SKIP_GRP     <<< "$SKIP_GROUP_LIST"
IFS=',' read -ra ONLY_ARR     <<< "$ONLY_LIST"
IFS=',' read -ra ONLY_GRP_ARR <<< "$ONLY_GROUP_LIST"
IFS=',' read -ra FORCE_ARR    <<< "$FORCE_LIST"

declare -A SKIP_SET SKIP_GRP_SET ONLY_SET ONLY_GRP_SET FORCE_SET
for s in "${SKIP_ARR[@]}";     do [[ -n "$s" ]] && SKIP_SET[${s// /}]=1; done
for s in "${SKIP_GRP[@]}";     do [[ -n "$s" ]] && SKIP_GRP_SET[${s// /}]=1; done
for s in "${ONLY_ARR[@]}";     do [[ -n "$s" ]] && ONLY_SET[${s// /}]=1; done
for s in "${ONLY_GRP_ARR[@]}"; do [[ -n "$s" ]] && ONLY_GRP_SET[${s// /}]=1; done
for s in "${FORCE_ARR[@]}";    do [[ -n "$s" ]] && FORCE_SET[${s// /}]=1; done

# Allowlist mode active iff either ONLY or ONLY_GROUP is non-empty.
# (Use the original strings, not the array; empty assoc arrays trip `set -u`.)
ONLY_MODE=0
if [[ -n "$ONLY_LIST" || -n "$ONLY_GROUP_LIST" ]]; then
  ONLY_MODE=1

  # Seed ONLY_SET with every package whose group is allowlisted.
  for name in "${NAMES[@]}"; do
    g="${P_GROUP[$name]}"
    if [[ -n "${ONLY_GRP_SET[$g]:-}" ]]; then
      ONLY_SET[$name]=1
    fi
  done

  # Auto-include transitive dependencies of allowlisted entries.
  changed=true
  while $changed; do
    changed=false
    for name in "${NAMES[@]}"; do
      [[ -z "${ONLY_SET[$name]:-}" ]] && continue
      IFS=',' read -ra deps <<< "${P_DEPS[$name]}"
      for d in "${deps[@]}"; do
        [[ -z "$d" ]] && continue
        if [[ -z "${ONLY_SET[$d]:-}" ]]; then
          ONLY_SET[$d]=1
          changed=true
        fi
      done
    done
  done
fi

# Pass 1: compute initial skip reason per package.
# Returns empty string if NOT skipped.
initial_skip() {
  local name="$1"

  if [[ -n "${FORCE_SET[$name]:-}" ]]; then
    echo ""  # force overrides everything
    return
  fi

  local cond="${P_COND[$name]}"
  if [[ "$cond" == "gpu_amd"    && "$GPU" != "amd"    ]]; then echo "condition gpu_amd (got $GPU)"; return; fi
  if [[ "$cond" == "gpu_nvidia" && "$GPU" != "nvidia" ]]; then echo "condition gpu_nvidia (got $GPU)"; return; fi

  # distro availability
  local dtype dpkg dscript
  if [[ "$DISTRO" == "arch" ]]; then
    dtype="${P_ARCH_TYPE[$name]}"
  else
    dtype="${P_UBU_TYPE[$name]}"
  fi
  if [[ -z "$dtype" ]]; then
    echo "not available on $DISTRO"
    return
  fi

  # skip lists
  if [[ -n "${SKIP_SET[$name]:-}" ]]; then
    echo "DOTFILES_SKIP"
    return
  fi
  if [[ -n "${SKIP_GRP_SET[${P_GROUP[$name]}]:-}" ]]; then
    echo "DOTFILES_SKIP_GROUP=${P_GROUP[$name]}"
    return
  fi

  # allowlist (only mode)
  if [[ "$ONLY_MODE" == "1" && -z "${ONLY_SET[$name]:-}" ]]; then
    echo "not in DOTFILES_ONLY"
    return
  fi

  # binary / config_path signal
  local binary="${P_BINARY[$name]}"
  [[ -z "$binary" ]] && binary="$name"

  local path
  if path=$(which_cmd "$binary"); then
    if [[ "$path" == /snap/* ]]; then
      echo "binary on PATH ($path) [snap]"
    else
      echo "binary on PATH ($path)"
    fi
    return
  fi

  local cfg="${P_CONFIG[$name]}"
  if [[ -z "$binary" && -n "$cfg" && -e "${cfg/#\~/$HOME}" ]]; then
    echo "config_path exists ($cfg)"
    return
  fi

  echo ""  # not skipped
}

declare -A SKIP_REASON UNAVAILABLE
for name in "${NAMES[@]}"; do
  reason=$(initial_skip "$name")
  if [[ -n "$reason" ]]; then
    SKIP_REASON[$name]="$reason"
    # If the reason indicates the dep is unavailable (not just already-installed
    # or filtered out by the user's allowlist), mark it for propagation.
    # Already-installed reasons contain "on PATH" or "exists".
    # "not in DOTFILES_ONLY" never propagates because deps were auto-expanded
    # into ONLY_SET, so no allowlisted package depends on a filtered one.
    if [[ ! "$reason" =~ (on PATH|exists|not in DOTFILES_ONLY) ]]; then
      UNAVAILABLE[$name]=1
    fi
  fi
done

# Pass 2: fixed-point propagate dep skips (only unavailable deps propagate)
changed=true
while $changed; do
  changed=false
  for name in "${NAMES[@]}"; do
    [[ -n "${SKIP_REASON[$name]:-}" ]] && continue
    [[ -n "${FORCE_SET[$name]:-}" ]] && continue

    IFS=',' read -ra deps <<< "${P_DEPS[$name]}"
    for d in "${deps[@]}"; do
      [[ -z "$d" ]] && continue
      if [[ -n "${UNAVAILABLE[$d]:-}" ]]; then
        SKIP_REASON[$name]="dep $d unavailable"
        UNAVAILABLE[$name]=1
        changed=true
        break
      fi
    done
  done
done

# ---------------------------------------------------------------------------
# Build plan arrays (preserve original order)
# ---------------------------------------------------------------------------
PLAN_NAMES=()
PLAN_ACTIONS=()   # install | skip
PLAN_METHODS=()   # pacman | yay | apt | script
PLAN_TARGETS=()   # package name or script path
PLAN_SNAPS=()     # snap path or ""
PLAN_REASONS=()   # skip reason

for name in "${NAMES[@]}"; do
  PLAN_NAMES+=("$name")

  if [[ -n "${SKIP_REASON[$name]:-}" && -z "${FORCE_SET[$name]:-}" ]]; then
    PLAN_ACTIONS+=("skip")
    PLAN_METHODS+=("")
    PLAN_TARGETS+=("")
    PLAN_SNAPS+=("")
    PLAN_REASONS+=("${SKIP_REASON[$name]}")
    continue
  fi

  dtype=""; dpkg=""; dscript=""
  if [[ "$DISTRO" == "arch" ]]; then
    dtype="${P_ARCH_TYPE[$name]}"
    dpkg="${P_ARCH_PKG[$name]}"
    dscript="${P_ARCH_SCRIPT[$name]}"
  else
    dtype="${P_UBU_TYPE[$name]}"
    dpkg="${P_UBU_PKG[$name]}"
    dscript="${P_UBU_SCRIPT[$name]}"
  fi

  if [[ -z "$dtype" ]]; then
    PLAN_ACTIONS+=("skip")
    PLAN_METHODS+=("")
    PLAN_TARGETS+=("")
    PLAN_SNAPS+=("")
    PLAN_REASONS+=("not available on $DISTRO")
    continue
  fi

  target=""
  if [[ "$dtype" == "script" ]]; then
    target="$dscript"
  else
    target="${dpkg:-$name}"
  fi

  # snap check
  snap_path=""
  binary="${P_BINARY[$name]}"
  [[ -z "$binary" ]] && binary="$name"
  if path=$(which_cmd "$binary" 2>/dev/null) && [[ "$path" == /snap/* ]]; then
    snap_path="$path"
  fi

  PLAN_ACTIONS+=("install")
  PLAN_METHODS+=("$dtype")
  PLAN_TARGETS+=("$target")
  PLAN_SNAPS+=("$snap_path")
  PLAN_REASONS+=("")
done

# ---------------------------------------------------------------------------
# Print plan + confirm
# ---------------------------------------------------------------------------
nlen=0
for name in "${PLAN_NAMES[@]}"; do
  ((${#name} > nlen)) && nlen=${#name}
done

echo
info "Action plan:"

inst=0; skip=0
for i in "${!PLAN_NAMES[@]}"; do
  name="${PLAN_NAMES[$i]}"
  action="${PLAN_ACTIONS[$i]}"
  if [[ "$action" == "skip" ]]; then
    printf "  %-${nlen}s  skip       %s\n" "$name" "${PLAN_REASONS[$i]}"
    skip=$((skip+1))
  else
    snap=""
    [[ -n "${PLAN_SNAPS[$i]}" ]] && snap=" [snap]"
    printf "  %-${nlen}s  install    %s:%s%s\n" "$name" "${PLAN_METHODS[$i]}" "${PLAN_TARGETS[$i]}" "$snap"
    inst=$((inst+1))
  fi
done

echo
echo "Summary: install=$inst  skip=$skip"

if [[ "$DRY_RUN" == "1" ]]; then
  info "Dry-run complete; no changes made."
  exit 0
fi

if [[ "$YES" != "1" ]] && [[ -t 0 ]]; then
  read -rp "Continue? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) info "Aborted."; exit 0 ;;
  esac
fi

# ---------------------------------------------------------------------------
# Install dispatch
# ---------------------------------------------------------------------------
install_pacman() { sudo pacman -S --needed --noconfirm "$1"; }
install_yay()    { command -v yay >/dev/null || { warn "yay missing, skipping $1"; return 1; }; yay -S --needed --noconfirm "$1"; }
install_apt()    { sudo apt-get update -qq && sudo apt-get install -y "$1"; }
run_script()     {
  local p="$SCRIPT_DIR/${1##scripts/}"
  if [[ ! -f "$p" ]]; then err "Script missing: $p"; return 1; fi
  bash "$p"
}

failed=0
for i in "${!PLAN_NAMES[@]}"; do
  [[ "${PLAN_ACTIONS[$i]}" == "skip" ]] && continue

  name="${PLAN_NAMES[$i]}"
  method="${PLAN_METHODS[$i]}"
  target="${PLAN_TARGETS[$i]}"
  snap_path="${PLAN_SNAPS[$i]}"

  if [[ -n "$snap_path" ]]; then
    warn "$name: snap version detected at $snap_path; install will create a duplicate."
  fi

  info "Installing $name ($method:$target)"
  case "$method" in
    pacman) install_pacman "$target" || { warn "Failed: $name"; failed=$((failed+1)); } ;;
    yay)    install_yay "$target"    || { warn "Failed: $name"; failed=$((failed+1)); } ;;
    apt)    install_apt "$target"    || { warn "Failed: $name"; failed=$((failed+1)); } ;;
    script) run_script "$target"     || { warn "Failed: $name"; failed=$((failed+1)); } ;;
    *)      warn "Unknown method '$method' for $name" ;;
  esac
done

ok "Done."
