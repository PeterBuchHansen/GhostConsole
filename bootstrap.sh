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

backup_existing_target() {
  local target_path="$1"
  local backup_root="$2"
  local basename_no_dot
  local stamp
  local backup_path

  [[ -e "${target_path}" || -L "${target_path}" ]] || return 0

  mkdir -p "${backup_root}"
  basename_no_dot="$(basename "${target_path}" | sed 's/^\.//')"
  stamp="${GHOSTCONSOLE_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  backup_path="${backup_root}/${basename_no_dot}-${stamp}"

  mv "${target_path}" "${backup_path}"
  log "backed up ${target_path} to ${backup_path}"
}

ensure_symlink() {
  local source_path="$1"
  local target_path="$2"

  if [[ -d "${target_path}" && ! -L "${target_path}" ]]; then
    die "refusing to replace directory target with symlink: ${target_path}"
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

  if [[ -d "${target_path}" && ! -L "${target_path}" ]]; then
    die "refusing to replace directory target with zsh loader: ${target_path}"
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

  if [[ -d "${target_path}" && ! -L "${target_path}" ]]; then
    die "refusing to replace directory target with git loader: ${target_path}"
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

main() {
  local platform

  platform="$(detect_platform)"
  log "detected ${platform}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
