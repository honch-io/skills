# Honch Integrator (agent instructions)

> Installed by the Honch skill installer (`honch.dev/skill`). This section tells
> any coding agent how to integrate Honch into this codebase. The full procedure
> and per-path recipes live next to this file in `content/`.

When the user asks to **add, install, set up, wire up, or instrument with Honch**
(the honch SDK / honch analytics / `honch/honch` / `honch/Honch` /
`@honch/react-native-relay`), or to **send events to Honch / `i.honch.io`**, do
the following.

**Targets Honch SDK `0.3.0`.** If the project already uses a newer SDK, follow
that version instead.

## Procedure

1. **Read `content/integrator.md`** — the full workflow, the hard "no edits before
   confirmation" gate, and the universal trap checklist. Follow it.
2. **Detect** the path with `content/detection.md`, then read the matching path
   file in `content/` (`esp-idf.md`, `arduino.md`, `c-posix.md`, `micropython.md`,
   `relay.md`, or `byo-http.md`).
3. **Plan → confirm (one explicit go-ahead) → implement → verify the build.**

## Non-negotiables

- **No edits before the user approves the plan.** Inspect and plan freely; modify
  nothing until they say go.
- **Delivery must be pumped:** if nothing calls `tick()`/`flush()` on an interval,
  events queue forever and never upload. Wiring the pump is mandatory.
- **Device ports (ESP-IDF/Arduino):** delivery task needs **≥ 8192 bytes** stack;
  never call `track`/`tick`/`flush` from an ISR; sync the clock (NTP) before
  tracking on ESP32/MicroPython or events date to ~1970 and look "missing."
- **Identity:** merging anonymous→user history needs a `$identify` carrying
  `$anon_distinct_id`; a bare `distinct_id` swap creates a second, unconnected
  person. See `content/identity.md`.
- **Reserved keys** (`$`-prefixed, `distinct_id`) are rejected as event properties.
- **API key** stays out of source control and logs.
- **Verify before "done":** run the build (or the most concrete check the path
  allows), then walk `content/production-checklist.md`.

This is the device/client integration only — not the Honch dashboard, cloud
ingest, or analytics UI.
