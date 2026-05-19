#!/usr/bin/env bash

if [[ -n "${BASH_VERSION-}" ]]; then
  GHOSTCONSOLE_BOOTSTRAP_INVOCATION="${BASH_SOURCE[0]}"
  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    GHOSTCONSOLE_BOOTSTRAP_EXECUTED=1
    set -euo pipefail
  else
    GHOSTCONSOLE_BOOTSTRAP_EXECUTED=0
  fi
elif [[ -n "${ZSH_VERSION-}" ]]; then
  GHOSTCONSOLE_BOOTSTRAP_INVOCATION="${(%):-%x}"
  GHOSTCONSOLE_BOOTSTRAP_EXECUTED=0
else
  printf '%s\n' "GhostConsole bootstrap supports bash execution and bash/zsh sourcing only." >&2
  return 1 2>/dev/null || exit 1
fi

GHOSTCONSOLE_ROOT="$(cd -- "$(dirname -- "${GHOSTCONSOLE_BOOTSTRAP_INVOCATION}")" && pwd)"
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
  run_install_command 'brew install zsh git coreutils ncdu btop lazygit lazydocker'
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
  run_install_command 'sudo apt-get install -y zsh git ncdu btop'
  install_ubuntu_github_release_tool lazygit jesseduffield/lazygit
  install_ubuntu_github_release_tool lazydocker jesseduffield/lazydocker
}

macos_tui_tools_install() {
  if ! command -v brew >/dev/null 2>&1; then
    log_error "Homebrew not in PATH on macOS — install from https://brew.sh then rerun bootstrap."
    exit 1
  fi

  log_info "Installing TUI tools on macOS..."
  run_install_command 'brew install ncdu btop lazygit lazydocker'
}

linux_ubuntu_tui_tools_install() {
  log_info "Installing TUI tools on Ubuntu..."
  run_install_command 'sudo apt-get install -y ncdu btop'
  install_ubuntu_github_release_tool lazygit jesseduffield/lazygit
  install_ubuntu_github_release_tool lazydocker jesseduffield/lazydocker
}

macos_tui_tools_update() {
  if ! command -v brew >/dev/null 2>&1; then
    log_error "Homebrew not in PATH on macOS — install from https://brew.sh then rerun bootstrap."
    exit 1
  fi

  log_info "Updating TUI tools on macOS..."
  run_install_command 'brew update && brew upgrade ncdu btop lazygit lazydocker || brew install ncdu btop lazygit lazydocker'
}

linux_ubuntu_tui_tools_update() {
  log_info "Updating TUI tools on Ubuntu..."
  run_install_command 'sudo apt-get update && sudo apt-get install -y ncdu btop'
  install_ubuntu_github_release_tool lazygit jesseduffield/lazygit force
  install_ubuntu_github_release_tool lazydocker jesseduffield/lazydocker force
}

install_tui_tools() {
  local kernel="$(uname -s | tr '[:upper:]' '[:lower:]')"

  case "${kernel}" in
    darwin)
      macos_tui_tools_install
      ;;
    linux)
      local distro_id; [[ ! -r /etc/os-release ]] || distro_id="$(. /etc/os-release && printf '%s' "${ID:-}")"

      case "${distro_id}" in
        ubuntu)
          linux_ubuntu_tui_tools_install
          ;;
        *)
          log_error "TUI tool install supports only Ubuntu for Linux right now (detected id: '${distro_id:-unknown}')."
          exit 1
          ;;
      esac
      ;;
    *)
      log_error "unsupported kernel '${kernel}' for TUI tool install."
      exit 1
      ;;
  esac
}

update_tui_tools() {
  local kernel="$(uname -s | tr '[:upper:]' '[:lower:]')"

  case "${kernel}" in
    darwin)
      macos_tui_tools_update
      ;;
    linux)
      local distro_id; [[ ! -r /etc/os-release ]] || distro_id="$(. /etc/os-release && printf '%s' "${ID:-}")"

      case "${distro_id}" in
        ubuntu)
          linux_ubuntu_tui_tools_update
          ;;
        *)
          log_error "TUI tool update supports only Ubuntu for Linux right now (detected id: '${distro_id:-unknown}')."
          exit 1
          ;;
      esac
      ;;
    *)
      log_error "unsupported kernel '${kernel}' for TUI tool update."
      exit 1
      ;;
  esac
}

