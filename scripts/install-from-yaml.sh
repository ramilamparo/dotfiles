#!/usr/bin/env bash
# Install packages declared in packages.yaml.
#
# Invoked by chezmoi (run_onchange_after_install_packages.sh.tmpl) on apply,
# or directly from the source dir:
#   cd "$(chezmoi source-path)"
#   ./scripts/install-from-yaml.sh ./packages.yaml \
#       [--dry-run] [--skip a,b] [--skip-group sway,gpu] [--force chromium] [--yes]
#
# Env vars (read first, CLI flags override):
#   DOTFILES_SKIP         comma-separated names to skip
#   DOTFILES_SKIP_GROUP   comma-separated groups to skip
#   DOTFILES_FORCE        comma-separated names to force-install (overrides skip)
#   DOTFILES_DRY_RUN      "1" -> preview only
#   DOTFILES_YES          "1" -> auto-confirm action plan
#
# Skip rule per entry:
#   1. In SKIP / SKIP_GROUP, unless in FORCE.
#   2. Any dep is in skip set (transitive).
#   3. command -v <binary> succeeds.
#   4. No binary defined AND config_path exists.

set -euo pipefail

# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
PACKAGES_YAML="${1:-}"
shift || true

SKIP_LIST="${DOTFILES_SKIP:-}"
SKIP_GROUP_LIST="${DOTFILES_SKIP_GROUP:-}"
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
    --force)          FORCE_LIST="${FORCE_LIST:+$FORCE_LIST,}$2"; shift 2 ;;
    --force=*)        FORCE_LIST="${FORCE_LIST:+$FORCE_LIST,}${1#--force=}"; shift ;;
    *) err "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$PACKAGES_YAML" || ! -f "$PACKAGES_YAML" ]]; then
  err "Usage: $0 <packages.yaml> [flags]"
  err "packages.yaml not found: $PACKAGES_YAML"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Detect distro / GPU
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
    elif lspci 2>/dev/null | grep -i vga | grep -iq "amd\|ati"; then echo "amd"
    else echo "unknown"
    fi
  else
    echo "unknown"
  fi
}

DISTRO="$(detect_distro)"
GPU="$(detect_gpu)"

if [[ "$DISTRO" == "unknown" ]]; then
  err "Unsupported distribution. Supports Arch and Ubuntu families."
  exit 1
fi

ok "Distro: $DISTRO  GPU: $GPU"
[[ "$DRY_RUN" == "1" ]] && warn "DRY-RUN MODE — no changes will be made"

# ---------------------------------------------------------------------------
# YAML parser pick
# ---------------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  PY=python3
else
  err "python3 is required to parse packages.yaml"
  exit 1
fi

# ---------------------------------------------------------------------------
# Build action plan (fixed-point dep propagation in Python)
# ---------------------------------------------------------------------------
PLAN_JSON=$($PY - "$PACKAGES_YAML" "$DISTRO" "$GPU" \
              "$SKIP_LIST" "$SKIP_GROUP_LIST" "$FORCE_LIST" <<'PY'
import json, os, shutil, subprocess, sys
from pathlib import Path

try:
    import yaml
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "--quiet", "pyyaml"])
    import yaml

yaml_path, distro, gpu, skip_csv, skip_grp_csv, force_csv = sys.argv[1:7]
skip_set  = {x.strip() for x in skip_csv.split(",") if x.strip()}
skip_grps = {x.strip() for x in skip_grp_csv.split(",") if x.strip()}
force_set = {x.strip() for x in force_csv.split(",") if x.strip()}

with open(yaml_path) as f:
    data = yaml.safe_load(f)
entries = data.get("packages", []) or []

def expand(p):
    if not p:
        return p
    return os.path.expanduser(os.path.expandvars(p))

def which(b):
    if not b:
        return None
    return shutil.which(b)

