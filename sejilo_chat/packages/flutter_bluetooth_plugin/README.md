# flutter_bluetooth_plugin

[简体中文](README.zh-CN.md)

A cross-platform Flutter Bluetooth plugin for Android, iOS, macOS, Linux,
Windows, and Web. It gives Flutter apps one Dart API for the parts of Bluetooth
that are useful in real products: adapter state, runtime permissions, BLE
scanning, GATT client operations, local GATT server/peripheral mode, BLE
advertising, notifications, RSSI, MTU, PHY, bonding, Android Classic RFCOMM,
BlueZ, WinRT, and Web Bluetooth.

This package is intentionally practical rather than pretending Bluetooth is the
same everywhere. Each platform keeps its native behavior where it matters, while
unsupported capabilities are surfaced consistently.

> Unsupported behavior contract: safe stop/clear methods are no-ops, capability
> checks return `false`, unavailable numeric values return `0`, unsupported event
> streams stay empty, and operations that cannot be represented by the platform
> throw an unsupported error.

## Contents

- [What you can build](#what-you-can-build)
- [Platform capability map](#platform-capability-map)
- [Install](#install)
- [Platform setup](#platform-setup)
- [Quick start: scan first](#quick-start-scan-first)
- [Recipes](#recipes)
- [API guide by category](#api-guide-by-category)
- [Models and enums](#models-and-enums)
- [Platform notes](#platform-notes)
- [Troubleshooting](#troubleshooting)
- [Example app](#example-app)
- [License](#license)

## What you can build

- BLE central apps that scan, connect, discover services, read/write
  characteristics, subscribe to notifications, and read descriptors.
- BLE peripheral prototypes on Android, iOS, and macOS with local GATT services,
  advertising, read/write handling, and notifications to centrals.
- Android Classic Bluetooth RFCOMM clients or servers for SPP-style devices.
- Desktop BLE tooling backed by BlueZ on Linux and WinRT on Windows.
- Web Bluetooth flows that use the browser chooser and site-authorized services.
- Diagnostic apps that expose adapter state, permissions, bonded devices,
  connected devices, RSSI, MTU, PHY, and platform raw fields.

## Platform capability map

Legend: `Full` = implemented by the native backend, `Partial` = implemented with
platform constraints, `No` = not available on that platform.

| Capability | Android | iOS | macOS | Linux | Windows | Web |
| --- | --- | --- | --- | --- | --- | --- |
| Adapter state and adapter info | Full | Full | Full | BlueZ | WinRT | Availability API |
| Permission helpers | Runtime permissions | CoreBluetooth auth | CoreBluetooth auth | Availability mapping | Availability mapping | No global preflight |
| BLE scan | Full | Full | Full | BlueZ discovery | BLE advertisements | Browser chooser |
| Service UUID scan filters | Full | Full | Full | BlueZ filter | Advertisement filter | Chooser filter |
| Classic discovery mode | Full | No | No | BlueZ discovery only | No | No |
| Bonded/paired devices | Full | No public list | No public list | BlueZ paired devices | Paired BLE best effort | Site-authorized devices |
| Connected devices | Full | Service-filtered lookup | Service-filtered lookup | BlueZ connected devices | Plugin-known devices | Site-authorized connected devices |
| BLE GATT client | Full | Full | Full | Full | Full | Authorized services only |
| Characteristic notify/indicate | Full | Full | Full | Full | Full | Full |
| Descriptor read/write | Full | Full | Full | Full | Full | Partial; use notify API for CCCD |
| RSSI | Connected RSSI | Connected RSSI | Connected RSSI | Cached advertisement RSSI | Cached advertisement RSSI | No |
| MTU request | Full | Returns max write length | Returns max write length | No | No | No |
| Max write length | MTU - 3 | Full | Full | No | No | No |
| PHY read/write | Android 8+ | No | No | No | No | No |
| Connection priority | Full | No | No | No | No | No |
| Bond create/remove | Full | No | No | BlueZ pair/remove | No | No |
| Local GATT server | Full | Full | Full | No | No | No |
| BLE advertising | Full | Partial | Partial | No | No | No |
| Android Classic RFCOMM | Full | No | No | No | No | No |

## Install

Add the package to your app:

```yaml
dependencies:
  flutter_bluetooth_plugin: ^2.0.0
```

Import the public API:

```dart
import 'dart:typed_data';

import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin.dart';
```

Create one plugin object wherever you manage Bluetooth work:

```dart
final bluetooth = FlutterBluetoothPlugin();
```

## Platform setup

Bluetooth permissions and platform policies are the most common source of
confusing scan results. Configure the host app first, then call
`requestPermissions()` from your UI before scanning, connecting, or advertising.

### Android

The plugin manifest contributes the common Bluetooth permissions and features to
the host app:

- Android 12+ uses `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and
  `BLUETOOTH_ADVERTISE` as runtime permissions.
- Android 6-11 needs location permission for BLE scan results, usually
  `ACCESS_FINE_LOCATION`.
- Android 11 and lower also use `BLUETOOTH` and `BLUETOOTH_ADMIN`.

Recommended app flow:

```dart
final permissions = await bluetooth.requestPermissions();
final state = await bluetooth.getAdapterState();

if (state != BluetoothAdapterState.poweredOn) {
  final opened = await bluetooth.requestEnable();
  if (!opened) await bluetooth.openBluetoothSettings();
}
```

### iOS

Add usage descriptions to the host app `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to scan, connect, and exchange data with nearby devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to communicate with nearby peripherals.</string>
```

Notes:

- `requestPermissions()` initializes CoreBluetooth so the system can ask for
  authorization.
- Apps cannot turn Bluetooth on programmatically; guide the user to Settings.
- iOS does not expose Classic Bluetooth RFCOMM to third-party apps.

### macOS

Add a Bluetooth usage description to `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to scan, connect, and exchange data with nearby devices.</string>
```

For sandboxed apps, enable the Bluetooth entitlement:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

### Linux

Linux support uses BlueZ over system DBus.

- `requestPermissions()` maps adapter availability to a permission status; it
  does not show a runtime permission dialog.
- `requestEnable()` attempts to set the BlueZ adapter `Powered` property.
- `openBluetoothSettings()` tries common desktop Bluetooth settings tools such
  as GNOME Control Center, Blueman, and KDE Bluetooth settings.
- The user may need BlueZ running and enough DBus permissions for adapter and
  device operations.

### Windows

Windows support uses WinRT BLE APIs.

- `requestPermissions()` reports whether a BLE adapter is available.
- `openBluetoothSettings()` opens the Windows Bluetooth settings page.
- Current Windows support focuses on BLE central/GATT client behavior.

### Web

Web Bluetooth is not passive scanning. It is a browser-mediated chooser.

- The page must run in a secure context: HTTPS or localhost.
- `startScan()` must be called from a user gesture such as a button tap.
- If you need to access GATT services after connecting, pass those service UUIDs
  to `startScan(serviceUuids: [...])`; browsers use that list for service
  authorization.
- Without service UUIDs, `acceptAllDevices` is used so users can see nearby BLE
  devices, but later GATT access may be limited.

## Quick start: scan first

For first-run diagnostics, scan without a service filter. Many devices do not
advertise every service UUID they expose after connection, so filtering too early
can make a healthy scanner look empty.

```dart
final bluetooth = FlutterBluetoothPlugin();

await bluetooth.requestPermissions();

final adapterState = await bluetooth.getAdapterState();
if (adapterState != BluetoothAdapterState.poweredOn) {
  final opened = await bluetooth.requestEnable();
  if (!opened) await bluetooth.openBluetoothSettings();
}

final scanSub = bluetooth.scanResults.listen((result) {
  final name = result.device.name ?? result.localName ?? 'Unnamed';
  print('$name ${result.device.id} RSSI=${result.rssi}');
});

await bluetooth.startScan(
  serviceUuids: const <String>[], // Empty means no BLE service filter.
  timeout: const Duration(seconds: 15),
  allowDuplicates: false,
  scanMode: BluetoothScanMode.ble,
);

await Future<void>.delayed(const Duration(seconds: 15));
await bluetooth.stopScan();
await scanSub.cancel();
```

When you already know the target service, use a filter deliberately:

```dart
await bluetooth.startScan(
  serviceUuids: const <String>['0000fff0-0000-1000-8000-00805f9b34fb'],
  timeout: const Duration(seconds: 10),
);
```

## Recipes

### Connect, discover, read, write, notify

```dart
await bluetooth.connect(deviceId, timeout: const Duration(seconds: 15));

final services = await bluetooth.discoverServices(deviceId);
final service = services.first;
final characteristic = service.characteristics.first;

final value = await bluetooth.readCharacteristic(
  deviceId: deviceId,
  serviceUuid: service.uuid,
  characteristicUuid: characteristic.uuid,
);

await bluetooth.writeCharacteristic(
  deviceId: deviceId,
  serviceUuid: service.uuid,
  characteristicUuid: characteristic.uuid,
  value: value,
  writeType: BluetoothWriteType.withResponse,
);

final notifySub = bluetooth.characteristicValues.listen((event) {
  print('${event.characteristicUuid}: ${event.value}');
});

await bluetooth.setCharacteristicNotification(
  deviceId: deviceId,
  serviceUuid: service.uuid,
  characteristicUuid: characteristic.uuid,
  enable: true,
);
```

### Read and write descriptors

```dart
const cccd = '00002902-0000-1000-8000-00805f9b34fb';

final descriptorValue = await bluetooth.readDescriptor(
  deviceId: deviceId,
  serviceUuid: serviceUuid,
  characteristicUuid: characteristicUuid,
  descriptorUuid: cccd,
);

await bluetooth.writeDescriptor(
  deviceId: deviceId,
  serviceUuid: serviceUuid,
  characteristicUuid: characteristicUuid,
  descriptorUuid: cccd,
  value: descriptorValue,
);
```

For notification subscription, prefer `setCharacteristicNotification()` over
writing the CCCD directly, especially on Web.

### RSSI, MTU, maximum write length, and PHY

```dart
final rssi = await bluetooth.readRssi(deviceId);
final mtu = await bluetooth.requestMtu(deviceId, 247);
final maxWrite = await bluetooth.getMaximumWriteLength(
  deviceId,
  withoutResponse: true,
);

final phy = await bluetooth.readPhy(deviceId);
if (phy.txPhy != BluetoothPhy.unknown) {
  await bluetooth.setPreferredPhy(
    deviceId: deviceId,
    txPhy: BluetoothPhy.le2m,
    rxPhy: BluetoothPhy.le2m,
  );
}
```

### Bonding and connection priority

```dart
final bonded = await bluetooth.createBond(deviceId);

final priorityChanged = await bluetooth.requestConnectionPriority(
  deviceId,
  BluetoothConnectionPriority.high,
);
```

`requestConnectionPriority()` is Android-only. `createBond()` and `removeBond()`
are implemented on Android and Linux.

### Local GATT server and BLE advertising

```dart
const serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
const characteristicUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

if (await bluetooth.isPeripheralSupported()) {
  await bluetooth.setGattServerServices(
    <BluetoothGattService>[
      BluetoothGattService(
        uuid: serviceUuid,
        characteristics: <BluetoothGattCharacteristic>[
          BluetoothGattCharacteristic(
            uuid: characteristicUuid,
            serviceUuid: serviceUuid,
            properties: <String>[
              'read',
              'write',
              'writeWithoutResponse',
              'notify',
            ],
            permissions: <String>['read', 'write'],
            value: Uint8List.fromList(<int>[72, 101, 108, 108, 111]),
          ),
        ],
      ),
    ],
  );

  await bluetooth.startAdvertising(
    advertisementData: const BluetoothAdvertisementData(
      localName: 'Flutter BT',
      serviceUuids: <String>[serviceUuid],
      includeDeviceName: true,
      includeTxPowerLevel: true,
    ),
    settings: const BluetoothAdvertisingSettings(
      mode: BluetoothAdvertisingMode.lowLatency,
      txPowerLevel: BluetoothTxPowerLevel.high,
      connectable: true,
    ),
  );
}

final serverSub = bluetooth.gattServerRequests.listen((event) {
  print('${event.event} from ${event.deviceId}: ${event.value}');
});
```

Update and notify a local characteristic:

```dart
await bluetooth.updateLocalCharacteristicValue(
  serviceUuid: serviceUuid,
  characteristicUuid: characteristicUuid,
  value: Uint8List.fromList(<int>[1, 2, 3]),
);

final sent = await bluetooth.notifyGattServerCharacteristic(
  serviceUuid: serviceUuid,
  characteristicUuid: characteristicUuid,
  value: Uint8List.fromList(<int>[1, 2, 3]),
  confirm: false,
);
```

### Android Classic RFCOMM

```dart
const sppUuid = '00001101-0000-1000-8000-00805f9b34fb';

await bluetooth.startClassicServer(
  serviceUuid: sppUuid,
  serviceName: 'FlutterBluetoothPlugin',
);

await bluetooth.connectClassic(
  deviceId: macAddress,
  serviceUuid: sppUuid,
  secure: true,
  timeout: const Duration(seconds: 15),
);

final classicStateSub = bluetooth.classicConnectionState.listen((event) {
  print('${event.deviceId}: ${event.state} ${event.error ?? ''}');
});

final classicDataSub = bluetooth.classicData.listen((event) {
  print('Classic ${event.deviceId}: ${event.value}');
});

await bluetooth.writeClassic(macAddress, Uint8List.fromList(<int>[1, 2, 3]));
```

## API guide by category

### Adapter and permissions

| API | Purpose | Platform notes |
| --- | --- | --- |
| `getPlatformVersion()` | Returns a platform version string. | Android/iOS/macOS/Linux/Windows/Web all return platform-specific text. |
| `isSupported()` | Checks whether Bluetooth is available. | Web also requires secure context and Web Bluetooth support. |
| `getAdapterState()` | Reads `unknown`, `unsupported`, `unauthorized`, `poweredOff`, `poweredOn`, `resetting`, `turningOn`, or `turningOff`. | Linux maps BlueZ `Powered`; Web maps browser availability. |
| `adapterState` | Emits adapter state changes. | Linux and Web send an initial mapped state when possible. |
| `getAdapterInfo()` | Returns name/address when public plus capability flags. | Android exposes the richest capability set; Apple/Web hide hardware addresses. |
| `isScanning()` | Reports whether scanning/discovery is active. | Android includes BLE and Classic discovery; Web means chooser is open. |
| `setAdapterName(name)` | Attempts to change the local adapter alias/name. | Android and Linux only; other platforms return `false`. |
| `checkPermissions()` | Reads permission state without prompting. | Android returns per-permission keys; iOS/macOS return `bluetooth`. |
| `requestPermissions()` | Requests or initializes permission flow. | Web cannot show a global prompt; use `startScan()` from a user gesture. |
| `requestEnable()` | Asks the user or system to enable Bluetooth. | Android shows the system prompt; Linux writes BlueZ `Powered`; others return `false`. |
| `openBluetoothSettings()` | Opens the relevant Bluetooth/app settings page. | Web is a no-op because browsers do not expose a standard settings URL. |

### Discovery and device lookup

| API | Purpose | Platform notes |
| --- | --- | --- |
| `startScan(serviceUuids, timeout, allowDuplicates, scanMode)` | Starts BLE scan, Classic discovery, or Web chooser. | Empty `serviceUuids` means no BLE filter; best for diagnostics. |
| `stopScan()` | Stops active scan/discovery. | Web cannot close the native chooser, but clears local selecting state. |
| `scanResults` | Emits `BluetoothScanResult`. | Subscribe before `startScan()` to avoid missing early results. |
| `getBondedDevices()` | Lists paired/bonded devices. | Android/Linux are most complete; Apple has no public paired list. |
| `getConnectedDevices(serviceUuids)` | Lists connected devices. | iOS/macOS/Web should usually pass target service UUIDs. |
| `getDevice(deviceId)` | Looks up one known device. | Device IDs are platform-specific; keep IDs from scan results. |
| `getDevices(deviceIds)` | Batch lookup for known IDs. | Useful when combining scan, bonded, and connected caches. |

### BLE connection and GATT client

| API | Purpose | Platform notes |
| --- | --- | --- |
| `connect(deviceId, autoConnect, timeout)` | Opens a BLE GATT connection. | `autoConnect` is Android-only; Web device must be chooser-authorized. |
| `disconnect(deviceId)` | Closes the BLE connection. | Android treats not-connected as success; Apple may report unknown device errors. |
| `getConnectionState(deviceId)` | Reads current connection state. | Pair with the `connectionState` stream for UI. |
| `connectionState` | Emits `BluetoothConnectionStateEvent`. | Android events may include native GATT status. |
| `discoverServices(deviceId)` | Discovers GATT services/characteristics/descriptors. | Web can discover only services authorized during chooser selection. |
| `readCharacteristic(...)` | Reads a characteristic value. | Requires a connected device and service/characteristic UUIDs. |
| `writeCharacteristic(..., writeType)` | Writes a characteristic value. | `withResponse` is safest; `withoutResponse` is faster when supported. |
| `setCharacteristicNotification(..., enable)` | Subscribes/unsubscribes notifications or indications. | Uses native subscription APIs; prefer this over manual CCCD writes. |
| `characteristicValues` | Emits notification/indication/read value events. | Stream payload is `BluetoothCharacteristicValue`. |
| `readDescriptor(...)` | Reads a descriptor value. | Web requires authorized parent service. |
| `writeDescriptor(...)` | Writes a descriptor value. | Web does not allow direct CCCD notification subscription writes. |
| `descriptorValues` | Emits descriptor read/write value events. | Useful for diagnostics. |

### Link diagnostics and Android BLE extras

| API | Purpose | Platform notes |
| --- | --- | --- |
| `readRssi(deviceId)` | Reads signal strength. | Android/iOS/macOS require connection; Linux/Windows return cached advertisement RSSI; Web unsupported. |
| `rssiUpdates` | Emits `BluetoothRssiEvent`. | Web stream stays empty. |
| `requestMtu(deviceId, mtu)` | Negotiates or reads MTU/write length. | Android negotiates MTU; iOS/macOS return max write length; others return `0`. |
| `getMaximumWriteLength(deviceId, withoutResponse)` | Returns writable payload size. | Android uses known MTU; iOS/macOS use native max write length; others return `0`. |
| `mtuUpdates` | Emits MTU/write-length events. | Android emits after negotiation; iOS/macOS emit current write length. |
| `setPreferredPhy(deviceId, txPhy, rxPhy, phyOptions)` | Requests BLE PHY. | Android 8+ only. |
| `readPhy(deviceId)` | Reads current BLE PHY. | Non-Android platforms return `unknown`. |
| `phyUpdates` | Emits PHY changes. | Mainly Android 8+. |
| `requestConnectionPriority(deviceId, priority)` | Requests `balanced`, `high`, or `lowPower` connection priority. | Android only; other platforms return `false`. |
| `createBond(deviceId)` | Starts pairing/bonding. | Android and Linux. |
| `removeBond(deviceId)` | Removes pairing/bonding. | Android and Linux. |
| `bondState` | Emits bond state events. | Android/Linux only. |

### Peripheral, local GATT server, and advertising

| API | Purpose | Platform notes |
| --- | --- | --- |
| `isPeripheralSupported()` | Checks local peripheral/advertising support. | Android/iOS/macOS can support it; Linux/Windows/Web return `false`. |
| `setGattServerServices(services)` | Registers local GATT services. | Android/iOS/macOS only. |
| `clearGattServerServices()` | Removes local GATT services. | No-op where unsupported. |
| `startAdvertising(advertisementData, scanResponse, settings)` | Starts BLE advertising. | Android supports the most fields; iOS/macOS use local name and service UUIDs. |
| `stopAdvertising()` | Stops BLE advertising. | No-op where unsupported. |
| `advertisingState` | Emits advertising started/stopped/error events. | Android includes error codes when available. |
| `updateLocalCharacteristicValue(...)` | Updates the cached local characteristic value. | Use before read responses or before notify. |
| `notifyGattServerCharacteristic(..., confirm)` | Sends notification or indication from the local server. | Android can target a device and confirm indications; iOS/macOS notify subscribed centrals. |
| `gattServerRequests` | Emits local server events. | Read/write/subscription events on Android/iOS/macOS. |

### Android Classic RFCOMM

| API | Purpose | Platform notes |
| --- | --- | --- |
| `connectClassic(deviceId, serviceUuid, secure, timeout)` | Connects to an RFCOMM service. | Android only; `deviceId` is usually MAC address. |
| `startClassicServer(serviceUuid, serviceName, secure)` | Starts an RFCOMM server socket. | Android only. |
| `stopClassicServer()` | Stops the RFCOMM server socket. | No-op where unsupported. |
| `disconnectClassic(deviceId)` | Disconnects a Classic RFCOMM connection. | Android only. |
| `writeClassic(deviceId, value)` | Writes bytes to an RFCOMM connection. | Android only. |
| `classicConnectionState` | Emits Classic connection state events. | Android only. |
| `classicData` | Emits received RFCOMM bytes. | Android only. |

## Models and enums

### Core enums

- `BluetoothAdapterState`: `unknown`, `unsupported`, `unauthorized`,
  `poweredOff`, `poweredOn`, `resetting`, `turningOn`, `turningOff`.
- `BluetoothPermissionStatus`: `unknown`, `notDetermined`, `granted`, `denied`,
  `restricted`, `permanentlyDenied`, `notApplicable`.
- `BluetoothScanMode`: `ble`, `classic`, `dual`.
- `BluetoothConnectionState`: `disconnected`, `connecting`, `connected`,
  `disconnecting`, `unknown`.
- `BluetoothBondState`: `none`, `bonding`, `bonded`, `unknown`.
- `BluetoothWriteType`: `withResponse`, `withoutResponse`.
- `BluetoothConnectionPriority`: `balanced`, `high`, `lowPower`.
- `BluetoothAdvertisingMode`: `lowPower`, `balanced`, `lowLatency`.
- `BluetoothTxPowerLevel`: `ultraLow`, `low`, `medium`, `high`.
- `BluetoothPhy`: `le1m`, `le2m`, `leCoded`, `unknown`.

### Data models

- `BluetoothAdapterInfo`: adapter support, state, name, address, BLE support,
  Android capability flags, discovery state, and raw platform fields.
- `BluetoothDevice`: `id`, `name`, `address`, `type`, `isConnected`,
  `isBonded`, and `raw` fields.
- `BluetoothScanResult`: device, RSSI, local name, service UUIDs, manufacturer
  data, service data, TX power, connectable flag, and raw fields.
- `BluetoothGattService`: service UUID, primary flag, included services, and
  characteristics.
- `BluetoothGattCharacteristic`: UUID, service UUID, properties, permissions,
  value, descriptors, plus helpers such as `canRead`, `canWrite`, `canNotify`,
  and `canIndicate`.
- `BluetoothGattDescriptor`: descriptor UUID, parent characteristic UUID, and
  value.
- `BluetoothAdvertisementData`: local name, include-device-name flag,
  include-TX-power flag, service UUIDs, manufacturer data, and service data.
- `BluetoothAdvertisingSettings`: advertising mode, TX power, connectable flag,
  and timeout.

### Event models

- `BluetoothConnectionStateEvent`
- `BluetoothCharacteristicValue`
- `BluetoothDescriptorValue`
- `BluetoothRssiEvent`
- `BluetoothMtuEvent`
- `BluetoothBondStateEvent`
- `BluetoothAdvertisingStateEvent`
- `BluetoothGattServerRequest`
- `BluetoothPhyEvent`
- `BluetoothClassicConnectionEvent`
- `BluetoothClassicDataEvent`

### Conversion helpers

These helpers convert native string values to Dart enums and fall back to the
corresponding `unknown` value when input is missing or unrecognized:

- `bluetoothAdapterStateFromString(value)`
- `bluetoothPermissionStatusFromString(value)`
- `bluetoothConnectionStateFromString(value)`
- `bluetoothBondStateFromString(value)`
- `bluetoothPhyFromString(value)`

## Platform notes

### Android

Android has the broadest API surface in this package. It supports BLE central,
BLE peripheral, local GATT server, advertising, bonding, MTU, PHY, connection
priority, and Classic RFCOMM. Android 12+ permission state is split across scan,
connect, and advertise permissions, so always check the returned permission map.

### iOS and macOS

Apple platforms support BLE central and CoreBluetooth peripheral mode, but do
not expose Classic Bluetooth RFCOMM. Apps cannot enable Bluetooth directly. For
connected-device lookup on iOS/macOS, pass target service UUIDs when possible.
Peripheral advertising uses local name and service UUIDs; Android-only fields
such as manufacturer data in advertising are ignored.

### Linux

The Linux backend talks to BlueZ on system DBus. BLE GATT client APIs are
implemented, bonded/connected devices come from BlueZ objects, and RSSI is based
on cached advertisements. BlueZ discovery can use LE, BR/EDR, or auto transport,
but this package does not implement Classic RFCOMM sockets on Linux.

### Windows

The Windows backend uses WinRT BLE APIs. It supports BLE advertisement scanning,
GATT client operations, paired-device lookup best effort, and cached RSSI. Local
GATT server, advertising, Classic RFCOMM, MTU negotiation, and PHY control are
not implemented.

### Web

The Web backend wraps Web Bluetooth. It cannot passively scan; `startScan()`
opens the browser chooser and returns one selected device as a scan result. The
browser decides what devices and services are visible, and GATT access is limited
to services authorized during selection.

## Troubleshooting

### Scan returns no devices

- Clear `serviceUuids` first. A UUID filter matches advertised services, not
  every service the device may reveal after connection.
- Subscribe to `scanResults` before calling `startScan()`.
- Confirm `getAdapterState()` is `BluetoothAdapterState.poweredOn`.
- On Android, call `requestPermissions()` and grant nearby-devices/Bluetooth and
  location permissions as required by the OS version.
- On iOS/macOS, confirm Bluetooth permission is granted in system settings.
- On Web, call `startScan()` directly from a user gesture and run on HTTPS or
  localhost.
- Remember that iOS, macOS, Windows, and Web do not show Classic-only devices.
  Android needs `BluetoothScanMode.classic` or `BluetoothScanMode.dual` for
  Classic discovery.

### I can scan but cannot discover services on Web

Pass target services to `startScan(serviceUuids: [...])` before connecting. Web
Bluetooth uses the chooser options to decide which GATT services the site may
access.

### Notifications do not arrive

- Check that the characteristic properties include `notify` or `indicate`.
- Use `setCharacteristicNotification(..., enable: true)` instead of manually
  writing the CCCD.
- Keep the stream subscription alive for `characteristicValues`.
- Some devices require pairing/bonding before encrypted notifications work.

### Advertising fails on Android

Traditional BLE advertising has a small payload budget. Start with only a short
`localName` and one service UUID, then add manufacturer data or scan response
data after the minimal payload works.

## Example app

The `example/` app is a Cupertino-style Bluetooth testing console. It is useful
for development because it exercises most plugin APIs from one screen:

- Platform/version, adapter, permission, scan, and settings diagnostics.
- BLE scan mode, duplicate events, bonded devices, connected devices, and device
  lookup APIs.
- BLE connection state, service discovery, characteristic/descriptor IO,
  notifications, RSSI, MTU, max write length, PHY, connection priority, and
  bonding actions.
- Local GATT server setup, advertising, local value updates, notifications, and
  service cleanup.
- Android Classic RFCOMM client/server socket actions.
- Live event log for every plugin event stream.

The example now starts with an empty Service UUID filter so a first scan shows
nearby BLE devices immediately. Enter a UUID only when you intentionally want a
filtered scan.

Run it with:

```sh
cd example
flutter pub get
flutter run
```

For Web Bluetooth, run on HTTPS or localhost and press the scan button inside
the app so the browser can open the device chooser.

## License

This project is released under the [MIT License](LICENSE).
