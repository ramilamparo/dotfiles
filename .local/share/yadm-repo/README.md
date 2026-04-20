# Dotfiles

Personal system configuration managed with [yadm](https://yadm.io/).

## Quick Start

```bash
# 1. Install yadm
# Arch:
sudo pacman -S yadm
# Ubuntu:
sudo apt install yadm

# 2. Clone this repo
yadm clone https://github.com/YOURUSER/dotfiles.git

# 3. Run the install script
~/.local/share/yadm-repo/install.sh
```

## What's Tracked

| Category | Paths |
|----------|-------|
| **Shell** | `~/.zshrc`, `~/.bashrc`, `~/.bash_profile` |
| **Sway WM** | `~/.config/sway/`, `~/.config/swaylock/`, `~/.config/swaync/`, `~/.config/waybar/`, `~/.config/wofi/` |
| **Terminal** | `~/.config/ghostty/` |
| **Editor** | `~/.config/nvim/` (NvChad) |
| **Prompt** | `~/.config/starship.toml` |
| **Game Streaming** | `~/.config/sunshine/` (credentials excluded) |
| **Scripts** | `~/.local/bin/` |
| **AI Tools** | `~/.config/opencode/`, `~/.agents/skills/` |

## Install Script

`install.sh` supports Arch Linux and Ubuntu:

```bash
./install.sh              # Full install (packages + dotfiles)
./install.sh --packages   # Install packages only
./install.sh --dotfiles   # Install dotfiles only
./install.sh --dry-run    # Preview what would be installed
```

### Package Management

Packages are defined in `packages.yaml` with distro-specific install methods:

```yaml
- name: ghostty
  arch: { type: pacman }
  ubuntu: { type: script, script: scripts/install-ghostty.sh }
```

Supported types: `pacman`, `yay`, `apt`, `script`

GPU-specific packages (AMD/NVIDIA) are auto-detected via `lspci`.

## Tracking New Changes

Use the `dotfiles-tracker` skill:

```
track package fastfetch
track config ~/.config/new-app/config.toml
track script ~/.local/bin/my-script
show pending dotfiles changes
```

Or manually:

```bash
yadm add ~/.config/new-app
yadm commit -m "Add new-app config"
yadm push
```

## Security

Sensitive files are excluded via `~/.config/yadm/.gitignore`:
- `~/.config/sunshine/credentials/`
- `~/.config/sunshine/*.log`
- `~/.claude.json`

Always review configs before tracking to avoid leaking secrets.

## Structure

```
~
├── .config/
│   ├── yadm/.gitignore          # Yadm exclusions
│   ├── sway/                    # Window manager
│   ├── waybar/                  # Status bar
│   ├── nvim/                    # Neovim (NvChad)
│   ├── ghostty/                 # Terminal
│   ├── sunshine/                # Game streaming
│   └── opencode/                # Opencode config + skills
├── .local/
│   ├── bin/                     # Custom scripts
│   └── share/yadm-repo/         # Repo meta files
│       ├── install.sh
│       ├── packages.yaml
│       └── scripts/             # Distro-specific installers
└── .agents/skills/              # Installed skills
```

## License

Public domain where applicable. Configs are personal — fork and adapt as needed.
