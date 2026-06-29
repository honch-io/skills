# Path: ESP-IDF (ESP32 firmware, C)

**Stable · 0.3.0.** Requires ESP-IDF `>= 5.0` (verified against v6.0.1). The
production Honch SDK for ESP32-family chips — a thin wrapper over the shared core,
published to the Espressif Component Registry as `honch/honch`. Singleton API
(no client handle).

The SDK does **no** network/clock setup. The firmware brings up NVS, netif,
Wi-Fi, time (SNTP), and the TLS trust store. There is no background task.

## 1. Install

```bash
idf.py add-dependency "honch/honch^0.3.0"
```

Or vendor as a submodule (the component pulls in the shared `core/`, so submodule
the whole repo):

```bash
git submodule add https://github.com/honch-io/SDK.git components/honch
```

## 2. Initialize (after NVS/Wi-Fi/SNTP, in `app_main`)

`honch_init()` is synchronous, no network I/O: validates config, derives identity,
reconciles the queue, queues `$device_boot`.

```c
#include "honch.h"

static uint8_t honch_event_buffer[16384];

void app_main(void) {
    // Bring up NVS, netif, Wi-Fi, and SNTP first (firmware's job).

    honch_config_t config = {
        .api_key = CONFIG_HONCH_API_KEY,   // keep the key out of source
        .host = "https://i.honch.io",
        .device_model = "demo-board",
        .firmware_version = "1.0.0",
        .event_buffer = honch_event_buffer,
        .event_buffer_size = sizeof(honch_event_buffer),
    };

    honch_err_t err = honch_init(&config);
    if (err != HONCH_OK) {
        ESP_LOGE("app", "honch_init failed: %d", err);
        return;
    }
}
```

Required: `api_key`, `host`, `device_model`, `firmware_version`, and an event
buffer (≥ 8192 bytes) unless you supply `event_queue_ops`. If you don't set a
`device_id`, the SDK derives `esp32-<station MAC>`.

Useful config fields:

| Field | Default | Notes |
| --- | --- | --- |
| `environment` | `production` | `development`/`staging` to separate test data. |
| `flush_interval_seconds` | 120 | Periodic flush cadence. |
| `flush_event_threshold` | 20 | Queue depth that requests a flush. |
| `transport_timeout_ms` | 8000 | Clamped 1000–10000. |
| `battery_callback` / `battery_low_threshold` | — / 15 | Return 0–100 to enable `$battery_level`/`$battery_low`. |
| `connectivity_callback` | — | Return 0 when offline so the SDK skips DNS/TLS. |
| `enable_error_tracking` | `false` | Master switch: `$crash` after abnormal reset + `ESP_LOGE`→`$error`. |
| `enable_crash_symbolication` | `false` | Also capture the coredump for backend symbolication (needs `enable_error_tracking`). |
| `state_storage_ops` / `event_queue_ops` | — | Durable identity / durable queue. |

## 3. Pump delivery (mandatory)

Low-priority task, **≥ 8192 bytes stack**. `tick()` sends ≤ 1 chunk/call and
blocks up to `transport_timeout_ms` — keep it off latency-sensitive paths.

```c
static void honch_task(void *arg) {
    for (;;) {
        honch_err_t err = honch_tick();
        if (err != HONCH_OK && err != HONCH_ERR_TRANSPORT &&
            err != HONCH_ERR_TIMEOUT && err != HONCH_ERR_OFFLINE) {
            ESP_LOGW("honch", "tick: %d", err);
        }
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
// xTaskCreate(honch_task, "honch", 8192, NULL, 2, NULL);
```

## 4. Track / identify / sessions

```c
const honch_property_t props[] = {
    honch_prop("mode", honch_str("record")),
    honch_prop("duration_ms", honch_i64(4200)),
};
honch_track("mode_changed", props, 2);

honch_identify("user-123", NULL, 0);   // see identity.md before wiring sign-in
honch_session_start("recording");
honch_track("frame_captured", NULL, 0);
honch_session_end();
honch_flush();   // force a send now
```

Reusing a `$`-prefixed key or `distinct_id` in properties returns
`HONCH_ERR_INVALID_ARG`.

### GPIO safely (never `track()` from an ISR)

ISR pushes the pin to a FreeRTOS queue; a normal task drains it and tracks. This
is what the `example_gpio` example does.

```c
static QueueHandle_t s_gpio_queue;   // xQueueCreate(16, sizeof(uint32_t))
static void IRAM_ATTR button_isr(void *arg) {
    uint32_t pin = (uint32_t)(uintptr_t)arg;
    xQueueSendFromISR(s_gpio_queue, &pin, NULL);
}
static void gpio_task(void *arg) {
    uint32_t pin;
    for (;;) if (xQueueReceive(s_gpio_queue, &pin, portMAX_DELAY) == pdTRUE) {
        const honch_property_t props[] = { honch_prop("pin", honch_i64(pin)) };
        honch_track("button_pressed", props, 1);
    }
}
```

## 5. Crash / error tracking (optional)

Two Kconfig options gate the *code* (both default on under **Honch SDK** in
`menuconfig`): `CONFIG_HONCH_ERROR_TRACKING` and `CONFIG_HONCH_CRASH_SYMBOLICATION`.
To actually report at runtime you must also set `enable_error_tracking = true`
(and `enable_crash_symbolication = true` for coredumps). Coredumps need ESP-IDF's
`CONFIG_ESP_COREDUMP_ENABLE_TO_FLASH` and a `coredump` partition. Full
symbolicated backtraces are Xtensa-only (ESP32, S-series); RISC-V (C3/C6/H2) is
more limited. No source code or symbols are ever uploaded.

## 6. Durability (optional)

Default queue is RAM, cap 1000, drop-oldest — cleared on reset/power loss. For
persistence, supply `state_storage_ops` (durable identity/firmware version, e.g.
NVS — note NVS keys cap at 15 chars, so firmware version is stored as `fw_version`)
and `event_queue_ops` (durable queue). The SDK ships the hooks; you provide storage.

## Verify

```bash
idf.py set-target esp32   # or esp32s3, etc.
idf.py build              # build alone proves the integration compiles
idf.py flash monitor      # on hardware: watch $device_boot at init, then POST /capture
```

A `204` = batch accepted; `202` = chunk stored. If events queue but never upload,
see [troubleshooting.md](troubleshooting.md). Then run
[production-checklist.md](production-checklist.md).

## Public API (singleton)

`honch_init(&config)`, `honch_track(event, props, count)`,
`honch_identify(distinct_id, traits, count)`, `honch_set_property(key, value)`,
`honch_session_start(name)` / `honch_session_end()`, `honch_tick()`,
`honch_flush()`, `honch_reset()`, `honch_shutdown()`, `honch_get_device_id()`,
`honch_get_queue_stats(&stats)`. All return `honch_err_t` (`HONCH_OK`).
