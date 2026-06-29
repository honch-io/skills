#!/bin/sh
set -eu

# honch.dev/skill — installs the `honch-integrator` agent skill for one or more
# coding agents (Claude Code, Codex, Cursor, Gemini CLI, Copilot).
#
# Zero dependencies beyond a POSIX shell + curl/wget + tar. No Node required.
#
# Usage:
#   curl -fsSL https://honch.dev/skill | sh
#   curl -fsSL https://honch.dev/skill | sh -s -- --all --project
#   curl -fsSL https://honch.dev/skill | sh -s -- --agent claude,codex
#
# Flags:
#   --agent a,b   install for these agents (claude,codex,cursor,gemini,copilot)
#   --all         install for every supported agent
#   --global      install into your home dir (default for global-style agents)
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
SCOPE=""        # global | project (resolved later)
AGENTS_ARG=""   # explicit --agent / --all selection
ALL=0

# ---------------------------------------------------------------- presentation
if [ -z "${NO_COLOR:-}" ] && { [ "${HONCH_FORCE_COLOR:-}" = "1" ] || [ -t 1 ]; }; then
  orange="$(printf '\033[38;5;208m')"; green="$(printf '\033[32m')"
  red="$(printf '\033[31m')"; muted="$(printf '\033[2m')"
  bold="$(printf '\033[1m')"; reset="$(printf '\033[0m')"
else
  orange=""; green=""; red=""; muted=""; bold=""; reset=""
fi
banner()  { printf '\n%s%sHONCH%s\n%sskill installer%s\n\n' "$bold" "$orange" "$reset" "$muted" "$reset"; }
step()    { printf '%s›%s %s\n' "$orange" "$reset" "$1"; }
ok()      { printf '%s✓%s %s\n' "$green" "$reset" "$1"; }
fail()    { printf '%s✗%s %s\n' "$red" "$reset" "$1" >&2; }

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

banner

SUPPORTED="claude codex cursor gemini copilot"

# Is an agent's config present on this machine / repo? (drives pre-selection)
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
    claude)  echo "Claude Code" ;; codex) echo "Codex" ;;
    cursor)  echo "Cursor" ;; gemini) echo "Gemini CLI" ;;
    copilot) echo "Copilot" ;;
  esac
}

# ---------------------------------------------------------------- selection
SELECTED=""

if [ -n "$AGENTS_ARG" ]; then
  SELECTED="$(echo "$AGENTS_ARG" | tr ',' ' ')"
elif [ "$ALL" -eq 1 ]; then
  SELECTED="$SUPPORTED"
elif [ -t 0 ] || (exec </dev/tty) 2>/dev/null; then
  # Interactive selector.
  [ -t 0 ] || exec </dev/tty
  printf '  Install %s%s%s for which agents?\n\n' "$bold" "$SKILL_NAME" "$reset"
  i=0
  for a in $SUPPORTED; do
    i=$((i+1))
    mark=" "; note=""
    if agent_detected "$a"; then mark="x"; note="${muted}(detected)${reset}"; fi
    printf '   [%s] %d) %-12s %s\n' "$mark" "$i" "$(agent_label "$a")" "$note"
  done
  printf '       a) all\n\n'
  printf '  %s›%s numbers (e.g. "1 2"), "a" for all, enter for detected: ' "$orange" "$reset"
  read -r choice || choice=""
  if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
    SELECTED="$SUPPORTED"
  elif [ -z "$choice" ]; then
    for a in $SUPPORTED; do agent_detected "$a" && SELECTED="$SELECTED $a"; done
  else
    for n in $choice; do
      j=0
      for a in $SUPPORTED; do j=$((j+1)); [ "$j" = "$n" ] && SELECTED="$SELECTED $a"; done
    done
  fi
else
  # Non-interactive, no explicit selection: fall back to detected agents.
  for a in $SUPPORTED; do agent_detected "$a" && SELECTED="$SELECTED $a"; done
fi

SELECTED="$(echo "$SELECTED" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
if [ -z "$(echo "$SELECTED" | tr -d ' ')" ]; then
  fail "No agents selected and none detected."
  printf '  Re-run with e.g. %s--agent claude%s or %s--all%s.\n' "$bold" "$reset" "$bold" "$reset"
  exit 1
fi

# ---------------------------------------------------------------- scope
if [ -z "$SCOPE" ]; then
  if (exec </dev/tty) 2>/dev/null; then
    exec </dev/tty
    printf '\n  Scope?  1) global (~)   2) this project   %s›%s ' "$orange" "$reset"
    read -r s || s="1"
    case "$s" in 2) SCOPE="project" ;; *) SCOPE="global" ;; esac
  else
    SCOPE="global"
  fi
fi
if [ "$SCOPE" = "project" ]; then BASE="$(pwd)"; else BASE="$HOME"; fi

# ---------------------------------------------------------------- fetch source
TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

if [ -n "$SRC" ]; then
  SKILL_ROOT="$SRC/$SKILL_NAME"
  [ -d "$SKILL_ROOT" ] || SKILL_ROOT="$SRC"   # allow pointing straight at the skill dir
else
  TMP="$(mktemp -d 2>/dev/null || mktemp -d -t honchskill)"
  step "fetching $REPO@$REF"
  fetch() { # $1=url $2=out
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
  ok "Claude Code   → $dir"
}

# AGENTS.md-family: a self-contained body under .honch/ plus the agent's own
# discovery file pointing at it.
install_agents_family() {
  agent="$1"; disc="$2"   # disc = path (relative to BASE) of the discovery file
  body="$BASE/.honch/$SKILL_NAME"
  rm -rf "$body"; copy_body "$body"
  cp "$SKILL_ROOT/adapters/AGENTS.md" "$body/AGENTS.md"
  discpath="$BASE/$disc"; mkdir -p "$(dirname "$discpath")"
  marker="<!-- honch-integrator -->"
  if [ ! -f "$discpath" ] || ! grep -q "$marker" "$discpath" 2>/dev/null; then
    {
      printf '\n%s\n' "$marker"
      printf '## Honch integration\n\n'
      printf 'To integrate Honch into this codebase, read and follow\n'
      printf '`.honch/%s/AGENTS.md` (and the per-path files in\n' "$SKILL_NAME"
      printf '`.honch/%s/content/`). Targets Honch SDK 0.3.0.\n' "$SKILL_NAME"
    } >> "$discpath"
  fi
  ok "$(agent_label "$agent")$(printf '%*s' $((12 - ${#agent})) '') → $discpath  (+ $body)"
}

install_cursor() {
  body="$BASE/.honch/$SKILL_NAME"; rm -rf "$body"; copy_body "$body"
  cp "$SKILL_ROOT/adapters/AGENTS.md" "$body/AGENTS.md"
  rules="$BASE/.cursor/rules"; mkdir -p "$rules"
  cp "$SKILL_ROOT/adapters/cursor/$SKILL_NAME.mdc" "$rules/$SKILL_NAME.mdc"
  ok "Cursor        → $rules/$SKILL_NAME.mdc  (+ $body)"
}

step "installing $SKILL_NAME ($SCOPE) for:$SELECTED"
echo
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

echo
ok "Done. Start a new agent session and ask it to \"integrate Honch\"."
if [ "$SCOPE" = "project" ]; then
  printf '%s  Tip: commit the new files (or add .honch/ to .gitignore) as you prefer.%s\n' "$muted" "$reset"
fi
exit 0
