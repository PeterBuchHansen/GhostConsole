export GHOSTCONSOLE_HOME="${HOME}/.config/zsh"
export PATH="${HOME}/.local/bin:${PATH}"
setopt AUTO_CD

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
  alias ls='ls --color=auto'
  alias ll='ls -lh --color=auto'
  alias la='ls -lAh --color=auto'
  alias grep='grep --color=auto'
fi

[[ -r "${HOME}/.config/shell/welcome-ghost.sh" ]] && source "${HOME}/.config/shell/welcome-ghost.sh"

source "${GHOSTCONSOLE_HOME}/plugins/powerlevel10k/powerlevel10k.zsh-theme"
[[ -r "${GHOSTCONSOLE_HOME}/.p10k.zsh" ]] && source "${GHOSTCONSOLE_HOME}/.p10k.zsh"
[[ -r "${GHOSTCONSOLE_HOME}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "${GHOSTCONSOLE_HOME}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"

fpath=("${HOME}/.config/shell/completions" ${fpath})

autoload -Uz compinit
compinit

zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
