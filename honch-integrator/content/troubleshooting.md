# Troubleshooting — symptom first

Find the symptom, confirm the cause, apply the fix. Use this both while
integrating and when the user reports a problem after the fact.

## Events queue but never upload
No background thread — uploads only happen when pumped.
- **Is something calling `tick()`?** A task/thread must call `tick()` periodically
  (and `flush()` to force a send). Without it, events sit forever. This is the #1
  cause.
- **Is the device online?** If a `connectivity_callback` reports offline, `tick()`
  no-ops and `flush()` returns offline by design. Confirm it reflects reality.
- **Network path?** Force a `flush()` and watch for a `POST /capture`.

## Upload returns 401
Project key missing/invalid. The SDK treats `401` as permanent and stops retrying.
- Confirm `X-Honch-Project-Key` carries the correct, capture-scoped key.
- Confirm the right endpoint/project. Rotate the key if it may have leaked.

## Which failures retry?
| Result | HTTP | Behavior |
| --- | --- | --- |
| Retryable | 408, 409, 429, 5xx, transport/timeout | Stay queued; backoff 1s→5min ±25% jitter, honoring `Retry-After`. |
| Permanent | 401, other 4xx | Dropped / dead-lettered so they can't block the queue. |

If events are *disappearing*, you're likely hitting a permanent rejection —
inspect the request body/headers.

## `track()` returns invalid-argument
Usually a reserved key: event properties may not reuse a `$`-prefixed key or
`distinct_id` (rejected, not overwritten). Rename the property. Also covers an
empty/oversized event name (max 128 bytes) or an event over `max_event_bytes`.

## Tick task crashes / resets the device (ESP-IDF / Arduino)
TLS handshake needs stack headroom — give the delivery task **≥ 8192 bytes**. A
too-small stack corrupts during the handshake and surfaces as bogus TLS/memory
errors. Never call `tick()`/`flush()` from an ISR or high-priority/real-time path.

## Tracking a GPIO press
No GPIO helper, and never `track()` from an ISR. ISR pushes the pin to a queue; a
normal task drains it and calls `track()`.

## Timestamps look wrong (events "missing")
Before the clock is set, the SDK stamps boot-relative time and normalizes at flush
— but on ESP32 / MicroPython boards with no RTC, confirm NTP/SNTP runs and the
clock reads real wall-clock time (≥ 2020-01-01) before steady-state. Events dated
to ~1970 fall outside the dashboard's time window and look missing.

## Events lost after a reset / power cut
Default queue is RAM-only and clears on reset. Wire a durable queue/state adapter
(file-backed on POSIX; NV-backed on device ports) and use `SYNC_ALWAYS` if you
must survive abrupt power loss.

## MicroPython: `ImportError` on `import honch`
Firmware wasn't built with the `_honch_core` user C module. Rebuild MicroPython
with `USER_C_MODULES` pointing at the module's CMake file.

## Relay: device never gets an ACK
The relay returns ACK bytes only after a frame is durably stored, and **your app**
must write them to the device's ACK characteristic. Confirm the `acknowledge`
callback actually performs the BLE write — the relay never touches Bluetooth.

## Still stuck?
Validate a payload without storing it: `POST /capture/validate` returns the
expanded events so you can see exactly how Honch interprets the request.
