# GhostConsole Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working `GhostConsole` bootstrap that installs `Ghostty` first, then `zsh` and `git`, and links repo-managed config for all three tools on macOS and Debian/Ubuntu-style Linux.

**Architecture:** Keep a single `bootstrap.sh` entrypoint, but structure it as sourceable shell functions with a `main` guard so it can be tested without running real installs during tests. Use a lightweight shell test file to drive TDD around platform detection, install command selection, backup/link behavior, and end-to-end orchestration before adding repo config and documentation.

**Tech Stack:** Bash, Homebrew, `apt`, small shell tests, repo-managed dotfiles/config under `.config/`

---

## File Structure
Create or modify these files during implementation:

- Create: `bootstrap.sh`
- Create: `tests/bootstrap_test.sh`
- Create: `.config/ghostty/config`
- Create: `.config/zsh/.zshrc`
- Create: `.config/git/config`
- Create: `bin/.gitkeep`
- Modify: `README.md`

Each file should keep one clear responsibility:

- `bootstrap.sh`: all bootstrap functions plus the `main` entrypoint
- `tests/bootstrap_test.sh`: shell-based regression tests for bootstrap behavior
- `.config/ghostty/config`: starter `Ghostty` config
- `.config/zsh/.zshrc`: starter `zsh` config sourced by the generated home-level loader
- `.config/git/config`: shared git defaults included from `~/.gitconfig`
- `README.md`: accurate install scope, structure, and manual verification steps

### Task 1: Test Harness And Bootstrap Skeleton

**Files:**
- Create: `tests/bootstrap_test.sh`
- Create: `bootstrap.sh`
- Test: `tests/bootstrap_test.sh`

- [ ] **Step 1: Write the failing test for platform detection and package order**

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/bootstrap_test.sh`

Expected: FAIL with a message like `bootstrap.sh: No such file or directory` because the bootstrap entrypoint does not exist yet.

- [ ] **Step 3: Write the minimal bootstrap skeleton**

```bash
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
  case "$1" in
    macos)
      printf 'brew\n'
      ;;
    linux)
      printf 'apt\n'
      ;;
    *)
      die "unsupported package manager target: $1"
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/bootstrap_test.sh`

Expected: `PASS: 3 tests`

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh tests/bootstrap_test.sh
git commit -m "test: add bootstrap shell test harness"
```

### Task 2: Backup, Linking, And Managed Entry Files

**Files:**
- Modify: `bootstrap.sh`
- Modify: `tests/bootstrap_test.sh`
- Create: `.config/ghostty/config`
- Create: `.config/zsh/.zshrc`
- Create: `.config/git/config`
- Create: `bin/.gitkeep`
- Test: `tests/bootstrap_test.sh`

- [ ] **Step 1: Write failing tests for backup, symlink creation, and generated home entrypoints**

```bash
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

test_write_zsh_loader_sources_repo_config() {
  local workdir
  local target_path

  workdir="$(mktemp -d)"
  target_path="${workdir}/.zshrc"

  write_zsh_loader "${target_path}" "/repo/.config/zsh/.zshrc"

  assert_eq 'source "/repo/.config/zsh/.zshrc"' "$(cat "${target_path}")" "zsh loader should source repo config"
  pass
}

test_write_git_loader_includes_repo_config() {
  local workdir
  local target_path

  workdir="$(mktemp -d)"
  target_path="${workdir}/.gitconfig"

  write_git_loader "${target_path}" "/repo/.config/git/config"

  assert_eq $'[include]\n    path = /repo/.config/git/config' "$(cat "${target_path}")" "git loader should include repo config"
  pass
}

test_backup_existing_target_moves_it_to_backup_root
test_ensure_symlink_creates_expected_link
test_prepare_link_target_backs_up_existing_directory
test_write_zsh_loader_sources_repo_config
test_write_git_loader_includes_repo_config
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/bootstrap_test.sh`

