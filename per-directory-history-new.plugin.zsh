#!/usr/bin/env zsh
#
# File-backed per-directory history.
#
# This keeps the public surface of oh-my-zsh's per-directory-history plugin
# while avoiding its fragile active-history juggling:
#   - every command is appended to both global and current-directory history
#   - the visible history view is reloaded at prompt boundaries when its file
#     changes, so other terminals sync after Enter, including empty Enter
#   - fzf-history-widget syncs the active history file before reading zsh's
#     in-memory active history list

[[ -z ${HISTORY_BASE:-} ]] && HISTORY_BASE="$HOME/.directory_history"
[[ -z ${HISTORY_START_WITH_GLOBAL:-} ]] && HISTORY_START_WITH_GLOBAL=false
[[ -z ${PER_DIRECTORY_HISTORY_TOGGLE:-} ]] && PER_DIRECTORY_HISTORY_TOGGLE='^G'
[[ -z ${PER_DIRECTORY_HISTORY_PRINT_MODE_CHANGE:-} ]] && PER_DIRECTORY_HISTORY_PRINT_MODE_CHANGE=true
[[ -z ${HISTFILE:-} ]] && HISTFILE="$HOME/.zsh_history"

typeset -g _per_directory_history_global_file="${HISTFILE}"
typeset -g _per_directory_history_directory
typeset -g _per_directory_history_is_global=false
typeset -g _per_directory_history_initialized=false
typeset -g _per_directory_history_active_file=''
typeset -g _per_directory_history_active_signature=''
typeset -g _per_directory_history_fzf_widget_installed=false

zmodload -F zsh/datetime p:EPOCHSECONDS 2>/dev/null || true

function _per-directory-history-update-directory() {
  _per_directory_history_directory="$HISTORY_BASE${PWD:A}/history"
  command mkdir -p -- "${_per_directory_history_directory:h}" 2>/dev/null
}

function _per-directory-history-ensure-file() {
  local file="$1"
  [[ -n "$file" ]] || return 1
  command mkdir -p -- "${file:h}" 2>/dev/null || return 1
  [[ -e "$file" ]] || : >| "$file"
}

function _per-directory-history-file-signature() {
  local file="$1"
  local -A stat

  if zmodload -F zsh/stat b:zstat 2>/dev/null && [[ -e "$file" ]] && zstat -H stat -- "$file" 2>/dev/null; then
    print -r -- "${stat[device]}:${stat[inode]}:${stat[size]}:${stat[mtime]}:${stat[ctime]}"
  else
    print -r -- "missing"
  fi
}

function _per-directory-history-clear-list() {
  local original_histsize="$HISTSIZE"
  HISTSIZE=0
  HISTSIZE="$original_histsize"
}

function _per-directory-history-active-file() {
  if [[ "$_per_directory_history_is_global" == true ]]; then
    print -r -- "$_per_directory_history_global_file"
  else
    print -r -- "$_per_directory_history_directory"
  fi
}

function _per-directory-history-load-active-history() {
  local force="${1:-false}"
  local file signature

  _per-directory-history-update-directory
  file="$(_per-directory-history-active-file)"
  _per-directory-history-ensure-file "$file" || return
  signature="$(_per-directory-history-file-signature "$file")"

  if [[ "$force" == true || "$file" != "$_per_directory_history_active_file" || "$signature" != "$_per_directory_history_active_signature" ]]; then
    _per-directory-history-clear-list
    fc -R "$file" 2>/dev/null
    _per_directory_history_active_file="$file"
    _per_directory_history_active_signature="$signature"
  fi
}

function _per-directory-history-initialize() {
  [[ "$_per_directory_history_initialized" == true ]] && return

  _per_directory_history_global_file="$HISTFILE"
  _per-directory-history-update-directory
  _per-directory-history-ensure-file "$_per_directory_history_global_file"
  _per-directory-history-ensure-file "$_per_directory_history_directory"

  # This plugin does explicit file sync. Letting zsh auto-import/write from
  # HISTFILE leaks global entries into a local history view.
  unsetopt share_history inc_append_history inc_append_history_time
  setopt append_history extended_history

  if [[ "$HISTORY_START_WITH_GLOBAL" == true ]]; then
    _per_directory_history_is_global=true
  else
    _per_directory_history_is_global=false
  fi

  _per_directory_history_initialized=true
  _per-directory-history-load-active-history true
}

