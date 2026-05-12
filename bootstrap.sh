#!/usr/bin/env bash
set -euo pipefail

GHOSTCONSOLE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GHOSTCONSOLE_BACKUP_ROOT="${HOME}/.ghostconsole-backups"

install_packages() {
  local kernel="$(uname -s | tr '[:upper:]' '[:lower:]')"

  case "${kernel}" in
    darwin)
      macos_install
      ;;
    linux)
      local distro_id; [[ ! -r /etc/os-release ]] || distro_id="$(. /etc/os-release && printf '%s' "${ID:-}")"

      case "${distro_id}" in
        ubuntu)
          linux_ubuntu_install
          ;;
        *)
          printf '[GhostConsole-Installer] error: Linux bootstrap supports only Ubuntu for now (detected id: '\''%s'\''); use Ubuntu or install/link configs yourself.\n' "${distro_id:-unknown}" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      printf '[GhostConsole-Installer] error: unsupported kernel '\''%s'\'' (need darwin for macOS or linux with Ubuntu per /etc/os-release).\n' "${kernel}" >&2
      exit 1
      ;;
  esac
}


macos_install() {
  if ! command -v brew >/dev/null 2>&1; then
    printf '[GhostConsole-Installer] error: Homebrew not in PATH on macOS — install from https://brew.sh then rerun bootstrap.\n' >&2
    exit 1
  fi

  printf '[GhostConsole-Installer] %s\n' "Installing packages on macOS (Ghostty first)..."
  run_install_command 'brew install --cask ghostty'
  run_install_command 'brew install zsh git'
}

linux_ubuntu_install() {
  printf '[GhostConsole-Installer] %s\n' "Installing packages on Ubuntu (Ghostty first)..."
  run_install_command '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"'
  run_install_command 'sudo apt-get install -y zsh git'
}

run_install_command() {
  local command="${1-}"

  env -u BASH_ENV -u ENV bash --noprofile --norc -c '
    while IFS= read -r function_name; do
      unset -f "${function_name}"
    done < <(compgen -A function)
    builtin eval -- "$1"
  ' _ "${command}"
}

backup_existing_target() {
  local target_path="$1"
  local backup_root="$2"
  local basename_no_dot
  local stamp
  local backup_path
  local suffix=1

  [[ -e "${target_path}" || -L "${target_path}" ]] || return 0

  mkdir -p "${backup_root}"
  basename_no_dot="$(basename "${target_path}" | sed 's/^\.//')"
  stamp="${GHOSTCONSOLE_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  backup_path="${backup_root}/${basename_no_dot}-${stamp}"

  while [[ -e "${backup_path}" || -L "${backup_path}" ]]; do
    backup_path="${backup_root}/${basename_no_dot}-${stamp}-${suffix}"
    suffix=$((suffix + 1))
  done

  mv "${target_path}" "${backup_path}"
  printf '[GhostConsole-Installer] %s\n' "backed up ${target_path} to ${backup_path}"
}

prepare_link_target() {
  local config_path="$1"

  if [[ -L "${HOME}/${config_path}" ]] && [[ "$(readlink "${HOME}/${config_path}")" == "${GHOSTCONSOLE_ROOT}/${config_path}" ]]; then
    return 0
  fi

  if [[ -e "${HOME}/${config_path}" || -L "${HOME}/${config_path}" ]]; then
    backup_existing_target "${HOME}/${config_path}" "${GHOSTCONSOLE_BACKUP_ROOT}"
  fi
}

ensure_symlink() {
  local config_path="$1"

  if [[ -e "${HOME}/${config_path}" && ! -L "${HOME}/${config_path}" ]]; then
    printf '[GhostConsole-Installer] error: refusing symlink at %s: path exists but is not a symlink (move or delete, then rerun).\n' "${HOME}/${config_path}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${HOME}/${config_path}")"
  ln -sfn "${GHOSTCONSOLE_ROOT}/${config_path}" "${HOME}/${config_path}"
}

prepare_loader_target() {
  local loader_path="$1"
  local expected_contents="$2"

  if [[ -L "${HOME}/${loader_path}" ]] || { [[ -e "${HOME}/${loader_path}" ]] && [[ "$(< "${HOME}/${loader_path}")" != "${expected_contents}" ]]; }; then
    backup_existing_target "${HOME}/${loader_path}" "${GHOSTCONSOLE_BACKUP_ROOT}"
  fi
}

