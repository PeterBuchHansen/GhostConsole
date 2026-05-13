## 1. Status

**Status:** Draft - Ready

No definition `TBD` blockers remain. In private-use mode, a `Beta` macOS template is an accepted unblocker.

## 2. Problem and goals (brief)

GhostConsole is moving from a simple bootstrap script to a small platform. Without tighter product and architecture guardrails, shell logic, scope boundaries, and UX consistency can drift.

Goals:
- keep GhostConsole practical on supported systems
- keep setup and replay predictable and testable
- preserve clean architecture as features evolve
- define measurable quality outcomes

## 3. Users / jobs-to-be-done (brief)

- **Primary user:** solo developer/power user managing one portable terminal setup.
- **Job 1:** install a consistent shell + terminal quickly and safely.
- **Job 2:** keep config versioned while protecting local state.
- **Job 3:** evolve tooling and UX without breaking bootstrap trust.

## 4. Scope and non-goals

### In scope
- single-entry bootstrap operations: install, targeted updates, uninstall, manual welcome replay
- managed config lifecycle: linking, backups, loader writing, idempotent reruns
- platform-aware package/install behavior for supported environments
- verification and regression testing to protect behavior during refactors
- PRD and planning discipline that supports clean code and sound decisions

### Out of scope
- universal Linux distro support beyond explicitly supported baseline
- migration tooling for every historical local dotfile layout
- replacing shell scripts with a heavier framework or daemonized service
- full plugin marketplace or remote state backend

## 5. Technical architecture and integration points

### Core modules
- **Bootstrap orchestrator:** routes CLI options and enforces operation flow (install/update/uninstall/playback/help).
- **Platform installers:** isolate platform and distro-specific package logic and fallback behavior.
- **Managed config engine:** handles conflict backup, symlink target preparation, loader creation, and safe idempotence.
- **Welcome animation runtime:** startup-safe, boot-aware replay logic with explicit manual playback path.
- **Verification layer:** validates installed binaries, managed links/loaders, and behavior contracts.
- **Test harness:** shell-based regression suite for orchestration, failure handling, and UX contract stability.

### Integration points
- macOS package manager toolchain
- Ubuntu package/install flows and fallback installers
- GitHub release downloads for selected tools
- Ghostty website frame source for animation playback
- local filesystem contract for home config, backups, and temporary boot markers

### Architectural principles
- keep modules deep (single-purpose interfaces, hidden operational detail)
- minimize cross-module coupling; orchestrator coordinates, modules execute
- fail loudly for explicit command actions, fail silently only where startup UX requires it
- preserve deterministic behavior under repeated runs

## 6. Functional requirements

1. The system shall provide explicit command modes for install, update-only, uninstall, help, and manual welcome playback.
2. Install flow shall execute in deterministic order: install dependencies/tools, apply managed config, verify, summarize.
3. Managed config shall back up conflicting state before replacement and keep backups collision-safe.
4. Managed links and loaders shall be idempotent across reruns.
5. Welcome animation auto-play shall be boot-aware and non-blocking for shell startup.
6. Manual welcome replay shall bypass boot marker gating and return non-zero on playback failure.
7. Completion/help output shall stay synchronized with supported flags.
8. Uninstall modes shall separate managed config removal from package removal.
9. Verification shall reject incomplete installs or incorrect managed link/loader targets.
10. Test suite shall enforce these contracts at module and orchestration levels.

## 7. Non-functional requirements

- **Reliability:** startup-critical flows must not degrade shell usability.
- **Safety:** no destructive overwrite of user state without backup.
- **Maintainability:** shell code remains modular, readable, and refactor-friendly.
- **Observability:** clear operator-facing logs for explicit commands.
- **Performance:** install/update command overhead remains acceptable for local bootstrap usage.
- **Portability discipline:** explicit support matrix and deterministic behavior on supported targets.
- **Security posture:** external download/install steps must be auditable and constrained.

## 8. Acceptance criteria (measurable)

### Project-level success metrics (approved)
1. `PRD.md` follows the required schema (11 sections) and stays at **<= 1300 words**.
2. `PRD.md` contains **0 TBD items** for `Draft - Ready` status, unless explicitly approved exceptions are named and justified.
3. `tests/bootstrap_test.sh` passes at **100%**, and Ubuntu install evidence is complete with zero manual file edits.
4. In private-use mode, an unfilled macOS template marked `Beta` is an accepted unblocker.

