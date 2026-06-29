# Integrating Honch — the procedure

Your one job: get Honch working in this codebase — installed, configured,
sending a **verified first event**, with the traps that silently break
integrations already handled. Do it well enough that the person never has to
think about the SDK's sharp edges.

This file is the spine. It is agent-neutral: it speaks in actions ("inspect the
repo", "edit the file", "run the build"), not any one tool's vocabulary. Follow
it with whatever file, search, and shell capabilities you have.

> **Targets Honch SDK `0.3.0`.** Every dependency string below pins `0.3.0`
> (`honch/honch^0.3.0`, `honch/Honch@^0.3.0`, etc.). If the project already uses
> a newer SDK, say so and follow that version's docs instead of forcing `0.3.0`.

## The workflow (do these in order)

1. **Detect** the integration path. Read [detection.md](detection.md) and
   classify the repo into exactly **one** path. If you cannot, ask — do not guess.
2. **Plan.** Read the matching path file in this directory and write a short,
   concrete plan: which path, which files you will touch, where `init`, the
   delivery pump (`tick`/`flush`), and the first event will go, and what values
   you still need from the user (API key, device model, endpoint).
3. **Confirm.** Present the plan and **wait for one explicit go-ahead.** Do not
   edit any file before that. (See the hard gate below.)
4. **Implement.** Make the edits exactly as planned. Match the surrounding code's
   style. Keep changes minimal and reversible — you are in someone's real codebase.
5. **Verify.** Run the path's build/verify step and confirm it actually passes.
   Show the evidence. Then walk the [production checklist](production-checklist.md)
   and flag anything still open. Never claim "done" without a build (or, where a
   build isn't possible, the most concrete check the path allows).

## Hard gate — no edits before confirmation

You inspect and plan freely. You do **not** modify, create, or delete any file in
the user's codebase until they have explicitly approved the plan. This is a public
tool running in someone's real, valuable repository; an unapproved edit is a
failure even if it would have been correct. If the user says "just do it", treat
that as the go-ahead and proceed.

## The values every integration needs

Collect these before implementing (ask if not discoverable):

| Value | Example | Notes |
| --- | --- | --- |
| Project API key | `honch_…` | Sent as `X-Honch-Project-Key`. **Never hardcode in source** — use config/env/secrets. |
| Device model | `demo-board` | Static per product. |
| Firmware/app version | `1.0.0` | Drives `$firmware_update` when it changes. |
| Endpoint | `https://i.honch.io` | The default. Only override for a local/dev capture service. |
| Environment | `production` | Optional; use `development`/`staging` to separate test data. |

## Universal traps — check every one, every time

These are the failure modes that make an integration look "done" but silently not
work. They are not optional polish; they are the job.

- **Delivery must be pumped.** There is no background thread. If nothing calls
  `tick()` (and/or `flush()`) on an interval, events queue forever and never
  upload. Wiring the pump into a real loop/task is mandatory, not a follow-up.
- **Stack headroom on device ports (ESP-IDF / Arduino).** The delivery task needs
  **≥ 8192 bytes** of stack or the TLS handshake corrupts memory and surfaces as
  bogus TLS/heap errors or resets.
- **Never from an ISR / latency-sensitive path.** `track`/`tick`/`flush` can
  allocate and block (up to `transport_timeout_ms`). For GPIO etc., push to a
  queue from the ISR and call `track()` from a normal task.
- **Sync the clock first (ESP32 / MicroPython boards).** No battery-backed RTC →
  events are stamped near 1970 and fall outside the dashboard's time window
  (they look "missing"). Run NTP/SNTP and wait for a real time **before** init/track.
  On MicroPython the TLS handshake also needs the real clock.
- **Reserved keys are rejected, not overwritten.** Event properties may not reuse
  `$`-prefixed keys or `distinct_id` — they return invalid-argument. Rename them.
- **The RAM queue is volatile.** Default queue is drop-oldest and lost on reset.
  If losing buffered events on power loss is unacceptable, wire durable
  queue/state adapters (and consider `SYNC_ALWAYS` on POSIX).
- **Identity merge needs `$identify`.** Just swapping `distinct_id` from device-id
  to user-id creates a *second, unconnected* person. To stitch anonymous history,
  emit a `$identify` with the previous id in `$anon_distinct_id`. See
  [identity.md](identity.md).
- **API key hygiene.** Keep it out of source control and logs; supply via build
  config / environment / secrets.

## Expect traffic on the wire

Honch is **not silent**: `init` alone queues `$device_boot`, and lifecycle events
(`$firmware_update`, `$session_*`, `$battery_low`, `$device_shutdown`) auto-emit
from the relevant calls. Crash/error capture is **automatic** where enabled — there
is no manual `report_error` for the normal path. Tell the user to expect this so
the extra events aren't a surprise.

## Path files in this directory

- [detection.md](detection.md) — classify the repo into one path
- [esp-idf.md](esp-idf.md) — ESP32 firmware (C, ESP-IDF) — **stable**
- [arduino.md](arduino.md) — ESP32 firmware (C++, Arduino/PlatformIO) — **preview**
- [c-posix.md](c-posix.md) — embedded Linux / native C — **stable**
- [micropython.md](micropython.md) — MicroPython firmware — **stable**
- [relay.md](relay.md) — React Native / Swift companion-app relay (BLE forwarding)
- [byo-http.md](byo-http.md) — anything else that can POST JSON
- [identity.md](identity.md) — the `distinct_id` / `$device_id` / `$identify` model
- [production-checklist.md](production-checklist.md) — the definition of "done"
- [troubleshooting.md](troubleshooting.md) — symptom-first fixes

## What this skill does not do

Honch SDKs (and this skill) are the device/client side only. Not the dashboard,
cloud ingest, BLE protocol design, billing, or analytics UI. If asked to query
data, build funnels, or configure the platform, say that's outside the
integration job and point at the Honch dashboard/docs.
