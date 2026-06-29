# Honch Skills

Public agent skills for working with [Honch](https://honch.io) — product
analytics for connected hardware. These are drop-in skills for AI coding agents
(Claude Code, Codex, Cursor, Gemini CLI, Copilot) that encode how to do a Honch
job well, so the agent gets it right the first time.

## Skills

| Skill | What it does |
| --- | --- |
| [`honch-integrator`](honch-integrator/) | Integrate Honch into any codebase — detect the right path (ESP-IDF, Arduino, C/POSIX, MicroPython, relay, or HTTP/JSON), wire it in, and verify a first event. Targets SDK `0.3.0`. |

More skills (e.g. event instrumentation, integration diagnosis) may land here over
time.

## Install

Each skill installs with one line, via an interactive selector that supports
multiple agents (zero dependencies — no Node):

```sh
curl -fsSL https://honch.dev/skill | sh
```

See [honch-integrator/README.md](honch-integrator/README.md) for flags, scopes,
and manual installation.

## How a skill is laid out

Skills are written **agent-neutral** and wrapped per agent:

```
<skill>/
  content/    # the real instructions, in plain action-language (no agent-specific tools)
  adapters/   # thin per-agent entry points (Claude SKILL.md, AGENTS.md, Cursor .mdc, …)
  install/    # the installer the honch.dev route serves
  VERSION
```

The knowledge lives once in `content/`; the adapters only handle discovery, so the
same skill works across agents. `AGENTS.md` is the cross-agent lingua franca.

## Versioning

A skill's `VERSION` tracks the Honch SDK version it targets. The installer fetches
a matching tag, so an install is pinned and ages honestly.

## License

[Apache 2.0](LICENSE).
