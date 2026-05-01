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

test_build_install_commands_macos_orders_ghostty_first() {
  local commands

  commands="$(build_install_commands "macos" "" "" "")"

  assert_eq $'brew install --cask ghostty\nbrew install zsh git' "${commands}" "macos install commands should install Ghostty first"
  pass
}

test_build_install_commands_ubuntu_adds_ghostty_ppa_when_missing() {
  local commands

  commands="$(build_install_commands "linux" "ubuntu" "missing" "")"

  assert_eq $'sudo apt-get update\nsudo apt-get install -y software-properties-common curl gpg\nsudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu\nsudo apt-get update\nsudo apt-get install -y ghostty\nsudo apt-get install -y zsh git' "${commands}" "ubuntu install commands should add the Ghostty PPA before package install"
  pass
}

test_build_install_commands_debian_adds_griffo_repo_when_missing() {
  local commands

  commands="$(build_install_commands "linux" "debian" "missing" "bookworm")"

  assert_eq $'sudo apt-get update\nsudo apt-get install -y curl gpg lsb-release\nsudo mkdir -p /usr/share/keyrings\ncurl -fsSL https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | sudo gpg --dearmor -o /usr/share/keyrings/debian.griffo.io.gpg\necho "deb [signed-by=/usr/share/keyrings/debian.griffo.io.gpg] https://debian.griffo.io/apt bookworm main" | sudo tee /etc/apt/sources.list.d/debian.griffo.io.list > /dev/null\nsudo apt-get update\nsudo apt-get install -y ghostty\nsudo apt-get install -y zsh git' "${commands}" "debian install commands should add the Ghostty repo before package install"
  pass
}

test_build_install_commands_linux_with_ghostty_present_skips_repo_setup() {
  local commands

  commands="$(build_install_commands "linux" "ubuntu" "present" "noble")"

  assert_eq $'sudo apt-get update\nsudo apt-get install -y ghostty\nsudo apt-get install -y zsh git' "${commands}" "linux install commands should skip repo setup when Ghostty is already available"
  pass
}

test_build_install_commands_rejects_unsupported_linux_fallback() {
  local output

  if output="$(bash -c 'source "$1"; build_install_commands "linux" "fedora" "missing" ""' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "unsupported linux fallback should fail"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "unsupported linux fallback should use script error handling"
  assert_contains "unsupported linux distro for ghostty install fallback: fedora" "${output}" "unsupported linux fallback should explain the distro rejection"
  pass
}

test_build_install_commands_rejects_missing_debian_codename() {
  local output

  if output="$(bash -c 'source "$1"; build_install_commands "linux" "debian" "missing" ""' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "debian fallback without codename should fail"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "missing debian codename should use script error handling"
  assert_contains "missing debian version codename for ghostty install fallback" "${output}" "missing debian codename should explain the failure"
  pass
}

test_run_install_commands_executes_without_bash_env_side_effects() {
  local workdir
  local bash_env_path
  local marker_path
  local output

  workdir="$(mktemp -d)"
  bash_env_path="${workdir}/bash_env.sh"
  marker_path="${workdir}/bash_env_marker"

  printf 'printf side-effect > "%s"\n' "${marker_path}" > "${bash_env_path}"

  output="$(bash -c '
    source "$1"
    build_install_commands() {
      printf "%s\n" \
        "printf first" \
        "printf -- \"|%s\" \"\$RUN_INSTALL_SENTINEL\""
    }
    export RUN_INSTALL_SENTINEL="second"
    export BASH_ENV="$2"
    run_install_commands "macos" "" "" ""
  ' _ "${REPO_ROOT}/bootstrap.sh" "${bash_env_path}")"

  assert_eq "first|second" "${output}" "run_install_commands should execute helper commands in order"
  [[ ! -e "${marker_path}" ]] || fail "run_install_commands should not source BASH_ENV side effects"
  pass
}

test_run_install_commands_rejects_unsupported_linux_fallback_before_execution() {
  local workdir
  local marker_path
  local output

  workdir="$(mktemp -d)"
  marker_path="${workdir}/executed"

  if output="$(bash -c '
    source "$1"
    run_install_command() {
      printf executed > "$2"
    }
    run_install_commands "linux" "fedora" "missing" ""
  ' _ "${REPO_ROOT}/bootstrap.sh" "${marker_path}" 2>&1)"; then
    fail "run_install_commands should fail for unsupported linux fallback"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "unsupported linux fallback should use script error handling"
  assert_contains "unsupported linux distro for ghostty install fallback: fedora" "${output}" "unsupported linux fallback should explain the distro rejection"
  [[ ! -e "${marker_path}" ]] || fail "run_install_commands should not execute any command before rejecting unsupported linux fallback"
  pass
}

