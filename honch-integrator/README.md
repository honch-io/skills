# honch-integrator

An agent skill that integrates **Honch** product analytics into any codebase —
correctly, and all the way to a verified first event. It detects the right
integration path (ESP-IDF, Arduino, C/POSIX, MicroPython, the React Native /
Swift relay, or plain HTTP/JSON), plans the change, wires in init + the delivery
pump + a first event, and handles the traps that silently break integrations.

- **Targets Honch SDK `0.3.0`.**
- **Works across agents:** Claude Code (first-class), plus Codex, Cursor, Gemini
  CLI, and Copilot via the cross-agent `AGENTS.md` standard.

## Install

One line — pick your agent(s) from an interactive menu:

```sh
curl -fsSL https://honch.dev/skill | sh
```

The installer auto-detects which agents you have, lets you multi-select, and asks
global vs. this-project. It is pure POSIX shell — **no Node required.**

Non-interactive / scripted:

```sh
# everything, globally
curl -fsSL https://honch.dev/skill | sh -s -- --all --global

# specific agents, into the current repo
curl -fsSL https://honch.dev/skill | sh -s -- --agent claude,codex --project
```

Flags: `--agent a,b,c` · `--all` · `--global` · `--project` · `--ref <tag>` ·
`--src <dir>` (install from a local checkout) · `--help`.

### Where it installs

| Agent | Location |
| --- | --- |
| Claude Code | `~/.claude/skills/honch-integrator/` (or `./.claude/skills/…` for `--project`) |
| Codex / Gemini / Copilot | self-contained body in `.honch/honch-integrator/` + a pointer in `AGENTS.md` / `GEMINI.md` / `.github/copilot-instructions.md` |
| Cursor | `.cursor/rules/honch-integrator.mdc` + body in `.honch/honch-integrator/` |

## Manual install (no curl)

Copy this directory into the right place for your agent. For Claude Code:

```sh
git clone https://github.com/honch-io/skills.git
cp -R skills/honch-integrator/content ~/.claude/skills/honch-integrator/content
cp skills/honch-integrator/adapters/claude/SKILL.md ~/.claude/skills/honch-integrator/SKILL.md
```

For an `AGENTS.md`-based agent, copy `content/` plus `adapters/AGENTS.md` into
your project (e.g. under `.honch/honch-integrator/`) and point your agent's
instruction file at it.

## Use it

Start an agent session in the target codebase and ask it to **"integrate
Honch."** It will detect the path, propose a plan, wait for your go-ahead, make
the edits, and verify the build.

## What's inside

```
honch-integrator/
  content/      # agent-neutral skill body (the real instructions + per-path recipes)
  adapters/     # thin per-agent entry points that point at content/
  install/      # the pure-sh installer served at honch.dev/skill
  VERSION       # 0.3.0
```

## Scope

This skill is the **device/client integration** only — not the Honch dashboard,
cloud ingest, or analytics UI.
