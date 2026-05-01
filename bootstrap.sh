#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[ghostconsole] %s\n' "$*"
}

die() {
  printf '[ghostconsole] error: %s\n' "$*" >&2
  exit 1
}

detect_platform() {
  local kernel="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"

  case "${kernel}" in
    darwin)
      printf 'macos\n'
      ;;
    linux)
      printf 'linux\n'
      ;;
    *)
      die "unsupported platform: ${kernel}"
      ;;
  esac
}

package_manager_for() {
  local platform="${1-}"

  case "${platform}" in
    macos)
      printf 'brew\n'
      ;;
    linux)
      printf 'apt\n'
      ;;
    *)
      die "unsupported package manager target: ${platform}"
      ;;
  esac
}

required_packages() {
  printf '%s\n' ghostty zsh git
}

ghostty_available_in_apt() {
  apt-cache show ghostty >/dev/null 2>&1
}

linux_distro_id() {
  local distro_id=''

  if [[ -r /etc/os-release ]]; then
    distro_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  fi

  printf '%s\n' "${distro_id}"
}

linux_version_codename() {
  local version_codename=''

  if [[ -r /etc/os-release ]]; then
    version_codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
  fi

  printf '%s\n' "${version_codename}"
}

validate_linux_install_inputs() {
  local distro_id="${1-}"
  local version_codename="${2-}"

  [[ -z "${distro_id}" || "${distro_id}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "unsafe distro id: ${distro_id}"
  [[ -z "${version_codename}" || "${version_codename}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "unsafe version codename: ${version_codename}"
}

build_install_commands() {
  local platform="${1-}"
  local distro_id="${2-}"
  local ghostty_state="${3-}"
  local version_codename="${4-}"

  case "${platform}" in
    macos)
      printf '%s\n' \
        'brew install --cask ghostty' \
        'brew install zsh git'
      ;;
    linux)
      validate_linux_install_inputs "${distro_id}" "${version_codename}"
      printf '%s\n' 'sudo apt-get update'

      case "${ghostty_state}" in
        missing)
          case "${distro_id}" in
            ubuntu)
              printf '%s\n' \
                'sudo apt-get install -y software-properties-common curl gpg' \
                'sudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu' \
                'sudo apt-get update'
              ;;
            debian)
              [[ -n "${version_codename}" ]] || die "missing debian version codename for ghostty install fallback"
              printf '%s\n' \
                'sudo apt-get install -y curl gpg lsb-release' \
                'sudo mkdir -p /usr/share/keyrings' \
                'curl -fsSL https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | sudo gpg --dearmor -o /usr/share/keyrings/debian.griffo.io.gpg' \
                "echo \"deb [signed-by=/usr/share/keyrings/debian.griffo.io.gpg] https://debian.griffo.io/apt ${version_codename} main\" | sudo tee /etc/apt/sources.list.d/debian.griffo.io.list > /dev/null" \
                'sudo apt-get update'
              ;;
            *)
              die "unsupported linux distro for ghostty install fallback: ${distro_id:-unknown}"
              ;;
          esac
          ;;
      esac

      printf '%s\n' \
        'sudo apt-get install -y ghostty' \
        'sudo apt-get install -y zsh git'
      ;;
    *)
      die "unsupported install target: ${platform}"
      ;;
  esac
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

run_install_commands() {
  local platform="${1-}"
  local distro_id="${2-}"
  local ghostty_state="${3-}"
  local version_codename="${4-}"
  local install_commands=''
  local command

  case "${platform}" in
    macos|'')
      ;;
    linux)
      validate_linux_install_inputs "${distro_id}" "${version_codename}"
      ;;
  esac

  install_commands="$(build_install_commands "${platform}" "${distro_id}" "${ghostty_state}" "${version_codename}")" || return $?

  while IFS= read -r command; do
    [[ -n "${command}" ]] || continue
    run_install_command "${command}"
  done <<< "${install_commands}"
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
  log "backed up ${target_path} to ${backup_path}"
}

ensure_symlink() {
  local source_path="$1"
  local target_path="$2"

  if [[ -e "${target_path}" && ! -L "${target_path}" ]]; then
    die "refusing to replace existing non-symlink target with symlink: ${target_path}"
  fi

  mkdir -p "$(dirname "${target_path}")"
  ln -sfn "${source_path}" "${target_path}"
}

prepare_link_target() {
  local target_path="$1"
  local source_path="$2"
  local backup_root="$3"

  if [[ -L "${target_path}" ]] && [[ "$(readlink "${target_path}")" == "${source_path}" ]]; then
    return 0
  fi

  if [[ -e "${target_path}" || -L "${target_path}" ]]; then
    backup_existing_target "${target_path}" "${backup_root}"
  fi
}

write_zsh_loader() {
  local target_path="$1"
  local source_path="$2"
  local target_dir
  local temp_path

  if [[ -L "${target_path}" && -d "${target_path}" ]]; then
    die "refusing to replace symlink-to-directory target with zsh loader: ${target_path}"
  fi

  if [[ -e "${target_path}" && ! -L "${target_path}" ]]; then
    die "refusing to replace existing non-symlink target with zsh loader: ${target_path}"
  fi

  target_dir="$(dirname "${target_path}")"
  mkdir -p "${target_dir}"
  temp_path="$(mktemp "${target_dir}/.ghostconsole-zsh.XXXXXX")"

  printf 'source "%s"\n' "${source_path}" > "${temp_path}"
  mv -f "${temp_path}" "${target_path}"
}

