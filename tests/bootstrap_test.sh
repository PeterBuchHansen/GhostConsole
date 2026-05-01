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

test_backup_existing_target_moves_it_to_backup_root() {
  local workdir
  local target
  local backup_root

  workdir="$(mktemp -d)"
  target="${workdir}/.zshrc"
  backup_root="${workdir}/backups"

  printf 'legacy-zsh\n' > "${target}"
  GHOSTCONSOLE_TIMESTAMP="20260424-120000" backup_existing_target "${target}" "${backup_root}"

  [[ ! -e "${target}" ]] || fail "target should be moved out of the way"
  [[ -f "${backup_root}/zshrc-20260424-120000" ]] || fail "backup should be created"
  pass
}

test_backup_existing_target_preserves_original_contents() {
  local workdir
  local target
  local backup_root
  local backup_path

  workdir="$(mktemp -d)"
  target="${workdir}/.gitconfig"
  backup_root="${workdir}/backups"
  backup_path="${backup_root}/gitconfig-20260424-120000"

  printf '[user]\n    name = legacy\n' > "${target}"
  GHOSTCONSOLE_TIMESTAMP="20260424-120000" backup_existing_target "${target}" "${backup_root}"

  assert_eq $'[user]\n    name = legacy' "$(< "${backup_path}")" "backup should preserve original file contents"
  pass
}

test_ensure_symlink_creates_expected_link() {
  local workdir
  local source_path
  local target_path

  workdir="$(mktemp -d)"
  source_path="${workdir}/source"
  target_path="${workdir}/target"

  mkdir -p "${source_path}"
  ensure_symlink "${source_path}" "${target_path}"

  [[ -L "${target_path}" ]] || fail "target should be a symlink"
  assert_eq "${source_path}" "$(readlink "${target_path}")" "target should point to source"
  pass
}

test_ensure_symlink_rejects_existing_directory() {
  local workdir
  local source_path
  local target_path
  local output

  workdir="$(mktemp -d)"
  source_path="${workdir}/source"
  target_path="${workdir}/target"

  mkdir -p "${source_path}" "${target_path}"

  if output="$(bash -c 'source "$1"; ensure_symlink "$2" "$3"' _ "${REPO_ROOT}/bootstrap.sh" "${source_path}" "${target_path}" 2>&1)"; then
    fail "ensure_symlink should fail for an existing real directory"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "directory rejection should use script error handling"
  [[ -d "${target_path}" ]] || fail "existing directory should remain in place"
  [[ ! -L "${target_path}/$(basename "${source_path}")" ]] || fail "ensure_symlink should not create a nested symlink"
  pass
}

test_prepare_link_target_backs_up_existing_directory() {
  local workdir
  local target_path
  local backup_root

  workdir="$(mktemp -d)"
  target_path="${workdir}/ghostty"
  backup_root="${workdir}/backups"

  mkdir -p "${target_path}"
  printf 'legacy\n' > "${target_path}/config"

  GHOSTCONSOLE_TIMESTAMP="20260424-120000" prepare_link_target "${target_path}" "/repo/.config/ghostty" "${backup_root}"

  [[ ! -d "${target_path}" ]] || fail "existing directory should be moved before linking"
  [[ -d "${backup_root}/ghostty-20260424-120000" ]] || fail "directory backup should be created"
  pass
}

test_prepare_link_target_backs_up_existing_wrong_symlink() {
  local workdir
  local source_path
  local wrong_source
  local target_path
  local backup_root
  local backup_path

  workdir="$(mktemp -d)"
  source_path="${workdir}/managed"
  wrong_source="${workdir}/legacy"
  target_path="${workdir}/ghostty"
  backup_root="${workdir}/backups"
  backup_path="${backup_root}/ghostty-20260424-120000"

  mkdir -p "${source_path}" "${wrong_source}"
  ln -s "${wrong_source}" "${target_path}"

  GHOSTCONSOLE_TIMESTAMP="20260424-120000" prepare_link_target "${target_path}" "${source_path}" "${backup_root}"

  [[ ! -e "${target_path}" && ! -L "${target_path}" ]] || fail "wrong symlink should be moved out of the way"
  [[ -L "${backup_path}" ]] || fail "wrong symlink should be backed up as a symlink"
  assert_eq "${wrong_source}" "$(readlink "${backup_path}")" "backup should preserve the original symlink target"
  [[ -d "${wrong_source}" ]] || fail "backing up the symlink should not modify the old destination"
  pass
}

