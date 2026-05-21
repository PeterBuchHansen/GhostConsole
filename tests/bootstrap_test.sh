#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# apply_repo_config must run in a subprocess: the test harness shares one shell with
# sourced bootstrap.sh and later tests can override functions; a clean bash also pins HOME.
ghostconsole_test_apply_repo_config_in_home() {
  local workdir="${1:?}"
  local timestamp="${2-}"
  if [[ -n "${timestamp}" ]]; then
    HOME="${workdir}" GHOSTCONSOLE_TIMESTAMP="${timestamp}" bash -euo pipefail -c '
      source "$1"
      apply_repo_config
    ' _ "${REPO_ROOT}/bootstrap.sh"
  else
    HOME="${workdir}" bash -euo pipefail -c '
      source "$1"
      apply_repo_config
    ' _ "${REPO_ROOT}/bootstrap.sh"
  fi
}

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

test_color_prefix_uses_ansi_when_forced() {
  local output

  output="$(GHOSTCONSOLE_COLOR=always color_prefix error 2)"

  assert_eq $'\033[31m[GhostConsole-Installer]\033[0m' "${output}" "error prefix should be red when color is forced"
  pass
}

test_color_prefix_stays_plain_when_disabled() {
  local output

  output="$(GHOSTCONSOLE_COLOR=never color_prefix success 1)"

  assert_eq '[GhostConsole-Installer]' "${output}" "prefix should stay plain when color is disabled"
  pass
}

test_macos_install_invokes_ghostty_first() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "brew" ]]; then
      return 0
    fi
    builtin command "$@"
  }

  macos_install

  [[ "${#calls[@]}" == 2 ]] || fail "macos_install should run two install commands"
  assert_eq 'brew install --cask ghostty' "${calls[0]}" "macos_install should install Ghostty first"
  assert_eq 'brew install zsh git coreutils ncdu btop lazygit lazydocker' "${calls[1]}" "macos_install should install zsh, git, coreutils, and TUI tools after Ghostty"
  pass
}

test_linux_ubuntu_install_uses_ghostty_ubuntu_install_script() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "ghostty" ]]; then
      return 1
    fi
    if [[ "$1" == "-v" && ( "$2" == "lazygit" || "$2" == "lazydocker" ) ]]; then
      return 1
    fi
    builtin command "$@"
  }

  linux_ubuntu_install

  assert_eq 4 "${#calls[@]}" "ubuntu flow should install Ghostty, apt packages, lazygit, and lazydocker"
  assert_eq '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"' "${calls[0]}" "ubuntu flow should install Ghostty from the documented ghostty-ubuntu script first"
  assert_eq 'sudo apt-get install -y zsh git ncdu btop' "${calls[1]}" "ubuntu flow should install zsh, git, and apt-packaged TUI tools after Ghostty"
  assert_contains "jesseduffield/lazygit" "${calls[2]}" "ubuntu flow should install lazygit from GitHub releases"
  assert_contains "jesseduffield/lazydocker" "${calls[3]}" "ubuntu flow should install lazydocker from GitHub releases"
  pass
}

test_linux_ubuntu_install_skips_ghostty_installer_when_present() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "ghostty" ]]; then
      return 0
    fi
    if [[ "$1" == "-v" && ( "$2" == "lazygit" || "$2" == "lazydocker" ) ]]; then
      return 1
    fi
    builtin command "$@"
  }

  linux_ubuntu_install

  assert_eq 3 "${#calls[@]}" "ubuntu flow should install apt packages, lazygit, and lazydocker when Ghostty is already installed"
  assert_eq 'sudo apt-get install -y zsh git ncdu btop' "${calls[0]}" "ubuntu flow should not rerun the upstream Ghostty installer when ghostty is already available"
  assert_contains "jesseduffield/lazygit" "${calls[1]}" "ubuntu flow should still install lazygit when Ghostty is already installed"
  assert_contains "jesseduffield/lazydocker" "${calls[2]}" "ubuntu flow should still install lazydocker when Ghostty is already installed"
  pass
}

test_linux_ubuntu_install_reports_ghostty_installer_failure() {
  local output

  run_install_command() {
    return 1
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "ghostty" ]]; then
      return 1
    fi
    if [[ "$1" == "-v" && ( "$2" == "lazygit" || "$2" == "lazydocker" ) ]]; then
      return 1
    fi
    builtin command "$@"
  }

  if output="$(linux_ubuntu_install 2>&1)"; then
    fail "ubuntu install should fail when the upstream Ghostty installer fails"
  fi

  assert_contains "Ghostty installer failed" "${output}" "ubuntu install should explain upstream Ghostty installer failures"
  pass
}

test_linux_ubuntu_install_falls_back_when_ghostty_installer_fails() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
    if [[ "$1" == *"raw.githubusercontent.com/mkasberg/ghostty-ubuntu"* ]]; then
      return 1
    fi
    return 0
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "ghostty" ]]; then
      return 1
    fi
    if [[ "$1" == "-v" && ( "$2" == "lazygit" || "$2" == "lazydocker" ) ]]; then
      return 1
    fi
    builtin command "$@"
  }

  linux_ubuntu_install

  assert_eq 5 "${#calls[@]}" "ubuntu flow should try upstream installer, fallback installer, apt packages, lazygit, and lazydocker"
  assert_contains "raw.githubusercontent.com/mkasberg/ghostty-ubuntu" "${calls[0]}" "ubuntu flow should try the documented Ghostty installer first"
  assert_contains "github.com/mkasberg/ghostty-ubuntu/releases/latest" "${calls[1]}" "ubuntu fallback should avoid the GitHub API release lookup"
  assert_eq 'sudo apt-get install -y zsh git ncdu btop' "${calls[2]}" "ubuntu flow should install zsh, git, and apt-packaged TUI tools after Ghostty fallback"
  assert_contains "jesseduffield/lazygit" "${calls[3]}" "ubuntu flow should install lazygit after Ghostty fallback"
  assert_contains "jesseduffield/lazydocker" "${calls[4]}" "ubuntu flow should install lazydocker after Ghostty fallback"
  pass
}

test_install_ubuntu_github_release_tool_installs_missing_binary() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "lazygit" ]]; then
      return 1
    fi
    builtin command "$@"
  }

  install_ubuntu_github_release_tool lazygit jesseduffield/lazygit

  [[ "${#calls[@]}" == 1 ]] || fail "missing GitHub release tool should run one install command"
  assert_contains "https://github.com/jesseduffield/lazygit/releases/latest" "${calls[0]}" "GitHub release tool install should resolve latest without the GitHub API"
  assert_contains "lazygit_\${version}_Linux_\${arch}.tar.gz" "${calls[0]}" "GitHub release tool install should download the expected Linux archive"
  assert_contains "sudo install -m 0755 lazygit /usr/local/bin/lazygit" "${calls[0]}" "GitHub release tool install should install binary into /usr/local/bin"
  pass
}

test_install_ubuntu_github_release_tool_skips_existing_binary() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "lazygit" ]]; then
      return 0
    fi
    builtin command "$@"
  }

  install_ubuntu_github_release_tool lazygit jesseduffield/lazygit

  assert_eq 0 "${#calls[@]}" "existing GitHub release tool should not be reinstalled"
  pass
}

test_install_ubuntu_github_release_tool_forces_existing_binary_when_requested() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "lazygit" ]]; then
      return 0
    fi
    builtin command "$@"
  }

  install_ubuntu_github_release_tool lazygit jesseduffield/lazygit force

  [[ "${#calls[@]}" == 1 ]] || fail "forced GitHub release tool install should run even when binary exists"
  assert_contains "https://github.com/jesseduffield/lazygit/releases/latest" "${calls[0]}" "forced GitHub release tool install should resolve latest release"
  pass
}

test_install_tui_tools_ubuntu_installs_only_tui_tools() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" ]]; then
      return 1
    fi
    builtin command "$@"
  }

  uname() {
    printf 'Linux\n'
  }

  install_tui_tools

  assert_eq 3 "${#calls[@]}" "ubuntu TUI installer should run apt plus lazygit and lazydocker installs"
  assert_eq 'sudo apt-get install -y ncdu btop' "${calls[0]}" "standalone Ubuntu TUI installer should not install ghostty, zsh, or git"
  assert_contains "jesseduffield/lazygit" "${calls[1]}" "standalone Ubuntu TUI installer should install lazygit"
  assert_contains "jesseduffield/lazydocker" "${calls[2]}" "standalone Ubuntu TUI installer should install lazydocker"
  pass
}

test_update_tui_tools_ubuntu_updates_tui_tools() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" ]]; then
      return 0
    fi
    builtin command "$@"
  }

  uname() {
    printf 'Linux\n'
  }

  update_tui_tools

  assert_eq 3 "${#calls[@]}" "ubuntu TUI updater should update apt packages plus GitHub release tools"
  assert_eq 'sudo apt-get update && sudo apt-get install -y ncdu btop' "${calls[0]}" "Ubuntu TUI updater should refresh apt metadata and update apt-packaged tools"
  assert_contains "jesseduffield/lazygit" "${calls[1]}" "Ubuntu TUI updater should update lazygit from GitHub releases"
  assert_contains "jesseduffield/lazydocker" "${calls[2]}" "Ubuntu TUI updater should update lazydocker from GitHub releases"
  pass
}

test_install_cursor_cli_runs_official_installer_when_missing() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "agent" ]]; then
      return 1
    fi
    builtin command "$@"
  }

  install_cursor_cli

  assert_eq 'curl https://cursor.com/install -fsS | bash' "$(printf '%s\n' "${calls[@]}")" "Cursor CLI installer should use the official install command"
  pass
}

test_install_cursor_cli_updates_when_agent_exists() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "agent" ]]; then
      return 0
    fi
    builtin command "$@"
  }

  install_cursor_cli

  assert_eq 'agent update' "$(printf '%s\n' "${calls[@]}")" "Cursor CLI installer should update when agent is already available"
  pass
}

