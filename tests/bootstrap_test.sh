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

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local message="$3"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "${message}: expected output to contain [${needle}] got [${haystack}]"
  fi
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local message="$3"

  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "${message}: expected output not to contain [${needle}] got [${haystack}]"
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

test_package_manager_for_missing_arg_uses_controlled_error() {
  local output

  if output="$(bash -c 'source "$1"; package_manager_for' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "package_manager_for without args should fail"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "missing arg should use script error handling"
  assert_contains "unsupported package manager target:" "${output}" "missing arg should explain the target failure"
  assert_not_contains "unbound variable" "${output}" "missing arg should not trigger bash unbound variable"
  pass
}

test_sourcing_bootstrap_does_not_run_main() {
  local output

  output="$(bash -c 'source "$1"' _ "${REPO_ROOT}/bootstrap.sh")"

  assert_eq "" "${output}" "sourcing bootstrap.sh should not execute main"
  pass
}

test_detect_platform_linux_uses_apt
test_required_packages_start_with_ghostty
test_detect_platform_macos_uses_brew
test_package_manager_for_missing_arg_uses_controlled_error
test_sourcing_bootstrap_does_not_run_main

printf 'PASS: %s tests\n' "${PASS_COUNT}"