test_run_install_commands_rejects_missing_debian_codename_before_execution() {
  local workdir
  local marker_path
  local output

  workdir="$(mktemp -d)"
  marker_path="${workdir}/executed"

  if output="$(bash -c '
    source "$1"
    run_install_command() {
      printf executed > "$2"
    }
    run_install_commands "linux" "debian" "missing" ""
  ' _ "${REPO_ROOT}/bootstrap.sh" "${marker_path}" 2>&1)"; then
    fail "run_install_commands should fail when Debian codename is missing"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "missing Debian codename should use script error handling"
  assert_contains "missing debian version codename for ghostty install fallback" "${output}" "missing Debian codename should explain the failure"
  [[ ! -e "${marker_path}" ]] || fail "run_install_commands should not execute any command before rejecting missing Debian codename"
  pass
}

test_run_install_command_ignores_exported_function_hijacking() {
  local output

  output="$(bash -c '
    source "$1"
    printf() {
      builtin printf hijacked
    }
    export -f printf
    run_install_command "printf safe"
  ' _ "${REPO_ROOT}/bootstrap.sh")"

  assert_eq "safe" "${output}" "run_install_command should ignore exported function hijacking"
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

test_backup_existing_target_avoids_name_collisions() {
  local workdir
  local target
  local backup_root

  workdir="$(mktemp -d)"
  target="${workdir}/.zshrc"
  backup_root="${workdir}/backups"

  printf 'first-version\n' > "${target}"
  GHOSTCONSOLE_TIMESTAMP="20260424-120000" backup_existing_target "${target}" "${backup_root}"

  printf 'second-version\n' > "${target}"
  GHOSTCONSOLE_TIMESTAMP="20260424-120000" backup_existing_target "${target}" "${backup_root}"

  [[ -f "${backup_root}/zshrc-20260424-120000" ]] || fail "first backup should keep its original name"
  [[ -f "${backup_root}/zshrc-20260424-120000-1" ]] || fail "second backup should use a collision-safe name"
  assert_eq 'first-version' "$(< "${backup_root}/zshrc-20260424-120000")" "first backup contents should be preserved"
  assert_eq 'second-version' "$(< "${backup_root}/zshrc-20260424-120000-1")" "second backup contents should be preserved"
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

test_ensure_symlink_rejects_existing_regular_file() {
  local workdir
  local source_path
  local target_path
  local output

  workdir="$(mktemp -d)"
  source_path="${workdir}/source"
  target_path="${workdir}/target"

  mkdir -p "${source_path}"
  printf 'legacy-target\n' > "${target_path}"

  if output="$(bash -c 'source "$1"; ensure_symlink "$2" "$3"' _ "${REPO_ROOT}/bootstrap.sh" "${source_path}" "${target_path}" 2>&1)"; then
    fail "ensure_symlink should fail for an existing regular file"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "file rejection should use script error handling"
  assert_eq 'legacy-target' "$(< "${target_path}")" "existing file should remain unchanged"
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

test_write_zsh_loader_rejects_existing_directory_target() {
  local workdir
  local target_path
  local output

  workdir="$(mktemp -d)"
  target_path="${workdir}/.zshrc"

  mkdir -p "${target_path}"

  if output="$(bash -c 'source "$1"; write_zsh_loader "$2" "$3"' _ "${REPO_ROOT}/bootstrap.sh" "${target_path}" "/repo/.config/zsh/.zshrc" 2>&1)"; then
    fail "zsh loader should fail for an existing real directory"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "zsh loader directory rejection should use script error handling"
  [[ -d "${target_path}" ]] || fail "zsh loader should leave the existing directory in place"
  [[ ! -e "$(dirname "${target_path}")"/.ghostconsole-zsh.* ]] || fail "zsh loader should not leave a temp file behind"
  pass
}

test_write_zsh_loader_rejects_existing_regular_file_target() {
  local workdir
  local target_path
  local output

  workdir="$(mktemp -d)"
  target_path="${workdir}/.zshrc"

  printf 'legacy-file\n' > "${target_path}"

  if output="$(bash -c 'source "$1"; write_zsh_loader "$2" "$3"' _ "${REPO_ROOT}/bootstrap.sh" "${target_path}" "/repo/.config/zsh/.zshrc" 2>&1)"; then
    fail "zsh loader should fail for an existing regular file"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "zsh loader file rejection should use script error handling"
  assert_eq 'legacy-file' "$(< "${target_path}")" "zsh loader should leave the existing file unchanged"
  [[ ! -e "$(dirname "${target_path}")"/.ghostconsole-zsh.* ]] || fail "zsh loader should not leave a temp file behind"
  pass
}

test_write_zsh_loader_rejects_symlink_to_directory_target() {
  local workdir
  local linked_dir
  local target_path
  local output

  workdir="$(mktemp -d)"
  linked_dir="${workdir}/linked-dir"
  target_path="${workdir}/.zshrc"

  mkdir -p "${linked_dir}"
  ln -s "${linked_dir}" "${target_path}"

  if output="$(bash -c 'source "$1"; write_zsh_loader "$2" "$3"' _ "${REPO_ROOT}/bootstrap.sh" "${target_path}" "/repo/.config/zsh/.zshrc" 2>&1)"; then
    fail "zsh loader should fail for a symlink to a directory"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "zsh loader symlink-dir rejection should use script error handling"
  [[ -L "${target_path}" ]] || fail "zsh loader should leave the symlink in place"
  assert_eq "${linked_dir}" "$(readlink "${target_path}")" "zsh loader should not alter the symlink target"
  [[ ! -e "${linked_dir}"/.ghostconsole-zsh.* ]] || fail "zsh loader should not move temp files into the linked directory"
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

test_write_git_loader_rejects_existing_directory_target() {
  local workdir
  local target_path
  local output

  workdir="$(mktemp -d)"
  target_path="${workdir}/.gitconfig"

  mkdir -p "${target_path}"

  if output="$(bash -c 'source "$1"; write_git_loader "$2" "$3"' _ "${REPO_ROOT}/bootstrap.sh" "${target_path}" "/repo/.config/git/config" 2>&1)"; then
    fail "git loader should fail for an existing real directory"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "git loader directory rejection should use script error handling"
  [[ -d "${target_path}" ]] || fail "git loader should leave the existing directory in place"
  [[ ! -e "$(dirname "${target_path}")"/.ghostconsole-git.* ]] || fail "git loader should not leave a temp file behind"
  pass
}

test_write_git_loader_rejects_existing_regular_file_target() {
  local workdir
  local target_path
  local output

  workdir="$(mktemp -d)"
  target_path="${workdir}/.gitconfig"

  printf '[user]\n    email = legacy@example.com\n' > "${target_path}"

  if output="$(bash -c 'source "$1"; write_git_loader "$2" "$3"' _ "${REPO_ROOT}/bootstrap.sh" "${target_path}" "/repo/.config/git/config" 2>&1)"; then
    fail "git loader should fail for an existing regular file"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "git loader file rejection should use script error handling"
  assert_eq $'[user]\n    email = legacy@example.com' "$(< "${target_path}")" "git loader should leave the existing file unchanged"
  [[ ! -e "$(dirname "${target_path}")"/.ghostconsole-git.* ]] || fail "git loader should not leave a temp file behind"
  pass
}

test_write_git_loader_rejects_symlink_to_directory_target() {
  local workdir
  local linked_dir
  local target_path
  local output

  workdir="$(mktemp -d)"
  linked_dir="${workdir}/linked-dir"
  target_path="${workdir}/.gitconfig"

  mkdir -p "${linked_dir}"
  ln -s "${linked_dir}" "${target_path}"

  if output="$(bash -c 'source "$1"; write_git_loader "$2" "$3"' _ "${REPO_ROOT}/bootstrap.sh" "${target_path}" "/repo/.config/git/config" 2>&1)"; then
    fail "git loader should fail for a symlink to a directory"
  fi

  assert_contains "[ghostconsole] error:" "${output}" "git loader symlink-dir rejection should use script error handling"
  [[ -L "${target_path}" ]] || fail "git loader should leave the symlink in place"
  assert_eq "${linked_dir}" "$(readlink "${target_path}")" "git loader should not alter the symlink target"
  [[ ! -e "${linked_dir}"/.ghostconsole-git.* ]] || fail "git loader should not move temp files into the linked directory"
  pass
}

test_detect_platform_linux_uses_apt
test_required_packages_start_with_ghostty
test_detect_platform_macos_uses_brew
test_build_install_commands_macos_orders_ghostty_first
test_build_install_commands_ubuntu_adds_ghostty_ppa_when_missing
test_build_install_commands_debian_adds_griffo_repo_when_missing
test_build_install_commands_linux_with_ghostty_present_skips_repo_setup
test_build_install_commands_rejects_unsupported_linux_fallback
test_build_install_commands_rejects_missing_debian_codename
test_run_install_commands_executes_without_bash_env_side_effects
test_run_install_commands_rejects_unsupported_linux_fallback_before_execution
test_run_install_commands_rejects_missing_debian_codename_before_execution
test_run_install_command_ignores_exported_function_hijacking
test_package_manager_for_missing_arg_uses_controlled_error
test_sourcing_bootstrap_does_not_run_main
test_backup_existing_target_moves_it_to_backup_root
test_backup_existing_target_preserves_original_contents
test_backup_existing_target_avoids_name_collisions
test_ensure_symlink_creates_expected_link
test_ensure_symlink_rejects_existing_directory
test_ensure_symlink_rejects_existing_regular_file
test_prepare_link_target_backs_up_existing_directory
test_prepare_link_target_backs_up_existing_wrong_symlink
test_prepare_link_target_leaves_matching_symlink_untouched
test_write_zsh_loader_sources_repo_config
test_write_zsh_loader_replaces_existing_symlink_without_touching_destination
test_write_zsh_loader_rejects_existing_directory_target
test_write_zsh_loader_rejects_existing_regular_file_target
test_write_zsh_loader_rejects_symlink_to_directory_target
test_write_git_loader_includes_repo_config
test_write_git_loader_replaces_existing_symlink_without_touching_destination
test_write_git_loader_rejects_existing_directory_target
test_write_git_loader_rejects_existing_regular_file_target
test_write_git_loader_rejects_symlink_to_directory_target

printf 'PASS: %s tests\n' "${PASS_COUNT}"