test_uninstall_cursor_cli_removes_local_agent_only() {
  local workdir

  workdir="$(mktemp -d)"
  HOME="${workdir}"
  mkdir -p "${HOME}/.local/bin"
  printf 'agent\n' > "${HOME}/.local/bin/agent"
  chmod +x "${HOME}/.local/bin/agent"

  uninstall_cursor_cli

  [[ ! -e "${HOME}/.local/bin/agent" ]] || fail "Cursor CLI uninstall should remove ~/.local/bin/agent"
  pass
}

test_uninstall_cursor_cli_skips_when_local_agent_missing() {
  local workdir
  local output

  workdir="$(mktemp -d)"
  HOME="${workdir}"

  output="$(uninstall_cursor_cli)"

  assert_contains "Cursor CLI not found at ${HOME}/.local/bin/agent; skipping." "${output}" "Cursor CLI uninstall should explain missing local agent"
  pass
}

test_install_powerlevel10k_clones_when_missing() {
  local workdir
  local plugin_path
  local -a calls=()

  workdir="$(mktemp -d)"
  GHOSTCONSOLE_ROOT="${workdir}/repo"
  plugin_path="${GHOSTCONSOLE_ROOT}/.config/zsh/plugins/powerlevel10k"

  run_install_command() {
    calls+=("$1")
  }

  install_powerlevel10k

  [[ -d "$(dirname "${plugin_path}")" ]] || fail "Powerlevel10k parent directory should be created"
  assert_eq "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \"${plugin_path}\"" "${calls[0]}" "Powerlevel10k should be cloned when missing"
  GHOSTCONSOLE_ROOT="${REPO_ROOT}"
  pass
}

test_install_powerlevel10k_updates_existing_checkout() {
  local workdir
  local plugin_path
  local -a calls=()

  workdir="$(mktemp -d)"
  GHOSTCONSOLE_ROOT="${workdir}/repo"
  plugin_path="${GHOSTCONSOLE_ROOT}/.config/zsh/plugins/powerlevel10k"
  mkdir -p "${plugin_path}/.git"

  run_install_command() {
    calls+=("$1")
  }

  install_powerlevel10k

  assert_eq "git -C \"${plugin_path}\" pull --ff-only" "${calls[0]}" "Powerlevel10k should update an existing checkout"
  GHOSTCONSOLE_ROOT="${REPO_ROOT}"
  pass
}

test_install_powerlevel10k_backs_up_non_git_path_before_reinstall() {
  local workdir
  local plugin_path
  local backup_path
  local -a calls=()

  workdir="$(mktemp -d)"
  GHOSTCONSOLE_ROOT="${workdir}/repo with spaces"
  GHOSTCONSOLE_BACKUP_ROOT="${workdir}/backups"
  plugin_path="${GHOSTCONSOLE_ROOT}/.config/zsh/plugins/powerlevel10k"
  backup_path="${GHOSTCONSOLE_BACKUP_ROOT}/powerlevel10k-20260424-120000"
  mkdir -p "${plugin_path}"
  printf 'legacy\n' > "${plugin_path}/README"

  run_install_command() {
    calls+=("$1")
  }

  GHOSTCONSOLE_TIMESTAMP="20260424-120000" install_powerlevel10k

  [[ -d "${backup_path}" ]] || fail "Powerlevel10k should back up an existing non-git path before reinstalling"
  assert_eq 'legacy' "$(< "${backup_path}/README")" "Powerlevel10k backup should preserve existing plugin contents"
  assert_eq "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \"${plugin_path}\"" "${calls[0]}" "Powerlevel10k reinstall should clone into the plugin path after backup"
  GHOSTCONSOLE_ROOT="${REPO_ROOT}"
  GHOSTCONSOLE_BACKUP_ROOT="${HOME}/.ghostconsole-backups"
  pass
}

test_install_powerlevel10k_reports_git_config_help_on_clone_failure() {
  local workdir
  local output

  workdir="$(mktemp -d)"

  if output="$(bash -c '
    source "$1"
    GHOSTCONSOLE_ROOT="$2"
    run_install_command() { return 1; }
    install_powerlevel10k
  ' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}/repo" 2>&1)"; then
    fail "Powerlevel10k install should fail when clone command fails"
  fi

  assert_contains "Failed to clone Powerlevel10k from https://github.com/romkatv/powerlevel10k.git." "${output}" "Powerlevel10k clone failure should explain what failed"
  assert_contains "git config --global --get-regexp '^url\\..*\\.insteadof$'" "${output}" "Powerlevel10k clone failure should suggest checking git URL rewrite rules"
  assert_contains "git ls-remote https://github.com/romkatv/powerlevel10k.git" "${output}" "Powerlevel10k clone failure should suggest direct git connectivity check"
  pass
}

test_install_powerlevel10k_reports_git_config_help_on_update_failure() {
  local workdir
  local plugin_path
  local output

  workdir="$(mktemp -d)"
  plugin_path="${workdir}/repo/.config/zsh/plugins/powerlevel10k"
  mkdir -p "${plugin_path}/.git"

  if output="$(bash -c '
    source "$1"
    GHOSTCONSOLE_ROOT="$2"
    run_install_command() { return 1; }
    install_powerlevel10k
  ' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}/repo" 2>&1)"; then
    fail "Powerlevel10k update should fail when git pull command fails"
  fi

  assert_contains "Failed to update Powerlevel10k from https://github.com/romkatv/powerlevel10k.git." "${output}" "Powerlevel10k update failure should explain what failed"
  assert_contains "git config --global --get-regexp '^url\\..*\\.insteadof$'" "${output}" "Powerlevel10k update failure should suggest checking git URL rewrite rules"
  assert_contains "git ls-remote https://github.com/romkatv/powerlevel10k.git" "${output}" "Powerlevel10k update failure should suggest direct git connectivity check"
  pass
}

test_install_powerlevel10k_reports_permission_fix_on_update_failure() {
  local workdir
  local plugin_path
  local output

  workdir="$(mktemp -d)"
  plugin_path="${workdir}/repo/.config/zsh/plugins/powerlevel10k"
  mkdir -p "${plugin_path}/.git"
  chmod 0555 "${plugin_path}/.git"

  if output="$(bash -c '
    source "$1"
    GHOSTCONSOLE_ROOT="$2"
    run_install_command() { return 1; }
    install_powerlevel10k
  ' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}/repo" 2>&1)"; then
    fail "Powerlevel10k update should fail when git pull command fails on a non-writable git directory"
  fi

  assert_contains "Detected likely filesystem permission issue" "${output}" "Powerlevel10k update failure should highlight permission problems when plugin path is not writable"
  assert_contains "sudo chown -R" "${output}" "Powerlevel10k update failure should include chown ownership fix command"
  pass
}

test_install_zsh_autosuggestions_clones_when_missing() {
  local workdir
  local plugin_path
  local -a calls=()

  workdir="$(mktemp -d)"
  GHOSTCONSOLE_ROOT="${workdir}/repo"
  plugin_path="${GHOSTCONSOLE_ROOT}/.config/zsh/plugins/zsh-autosuggestions"

  run_install_command() {
    calls+=("$1")
  }

  install_zsh_autosuggestions

  [[ -d "$(dirname "${plugin_path}")" ]] || fail "zsh-autosuggestions parent directory should be created"
  assert_eq "git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \"${plugin_path}\"" "${calls[0]}" "zsh-autosuggestions should be cloned when missing"
  GHOSTCONSOLE_ROOT="${REPO_ROOT}"
  pass
}

test_install_zsh_autosuggestions_updates_existing_checkout() {
  local workdir
  local plugin_path
  local -a calls=()

  workdir="$(mktemp -d)"
  GHOSTCONSOLE_ROOT="${workdir}/repo"
  plugin_path="${GHOSTCONSOLE_ROOT}/.config/zsh/plugins/zsh-autosuggestions"
  mkdir -p "${plugin_path}/.git"

  run_install_command() {
    calls+=("$1")
  }

  install_zsh_autosuggestions

  assert_eq "git -C \"${plugin_path}\" pull --ff-only" "${calls[0]}" "zsh-autosuggestions should update an existing checkout"
  GHOSTCONSOLE_ROOT="${REPO_ROOT}"
  pass
}

test_welcome_ghost_prints_only_in_interactive_ghostty_shell() {
  local output
  local page_path
  local boot_id

  page_path="$(mktemp)"
  boot_id="print-boot-${RANDOM}-${RANDOM}"
  rm -rf "/tmp/ghostconsole-welcome-ghost-${boot_id}"
  cat > "${page_path}" <<'EOF'
home/animation_frames/frame_001\":[\"one <span class=\\\"b\\\">blue</span>\",\"@$$$$\"],\"home/animation_frames/frame_002\":[\"two\"]
EOF

  output="$(
    TERM=xterm-ghostty \
    COLUMNS=30 \
    LINES=10 \
    GHOSTCONSOLE_WELCOME_GHOST_FORCE=1 \
    GHOSTCONSOLE_GHOSTTY_PAGE_URL="file://${page_path}" \
    GHOSTCONSOLE_BOOT_ID="${boot_id}" \
    bash --noprofile --norc -i -c 'source "$1"' _ "${REPO_ROOT}/.config/shell/welcome-ghost.sh" 2>/dev/null
  )"

  assert_contains '@$$$$' "${output}" "welcome ghost should print the Ghostty-style mascot in interactive Ghostty shell"
  assert_contains 'blue' "${output}" "welcome ghost should strip homepage color spans from fetched frames"
  assert_contains $'\033[0;34mblue\033[0;37m' "${output}" "welcome ghost should preserve homepage blue accent spans"
  assert_contains 'two' "${output}" "welcome ghost should play all fetched frames"
  assert_contains $'\033[?1049h' "${output}" "welcome ghost should use the alternate screen while animating"
  assert_contains $'\033[?1049l' "${output}" "welcome ghost should leave the alternate screen after animating"
  assert_contains $'\033[?7l' "${output}" "welcome ghost should disable autowrap while animating to avoid resize wrapping"
  assert_contains $'\033[?7h' "${output}" "welcome ghost should restore autowrap after animating"
  assert_eq 2 "$(grep -o $'\033\\[?2026h' <<< "${output}" | wc -l | tr -d ' ')" "welcome ghost should begin synchronized output for each frame"
  assert_eq 2 "$(grep -o $'\033\\[?2026l' <<< "${output}" | wc -l | tr -d ' ')" "welcome ghost should end synchronized output for each frame"
  assert_contains $'\033[5;12H\033[0;37mone' "${output}" "welcome ghost should center frames in the terminal grid"
  assert_contains $'@$$$$\033[K' "${output}" "welcome ghost should erase stale cells at the end of each frame line"
  rm -rf "/tmp/ghostconsole-welcome-ghost-${boot_id}"
  pass
}