Expected: FAIL with `command not found` for one of `backup_existing_target`, `ensure_symlink`, `write_zsh_loader`, or `write_git_loader`.

- [ ] **Step 3: Implement linking helpers and add starter config files**

```bash
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

  printf 'source "%s"\n' "${source_path}" > "${target_path}"
}

write_git_loader() {
  local target_path="$1"
  local source_path="$2"

  cat > "${target_path}" <<EOF
[include]
    path = ${source_path}
EOF
}
```

```text
# .config/ghostty/config
font-size = 14
theme = dark:OneHalfDark,light:OneHalfLight
```

```bash
# .config/zsh/.zshrc
export GHOSTCONSOLE_HOME="${HOME}/.config/zsh"
export PATH="${HOME}/bin:${PATH}"

autoload -Uz compinit
compinit
```

```ini
# .config/git/config
[init]
    defaultBranch = main

[pull]
    rebase = false
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/bootstrap_test.sh`

Expected: `PASS: 8 tests`

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh tests/bootstrap_test.sh .config/ghostty/config .config/zsh/.zshrc .config/git/config bin/.gitkeep
git commit -m "feat: add managed config linking helpers"
```

### Task 3: Package Installation Logic With Ghostty-First Ordering

**Files:**
- Modify: `bootstrap.sh`
- Modify: `tests/bootstrap_test.sh`
- Test: `tests/bootstrap_test.sh`

- [ ] **Step 1: Write failing tests for macOS install commands and Linux Ghostty fallback**

```bash
test_macos_install_commands_install_ghostty_first() {
  local commands

  commands="$(build_install_commands macos '' '')"

  assert_eq $'brew install --cask ghostty\nbrew install zsh git' "${commands}" "macos install commands should install Ghostty first"
  pass
}

test_ubuntu_install_commands_use_ppa_when_apt_package_missing() {
  local commands

  commands="$(build_install_commands linux ubuntu missing)"

  assert_eq $'sudo apt-get update\nsudo apt-get install -y software-properties-common curl gpg\nsudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu\nsudo apt-get update\nsudo apt-get install -y ghostty\nsudo apt-get install -y zsh git' "${commands}" "ubuntu fallback should use the Ghostty PPA and still install Ghostty first"
  pass
}

test_debian_install_commands_add_repo_when_apt_package_missing() {
  local commands

  commands="$(build_install_commands linux debian missing bookworm)"

  assert_eq $'sudo apt-get update\nsudo apt-get install -y curl gpg lsb-release\nsudo mkdir -p /usr/share/keyrings\ncurl -fsSL https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | sudo gpg --dearmor -o /usr/share/keyrings/debian.griffo.io.gpg\necho "deb [signed-by=/usr/share/keyrings/debian.griffo.io.gpg] https://debian.griffo.io/apt bookworm main" | sudo tee /etc/apt/sources.list.d/debian.griffo.io.list > /dev/null\nsudo apt-get update\nsudo apt-get install -y ghostty\nsudo apt-get install -y zsh git' "${commands}" "debian fallback should add the community repo and still install Ghostty first"
  pass
}

test_linux_install_commands_use_direct_apt_when_ghostty_exists() {
  local commands

  commands="$(build_install_commands linux ubuntu present)"

  assert_eq $'sudo apt-get update\nsudo apt-get install -y ghostty\nsudo apt-get install -y zsh git' "${commands}" "linux should use apt directly when Ghostty is available"
  pass
}

test_macos_install_commands_install_ghostty_first
test_ubuntu_install_commands_use_ppa_when_apt_package_missing
test_debian_install_commands_add_repo_when_apt_package_missing
test_linux_install_commands_use_direct_apt_when_ghostty_exists
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/bootstrap_test.sh`

Expected: FAIL with `build_install_commands: command not found`.

- [ ] **Step 3: Implement package install command selection**

```bash
build_install_commands() {
  local platform="$1"
  local distro_id="${2:-}"
  local ghostty_state="${3:-present}"
  local version_codename="${4:-}"

  case "${platform}" in
    macos)
      cat <<'EOF'