write_git_loader() {
  local target_path="$1"
  local source_path="$2"
  local target_dir
  local temp_path

  if [[ -L "${target_path}" && -d "${target_path}" ]]; then
    die "refusing to replace symlink-to-directory target with git loader: ${target_path}"
  fi

  if [[ -e "${target_path}" && ! -L "${target_path}" ]]; then
    die "refusing to replace existing non-symlink target with git loader: ${target_path}"
  fi

  target_dir="$(dirname "${target_path}")"
  mkdir -p "${target_dir}"
  temp_path="$(mktemp "${target_dir}/.ghostconsole-git.XXXXXX")"

  cat > "${temp_path}" <<EOF
[include]
    path = ${source_path}
EOF
  mv -f "${temp_path}" "${target_path}"
}

repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

ensure_managed_paths() {
  mkdir -p "${HOME}/.config" "${HOME}/.ghostconsole-backups"
}

link_repo_config() {
  local root
  local backup_root

  root="$(repo_root)"
  backup_root="${HOME}/.ghostconsole-backups"

  prepare_link_target "${HOME}/.config/ghostty" "${root}/.config/ghostty" "${backup_root}"
  prepare_link_target "${HOME}/.config/zsh" "${root}/.config/zsh" "${backup_root}"
  prepare_link_target "${HOME}/.config/git" "${root}/.config/git" "${backup_root}"

  ensure_symlink "${root}/.config/ghostty" "${HOME}/.config/ghostty"
  ensure_symlink "${root}/.config/zsh" "${HOME}/.config/zsh"
  ensure_symlink "${root}/.config/git" "${HOME}/.config/git"
}

write_home_entrypoints() {
  local root
  local backup_root
  local zsh_loader
  local git_loader

  root="$(repo_root)"
  backup_root="${HOME}/.ghostconsole-backups"
  zsh_loader="source \"${root}/.config/zsh/.zshrc\""
  git_loader=$'[include]\n    path = '"${root}"'/.config/git/config'

  if [[ -L "${HOME}/.zshrc" ]]; then
    backup_existing_target "${HOME}/.zshrc" "${backup_root}"
  elif [[ -e "${HOME}/.zshrc" ]] && [[ "$(< "${HOME}/.zshrc")" != "${zsh_loader}" ]]; then
    backup_existing_target "${HOME}/.zshrc" "${backup_root}"
  fi

  if [[ -L "${HOME}/.gitconfig" ]]; then
    backup_existing_target "${HOME}/.gitconfig" "${backup_root}"
  elif [[ -e "${HOME}/.gitconfig" ]] && [[ "$(< "${HOME}/.gitconfig")" != "${git_loader}" ]]; then
    backup_existing_target "${HOME}/.gitconfig" "${backup_root}"
  fi

  if [[ ! -e "${HOME}/.zshrc" && ! -L "${HOME}/.zshrc" ]]; then
    write_zsh_loader "${HOME}/.zshrc" "${root}/.config/zsh/.zshrc"
  fi

  if [[ ! -e "${HOME}/.gitconfig" && ! -L "${HOME}/.gitconfig" ]]; then
    write_git_loader "${HOME}/.gitconfig" "${root}/.config/git/config"
  fi
}

verify_installation() {
  command -v ghostty >/dev/null 2>&1 || die "ghostty not found after install"
  command -v zsh >/dev/null 2>&1 || die "zsh not found after install"
  command -v git >/dev/null 2>&1 || die "git not found after install"
}

verify_links() {
  local root
  local zsh_loader
  local git_loader

  root="$(repo_root)"
  zsh_loader="source \"${root}/.config/zsh/.zshrc\""
  git_loader=$'[include]\n    path = '"${root}"'/.config/git/config'

  [[ -L "${HOME}/.config/ghostty" ]] && [[ "$(readlink "${HOME}/.config/ghostty")" == "${root}/.config/ghostty" ]] || die "ghostty config link is incorrect"
  [[ -L "${HOME}/.config/zsh" ]] && [[ "$(readlink "${HOME}/.config/zsh")" == "${root}/.config/zsh" ]] || die "zsh config link is incorrect"
  [[ -L "${HOME}/.config/git" ]] && [[ "$(readlink "${HOME}/.config/git")" == "${root}/.config/git" ]] || die "git config link is incorrect"
  [[ -f "${HOME}/.zshrc" ]] && [[ "$(< "${HOME}/.zshrc")" == "${zsh_loader}" ]] || die "~/.zshrc loader is incorrect"
  [[ -f "${HOME}/.gitconfig" ]] && [[ "$(< "${HOME}/.gitconfig")" == "${git_loader}" ]] || die "~/.gitconfig loader is incorrect"
}

print_summary() {
  cat <<EOF
[ghostconsole] bootstrap complete
[ghostconsole] installed: ghostty, zsh, git
[ghostconsole] linked: ~/.config/ghostty ~/.config/zsh ~/.config/git ~/.zshrc ~/.gitconfig
EOF
}

main() {
  local platform
  local distro_id=''
  local ghostty_state='present'
  local version_codename=''

  platform="$(detect_platform)"

  if [[ "${platform}" == "linux" ]]; then
    distro_id="$(linux_distro_id)"
    version_codename="$(linux_version_codename)"

    if ! ghostty_available_in_apt; then
      ghostty_state='missing'
    fi
  fi

  run_install_commands "${platform}" "${distro_id}" "${ghostty_state}" "${version_codename}"
  ensure_managed_paths
  link_repo_config
  write_home_entrypoints
  verify_installation
  verify_links
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
