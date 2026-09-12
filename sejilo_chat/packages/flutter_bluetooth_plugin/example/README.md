# flutter_bluetooth_plugin Example

This example is a Cupertino-based Bluetooth testing console for the
`flutter_bluetooth_plugin` package. It is designed to exercise as much of the
plugin API surface as possible from one app.

## What it covers

- Platform/version, adapter state, adapter info, permission checks, permission
  requests, Bluetooth settings, and adapter-name updates
- BLE scanning with service UUID filters, duplicate-event control, BLE/Classic
  scan modes, bonded-device loading, connected-device loading, and device lookup
- BLE connection state, service discovery, characteristic reads/writes,
  descriptor reads/writes, notifications, RSSI, MTU, maximum write length, PHY,
  connection priority, and bond/unbond flows
- Local GATT server setup, BLE advertising, scan-response data, local
  characteristic updates, notifications/indications, and service cleanup
- Android Classic RFCOMM client/server socket actions
- A live event log for every plugin event stream

## Run

```sh
flutter pub get
flutter run
```

For Web Bluetooth, run on HTTPS or localhost and trigger scanning from the app
button so the browser can open the device chooser.
