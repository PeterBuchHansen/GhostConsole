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

The first milestone flow is:
- detect whether you are on macOS or **Ubuntu** Linux
- install `Ghostty` first, then `zsh` and `git`
- create managed config and backup directories in your home folder
- link the repo-owned config in `.config/ghostty`, `.config/zsh`, `.config/shell`, and `.config/git`
- write thin home entrypoints at `~/.zshrc` and `~/.gitconfig`
- verify the installed tools and linked config paths before printing a summary

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
readlink ~/.config/shell
readlink ~/.config/git
\`\`\`

You should also see managed home entrypoints:

\`\`\`bash
sed -n '1p' ~/.zshrc
sed -n '1,2p' ~/.gitconfig
\`\`\`

---

## 🧱 What’s included (for now)

### ⚙️ Bootstrap
Basic setup scripts for:
- macOS (Homebrew)
- **Ubuntu** (apt — other Linux distributions are not supported yet)

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
- shared shell startup scripts and completions
- **git**

All configs are symlinked into place.

---

## 📁 Structure

\`\`\`
.
├── bootstrap.sh
├── .config/
│   ├── ghostty/
│   ├── zsh/
│   ├── shell/
│   └── git/
├── docs/
│   └── superpowers/
│       ├── plans/
│       └── specs/
└── README.md
\`\`\`

---

## 🔒 Local state

This milestone backs up conflicting files before replacing them, but it does not implement a separate local-override loading mechanism yet.

Machine-specific changes need to be managed manually outside the repo for now.

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
- Works best on macOS and **Ubuntu** Linux
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
