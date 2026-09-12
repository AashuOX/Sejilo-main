## 2.0.0

* Standardized Bluetooth byte payload APIs on Dart `Uint8List` for characteristic, descriptor, local GATT server, scan advertisement, and Classic RFCOMM data.
* Updated MethodChannel payloads to send and receive typed byte data while keeping compatibility with legacy numeric lists from older native implementations.
* Updated Android, iOS, and macOS implementations to transfer native byte payloads as `ByteArray`, `Data`, or `FlutterStandardTypedData` instead of generic number lists.
* Updated the example app and documentation to use `Uint8List` for all Bluetooth byte payload examples.

## 1.0.0

* Initial release of the cross-platform Flutter Bluetooth plugin.
* Added adapter state/info, permission helpers, scanning, device lookup, and BLE GATT client APIs.
* Added Android, iOS, macOS, Linux BlueZ, Windows WinRT, and Web Bluetooth implementations.
* Added local GATT server and BLE advertising support on Android, iOS, and macOS.
* Added Android Classic RFCOMM, MTU, PHY, bonding, and connection priority helpers.
