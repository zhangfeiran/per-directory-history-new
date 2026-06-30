# per-directory-history-new

File-backed per-directory history for zsh and Oh My Zsh.

This plugin keeps separate history files for each directory while still writing every command to the global history file. It is designed to work well with multiple terminals and with `fzf` history search.

## Features

- Saves each command to both global history and the current directory history.
- Does not reload the active history view after pressing Enter.
- Reloads the active history view only through explicit refresh points such as startup, directory changes, mode toggles, and `Ctrl-R` search.
- Provides a local/global history toggle, compatible with the original `per-directory-history` plugin state variables.
- Overrides `fzf-history-widget` so `Ctrl-R` refreshes the active in-memory history before opening search.
- Does not hook Up/Down keys for synchronization, so history navigation stays responsive.

## Requirements

- zsh
- Oh My Zsh
- `fzf` for `Ctrl-R` history search integration

The core per-directory history behavior works without `fzf`; only the `Ctrl-R` widget requires it.

## Installation

Clone the plugin into Oh My Zsh's custom plugin directory:

```zsh
git clone https://github.com/zhangfeiran/per-directory-history-new \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/per-directory-history-new
```

Enable it in `~/.zshrc`:

```zsh
plugins=(
  # other plugins...
  per-directory-history-new
)
```

Reload zsh:

```zsh
exec zsh
```

If you were using Oh My Zsh's original `per-directory-history` plugin, remove it from `plugins=(...)` before enabling this one.

## Optional Configuration

Set these variables before `source $ZSH/oh-my-zsh.sh`:

```zsh
# Base directory for per-directory history files.
HISTORY_BASE="$HOME/.directory_history"

# Start new shells in global history mode instead of local directory mode.
HISTORY_START_WITH_GLOBAL=true

# Key binding for switching between global and local history.
PER_DIRECTORY_HISTORY_TOGGLE='^G'

# Print a zle message when switching modes.
PER_DIRECTORY_HISTORY_PRINT_MODE_CHANGE=true
```

Directory history files are stored under:

```text
$HISTORY_BASE/<absolute-current-directory>/history
```

For example, history for `/home/me/project` is stored at:

```text
~/.directory_history/home/me/project/history
```

## Usage

Use your shell normally. Commands are written to:

- global history: `$HISTFILE`
- local history: `$HISTORY_BASE${PWD:A}/history`

Press `Ctrl-G` by default to toggle the active history view:

- global mode searches `$HISTFILE`
- local mode searches the current directory's history file

Changing directories refreshes the active history view in both modes: global mode reloads `$HISTFILE`, and local mode reloads the new directory's history file.

If `fzf` is installed, `Ctrl-R` opens history search for the active history view. It first refreshes zsh's in-memory history from the active history file, so commands written by another terminal are visible to both `Ctrl-R` search and later Up/Down history navigation.

## Notes

This plugin takes over history file writing and explicit reloads, and disables zsh's automatic `share_history`, `inc_append_history`, and `inc_append_history_time` options after initialization. This avoids mixing global history entries into a local directory history view.

Blank commands are not written to history. Pressing Enter does not refresh the active history view, whether the command line is empty or non-empty.
