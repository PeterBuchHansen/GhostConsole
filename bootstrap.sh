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

main() {
  local platform

  platform="$(detect_platform)"
  log "detected ${platform}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
