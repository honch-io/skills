#!/bin/sh
set -eu

# honch.dev/skill — installs the `honch-integrator` agent skill for one or more
# coding agents (Claude Code, Codex, Cursor, Gemini CLI, Copilot).
#
# Zero dependencies beyond a POSIX shell + curl/wget + tar. No Node required.
# The interactive picker is a pure-shell arrow-key selector (no fzf/dialog).
#
# Usage:
#   curl -fsSL https://honch.dev/skill | sh
#   curl -fsSL https://honch.dev/skill | sh -s -- --all --project
#   curl -fsSL https://honch.dev/skill | sh -s -- --agent claude,codex
#
# Flags:
#   --agent a,b   install for these agents (claude,codex,cursor,gemini,copilot)
#   --all         install for every supported agent
#   --global      install into your home dir
#   --project     install into the current repository
#   --ref REF     git ref/tag of honch-io/skills to fetch (default: v0.3.0)
#   --src DIR     install from a local checkout instead of downloading (testing)
#   --help        show this help
#
# Env: HONCH_SKILL_REF, HONCH_SKILL_SRC, NO_COLOR, HONCH_FORCE_COLOR

SKILL_NAME="honch-integrator"
REPO="honch-io/skills"
REF="${HONCH_SKILL_REF:-v0.3.0}"
SRC="${HONCH_SKILL_SRC:-}"
SCOPE=""
AGENTS_ARG=""
ALL=0

# ---------------------------------------------------------------- presentation
if [ -z "${NO_COLOR:-}" ] && { [ "${HONCH_FORCE_COLOR:-}" = "1" ] || [ -t 1 ]; }; then
  orange="$(printf '\033[38;5;208m')"; green="$(printf '\033[32m')"
  red="$(printf '\033[31m')"; dim="$(printf '\033[2m')"
  bold="$(printf '\033[1m')"; reset="$(printf '\033[0m')"
else
  orange=""; green=""; red=""; dim=""; bold=""; reset=""
fi
brand() { printf '\n  %s%shonch%s %s·  skill installer%s\n\n' "$bold" "$orange" "$reset" "$dim" "$reset"; }
ok()    { printf '  %s✓%s %s\n' "$green" "$reset" "$1"; }
fail()  { printf '  %s✗%s %s\n' "$red" "$reset" "$1" >&2; }
usage() { sed -n '3,30p' "$0" 2>/dev/null || true; exit 0; }

# ---------------------------------------------------------------- args
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENTS_ARG="${2:-}"; shift 2 ;;
    --agent=*) AGENTS_ARG="${1#*=}"; shift ;;
    --all) ALL=1; shift ;;
    --global) SCOPE="global"; shift ;;
    --project) SCOPE="project"; shift ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --ref=*) REF="${1#*=}"; shift ;;
    --src) SRC="${2:-}"; shift 2 ;;
    --src=*) SRC="${1#*=}"; shift ;;
    -h|--help) usage ;;
    *) fail "unknown option: $1"; exit 2 ;;
  esac
done

SUPPORTED="claude codex cursor gemini copilot"

agent_detected() {
  case "$1" in
    claude)  [ -d "$HOME/.claude" ] || [ -d ".claude" ] ;;
    codex)   [ -d "$HOME/.codex" ]  || [ -f "AGENTS.md" ] ;;
    cursor)  [ -d "$HOME/.cursor" ] || [ -d ".cursor" ] ;;
    gemini)  [ -d "$HOME/.gemini" ] || [ -f "GEMINI.md" ] ;;
    copilot) [ -d ".github" ] ;;
    *) return 1 ;;
  esac
}
agent_label() {
  case "$1" in
    claude) echo "Claude Code" ;; codex) echo "Codex" ;;
    cursor) echo "Cursor" ;; gemini) echo "Gemini CLI" ;; copilot) echo "Copilot" ;;
  esac
}

# ---------------------------------------------------------------- key reading
# Read one keypress from the terminal, echo a symbolic name.
read_byte() { dd if=/dev/tty bs=1 count=1 2>/dev/null | od -An -tu1 | tr -dc '0-9'; }
read_key() {
  b="$(read_byte)"
  [ -z "$b" ] && { echo eof; return; }
  if [ "$b" = 27 ]; then
    b2="$(read_byte)"
    if [ "$b2" = 91 ] || [ "$b2" = 79 ]; then
      case "$(read_byte)" in 65) echo up ;; 66) echo down ;; *) echo other ;; esac
    else echo esc; fi
    return
  fi
  case "$b" in
    32) echo space ;; 10|13) echo enter ;;
    97|65) echo all ;; 113|81) echo quit ;;
    106) echo down ;; 107) echo up ;;   # j / k
    *) echo other ;;
  esac
}

