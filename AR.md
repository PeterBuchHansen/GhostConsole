## 1. Status

**Status:** Draft - Ready

This architecture spec is ready for implementation planning. No open architecture-definition `TBD` items remain.

## 2. Architecture goals and constraints

### Goals
- keep `bootstrap.sh` as the single user-facing entrypoint
- improve architecture quality without changing the public CLI contract
- reduce coupling while preserving shell-script simplicity
- keep refactors behavior-preserving and test-guarded
- use agents to accelerate architecture uplift analysis

### Constraints
- single-file approach is intentionally retained (`bootstrap.sh`)
- architecture style is layered procedural (not object framework, not multi-binary split)
- major mode behavior must remain stable (`--install`, `--update-tui-tools`, `--play-welcome-ghost`, `--cursor-cli`, `--uninstall`)
- project is private-use, so governance can stay lightweight

## 3. Current system map (modules, boundaries, dependencies)

Current implementation centers on `bootstrap.sh` with functional clusters:
- logging and shell environment helpers (`use_color`, `log_*`)
- install engines (platform dispatch, Ubuntu/macOS installers, GitHub release installs)
- config lifecycle (backup, link prep, symlink/loaders, apply/remove managed config)
- verification (`verify_installation`, `verify_links`)
- interaction UX (help, completions, prefill behavior)
- mode orchestration (`main`, `run_full_install`, uninstall/update branches)

Primary dependencies:
- package managers and system tools (`apt`, `brew`, `git`, `curl`, `gpg`)
- external installer/release sources
- local home-directory filesystem for managed links/loaders/backups
- shell startup files and completion paths

Test architecture:
- one large shell regression suite (`tests/bootstrap_test.sh`) currently protecting broad behavior contracts.

## 4. Design pattern inventory (used, misused, missing)

### Used patterns
- **Layered procedural flow:** orchestration + operational functions + utility helpers.
- **Strategy-like platform branching:** kernel/distro routing to install strategy.
- **Adapter wrappers for external commands:** command execution funneled via helper functions.
- **Fail-fast verification gates:** explicit validation before successful completion.

### Misused or fragile patterns
- **God-script risk:** single file can drift into uncontrolled cross-calling and implicit coupling.
- **Boundary ambiguity:** section ownership exists by naming intent, not by enforced call contract.
- **Mixed abstraction levels:** orchestration concerns and low-level command details coexist tightly.

### Missing patterns
- explicit boundary contract for section-to-section calls
- architecture drift checks beyond test pass/fail
- standardized decision matrix output when multiple analysis tracks disagree

## 5. Architecture hotspots and failure modes

- external source volatility breaks install/update paths
- config loader rewrites can accidentally alter user shell behavior
- single-file growth increases hidden coupling across concern boundaries
- welcome/completion UX logic can leak side effects into startup behavior
- behavior regressions can slip in when refactor intent is architectural but CLI output drifts

## 6. Decision options and tradeoffs

### Boundary model options
- **A (selected):** keep single `bootstrap.sh`
  - pros: simple UX, low operational overhead, easy invocation model
  - cons: higher coupling risk without strict boundaries
- **B (rejected):** split into multiple scripts
  - pros: cleaner physical module boundaries
  - cons: higher complexity for a private-use shell toolchain

### Guardrail options
- **B (selected):** strict in-file section contracts and bounded call flow
  - `main` remains top-level router for mode entry
  - cross-section calls are limited by contract, not ad hoc convenience

### Migration policy
- **B (selected):** behavior-preserving refactor only
  - no CLI/output contract drift unless explicitly approved

### Pattern policy
- **B (selected):** layered procedural architecture

### Conflict resolution policy
- **B (selected):** user is final decision-maker; agent must provide tradeoff matrix + recommendation

## 7. Target architecture and boundary contracts

Target in-file layers:
1. **Orchestration layer:** `main` + mode routing only.
2. **Domain sections:** install, config lifecycle, verification, UX/welcome.
3. **Utility primitives:** logging, command execution, low-level helpers.

Boundary contracts:
- only orchestration layer invokes mode entrypoints
- domain sections should not directly call unrelated domain sections
- shared utility primitives may be called by any section
- each section must expose explicit section entry functions and keep internal helpers private-by-convention
- any boundary exception requires explicit approval and documentation in AR/PRD updates

## 8. Agent-assisted uplift plan

Default analysis model: 5 parallel tracks.

1. **Control-flow track**
   - map `main` routing, mode entrypoints, and cross-section call graph
   - output: boundary violation list + refactor targets
2. **Install architecture track**
   - evaluate platform strategy branches and external-source coupling
   - output: install-layer contracts and failure isolation rules
3. **Config lifecycle track**
   - analyze backup/link/loader idempotence and state-safety boundaries
   - output: state transition model and invariants
4. **Verification/test track**
   - map test coverage to architecture contracts
   - output: contract-to-test matrix and test gap list
5. **UX/startup track**
   - review completion and welcome-ghost behaviors for side-effect safety
   - output: startup-safe interaction contract

Synthesis rule:
- combine all track outputs into one target architecture proposal
- when tracks conflict, produce tradeoff table and escalate final choice to user

## 9. Acceptance criteria (measurable)

- `AR.md` uses the required 11-section structure and stays <= 1200 words.
- total architecture-definition `TBD` count is 0 for `Draft - Ready`.
- 0 unauthorized cross-section calls under the section contract.
- all mode entrypoints are routed through orchestration (`main`) contract.
- test suite passes at 100% after architecture changes.
- no unapproved CLI/output contract drift during refactor scope.
- uplift plan deliverables are produced for all five analysis tracks.

## 10. Risks and migration sequence

### Risks
- enforcing boundaries too aggressively can create refactor churn
- preserving behavior may constrain desirable cleanup in early steps
- parallel analysis can produce contradictory recommendations

### Migration sequence
1. baseline mapping: generate current call graph and section ownership map
2. contract codification: annotate section boundaries and allowed call paths
3. low-risk refactor pass: remove obvious boundary violations without behavior change
4. verification pass: run tests and compare CLI/output behavior against baseline
5. synthesis checkpoint: resolve open tradeoffs with user decisions
6. finalize architecture uplift with updated documentation

## 11. Open questions and `TBD`s

No open architecture-definition `TBD` items.
