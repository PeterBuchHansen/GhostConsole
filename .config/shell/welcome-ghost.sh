# GhostConsole welcome ghost. This file is sourced by bash and zsh.

ghostconsole_play() {
  command -v python3 >/dev/null 2>&1 || return 1

  GHOSTCONSOLE_GHOSTTY_PAGE_URL="${GHOSTCONSOLE_GHOSTTY_PAGE_URL:-https://ghostty.org/}" \
  GHOSTCONSOLE_WELCOME_GHOST_FRAME_DELAY="${GHOSTCONSOLE_WELCOME_GHOST_FRAME_DELAY:-0.03}" \
  python3 - <<'PY'
import html
import json
import os
import re
import shutil
import sys
import time
import urllib.request

url = os.environ["GHOSTCONSOLE_GHOSTTY_PAGE_URL"]
delay = float(os.environ["GHOSTCONSOLE_WELCOME_GHOST_FRAME_DELAY"])
page = urllib.request.urlopen(url, timeout=5).read().decode("utf-8", errors="replace")
pattern = re.compile(
    r"home/animation_frames/(frame_\d+)\\\":\[(.*?)\](?=,\\\"home/animation_frames/|[}\]]|$)",
    re.S,
)
frames = []

for name, body in sorted(pattern.findall(page)):
    source = "[" + body.replace(r"\"", '"').replace(r"\\", "\\") + "]"
    lines = json.loads(source)
    cleaned = []
    for line in lines:
        line = line.replace(r"\u003c", "<").replace(r"\u003e", ">").replace(r"\u0026", "&")
        line = html.unescape(line)
        line = re.sub(r'<span class=\\?"b\\?">', "\033[0;34m", line)
        line = line.replace("</span>", "\033[0;37m")
        line = re.sub(r"</?span[^>]*>", "", line)
        cleaned.append(line.rstrip())
    frames.append(cleaned)

if not frames:
    raise SystemExit(1)

ansi_pattern = re.compile(r"\033\[[0-9;?]*[A-Za-z]")
terminal_size = shutil.get_terminal_size(fallback=(120, 45))
frame_width = max(
    (len(ansi_pattern.sub("", line)) for frame in frames for line in frame),
    default=0,
)
frame_height = max((len(frame) for frame in frames), default=0)
frame_left = max(1, ((terminal_size.columns - frame_width) // 2) + 1)
frame_top = max(1, ((terminal_size.lines - frame_height) // 2) + 1)

def render_frame(frame):
    sys.stdout.write("\033[?2026h\033[H\033[J")
    try:
        for row, line in enumerate(frame, start=1):
            sys.stdout.write(f"\033[{frame_top + row - 1};{frame_left}H\033[0;37m{line}\033[K")
        sys.stdout.write(f"\033[{frame_top + len(frame)};1H\033[J\033[0m")
    finally:
        sys.stdout.write("\033[?2026l")
        sys.stdout.flush()


sys.stdout.write("\033[?1049h\033[?25l")
try:
    for frame in frames:
        render_frame(frame)
        if delay > 0:
            time.sleep(delay)
finally:
    sys.stdout.write("\033[?25h\033[?1049l")
    sys.stdout.flush()
PY
}

ghostconsole_startup() {
  local boot_id
  local marker_file

  case "$-" in
    *i*) ;;
    *) return 0 ;;
  esac

  case "${TERM_PROGRAM-}:${TERM-}:${GHOSTTY_RESOURCES_DIR-}:${GHOSTTY_BIN_DIR-}" in
    *ghostty*|*:xterm-ghostty:*|*:*:*ghostty*|*:*:*:*ghostty*) ;;
    *) return 0 ;;
  esac

  if [[ "${GHOSTCONSOLE_WELCOME_GHOST_FORCE-}" != 1 ]] && { [[ ! -t 1 ]] || [[ "${TERM-}" == dumb ]]; }; then
    return 0
  fi

  if [[ -n "${GHOSTCONSOLE_BOOT_ID-}" ]]; then
    boot_id="${GHOSTCONSOLE_BOOT_ID}"
  elif [[ -r "${GHOSTCONSOLE_BOOT_ID_PATH:-/proc/sys/kernel/random/boot_id}" ]]; then
    boot_id="$(sed 's/[^[:alnum:]_-]//g; q' "${GHOSTCONSOLE_BOOT_ID_PATH:-/proc/sys/kernel/random/boot_id}")"
  else
    return 0
  fi

  marker_file="/tmp/ghostconsole-welcome-ghost-${boot_id}"
  ( set -C; : > "${marker_file}" ) 2>/dev/null || return 0
  ghostconsole_play 2>/dev/null || return 0
}

if [[ "${GHOSTCONSOLE_WELCOME_GHOST_AUTO-1}" != 0 ]]; then
  ghostconsole_startup
fi
