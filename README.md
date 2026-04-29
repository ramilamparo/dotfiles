# Dotfiles

Personal system configuration managed with [chezmoi](https://chezmoi.io).
The repo deploys configs into `$HOME` and installs a curated package list
per distro (Arch / Ubuntu).

## Quick install (fresh system)

One-liner — installs chezmoi, clones this repo, applies everything, and
runs the package installer:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ramilamparo/dotfiles
```

Replace `ramilamparo/dotfiles` with your fork's `<user>/<repo>` if forked.

## Install on a system with existing config

If you already have a `~/.zshrc`, `~/.bashrc`, etc. that you want to
preserve, do **not** use `--apply` on the first run — preview first:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init ramilamparo/dotfiles
chezmoi diff                     # preview every file change
chezmoi apply --interactive      # prompt per file
# or selectively merge:
chezmoi merge ~/.zshrc
chezmoi merge ~/.bashrc
chezmoi apply ~/.config/sway     # apply just one path
```

`chezmoi merge` opens your configured merge tool (vimdiff by default)
with three panes: source (repo), destination (current `$HOME`), and the
merged result.

## Updating after pulling upstream changes

```bash
chezmoi update                   # git pull + chezmoi apply
chezmoi merge <path>             # if a file has local edits and conflicts
```

## Tracking new local changes

Use the AI skill at `skills/dotfiles-tracker/SKILL.md` from your AI
assistant ("track ~/.config/foo/config", "add package fastfetch"), or
do it manually:

```bash
chezmoi add ~/.config/foo/config         # copy local file into the repo
chezmoi add --encrypt ~/.config/secret   # for files with credentials
chezmoi cd                               # cd into the source dir
git add . && git commit -m "track foo"   # never push without intent
chezmoi forget ~/.config/foo/config      # untrack
```

## Per-machine config gating

`.chezmoiignore` at the repo root is rendered as a Go template, so we
gate configs on whether the relevant binary is installed. On a KDE box
without sway, `chezmoi diff` stays quiet about sway/waybar/wofi configs
because they're conditionally ignored:

```gotmpl
{{- if not (lookPath "sway") }}
.config/sway/**
.config/waybar/**
.config/wofi/**
{{- end }}
```

This is the same skip rule (`command -v <binary>`) the package installer
uses, so configs and packages stay in sync per host. Verify what's gated:

```bash
chezmoi ignored                       # what's hidden on this machine
chezmoi execute-template < "$(chezmoi source-path)/.chezmoiignore"
```

## Interactive picker

When `chezmoi apply` triggers the package phase and stdout is a TTY with
`fzf` installed, an interactive picker runs by default — tab-select the
packages you want, then `ENTER` to install. Otherwise (bootstrap, CI, no
fzf), apply falls back to the non-interactive worker, which installs
everything not already on PATH.

To run the picker manually:

```bash
cd "$(chezmoi source-path)"
./scripts/install-interactive.sh                   # tab-select, then install
./scripts/install-interactive.sh -- --dry-run      # preview without installing
./scripts/install-interactive.sh -- --yes          # skip the confirm prompt
```

The picker classifies each package as `available` / `installed` /
`unavail` (wrong distro/GPU), forwards your selection to the worker as
`--only`, and the worker auto-includes transitive dependencies.

## Skipping or forcing packages

The package installer reads env vars (because chezmoi's `run_onchange_*`
scripts don't take CLI args). Set them on the command line for one apply:

```bash
DOTFILES_SKIP=nvm,glow chezmoi apply               # skip by name
DOTFILES_SKIP_GROUP=sway chezmoi apply             # skip whole group
DOTFILES_ONLY=glow chezmoi apply                   # allowlist (deps auto-included)
DOTFILES_ONLY_GROUP=shell chezmoi apply            # allowlist whole group
DOTFILES_FORCE=chromium chezmoi apply              # overrides SKIP and ONLY
DOTFILES_DRY_RUN=1 chezmoi apply                   # preview package phase
DOTFILES_YES=1 chezmoi apply                       # skip the confirm prompt
```

You can also invoke the worker directly from the source dir:

```bash
cd "$(chezmoi source-path)"
./scripts/install-from-yaml.sh ./packages.yaml --skip-group sway --dry-run
./scripts/install-from-yaml.sh ./packages.yaml --only glow,fzf --dry-run
```

## What gets installed

Source of truth: `packages.yaml` at repo root.

| Group | Examples |
|---|---|
| `shell` | zsh, starship, nvm, neovim, fzf, jq, glow |
| `terminal` | ghostty |
| `sway` | sway, swaylock, swaync, waybar, wofi, brightnessctl |
| `gpu` | mesa-vulkan-drivers (AMD) / nvidia-driver-570 (NVIDIA) |
| `apps` | sunshine, flatpak, chromium |
| `fonts` | fonts-roboto |
| `dev` | go |
| `aur` | yay (Arch only) |

The installer auto-detects distro (`/etc/os-release`) and GPU (`lspci`),
skips wrong-distro / wrong-GPU entries, and routes through `pacman` /
`yay` / `apt` / a custom script per entry.

## packages.yaml schema

```yaml
- name: glow                              # required, used in DOTFILES_SKIP
  arch:    { type: pacman }               # required (or null)
  ubuntu:  { type: script, script: scripts/install-glow.sh }   # required (or null)
  binary:  glow                           # optional; defaults to name
  config_path: ~/.config/glow             # optional; tilde-expanded
  dependencies: [go]                      # optional; skip if any dep skipped
  group:   shell                          # required
  condition: gpu_amd                      # optional: gpu_amd | gpu_nvidia
```

Skip rule (per package, in order):

1. Listed in `DOTFILES_SKIP` or matched by `DOTFILES_SKIP_GROUP` —
   **unless** in `DOTFILES_FORCE`.
2. Any name in `dependencies` is in the skip set (transitive).
3. `command -v <binary>` succeeds.
4. `binary` not defined for entry **and** `config_path` exists (fallback
   for shell-function tools like nvm).

`condition: gpu_amd` / `gpu_nvidia` skips when GPU vendor doesn't match.

## Custom install scripts must be idempotent

Anything under `scripts/` MUST tolerate re-execution. Start each script
with:

```bash
command -v <binary> >/dev/null && exit 0
```

The package loop's binary check normally gates execution, but
`DOTFILES_FORCE` and re-runs can re-invoke a script — it must be safe.

## Repo layout

```
/                                       ← repo root (= chezmoi source dir)
├── README.md                           ← repo-only (in .chezmoiignore)
├── AGENTS.md                           ← repo-only
├── skills/                             ← repo-only — AI agent skills
├── packages.yaml                       ← repo-only — package manifest
├── scripts/                            ← repo-only — installer + custom installers
│   ├── install-from-yaml.sh            ← env-var-driven worker
│   ├── install-interactive.sh          ← fzf picker UI → worker --only
│   ├── lib/install-common.sh           ← shared helpers (sourced by both)
│   └── install-<name>.sh               ← per-package custom installers
├── .chezmoiignore                      ← lists repo-only paths
├── .chezmoiscripts/                    ← run scripts (no target files created)
│   └── run_onchange_after_install_packages.sh
├── dot_zshrc, dot_bashrc, dot_bash_profile       ← deploy to ~/.{zshrc,...}
├── dot_config/                         ← deploys to ~/.config/
│   └── (sway, waybar, nvim, ghostty, opencode, ...)
└── dot_local/
    └── bin/                            ← deploys to ~/.local/bin/
```

chezmoi conventions in source: `.x` → `dot_x`, executable scripts get
`executable_<name>`, encrypted files get `encrypted_<name>`.

## Common chezmoi commands

```bash
chezmoi diff                # what would change in $HOME
chezmoi status              # which managed files differ
chezmoi apply               # apply repo state to $HOME
chezmoi apply --dry-run -v  # preview
chezmoi merge <path>        # 3-way merge interactively
chezmoi update              # git pull + apply
chezmoi add <path>          # track a $HOME file into the repo
chezmoi forget <path>       # untrack
chezmoi cd                  # cd into source dir
chezmoi source-path         # print source dir path
chezmoi managed             # list everything chezmoi manages
chezmoi unmanaged ~         # list $HOME files NOT managed
chezmoi data                # dump template variables (for .tmpl files)
```

## See also

- `AGENTS.md` — conventions for AI agents and contributors.
- `skills/dotfiles-tracker/SKILL.md` — the AI skill for adding to this repo.
- chezmoi docs: https://chezmoi.io/user-guide/
