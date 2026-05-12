#!/usr/bin/env bash
set -euo pipefail

GHOSTCONSOLE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GHOSTCONSOLE_BACKUP_ROOT="${HOME}/.ghostconsole-backups"

use_color() {
  local fd="${1:-1}"

  [[ "${GHOSTCONSOLE_COLOR-}" == always ]] && return 0
  [[ "${GHOSTCONSOLE_COLOR-}" == never ]] && return 1
  [[ -z "${NO_COLOR-}" ]] || return 1
  [[ "${TERM-}" != dumb ]] || return 1
  [[ -t "${fd}" ]]
}

color_prefix() {
  local color_name="$1"
  local fd="${2:-1}"
  local color_code

  if ! use_color "${fd}"; then
    printf '[GhostConsole-Installer]'
    return 0
  fi

  case "${color_name}" in
    error) color_code=31 ;;
    success) color_code=32 ;;
    warning) color_code=33 ;;
    *) color_code=36 ;;
  esac

  printf '\033[%sm[GhostConsole-Installer]\033[0m' "${color_code}"
}

log_info() {
  color_prefix info 1
  printf ' %s\n' "$1"
}

log_success() {
  color_prefix success 1
  printf ' %s\n' "$1"
}

log_warning() {
  color_prefix warning 1
  printf ' %s\n' "$1"
}

log_error() {
  color_prefix error 2 >&2
  printf ' error: %s\n' "$1" >&2
}

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
          log_error "Linux bootstrap supports only Ubuntu for now (detected id: '${distro_id:-unknown}'); use Ubuntu or install/link configs yourself."
          exit 1
          ;;
      esac
      ;;
    *)
      log_error "unsupported kernel '${kernel}' (need darwin for macOS or linux with Ubuntu per /etc/os-release)."
      exit 1
      ;;
  esac
}


macos_install() {
  if ! command -v brew >/dev/null 2>&1; then
    log_error "Homebrew not in PATH on macOS — install from https://brew.sh then rerun bootstrap."
    exit 1
  fi

  log_info "Installing packages on macOS (Ghostty first)..."
  run_install_command 'brew install --cask ghostty'
  run_install_command 'brew install zsh git'
}

linux_ubuntu_install() {
  log_info "Installing packages on Ubuntu (Ghostty first)..."
  if command -v ghostty >/dev/null 2>&1; then
    log_info "Ghostty already installed; skipping Ghostty installer."
  else
    if ! run_install_command '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"'; then
      log_warning "Ghostty installer failed; trying direct GitHub release download."
      if ! run_install_command 'set -euo pipefail
source /etc/os-release
arch="$(dpkg --print-architecture)"
version_id="${VERSION_ID}"
case "${version_id}" in
  24.04|25.10|26.04) ;;
  *) printf "Unsupported Ubuntu version: %s\n" "${version_id}" >&2; exit 1 ;;
esac
latest_url="$(curl -fsSLI -o /dev/null -w "%{url_effective}" https://github.com/mkasberg/ghostty-ubuntu/releases/latest)"
tag="${latest_url##*/}"
if [[ "${tag}" == *-ppa* ]]; then
  deb_version="${tag%-ppa*}.ppa${tag##*-ppa}"
else
  deb_version="${tag}"
fi
deb_file="ghostty_${deb_version}_${arch}_${version_id}.deb"
curl -fL -o "${deb_file}" "https://github.com/mkasberg/ghostty-ubuntu/releases/download/${tag}/${deb_file}"
sudo apt-get install -y "./${deb_file}"
rm -f "${deb_file}"'; then
        log_error "Ghostty installer failed; rerun ./bootstrap.sh after checking network access to GitHub or install Ghostty manually."
        exit 1
      fi
    fi
  fi
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

