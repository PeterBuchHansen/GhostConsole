#compdef bootstrap.sh

_bootstrap_sh() {
  local -a first_flags uninstall_flags
  first_flags=(
    "--install:install Ghostty, zsh, git, TUI tools, zsh plugins, and managed config"
    "--update-tui-tools:update ncdu, btop, lazygit, and lazydocker only"
    "--play-welcome-ghost:play the welcome ghost immediately"
    "--cursor-cli:install or update Cursor CLI only"
    "--uninstall:remove GhostConsole-managed items"
    "-h:show help"
    "--help:show help"
  )
  uninstall_flags=(
    "--packages:also uninstall Ghostty package"
    "--cursor-cli:remove Cursor CLI only"
  )

  if (( CURRENT == 2 )); then
    _describe "bootstrap options" first_flags
    return
  fi

  if [[ "${words[2]}" == "--uninstall" ]]; then
    _describe "uninstall options" uninstall_flags
  fi
}

_bootstrap_sh "$@"