function _per-directory-history-append-record() {
  local file="$1"
  local command="$2"
  local timestamp="${3:-${EPOCHSECONDS:-$(command date +%s)}}"
  local lock_file lock_fd

  [[ -n "$file" && -n "$command" ]] || return 1
  _per-directory-history-ensure-file "$file" || return 1

  lock_file="${file}.lock"
  : >| "$lock_file" 2>/dev/null || true

  if zmodload zsh/system 2>/dev/null && zsystem flock -t 2 -f lock_fd "$lock_file" 2>/dev/null; then
    {
      print -rn -- ": ${timestamp}:0;${command}"
      print -r -- ''
    } >>| "$file"
    zsystem flock -u "$lock_fd" 2>/dev/null
  else
    {
      print -rn -- ": ${timestamp}:0;${command}"
      print -r -- ''
    } >>| "$file"
  fi
}

function _per-directory-history-ignored-command() {
  local command="$1"
  local last

  [[ "$command" == *[![:space:]]* ]] || return 0
  [[ -o hist_ignore_space && "$command" == ' '* ]] && return 0

  if [[ -n "${HISTORY_IGNORE:-}" ]]; then
    setopt localoptions extendedglob
    [[ "$command" == ${~HISTORY_IGNORE} ]] && return 0
  fi

  if [[ -o hist_ignore_dups ]]; then
    setopt localoptions extendedglob
    last="$(fc -ln -1 2>/dev/null)"
    last="${last##[[:space:]]##}"
    [[ "$last" == "$command" ]] && return 0
  fi

  return 1
}

function _per-directory-history-addhistory() {
  local command="${1%$'\n'}"
  local timestamp="${EPOCHSECONDS:-$(command date +%s)}"
  local wrote=0

  _per-directory-history-initialize
  _per-directory-history-update-directory

  if _per-directory-history-ignored-command "$command"; then
    return 1
  fi

  _per-directory-history-append-record "$_per_directory_history_global_file" "$command" "$timestamp" && wrote=1
  if [[ "$_per_directory_history_directory" != "$_per_directory_history_global_file" ]]; then
    _per-directory-history-append-record "$_per_directory_history_directory" "$command" "$timestamp" || true
  fi

  (( wrote )) && return 2
  return 0
}

function _per-directory-history-change-directory() {
  _per-directory-history-initialize
  _per-directory-history-update-directory
  _per-directory-history-ensure-file "$_per_directory_history_directory"

  if [[ "$_per_directory_history_is_global" == false ]]; then
    _per-directory-history-load-active-history true
  fi
}

function _per-directory-history-fzf-entries() {
  _per-directory-history-initialize
  _per-directory-history-load-active-history false

  if (( $+functions[__fzf_exec_awk] )); then
    fc -rl 1 | __fzf_exec_awk '{ cmd=$0; sub(/^[ \t]*[0-9]+\**[ \t]+/, "", cmd); if (!seen[cmd]++) print $0 }'
  else
    fc -rl 1 | command awk '{ cmd=$0; sub(/^[ \t]*[0-9]+\**[ \t]+/, "", cmd); if (!seen[cmd]++) print $0 }'
  fi
}

function _per-directory-history-fzf-cmd() {
  if (( $+functions[__fzfcmd] )); then
    __fzfcmd
  else
    print -r -- fzf
  fi
}

function _per-directory-history-fzf-defaults() {
  local opts="-n2..,.. --scheme=history --bind=ctrl-r:toggle-sort,alt-r:toggle-raw --highlight-line --multi ${FZF_CTRL_R_OPTS-} --query=${(qqq)LBUFFER}"

  if (( $+functions[__fzf_defaults] )); then
    __fzf_defaults "" "$opts"
  else
    print -r -- "$opts"
  fi
}