# Restore terminal on any exit.
TTY_SAVED=""
restore_tty() {
  [ -n "$TTY_SAVED" ] && stty "$TTY_SAVED" </dev/tty 2>/dev/null || true
  [ -t 1 ] && printf '\033[?25h'   # show cursor (only on a real terminal)
  TTY_SAVED=""
}

can_interact() { [ -t 1 ] && { true </dev/tty; } 2>/dev/null; }

# ---------------------------------------------------------------- multi-select
SELECTED=""
multiselect() {
  MS_KEYS="$SUPPORTED"; n=0
  i=0
  for k in $MS_KEYS; do
    if agent_detected "$k"; then eval "sel_$i=1"; else eval "sel_$i=0"; fi
    i=$((i+1)); n=$((n+1))
  done
  cur=0

  printf '  %sWhich agents should get %s%s?\n' "$bold" "$SKILL_NAME" "$reset"
  printf '  %s↑/↓ move   space toggle   a all   enter confirm%s\n\n' "$dim" "$reset"

  TTY_SAVED="$(stty -g </dev/tty)"
  stty -echo -icanon min 1 time 0 </dev/tty
  printf '\033[?25l'
  ms_draw
  while :; do
    case "$(read_key)" in
      up)    cur=$(( (cur - 1 + n) % n )) ;;
      down)  cur=$(( (cur + 1) % n )) ;;
      space) eval "v=\$sel_$cur"; [ "$v" = 1 ] && eval "sel_$cur=0" || eval "sel_$cur=1" ;;
      all)   i=0; for k in $MS_KEYS; do eval "sel_$i=1"; i=$((i+1)); done ;;
      enter) break ;;
      quit|eof) restore_tty; printf '\n  cancelled.\n'; exit 130 ;;
    esac
    printf '\033[%dA' "$n"
    ms_draw
  done
  restore_tty

  i=0
  for k in $MS_KEYS; do eval "v=\$sel_$i"; [ "$v" = 1 ] && SELECTED="$SELECTED $k"; i=$((i+1)); done
}
ms_draw() {
  i=0
  for k in $MS_KEYS; do
    eval "v=\$sel_$i"
    if [ "$i" = "$cur" ]; then ptr="${orange}❯${reset}"; lb="$bold"; else ptr=" "; lb=""; fi
    if [ "$v" = 1 ]; then box="${orange}◉${reset}"; else box="${dim}◯${reset}"; fi
    det=""; agent_detected "$k" && det="  ${dim}· detected${reset}"
    printf '\r   %s %s %s%-11s%s%s\033[K\n' "$ptr" "$box" "$lb" "$(agent_label "$k")" "$reset" "$det"
    i=$((i+1))
  done
}

# ---------------------------------------------------------------- scope select
scope_select() {
  SC_KEYS="global project"; cur=0; n=2
  printf '\n  %sInstall where?%s\n' "$bold" "$reset"
  printf '  %s↑/↓ move   enter confirm%s\n\n' "$dim" "$reset"
  TTY_SAVED="$(stty -g </dev/tty)"
  stty -echo -icanon min 1 time 0 </dev/tty
  printf '\033[?25l'
  sc_draw
  while :; do
    case "$(read_key)" in
      up)   cur=$(( (cur - 1 + n) % n )) ;;
      down) cur=$(( (cur + 1) % n )) ;;
      enter) break ;;
      quit|eof) restore_tty; printf '\n  cancelled.\n'; exit 130 ;;
    esac
    printf '\033[%dA' "$n"; sc_draw
  done
  restore_tty
  [ "$cur" = 1 ] && SCOPE="project" || SCOPE="global"
}
sc_draw() {
  i=0
  for k in $SC_KEYS; do
    if [ "$i" = "$cur" ]; then ptr="${orange}❯${reset}"; lb="$bold"; dot="${orange}●${reset}"; else ptr=" "; lb=""; dot="${dim}○${reset}"; fi
    case "$k" in
      global)  txt="global   ${dim}~/.claude, ~/.honch${reset}" ;;
      project) txt="project  ${dim}this repo${reset}" ;;
    esac
    printf '\r   %s %s %s%s%s\033[K\n' "$ptr" "$dot" "$lb" "$txt" "$reset"
    i=$((i+1))
  done
}

# ---------------------------------------------------------------- run
brand

# Resolve agent selection.
if [ -n "$AGENTS_ARG" ]; then
  SELECTED="$(echo "$AGENTS_ARG" | tr ',' ' ')"
elif [ "$ALL" -eq 1 ]; then
  SELECTED="$SUPPORTED"
elif can_interact; then
  multiselect
else
  for a in $SUPPORTED; do agent_detected "$a" && SELECTED="$SELECTED $a"; done
fi

