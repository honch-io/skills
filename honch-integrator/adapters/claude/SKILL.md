---
name: honch-integrator
description: >-
  Integrate Honch product analytics into any codebase, end to end. Use whenever
  the user wants to add, install, set up, or wire up Honch (the honch SDK, honch
  analytics, honch/honch, honch/Honch, @honch/react-native-relay), send device or
  app events to Honch / i.honch.io, or instrument firmware or an app with Honch.
  Detects the right integration path — ESP-IDF, Arduino (ESP32), C/POSIX,
  MicroPython, the React Native / Swift relay, or plain HTTP/JSON for anything
  else — then plans, wires in init + delivery pump + a verified first event, and
  handles the traps that silently break integrations. Targets Honch SDK 0.3.0.
---

# Honch Integrator

Your one job: integrate Honch into this codebase correctly — installed,
configured, sending a **verified first event**, with the silent-failure traps
already handled.

**Targets Honch SDK `0.3.0`.** If the project already uses a newer SDK, follow
that version instead of forcing `0.3.0`.

## Do this

1. **Read [content/integrator.md](content/integrator.md) now** — it is the
   full procedure (workflow, the hard "no edits before confirmation" gate, the
   universal trap checklist). Follow it.
2. **Detect** the path with [content/detection.md](content/detection.md),
   then **read the matching path file** in `content/` before planning.
3. **Plan → confirm (one explicit go-ahead) → implement → verify the build.**

## The non-negotiables (full detail in content/)

- **No edits before the user approves the plan.** Inspect and plan freely; do not
  modify files until they say go.
- **Delivery must be pumped.** Nothing calls `tick()`/`flush()` on an interval →
  events queue forever. Wiring the pump is mandatory.
- **Device ports:** delivery task needs **≥ 8192 bytes** stack; never call
  `track`/`tick`/`flush` from an ISR; sync the clock (NTP) before tracking on
  ESP32/MicroPython.
- **Identity:** merging anonymous→user history needs a `$identify` with
  `$anon_distinct_id` — a bare `distinct_id` swap creates a second person. See
  [content/identity.md](content/identity.md).
- **Reserved `$`/`distinct_id` keys** are rejected as event properties.
- **API key** stays out of source control and logs.
- **Verify before "done"** — run the build (or the most concrete check the path
  allows), then walk
  [content/production-checklist.md](content/production-checklist.md).

## Path files (in `content/`)

`detection.md` · `esp-idf.md` · `arduino.md` · `c-posix.md` · `micropython.md` ·
`relay.md` · `byo-http.md` · `identity.md` · `production-checklist.md` ·
`troubleshooting.md`

This skill is the device/client integration only — not the Honch dashboard, cloud
ingest, or analytics UI.