install_powerlevel10k() {
  local plugin_path="${GHOSTCONSOLE_ROOT}/.config/zsh/plugins/powerlevel10k"

  mkdir -p "$(dirname "${plugin_path}")"

  if [[ -d "${plugin_path}/.git" ]]; then
    log_info "Updating Powerlevel10k..."
    run_install_command "git -C ${plugin_path} pull --ff-only"
    return 0
  fi

  if [[ -e "${plugin_path}" ]]; then
    log_error "refusing Powerlevel10k install at ${plugin_path}: path exists but is not a git checkout."
    exit 1
  fi

  log_info "Installing Powerlevel10k..."
  run_install_command "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${plugin_path}"
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
  log_warning "backed up ${target_path} to ${backup_path}"
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
    log_error "refusing symlink at ${HOME}/${config_path}: path exists but is not a symlink (move or delete, then rerun)."
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

remove_managed_symlink() {
  local config_path="$1"

  if [[ -L "${HOME}/${config_path}" ]] && [[ "$(readlink "${HOME}/${config_path}")" == "${GHOSTCONSOLE_ROOT}/${config_path}" ]]; then
    rm "${HOME}/${config_path}"
    log_warning "removed ${HOME}/${config_path}"
  fi
}

remove_managed_loader() {
  local loader_path="$1"
  local expected_contents="$2"

  if [[ -f "${HOME}/${loader_path}" ]] && [[ "$(< "${HOME}/${loader_path}")" == "${expected_contents}" ]]; then
    rm "${HOME}/${loader_path}"
    log_warning "removed ${HOME}/${loader_path}"
  fi
}

write_zsh_loader() {
  if [[ -L "${HOME}/.zshrc" && -d "${HOME}/.zshrc" ]]; then
    log_error "refusing zsh loader at ${HOME}/.zshrc: symlink points at a directory (fix or remove, then rerun)."
    exit 1
  fi

  if [[ -d "${HOME}/.zshrc" && ! -L "${HOME}/.zshrc" ]]; then
    log_error "refusing zsh loader at ${HOME}/.zshrc: ordinary file blocks managed loader (backup or remove, then rerun)."
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
    log_error "refusing git loader at ${HOME}/.gitconfig: symlink resolves to a directory (fix path, then rerun)."
    exit 1
  fi

  if [[ -d "${HOME}/.gitconfig" && ! -L "${HOME}/.gitconfig" ]]; then
    log_error "refusing git loader at ${HOME}/.gitconfig: ordinary file blocks include snippet (rename/remove, then rerun)."
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

uninstall_config() {
  remove_managed_symlink ".config/ghostty"
  remove_managed_symlink ".config/git"
  remove_managed_symlink ".config/zsh"
  remove_managed_loader ".gitconfig" "$(printf '[include]\n    path = %s/.config/git/config' "${GHOSTCONSOLE_ROOT}")"
  remove_managed_loader ".zshrc" "$(printf 'source "%s/.config/zsh/.zshrc"' "${GHOSTCONSOLE_ROOT}")"
  log_success "uninstalled GhostConsole links and loaders; backups left in ${GHOSTCONSOLE_BACKUP_ROOT}"
}

uninstall_packages() {
  log_warning "Uninstalling Ghostty package only; zsh and git are left installed."
  run_install_command 'sudo apt-get remove -y ghostty'
}

verify_installation() {
  if ! command -v ghostty >/dev/null 2>&1; then
    log_error "ghostty not found after install (not on PATH — check install output or try a new shell)."
    exit 1
  fi
  if ! command -v zsh >/dev/null 2>&1; then
    log_error "zsh not found after install (not on PATH — check install output or try a new shell)."
    exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    log_error "git not found after install (not on PATH — check install output or try a new shell)."
    exit 1
  fi
}

verify_links() {
  local zsh_loader
  local git_loader

  zsh_loader="$(printf 'source "%s/.config/zsh/.zshrc"' "${GHOSTCONSOLE_ROOT}")"
  git_loader="$(printf '[include]\n    path = %s/.config/git/config' "${GHOSTCONSOLE_ROOT}")"

  if [[ ! -L "${HOME}/.config/ghostty" ]] || [[ "$(readlink "${HOME}/.config/ghostty")" != "${GHOSTCONSOLE_ROOT}/.config/ghostty" ]]; then
    log_error "ghostty config link incorrect (want symlink ${HOME}/.config/ghostty -> ${GHOSTCONSOLE_ROOT}/.config/ghostty)."
    exit 1
  fi
  if [[ ! -L "${HOME}/.config/zsh" ]] || [[ "$(readlink "${HOME}/.config/zsh")" != "${GHOSTCONSOLE_ROOT}/.config/zsh" ]]; then
    log_error "zsh config link incorrect (want symlink ${HOME}/.config/zsh -> ${GHOSTCONSOLE_ROOT}/.config/zsh)."
    exit 1
  fi
  if [[ ! -L "${HOME}/.config/git" ]] || [[ "$(readlink "${HOME}/.config/git")" != "${GHOSTCONSOLE_ROOT}/.config/git" ]]; then
    log_error "git config link incorrect (want symlink ${HOME}/.config/git -> ${GHOSTCONSOLE_ROOT}/.config/git)."
    exit 1
  fi
  if [[ ! -f "${HOME}/.zshrc" ]] || [[ "$(< "${HOME}/.zshrc")" != "${zsh_loader}" ]]; then
    log_error "~/.zshrc loader is incorrect — must exactly source \"${GHOSTCONSOLE_ROOT}/.config/zsh/.zshrc\"."
    exit 1
  fi
  if [[ ! -f "${HOME}/.gitconfig" ]] || [[ "$(< "${HOME}/.gitconfig")" != "${git_loader}" ]]; then
    log_error "~/.gitconfig loader is incorrect — must include path ${GHOSTCONSOLE_ROOT}/.config/git/config like bootstrap writes."
    exit 1
  fi
}

print_summary() {
  log_success "bootstrap complete"
  log_success "installed: ghostty, zsh, git"
  log_success "linked: ~/.config/ghostty ~/.config/zsh ~/.config/git ~/.zshrc ~/.gitconfig"
}

main() {
  if [[ "${1-}" == "--uninstall" ]]; then
    uninstall_config
    if [[ "${2-}" == "--packages" ]]; then
      uninstall_packages
    fi
    return 0
  fi

  install_packages
  install_powerlevel10k
  apply_repo_config
  verify_installation
  verify_links
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
