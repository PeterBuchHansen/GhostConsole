export GHOSTCONSOLE_HOME="${HOME}/.config/zsh"
export PATH="${HOME}/.local/bin:${PATH}"

[[ -r "${HOME}/.config/shell/welcome-ghost.sh" ]] && source "${HOME}/.config/shell/welcome-ghost.sh"

source "${GHOSTCONSOLE_HOME}/plugins/powerlevel10k/powerlevel10k.zsh-theme"
[[ -r "${GHOSTCONSOLE_HOME}/.p10k.zsh" ]] && source "${GHOSTCONSOLE_HOME}/.p10k.zsh"
[[ -r "${GHOSTCONSOLE_HOME}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "${GHOSTCONSOLE_HOME}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"

fpath=("${HOME}/.config/shell/completions" ${fpath})

autoload -Uz compinit
compinit