brew install --cask ghostty
brew install zsh git
EOF
      ;;
    linux)
      if [[ "${ghostty_state}" == "present" ]]; then
        cat <<'EOF'
sudo apt-get update
sudo apt-get install -y ghostty
sudo apt-get install -y zsh git
EOF
        return 0
      fi

      case "${distro_id}" in
        ubuntu)
          cat <<'EOF'
sudo apt-get update
sudo apt-get install -y software-properties-common curl gpg
sudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu
sudo apt-get update
sudo apt-get install -y ghostty
sudo apt-get install -y zsh git
EOF
          ;;
        debian)
          cat <<'EOF'
sudo apt-get update
sudo apt-get install -y curl gpg lsb-release
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | sudo gpg --dearmor -o /usr/share/keyrings/debian.griffo.io.gpg
echo "deb [signed-by=/usr/share/keyrings/debian.griffo.io.gpg] https://debian.griffo.io/apt ${version_codename} main" | sudo tee /etc/apt/sources.list.d/debian.griffo.io.list > /dev/null
sudo apt-get update
sudo apt-get install -y ghostty
sudo apt-get install -y zsh git
EOF
          ;;
        *)
          die "unsupported linux distro for Ghostty fallback: ${distro_id}"
          ;;
      esac
      ;;
    *)
      die "unsupported platform for installs: ${platform}"
      ;;
  esac
}

ghostty_available_in_apt() {
  apt-cache show ghostty >/dev/null 2>&1
}

linux_distro_id() {
  . /etc/os-release
  printf '%s\n' "${ID}"
}

linux_version_codename() {
  . /etc/os-release
  printf '%s\n' "${VERSION_CODENAME:-}"
}