test_welcome_ghost_runs_once_per_boot_marker() {
  local first_output
  local second_output
  local page_path
  local boot_id

  page_path="$(mktemp)"
  boot_id="same-boot-${RANDOM}-${RANDOM}"
  printf 'home/animation_frames/frame_001\\":[\\"first-boot-frame\\"]' > "${page_path}"
  rm -rf "/tmp/ghostconsole-welcome-ghost-${boot_id}"

  first_output="$(
    TERM=xterm-ghostty \
    GHOSTCONSOLE_WELCOME_GHOST_FORCE=1 \
    GHOSTCONSOLE_GHOSTTY_PAGE_URL="file://${page_path}" \
    GHOSTCONSOLE_BOOT_ID="${boot_id}" \
    bash --noprofile --norc -i -c 'source "$1"' _ "${REPO_ROOT}/.config/shell/welcome-ghost.sh" 2>/dev/null
  )"
  second_output="$(
    TERM=xterm-ghostty \
    GHOSTCONSOLE_WELCOME_GHOST_FORCE=1 \
    GHOSTCONSOLE_GHOSTTY_PAGE_URL="file://${page_path}" \
    GHOSTCONSOLE_BOOT_ID="${boot_id}" \
    bash --noprofile --norc -i -c 'source "$1"' _ "${REPO_ROOT}/.config/shell/welcome-ghost.sh" 2>/dev/null
  )"

  assert_contains 'first-boot-frame' "${first_output}" "welcome ghost should play on first terminal for boot id"
  assert_eq "" "${second_output}" "welcome ghost should stay silent after boot marker exists"
  [[ -f "/tmp/ghostconsole-welcome-ghost-${boot_id}" ]] || fail "welcome ghost should create its boot marker file under /tmp"
  rm -rf "/tmp/ghostconsole-welcome-ghost-${boot_id}"
  pass
}

test_welcome_ghost_does_not_define_reset_alias() {
  local page_path
  local output

  page_path="$(mktemp)"
  printf 'home/animation_frames/frame_001\\":[\\"alias-check-frame\\"]' > "${page_path}"

  output="$(
    TERM=xterm-ghostty \
    GHOSTCONSOLE_WELCOME_GHOST_FORCE=1 \
    GHOSTCONSOLE_GHOSTTY_PAGE_URL="file://${page_path}" \
    GHOSTCONSOLE_BOOT_ID="alias-boot-${RANDOM}-${RANDOM}" \
    bash --noprofile --norc -i -c 'source "$1" >/dev/null 2>&1; alias reset-ghost-welcome >/dev/null 2>&1 && printf alias-present || printf alias-missing' _ "${REPO_ROOT}/.config/shell/welcome-ghost.sh" 2>/dev/null
  )"

  assert_eq "alias-missing" "${output}" "welcome ghost should not expose reset-ghost-welcome alias"
  pass
}

test_welcome_ghost_stays_silent_outside_ghostty() {
  local output

  output="$(TERM=xterm bash --noprofile --norc -i -c 'source "$1"' _ "${REPO_ROOT}/.config/shell/welcome-ghost.sh" 2>/dev/null)"

  assert_eq "" "${output}" "welcome ghost should not print outside Ghostty"
  pass
}

test_main_play_welcome_ghost_ignores_boot_marker() {
  local boot_id
  local output
  local page_path

  page_path="$(mktemp)"
  boot_id="manual-play-${RANDOM}-${RANDOM}"
  : > "/tmp/ghostconsole-welcome-ghost-${boot_id}"
  printf 'home/animation_frames/frame_001\\":[\\"manual-play-frame\\"]' > "${page_path}"

  output="$(
    TERM=xterm-ghostty \
    COLUMNS=30 \
    LINES=10 \
    GHOSTCONSOLE_WELCOME_GHOST_FORCE=1 \
    GHOSTCONSOLE_GHOSTTY_PAGE_URL="file://${page_path}" \
    GHOSTCONSOLE_BOOT_ID="${boot_id}" \
    bash -c 'source "$1"; main --play-welcome-ghost' _ "${REPO_ROOT}/bootstrap.sh" 2>/dev/null
  )"

  assert_contains "manual-play-frame" "${output}" "main --play-welcome-ghost should play even when boot marker exists"
  rm -rf "/tmp/ghostconsole-welcome-ghost-${boot_id}"
  pass
}

test_main_play_welcome_ghost_reports_playback_failure() {
  local output

  if output="$(
    TERM=xterm-ghostty \
    GHOSTCONSOLE_WELCOME_GHOST_FORCE=1 \
    GHOSTCONSOLE_GHOSTTY_PAGE_URL="file:///tmp/ghostconsole-missing-welcome-page-${RANDOM}" \
    bash -c 'source "$1"; main --play-welcome-ghost' _ "${REPO_ROOT}/bootstrap.sh" 2>&1
  )"; then
    fail "main --play-welcome-ghost should return non-zero when playback fails"
  fi

  assert_contains "welcome ghost playback failed" "${output}" "manual welcome ghost playback should explain renderer failure"
  pass
}

test_main_rejects_linux_non_ubuntu_before_install() {
  local output

  if output="$(bash -c '
    source "$1"
    macos_install() { printf SHOULD_NOT_EXEC_MACOS >&2; exit 99; }
    linux_ubuntu_install() { printf SHOULD_NOT_EXEC_U >&2; exit 98; }
    uname() { printf "%s\n" Linux; }
    .() {
      [[ "$1" == /etc/os-release ]] || return 1
      ID=debian
    }
    main --install
  ' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "non-Ubuntu Linux should not complete main"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "non-Ubuntu Linux should surface a script error"
  assert_contains 'Linux bootstrap supports only Ubuntu' "${output}" "non-Ubuntu Linux should explain supported distros"
  assert_not_contains "SHOULD_NOT_EXEC" "${output}" "install hooks should never run before distro check"
  pass
}

test_main_reads_linux_id_from_os_release() {
  local output

  if ! output="$(bash -c '
    source "$1"
    macos_install() { printf SHOULD_NOT_EXEC_MACOS >&2; exit 99; }
    linux_ubuntu_install() { printf UBUNTU_INSTALL; }
    apply_repo_config() { :; }
    verify_installation() { :; }
    verify_links() { :; }
    print_summary() { :; }
    uname() { printf "%s\n" Linux; }
    .() {
      [[ "$1" == /etc/os-release ]] || return 1
      ID=ubuntu
    }
    main --install
  ' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "Linux id should come from /etc/os-release: ${output}"
  fi

  assert_contains "UBUNTU_INSTALL" "${output}" "Ubuntu from os-release should select Ubuntu install"
  assert_not_contains "SHOULD_NOT_EXEC" "${output}" "macOS install hook should not run on Linux"
  pass
}

test_main_install_rejects_sudo_user_execution() {
  local workdir
  local trace_file
  local output

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"
  : > "${trace_file}"

  if output="$(TRACE_FILE="${trace_file}" bash -c '
    source "$1"
    export SUDO_USER="teammate"
    install_packages() { printf "SHOULD_NOT_INSTALL\n" >> "${TRACE_FILE}"; }
    install_powerlevel10k() { printf "SHOULD_NOT_INSTALL_P10K\n" >> "${TRACE_FILE}"; }
    install_zsh_autosuggestions() { printf "SHOULD_NOT_INSTALL_ZAS\n" >> "${TRACE_FILE}"; }
    apply_repo_config() { printf "SHOULD_NOT_APPLY\n" >> "${TRACE_FILE}"; }
    verify_installation() { printf "SHOULD_NOT_VERIFY_INSTALL\n" >> "${TRACE_FILE}"; }
    verify_links() { printf "SHOULD_NOT_VERIFY_LINKS\n" >> "${TRACE_FILE}"; }
    print_summary() { printf "SHOULD_NOT_SUMMARY\n" >> "${TRACE_FILE}"; }
    main --install
  ' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "main --install should fail when run with sudo"
  fi

  assert_contains "do not run bootstrap.sh with sudo or as root" "${output}" "sudo guard should explain why sudo is blocked"
  assert_contains "rerun without sudo" "${output}" "sudo guard should suggest rerunning without sudo"
  assert_eq '' "$(< "${trace_file}")" "sudo guard should stop install before any install hooks run"
  pass
}

test_main_install_rejects_root_execution() {
  local workdir
  local trace_file
  local output

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"
  : > "${trace_file}"

  if output="$(TRACE_FILE="${trace_file}" bash -c '
    source "$1"
    unset SUDO_USER
    id() {
      if [[ "$1" == "-u" ]]; then
        printf "0\n"
        return 0
      fi
      builtin command id "$@"
    }
    install_packages() { printf "SHOULD_NOT_INSTALL\n" >> "${TRACE_FILE}"; }
    install_powerlevel10k() { printf "SHOULD_NOT_INSTALL_P10K\n" >> "${TRACE_FILE}"; }
    install_zsh_autosuggestions() { printf "SHOULD_NOT_INSTALL_ZAS\n" >> "${TRACE_FILE}"; }
    apply_repo_config() { printf "SHOULD_NOT_APPLY\n" >> "${TRACE_FILE}"; }
    verify_installation() { printf "SHOULD_NOT_VERIFY_INSTALL\n" >> "${TRACE_FILE}"; }
    verify_links() { printf "SHOULD_NOT_VERIFY_LINKS\n" >> "${TRACE_FILE}"; }
    print_summary() { printf "SHOULD_NOT_SUMMARY\n" >> "${TRACE_FILE}"; }
    main --install
  ' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "main --install should fail when run as root"
  fi

  assert_contains "do not run bootstrap.sh with sudo or as root" "${output}" "root guard should explain why root is blocked"
  assert_eq '' "$(< "${trace_file}")" "root guard should stop install before any install hooks run"
  pass
}

