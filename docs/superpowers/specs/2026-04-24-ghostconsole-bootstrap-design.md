# GhostConsole Bootstrap Design

**Date:** 2026-04-24

**Status:** Drafted from approved brainstorming

## Goal
Build the first working version of GhostConsole as a portable console bootstrap for macOS and Linux that installs `Ghostty`, `git`, and `zsh`, then links repo-managed configuration for those tools into the local machine.

## Scope
This first slice includes:

- a single `bootstrap.sh` entrypoint
- platform detection for macOS and Linux
- package installation for `Ghostty`, `git`, and `zsh`
- linking repo-managed config for `zsh`, `git`, and `Ghostty`
- safe backups for conflicting existing files or directories
- a clear summary of what the bootstrap changed

## Repository Layout
The repository should contain the following top-level structure:

```text
.
├── bootstrap.sh
├── bin/
├── .config/
│   ├── ghostty/
│   ├── zsh/
│   └── git/
└── README.md
```

### Responsibilities

- `bootstrap.sh`
  Detects platform, installs packages, creates backups, links config, and prints a final summary.

- `.config/ghostty/`
  Stores the repo-managed `Ghostty` configuration that should be used after bootstrap completes.

- `.config/zsh/`
  Stores the repo-managed `zsh` configuration that should be loaded from the user's shell startup files.

- `.config/git/`
  Stores the repo-managed git configuration that should be layered into the user's git setup.

- `bin/`
  Exists now as a placeholder for future scripts so the repo shape matches the project direction without inventing utilities early.

## Bootstrap Behavior
`bootstrap.sh` should run as a linear, idempotent setup script with visible logging.

Execution order:

1. Resolve the repository root from the location of `bootstrap.sh`.
2. Detect the operating system.
3. Select the install path:
   - macOS: Homebrew
   - Linux: `apt`
4. Install required packages:
   - `Ghostty`
   - `zsh`
   - `git`
5. Ensure required target directories exist.
6. Back up conflicting files or directories if they are not already the expected symlink.
7. Create symlinks for repo-managed configuration.
8. Print a final summary.

## Platform Support
### macOS
Use Homebrew to install all three required tools.

If `brew` is missing, the script should fail with a clear message explaining that Homebrew is required and must be installed first.

### Linux
Assume Debian or Ubuntu style systems and use `apt`.

For `zsh` and `git`, install directly via `apt`.

For `Ghostty`:

1. Try the system package source first.
2. If `Ghostty` is not available, fall back to an approved recommended repository-based install path.
3. If the fallback cannot be completed safely or automatically, fail with a clear explanation instead of silently skipping `Ghostty`.

The implementation should keep the Linux fallback logic explicit and easy to audit. It should not pretend Linux packaging is uniform when it is not.

## Config Linking Model
The bootstrap should link repo-owned config into the user's environment using these targets:

- `~/.config/ghostty` -> repo `.config/ghostty`
- `~/.config/zsh` -> repo `.config/zsh`
- `~/.config/git` -> repo `.config/git`

In addition, the bootstrap should manage thin user entrypoints where needed:

- `~/.zshrc`
  Should source the repo-managed zsh configuration rather than duplicating shell logic directly in the home directory.

- `~/.gitconfig`
  Should include the repo-managed git config rather than requiring the repo to own every personal git setting directly.

This design intentionally keeps app config directories fully owned by the repo while treating user-level shell and git entrypoints more cautiously.

## Conflict Handling And Backups
The script must not overwrite existing user files or directories blindly.

Rules:

- If the target does not exist, create the symlink directly.
- If the target already exists and is already the correct symlink, leave it alone.
- If the target exists but is not the expected symlink, move it into a timestamped backup location before linking the repo-managed version.

Backups should be stored under:

`~/.ghostconsole-backups/`

Suggested naming pattern:

- `~/.ghostconsole-backups/zshrc-<timestamp>`
- `~/.ghostconsole-backups/gitconfig-<timestamp>`
- `~/.ghostconsole-backups/ghostty-<timestamp>`

Every created backup path should be printed to the terminal output.

## Error Handling
The script should prioritize correctness and explicit failure over silent partial success.

Expected behavior:

- use strict shell mode such as `set -euo pipefail`
- log each major step before it runs
- verify required package tools exist before using them
- verify installed binaries exist after installation
- verify symlinks point to the expected repository locations after linking
- exit with a clear non-zero failure on unsupported platforms or missing prerequisites

The script should surface partial progress in its logs so users can understand what succeeded before a failure happened.

## Verification Strategy
Initial verification should stay lightweight and practical.

### Script-level checks
After installation, the bootstrap should verify:

- `command -v ghostty`
- `command -v zsh`
- `command -v git`

After linking, the bootstrap should verify the created symlinks point to the expected repo paths.

### Manual verification
The README should document a short manual verification flow:

1. Run `./bootstrap.sh`
2. Confirm `zsh --version`
3. Confirm `git --version`
4. Confirm `ghostty --version` or equivalent command
5. Inspect the linked config paths

### Testing posture
Do not introduce a heavy testing framework in the first slice unless the implementation complexity clearly justifies it. A small verification script is acceptable later, but the first milestone should focus on a trustworthy happy-path installer and documented manual checks.

## Non-Goals
This first milestone is not trying to solve every bootstrap case.

It does not attempt to:

- support every Linux distribution
- support multiple package managers on Linux
- expose a polished bootstrap CLI
- migrate arbitrary existing dotfile layouts into the repo
- manage personal secrets or machine-specific overrides beyond preserving existing user files via backups

## Design Rationale
This design chooses a narrow first milestone on purpose.

Why this shape:

- It matches the project's "start simple" philosophy.
- It creates a real end-to-end bootstrap flow instead of a repo skeleton with little behavior.
- It avoids over-designing optional package flags before the base path works.
- It treats user home-directory state conservatively by backing up conflicts instead of replacing them.
- It keeps the difference between repo-owned config and user-owned entrypoints explicit.

## Open Implementation Notes
These items are intentionally left for implementation planning, not for revisiting scope:

- the exact Linux repository fallback steps for `Ghostty`
- the exact file names inside `.config/zsh/`, `.config/git/`, and `.config/ghostty/`
- whether `bin/` uses `.gitkeep` or a first helper script

Those are implementation details within the approved design, not unresolved product questions.
