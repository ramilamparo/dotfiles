---
name: sway-keybindings
description: >
  Generate and update the Sway keybindings cheatsheet (KEYBINDINGS.md) from the
  sway config file. Use when the user says "update keybindings", "regenerate
  cheatsheet", "sync keybindings", or any variation of updating the sway
  keybindings documentation.
---

# Sway Keybindings Skill

You are a sway keybindings assistant. Help the user generate and maintain an
up-to-date KEYBINDINGS.md file from their sway config.

## Workflow

### Detect Changes (if KEYBINDINGS.md exists)

1. Check if `~/.config/sway/KEYBINDINGS.md` exists
2. If it exists, use `yadm diff ~/.config/sway/config` to find new/removed/changed keybindings
3. Report what changed to the user

### Parse Sway Config

If no KEYBINDINGS.md exists (or user wants full regeneration):

1. Read `~/.config/sway/config`
2. Extract all `bindsym` lines with their preceding comments
3. Resolve variables (`$mod` → `Mod`, `$left` → `h`, etc.)
4. Handle special cases:
   - `--locked` flag (media keys)
   - `mode "resize" { ... }` blocks
   - Variable definitions (`set $var value`)

### Categorize Keybindings

Group extracted keybindings into these categories (in order):

1. **Basics** - Terminal, kill window, launcher, reload, exit
2. **Navigation** - Focus movement (vim keys + arrow keys)
3. **Window Movement** - Move window (vim keys + arrow keys)
4. **Workspaces** - Switch workspace, move window to workspace
5. **Layout** - Split, stacking, tabbed, fullscreen, floating toggle
6. **Scratchpad** - Move to scratchpad, show scratchpad
7. **Resize Mode** - Resize mode bindings (with mode entry note)
8. **Notifications (SwayNC)** - Toggle notification center, DND
9. **Media Keys** - Volume, brightness, screenshots
10. **Help** - Show keybindings cheatsheet

### Format Output

Generate markdown matching this format:

```markdown
# Sway Keybindings Cheatsheet

> Auto-generated from `~/.config/sway/config`
> Modifier key: **Mod** (Windows/Super key)

---

## Category Name

| Keybinding | Action |
|------------|--------|
| `Mod+Return` | Open terminal (ghostty) |
| `Mod+Shift+q` | Kill focused window |

---

*Last updated: Auto-generated from sway config*
```

For **Resize Mode**, use special format:
```markdown
## Resize Mode

Enter resize mode: `Mod+r`

| Keybinding | Action |
|------------|--------|
| `h` | Shrink width |
```

### Display Keybindings

When the user wants to view the keybindings:

1. Run: `~/.local/bin/sway-cheatsheet`
2. This opens a ghostty terminal in the scratchpad with glow rendering the markdown

## Safety Rules

- NEVER modify the sway config directly unless explicitly asked
- ALWAYS preserve the existing KEYBINDINGS.md format
- When in doubt, ask the user before making changes
- Use yadm diff to show what changed in the sway config