test_macos_install_uses_runner_without_bash_env_side_effects() {
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
    macos_install() {
      run_install_command "printf first"
      run_install_command "printf -- \"|%s\" \"\$RUN_INSTALL_SENTINEL\""
    }
    command() {
      [[ "$1" == "-v" && "$2" == "brew" ]] && return 0
      builtin command "$@"
    }
    export RUN_INSTALL_SENTINEL="second"
    export BASH_ENV="$2"
    macos_install
  ' _ "${REPO_ROOT}/bootstrap.sh" "${bash_env_path}")"

  assert_eq "first|second" "${output}" "macos_install should execute commands through run_install_command in order"
  [[ ! -e "${marker_path}" ]] || fail "installer should not source BASH_ENV side effects during command runs"
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

test_sourcing_bootstrap_does_not_run_main() {
  local output

  output="$(bash -c 'source "$1"' _ "${REPO_ROOT}/bootstrap.sh")"

  assert_eq "" "${output}" "sourcing bootstrap.sh should not execute main"
  pass
}

test_sourcing_bootstrap_from_zsh_keeps_shell_alive() {
  local output

  output="$(zsh -f -i -c 'source "$1" >/dev/null; print ZSH_AFTER_SOURCE' _ "${REPO_ROOT}/bootstrap.sh" 2>/dev/null)"

  assert_contains "ZSH_AFTER_SOURCE" "${output}" "sourcing bootstrap.sh from zsh should not close the shell"
  pass
}

test_bootstrap_prefill_line_uses_source_invocation() {
  local output

  output="$(GHOSTCONSOLE_BOOTSTRAP_INVOCATION="../GhostConsole/bootstrap.sh" bootstrap_prefill_line)"

  assert_eq "../GhostConsole/bootstrap.sh --" "${output}" "prefill line should use the path from the source command"
  pass
}

test_interactive_sourcing_bootstrap_loads_bash_completion() {
  local workdir
  local output

  workdir="$(mktemp -d)"

  output="$(HOME="${workdir}" GHOSTCONSOLE_ROOT="${workdir}/repo" bash --noprofile --norc -i -c '
    source "$1"
    complete -p ./bootstrap.sh
    COMP_WORDS=(./bootstrap.sh --)
    COMP_CWORD=1
    _ghostconsole_bootstrap_complete
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "${REPO_ROOT}/bootstrap.sh" 2>/dev/null)"

  assert_not_contains "Usage: ./bootstrap.sh [option]" "${output}" "interactive source should not print help"
  assert_contains "complete -F _ghostconsole_bootstrap_complete ./bootstrap.sh" "${output}" "interactive source should register bash completion for ./bootstrap.sh"
  assert_contains "--install" "${output}" "interactive source should complete --install"
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
  local root
  local source_path
  local target_path

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  source_path="${root}/.config/ghostty"
  target_path="${workdir}/.config/ghostty"

  mkdir -p "${source_path}"
  HOME="${workdir}" GHOSTCONSOLE_ROOT="${root}" ensure_symlink ".config/ghostty"

  [[ -L "${target_path}" ]] || fail "target should be a symlink"
  assert_eq "${source_path}" "$(readlink "${target_path}")" "target should point to source"
  pass
}

test_ensure_symlink_rejects_existing_directory() {
  local workdir
  local root
  local source_path
  local target_path
  local output

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  source_path="${root}/.config/ghostty"
  target_path="${workdir}/.config/ghostty"

  mkdir -p "${source_path}" "${target_path}"

  if output="$(bash -c 'source "$1"; HOME="$2" GHOSTCONSOLE_ROOT="$3" ensure_symlink ".config/ghostty"' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}" "${root}" 2>&1)"; then
    fail "ensure_symlink should fail for an existing real directory"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "directory rejection should use script error handling"
  [[ -d "${target_path}" ]] || fail "existing directory should remain in place"
  [[ ! -L "${target_path}/ghostty" ]] || fail "ensure_symlink should not create a nested symlink"
  pass
}

test_ensure_symlink_rejects_existing_regular_file() {
  local workdir
  local root
  local source_path
  local target_path
  local output

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  source_path="${root}/.config/ghostty"
  target_path="${workdir}/.config/ghostty"

  mkdir -p "${source_path}"
  mkdir -p "$(dirname "${target_path}")"
  printf 'legacy-target\n' > "${target_path}"

  if output="$(bash -c 'source "$1"; HOME="$2" GHOSTCONSOLE_ROOT="$3" ensure_symlink ".config/ghostty"' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}" "${root}" 2>&1)"; then
    fail "ensure_symlink should fail for an existing regular file"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "file rejection should use script error handling"
  assert_eq 'legacy-target' "$(< "${target_path}")" "existing file should remain unchanged"
  pass
}

test_prepare_link_target_backs_up_existing_directory() {
  local workdir
  local root
  local target_path
  local backup_root

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  target_path="${workdir}/.config/ghostty"
  backup_root="${workdir}/backups"

  mkdir -p "${root}/.config/ghostty" "${target_path}"
  printf 'legacy\n' > "${target_path}/config"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${root}" GHOSTCONSOLE_BACKUP_ROOT="${backup_root}" GHOSTCONSOLE_TIMESTAMP="20260424-120000" prepare_link_target ".config/ghostty"

  [[ ! -d "${target_path}" ]] || fail "existing directory should be moved before linking"
  [[ -d "${backup_root}/ghostty-20260424-120000" ]] || fail "directory backup should be created"
  pass
}

test_prepare_link_target_backs_up_existing_wrong_symlink() {
  local workdir
  local root
  local source_path
  local wrong_source
  local target_path
  local backup_root
  local backup_path

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  source_path="${root}/.config/ghostty"
  wrong_source="${workdir}/legacy"
  target_path="${workdir}/.config/ghostty"
  backup_root="${workdir}/backups"
  backup_path="${backup_root}/ghostty-20260424-120000"

  mkdir -p "${source_path}" "${wrong_source}" "$(dirname "${target_path}")"
  ln -s "${wrong_source}" "${target_path}"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${root}" GHOSTCONSOLE_BACKUP_ROOT="${backup_root}" GHOSTCONSOLE_TIMESTAMP="20260424-120000" prepare_link_target ".config/ghostty"

  [[ ! -e "${target_path}" && ! -L "${target_path}" ]] || fail "wrong symlink should be moved out of the way"
  [[ -L "${backup_path}" ]] || fail "wrong symlink should be backed up as a symlink"
  assert_eq "${wrong_source}" "$(readlink "${backup_path}")" "backup should preserve the original symlink target"
  [[ -d "${wrong_source}" ]] || fail "backing up the symlink should not modify the old destination"
  pass
}

test_prepare_link_target_leaves_matching_symlink_untouched() {
  local workdir
  local root
  local source_path
  local target_path
  local backup_root

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  source_path="${root}/.config/ghostty"
  target_path="${workdir}/.config/ghostty"
  backup_root="${workdir}/backups"

  mkdir -p "${source_path}" "$(dirname "${target_path}")"
  ln -s "${source_path}" "${target_path}"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${root}" GHOSTCONSOLE_BACKUP_ROOT="${backup_root}" GHOSTCONSOLE_TIMESTAMP="20260424-120000" prepare_link_target ".config/ghostty"

  [[ -L "${target_path}" ]] || fail "matching symlink should remain in place"
  assert_eq "${source_path}" "$(readlink "${target_path}")" "matching symlink should stay unchanged"
  [[ ! -e "${backup_root}" ]] || fail "matching symlink should not create a backup"
  pass
}

test_write_zsh_loader_sources_repo_config() {
  local workdir
  local root
  local target_path

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  target_path="${workdir}/.zshrc"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${root}" write_zsh_loader

  assert_eq 'source "'"${root}"'/.config/zsh/.zshrc"' "$(< "${target_path}")" "zsh loader should source repo config"
  pass
}

test_write_zsh_loader_leaves_existing_symlink_without_touching_destination() {
  local workdir
  local root
  local destination_path
  local target_path

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  destination_path="${workdir}/outside-zshrc"
  target_path="${workdir}/.zshrc"

  printf 'legacy-destination\n' > "${destination_path}"
  ln -s "${destination_path}" "${target_path}"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${root}" write_zsh_loader

  [[ -L "${target_path}" ]] || fail "zsh loader should leave an existing symlink in place"
  assert_eq 'legacy-destination' "$(< "${destination_path}")" "zsh loader should not write through the symlink"
  assert_eq "${destination_path}" "$(readlink "${target_path}")" "zsh loader should not alter the symlink target"
  pass
}

test_write_zsh_loader_rejects_existing_directory_target() {
  local workdir
  local target_path
  local output

  workdir="$(mktemp -d)"
  target_path="${workdir}/.zshrc"

  mkdir -p "${target_path}"

  if output="$(bash -c 'source "$1"; HOME="$2"; GHOSTCONSOLE_ROOT="$3"; write_zsh_loader' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}" "${workdir}/repo" 2>&1)"; then
    fail "zsh loader should fail for an existing real directory"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "zsh loader directory rejection should use script error handling"
  [[ -d "${target_path}" ]] || fail "zsh loader should leave the existing directory in place"
  [[ ! -e "$(dirname "${target_path}")"/.ghostconsole-zsh.* ]] || fail "zsh loader should not leave a temp file behind"
  pass
}

test_write_zsh_loader_leaves_existing_regular_file_target() {
  local workdir
  local target_path

  workdir="$(mktemp -d)"
  target_path="${workdir}/.zshrc"

  printf 'legacy-file\n' > "${target_path}"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${workdir}/repo" write_zsh_loader

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

  if output="$(bash -c 'source "$1"; HOME="$2"; GHOSTCONSOLE_ROOT="$3"; write_zsh_loader' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}" "${workdir}/repo" 2>&1)"; then
    fail "zsh loader should fail for a symlink to a directory"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "zsh loader symlink-dir rejection should use script error handling"
  [[ -L "${target_path}" ]] || fail "zsh loader should leave the symlink in place"
  assert_eq "${linked_dir}" "$(readlink "${target_path}")" "zsh loader should not alter the symlink target"
  [[ ! -e "${linked_dir}"/.ghostconsole-zsh.* ]] || fail "zsh loader should not move temp files into the linked directory"
  pass
}

