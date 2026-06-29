# Identity — the part integrations get wrong

This is the single highest-value thing to get right, because getting it wrong is
silent: data still flows, but a device's history never connects to the user, and
you end up with duplicate, unmergeable people. Read this before wiring any sign-in.

## The four IDs

| ID | Who sets it | Lifetime | What it is |
| --- | --- | --- | --- |
| `distinct_id` | you | changes at identify | Who each event is attributed to. **Starts as the device id**, becomes the user id after `$identify`. |
| `$device_id` | you | device's life (new on factory reset) | The physical hardware. Independent of `distinct_id`. |
| `$session_id` | you (optional) | one logical session | A recording, workout, trip, etc. |
| `person_id` | **Honch** (server-side) | — | The canonical person every `distinct_id` resolves to. **You never send it.** |

You manage `distinct_id`, `$device_id`, and optionally `$session_id`. Honch mints
`person_id` and groups `distinct_id`s under it.

## Anonymous → identified (the merge)

1. **Before you know the user:** send events with `distinct_id` = the **device
   id** (same value as `$device_id`). Honch creates an anonymous person.
2. **On sign-in:** emit a `$identify` event. Set `distinct_id` to the **user id**,
   and put the **previous (device) id** in the event's `$anon_distinct_id`
   property. This is the *only* thing that merges the anonymous history into the
   user.
3. **After that:** send subsequent events with `distinct_id` = the user id.

```json
{
  "context": { "distinct_id": "user-98234", "$device_id": "device-abc", "...": "..." },
  "events": [{
    "event": "$identify",
    "properties": {
      "$anon_distinct_id": "device-abc",
      "$set": { "email": "sam@example.com", "plan": "pro" },
      "$set_once": { "signup_source": "app" }
    }
  }]
}
```

With the native SDKs this is `identify("user-98234", ...)` — the SDK carries the
previous id as `$anon_distinct_id` for you. For BYO HTTP you set it yourself.

## The trap (say this to the user explicitly)

> **Just switching `distinct_id` from the device id to the user id, without a
> `$identify` event, does NOT stitch anything — it creates a second, unconnected
> person.** The `$anon_distinct_id` on a `$identify` is what performs the merge.

On BYO HTTP, also don't mix identities in one request (context's `distinct_id` is
shared by the whole batch): flush device-id events, send the `$identify`, then
continue under the user id.

## Person properties without identifying

For a hardware-only device with no login, attach properties to the current person
with a `$set` event (or `$set` / `$set_once` inside `$identify`):

```json
{ "context": { "distinct_id": "device-abc", "$device_id": "device-abc", "...": "..." },
  "events": [ { "event": "$set", "properties": { "$set": { "region": "us-west" } } } ] }
```

`$set` overwrites; `$set_once` only fills gaps.

## reset()

Call `reset()` (native) at a factory-reset / logout boundary: it clears identity,
session, and queue and emits no event. On factory reset a device should also get a
new `$device_id` and start fresh.

## Devices vs people

`$device_id` is tracked independently of identity — Honch keeps a record per
device and links it to the most recent person. One person can own several devices;
a resold device gets a new `$device_id` on factory reset.