SELECTED="$(echo "$SELECTED" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
if [ -z "$(echo "$SELECTED" | tr -d ' ')" ]; then
  fail "No agents selected and none detected."
  printf '  Re-run with e.g. %s--agent claude%s or %s--all%s.\n' "$bold" "$reset" "$bold" "$reset"
  exit 1
fi

# Resolve scope.
if [ -z "$SCOPE" ]; then
  if can_interact; then scope_select; else SCOPE="global"; fi
fi
if [ "$SCOPE" = "project" ]; then BASE="$(pwd)"; else BASE="$HOME"; fi

# ---------------------------------------------------------------- fetch source
TMP=""
cleanup() { restore_tty; [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

if [ -n "$SRC" ]; then
  SKILL_ROOT="$SRC/$SKILL_NAME"
  [ -d "$SKILL_ROOT" ] || SKILL_ROOT="$SRC"
else
  TMP="$(mktemp -d 2>/dev/null || mktemp -d -t honchskill)"
  printf '\n  %s⋯%s fetching %s@%s\n' "$dim" "$reset" "$REPO" "$REF"
  fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1" 2>/dev/null
    else fail "need curl or wget to download the skill"; exit 1; fi
  }
  got=0
  for ref in "refs/tags/$REF" "refs/heads/$REF" "refs/heads/main"; do
    if fetch "https://codeload.github.com/$REPO/tar.gz/$ref" "$TMP/skill.tgz"; then got=1; break; fi
  done
  [ "$got" -eq 1 ] || { fail "could not download $REPO (tried $REF and main)"; exit 1; }
  tar -xzf "$TMP/skill.tgz" -C "$TMP"
  SKILL_ROOT="$(find "$TMP" -maxdepth 2 -type d -name "$SKILL_NAME" | head -1)"
fi

if [ -z "${SKILL_ROOT:-}" ] || [ ! -d "$SKILL_ROOT/content" ]; then
  fail "could not locate the $SKILL_NAME skill (no content/ dir)"; exit 1
fi

# ---------------------------------------------------------------- install
copy_body() {
  mkdir -p "$1"; cp -R "$SKILL_ROOT/content" "$1/content"
  [ -f "$SKILL_ROOT/VERSION" ] && cp "$SKILL_ROOT/VERSION" "$1/VERSION"
  return 0
}

install_claude() {
  if [ "$SCOPE" = "project" ]; then dir="$BASE/.claude/skills/$SKILL_NAME"; else dir="$HOME/.claude/skills/$SKILL_NAME"; fi
  rm -rf "$dir"; copy_body "$dir"
  cp "$SKILL_ROOT/adapters/claude/SKILL.md" "$dir/SKILL.md"
  ok "Claude Code   $dim$dir$reset"
}

install_agents_family() {
  agent="$1"; disc="$2"
  body="$BASE/.honch/$SKILL_NAME"; rm -rf "$body"; copy_body "$body"
  cp "$SKILL_ROOT/adapters/AGENTS.md" "$body/AGENTS.md"
  discpath="$BASE/$disc"; mkdir -p "$(dirname "$discpath")"
  marker="<!-- honch-integrator -->"
  if [ ! -f "$discpath" ] || ! grep -q "$marker" "$discpath" 2>/dev/null; then
    {
      printf '\n%s\n## Honch integration\n\n' "$marker"
      printf 'To integrate Honch into this codebase, read and follow\n'
      printf '`.honch/%s/AGENTS.md` (and `.honch/%s/content/`). Targets Honch SDK 0.3.0.\n' "$SKILL_NAME" "$SKILL_NAME"
    } >> "$discpath"
  fi
  ok "$(agent_label "$agent")$(printf '%*s' $((14 - ${#agent})) '')$dim$discpath$reset"
}

install_cursor() {
  body="$BASE/.honch/$SKILL_NAME"; rm -rf "$body"; copy_body "$body"
  cp "$SKILL_ROOT/adapters/AGENTS.md" "$body/AGENTS.md"
  rules="$BASE/.cursor/rules"; mkdir -p "$rules"
  cp "$SKILL_ROOT/adapters/cursor/$SKILL_NAME.mdc" "$rules/$SKILL_NAME.mdc"
  ok "Cursor        $dim$rules/$SKILL_NAME.mdc$reset"
}

printf '\n'
for a in $SELECTED; do
  case "$a" in
    claude)  install_claude ;;
    codex)   install_agents_family codex   "AGENTS.md" ;;
    gemini)  install_agents_family gemini  "GEMINI.md" ;;
    copilot) install_agents_family copilot ".github/copilot-instructions.md" ;;
    cursor)  install_cursor ;;
    *) fail "unknown agent: $a (skipped)" ;;
  esac
done

printf '\n'
ok "Done — start a new agent session and ask it to \"integrate Honch\"."
exit 0