def initial_skip(e):
    """
    Returns (reason, propagate) tuple, or None if entry is not skipped.
    propagate=True means dependents should also skip (dep won't be available).
    propagate=False means the dep IS available (already installed) so dependents don't propagate.
    """
    name  = e.get("name")
    group = e.get("group", "")
    cond  = e.get("condition", "always")
    distro_cfg = e.get(distro)

    if name in force_set:
        return None  # force overrides everything

    if cond == "gpu_amd"    and gpu != "amd":    return (f"condition gpu_amd (got {gpu})", True)
    if cond == "gpu_nvidia" and gpu != "nvidia": return (f"condition gpu_nvidia (got {gpu})", True)

    if distro_cfg is None:
        return (f"not available on {distro}", True)

    if name in skip_set:
        return ("DOTFILES_SKIP", True)
    if group in skip_grps:
        return (f"DOTFILES_SKIP_GROUP={group}", True)

    binary = e.get("binary", name)
    cfg    = expand(e.get("config_path"))

    if binary:
        path = which(binary)
        if path:
            tag = " [snap]" if path.startswith("/snap/") else ""
            return (f"binary on PATH ({path}){tag}", False)
    elif cfg and Path(cfg).exists():
        return (f"config_path exists ({cfg})", False)

    return None  # not skipped

by_name = {e["name"]: e for e in entries}
skip_reasons = {}     # name -> reason str
unavailable = set()   # names whose absence propagates to dependents
for e in entries:
    r = initial_skip(e)
    if r is not None:
        reason, propagate = r
        skip_reasons[e["name"]] = reason
        if propagate:
            unavailable.add(e["name"])

# Fixed-point: propagate dep skips (only for unavailable deps)
changed = True
while changed:
    changed = False
    for e in entries:
        name = e["name"]
        if name in skip_reasons or name in force_set:
            continue
        deps = e.get("dependencies", []) or []
        for d in deps:
            if d in unavailable:
                skip_reasons[name] = f"dep {d} unavailable"
                unavailable.add(name)
                changed = True
                break

# Build plan
plan = []
for e in entries:
    name  = e["name"]
    group = e.get("group", "")
    distro_cfg = e.get(distro)
    if name in skip_reasons and name not in force_set:
        plan.append({"name": name, "group": group, "action": "skip", "reason": skip_reasons[name]})
        continue
    if distro_cfg is None:
        plan.append({"name": name, "group": group, "action": "skip", "reason": f"not available on {distro}"})
        continue

    itype = distro_cfg.get("type", "")
    pkg   = distro_cfg.get("package") or name
    sp    = distro_cfg.get("script", "")
    target = sp if itype == "script" else pkg

    snap_path = ""
    binary = e.get("binary", name)
    if binary:
        p = which(binary)
        if p and p.startswith("/snap/"):
            snap_path = p

    plan.append({
        "name": name, "group": group, "action": "install",
        "method": itype, "target": target,
        "snap_path": snap_path,
    })

print(json.dumps(plan))
PY
)

if [[ -z "$PLAN_JSON" ]]; then
  err "Action plan generation failed"
  exit 1
fi

# ---------------------------------------------------------------------------
# Print plan + confirm
# ---------------------------------------------------------------------------
print_plan() {
  echo
  info "Action plan:"
  echo "$PLAN_JSON" | $PY -c '
import json, sys
plan = json.load(sys.stdin)
nlen = max((len(p["name"]) for p in plan), default=4)
for p in plan:
    name   = p["name"]
    action = p["action"]
    if action == "skip":
        reason = p["reason"]
        print(f"  {name:<{nlen}}  skip       {reason}")
    else:
        snap   = " [snap]" if p.get("snap_path") else ""
        method = p["method"]
        target = p["target"]
        print(f"  {name:<{nlen}}  install    {method}:{target}{snap}")
inst = sum(1 for p in plan if p["action"] == "install")
skip = sum(1 for p in plan if p["action"] == "skip")
print(f"\nSummary: install={inst}  skip={skip}")
'
}

print_plan

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
echo "$PLAN_JSON" | $PY -c '
import json, sys
for p in json.load(sys.stdin):
    if p["action"] == "install":
        name = p["name"]; method = p["method"]; target = p["target"]; snap = p.get("snap_path","")
        print(f"{name}\t{method}\t{target}\t{snap}")
' | while IFS=$'\t' read -r name method target snap_path; do
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