install_ubuntu_github_release_tool() {
  local binary_name="$1"
  local github_repo="$2"
  local mode="${3-}"

  if [[ "${mode}" != "force" ]] && command -v "${binary_name}" >/dev/null 2>&1; then
    log_info "${binary_name} already installed; skipping."
    return 0
  fi

  log_info "Installing ${binary_name} from GitHub releases..."
  run_install_command "set -euo pipefail
arch=\"\$(dpkg --print-architecture)\"
case \"\${arch}\" in
  amd64) arch=\"x86_64\" ;;
  arm64) arch=\"arm64\" ;;
  *) printf \"Unsupported architecture for ${binary_name}: %s\\n\" \"\${arch}\" >&2; exit 1 ;;
esac
workdir=\"\$(mktemp -d)\"
trap 'rm -rf \"\${workdir}\"' EXIT
cd \"\${workdir}\"
latest_url=\"\$(curl -fsSLI -o /dev/null -w \"%{url_effective}\" https://github.com/${github_repo}/releases/latest)\"
tag=\"\${latest_url##*/}\"
version=\"\${tag#v}\"
archive=\"${binary_name}_\${version}_Linux_\${arch}.tar.gz\"
curl -fL -o \"\${archive}\" \"https://github.com/${github_repo}/releases/download/\${tag}/\${archive}\"
tar -xzf \"\${archive}\" ${binary_name}
sudo install -m 0755 ${binary_name} /usr/local/bin/${binary_name}"
}

install_cursor_cli() {
  if command -v agent >/dev/null 2>&1; then
    log_info "Updating Cursor CLI..."
    run_install_command 'agent update'
    return 0
  fi

  log_info "Installing Cursor CLI..."
  run_install_command 'curl https://cursor.com/install -fsS | bash'
}