test_write_git_loader_includes_repo_config() {
  local workdir
  local root
  local target_path

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  target_path="${workdir}/.gitconfig"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${root}" write_git_loader

  assert_eq $'[include]\n    path = '"${root}"'/.config/git/config' "$(< "${target_path}")" "git loader should include repo config"
  pass
}

test_write_git_loader_leaves_existing_symlink_without_touching_destination() {
  local workdir
  local root
  local destination_path
  local target_path

  workdir="$(mktemp -d)"
  root="${workdir}/repo"
  destination_path="${workdir}/outside-gitconfig"
  target_path="${workdir}/.gitconfig"

  printf '[user]\n    email = legacy@example.com\n' > "${destination_path}"
  ln -s "${destination_path}" "${target_path}"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${root}" write_git_loader

  [[ -L "${target_path}" ]] || fail "git loader should leave an existing symlink in place"
  assert_eq $'[user]\n    email = legacy@example.com' "$(< "${destination_path}")" "git loader should not write through the symlink"
  assert_eq "${destination_path}" "$(readlink "${target_path}")" "git loader should not alter the symlink target"
  pass
}

test_write_git_loader_rejects_existing_directory_target() {
  local workdir
  local target_path
  local output

  workdir="$(mktemp -d)"
  target_path="${workdir}/.gitconfig"

  mkdir -p "${target_path}"

  if output="$(bash -c 'source "$1"; HOME="$2"; GHOSTCONSOLE_ROOT="$3"; write_git_loader' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}" "${workdir}/repo" 2>&1)"; then
    fail "git loader should fail for an existing real directory"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "git loader directory rejection should use script error handling"
  [[ -d "${target_path}" ]] || fail "git loader should leave the existing directory in place"
  [[ ! -e "$(dirname "${target_path}")"/.ghostconsole-git.* ]] || fail "git loader should not leave a temp file behind"
  pass
}

test_write_git_loader_leaves_existing_regular_file_target() {
  local workdir
  local target_path

  workdir="$(mktemp -d)"
  target_path="${workdir}/.gitconfig"

  printf '[user]\n    email = legacy@example.com\n' > "${target_path}"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${workdir}/repo" write_git_loader

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

  if output="$(bash -c 'source "$1"; HOME="$2"; GHOSTCONSOLE_ROOT="$3"; write_git_loader' _ "${REPO_ROOT}/bootstrap.sh" "${workdir}" "${workdir}/repo" 2>&1)"; then
    fail "git loader should fail for a symlink to a directory"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "git loader symlink-dir rejection should use script error handling"
  [[ -L "${target_path}" ]] || fail "git loader should leave the symlink in place"
  assert_eq "${linked_dir}" "$(readlink "${target_path}")" "git loader should not alter the symlink target"
  [[ ! -e "${linked_dir}"/.ghostconsole-git.* ]] || fail "git loader should not move temp files into the linked directory"
  pass
}

test_repo_root_matches_bootstrap_script_parent() {
  assert_eq "${REPO_ROOT}" "$(cd "$(dirname "${REPO_ROOT}/bootstrap.sh")" && pwd)" "REPO_ROOT should be the real path of the directory containing bootstrap.sh"
  pass
}

test_apply_repo_config_creates_dotconfig_and_backup_dirs() {
  local workdir

  workdir="$(mktemp -d)"
  ghostconsole_test_apply_repo_config_in_home "${workdir}"

  [[ -d "${workdir}/.config" ]] || fail "apply_repo_config should create ~/.config"
  [[ -d "${workdir}/.ghostconsole-backups" ]] || fail "apply_repo_config should create ~/.ghostconsole-backups"
  pass
}

test_apply_repo_config_symlinks_repo_config_under_dotconfig() {
  local workdir

  workdir="$(mktemp -d)"
  ghostconsole_test_apply_repo_config_in_home "${workdir}"

  [[ -L "${workdir}/.config/ghostty" ]] || fail "ghostty config should be symlinked"
  [[ -L "${workdir}/.config/zsh" ]] || fail "zsh config should be symlinked"
  [[ -L "${workdir}/.config/git" ]] || fail "git config should be symlinked"
  [[ -L "${workdir}/.config/shell" ]] || fail "shell config should be symlinked"
  assert_eq "${REPO_ROOT}/.config/ghostty" "$(readlink "${workdir}/.config/ghostty")" "ghostty config link should point to repo config"
  assert_eq "${REPO_ROOT}/.config/zsh" "$(readlink "${workdir}/.config/zsh")" "zsh config link should point to repo config"
  assert_eq "${REPO_ROOT}/.config/git" "$(readlink "${workdir}/.config/git")" "git config link should point to repo config"
  assert_eq "${REPO_ROOT}/.config/shell" "$(readlink "${workdir}/.config/shell")" "shell config link should point to repo config"
  pass
}

test_apply_repo_config_backs_up_conflicting_dotconfig_ghostty() {
  local workdir
  local backup_root

  workdir="$(mktemp -d)"
  backup_root="${workdir}/.ghostconsole-backups"
  mkdir -p "${workdir}/.config/ghostty"
  printf 'legacy\n' > "${workdir}/.config/ghostty/config"

  ghostconsole_test_apply_repo_config_in_home "${workdir}" "20260424-120000"

  [[ -d "${backup_root}/ghostty-20260424-120000" ]] || fail "conflicting ghostty config dir should move to backups before linking"
  [[ -L "${workdir}/.config/ghostty" ]] || fail "ghostty config path should become a symlink to the repo"
  pass
}

test_apply_repo_config_writes_home_loaders_with_backup() {
  local workdir
  local backup_root

  workdir="$(mktemp -d)"
  backup_root="${workdir}/.ghostconsole-backups"
  printf 'legacy zsh\n' > "${workdir}/.zshrc"
  printf 'legacy git\n' > "${workdir}/.gitconfig"

  ghostconsole_test_apply_repo_config_in_home "${workdir}" "20260424-120000"

  [[ -f "${backup_root}/zshrc-20260424-120000" ]] || fail "existing ~/.zshrc should land in backups"
  [[ -f "${backup_root}/gitconfig-20260424-120000" ]] || fail "existing ~/.gitconfig should land in backups"
  assert_eq 'source "'"${REPO_ROOT}"'/.config/zsh/.zshrc"' "$(< "${workdir}/.zshrc")" "bootstrap should replace ~/.zshrc with the repo loader line"
  assert_eq $'[include]\n    path = '"${REPO_ROOT}"'/.config/git/config' "$(< "${workdir}/.gitconfig")" "bootstrap should replace ~/.gitconfig with the managed include snippet"
  pass
}

test_apply_repo_config_accepts_existing_managed_home_loaders() {
  local workdir

  workdir="$(mktemp -d)"
  printf 'source "%s/.config/zsh/.zshrc"\n' "${REPO_ROOT}" > "${workdir}/.zshrc"
  printf '[include]\n    path = %s/.config/git/config\n' "${REPO_ROOT}" > "${workdir}/.gitconfig"

  ghostconsole_test_apply_repo_config_in_home "${workdir}" "20260424-120000"

  [[ ! -e "${workdir}/.ghostconsole-backups/zshrc-20260424-120000" ]] || fail "existing managed ~/.zshrc should not be backed up"
  [[ ! -e "${workdir}/.ghostconsole-backups/gitconfig-20260424-120000" ]] || fail "existing managed ~/.gitconfig should not be backed up"
  assert_eq 'source "'"${REPO_ROOT}"'/.config/zsh/.zshrc"' "$(< "${workdir}/.zshrc")" "managed ~/.zshrc should remain unchanged"
  assert_eq $'[include]\n    path = '"${REPO_ROOT}"'/.config/git/config' "$(< "${workdir}/.gitconfig")" "managed ~/.gitconfig should remain unchanged"
  pass
}

test_apply_repo_config_adds_bash_welcome_loader() {
  local workdir

  workdir="$(mktemp -d)"
  printf '# existing bashrc\n' > "${workdir}/.bashrc"

  ghostconsole_test_apply_repo_config_in_home "${workdir}" "20260424-120000"

  assert_contains '# >>> GhostConsole welcome ghost >>>' "$(< "${workdir}/.bashrc")" "bootstrap should add managed bash welcome block"
  assert_contains 'source "${HOME}/.config/shell/welcome-ghost.sh"' "$(< "${workdir}/.bashrc")" "bash welcome block should source home shell config"
  assert_contains '# existing bashrc' "$(< "${workdir}/.bashrc")" "bash welcome block should preserve existing bashrc contents"
  pass
}

test_apply_repo_config_keeps_bash_welcome_loader_idempotent() {
  local workdir
  local count

  workdir="$(mktemp -d)"

  ghostconsole_test_apply_repo_config_in_home "${workdir}" "20260424-120000"
  ghostconsole_test_apply_repo_config_in_home "${workdir}" "20260424-120001"

  count="$(python3 - <<'PY' "${workdir}/.bashrc"
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().count("# >>> GhostConsole welcome ghost >>>"))
PY
)"
  assert_eq "1" "${count}" "bash welcome block should not duplicate on rerun"
  pass
}

test_apply_repo_config_backs_up_zshrc_symlink_before_rewrite() {
  local workdir
  local backup_root
  local legacy_target

  workdir="$(mktemp -d)"
  backup_root="${workdir}/.ghostconsole-backups"
  legacy_target="${workdir}/legacy-zshrc"
  printf 'legacy target\n' > "${legacy_target}"
  ln -s "${legacy_target}" "${workdir}/.zshrc"

  ghostconsole_test_apply_repo_config_in_home "${workdir}" "20260424-120000"

  [[ -L "${backup_root}/zshrc-20260424-120000" ]] || fail "existing ~/.zshrc symlink should be backed up intact"
  legacy_link_target="$(python3 -c 'import os,sys; sys.stdout.write(os.readlink(sys.argv[1]))' "${backup_root}/zshrc-20260424-120000")" || fail "backup symlink target should be readable"

  assert_eq "${legacy_target}" "${legacy_link_target}" "backup should record the former ~/.zshrc symlink target"
  assert_eq 'legacy target' "$(< "${legacy_target}")" "replacement should leave the former symlink destination unchanged"
  pass
}

