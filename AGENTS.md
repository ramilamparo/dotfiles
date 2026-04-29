# Agent / Contributor Guide

This is a [chezmoi](https://chezmoi.io)-managed dotfiles repo plus a
cross-distro package installer. AI agents and human contributors editing
this repo follow the conventions below.

## TL;DR for agents

- Repo root = chezmoi source dir. Run `chezmoi source-path` to find it on
  the user's machine.
- Files in source use chezmoi naming: `.x` → `dot_x`, executable scripts
  → `executable_<name>`, encrypted secrets → `encrypted_<name>`.
- Five paths at repo root are repo-only and never deploy to `$HOME`:
  `README.md`, `AGENTS.md`, `skills/`, `packages.yaml`, `scripts/`.
  All listed in `.chezmoiignore`.
- One script in `.chezmoiscripts/` drives package install:
  `run_onchange_after_install_packages.sh`.
- The package manifest is `packages.yaml` at repo root (repo-only).
  The worker is `scripts/install-from-yaml.sh` (also repo-only).
- The AI skill for adding to this repo is
  `skills/dotfiles-tracker/SKILL.md`.

## Repo conventions

- Source dir = chezmoi source = repo root. There is **no** `.git` in
  `$HOME` and no yadm. Do not introduce either.
- File deployment is chezmoi's job. Do not write parallel install scripts.
- Existing dotfiles deployed to `$HOME` get a `dot_` prefix in source.
  Whole subtrees too: `dot_config/`, `dot_local/`.
- Executable scripts get `executable_` prefix in source. chezmoi sets
  the `+x` bit on apply.
- Use `.chezmoiignore` for repo-only files (lives at repo root). One
  glob pattern per line, relative to source.
- Use `.chezmoiscripts/` for `run_` scripts that should execute during
  `chezmoi apply` but not create files in `$HOME` (e.g. package install
  triggers). Scripts there run from a temp dir; target files are not created.

### Renaming examples

| `$HOME` path | Source path |
|---|---|
| `~/.zshrc` | `dot_zshrc` |
| `~/.bashrc` | `dot_bashrc` |
| `~/.config/sway/config` | `dot_config/sway/config` |
| `~/.config/waybar/power-menu.sh` (executable) | `dot_config/waybar/executable_power-menu.sh` |
| `~/.local/bin/opencode-run` (executable) | `dot_local/bin/executable_opencode-run` |
| `~/.ssh/config` (mode 0600) | `private_dot_ssh/config` |
| `~/.netrc` (encrypted) | `encrypted_dot_netrc` |

## Per-host variants (templates)

Use chezmoi templates when the same logical file needs different content
across machines. Template files end with `.tmpl` and use Go template
syntax with `.chezmoi.*` variables.

### Example: ghostty config differs between Arch+sway and Kubuntu+KDE

The KDE box needs a title-bar fix that the sway box doesn't. One source
file produces the right output on each machine:

```
# dot_config/ghostty/config.tmpl
font-family = RobotoMono Nerd Font Mono
theme = Catppuccin Mocha
window-padding-x = 16

{{ if eq .chezmoi.osRelease.id "ubuntu" -}}
# KDE Plasma title-bar fix
window-decoration = client
window-theme = ghostty
{{- end }}
```

To create a template from an existing file: `chezmoi add --template
~/.config/ghostty/config`. Or rename `config` → `config.tmpl` in source
and edit by hand.

### Useful template variables

```
{{ .chezmoi.os }}                  # "linux"
{{ .chezmoi.osRelease.id }}        # "arch", "ubuntu"
{{ .chezmoi.osRelease.idLike }}    # "debian"
{{ .chezmoi.hostname }}            # actual hostname
{{ .chezmoi.username }}            # current user
{{ .chezmoi.arch }}                # "amd64", "arm64"
```

Run `chezmoi data` to dump everything available. Test a template with
`chezmoi execute-template < dot_config/ghostty/config.tmpl`.

### Conditional patterns

Distro-specific:
```
{{ if eq .chezmoi.osRelease.id "arch" -}}
# arch-specific
{{ else if eq .chezmoi.osRelease.id "ubuntu" -}}
# ubuntu-specific
{{ end }}
```

Hostname-specific (e.g. laptop vs desktop):
```
{{ if eq .chezmoi.hostname "ramil-laptop" -}}
# laptop only
{{ end }}
```

DE-specific. No built-in `.chezmoi.de` var. In order of preference:

```
{{ if lookPath "plasmashell" -}}            # KDE installed (most reliable)
window-decoration = client
{{ end }}

{{ if lookPath "sway" -}}                   # sway installed
include /etc/sway/config.d/*
{{ end }}

{{ if env "XDG_CURRENT_DESKTOP" | eq "KDE" -}}   # KDE running NOW (env var)
window-decoration = client
{{ end }}
```

`lookPath` is preferred — it works the same whether `chezmoi apply` runs
from a graphical session, an SSH login, or a tty. Common detection probes:

| Desktop / WM     | `lookPath` probe |
|------------------|------------------|
| GNOME            | `gnome-shell`    |
| KDE Plasma       | `plasmashell`    |
| XFCE             | `xfce4-session`  |
| sway             | `sway`           |
| Hyprland         | `Hyprland`       |

## .chezmoiignore patterns

Lives at repo root. One glob per line. Patterns match **target paths**
(post-rename, post-`dot_` prefix) — so write `.config/sway/**`, not
`dot_config/sway/**`. The file is auto-rendered as a Go template, so you
can conditionally ignore.

Repo-only files at the source root (no `dot_` prefix) have target == source,
which is why patterns like `/README.md` and `/skills/**` work to keep them
out of `$HOME`.

```
/README.md
/AGENTS.md
/skills/**
/packages.yaml
/scripts/**

# Always ignored regardless of host
.bash_profile
.bashrc

# Ignored on hosts where sway is not installed
{{- if not (lookPath "sway") }}
.config/sway/**
.config/waybar/**
.config/wofi/**
.local/bin/pacman-wofi
{{- end }}
```

Leading-slash patterns anchor at the repo root (so `/README.md` ignores
only the root README, not nested ones like `dot_config/nvim/README.md`).

### Gating by installed binary (preferred over OS / hostname)

`lookPath "<binary>"` returns the binary path, or empty if missing. Gating
on it mirrors the install-skip rule in `scripts/install-from-yaml.sh`
(`command -v <binary>`), so ignore-policy and install-policy stay in sync:
a machine that has the binary gets both the package and the configs; a
machine that doesn't gets neither, and `chezmoi diff` stays quiet about it.

Prefer this over `XDG_CURRENT_DESKTOP` env detection (which is only set
inside a graphical session — not in SSH, cron, or tty1 applies) or
hostname matching (fragile).

## packages.yaml conventions

- Every entry has `name`, exactly one of `arch:` / `ubuntu:` (or both),
  `group`. Optional: `binary`, `config_path`, `dependencies`, `condition`.
- `binary` defaults to `name`. Override when the executable name differs
  from the package name.
- `config_path` only for entries without a binary signal (e.g. `nvm` is
  a shell function). Otherwise leave unset — chezmoi handles the
  config-file side independently.
- `dependencies` is for hard runtime deps (e.g. `glow → go`). Skipping
  the dep skips the entry transitively.
- `group` is required. Current groups: `shell`, `terminal`, `sway`,
  `gpu`, `aur`, `apps`, `fonts`, `dev`. Add a new group only with reason
  in PR.
- `condition: gpu_amd` / `gpu_nvidia` gates entries on hardware
  detection (`lspci`).

### Example entries

A standard package available on both distros:
```yaml
- name: fzf
  arch: { type: pacman }
  ubuntu: { type: apt }
  binary: fzf
  group: shell
```

Different package name on one distro:
```yaml
- name: swaync
  arch: { type: pacman }
  ubuntu: { type: apt, package: sway-notification-center }
  binary: swaync                                 # binary name, not package name
  group: sway
```

Custom install script (no apt/pacman package):
```yaml
- name: ghostty
  arch: { type: pacman }
  ubuntu: { type: script, script: scripts/install-ghostty.sh }
  binary: ghostty
  group: terminal
```

Hardware-conditional:
```yaml
- name: amd-gpu
  arch: { type: pacman, package: lib32-vulkan-radeon }
  ubuntu: { type: apt, package: mesa-vulkan-drivers }
  group: gpu
  condition: gpu_amd
```

Hard runtime dependency:
```yaml
- name: glow
  arch: { type: pacman }
  ubuntu: { type: script, script: scripts/install-glow.sh }
  binary: glow
  dependencies: [go]
  group: shell
```

Shell-function tool with no binary on PATH:
```yaml
- name: nvm
  arch: { type: script, script: scripts/install-nvm.sh }
  ubuntu: { type: script, script: scripts/install-nvm.sh }
  config_path: ~/.nvm                            # fallback skip signal
  group: shell
```

## Custom install scripts

All scripts under `scripts/` MUST be idempotent. Start each with the
binary guard:

```bash
#!/usr/bin/env bash
set -euo pipefail

command -v ghostty >/dev/null 2>&1 && exit 0

# install logic here…
```

The package loop's binary check normally gates execution, but
`DOTFILES_FORCE` and direct invocations can re-run a script — it must
tolerate it.

## Skills

AI agent skills live at `skills/<name>/SKILL.md` at repo root.
Repo-only (in `.chezmoiignore`). Format:

```markdown
---
name: skill-name
description: >
  One-paragraph description used by AI agents to decide when to invoke.
---

# Skill body — markdown instructions for the agent.
```

The canonical skill for this repo is `skills/dotfiles-tracker/SKILL.md`.

## Workflow examples

### Track a config file (example: new ghostty config)

```bash
chezmoi add ~/.config/ghostty/config
chezmoi cd
git status                          # confirm dot_config/ghostty/config is staged
git add dot_config/ghostty/config
git commit -m "track: ghostty config"
# user pushes when they're ready — agents do not push
```

### Add a package (example: fastfetch)

1. Edit `packages.yaml` at repo root. Insert under `# --- apps ---`:
   ```yaml
   - name: fastfetch
     arch: { type: pacman }
     ubuntu: { type: apt }
     binary: fastfetch
     group: apps
   ```
2. Validate via dry-run:
   ```bash
   DOTFILES_DRY_RUN=1 "$(chezmoi source-path)/scripts/install-from-yaml.sh" \
       "$(chezmoi source-path)/packages.yaml"
   ```
   The new entry should appear in the action plan.
3. Commit:
   ```bash
   chezmoi cd
   git add packages.yaml
   git commit -m "track: add fastfetch"
   ```

### Track a custom install script (example: a tool not in apt)

1. Create the script:
   ```bash
   cat > "$(chezmoi source-path)/scripts/install-foo.sh" <<'EOF'
   #!/usr/bin/env bash
   set -euo pipefail
   command -v foo >/dev/null 2>&1 && exit 0
   curl -fsSL https://example.com/install-foo.sh | bash
   EOF
   ```
2. Add packages.yaml entry:
   ```yaml
   - name: foo
     arch: { type: script, script: scripts/install-foo.sh }
     ubuntu: { type: script, script: scripts/install-foo.sh }
     binary: foo
     group: apps
   ```
3. Validate + commit both files together.

### Update local from upstream changes

```bash
chezmoi update                      # git pull + apply
chezmoi merge ~/.zshrc              # if there's a conflict on .zshrc
```

### Untrack

```bash
chezmoi forget ~/.config/old-thing/     # stop tracking, leave $HOME copy
chezmoi cd && git commit -m "untrack: old-thing"
```

### Gate a config so it's only applied on machines with a binary

Goal: keep sway/waybar/wofi configs in source, but make them invisible
(no diff, no apply) on machines without sway installed.

1. Edit `$(chezmoi source-path)/.chezmoiignore`:
   ```gotmpl
   {{- if not (lookPath "sway") }}
   .config/sway/**
   .config/waybar/**
   .config/wofi/**
   .local/bin/pacman-wofi
   {{- end }}
   ```
2. Verify the render and that `diff` is quiet on this host:
   ```bash
   chezmoi execute-template < "$(chezmoi source-path)/.chezmoiignore"
   chezmoi ignored                          # confirms the gated entries
   chezmoi diff | grep -E "^diff --git"     # should not list gated paths
   ```
3. Commit `.chezmoiignore`. The same source still applies on a sway machine
   because `lookPath "sway"` is non-empty there.

## Hard rules

- **Never `git push`** without explicit user authorization. Local commits
  are fine; pushes are not.
- **Never** install packages or run package managers (apt, pacman, yay)
  unless the user explicitly asked.
- **Always** secret-scan before `chezmoi add`. Block on these patterns:
  - `(?i)(api[_-]?key|secret|token|password|passwd|bearer)[:= ]+["']?[A-Za-z0-9+/=_-]{16,}`
  - PEM headers (`-----BEGIN ... PRIVATE KEY-----`)
  - `.env` files (always block — suggest `.chezmoiignore` + env vars)
  - Anything under `~/.config/sunshine/credentials/`
  Use `chezmoi add --encrypt` for legitimate secrets.
- **Always** validate `packages.yaml` edits via `DOTFILES_DRY_RUN=1`
  before commit.
- When uncertain about `binary` / `group` / `dependencies`, ask the user
  rather than guess.
- When renaming for chezmoi conventions, use `git mv` so history follows.

## Out of scope

- Auto-merging local dotfiles with repo versions on `chezmoi apply`.
  Conflicts → `chezmoi merge` (interactive). Users resolve by hand.
- Pushing changes to remotes. Always user-initiated.
- Multi-repo orchestration. One source repo, one chezmoi instance.

## Related

- `README.md` — user-facing usage.
- chezmoi docs: https://chezmoi.io/user-guide/
- chezmoi templating: https://chezmoi.io/user-guide/templating/
