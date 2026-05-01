#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/bootstrap.sh"

PASS_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${expected}" != "${actual}" ]]; then
    fail "${message}: expected [${expected}] got [${actual}]"
  fi
}

test_detect_platform_linux_uses_apt() {
  local platform
  local manager

  platform="$(detect_platform 'linux')"
  manager="$(package_manager_for "${platform}")"

  assert_eq "linux" "${platform}" "linux platform should be detected"
  assert_eq "apt" "${manager}" "linux should use apt"
  pass
}

test_required_packages_start_with_ghostty() {
  local packages

  packages="$(required_packages)"

  assert_eq $'ghostty\nzsh\ngit' "${packages}" "Ghostty should install first"
  pass
}

test_detect_platform_macos_uses_brew() {
  local platform
  local manager

  platform="$(detect_platform 'darwin')"
  manager="$(package_manager_for "${platform}")"

  assert_eq "macos" "${platform}" "darwin should map to macos"
  assert_eq "brew" "${manager}" "macos should use brew"
  pass
}

test_detect_platform_linux_uses_apt
test_required_packages_start_with_ghostty
test_detect_platform_macos_uses_brew

printf 'PASS: %s tests\n' "${PASS_COUNT}"