test_uninstall_config_removes_only_managed_links_and_loaders() {
  local workdir
  local backup_root

  workdir="$(mktemp -d)"
  backup_root="${workdir}/.ghostconsole-backups"
  mkdir -p "${workdir}/.config" "${backup_root}"
  ln -s "${REPO_ROOT}/.config/ghostty" "${workdir}/.config/ghostty"
  ln -s "${REPO_ROOT}/.config/zsh" "${workdir}/.config/zsh"
  ln -s "${REPO_ROOT}/.config/git" "${workdir}/.config/git"
  printf 'source "%s/.config/zsh/.zshrc"\n' "${REPO_ROOT}" > "${workdir}/.zshrc"
  printf '[include]\n    path = %s/.config/git/config\n' "${REPO_ROOT}" > "${workdir}/.gitconfig"
  printf '# >>> GhostConsole welcome ghost >>>\n[[ -r "%s/.config/shell/welcome-ghost.sh" ]] && source "%s/.config/shell/welcome-ghost.sh"\n# <<< GhostConsole welcome ghost <<<\n' "${REPO_ROOT}" "${REPO_ROOT}" > "${workdir}/.bashrc"
  printf 'legacy backup\n' > "${backup_root}/zshrc-20260424-120000"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${REPO_ROOT}" GHOSTCONSOLE_BACKUP_ROOT="${backup_root}" uninstall_config

  [[ ! -e "${workdir}/.config/ghostty" && ! -L "${workdir}/.config/ghostty" ]] || fail "managed ghostty symlink should be removed"
  [[ ! -e "${workdir}/.config/zsh" && ! -L "${workdir}/.config/zsh" ]] || fail "managed zsh symlink should be removed"
  [[ ! -e "${workdir}/.config/git" && ! -L "${workdir}/.config/git" ]] || fail "managed git symlink should be removed"
  [[ ! -e "${workdir}/.zshrc" ]] || fail "managed ~/.zshrc loader should be removed"
  [[ ! -e "${workdir}/.gitconfig" ]] || fail "managed ~/.gitconfig loader should be removed"
  assert_eq "" "$(< "${workdir}/.bashrc")" "managed bash welcome block should be removed"
  [[ -f "${backup_root}/zshrc-20260424-120000" ]] || fail "uninstall should leave backups untouched"
  pass
}

test_uninstall_config_leaves_unmanaged_paths() {
  local workdir
  local outside_path

  workdir="$(mktemp -d)"
  outside_path="${workdir}/outside"
  mkdir -p "${workdir}/.config" "${outside_path}/ghostty"
  ln -s "${outside_path}/ghostty" "${workdir}/.config/ghostty"
  printf 'custom zsh\n' > "${workdir}/.zshrc"
  printf 'custom git\n' > "${workdir}/.gitconfig"

  HOME="${workdir}" GHOSTCONSOLE_ROOT="${REPO_ROOT}" GHOSTCONSOLE_BACKUP_ROOT="${workdir}/.ghostconsole-backups" uninstall_config

  [[ -L "${workdir}/.config/ghostty" ]] || fail "unmanaged ghostty symlink should remain"
  assert_eq "${outside_path}/ghostty" "$(readlink "${workdir}/.config/ghostty")" "unmanaged symlink target should remain unchanged"
  assert_eq 'custom zsh' "$(< "${workdir}/.zshrc")" "unmanaged ~/.zshrc should remain"
  assert_eq 'custom git' "$(< "${workdir}/.gitconfig")" "unmanaged ~/.gitconfig should remain"
  pass
}

test_uninstall_packages_ubuntu_removes_only_ghostty() {
  local -a calls=()

  run_install_command() {
    calls+=("$1")
  }

  uninstall_packages

  assert_eq 'sudo apt-get remove -y ghostty' "${calls[0]}" "package uninstall should remove only Ghostty"
  [[ "${#calls[@]}" == 1 ]] || fail "package uninstall should not remove zsh or git"
  pass
}

test_verify_installation_rejects_missing_ghostty() {
  local output

  if output="$(bash -c '
    source "$1"
    command() {
      if [[ "$1" == "-v" && "$2" == "ghostty" ]]; then
        return 1
      fi
      return 0
    }
    verify_installation
  ' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "verify_installation should fail when ghostty is missing"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "verify_installation failure should use script error handling"
  assert_contains "ghostty not found after install" "${output}" "verify_installation should explain the missing binary"
  pass
}

test_verify_links_accepts_expected_repo_targets_and_home_entrypoints() {
  local workdir

  workdir="$(mktemp -d)"
  mkdir -p "${workdir}/.config"
  ln -s "${REPO_ROOT}/.config/ghostty" "${workdir}/.config/ghostty"
  ln -s "${REPO_ROOT}/.config/zsh" "${workdir}/.config/zsh"
  ln -s "${REPO_ROOT}/.config/git" "${workdir}/.config/git"
  printf 'source "%s/.config/zsh/.zshrc"\n' "${REPO_ROOT}" > "${workdir}/.zshrc"
  printf '[include]\n    path = %s/.config/git/config\n' "${REPO_ROOT}" > "${workdir}/.gitconfig"

  HOME="${workdir}" verify_links

  pass
}

test_verify_links_rejects_wrong_home_entrypoint_contents() {
  local workdir
  local output

  workdir="$(mktemp -d)"
  mkdir -p "${workdir}/.config"
  ln -s "${REPO_ROOT}/.config/ghostty" "${workdir}/.config/ghostty"
  ln -s "${REPO_ROOT}/.config/zsh" "${workdir}/.config/zsh"
  ln -s "${REPO_ROOT}/.config/git" "${workdir}/.config/git"
  printf 'source "/wrong/.config/zsh/.zshrc"\n' > "${workdir}/.zshrc"
  printf '[include]\n    path = %s/.config/git/config\n' "${REPO_ROOT}" > "${workdir}/.gitconfig"

  if output="$(HOME="${workdir}" bash -c 'source "$1"; verify_links' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "verify_links should fail when ~/.zshrc does not match the managed loader"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "wrong home entrypoint should use script error handling"
  assert_contains "~/.zshrc loader is incorrect" "${output}" "wrong home entrypoint should explain the failure"
  pass
}

test_print_summary_reports_installed_tools_and_linked_targets() {
  local output

  output="$(print_summary)"

  assert_contains "[GhostConsole-Installer] bootstrap complete" "${output}" "print_summary should report completion"
  assert_contains "[GhostConsole-Installer] installed: ghostty, zsh, git, ncdu, btop, lazygit, lazydocker, Powerlevel10k, zsh-autosuggestions" "${output}" "print_summary should list installed tools"
  assert_contains "[GhostConsole-Installer] linked: ~/.config/ghostty ~/.config/zsh ~/.config/shell ~/.config/git ~/.zshrc ~/.gitconfig" "${output}" "print_summary should list linked targets"
  pass
}

test_print_help_lists_supported_commands() {
  local output

  output="$(print_help)"

  assert_not_contains "source ./bootstrap.sh # To get tab completion for Usage." "${output}" "plain help should not include the source instruction"
  assert_contains "Usage: ./bootstrap.sh [option]" "${output}" "help should show usage"
  assert_contains "--install" "${output}" "help should list full install"
  assert_contains "-h, --help" "${output}" "help should list help flags"
  assert_not_contains "--completion-source" "${output}" "help should not expose internal completion source mode"
  assert_contains "--update-tui-tools" "${output}" "help should list TUI tool update"
  assert_not_contains "--tui-tools" "${output}" "help should not list old TUI-only install flag"
  assert_contains "--play-welcome-ghost" "${output}" "help should list manual welcome ghost playback"
  assert_contains "--cursor-cli" "${output}" "help should list Cursor CLI install"
  assert_contains "--uninstall" "${output}" "help should list uninstall"
  assert_contains "--uninstall --cursor-cli" "${output}" "help should list Cursor CLI uninstall"
  assert_contains "--uninstall --packages" "${output}" "help should list package uninstall"
  pass
}

test_print_completion_lists_supported_flags() {
  local output

  output="$(print_completion)"

  assert_contains "--install" "${output}" "completion should include full install"
  assert_contains "--update-tui-tools" "${output}" "completion should include TUI tool update"
  assert_not_contains "--tui-tools" "${output}" "completion should not include old TUI-only install flag"
  assert_contains "--play-welcome-ghost" "${output}" "completion should include manual welcome ghost playback"
  assert_contains "--cursor-cli" "${output}" "completion should include Cursor CLI"
  assert_contains "--uninstall" "${output}" "completion should include uninstall"
  assert_contains "--packages" "${output}" "completion should include package uninstall"
  pass
}

test_print_completion_source_sources_repo_completion_for_current_shell() {
  local output

  output="$(GHOSTCONSOLE_BOOTSTRAP_INVOCATION="../GhostConsole/bootstrap.sh" print_completion_source)"

  assert_contains 'if [ -n "${BASH_VERSION-}" ]; then' "${output}" "completion source should support bash"
  assert_contains 'complete -F _ghostconsole_bootstrap_complete ./bootstrap.sh bootstrap.sh' "${output}" "completion source should register bash completion"
  assert_contains '../GhostConsole/bootstrap.sh' "${output}" "completion source should register the sourced bootstrap path"
  assert_contains 'elif [ -n "${ZSH_VERSION-}" ]; then' "${output}" "completion source should support zsh"
  assert_contains 'fpath=("' "${output}" "completion source should update zsh fpath"
  assert_contains '/.config/shell/completions" ${fpath})' "${output}" "completion source should include shared shell completions path"
  assert_not_contains '/.config/zsh/completions" ${fpath})' "${output}" "completion source should not include old zsh-only completions path"
  assert_contains 'autoload -Uz compinit' "${output}" "completion source should load zsh compinit"
  assert_contains 'compinit' "${output}" "completion source should initialize zsh completion"
  assert_not_contains "[GhostConsole-Installer]" "${output}" "completion source should emit only shell code"
  pass
}

