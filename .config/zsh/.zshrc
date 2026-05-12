export GHOSTCONSOLE_HOME="${HOME}/.config/zsh"
export PATH="${HOME}/bin:${PATH}"

source "${GHOSTCONSOLE_HOME}/plugins/powerlevel10k/powerlevel10k.zsh-theme"
[[ -r "${GHOSTCONSOLE_HOME}/.p10k.zsh" ]] && source "${GHOSTCONSOLE_HOME}/.p10k.zsh"

autoload -Uz compinit
compinit
