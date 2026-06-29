# Path: BYO HTTP (JSON) — any codebase that can POST

No official SDK required. If the codebase can make an HTTPS request, it can send
to Honch by POSTing JSON to Capture. This is a first-class integration — use it
for any app, backend, gateway, or script in any language without a matching native
SDK. JSON expands to the exact same canonical event as the binary wire format, so
nothing is lost on the analytics side.

> Reach for the binary wire format **only** when the device transport is severely
> bandwidth/power constrained. JSON is the recommended default.

## 1. Send one event

```bash
curl -X POST https://i.honch.io/capture \
  -H "Content-Type: application/json" \
  -H "X-Honch-Project-Key: your-project-key" \
  -d '{
    "context": {
      "distinct_id": "device-1",
      "$device_id": "device-1",
      "$device_model": "demo-board",
      "$firmware_version": "1.0.0",
      "$sdk_platform": "custom",
      "$sdk_version": "1.0.0"
    },
    "events": [{ "event": "app_started" }]
  }'
```

`200` with `{"status":"ok","accepted":1,"rejected":0}` = stored. A `4xx` = nothing
stored; fix the request.

## 2. The request shape

- **`context`** is declared **once per request** and applies to the whole batch —
  so every event in one request shares one `distinct_id`. Required context keys:
  `distinct_id`, `$device_id`, `$device_model`, `$firmware_version`,
  `$sdk_platform`, `$sdk_version`.
- **`events`** is an array (≤ 500 per request). Each has `event` (name), optional
  `timestamp` (ms epoch — use **on-device event time**, not send time), and
  optional `properties`.
- **Reserved keys**: the promoted context keys (`$device_id`, `distinct_id`, …)
  must **not** be set per-event. Lifecycle property names (`reset_reason`,
  `session_name`, `previous_version`, `new_version`, `state`, `$battery_level`,
  `$wifi_rssi`) **are** allowed inside an event's `properties`.

## 3. Identity — get this right (see identity.md)

Send `context.distinct_id = $device_id` while anonymous. On sign-in, emit a
`$identify` event with the user id as `distinct_id` and the previous device id in
`$anon_distinct_id` — this is the only thing that merges anonymous history.
**Switching `distinct_id` without `$identify` creates a second, unconnected
person.** Don't mix identities in one request: flush device-id events, then send
`$identify`, then continue under the user id.

```json
{ "context": { "distinct_id": "user-98234", "$device_id": "device-abc", "...": "..." },
  "events": [ { "event": "$identify",
    "properties": { "$anon_distinct_id": "device-abc",
      "$set": { "email": "sam@example.com" }, "$set_once": { "signup_source": "app" } } } ] }
```

## 4. Lifecycle events (free device health analytics)

Emit these as ordinary events with the listed properties: `$device_boot`
(`reset_reason`), `$session_start` (`session_name`) / `$session_end`,
`$firmware_update` (`previous_version`, `new_version`), `$battery_low` (`level`),
`$connectivity_change` (`state`), `$crash`/`$error`, `$device_reset`,
`$device_shutdown`.

## 5. Batch, retry, backoff (the client you build)

- Keep events in a local queue until Capture accepts them.
- Flush on a timer (30–60s), at a depth threshold, on app background, before exit.
- Classify responses:

| Response | Action |
| --- | --- |
| `200` | Stored — drop the batch. If `rejected > 0`, the events in `errors` are permanently bad; log, don't retry. |
| `429`, `5xx`, network/timeout | Retryable — keep and back off. |
| `400`, `401`, `415`, `422` | Permanent — nothing stored; fix request/key/content-type. Do **not** loop. |

Contract: **`2xx` = at least one event stored; `4xx` = nothing stored.** Backoff:
1s initial, 5min cap, ±25% jitter.

```ts
function nextBackoffMs(attempt: number): number {
  const base = Math.min(1000 * 2 ** attempt, 5 * 60 * 1000);
  const jitter = base * 0.25 * (Math.random() * 2 - 1);
  return Math.max(0, Math.round(base + jitter));
}
```

## 6. Reference client

A zero-dependency TypeScript reference client (uses `fetch`; has `identify`,
lifecycle helpers, retry/backoff, and pluggable durable persistence via
`initialQueue`/`onQueueChange`) lives in the SDK repo at
`examples/http-json/typescript`. Mirror its structure when building in another
language.

## Verify (do this before wiring live `/capture`)

Point the client at `POST https://i.honch.io/capture/validate` first — it
authenticates and runs full validation + expansion, returns the canonical
`expanded_events` it *would* store, and surfaces every error **without storing
anything or consuming rate limit**.

```bash
curl -sS https://i.honch.io/capture/validate \
  -H "Content-Type: application/json" \
  -H "X-Honch-Project-Key: honch_your_project_key" \
  -d @payload.json
```

Iterate until `{ "ok": true, ... }` and the `expanded_events` look right, then
switch the URL to `/capture` and confirm `{ "status": "ok", "accepted": N }`. You
can also assert against the shared JSON conformance fixtures in the SDK repo
(`spec/conformance/json`). Then run
[production-checklist.md](production-checklist.md).
