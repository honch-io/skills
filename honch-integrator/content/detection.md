# Detecting the integration path

Classify the repo into **exactly one** path before planning. Inspect the files,
don't assume. If two paths seem plausible, pick by what the code is actually
*built and run as*, and state your reasoning. If nothing fits, the answer is
almost always **BYO HTTP** — anything that can make an HTTPS request can send to
Honch.

## Decision order

Check in this order; take the first match.

1. **ESP-IDF** — ESP32 firmware built with Espressif's IDF.
   - Signals: `idf.py`, a top-level `CMakeLists.txt` with
     `idf_component_register(...)`, an `sdkconfig` / `sdkconfig.defaults`,
     `main/` with `app_main(`, `managed_components/`, `dependencies.lock`.
   - → [esp-idf.md](esp-idf.md)

2. **Arduino (ESP32)** — ESP32 firmware on the Arduino framework.
   - Signals: `platformio.ini` with `framework = arduino` and an `esp32` board;
     or `.ino` sketches with `setup()`/`loop()` and `#include <WiFi.h>`.
   - Note: a `platformio.ini` with `framework = espidf` is **ESP-IDF**, not this.
   - → [arduino.md](arduino.md)

3. **MicroPython** — MicroPython firmware/app.
   - Signals: `.py` files using `machine`, `network`, `time.sleep`, `boot.py` /
     `main.py` on a board; a MicroPython build tree (`ports/unix`, `ports/esp32`);
     mention of `mip` / `manifest.py`. CircuitPython is **out of scope**.
   - → [micropython.md](micropython.md)

4. **C / POSIX** — native C/C++ for Linux/macOS or embedded Linux (a gateway,
   daemon, or CLI), **not** ESP32 firmware.
   - Signals: `CMakeLists.txt` / `Makefile` building a host binary, `main(int argc`,
     libcurl/pthreads usage, a systemd unit, a Yocto/Buildroot recipe.
   - → [c-posix.md](c-posix.md)

5. **Relay (React Native / Swift)** — a **companion mobile app** whose job is to
   forward Honch frames a device sends over BLE. Only this when the device cannot
   upload directly and the app is the uploader.
   - Signals: a React Native app (`package.json` with `react-native`) or an iOS
     app (`*.xcodeproj`, `Package.swift`, Swift sources) **plus** a BLE story
     (CoreBluetooth, `react-native-ble-plx`, talk of device frames/ACKs).
   - Caveat: a normal mobile app that just wants to send its *own* analytics is
     **BYO HTTP**, not a relay. The relay is specifically for forwarding an
     offline device's frames.
   - → [relay.md](relay.md)

6. **BYO HTTP (JSON)** — everything else: any app, backend, gateway, or script in
   any language that can POST JSON. This is the catch-all and a perfectly good
   integration, not a fallback to apologize for.
   - Signals: a web/back-end service (Node, Python, Go, Rust, Ruby, …), a mobile
     app sending its own events, anything with an HTTP client and no matching
     native SDK above.
   - → [byo-http.md](byo-http.md)

## When the repo is mixed

Monorepos and device+app products can contain more than one path (e.g. ESP-IDF
firmware *and* a React Native companion app). That's fine — confirm with the user
which component they want instrumented now, integrate that one path end-to-end,
and note the others as separate follow-ups. Don't try to wire several at once.

## When you genuinely can't tell

Ask one targeted question: "What does this codebase build and run as — ESP32
firmware, an embedded-Linux binary, a MicroPython board, a mobile app, or a
service that can make HTTPS requests?" The answer maps directly to a path above.