uninstall_cursor_cli() {
  if [[ ! -e "${HOME}/.local/bin/agent" ]]; then
    log_info "Cursor CLI not found at ${HOME}/.local/bin/agent; skipping."
    return 0
  fi

  rm -f -- "${HOME}/.local/bin/agent"
  log_success "removed Cursor CLI at ${HOME}/.local/bin/agent"
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

is_git_plugin_permission_issue() {
  local plugin_path="$1"
  local git_dir="${plugin_path}/.git"

  [[ -e "${plugin_path}" ]] || return 1

  if [[ ! -w "${plugin_path}" ]]; then
    return 0
  fi
  if [[ -d "${git_dir}" && ! -w "${git_dir}" ]]; then
    return 0
  fi
  if [[ -e "${git_dir}/FETCH_HEAD" && ! -w "${git_dir}/FETCH_HEAD" ]]; then
    return 0
  fi

  return 1
}

print_git_plugin_failure_help() {
  local operation="$1"
  local plugin_name="$2"
  local plugin_repo="$3"
  local plugin_path="$4"
  local current_user="${USER-}"
  local current_group

  log_error "Failed to ${operation} ${plugin_name} from ${plugin_repo}."
  log_warning "Common causes: filesystem permissions, broken git URL rewrites, or proxy settings."
  if is_git_plugin_permission_issue "${plugin_path}"; then
    if [[ -z "${current_user}" ]]; then
      current_user="$(id -un 2>/dev/null || printf 'your-user')"
    fi
    current_group="$(id -gn 2>/dev/null || printf '%s' "${current_user}")"
    log_warning "Detected likely filesystem permission issue at ${plugin_path} (often caused by a past sudo run)."
    log_warning "Fix ownership then rerun without sudo:"
    log_warning "  sudo chown -R ${current_user}:${current_group} \"${plugin_path}\""
  fi
  log_warning "Inspect URL rewrites: git config --global --get-regexp '^url\\..*\\.insteadof$'"
  log_warning "Inspect proxy config: git config --global --get-regexp '^(http|https)\\.proxy$'"
  log_warning "Verify repository access directly: git ls-remote ${plugin_repo}"
  log_warning "If a rewrite is wrong, remove it: git config --global --unset-all url.<bad-base>.insteadof"
  log_warning "If a proxy is required, set one: git config --global http.proxy http://<proxy-host>:<proxy-port>"
  log_warning "After fixing git config, rerun: ./bootstrap.sh --install"
}

install_or_update_git_plugin() {
  local plugin_name="$1"
  local plugin_repo="$2"
  local plugin_path="$3"

  mkdir -p "$(dirname "${plugin_path}")"

  if [[ -d "${plugin_path}/.git" ]]; then
    log_info "Updating ${plugin_name}..."
    if ! run_install_command "git -C \"${plugin_path}\" pull --ff-only"; then
      print_git_plugin_failure_help "update" "${plugin_name}" "${plugin_repo}" "${plugin_path}"
      exit 1
    fi
    return 0
  fi

  if [[ -e "${plugin_path}" ]]; then
    log_warning "${plugin_name} path exists without git metadata; backing it up and reinstalling."
    backup_existing_target "${plugin_path}" "${GHOSTCONSOLE_BACKUP_ROOT}"
  fi

  log_info "Installing ${plugin_name}..."
  if ! run_install_command "git clone --depth=1 ${plugin_repo} \"${plugin_path}\""; then
    print_git_plugin_failure_help "clone" "${plugin_name}" "${plugin_repo}" "${plugin_path}"
    exit 1
  fi
}

install_powerlevel10k() {
  install_or_update_git_plugin \
    "Powerlevel10k" \
    "https://github.com/romkatv/powerlevel10k.git" \
    "${GHOSTCONSOLE_ROOT}/.config/zsh/plugins/powerlevel10k"
}

install_zsh_autosuggestions() {
  install_or_update_git_plugin \
    "zsh-autosuggestions" \
    "https://github.com/zsh-users/zsh-autosuggestions.git" \
    "${GHOSTCONSOLE_ROOT}/.config/zsh/plugins/zsh-autosuggestions"
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

remove_managed_bash_welcome_block() {
  local bashrc_path="${HOME}/.bashrc"
  local temp_path

  [[ -f "${bashrc_path}" ]] || return 0
  temp_path="$(mktemp)"
  awk '
    $0 == "# >>> GhostConsole welcome ghost >>>" { skip = 1; next }
    $0 == "# <<< GhostConsole welcome ghost <<<" { skip = 0; next }
    !skip { print }
  ' "${bashrc_path}" > "${temp_path}"
  mv "${temp_path}" "${bashrc_path}"
}

write_bash_welcome_loader() {
  mkdir -p "$(dirname "${HOME}/.bashrc")"
  [[ -f "${HOME}/.bashrc" ]] || : > "${HOME}/.bashrc"
  remove_managed_bash_welcome_block
  {
    printf '# >>> GhostConsole welcome ghost >>>\n'
    printf 'if [[ -r "${HOME}/.config/shell/welcome-ghost.sh" ]]; then\n'
    printf '  source "${HOME}/.config/shell/welcome-ghost.sh"\n'
    printf 'fi\n'
    printf '# <<< GhostConsole welcome ghost <<<\n'
  } >> "${HOME}/.bashrc"
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

apply_shell_config() {
  prepare_link_target ".config/shell"
  ensure_symlink ".config/shell"
  write_bash_welcome_loader
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
  apply_shell_config
  apply_git_config
  apply_zsh_config
}

uninstall_config() {
  remove_managed_symlink ".config/ghostty"
  remove_managed_symlink ".config/shell"
  remove_managed_symlink ".config/git"
  remove_managed_symlink ".config/zsh"
  remove_managed_loader ".gitconfig" "$(printf '[include]\n    path = %s/.config/git/config' "${GHOSTCONSOLE_ROOT}")"
  remove_managed_loader ".zshrc" "$(printf 'source "%s/.config/zsh/.zshrc"' "${GHOSTCONSOLE_ROOT}")"
  remove_managed_bash_welcome_block
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
  log_success "installed: ghostty, zsh, git, ncdu, btop, lazygit, lazydocker, Powerlevel10k, zsh-autosuggestions"
  log_success "linked: ~/.config/ghostty ~/.config/zsh ~/.config/shell ~/.config/git ~/.zshrc ~/.gitconfig"
}

run_full_install() {
  install_packages
  install_powerlevel10k
  install_zsh_autosuggestions
  apply_repo_config
  verify_installation
  verify_links
  print_summary
}

play_welcome_ghost() {
  local welcome_script="${GHOSTCONSOLE_ROOT}/.config/shell/welcome-ghost.sh"

  if [[ ! -r "${welcome_script}" ]]; then
    log_error "welcome ghost script not found at ${welcome_script}."
    return 1
  fi

  GHOSTCONSOLE_WELCOME_GHOST_AUTO=0 source "${welcome_script}"
  if ! command -v ghostconsole_play >/dev/null 2>&1; then
    log_error "welcome ghost playback function was not loaded."
    return 1
  fi

  if ! ghostconsole_play 2>/dev/null; then
    log_error "welcome ghost playback failed."
    return 1
  fi
}

print_completion() {
  printf '%s\n' \
    '#compdef bootstrap.sh' \
    '' \
    '_bootstrap_sh() {' \
    '  local -a first_flags uninstall_flags' \
    '  first_flags=(' \
    '    "--install:install Ghostty, zsh, git, TUI tools, zsh plugins, and managed config"' \
    '    "--update-tui-tools:update ncdu, btop, lazygit, and lazydocker only"' \
    '    "--play-welcome-ghost:play the welcome ghost immediately"' \
    '    "--cursor-cli:install or update Cursor CLI only"' \
    '    "--uninstall:remove GhostConsole-managed items"' \
    '    "-h:show help"' \
    '    "--help:show help"' \
    '  )' \
    '  uninstall_flags=(' \
    '    "--packages:also uninstall Ghostty package"' \
    '    "--cursor-cli:remove Cursor CLI only"' \
    '  )' \
    '' \
    '  if (( CURRENT == 2 )); then' \
    '    _describe "bootstrap options" first_flags' \
    '    return' \
    '  fi' \
    '' \
    '  if [[ "${words[2]}" == "--uninstall" ]]; then' \
    '    _describe "uninstall options" uninstall_flags' \
    '  fi' \
    '}' \
    '' \
    '_bootstrap_sh "$@"'
}

print_completion_source() {
  printf '%s\n' \
    'if [ -n "${BASH_VERSION-}" ]; then' \
    '  _ghostconsole_bootstrap_complete() {' \
    '    local cur prev opts uninstall_opts' \
    '    cur="${COMP_WORDS[COMP_CWORD]}"' \
    '    prev="${COMP_WORDS[COMP_CWORD-1]}"' \
    '    opts="--install -h --help --update-tui-tools --play-welcome-ghost --cursor-cli --uninstall"' \
    '    uninstall_opts="--packages --cursor-cli"' \
    '    if [ "${prev}" = "--uninstall" ]; then' \
    '      COMPREPLY=( $(compgen -W "${uninstall_opts}" -- "${cur}") )' \
    '    else' \
    '      COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )' \
    '    fi' \
    '  }'
  printf '  complete -F _ghostconsole_bootstrap_complete ./bootstrap.sh bootstrap.sh %q\n' "${GHOSTCONSOLE_BOOTSTRAP_INVOCATION}"
  printf '%s\n' \
    'elif [ -n "${ZSH_VERSION-}" ]; then'
  printf '  fpath=("%s/.config/shell/completions" ${fpath})\n' "${GHOSTCONSOLE_ROOT}"
  printf '%s\n' \
    '  autoload -Uz compinit' \
    '  compinit'
  printf '  compdef _bootstrap_sh %q 2>/dev/null || true\n' "${GHOSTCONSOLE_BOOTSTRAP_INVOCATION}"
  printf '%s\n' \
    'else' \
    '  printf "%s\n" "GhostConsole completion supports bash and zsh only." >&2' \
    'fi'
}

install_bootstrap_completion() {
  local completion_path="${GHOSTCONSOLE_ROOT}/.config/shell/completions/_bootstrap.sh"

  mkdir -p "$(dirname "${completion_path}")"
  print_completion > "${completion_path}"
  log_success "installed bootstrap completion"
}

activate_bootstrap_completion() {
  install_bootstrap_completion
  eval "$(print_completion_source)"
}

bootstrap_prefill_line() {
  printf '%s --\n' "${GHOSTCONSOLE_BOOTSTRAP_INVOCATION}"
}

queue_bootstrap_prefill() {
  local prefill_line

  prefill_line="$(bootstrap_prefill_line)"

  if [[ -n "${ZSH_VERSION-}" ]] && command -v print >/dev/null 2>&1; then
    print -z -- "${prefill_line}"
    return 0
  fi

  if [[ -n "${BASH_VERSION-}" && -t 0 && -t 1 ]]; then
    __ghostconsole_bootstrap_prefill_line="${prefill_line}"
    __ghostconsole_prefill_bootstrap_line() {
      READLINE_LINE="${__ghostconsole_bootstrap_prefill_line}"
      READLINE_POINT="${#__ghostconsole_bootstrap_prefill_line}"
      unset __ghostconsole_bootstrap_prefill_line
      bind -r '"\e[0n"' 2>/dev/null || true
      unset -f __ghostconsole_prefill_bootstrap_line
    }
    bind -x '"\e[0n": __ghostconsole_prefill_bootstrap_line' 2>/dev/null || return 0
    printf '\033[5n' > /dev/tty 2>/dev/null || true
  fi
}

print_help() {
  printf '%s\n' \
    'Usage: ./bootstrap.sh [option]' \
    '' \
    'Options:' \
    '  -h, --help                Show this help message.' \
    '  --install                 Install Ghostty, zsh, git, TUI tools, zsh plugins, and managed config.' \
    '  --update-tui-tools        Update ncdu, btop, lazygit, and lazydocker only.' \
    '  --play-welcome-ghost      Play the welcome ghost immediately.' \
    '  --cursor-cli              Install Cursor CLI only.' \
    '  --uninstall               Remove GhostConsole-managed links and loaders.' \
    '  --uninstall --cursor-cli  Remove Cursor CLI only.' \
    '  --uninstall --packages    Remove managed links/loaders and uninstall Ghostty.'
}

print_source_instruction() {
  local command='source ./bootstrap.sh'
  local comment='# To get tab completion for Usage.'

  if use_color 1; then
    printf '\033[36m%s\033[0m %s\n\n' "${command}" "${comment}"
    return 0
  fi

  printf '%s %s\n\n' "${command}" "${comment}"
}

require_non_privileged_execution() {
  local current_uid

  current_uid="$(id -u 2>/dev/null || printf '%s' "${EUID-}")"
  if [[ -n "${SUDO_USER-}" || "${current_uid}" == "0" ]]; then
    log_error "do not run bootstrap.sh with sudo or as root; run it as your normal user."
    log_warning "rerun without sudo (example): ./bootstrap.sh --install"
    return 1
  fi
}

main() {
  if [[ -z "${1-}" || "${1-}" == "-h" || "${1-}" == "--help" ]]; then
    print_source_instruction
    print_help
    return 0
  fi

  if [[ "${1-}" == "--install" ]]; then
    require_non_privileged_execution || return 1
    run_full_install
    return 0
  fi

  if [[ "${1-}" == "--update-tui-tools" ]]; then
    require_non_privileged_execution || return 1
    update_tui_tools
    return 0
  fi

  if [[ "${1-}" == "--play-welcome-ghost" ]]; then
    play_welcome_ghost
    return $?
  fi

  if [[ "${1-}" == "--cursor-cli" ]]; then
    require_non_privileged_execution || return 1
    install_cursor_cli
    return 0
  fi

  if [[ "${1-}" == "--uninstall" ]]; then
    require_non_privileged_execution || return 1
    case "${2-}" in
      --cursor-cli)
        uninstall_cursor_cli
        ;;
      --packages)
        uninstall_config
        uninstall_packages
        ;;
      *)
        uninstall_config
        ;;
    esac
    return 0
  fi

  if [[ -n "${1-}" ]]; then
    log_error "unrecognized option: ${1}"
    print_help >&2
    return 1
  fi
}

if [[ "${GHOSTCONSOLE_BOOTSTRAP_EXECUTED}" == 1 ]]; then
  main "$@"
elif [[ $- == *i* ]]; then
  activate_bootstrap_completion
  queue_bootstrap_prefill
fi
