# Path: Arduino (ESP32 firmware, C++)

**Preview · 0.3.0. ESP32-only.** A C++ wrapper over the shared core for the
Arduino-ESP32 framework, published to the PlatformIO registry as `honch/Honch`
(it vendors a byte-identical copy of the core, so the library is self-contained).
Not a relay; no OTA. Singleton via `honch::defaultClient()`.

Preview status: fine for evaluation and controlled pilots; tell the user
production rollout should wait on hardware/TLS/offline/flush/retry/power-cycle
validation on their board.

## 1. Add the library

`platformio.ini`:

```ini
lib_deps = honch/Honch@^0.3.0
```

## 2. Configure + first event

`HonchConfig` uses default member initializers — **construct empty and assign
fields; do NOT use designated-initializer syntax** (it won't compile in C++).

```cpp
#include <WiFi.h>
#include <time.h>
#include <Honch.h>

static uint8_t eventBuffer[8192];

void setup() {
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) delay(250);

  // ESP32 has no RTC: sync the clock BEFORE tracking or events date to ~1970
  // and fall outside the dashboard's time window.
  configTime(0, 0, "pool.ntp.org");
  while (time(nullptr) < 1577836800UL) delay(250);

  HonchConfig config = {};
  config.apiKey = "your-api-key";          // keep out of source control
  config.host = "https://i.honch.io";
  config.deviceModel = "demo-board";
  config.firmwareVersion = "1.0.0";
  config.rootCaPem = ROOT_CA_PEM;          // required for HTTPS
  config.eventBuffer = eventBuffer;
  config.eventBufferSize = sizeof(eventBuffer);

  if (!honch::defaultClient().begin(config)) {
    Serial.printf("honch begin failed: %s\n", honch::defaultClient().lastError());
    return;
  }
  honch::defaultClient().track("app_started");
}

void loop() {
  honch::defaultClient().tick();   // pump delivery; alias loop()
  delay(1000);
}
```

Methods return `bool` (`true` on success); `lastError()` gives the status string.
Calls are serialized on a per-instance mutex (10 ms timeout) — under contention a
call returns `false` with `lastError()` `"busy"`.

Config fields:

| Field | Default | Notes |
| --- | --- | --- |
| `apiKey`, `host`, `deviceModel`, `firmwareVersion` | — | Required. |
| `rootCaPem` | — | PEM root CA for HTTPS (required for real TLS). |
| `environment` | `production` | |
| `eventBuffer` / `eventBufferSize` | — | RAM queue backing; size also sets `max_event_bytes`. |
| `flushIntervalSeconds`, `flushMinIntervalMs`, `flushEventThreshold` | shared defaults | `flushEventThreshold` also sets batch size. |
| `transportTimeoutMs` | 8000 | Capped 10000. |
| `connectivityCallback` | — | Return `false` when offline. |
| `enableErrorTracking` | `false` | `$crash` on abnormal reset (reset reason only — no coredump/backtrace; those are ESP-IDF only). |
| `insecureSkipTlsVerify` | `false` | **Local testing only**; logs a warning. Never in production. |
| `stateStorageOps` / `eventQueueOps` | — | Durable identity / durable queue. |

`$sdk_platform` is hardcoded `arduino-esp32`; queue cap 1000; device ID defaults
to `esp32-<eFuse MAC>`.

## 3. Pump delivery (mandatory)

`tick()` (or its `loop()` alias) from the sketch `loop()` or a dedicated task.
If you use a task, give it **≥ 8192 bytes stack** for the TLS handshake, and never
call from an ISR.

## 4. Track / identify / sessions

```cpp
const honch_property_t props[] = { honch_prop("mode", honch_str("record")) };
honch::defaultClient().track("mode_changed", props, 1);

honch::defaultClient().identify("user-123");   // see identity.md
honch::defaultClient().sessionStart("recording");
honch::defaultClient().sessionEnd();
honch::defaultClient().flush();
```

## 5. TLS & durability

Uploads use `HTTPClient` over `WiFiClientSecure` to `<host>/capture`. Set
`rootCaPem` for real HTTPS; `insecureSkipTlsVerify = true` is local-only and logs
a warning. Default queue is RAM-only and identity isn't persisted (lost on reset)
— for persistence wire `eventQueueOps` (a tiered RAM+NV queue; the
`HonchDurableQueue` example shows a LittleFS cold tier) and `stateStorageOps`
(e.g. `Preferences`). If you persist the tiered queue yourself, hold the same lock
as `track()`/`tick()`.

## 6. Debugging failures

`lastError()` is a short status word; for *why*, use the structured accessors:

```cpp
if (!Honch.flush()) {
  honch_error_detail_t detail;
  Honch.lastErrorDetail(&detail);
  Serial.println(Honch.lastErrorMessage());   // e.g. "transport error: HTTP 401 ... (reason=auth_invalid_key)"
  if (detail.http_status == 401) { /* bad project key */ }
}
```

The SDK also logs that line once per distinct failure via `log_w`/`log_e`.

## Verify

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 examples/HonchBasic
```

(Or build the user's sketch / `pio run`.) On hardware: flash, open the serial
monitor, confirm `POST /capture` after Wi-Fi connects. Registered examples:
`HonchBasic`, `HonchOfflineQueue` (plus `HonchDedicatedTask`, `HonchDurableQueue`
helpers). Then run [production-checklist.md](production-checklist.md).

## Public API

`honch::defaultClient()` → singleton. `begin(config)`,
`track(name, props, count)`, `identify(id, traits, count)`,
`setProperty(key, value)`, `sessionStart(name)`, `sessionEnd()`, `flush()`,
`tick()`/`loop()`, `reset()`, `shutdown()`, `deviceId()`, `queueStats(&stats)`,
`lastError()`, `lastErrorDetail(&detail)`, `lastErrorMessage()`.