### Product and technical acceptance checks
- Install command succeeds end-to-end on Ubuntu; macOS may be `Beta`-deferred for private use.
- Managed links/loaders match expected targets after install and remain stable on rerun.
- Conflicting existing user state is preserved in backup storage with collision-safe naming.
- Manual welcome replay is available and reports failure correctly when playback cannot run.
- Startup path remains non-disruptive even when animation/network fetch fails.
- Help and completion output include all active command flags with no stale options.
- Uninstall mode removes only managed artifacts unless package uninstall is explicitly requested.

### Platform validation evidence protocol (agreed)
- Use the templates below to close platform evidence gates.
- A gate is closed only when every required field is filled with real command output.
- If a template is not filled yet, add `Beta` at the top; in private-use mode this can unblock readiness.

#### macOS evidence template
```markdown
- Beta: pending run on clean macOS host.
- Date:
- Host:
- OS:
- Run 1 `./bootstrap.sh --install`: pass/fail
- Versions:
  - `zsh --version`:
  - `git --version`:
  - `ghostty --version`:
- Links:
  - `readlink ~/.config/ghostty`:
  - `readlink ~/.config/zsh`:
  - `readlink ~/.config/shell`:
  - `readlink ~/.config/git`:
- Loaders:
  - `sed -n '1p' ~/.zshrc`:
  - `sed -n '1,2p' ~/.gitconfig`:
- Run 2 `./bootstrap.sh --install`: drift yes/no
- Attestation: zero manual file edits yes/no
```

#### Ubuntu evidence template
```markdown
- Date: 2026-05-13T14:19:49+02:00
- Host: ia-li-9vfrdk3.unirobotts.local
- OS: Ubuntu 24.04.4 LTS (Noble Numbat)
- Run 1 `./bootstrap.sh --install`: pass
- Versions:
  - `zsh --version`: zsh 5.9 (x86_64-ubuntu-linux-gnu)
  - `git --version`: git version 2.43.0
  - `ghostty --version`: Ghostty 1.3.1
- Links:
  - `readlink ~/.config/ghostty`: /home/mirpeha/repos/GhostConsole/.config/ghostty
  - `readlink ~/.config/zsh`: /home/mirpeha/repos/GhostConsole/.config/zsh
  - `readlink ~/.config/shell`: /home/mirpeha/repos/GhostConsole/.config/shell
  - `readlink ~/.config/git`: /home/mirpeha/repos/GhostConsole/.config/git
- Loaders:
  - `sed -n '1p' ~/.zshrc`: source "/home/mirpeha/repos/GhostConsole/.config/zsh/.zshrc"
  - `sed -n '1,2p' ~/.gitconfig`: [include] / path = /home/mirpeha/repos/GhostConsole/.config/git/config
- Run 2 `./bootstrap.sh --install`: drift no
- Attestation: zero manual file edits yes
- `/etc/os-release` ID: ubuntu
- `/etc/os-release` VERSION: 24.04.4 LTS (Noble Numbat)
- Ghostty install path used: already-installed (installer skipped)
```

## 9. Dependencies and constraints

### Dependencies
- shell runtime compatibility for bash execution and bash/zsh sourcing model
- platform package managers and network reachability for package/tool retrieval
- upstream release sources for selected tools
- Ghostty frame source availability for dynamic animation playback

### Constraints
- Linux support is constrained to the declared supported distro path.
- bootstrap behavior must remain understandable and script-native (no heavy framework pivot).
- config ownership model is repo-first with cautious home-loader injection.
- compatibility must prioritize safe failure semantics over silent partial success for explicit commands.

## 10. Risks and rollout plan

### Key risks
- external installer/source volatility can break package or tool retrieval
- growing command surface can increase branching complexity
- shell portability edge cases can regress behavior across environments
- startup UX features can accidentally leak failure noise into normal shell sessions

### Mitigations
- preserve test-driven guardrails around orchestration and mode behavior
- isolate external integration logic and keep fallback handling explicit
- keep startup-safe and explicit-command error policies separated
- gate command additions behind tests + documentation updates

### Rollout phases
1. **Stabilize core:** lock current contracts (install/link/verify/uninstall/playback) and keep tests green.
2. **Quality hardening:** refactor for deeper modules and cleaner boundaries without behavior drift.
3. **Controlled expansion:** add scoped capabilities only after acceptance checks and docs are updated.

## 11. Open questions and `TBD`s

No open `TBD` blockers. Platform validation is tracked as acceptance evidence work in section 8, not as unresolved requirements.

Future governance note (non-blocking, private-repo context):
- ADR governance is intentionally informal for now because this project is private-use. If collaboration scope grows, revisit this and define a lightweight documented decision process.
