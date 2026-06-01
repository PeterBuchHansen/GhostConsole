export GHOSTCONSOLE_HOME="${HOME}/.config/zsh"
export PATH="${HOME}/.local/bin:${PATH}"
if [[ -z "${EDITOR+x}" ]]; then
  export EDITOR="nvim"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  for coreutils_gnubin in /opt/homebrew/opt/coreutils/libexec/gnubin /usr/local/opt/coreutils/libexec/gnubin; do
    [[ -d "${coreutils_gnubin}" ]] && PATH="${coreutils_gnubin}:${PATH}"
  done
fi

if command -v dircolors >/dev/null 2>&1; then
  if [[ -r "${HOME}/.dircolors" ]]; then
    eval "$(dircolors -b "${HOME}/.dircolors")"
  else
    eval "$(dircolors -b)"
  fi
fi

[[ -r "${HOME}/.config/shell/welcome-ghost.sh" ]] && source "${HOME}/.config/shell/welcome-ghost.sh"

source "${GHOSTCONSOLE_HOME}/plugins/powerlevel10k/powerlevel10k.zsh-theme"
[[ -r "${GHOSTCONSOLE_HOME}/.p10k.zsh" ]] && source "${GHOSTCONSOLE_HOME}/.p10k.zsh"
[[ -r "${GHOSTCONSOLE_HOME}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "${GHOSTCONSOLE_HOME}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"

fpath=("${HOME}/.config/shell/completions" ${fpath})

autoload -Uz compinit
compinit

if [[ -n "${LS_COLORS-}" ]]; then
  zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
  alias ls='ls --color=auto'
  alias ll='ls -lh --color=auto'
  alias la='ls -lAh --color=auto'
  alias grep='grep --color=auto'
fi

# Keep this at the end so later startup hooks cannot disable it.
setopt AUTO_CD

# AUTO_CD does not treat bare `..` as a directory jump command in all zsh contexts.
# Keep explicit parent-navigation aliases so `..`/`...` always work.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Make Tab expand parent-directory shorthand:
# ..<TAB> -> ../, ../..<TAB> -> ../../, ../../..<TAB> -> ../../../
_ghostconsole_parent_dir_tab() {
  local token="${LBUFFER##* }"
  if [[ "${token}" == ".." || "${token}" == */.. ]]; then
    LBUFFER+="/"
    zle redisplay
    return 0
  fi
  zle expand-or-complete
}

zle -N _ghostconsole_parent_dir_tab
bindkey -M emacs '^I' _ghostconsole_parent_dir_tab
bindkey -M viins '^I' _ghostconsole_parent_dir_tab
