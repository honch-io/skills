# Production checklist — the definition of "done"

A first event is the start, not the finish. Walk this before telling the user the
integration is ready to ship. Flag anything you couldn't verify rather than
assuming it's fine — "evidence before claims."

## Identity
- [ ] Decided fixed `device_id` vs SDK-generated. If generated, it **persists**
      across restarts (durable state storage is wired on device ports).
- [ ] `identify()` called at the right moment if the product has accounts, and
      earlier anonymous events **merge** to the person (see identity.md).
- [ ] `reset()` is called at the factory-reset / logout boundary.

## Transport & security
- [ ] Endpoint is `https://i.honch.io` (or the assigned host) over HTTPS. No
      production path disables TLS verification (`insecureSkipTlsVerify` /
      `verify_tls(False)` are dev-only).
- [ ] API key supplied via config, **out of source control and logs**, scoped to
      capture.
- [ ] `401` is understood as permanent (bad key), not retried forever.

## Queue & durability
- [ ] Event buffer / queue sized for the worst-case offline window. Default is
      drop-oldest past `max_queued_events` (1000).
- [ ] Volatile RAM vs durable storage chosen **deliberately**. If losing buffered
      events on power loss is unacceptable, durable queue/state adapters are wired
      (and `SYNC_ALWAYS` considered on POSIX).
- [ ] Largest event stays under `max_event_bytes` (default 8192).

## Flushing
- [ ] `tick()` is pumped from a dedicated task/thread — **never** an ISR or
      latency-sensitive path. On device ports that task has **≥ 8192 bytes** stack.
- [ ] Flush cadence (`flush_interval_seconds`, `flush_event_threshold`,
      `flush_min_interval_ms`) suits event volume and power budget.
- [ ] A `connectivity_callback` (or equivalent) is supplied so the SDK skips
      DNS/TLS while the radio is down.

## Time
- [ ] Device clock is synced (NTP/SNTP) before depending on absolute timestamps.
      (Critical on ESP32 / MicroPython boards with no RTC.)

## Lifecycle & errors
- [ ] The team expects the automatic traffic: `init` alone queues `$device_boot`;
      `$firmware_update` fires when the stored version changes; sessions/battery/
      shutdown auto-emit.
- [ ] If crash/error capture is wanted, it's enabled (`enable_error_tracking`,
      and `enable_crash_symbolication` + ESP-IDF coredump options for backtraces —
      coredumps are ESP-IDF/Xtensa only; MicroPython captures the Python traceback;
      other ports report `$crash` without a coredump).

## Verify on real hardware (device ports)
- [ ] Watched a real device boot, queue, and upload (`204`/`202`) and seen events
      land in Honch.
- [ ] Tested offline → reconnect: events stay pending offline, flush on reconnect
      with backoff.
- [ ] Power-cycled mid-queue and confirmed the durability behavior you expect.

When all of the above hold, the integration is ready to ship. Point the user at
[troubleshooting.md](troubleshooting.md) for the failure modes they'll field.
