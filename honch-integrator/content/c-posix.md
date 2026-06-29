# Path: C / POSIX (embedded Linux / native C)

**Stable · 0.3.0.** Runs on macOS and Linux; targets embedded-Linux devices and
gateways. Reports `$sdk_platform` as `c-posix`. The queue is **file-backed**, so
you can watch events move through directories on disk — it's also the fastest way
to validate an integration before a constrained device. **Multi-client API**:
every call takes an explicit `honch_client_t *`.

Requirements: CMake `3.20+`, a C11 compiler, libcurl, pthreads. Each client needs
its own writable `queue_directory` — never point two clients at the same one.

## 1. Build the SDK

```bash
cmake -S . -B build -DHONCH_BUILD_TESTS=ON -DHONCH_BUILD_EXAMPLES=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

Build is warnings-as-errors. To compile out crash/error reporting:
`-DHONCH_ENABLE_ERROR_TRACKING=OFF`.

To install and link from another CMake project:

```bash
cmake -S . -B build-install -DHONCH_BUILD_TESTS=OFF -DHONCH_BUILD_EXAMPLES=OFF \
  -DCMAKE_INSTALL_PREFIX=/opt/honch-posix
cmake --build build-install --target honch_posix
cmake --install build-install
```

```cmake
find_package(honch_posix REQUIRED)
target_link_libraries(app PRIVATE honch::honch_posix)
```

## 2. Configure + first event

```c
#include "honch/honch.h"

honch_config_t config = {
    .api_key = "your-api-key",            // keep out of source control
    .endpoint_url = "https://i.honch.io",
    .device_model = "linux-gateway",
    .firmware_version = "1.0.0",
    .queue_directory = "/var/lib/honch",
};

honch_client_t *client = NULL;
if (honch_init(&client, &config) != HONCH_STATUS_OK) return 1;

const honch_property_t props[] = { honch_prop("role", honch_str("developer")) };
honch_identify(client, "local-user-001", props, 1);   // see identity.md

honch_session_start(client, "demo");
honch_track(client, "button_pressed", NULL, 0);
honch_session_end(client);

honch_flush(client);
honch_shutdown(client);
```

Required: `api_key`, `endpoint_url`, `device_model`, `firmware_version`,
`queue_directory`. `honch_init()` is synchronous (validates, reconciles the queue
dir, persists identity, queues `$device_boot`) — no network I/O.

| Field | Default | Notes |
| --- | --- | --- |
| `device_id` | generated + persisted | Random ID on first run if unset. |
| `environment` | `production` | |
| `durability_mode` | `OS_BUFFERED` | `SYNC_ALWAYS` fsyncs every write (power-loss safe, slower). |
| `flush_interval_seconds` | 120 | |
| `flush_event_threshold` | 20 | |
| `transport_timeout_ms` | 8000 | |
| `connectivity_callback` | — | Return offline so ticks skip DNS/TLS. |

## 3. Pump delivery (mandatory)

Dedicated thread; `honch_tick(client)` does a synchronous POST and blocks up to
`transport_timeout_ms`.

```c
while (running) {
    honch_tick(client);
    sleep(1);
}
```

`honch_flush(client)` forces a send now — useful in short-lived processes before
exit.

## 4. Inspect local storage (the debugging superpower of this port)

```text
<queue_directory>/
  pending/   events waiting to upload (one file each)
  dead/      permanently rejected events
  state/     device_id, distinct_id, firmware_version
```

Atomic writes (temp + rename), oldest-first eviction. Retryable failures stay in
`pending/`; permanent rejections move to `dead/`.

## 5. Crash breadcrumbs (optional)

`honch_install_error_handlers(queue_directory)` installs async-signal-safe handlers
for `SIGABRT/SIGSEGV/SIGBUS/SIGILL/SIGFPE` that write a bounded breadcrumb; the
next `honch_init()` imports it as a `$crash`. Process-global → single client only.
No coredump/symbolicated backtrace on this port. For handled, non-fatal errors:
`honch_core_report_log_error(client, component, message)`.

## 6. Debugging failures

```c
honch_error_detail_t detail;
if (honch_tick(client) != HONCH_OK &&
    honch_core_get_last_error(client, &detail) == HONCH_OK) {
    char line[192];
    honch_error_detail_format(&detail, line, sizeof(line));
    fprintf(stderr, "honch: %s\n", line);   // e.g. "transport error: HTTP 503 (reason=http_status)"
}
```

## Verify

The `cmake --build` + `ctest` above proves the SDK builds and passes. For the
integration itself: run the binary, then confirm events leave
`<queue_directory>/pending/` as they upload (and don't pile up in `dead/`).
Examples live under `ports/posix/example/` (`posix_device`, `connected_camera`,
`posix_gpio`, `identify_merge`). Then run
[production-checklist.md](production-checklist.md).

## Public API (multi-client)

`honch_init(&client, &config)`, `honch_track(client, event, props, count)`,
`honch_identify(client, distinct_id, traits, count)`,
`honch_set_property(client, key, value)`,
`honch_session_start(client, name)` / `honch_session_end(client)`,
`honch_tick(client)`, `honch_flush(client)`, `honch_reset(client)`,
`honch_shutdown(client)`, `honch_get_device_id(client)`,
`honch_copy_device_id(client, buf, size)`,
`honch_core_report_log_error(client, component, message)`,
`honch_install_error_handlers(queue_directory)`,
`honch_core_get_last_error(client, &detail)`. Return `honch_status_t`
(`HONCH_STATUS_OK`) except the `const char *` getters.