test_install_bootstrap_completion_writes_repo_shell_completion() {
  local workdir
  local completion_path
  local output

  workdir="$(mktemp -d)"
  GHOSTCONSOLE_ROOT="${workdir}/repo"
  completion_path="${GHOSTCONSOLE_ROOT}/.config/shell/completions/_bootstrap.sh"

  output="$(install_bootstrap_completion)"

  [[ -f "${completion_path}" ]] || fail "install_bootstrap_completion should write repo shell completion file"
  [[ ! -e "${GHOSTCONSOLE_ROOT}/.config/zsh/completions/_bootstrap.sh" ]] || fail "install_bootstrap_completion should not write old zsh-specific completion file"
  assert_contains "--install" "$(< "${completion_path}")" "installed completion should include --install"
  assert_contains "installed bootstrap completion" "${output}" "install_bootstrap_completion should report completion"
  assert_not_contains "${completion_path}" "${output}" "install_bootstrap_completion should not print the completion path"
  GHOSTCONSOLE_ROOT="${REPO_ROOT}"
  pass
}

test_main_install_orchestrates_install_link_verify_and_summary_in_order() {
  local workdir
  local trace_file

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"

  install_packages() {
    printf 'install:ubuntu\n' >> "${trace_file}"
  }
  install_powerlevel10k() { printf 'install-powerlevel10k\n' >> "${trace_file}"; }
  install_zsh_autosuggestions() { printf 'install-zsh-autosuggestions\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'apply-repo-config\n' >> "${trace_file}"; }
  verify_installation() { printf 'verify-install\n' >> "${trace_file}"; }
  verify_links() { printf 'verify-links\n' >> "${trace_file}"; }
  print_summary() { printf 'summary\n' >> "${trace_file}"; }

  main --install

  assert_eq $'install:ubuntu\ninstall-powerlevel10k\ninstall-zsh-autosuggestions\napply-repo-config\nverify-install\nverify-links\nsummary' "$(< "${trace_file}")" "main --install should install before applying repo layout and verify before summary"
  pass
}

test_main_without_flags_prints_help_without_installing_completion() {
  local workdir
  local trace_file
  local output

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"
  : > "${trace_file}"

  install_bootstrap_completion() { printf 'SHOULD_NOT_INSTALL_COMPLETION\n' >> "${trace_file}"; }
  install_packages() { printf 'SHOULD_NOT_INSTALL\n' >> "${trace_file}"; }
  install_tui_tools() { printf 'SHOULD_NOT_INSTALL_TUI\n' >> "${trace_file}"; }
  install_cursor_cli() { printf 'SHOULD_NOT_INSTALL_CURSOR_CLI\n' >> "${trace_file}"; }
  install_powerlevel10k() { printf 'SHOULD_NOT_INSTALL_P10K\n' >> "${trace_file}"; }
  uninstall_config() { printf 'SHOULD_NOT_UNINSTALL_CONFIG\n' >> "${trace_file}"; }
  uninstall_packages() { printf 'SHOULD_NOT_UNINSTALL_PACKAGES\n' >> "${trace_file}"; }
  uninstall_cursor_cli() { printf 'SHOULD_NOT_UNINSTALL_CURSOR_CLI\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'SHOULD_NOT_APPLY\n' >> "${trace_file}"; }
  verify_installation() { printf 'SHOULD_NOT_VERIFY_INSTALL\n' >> "${trace_file}"; }
  verify_links() { printf 'SHOULD_NOT_VERIFY_LINKS\n' >> "${trace_file}"; }
  print_summary() { printf 'SHOULD_NOT_SUMMARY\n' >> "${trace_file}"; }

  output="$(main)"

  assert_eq '' "$(< "${trace_file}")" "main without flags should not install completion"
  assert_contains "Usage: ./bootstrap.sh [option]" "${output}" "main without flags should print help"
  assert_contains 'source ./bootstrap.sh' "${output}" "main without flags should explain how to load completion into the current shell"
  pass
}

test_main_uninstall_removes_config_without_installing() {
  local workdir
  local trace_file

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"

  install_packages() { printf 'SHOULD_NOT_INSTALL\n' >> "${trace_file}"; }
  install_powerlevel10k() { printf 'SHOULD_NOT_INSTALL_P10K\n' >> "${trace_file}"; }
  uninstall_config() { printf 'uninstall-config\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'SHOULD_NOT_APPLY\n' >> "${trace_file}"; }
  verify_installation() { printf 'SHOULD_NOT_VERIFY_INSTALL\n' >> "${trace_file}"; }
  verify_links() { printf 'SHOULD_NOT_VERIFY_LINKS\n' >> "${trace_file}"; }
  print_summary() { printf 'SHOULD_NOT_SUMMARY\n' >> "${trace_file}"; }

  main --uninstall

  assert_eq 'uninstall-config' "$(< "${trace_file}")" "main --uninstall should only run uninstall_config"
  pass
}

test_main_uninstall_packages_removes_config_and_ghostty_only() {
  local workdir
  local trace_file

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"

  install_packages() { printf 'SHOULD_NOT_INSTALL\n' >> "${trace_file}"; }
  install_powerlevel10k() { printf 'SHOULD_NOT_INSTALL_P10K\n' >> "${trace_file}"; }
  uninstall_config() { printf 'uninstall-config\n' >> "${trace_file}"; }
  uninstall_packages() { printf 'uninstall-packages\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'SHOULD_NOT_APPLY\n' >> "${trace_file}"; }
  verify_installation() { printf 'SHOULD_NOT_VERIFY_INSTALL\n' >> "${trace_file}"; }
  verify_links() { printf 'SHOULD_NOT_VERIFY_LINKS\n' >> "${trace_file}"; }
  print_summary() { printf 'SHOULD_NOT_SUMMARY\n' >> "${trace_file}"; }

  main --uninstall --packages

  assert_eq $'uninstall-config\nuninstall-packages' "$(< "${trace_file}")" "main --uninstall --packages should remove config then packages"
  pass
}

test_main_uninstall_cursor_cli_removes_only_cursor_cli() {
  local workdir
  local trace_file

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"

  install_packages() { printf 'SHOULD_NOT_INSTALL\n' >> "${trace_file}"; }
  install_tui_tools() { printf 'SHOULD_NOT_INSTALL_TUI\n' >> "${trace_file}"; }
  install_cursor_cli() { printf 'SHOULD_NOT_INSTALL_CURSOR_CLI\n' >> "${trace_file}"; }
  install_powerlevel10k() { printf 'SHOULD_NOT_INSTALL_P10K\n' >> "${trace_file}"; }
  uninstall_config() { printf 'SHOULD_NOT_UNINSTALL_CONFIG\n' >> "${trace_file}"; }
  uninstall_packages() { printf 'SHOULD_NOT_UNINSTALL_PACKAGES\n' >> "${trace_file}"; }
  uninstall_cursor_cli() { printf 'uninstall-cursor-cli\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'SHOULD_NOT_APPLY\n' >> "${trace_file}"; }
  verify_installation() { printf 'SHOULD_NOT_VERIFY_INSTALL\n' >> "${trace_file}"; }
  verify_links() { printf 'SHOULD_NOT_VERIFY_LINKS\n' >> "${trace_file}"; }
  print_summary() { printf 'SHOULD_NOT_SUMMARY\n' >> "${trace_file}"; }

  main --uninstall --cursor-cli

  assert_eq 'uninstall-cursor-cli' "$(< "${trace_file}")" "main --uninstall --cursor-cli should only remove Cursor CLI"
  pass
}

test_main_update_tui_tools_updates_only_tui_tools() {
  local workdir
  local trace_file

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"

  install_packages() { printf 'SHOULD_NOT_INSTALL\n' >> "${trace_file}"; }
  install_tui_tools() { printf 'SHOULD_NOT_INSTALL_TUI\n' >> "${trace_file}"; }
  update_tui_tools() { printf 'update-tui-tools\n' >> "${trace_file}"; }
  install_powerlevel10k() { printf 'SHOULD_NOT_INSTALL_P10K\n' >> "${trace_file}"; }
  uninstall_config() { printf 'SHOULD_NOT_UNINSTALL_CONFIG\n' >> "${trace_file}"; }
  uninstall_packages() { printf 'SHOULD_NOT_UNINSTALL_PACKAGES\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'SHOULD_NOT_APPLY\n' >> "${trace_file}"; }
  verify_installation() { printf 'SHOULD_NOT_VERIFY_INSTALL\n' >> "${trace_file}"; }
  verify_links() { printf 'SHOULD_NOT_VERIFY_LINKS\n' >> "${trace_file}"; }
  print_summary() { printf 'SHOULD_NOT_SUMMARY\n' >> "${trace_file}"; }

  main --update-tui-tools

  assert_eq 'update-tui-tools' "$(< "${trace_file}")" "main --update-tui-tools should only update TUI tools"
  pass
}

test_main_cursor_cli_installs_only_cursor_cli() {
  local workdir
  local trace_file

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"

  install_packages() { printf 'SHOULD_NOT_INSTALL\n' >> "${trace_file}"; }
  install_tui_tools() { printf 'SHOULD_NOT_INSTALL_TUI\n' >> "${trace_file}"; }
  install_cursor_cli() { printf 'install-cursor-cli\n' >> "${trace_file}"; }
  install_powerlevel10k() { printf 'SHOULD_NOT_INSTALL_P10K\n' >> "${trace_file}"; }
  uninstall_config() { printf 'SHOULD_NOT_UNINSTALL_CONFIG\n' >> "${trace_file}"; }
  uninstall_packages() { printf 'SHOULD_NOT_UNINSTALL_PACKAGES\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'SHOULD_NOT_APPLY\n' >> "${trace_file}"; }
  verify_installation() { printf 'SHOULD_NOT_VERIFY_INSTALL\n' >> "${trace_file}"; }
  verify_links() { printf 'SHOULD_NOT_VERIFY_LINKS\n' >> "${trace_file}"; }
  print_summary() { printf 'SHOULD_NOT_SUMMARY\n' >> "${trace_file}"; }

  main --cursor-cli

  assert_eq 'install-cursor-cli' "$(< "${trace_file}")" "main --cursor-cli should only install Cursor CLI"
  pass
}

test_main_help_prints_help_without_installing() {
  local workdir
  local trace_file
  local output

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"
  : > "${trace_file}"

  install_packages() { printf 'SHOULD_NOT_INSTALL\n' >> "${trace_file}"; }
  install_tui_tools() { printf 'SHOULD_NOT_INSTALL_TUI\n' >> "${trace_file}"; }
  install_powerlevel10k() { printf 'SHOULD_NOT_INSTALL_P10K\n' >> "${trace_file}"; }
  uninstall_config() { printf 'SHOULD_NOT_UNINSTALL_CONFIG\n' >> "${trace_file}"; }
  uninstall_packages() { printf 'SHOULD_NOT_UNINSTALL_PACKAGES\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'SHOULD_NOT_APPLY\n' >> "${trace_file}"; }
  verify_installation() { printf 'SHOULD_NOT_VERIFY_INSTALL\n' >> "${trace_file}"; }
  verify_links() { printf 'SHOULD_NOT_VERIFY_LINKS\n' >> "${trace_file}"; }
  print_summary() { printf 'SHOULD_NOT_SUMMARY\n' >> "${trace_file}"; }

  output="$(main -h)"

  assert_contains "source ./bootstrap.sh # To get tab completion for Usage." "${output}" "main -h should explain how to install completion"
  assert_contains "Usage: ./bootstrap.sh [option]" "${output}" "main -h should print help"
  assert_eq '' "$(< "${trace_file}")" "main -h should not install, uninstall, apply, verify, or summarize"
  pass
}

test_main_help_highlights_source_instruction_when_color_forced() {
  local output

  output="$(GHOSTCONSOLE_COLOR=always main -h)"

  assert_contains $'\033[36msource ./bootstrap.sh\033[0m # To get tab completion for Usage.' "${output}" "main -h should highlight only the source command when color is forced"
  pass
}

test_main_rejects_unrecognized_flag_without_installing_or_completion() {
  local workdir
  local trace_file
  local output

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"
  : > "${trace_file}"

  install_packages() { printf 'SHOULD_NOT_INSTALL\n' >> "${trace_file}"; }
  install_bootstrap_completion() { printf 'SHOULD_NOT_INSTALL_COMPLETION\n' >> "${trace_file}"; }
  install_tui_tools() { printf 'SHOULD_NOT_INSTALL_TUI\n' >> "${trace_file}"; }
  install_powerlevel10k() { printf 'SHOULD_NOT_INSTALL_P10K\n' >> "${trace_file}"; }
  uninstall_config() { printf 'SHOULD_NOT_UNINSTALL_CONFIG\n' >> "${trace_file}"; }
  uninstall_packages() { printf 'SHOULD_NOT_UNINSTALL_PACKAGES\n' >> "${trace_file}"; }
  apply_repo_config() { printf 'SHOULD_NOT_APPLY\n' >> "${trace_file}"; }
  verify_installation() { printf 'SHOULD_NOT_VERIFY_INSTALL\n' >> "${trace_file}"; }
  verify_links() { printf 'SHOULD_NOT_VERIFY_LINKS\n' >> "${trace_file}"; }
  print_summary() { printf 'SHOULD_NOT_SUMMARY\n' >> "${trace_file}"; }

  if output="$(main --wat 2>&1)"; then
    fail "main should reject unrecognized flags"
  fi

  assert_contains "unrecognized option: --wat" "${output}" "main should explain unrecognized flag"
  assert_contains "Usage: ./bootstrap.sh [option]" "${output}" "main should print help after unrecognized flag"
  assert_eq '' "$(< "${trace_file}")" "main should not install, uninstall, apply, verify, summarize, or install completion after unrecognized flag"
  pass
}

test_main_does_not_print_summary_when_verification_fails() {
  local workdir
  local trace_file
  local output

  workdir="$(mktemp -d)"
  trace_file="${workdir}/trace.log"

  if output="$(TRACE_FILE="${trace_file}" bash -c '
    source "$1"
    install_packages() { printf "install\n" >> "${TRACE_FILE}"; }
    install_powerlevel10k() { printf "install-powerlevel10k\n" >> "${TRACE_FILE}"; }
    install_zsh_autosuggestions() { printf "install-zsh-autosuggestions\n" >> "${TRACE_FILE}"; }
    apply_repo_config() { printf "apply-repo-config\n" >> "${TRACE_FILE}"; }
    verify_installation() { printf "verify-install\n" >> "${TRACE_FILE}"; }
    verify_links() {
      printf "verify-links\n" >> "${TRACE_FILE}"
      printf "%s\n" "[GhostConsole-Installer] error: zsh config link is incorrect" >&2
      exit 1
    }
    print_summary() { printf "summary\n" >> "${TRACE_FILE}"; }
    main --install
  ' _ "${REPO_ROOT}/bootstrap.sh" 2>&1)"; then
    fail "main --install should fail when verification fails"
  fi

  assert_contains "[GhostConsole-Installer] error:" "${output}" "verification failure should use script error handling"
  assert_eq $'install\ninstall-powerlevel10k\ninstall-zsh-autosuggestions\napply-repo-config\nverify-install\nverify-links' "$(< "${trace_file}")" "main --install should stop before printing the summary when verification fails"
  pass
}

test_color_prefix_uses_ansi_when_forced
test_color_prefix_stays_plain_when_disabled
test_macos_install_invokes_ghostty_first
test_linux_ubuntu_install_uses_ghostty_ubuntu_install_script
test_linux_ubuntu_install_skips_ghostty_installer_when_present
test_linux_ubuntu_install_reports_ghostty_installer_failure
test_linux_ubuntu_install_falls_back_when_ghostty_installer_fails
test_install_ubuntu_github_release_tool_installs_missing_binary
test_install_ubuntu_github_release_tool_skips_existing_binary
test_install_ubuntu_github_release_tool_forces_existing_binary_when_requested
test_install_tui_tools_ubuntu_installs_only_tui_tools
test_update_tui_tools_ubuntu_updates_tui_tools
test_install_cursor_cli_runs_official_installer_when_missing
test_install_cursor_cli_updates_when_agent_exists
test_uninstall_cursor_cli_removes_local_agent_only
test_uninstall_cursor_cli_skips_when_local_agent_missing
test_install_powerlevel10k_clones_when_missing
test_install_powerlevel10k_updates_existing_checkout
test_install_powerlevel10k_backs_up_non_git_path_before_reinstall
test_install_powerlevel10k_reports_git_config_help_on_clone_failure
test_install_powerlevel10k_reports_git_config_help_on_update_failure
test_install_powerlevel10k_reports_permission_fix_on_update_failure
test_install_zsh_autosuggestions_clones_when_missing
test_install_zsh_autosuggestions_updates_existing_checkout
test_welcome_ghost_prints_only_in_interactive_ghostty_shell
test_welcome_ghost_runs_once_per_boot_marker
test_welcome_ghost_does_not_define_reset_alias
test_welcome_ghost_stays_silent_outside_ghostty
test_main_play_welcome_ghost_ignores_boot_marker
test_main_play_welcome_ghost_reports_playback_failure
test_main_rejects_linux_non_ubuntu_before_install
test_main_reads_linux_id_from_os_release
test_main_install_rejects_sudo_user_execution
test_main_install_rejects_root_execution
test_macos_install_uses_runner_without_bash_env_side_effects
test_run_install_command_ignores_exported_function_hijacking
test_sourcing_bootstrap_does_not_run_main
test_sourcing_bootstrap_from_zsh_keeps_shell_alive
test_bootstrap_prefill_line_uses_source_invocation
test_interactive_sourcing_bootstrap_loads_bash_completion
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
test_write_zsh_loader_leaves_existing_symlink_without_touching_destination
test_write_zsh_loader_rejects_existing_directory_target
test_write_zsh_loader_leaves_existing_regular_file_target
test_write_zsh_loader_rejects_symlink_to_directory_target
test_write_git_loader_includes_repo_config
test_write_git_loader_leaves_existing_symlink_without_touching_destination
test_write_git_loader_rejects_existing_directory_target
test_write_git_loader_leaves_existing_regular_file_target
test_write_git_loader_rejects_symlink_to_directory_target
test_repo_root_matches_bootstrap_script_parent
test_apply_repo_config_creates_dotconfig_and_backup_dirs
test_apply_repo_config_symlinks_repo_config_under_dotconfig
test_apply_repo_config_backs_up_conflicting_dotconfig_ghostty
test_apply_repo_config_writes_home_loaders_with_backup
test_apply_repo_config_accepts_existing_managed_home_loaders
test_apply_repo_config_adds_bash_welcome_loader
test_apply_repo_config_keeps_bash_welcome_loader_idempotent
test_apply_repo_config_backs_up_zshrc_symlink_before_rewrite
test_uninstall_config_removes_only_managed_links_and_loaders
test_uninstall_config_leaves_unmanaged_paths
test_uninstall_packages_ubuntu_removes_only_ghostty
test_verify_installation_rejects_missing_ghostty
test_verify_links_accepts_expected_repo_targets_and_home_entrypoints
test_verify_links_rejects_wrong_home_entrypoint_contents
test_print_summary_reports_installed_tools_and_linked_targets
test_print_help_lists_supported_commands
test_print_completion_lists_supported_flags
test_print_completion_source_sources_repo_completion_for_current_shell
test_install_bootstrap_completion_writes_repo_shell_completion
test_main_install_orchestrates_install_link_verify_and_summary_in_order
test_main_without_flags_prints_help_without_installing_completion
test_main_uninstall_removes_config_without_installing
test_main_uninstall_packages_removes_config_and_ghostty_only
test_main_uninstall_cursor_cli_removes_only_cursor_cli
test_main_update_tui_tools_updates_only_tui_tools
test_main_cursor_cli_installs_only_cursor_cli
test_main_help_prints_help_without_installing
test_main_help_highlights_source_instruction_when_color_forced
test_main_rejects_unrecognized_flag_without_installing_or_completion
test_main_does_not_print_summary_when_verification_fails

printf 'PASS: %s tests\n' "${PASS_COUNT}"