test_prepare_link_target_leaves_matching_symlink_untouched() {
  local workdir
  local source_path
  local target_path
  local backup_root

  workdir="$(mktemp -d)"
  source_path="${workdir}/managed"
  target_path="${workdir}/ghostty"
  backup_root="${workdir}/backups"

  mkdir -p "${source_path}"
  ln -s "${source_path}" "${target_path}"

  GHOSTCONSOLE_TIMESTAMP="20260424-120000" prepare_link_target "${target_path}" "${source_path}" "${backup_root}"

  [[ -L "${target_path}" ]] || fail "matching symlink should remain in place"
  assert_eq "${source_path}" "$(readlink "${target_path}")" "matching symlink should stay unchanged"
  [[ ! -e "${backup_root}" ]] || fail "matching symlink should not create a backup"
  pass
}

test_write_zsh_loader_sources_repo_config() {
  local workdir
  local target_path

  workdir="$(mktemp -d)"
  target_path="${workdir}/.zshrc"

  write_zsh_loader "${target_path}" "/repo/.config/zsh/.zshrc"

  assert_eq 'source "/repo/.config/zsh/.zshrc"' "$(< "${target_path}")" "zsh loader should source repo config"
  pass
}

test_write_zsh_loader_replaces_existing_symlink_without_touching_destination() {
  local workdir
  local destination_path
  local target_path

  workdir="$(mktemp -d)"
  destination_path="${workdir}/outside-zshrc"
  target_path="${workdir}/.zshrc"

  printf 'legacy-destination\n' > "${destination_path}"
  ln -s "${destination_path}" "${target_path}"

  write_zsh_loader "${target_path}" "/repo/.config/zsh/.zshrc"

  [[ ! -L "${target_path}" ]] || fail "zsh loader should replace the symlink itself"
  assert_eq 'legacy-destination' "$(< "${destination_path}")" "zsh loader should not write through the symlink"
  assert_eq 'source "/repo/.config/zsh/.zshrc"' "$(< "${target_path}")" "zsh loader should write managed contents"
  pass
}

test_write_git_loader_includes_repo_config() {
  local workdir
  local target_path

  workdir="$(mktemp -d)"
  target_path="${workdir}/.gitconfig"

  write_git_loader "${target_path}" "/repo/.config/git/config"

  assert_eq $'[include]\n    path = /repo/.config/git/config' "$(< "${target_path}")" "git loader should include repo config"
  pass
}

test_write_git_loader_replaces_existing_symlink_without_touching_destination() {
  local workdir
  local destination_path
  local target_path

  workdir="$(mktemp -d)"
  destination_path="${workdir}/outside-gitconfig"
  target_path="${workdir}/.gitconfig"

  printf '[user]\n    email = legacy@example.com\n' > "${destination_path}"
  ln -s "${destination_path}" "${target_path}"

  write_git_loader "${target_path}" "/repo/.config/git/config"

  [[ ! -L "${target_path}" ]] || fail "git loader should replace the symlink itself"
  assert_eq $'[user]\n    email = legacy@example.com' "$(< "${destination_path}")" "git loader should not write through the symlink"
  assert_eq $'[include]\n    path = /repo/.config/git/config' "$(< "${target_path}")" "git loader should write managed contents"
  pass
}

test_detect_platform_linux_uses_apt
test_required_packages_start_with_ghostty
test_detect_platform_macos_uses_brew
test_package_manager_for_missing_arg_uses_controlled_error
test_sourcing_bootstrap_does_not_run_main
test_backup_existing_target_moves_it_to_backup_root
test_backup_existing_target_preserves_original_contents
test_ensure_symlink_creates_expected_link
test_ensure_symlink_rejects_existing_directory
test_prepare_link_target_backs_up_existing_directory
test_prepare_link_target_backs_up_existing_wrong_symlink
test_prepare_link_target_leaves_matching_symlink_untouched
test_write_zsh_loader_sources_repo_config
test_write_zsh_loader_replaces_existing_symlink_without_touching_destination
test_write_git_loader_includes_repo_config
test_write_git_loader_replaces_existing_symlink_without_touching_destination

printf 'PASS: %s tests\n' "${PASS_COUNT}"