write_zsh_loader() {
  if [[ -L "${HOME}/.zshrc" && -d "${HOME}/.zshrc" ]]; then
    printf '[GhostConsole-Installer] error: refusing zsh loader at %s: symlink points at a directory (fix or remove, then rerun).\n' "${HOME}/.zshrc" >&2
    exit 1
  fi

  if [[ -e "${HOME}/.zshrc" && ! -L "${HOME}/.zshrc" ]]; then
    printf '[GhostConsole-Installer] error: refusing zsh loader at %s: ordinary file blocks managed loader (backup or remove, then rerun).\n' "${HOME}/.zshrc" >&2
    exit 1
  fi

  if [[ -e "${HOME}/.zshrc" || -L "${HOME}/.zshrc" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${HOME}/.zshrc")"
  printf 'source "%s/.config/zsh/.zshrc"\n' "${GHOSTCONSOLE_ROOT}" > "${HOME}/.zshrc"
}

write_git_loader() {
  if [[ -L "${HOME}/.gitconfig" && -d "${HOME}/.gitconfig" ]]; then
    printf '[GhostConsole-Installer] error: refusing git loader at %s: symlink resolves to a directory (fix path, then rerun).\n' "${HOME}/.gitconfig" >&2
    exit 1
  fi

  if [[ -e "${HOME}/.gitconfig" && ! -L "${HOME}/.gitconfig" ]]; then
    printf '[GhostConsole-Installer] error: refusing git loader at %s: ordinary file blocks include snippet (rename/remove, then rerun).\n' "${HOME}/.gitconfig" >&2
    exit 1
  fi

  if [[ -e "${HOME}/.gitconfig" || -L "${HOME}/.gitconfig" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${HOME}/.gitconfig")"
  printf '[include]\n    path = %s/.config/git/config\n' "${GHOSTCONSOLE_ROOT}" > "${HOME}/.gitconfig"
}

apply_ghostty_config() {
  prepare_link_target ".config/ghostty"
  ensure_symlink ".config/ghostty"
}

apply_git_config() {
  prepare_link_target ".config/git"
  ensure_symlink ".config/git"
  prepare_loader_target ".gitconfig" "$(printf '[include]\n    path = %s/.config/git/config' "${GHOSTCONSOLE_ROOT}")"
  write_git_loader
}

apply_zsh_config() {
  prepare_link_target ".config/zsh"
  ensure_symlink ".config/zsh"
  prepare_loader_target ".zshrc" "$(printf 'source "%s/.config/zsh/.zshrc"' "${GHOSTCONSOLE_ROOT}")"
  write_zsh_loader
}

apply_repo_config() {
  mkdir -p "${HOME}/.config" "${GHOSTCONSOLE_BACKUP_ROOT}"

  apply_ghostty_config
  apply_git_config
  apply_zsh_config
}

verify_installation() {
  if ! command -v ghostty >/dev/null 2>&1; then
    printf '[GhostConsole-Installer] error: ghostty not found after install (not on PATH — check install output or try a new shell).\n' >&2
    exit 1
  fi
  if ! command -v zsh >/dev/null 2>&1; then
    printf '[GhostConsole-Installer] error: zsh not found after install (not on PATH — check install output or try a new shell).\n' >&2
    exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    printf '[GhostConsole-Installer] error: git not found after install (not on PATH — check install output or try a new shell).\n' >&2
    exit 1
  fi
}

verify_links() {
  local zsh_loader
  local git_loader

  zsh_loader="$(printf 'source "%s/.config/zsh/.zshrc"' "${GHOSTCONSOLE_ROOT}")"
  git_loader="$(printf '[include]\n    path = %s/.config/git/config' "${GHOSTCONSOLE_ROOT}")"

  if [[ ! -L "${HOME}/.config/ghostty" ]] || [[ "$(readlink "${HOME}/.config/ghostty")" != "${GHOSTCONSOLE_ROOT}/.config/ghostty" ]]; then
    printf '[GhostConsole-Installer] error: ghostty config link incorrect (want symlink %s -> %s).\n' "${HOME}/.config/ghostty" "${GHOSTCONSOLE_ROOT}/.config/ghostty" >&2
    exit 1
  fi
  if [[ ! -L "${HOME}/.config/zsh" ]] || [[ "$(readlink "${HOME}/.config/zsh")" != "${GHOSTCONSOLE_ROOT}/.config/zsh" ]]; then
    printf '[GhostConsole-Installer] error: zsh config link incorrect (want symlink %s -> %s).\n' "${HOME}/.config/zsh" "${GHOSTCONSOLE_ROOT}/.config/zsh" >&2
    exit 1
  fi
  if [[ ! -L "${HOME}/.config/git" ]] || [[ "$(readlink "${HOME}/.config/git")" != "${GHOSTCONSOLE_ROOT}/.config/git" ]]; then
    printf '[GhostConsole-Installer] error: git config link incorrect (want symlink %s -> %s).\n' "${HOME}/.config/git" "${GHOSTCONSOLE_ROOT}/.config/git" >&2
    exit 1
  fi
  if [[ ! -f "${HOME}/.zshrc" ]] || [[ "$(< "${HOME}/.zshrc")" != "${zsh_loader}" ]]; then
    printf '[GhostConsole-Installer] error: ~/.zshrc loader is incorrect — must exactly source \"%s/.config/zsh/.zshrc\".\n' "${GHOSTCONSOLE_ROOT}" >&2
    exit 1
  fi
  if [[ ! -f "${HOME}/.gitconfig" ]] || [[ "$(< "${HOME}/.gitconfig")" != "${git_loader}" ]]; then
    printf '[GhostConsole-Installer] error: ~/.gitconfig loader is incorrect — must include path %s/.config/git/config like bootstrap writes.\n' "${GHOSTCONSOLE_ROOT}" >&2
    exit 1
  fi
}

print_summary() {
  printf '[GhostConsole-Installer] bootstrap complete\n'
  printf '[GhostConsole-Installer] installed: ghostty, zsh, git\n'
  printf '[GhostConsole-Installer] linked: ~/.config/ghostty ~/.config/zsh ~/.config/git ~/.zshrc ~/.gitconfig\n'
}

main() {
  install_packages
  apply_repo_config
  verify_installation
  verify_links
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
