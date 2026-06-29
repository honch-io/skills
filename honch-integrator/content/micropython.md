# Path: MicroPython (firmware)

**Stable · 0.3.0.** PyPI package `honch-micropython`. A thin Python wrapper over
the same C core, bound through a user C module named `_honch_core`. **Not pure
Python and not standalone** — the module must be compiled into the firmware;
`import honch` without `_honch_core` raises `ImportError`. CircuitPython is out of
scope.

The wrapper rejects host-side hooks: passing `platform`, `transport`,
`battery_callback`, or `auto_properties_callback` raises `InvalidArgumentError`
(those adapters live in the C module).

## 1. Build firmware with `_honch_core`

Point the MicroPython build at the module's CMake file with `USER_C_MODULES`:

```bash
# Unix port (handy for host testing)
make -C ports/unix \
  USER_C_MODULES=/path/to/SDK/ports/micropython/usermod/honch/micropython.cmake

# A board — also freeze the Python wrapper into the image:
make -C ports/esp32 BOARD=ESP32_GENERIC \
  USER_C_MODULES=/path/to/SDK/ports/micropython/usermod/honch/micropython.cmake \
  FROZEN_MANIFEST=/path/to/SDK/ports/micropython/manifest.py
```

The user C module does not set firmware-global options (e.g. GC heap size) — keep
those in your board/host config.

## 2. Install or freeze the wrapper

The `honch/*.py` wrapper modules ship on PyPI as `honch-micropython`: freeze via
the manifest (recommended for boards) or install with `mip`. If frozen into
firmware, do **not** also copy it into `/lib`.

## 3. Sync the clock (required — before constructing the client)

Most MicroPython boards (incl. Pico W) have no RTC; `time.time()` reads
`2000-01-01` until set. Events stamped before sync land near 1970 and fall outside
the dashboard's time window. The TLS handshake also needs a real clock (cert
validity check). So sync NTP once after Wi-Fi is up and **before** the client:

```python
import ntptime
# ... after Wi-Fi connected ...
ntptime.settime()   # set RTC from NTP (UTC)
```

## 4. Configure + first event

```python
import honch

client = honch.Honch(
    api_key="your-api-key",            # keep out of source control
    endpoint_url="https://i.honch.io",
    device_id="dev-board-001",
    device_model="dev-board",
    firmware_version="1.0.0",
    event_buffer=bytearray(8192),      # sized to max_event_bytes
)

client.identify("user-123", {"plan": "beta"})   # see identity.md
client.session_start("demo")
client.track("button_pressed", {"button": "boot"})
client.session_end()
client.flush()
```

Required kwargs: `api_key`, `endpoint_url`, `device_id`, `device_model`,
`firmware_version`, `event_buffer`. Optional map to shared defaults
(`environment`, `batch_size`, `max_queued_events`, `max_event_bytes`,
`transport_timeout_ms`, `flush_interval_seconds`, `flush_min_interval_ms`,
`flush_event_threshold`, `flush_retry_initial_ms`, `flush_retry_max_ms`,
`battery_low_threshold`, `connectivity_callback`). Property values may be
`None`/`bool`/`int`/`float`/`str`/`bytes`/`list`/`tuple`/`dict` (string keys),
nested.

## 5. Pump delivery (mandatory)

No background thread. Call `tick()` on an interval; `flush()` to force a send.

```python
while True:
    client.tick()
    time.sleep(1)
```

Connectivity is explicit: `client.connectivity_changed(connected)` (or
`connected()`/`disconnected()`) records state and emits `$connectivity_change`.
When offline, `flush()` raises `OfflineError` and `tick()` is a no-op.

## 6. TLS

The port verifies the server cert against Google Trust Services root R1 (the
anchor for `i.honch.io`). The NTP sync above is required for the handshake. For a
custom/local endpoint not behind GTS: `honch_transport.verify_tls(False)` before
constructing the client.

## 7. Crash & error reporting (optional)

```python
client.report_log_error("sensor read failed", component="imu")   # handled, non-fatal
```

For **uncaught crashes** pick one (both report a `$crash` with exception type,
message, and Python traceback — the traceback *is* the backtrace; no coredump):

- **Option A — wrap the entry point (works on every build):** `client.run(main)`
  instead of `main()`. Any uncaught exception is reported, flushed, re-raised.
- **Option B — global hook (needs `MICROPY_PY_SYS_EXCEPTHOOK`):**
  `client.install_error_hook()` (returns `False` if unavailable).

Stock firmware (incl. Pico W) ships **without** `sys.excepthook`, so prefer
**Option A**. A fatal `$crash` is delivered only if the flush completes before the
board resets (or you have a durable queue); `run()` flushes before re-raising.

## 8. Debugging failures

```python
try:
    client.flush()
except honch.HonchError:
    print(client.last_error())
    # {'status':'rejected','reason':'auth_invalid_key','http':401,'message':'API key invalid or revoked',...}
```

Wrapper exceptions subclass `HonchError`: `InvalidArgumentError`, `StorageError`,
`RejectedError`, `NotInitializedError`, `CompressionUnavailableError`,
`TransportError` (with `OfflineError`/`RateLimitedError`/`ServerError`).

## Verify

Run the firmware (or the unix build) and confirm a `POST /capture` reaches your
capture service. Examples in `ports/micropython/examples/` (`basic.py`, a
persistent-queue example, a Pico W example). Then run
[production-checklist.md](production-checklist.md).

## Public API

`Honch(**config)`, `track(event, properties=None)`,
`identify(distinct_id, traits=None)`, `set_property(key, value=None)`,
`session_start(name=None)` / `session_end()`,
`report_log_error(message, *, component=None)`, `run(fn, ...)`,
`install_error_hook()` / `uninstall_error_hook()`,
`connectivity_changed()` / `connected()` / `disconnected()`, `tick()`, `flush()`,
`reset()`, `shutdown()`, `get_device_id()`, `queue_stats()`, `last_error()`.
