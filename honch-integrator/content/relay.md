# Path: Relay (React Native / Swift companion app)

**Preview.** A relay is **not a device analytics SDK** — it has no `track` or
`identify`. Use it **only** when firmware cannot upload directly and a companion
mobile app forwards the device's Honch frames over BLE. The relay receives frames,
durably reassembles compact messages, builds ACKs, and uploads to Honch.

If the mobile app just wants to send its *own* events, that's **not** a relay —
use [byo-http.md](byo-http.md) instead.

## The host-owned Bluetooth model (state this up front)

**Bluetooth is owned by the app, not the relay.** The relay never scans, connects,
subscribes, requests BLE permissions, or writes characteristics. The app owns the
BLE stack and hands frame bytes in; the relay returns ACK bytes **only after the
frame is durably stored**, and the app writes those bytes back to the device's ACK
characteristic. An ACK is 9 bytes: version `0x01` + big-endian uint64 sequence.
BLE service/characteristic UUIDs and the frame format are in the relay-chunks spec.

---

## React Native — `@honch/react-native-relay` (Preview · 0.1.0)

### 1. Install

```bash
bun add @honch/react-native-relay
```

Peer dep `react-native >= 0.72`. For the durable store also add
`react-native-mmkv` (optional). Ships TS source — Metro transpiles it, no build step.

### 2. Wire the relay

```ts
import { NativeModules } from "react-native";
import { createMMKV } from "react-native-mmkv";
import {
  createMmkvRelayStore, createMobileRelay, createRelayNativeBindings,
} from "@honch/react-native-relay";

const bindings = createRelayNativeBindings(NativeModules.HonchReactNativeRelay);

export const relay = createMobileRelay({
  durableStore: createMmkvRelayStore(createMMKV({ id: "honch-relay" })),
  uploaderConfig: {
    endpointUrl: "https://i.honch.io",
    projectKey: "your-project-key",        // keep out of source control
    relayId: "mobile-relay-01",
    relaySdkPlatform: "react-native",
    relaySdkVersion: "0.1.0",
    streamId: (m) => `relay-${m.deviceId}`,
    messageId: (m) => Number(m.sequence),
  },
  schedulerNative: bindings.schedulerNative,
});
```

`createMobileRelay` returns `{ receiveFrame, pending, startUploadScheduler,
stopUploadScheduler, drainUploads }`.

### 3. Hand frames in and ACK

```ts
await relay.receiveFrame(deviceId, frameBytes, {
  acknowledge: async ({ ackBytes }) => {
    await writeAckCharacteristic(deviceId, ackBytes);   // YOUR BLE write
  },
});
```

The relay calls `acknowledge` only after durable storage. **If the device never
gets an ACK, confirm your `acknowledge` callback actually performs the BLE write**
— the relay does not touch Bluetooth.

### 4. Upload + native requirements

Uploads add relay headers (`X-Honch-Relay-Id`, `X-Honch-Relay-SDK-Platform`,
`X-Honch-Relay-SDK-Version`) on the standard `/capture` contract. Result codes:
`204`/`202` accepted; `408/409/429/5xx` retry (1s→5min, ±25% jitter); `400/401/
404/413/415/422` drop.

- **iOS:** `NSBluetoothAlwaysUsageDescription`, `bluetooth-central` background
  mode. No native background upload module ships in 0.1.0 — call `drainUploads()`
  from the foreground.
- **Android:** `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` (and location where required),
  plus `androidx.work:work-runtime` for the `HonchRelayUpload` headless task.

The package does not merge BLE/location/notification permissions into your
manifest — declare what your app needs.

### Verify

Build the RN app (`bun run …` / Metro). On device: feed a real device frame to
`receiveFrame`, confirm an ACK is written back and a `POST /capture` (with relay
headers) goes out. Then run [production-checklist.md](production-checklist.md).

---

## Swift / iOS — `HonchSwiftRelay` (Coming soon)

The Swift relay's source exists but **there is no published SwiftPM distribution
yet** — no `.package(url:)` line to add. If the user needs the iOS relay today,
tell them to contact support@honch.io. Until it ships at a repo root with a semver
tag, treat this as a planned API, not an integration you can complete.

Planned surface (an actor):

```swift
public actor HonchRelay {
    init(store:config:uploader:scheduler:nowMs:random:)
    func receiveFrame(deviceId:frameBytes:acknowledge:) async throws -> RelayFrameReceipt
    func pending() async throws -> [StoredRelayMessage]
    func startUploadScheduler(); func stopUploadScheduler(); func drainUploads() async
}
```

`HonchRelayConfig` defaults `endpointURL` to `https://i.honch.io`,
`relaySdkPlatform` to `ios`. For iOS today, the working reference is the React
Native relay above.
