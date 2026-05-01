# 👻 GhostConsole

**GhostConsole** is my portable, cross-platform console environment.

It provides a consistent terminal, shell, and core toolset across macOS and Linux — built around **Ghostty**, **zsh**, and a small collection of CLI utilities.

> *Your console, anywhere.*

---

## ✨ Goals

- Same developer experience on any machine
- Fast setup with minimal friction
- Simple, readable configuration
- Easy to extend with scripts and tools over time

---

## 🚀 Getting started

Clone the repo and run:

\`\`\`bash
./bootstrap.sh
\`\`\`

This first version will:
- detect your OS (macOS or Linux)
- install `Ghostty` first, then `zsh` and `git`
- link repo-managed configuration files
- write lightweight home entry files for shell and git
- back up conflicting existing files before replacing them

## ✅ Verify

After bootstrap completes:

\`\`\`bash
zsh --version
git --version
ghostty --version
\`\`\`

Confirm these paths now point at this repo:

\`\`\`bash
readlink ~/.config/ghostty
readlink ~/.config/zsh
readlink ~/.config/git
\`\`\`

---

## 🧱 What’s included (for now)

### ⚙️ Bootstrap
Basic setup scripts for:
- macOS (Homebrew)
- Linux (apt)

Installs these tools in the first milestone:
- `Ghostty`
- `zsh`
- `git`

Later milestones may add more CLI tools and optional packages.

---

### 🖥️ Configuration
Versioned config files for:
- **Ghostty** (terminal)
- **zsh** (shell)
- **git**

All configs are symlinked into place.

---

### 🧰 CLI tools (early stage)
A small set of personal scripts in:

\`\`\`
bin/
\`\`\`

These are simple utilities to support daily workflows.  
This area will grow over time.

---

## 📁 Structure

\`\`\`
.
├── bootstrap.sh
├── bin/
├── .config/
│   ├── ghostty/
│   ├── zsh/
│   └── git/
├── docs/
│   └── superpowers/
│       ├── plans/
│       └── specs/
└── README.md
\`\`\`

---

## 🔒 Local overrides

Machine-specific or sensitive config should not be committed.

Use local files like:
- `~/.zshrc.local`
- anything inside `private/`

These are ignored by git and loaded if present.

---

## 🔜 Roadmap

GhostConsole will expand gradually:

- More CLI utilities
- Simple TUI tools
- Better workflow commands (e.g. `gc <command>`)
- Optional project-based environments

---

## 🧠 Philosophy

- Start simple
- Prefer plain shell scripts over heavy frameworks
- Keep everything understandable
- Build tools when needed, not upfront

---

## 📌 Notes

- Optimized for personal use
- Works best on macOS and Debian/Ubuntu-based Linux
- Designed to evolve over time

---

## 🏁 Vision

GhostConsole is not just dotfiles.

It’s a growing **console toolkit** — a place for:
- configuration
- scripts
- tools
- experiments

All in one portable setup.