run_install_commands() {
  local platform="$1"
  local distro_id="${2:-}"
  local ghostty_state="${3:-present}"
  local version_codename="${4:-}"

  while IFS= read -r command_line; do
    [[ -n "${command_line}" ]] || continue
    log "running: ${command_line}"
    eval "${command_line}"
  done < <(build_install_commands "${platform}" "${distro_id}" "${ghostty_state}" "${version_codename}")
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/bootstrap_test.sh`

Expected: `PASS: 12 tests`

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh tests/bootstrap_test.sh
git commit -m "feat: add ghostty-first install logic"
```

### Task 4: Main Orchestration, Verification, And README

**Files:**
- Modify: `bootstrap.sh`
- Modify: `tests/bootstrap_test.sh`
- Modify: `README.md`
- Test: `tests/bootstrap_test.sh`

- [ ] **Step 1: Write failing orchestration tests for call order and generated files**

```bash
test_main_runs_install_before_linking() {
  local workdir
  local trace_file

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"

  repo_root() { printf '%s\n' "/repo"; }
  detect_platform() { printf 'linux\n'; }
  package_manager_for() { printf 'apt\n'; }
  linux_distro_id() { printf 'ubuntu\n'; }
  ghostty_available_in_apt() { return 0; }
  run_install_commands() { printf 'install\n' >> "${trace_file}"; }
  ensure_managed_paths() { printf 'paths\n' >> "${trace_file}"; }
  link_repo_config() { printf 'links\n' >> "${trace_file}"; }
  write_home_entrypoints() { printf 'entrypoints\n' >> "${trace_file}"; }
  verify_installation() { printf 'verify-install\n' >> "${trace_file}"; }
  verify_links() { printf 'verify-links\n' >> "${trace_file}"; }
  print_summary() { printf 'summary\n' >> "${trace_file}"; }

  main

  assert_eq $'install\npaths\nlinks\nentrypoints\nverify-install\nverify-links\nsummary' "$(cat "${trace_file}")" "main should install before linking and verify before summary"
  pass
}

test_main_runs_install_before_linking
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/bootstrap_test.sh`

Expected: FAIL because `main` does not yet orchestrate those functions.

- [ ] **Step 3: Implement orchestration helpers and update README**

```bash
repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

ensure_managed_paths() {
  mkdir -p "${HOME}/.config" "${HOME}/.ghostconsole-backups"
}

link_repo_config() {
  local root
  root="$(repo_root)"

  prepare_link_target "${HOME}/.config/ghostty" "${root}/.config/ghostty" "${HOME}/.ghostconsole-backups"
  prepare_link_target "${HOME}/.config/zsh" "${root}/.config/zsh" "${HOME}/.ghostconsole-backups"
  prepare_link_target "${HOME}/.config/git" "${root}/.config/git" "${HOME}/.ghostconsole-backups"

  ensure_symlink "${root}/.config/ghostty" "${HOME}/.config/ghostty"
  ensure_symlink "${root}/.config/zsh" "${HOME}/.config/zsh"
  ensure_symlink "${root}/.config/git" "${HOME}/.config/git"
}

write_home_entrypoints() {
  local root
  root="$(repo_root)"

  if [[ -e "${HOME}/.zshrc" && ! -L "${HOME}/.zshrc" ]]; then
    backup_existing_target "${HOME}/.zshrc" "${HOME}/.ghostconsole-backups"
  fi

  if [[ -e "${HOME}/.gitconfig" && ! -L "${HOME}/.gitconfig" ]]; then
    backup_existing_target "${HOME}/.gitconfig" "${HOME}/.ghostconsole-backups"
  fi

  write_zsh_loader "${HOME}/.zshrc" "${root}/.config/zsh/.zshrc"
  write_git_loader "${HOME}/.gitconfig" "${root}/.config/git/config"
}

verify_installation() {
  command -v ghostty >/dev/null 2>&1 || die "ghostty not found after install"
  command -v zsh >/dev/null 2>&1 || die "zsh not found after install"
  command -v git >/dev/null 2>&1 || die "git not found after install"
}

verify_links() {
  local root
  root="$(repo_root)"

  [[ "$(readlink "${HOME}/.config/ghostty")" == "${root}/.config/ghostty" ]] || die "ghostty config link is incorrect"
  [[ "$(readlink "${HOME}/.config/zsh")" == "${root}/.config/zsh" ]] || die "zsh config link is incorrect"
  [[ "$(readlink "${HOME}/.config/git")" == "${root}/.config/git" ]] || die "git config link is incorrect"
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
  local distro_id=""
  local ghostty_state="present"
  local version_codename=""

  platform="$(detect_platform)"

  if [[ "${platform}" == "linux" ]]; then
    distro_id="$(linux_distro_id)"
    version_codename="$(linux_version_codename)"
    if ! ghostty_available_in_apt; then
      ghostty_state="missing"
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
```

````markdown
## 🚀 Getting started
Clone the repo and run:

```bash
./bootstrap.sh
```

This first version installs:
- `Ghostty`
- `zsh`
- `git`

It then links repo-managed config for those tools into your home directory.

## ✅ Verify
After bootstrap completes:

```bash
zsh --version
git --version
ghostty --version
```

Confirm these paths now point at the repo:

```bash
readlink ~/.config/ghostty
readlink ~/.config/zsh
readlink ~/.config/git
```
````

- [ ] **Step 4: Run the test suite to verify everything passes**

Run: `bash tests/bootstrap_test.sh`

Expected: `PASS: 13 tests`

- [ ] **Step 5: Run final manual verification**

Run: `bash tests/bootstrap_test.sh && bash bootstrap.sh`

Expected:
- tests print `PASS: 13 tests`
- bootstrap logs each stage
- final summary prints installed and linked targets

- [ ] **Step 6: Commit**

```bash
git add bootstrap.sh tests/bootstrap_test.sh README.md .config/ghostty/config .config/zsh/.zshrc .config/git/config bin/.gitkeep
git commit -m "feat: bootstrap ghostconsole core setup"
```