function _per-directory-history-fzf-history-widget() {
  local selected ret line trimmed number command
  local -a commands

  setopt localoptions noglobsubst noposixbuiltins pipefail no_aliases no_glob no_sh_glob no_ksharrays extendedglob 2>/dev/null

  selected="$(_per-directory-history-fzf-entries |
    FZF_DEFAULT_OPTS="$(_per-directory-history-fzf-defaults)" \
    FZF_DEFAULT_OPTS_FILE='' $(_per-directory-history-fzf-cmd))"
  ret=$?

  if [[ -n "$selected" ]]; then
    for line in ${(f)selected}; do
      trimmed="${line##[[:blank:]]#}"
      number="${trimmed%%[[:blank:]]*}"

      if [[ "$number" == <-> ]]; then
        command=''

        if zmodload -F zsh/parameter p:history 2>/dev/null && (( ${+history[$number]} )); then
          command="${history[$number]}"
        else
          zle .push-line
          zle vi-fetch-history -n "$number"
          command="$BUFFER"
          BUFFER=""
          zle .get-line
        fi

        if [[ -z "$command" ]]; then
          command="${trimmed#$number}"
          command="${command##[[:blank:]]#}"
          [[ "$command" == \** ]] && command="${command#\*}"
          command="${command##[[:blank:]]#}"
        fi

        [[ -n "$command" ]] && commands+=("$command")
      fi
    done

    if (( ${#commands[@]} )); then
      BUFFER="${(pj:\n:)commands}"
      CURSOR=${#BUFFER}
    else
      LBUFFER="$selected"
    fi
  fi

  zle reset-prompt
  return "$ret"
}

function _per-directory-history-install-fzf-history-widget() {
  [[ "$_per_directory_history_fzf_widget_installed" == true ]] && return
  (( $+commands[fzf] || $+functions[__fzfcmd] )) || return

  zle -N fzf-history-widget _per-directory-history-fzf-history-widget 2>/dev/null || return
  bindkey -M emacs '^R' fzf-history-widget 2>/dev/null
  bindkey -M viins '^R' fzf-history-widget 2>/dev/null
  bindkey -M vicmd '^R' fzf-history-widget 2>/dev/null
  _per_directory_history_fzf_widget_installed=true
}

function _per-directory-history-precmd() {
  _per-directory-history-initialize
  _per-directory-history-load-active-history false
  _per-directory-history-install-fzf-history-widget
}

function _per-directory-history-set-directory-history() {
  _per-directory-history-initialize
  _per_directory_history_is_global=false
  _per-directory-history-load-active-history true
}

function _per-directory-history-set-global-history() {
  _per-directory-history-initialize
  _per_directory_history_is_global=true
  _per-directory-history-load-active-history true
}

function per-directory-history-toggle-history() {
  if [[ "$_per_directory_history_is_global" == true ]]; then
    _per-directory-history-set-directory-history
    [[ "$PER_DIRECTORY_HISTORY_PRINT_MODE_CHANGE" == true ]] && zle -M "using local history"
  else
    _per-directory-history-set-global-history
    [[ "$PER_DIRECTORY_HISTORY_PRINT_MODE_CHANGE" == true ]] && zle -M "using global history"
  fi
}

autoload -U add-zsh-hook
add-zsh-hook chpwd _per-directory-history-change-directory
add-zsh-hook zshaddhistory _per-directory-history-addhistory
add-zsh-hook precmd _per-directory-history-precmd

zle -N per-directory-history-toggle-history
[[ -n "$PER_DIRECTORY_HISTORY_TOGGLE" ]] && bindkey "$PER_DIRECTORY_HISTORY_TOGGLE" per-directory-history-toggle-history
[[ -n "$PER_DIRECTORY_HISTORY_TOGGLE" ]] && bindkey -M vicmd "$PER_DIRECTORY_HISTORY_TOGGLE" per-directory-history-toggle-history
