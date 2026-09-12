import Cocoa
import CoreBluetooth
import FlutterMacOS

/// macOS implementation backed by CoreBluetooth.
///
/// CoreBluetooth on macOS matches the iOS BLE central/peripheral APIs closely,
/// but it still does not expose public Classic RFCOMM, adapter renaming,
/// programmatic Bluetooth enabling, bonding management, connection priority, or PHY control.
public class FlutterBluetoothPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate {
  private var centralManager: CBCentralManager?
  private var peripheralManager: CBPeripheralManager?
  private var eventSink: FlutterEventSink?
  private var scanTimer: Timer?
  private var peripherals: [String: CBPeripheral] = [:]
  private var isAdvertising = false

  private var pendingPermissionResults: [FlutterResult] = []
  private var pendingConnectResults: [String: FlutterResult] = [:]
  private var pendingConnectTimers: [String: Timer] = [:]
  private var pendingDiscoveries: [String: ServiceDiscoverySession] = [:]
  private var pendingCharacteristicReads: [String: FlutterResult] = [:]
  private var pendingCharacteristicWrites: [String: FlutterResult] = [:]
  private var pendingDescriptorReads: [String: FlutterResult] = [:]
  private var pendingDescriptorWrites: [String: FlutterResult] = [:]
  private var pendingNotificationResults: [String: FlutterResult] = [:]
  private var pendingRssiResults: [String: FlutterResult] = [:]
  private var pendingAdvertisingResult: FlutterResult?
  private var localCharacteristics: [String: CBMutableCharacteristic] = [:]
  private var localCharacteristicValues: [String: Data] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "flutter_bluetooth_plugin", binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(name: "flutter_bluetooth_plugin/events", binaryMessenger: registrar.messenger)
    let instance = FlutterBluetoothPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "isSupported":
      let manager = ensureCentralManager()
      result(manager.state != .unsupported)
    case "getAdapterState":
      result(adapterStateString(ensureCentralManager().state))
    case "getAdapterInfo":
      result(adapterInfoMap())
    case "isScanning":
      result(centralManager?.isScanning == true)
    case "setAdapterName":
      // CoreBluetooth does not allow apps to rename the host Bluetooth adapter on macOS.
      result(false)
    case "checkPermissions":
      result(permissionMap())
    case "requestPermissions":
      handleRequestPermissions(result: result)
    case "requestEnable":
      // macOS apps cannot programmatically power Bluetooth on; callers should open settings.
      result(false)
    case "openBluetoothSettings":
      openBluetoothSettings(result: result)
    case "startScan":
      startScan(arguments: call.arguments, result: result)
    case "stopScan":
      stopScan(result: result)
    case "getBondedDevices":
      result([])
    case "getConnectedDevices":
      getConnectedDevices(arguments: call.arguments, result: result)
    case "getDevice":
      getDevice(arguments: call.arguments, result: result)
    case "getDevices":
      getDevices(arguments: call.arguments, result: result)
    case "connect":
      connect(arguments: call.arguments, result: result)
    case "disconnect":
      disconnect(arguments: call.arguments, result: result)
    case "getConnectionState":
      getConnectionState(arguments: call.arguments, result: result)
    case "discoverServices":
      discoverServices(arguments: call.arguments, result: result)
    case "readCharacteristic":
      readCharacteristic(arguments: call.arguments, result: result)
    case "writeCharacteristic":
      writeCharacteristic(arguments: call.arguments, result: result)
    case "setCharacteristicNotification":
      setCharacteristicNotification(arguments: call.arguments, result: result)
    case "readDescriptor":
      readDescriptor(arguments: call.arguments, result: result)
    case "writeDescriptor":
      writeDescriptor(arguments: call.arguments, result: result)
    case "readRssi":
      readRssi(arguments: call.arguments, result: result)
    case "requestMtu":
      requestMtu(arguments: call.arguments, result: result)
    case "getMaximumWriteLength":
      getMaximumWriteLength(arguments: call.arguments, result: result)
    case "setPreferredPhy":
      // macOS CoreBluetooth does not expose BLE PHY selection; keep this as a no-op
      // so the cross-platform Future<void> API can be called safely.
      result(nil)
    case "readPhy":
      result(["deviceId": (call.arguments as? [String: Any])?["deviceId"] as? String ?? "", "txPhy": "unknown", "rxPhy": "unknown"])
    case "requestConnectionPriority":
      // Android-only connection priority hint; CoreBluetooth manages this automatically.
      result(false)
    case "createBond", "removeBond":
      // Pairing is system-managed on macOS and not exposed as create/remove bond APIs.
      result(false)
    case "isPeripheralSupported":
      result(true)
    case "startAdvertising":
      startAdvertising(arguments: call.arguments, result: result)
    case "stopAdvertising":
      stopAdvertising(result: result)
    case "setGattServerServices":
      setGattServerServices(arguments: call.arguments, result: result)
    case "clearGattServerServices":
      clearGattServerServices(result: result)
    case "updateLocalCharacteristicValue":
      updateLocalCharacteristicValue(arguments: call.arguments, result: result)
    case "notifyGattServerCharacteristic":
      notifyGattServerCharacteristic(arguments: call.arguments, result: result)
    case "connectClassic", "startClassicServer", "writeClassic":
      // macOS Classic Bluetooth/RFCOMM is not available through CoreBluetooth.
      result(FlutterError(code: "unsupported", message: "Classic Bluetooth RFCOMM is not supported on macOS.", details: nil))
    case "stopClassicServer", "disconnectClassic":
      // No Classic resources can be opened on macOS, so stop/disconnect are safe no-ops.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if let manager = centralManager {
      sendEvent(["type": "adapterState", "state": adapterStateString(manager.state)])
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func ensureCentralManager() -> CBCentralManager {
    if centralManager == nil {
      centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }
    return centralManager!
  }

  private func ensurePeripheralManager() -> CBPeripheralManager {
    if peripheralManager == nil {
      peripheralManager = CBPeripheralManager(delegate: self, queue: DispatchQueue.main)
    }
    return peripheralManager!
  }

  private func adapterInfoMap() -> [String: Any] {
    let manager = ensureCentralManager()
    return [
      "isSupported": manager.state != .unsupported,
      "state": adapterStateString(manager.state),
      "isBleSupported": manager.state != .unsupported,
      "isMultipleAdvertisementSupported": true,
      "isOffloadedFilteringSupported": false,
      "isOffloadedScanBatchingSupported": false,
      "isLe2MPhySupported": false,
      "isLeCodedPhySupported": false,
      "isLeExtendedAdvertisingSupported": false,
      "isLePeriodicAdvertisingSupported": false,
      "isDiscovering": manager.isScanning
    ]
  }

  private func handleRequestPermissions(result: @escaping FlutterResult) {
    let status = bluetoothPermissionStatus()
    guard status == "notDetermined" else {
      result(permissionMap())
      return
    }

    pendingPermissionResults.append(result)
    _ = ensureCentralManager()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      self?.flushPermissionResults()
    }
  }

  private func openBluetoothSettings(result: @escaping FlutterResult) {
    // macOS does not expose an app-specific Bluetooth settings URL like iOS;
    // open the system Bluetooth pane instead and let the user enable/authorize there.
    let candidates = [
      "x-apple.systempreferences:com.apple.BluetoothSettings",
      "x-apple.systempreferences:com.apple.preference.bluetooth"
    ]
    for candidate in candidates {
      if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
        result(nil)
        return
      }
    }
    result(FlutterError(code: "settings_unavailable", message: "Unable to open Bluetooth settings.", details: nil))
  }

  private func startScan(arguments: Any?, result: @escaping FlutterResult) {
    let manager = ensureCentralManager()
    guard manager.state == .poweredOn else {
      result(FlutterError(code: "bluetooth_unavailable", message: "Bluetooth is not powered on.", details: adapterStateString(manager.state)))
      return
    }

    let args = arguments as? [String: Any] ?? [:]
    let serviceUuidStrings = args["serviceUuids"] as? [String] ?? []
    let services = serviceUuidStrings.map { CBUUID(string: $0) }
    let allowDuplicates = args["allowDuplicates"] as? Bool ?? false
    let timeoutMs = args["timeoutMs"] as? Int
    let options = [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]

    manager.scanForPeripherals(withServices: services.isEmpty ? nil : services, options: options)
    scanTimer?.invalidate()
    if let timeoutMs = timeoutMs, timeoutMs > 0 {
      scanTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutMs) / 1000.0, repeats: false) { [weak self] _ in
        self?.centralManager?.stopScan()
      }
    }
    result(nil)
  }

  private func stopScan(result: @escaping FlutterResult) {
    scanTimer?.invalidate()
    scanTimer = nil
    centralManager?.stopScan()
    result(nil)
  }

  private func getConnectedDevices(arguments: Any?, result: @escaping FlutterResult) {
    let manager = ensureCentralManager()
    let args = arguments as? [String: Any] ?? [:]
    let serviceUuidStrings = args["serviceUuids"] as? [String] ?? []
    let connected: [CBPeripheral]

    if serviceUuidStrings.isEmpty {
      connected = peripherals.values.filter { $0.state == .connected }
    } else {
      connected = manager.retrieveConnectedPeripherals(withServices: serviceUuidStrings.map { CBUUID(string: $0) })
      connected.forEach { remember($0) }
    }

    result(connected.map { deviceMap($0) })
  }

  private func getDevice(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String, let peripheral = peripheral(for: deviceId) else {
      result(nil)
      return
    }
    result(deviceMap(peripheral))
  }

  private func getDevices(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    let ids = args["deviceIds"] as? [String] ?? []
    let devices = ids.compactMap { peripheral(for: $0) }.map { deviceMap($0) }
    result(devices)
  }

  private func connect(arguments: Any?, result: @escaping FlutterResult) {
    let manager = ensureCentralManager()
    guard manager.state == .poweredOn else {
      result(FlutterError(code: "bluetooth_unavailable", message: "Bluetooth is not powered on.", details: adapterStateString(manager.state)))
      return
    }

    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String, let peripheral = peripheral(for: deviceId) else {
      result(FlutterError(code: "device_not_found", message: "Device was not found. Scan first or pass a known macOS CoreBluetooth peripheral UUID.", details: nil))
      return
    }

    remember(peripheral)
    peripheral.delegate = self
    if peripheral.state == .connected {
      result(nil)
      sendConnectionEvent(deviceId: deviceId, state: "connected", status: nil)
      return
    }

    pendingConnectResults[deviceId] = result
    pendingConnectTimers[deviceId]?.invalidate()
    if let timeoutMs = args["timeoutMs"] as? Int, timeoutMs > 0 {
      pendingConnectTimers[deviceId] = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutMs) / 1000.0, repeats: false) { [weak self] _ in
        guard let self = self else { return }
        self.centralManager?.cancelPeripheralConnection(peripheral)
        self.finishConnect(deviceId: deviceId) { callback in
          callback(FlutterError(code: "connect_timeout", message: "Connection timed out.", details: nil))
        }
      }
    }

    manager.connect(peripheral, options: nil)
    sendConnectionEvent(deviceId: deviceId, state: "connecting", status: nil)
  }

  private func disconnect(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String, let peripheral = peripheral(for: deviceId) else {
      result(FlutterError(code: "device_not_found", message: "Device was not found.", details: nil))
      return
    }
    centralManager?.cancelPeripheralConnection(peripheral)
    result(nil)
  }

  private func getConnectionState(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String, let peripheral = peripheral(for: deviceId) else {
      result("disconnected")
      return
    }
    result(connectionStateString(peripheral.state))
  }

  private func discoverServices(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String, let peripheral = peripheral(for: deviceId) else {
      result(FlutterError(code: "device_not_found", message: "Device was not found.", details: nil))
      return
    }
    guard peripheral.state == .connected else {
      result(FlutterError(code: "not_connected", message: "Device is not connected.", details: nil))
      return
    }
    guard pendingDiscoveries[deviceId] == nil else {
      result(FlutterError(code: "operation_in_progress", message: "Service discovery is already running for this device.", details: nil))
      return
    }

    peripheral.delegate = self
    pendingDiscoveries[deviceId] = ServiceDiscoverySession(result: result)
    peripheral.discoverServices(nil)
  }

  private func readCharacteristic(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = CharacteristicRequest(arguments: arguments), let peripheral = peripheral(for: request.deviceId) else {
      result(FlutterError(code: "invalid_arguments", message: "Missing deviceId, serviceUuid, or characteristicUuid.", details: nil))
      return
    }
    guard let characteristic = findCharacteristic(peripheral: peripheral, serviceUuid: request.serviceUuid, characteristicUuid: request.characteristicUuid) else {
      result(FlutterError(code: "characteristic_not_found", message: "Characteristic was not found. Discover services first.", details: nil))
      return
    }
    pendingCharacteristicReads[characteristicKey(request.deviceId, request.serviceUuid, request.characteristicUuid)] = result
    peripheral.readValue(for: characteristic)
  }

  private func writeCharacteristic(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = CharacteristicRequest(arguments: arguments), let peripheral = peripheral(for: request.deviceId) else {
      result(FlutterError(code: "invalid_arguments", message: "Missing deviceId, serviceUuid, or characteristicUuid.", details: nil))
      return
    }
    guard let characteristic = findCharacteristic(peripheral: peripheral, serviceUuid: request.serviceUuid, characteristicUuid: request.characteristicUuid) else {
      result(FlutterError(code: "characteristic_not_found", message: "Characteristic was not found. Discover services first.", details: nil))
      return
    }

    let args = arguments as? [String: Any] ?? [:]
    let data = Data(byteArray(args["value"]))
    let writeTypeName = args["writeType"] as? String ?? "withResponse"
    if writeTypeName == "withoutResponse" {
      peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
      result(nil)
      return
    }

    pendingCharacteristicWrites[characteristicKey(request.deviceId, request.serviceUuid, request.characteristicUuid)] = result
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
  }

  private func setCharacteristicNotification(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = CharacteristicRequest(arguments: arguments), let peripheral = peripheral(for: request.deviceId) else {
      result(FlutterError(code: "invalid_arguments", message: "Missing deviceId, serviceUuid, or characteristicUuid.", details: nil))
      return
    }
    guard let characteristic = findCharacteristic(peripheral: peripheral, serviceUuid: request.serviceUuid, characteristicUuid: request.characteristicUuid) else {
      result(FlutterError(code: "characteristic_not_found", message: "Characteristic was not found. Discover services first.", details: nil))
      return
    }

    let args = arguments as? [String: Any] ?? [:]
    let enable = args["enable"] as? Bool ?? false
    pendingNotificationResults[characteristicKey(request.deviceId, request.serviceUuid, request.characteristicUuid)] = result
    peripheral.setNotifyValue(enable, for: characteristic)
  }

  private func readDescriptor(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = DescriptorRequest(arguments: arguments), let peripheral = peripheral(for: request.deviceId) else {
      result(FlutterError(code: "invalid_arguments", message: "Missing descriptor read arguments.", details: nil))
      return
    }
    guard let descriptor = findDescriptor(peripheral: peripheral, request: request) else {
      result(FlutterError(code: "descriptor_not_found", message: "Descriptor was not found. Discover services first.", details: nil))
      return
    }
    pendingDescriptorReads[descriptorKey(request.deviceId, request.serviceUuid, request.characteristicUuid, request.descriptorUuid)] = result
    peripheral.readValue(for: descriptor)
  }

  private func writeDescriptor(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = DescriptorRequest(arguments: arguments), let peripheral = peripheral(for: request.deviceId) else {
      result(FlutterError(code: "invalid_arguments", message: "Missing descriptor write arguments.", details: nil))
      return
    }
    guard let descriptor = findDescriptor(peripheral: peripheral, request: request) else {
      result(FlutterError(code: "descriptor_not_found", message: "Descriptor was not found. Discover services first.", details: nil))
      return
    }
    let args = arguments as? [String: Any] ?? [:]
    let data = Data(byteArray(args["value"]))
    pendingDescriptorWrites[descriptorKey(request.deviceId, request.serviceUuid, request.characteristicUuid, request.descriptorUuid)] = result
    peripheral.writeValue(data, for: descriptor)
  }

  private func readRssi(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String, let peripheral = peripheral(for: deviceId) else {
      result(FlutterError(code: "device_not_found", message: "Device was not found.", details: nil))
      return
    }
    pendingRssiResults[deviceId] = result
    peripheral.readRSSI()
  }

  private func requestMtu(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String, let peripheral = peripheral(for: deviceId) else {
      result(FlutterError(code: "device_not_found", message: "Device was not found.", details: nil))
      return
    }
    let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
    sendEvent(["type": "mtu", "deviceId": deviceId, "mtu": mtu])
    result(mtu)
  }

  private func getMaximumWriteLength(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String, let peripheral = peripheral(for: deviceId) else {
      result(FlutterError(code: "device_not_found", message: "Device was not found.", details: nil))
      return
    }
    let withoutResponse = args["withoutResponse"] as? Bool ?? true
    let type: CBCharacteristicWriteType = withoutResponse ? .withoutResponse : .withResponse
    result(peripheral.maximumWriteValueLength(for: type))
  }

  private func startAdvertising(arguments: Any?, result: @escaping FlutterResult) {
    let manager = ensurePeripheralManager()
    guard manager.state == .poweredOn else {
      result(FlutterError(code: "bluetooth_unavailable", message: "Bluetooth is not powered on.", details: adapterStateString(manager.state)))
      return
    }
    let args = arguments as? [String: Any] ?? [:]
    let data = args["advertisementData"] as? [String: Any] ?? [:]
    var advertisement: [String: Any] = [:]
    if let localName = data["localName"] as? String {
      advertisement[CBAdvertisementDataLocalNameKey] = localName
    }
    let serviceUuids = (data["serviceUuids"] as? [String] ?? []).map { CBUUID(string: $0) }
    if !serviceUuids.isEmpty {
      advertisement[CBAdvertisementDataServiceUUIDsKey] = serviceUuids
    }
    pendingAdvertisingResult = result
    manager.startAdvertising(advertisement)
  }

  private func stopAdvertising(result: @escaping FlutterResult) {
    peripheralManager?.stopAdvertising()
    isAdvertising = false
    sendEvent(["type": "advertisingState", "isAdvertising": false])
    result(nil)
  }

  private func setGattServerServices(arguments: Any?, result: @escaping FlutterResult) {
    let manager = ensurePeripheralManager()
    manager.removeAllServices()
    localCharacteristics.removeAll()
    localCharacteristicValues.removeAll()
    let args = arguments as? [String: Any] ?? [:]
    let services = args["services"] as? [[String: Any]] ?? []
    for serviceMap in services {
      manager.add(localService(serviceMap))
    }
    result(nil)
  }

  private func clearGattServerServices(result: @escaping FlutterResult) {
    peripheralManager?.removeAllServices()
    localCharacteristics.removeAll()
    localCharacteristicValues.removeAll()
    result(nil)
  }

  private func updateLocalCharacteristicValue(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let serviceUuid = args["serviceUuid"] as? String,
      let characteristicUuid = args["characteristicUuid"] as? String
    else {
      result(FlutterError(code: "invalid_arguments", message: "serviceUuid and characteristicUuid are required.", details: nil))
      return
    }
    let data = Data(byteArray(args["value"]))
    let key = characteristicKey("local", serviceUuid, characteristicUuid)
    localCharacteristicValues[key] = data
    localCharacteristics[key]?.value = data
    result(nil)
  }

  private func notifyGattServerCharacteristic(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard let serviceUuid = args["serviceUuid"] as? String,
      let characteristicUuid = args["characteristicUuid"] as? String
    else {
      result(FlutterError(code: "invalid_arguments", message: "serviceUuid and characteristicUuid are required.", details: nil))
      return
    }
    let key = characteristicKey("local", serviceUuid, characteristicUuid)
    guard let characteristic = localCharacteristics[key] else {
      result(FlutterError(code: "characteristic_not_found", message: "Local characteristic was not found.", details: nil))
      return
    }
    let data = Data(byteArray(args["value"]))
    localCharacteristicValues[key] = data
    characteristic.value = data
    result(peripheralManager?.updateValue(data, for: characteristic, onSubscribedCentrals: nil) == true)
  }

  public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    sendEvent(["type": "advertisingState", "isAdvertising": isAdvertising, "message": adapterStateString(peripheral.state)])
    flushPermissionResults()
  }

  public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    if let error = error {
      isAdvertising = false
      pendingAdvertisingResult?(FlutterError(code: "advertising_failed", message: error.localizedDescription, details: nil))
      sendEvent(["type": "advertisingState", "isAdvertising": false, "message": error.localizedDescription])
    } else {
      isAdvertising = true
      pendingAdvertisingResult?(nil)
      sendEvent(["type": "advertisingState", "isAdvertising": true])
    }
    pendingAdvertisingResult = nil
  }

  public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    sendEvent([
      "type": "gattServerRequest",
      "event": "serviceAdded",
      "deviceId": "",
      "serviceUuid": service.uuid.uuidString,
      "status": error == nil ? 0 : 1,
      "message": error?.localizedDescription
    ])
  }

  public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    let serviceUuid = request.characteristic.service?.uuid.uuidString ?? ""
    let characteristicUuid = request.characteristic.uuid.uuidString
    let key = characteristicKey("local", serviceUuid, characteristicUuid)
    let value = localCharacteristicValues[key] ?? Data()
    if request.offset > value.count {
      peripheral.respond(to: request, withResult: .invalidOffset)
      return
    }
    request.value = value.subdata(in: request.offset..<value.count)
    peripheral.respond(to: request, withResult: .success)
    sendEvent([
      "type": "gattServerRequest",
      "event": "characteristicRead",
      "deviceId": centralIdentifier(request.central),
      "serviceUuid": serviceUuid,
      "characteristicUuid": characteristicUuid,
      "offset": request.offset,
      "value": byteList(request.value),
      "responseNeeded": true
    ])
  }

  public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for request in requests {
      let serviceUuid = request.characteristic.service?.uuid.uuidString ?? ""
      let characteristicUuid = request.characteristic.uuid.uuidString
      let key = characteristicKey("local", serviceUuid, characteristicUuid)
      let value = request.value ?? Data()
      localCharacteristicValues[key] = value
      if let characteristic = localCharacteristics[key] {
        characteristic.value = value
      }
      sendEvent([
        "type": "gattServerRequest",
        "event": "characteristicWrite",
        "deviceId": centralIdentifier(request.central),
        "serviceUuid": serviceUuid,
        "characteristicUuid": characteristicUuid,
        "offset": request.offset,
        "value": byteList(value),
        "responseNeeded": true
      ])
    }
    if let first = requests.first {
      peripheral.respond(to: first, withResult: .success)
    }
  }

  public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    sendEvent([
      "type": "gattServerRequest",
      "event": "subscribed",
      "deviceId": centralIdentifier(central),
      "serviceUuid": characteristic.service?.uuid.uuidString ?? "",
      "characteristicUuid": characteristic.uuid.uuidString
    ])
  }

  public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
    sendEvent([
      "type": "gattServerRequest",
      "event": "unsubscribed",
      "deviceId": centralIdentifier(central),
      "serviceUuid": characteristic.service?.uuid.uuidString ?? "",
      "characteristicUuid": characteristic.uuid.uuidString
    ])
  }

  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    sendEvent(["type": "adapterState", "state": adapterStateString(central.state)])
    flushPermissionResults()
  }

  public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    remember(peripheral)
    sendEvent(scanResultMap(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI.intValue))
  }

  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    remember(peripheral)
    peripheral.delegate = self
    let deviceId = peripheral.identifier.uuidString
    finishConnect(deviceId: deviceId) { callback in callback(nil) }
    sendConnectionEvent(deviceId: deviceId, state: "connected", status: nil)
  }

  public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    finishConnect(deviceId: deviceId) { callback in
      callback(FlutterError(code: "connect_failed", message: error?.localizedDescription ?? "Failed to connect.", details: nil))
    }
    sendConnectionEvent(deviceId: deviceId, state: "disconnected", status: nil)
  }

  public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    finishConnect(deviceId: deviceId) { callback in
      callback(FlutterError(code: "connect_failed", message: error?.localizedDescription ?? "Disconnected before connection completed.", details: nil))
    }
    sendConnectionEvent(deviceId: deviceId, state: "disconnected", status: nil)
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    guard let session = pendingDiscoveries[deviceId] else { return }
    if let error = error {
      finishDiscovery(deviceId: deviceId, error: error)
      return
    }

    let services = peripheral.services ?? []
    if services.isEmpty {
      finishDiscovery(deviceId: deviceId, services: [])
      return
    }

    session.pendingCharacteristics = Set(services.map { $0.uuid.uuidString })
    for service in services {
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    guard let session = pendingDiscoveries[deviceId] else { return }
    session.pendingCharacteristics.remove(service.uuid.uuidString)

    if let error = error {
      finishDiscovery(deviceId: deviceId, error: error)
      return
    }

    let characteristics = service.characteristics ?? []
    for characteristic in characteristics {
      let key = descriptorDiscoveryKey(service.uuid.uuidString, characteristic.uuid.uuidString)
      session.pendingDescriptors.insert(key)
      peripheral.discoverDescriptors(for: characteristic)
    }
    maybeFinishDiscovery(deviceId: deviceId, peripheral: peripheral)
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    guard let session = pendingDiscoveries[deviceId] else { return }
    let key = descriptorDiscoveryKey(characteristic.service?.uuid.uuidString ?? "", characteristic.uuid.uuidString)
    session.pendingDescriptors.remove(key)

    if let error = error {
      finishDiscovery(deviceId: deviceId, error: error)
      return
    }

    maybeFinishDiscovery(deviceId: deviceId, peripheral: peripheral)
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    let serviceUuid = characteristic.service?.uuid.uuidString ?? ""
    let key = characteristicKey(deviceId, serviceUuid, characteristic.uuid.uuidString)

    if let result = pendingCharacteristicReads.removeValue(forKey: key) {
      if let error = error {
        result(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
      } else {
        result(byteList(characteristic.value))
      }
      return
    }

    guard error == nil else { return }
    sendEvent([
      "type": "characteristicValue",
      "deviceId": deviceId,
      "serviceUuid": serviceUuid,
      "characteristicUuid": characteristic.uuid.uuidString,
      "value": byteList(characteristic.value)
    ])
  }

  public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    let serviceUuid = characteristic.service?.uuid.uuidString ?? ""
    let key = characteristicKey(deviceId, serviceUuid, characteristic.uuid.uuidString)
    guard let result = pendingCharacteristicWrites.removeValue(forKey: key) else { return }
    if let error = error {
      result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
    } else {
      result(nil)
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    let serviceUuid = characteristic.service?.uuid.uuidString ?? ""
    let key = characteristicKey(deviceId, serviceUuid, characteristic.uuid.uuidString)
    guard let result = pendingNotificationResults.removeValue(forKey: key) else { return }
    if let error = error {
      result(FlutterError(code: "notification_failed", message: error.localizedDescription, details: nil))
    } else {
      result(nil)
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
    let requestKey = descriptorKey(
      peripheral.identifier.uuidString,
      descriptor.characteristic?.service?.uuid.uuidString ?? "",
      descriptor.characteristic?.uuid.uuidString ?? "",
      descriptor.uuid.uuidString
    )

    if let result = pendingDescriptorReads.removeValue(forKey: requestKey) {
      if let error = error {
        result(FlutterError(code: "descriptor_read_failed", message: error.localizedDescription, details: nil))
      } else {
        result(descriptorValueBytes(descriptor.value))
      }
      return
    }

    guard error == nil else { return }
    sendEvent([
      "type": "descriptorValue",
      "deviceId": peripheral.identifier.uuidString,
      "serviceUuid": descriptor.characteristic?.service?.uuid.uuidString ?? "",
      "characteristicUuid": descriptor.characteristic?.uuid.uuidString ?? "",
      "descriptorUuid": descriptor.uuid.uuidString,
      "value": descriptorValueBytes(descriptor.value)
    ])
  }

  public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
    let requestKey = descriptorKey(
      peripheral.identifier.uuidString,
      descriptor.characteristic?.service?.uuid.uuidString ?? "",
      descriptor.characteristic?.uuid.uuidString ?? "",
      descriptor.uuid.uuidString
    )
    guard let result = pendingDescriptorWrites.removeValue(forKey: requestKey) else { return }
    if let error = error {
      result(FlutterError(code: "descriptor_write_failed", message: error.localizedDescription, details: nil))
    } else {
      result(nil)
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    let deviceId = peripheral.identifier.uuidString
    if let result = pendingRssiResults.removeValue(forKey: deviceId) {
      if let error = error {
        result(FlutterError(code: "rssi_failed", message: error.localizedDescription, details: nil))
      } else {
        result(RSSI.intValue)
      }
    }
    if error == nil {
      sendEvent(["type": "rssi", "deviceId": deviceId, "rssi": RSSI.intValue])
    }
  }

  private func maybeFinishDiscovery(deviceId: String, peripheral: CBPeripheral) {
    guard let session = pendingDiscoveries[deviceId] else { return }
    if session.pendingCharacteristics.isEmpty && session.pendingDescriptors.isEmpty {
      finishDiscovery(deviceId: deviceId, services: (peripheral.services ?? []).map { serviceMap($0) })
    }
  }

  private func finishDiscovery(deviceId: String, services: [[String: Any]]) {
    guard let session = pendingDiscoveries.removeValue(forKey: deviceId) else { return }
    session.result(services)
  }

  private func finishDiscovery(deviceId: String, error: Error) {
    guard let session = pendingDiscoveries.removeValue(forKey: deviceId) else { return }
    session.result(FlutterError(code: "service_discovery_failed", message: error.localizedDescription, details: nil))
  }

  private func finishConnect(deviceId: String, complete: (FlutterResult) -> Void) {
    pendingConnectTimers.removeValue(forKey: deviceId)?.invalidate()
    if let result = pendingConnectResults.removeValue(forKey: deviceId) {
      complete(result)
    }
  }

  private func flushPermissionResults() {
    guard !pendingPermissionResults.isEmpty else { return }
    let results = pendingPermissionResults
    pendingPermissionResults.removeAll()
    let map = permissionMap()
    results.forEach { $0(map) }
  }

  private func peripheral(for deviceId: String) -> CBPeripheral? {
    if let peripheral = peripherals[deviceId] {
      return peripheral
    }
    guard let uuid = UUID(uuidString: deviceId) else {
      return nil
    }
    let retrieved = centralManager?.retrievePeripherals(withIdentifiers: [uuid]).first
    if let retrieved = retrieved {
      remember(retrieved)
    }
    return retrieved
  }

  private func remember(_ peripheral: CBPeripheral) {
    peripherals[peripheral.identifier.uuidString] = peripheral
  }

  private func findCharacteristic(peripheral: CBPeripheral, serviceUuid: String, characteristicUuid: String) -> CBCharacteristic? {
    guard let service = peripheral.services?.first(where: { uuidEquals($0.uuid, serviceUuid) }) else { return nil }
    return service.characteristics?.first(where: { uuidEquals($0.uuid, characteristicUuid) })
  }

  private func findDescriptor(peripheral: CBPeripheral, request: DescriptorRequest) -> CBDescriptor? {
    guard let characteristic = findCharacteristic(peripheral: peripheral, serviceUuid: request.serviceUuid, characteristicUuid: request.characteristicUuid) else {
      return nil
    }
    return characteristic.descriptors?.first(where: { uuidEquals($0.uuid, request.descriptorUuid) })
  }

  private func uuidEquals(_ lhs: CBUUID, _ rhs: String) -> Bool {
    return lhs.uuidString.caseInsensitiveCompare(CBUUID(string: rhs).uuidString) == .orderedSame
  }

  private func sendConnectionEvent(deviceId: String, state: String, status: Int?) {
    var event: [String: Any] = ["type": "connectionState", "deviceId": deviceId, "state": state]
    if let status = status {
      event["status"] = status
    }
    sendEvent(event)
  }

  private func sendEvent(_ event: [String: Any?]) {
    guard let eventSink = eventSink else { return }
    var payload: [String: Any] = [:]
    for (key, value) in event {
      if let value = value {
        payload[key] = value
      }
    }
    eventSink(payload)
  }

  private func adapterStateString(_ state: CBManagerState) -> String {
    switch state {
    case .unknown:
      return "unknown"
    case .resetting:
      return "resetting"
    case .unsupported:
      return "unsupported"
    case .unauthorized:
      return "unauthorized"
    case .poweredOff:
      return "poweredOff"
    case .poweredOn:
      return "poweredOn"
    @unknown default:
      return "unknown"
    }
  }

  private func connectionStateString(_ state: CBPeripheralState) -> String {
    switch state {
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .connected:
      return "connected"
    case .disconnecting:
      return "disconnecting"
    @unknown default:
      return "unknown"
    }
  }

  private func bluetoothPermissionStatus() -> String {
    switch CBManager.authorization {
    case .allowedAlways:
      return "granted"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  private func permissionMap() -> [String: String] {
    return ["bluetooth": bluetoothPermissionStatus()]
  }

  private func localService(_ map: [String: Any]) -> CBMutableService {
    let serviceUuid = CBUUID(string: map["uuid"] as? String ?? "")
    let service = CBMutableService(type: serviceUuid, primary: map["isPrimary"] as? Bool ?? true)
    let characteristics = map["characteristics"] as? [[String: Any]] ?? []
    service.characteristics = characteristics.map { localCharacteristic(serviceUuid: serviceUuid.uuidString, map: $0) }
    return service
  }

  private func localCharacteristic(serviceUuid: String, map: [String: Any]) -> CBMutableCharacteristic {
    let characteristicUuid = CBUUID(string: map["uuid"] as? String ?? "")
    let properties = mutableCharacteristicProperties(map["properties"] as? [String] ?? [])
    let permissions = attributePermissions(map["permissions"] as? [String] ?? [])
    let descriptors = (map["descriptors"] as? [[String: Any]] ?? []).map { descriptor -> CBMutableDescriptor in
      let uuid = CBUUID(string: descriptor["uuid"] as? String ?? "")
      let value = Data(byteArray(descriptor["value"]))
      return CBMutableDescriptor(type: uuid, value: value)
    }
    let value = Data(byteArray(map["value"]))
    let characteristic = CBMutableCharacteristic(
      type: characteristicUuid,
      properties: properties,
      value: properties.contains(.read) && !properties.contains(.write) ? value : nil,
      permissions: permissions
    )
    characteristic.descriptors = descriptors
    let key = characteristicKey("local", serviceUuid, characteristicUuid.uuidString)
    localCharacteristics[key] = characteristic
    localCharacteristicValues[key] = value
    return characteristic
  }

  private func mutableCharacteristicProperties(_ values: [String]) -> CBCharacteristicProperties {
    var properties: CBCharacteristicProperties = []
    if values.contains("broadcast") { properties.insert(.broadcast) }
    if values.contains("read") { properties.insert(.read) }
    if values.contains("writeWithoutResponse") { properties.insert(.writeWithoutResponse) }
    if values.contains("write") { properties.insert(.write) }
    if values.contains("notify") { properties.insert(.notify) }
    if values.contains("indicate") { properties.insert(.indicate) }
    if values.contains("authenticatedSignedWrites") { properties.insert(.authenticatedSignedWrites) }
    if values.contains("extendedProperties") { properties.insert(.extendedProperties) }
    if values.contains("notifyEncryptionRequired") { properties.insert(.notifyEncryptionRequired) }
    if values.contains("indicateEncryptionRequired") { properties.insert(.indicateEncryptionRequired) }
    return properties
  }

  private func attributePermissions(_ values: [String]) -> CBAttributePermissions {
    var permissions: CBAttributePermissions = []
    if values.isEmpty || values.contains("read") { permissions.insert(.readable) }
    if values.isEmpty || values.contains("write") { permissions.insert(.writeable) }
    if values.contains("readEncrypted") || values.contains("readEncryptionRequired") { permissions.insert(.readEncryptionRequired) }
    if values.contains("writeEncrypted") || values.contains("writeEncryptionRequired") { permissions.insert(.writeEncryptionRequired) }
    return permissions
  }

  private func centralIdentifier(_ central: CBCentral) -> String {
    return central.identifier.uuidString
  }

  private func deviceMap(_ peripheral: CBPeripheral) -> [String: Any] {
    var map: [String: Any] = [
      "id": peripheral.identifier.uuidString,
      "type": "ble",
      "isConnected": peripheral.state == .connected,
      "isBonded": false
    ]
    if let name = peripheral.name {
      map["name"] = name
    }
    return map
  }

  private func scanResultMap(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: Int) -> [String: Any] {
    let serviceUuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map { $0.uuidString }
    let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
    let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
    let serviceDataMap = serviceData.reduce(into: [String: FlutterStandardTypedData]()) { partial, item in
      partial[item.key.uuidString] = byteList(item.value)
    }

    var map: [String: Any] = [
      "type": "scanResult",
      "device": deviceMap(peripheral),
      "rssi": rssi,
      "serviceUuids": serviceUuids,
      "manufacturerData": manufacturerData == nil ? [:] : ["0": byteList(manufacturerData)],
      "serviceData": serviceDataMap
    ]
    if let localName = localName {
      map["localName"] = localName
    }
    if let txPowerLevel = advertisementData[CBAdvertisementDataTxPowerLevelKey] {
      map["txPowerLevel"] = txPowerLevel
    }
    if let isConnectable = boolValue(advertisementData[CBAdvertisementDataIsConnectable]) {
      map["isConnectable"] = isConnectable
    }
    return map
  }

  private func serviceMap(_ service: CBService) -> [String: Any] {
    return [
      "uuid": service.uuid.uuidString,
      "isPrimary": service.isPrimary,
      "includedServices": (service.includedServices ?? []).map { $0.uuid.uuidString },
      "characteristics": (service.characteristics ?? []).map { characteristicMap($0, serviceUuid: service.uuid.uuidString) }
    ]
  }

  private func characteristicMap(_ characteristic: CBCharacteristic, serviceUuid: String) -> [String: Any] {
    return [
      "uuid": characteristic.uuid.uuidString,
      "serviceUuid": serviceUuid,
      "properties": characteristicProperties(characteristic.properties),
      "permissions": [],
      "descriptors": (characteristic.descriptors ?? []).map { descriptorMap($0, characteristicUuid: characteristic.uuid.uuidString) }
    ]
  }

  private func descriptorMap(_ descriptor: CBDescriptor, characteristicUuid: String) -> [String: Any] {
    return [
      "uuid": descriptor.uuid.uuidString,
      "characteristicUuid": characteristicUuid,
      "value": descriptorValueBytes(descriptor.value)
    ]
  }

  private func characteristicProperties(_ properties: CBCharacteristicProperties) -> [String] {
    var values: [String] = []
    if properties.contains(.broadcast) { values.append("broadcast") }
    if properties.contains(.read) { values.append("read") }
    if properties.contains(.writeWithoutResponse) { values.append("writeWithoutResponse") }
    if properties.contains(.write) { values.append("write") }
    if properties.contains(.notify) { values.append("notify") }
    if properties.contains(.indicate) { values.append("indicate") }
    if properties.contains(.authenticatedSignedWrites) { values.append("authenticatedSignedWrites") }
    if properties.contains(.extendedProperties) { values.append("extendedProperties") }
    if properties.contains(.notifyEncryptionRequired) { values.append("notifyEncryptionRequired") }
    if properties.contains(.indicateEncryptionRequired) { values.append("indicateEncryptionRequired") }
    return values
  }

  private func byteArray(_ value: Any?) -> [UInt8] {
    if let typedData = value as? FlutterStandardTypedData { return Array(typedData.data) }
    if let data = value as? Data { return Array(data) }
    if let data = value as? NSData { return Array(data as Data) }
    guard let list = value as? [Any] else { return [] }
    return list.compactMap { item in
      if let number = item as? NSNumber { return number.uint8Value }
      if let int = item as? Int { return UInt8(truncatingIfNeeded: int) }
      return nil
    }
  }

  private func byteList(_ data: Data?) -> FlutterStandardTypedData {
    return FlutterStandardTypedData(bytes: data ?? Data())
  }

  private func boolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String {
      let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if ["true", "1", "yes"].contains(normalized) { return true }
      if ["false", "0", "no"].contains(normalized) { return false }
    }
    return nil
  }

  private func descriptorValueBytes(_ value: Any?) -> FlutterStandardTypedData {
    if let data = value as? Data { return byteList(data) }
    if let data = value as? NSData { return byteList(data as Data) }
    if let typedData = value as? FlutterStandardTypedData { return typedData }
    if let string = value as? String { return byteList(Data(string.utf8)) }
    if let number = value as? NSNumber {
      return byteList(Data([UInt8(truncatingIfNeeded: number.uint64Value)]))
    }
    return byteList(nil)
  }

  private func characteristicKey(_ deviceId: String, _ serviceUuid: String, _ characteristicUuid: String) -> String {
    return [deviceId, normalizedUuid(serviceUuid), normalizedUuid(characteristicUuid)].joined(separator: "|")
  }

  private func descriptorKey(_ deviceId: String, _ serviceUuid: String, _ characteristicUuid: String, _ descriptorUuid: String) -> String {
    return [deviceId, normalizedUuid(serviceUuid), normalizedUuid(characteristicUuid), normalizedUuid(descriptorUuid)].joined(separator: "|")
  }

  private func descriptorDiscoveryKey(_ serviceUuid: String, _ characteristicUuid: String) -> String {
    return [normalizedUuid(serviceUuid), normalizedUuid(characteristicUuid)].joined(separator: "|")
  }

  private func normalizedUuid(_ uuid: String) -> String {
    return CBUUID(string: uuid).uuidString.uppercased()
  }
}

private final class ServiceDiscoverySession {
  let result: FlutterResult
  var pendingCharacteristics: Set<String> = []
  var pendingDescriptors: Set<String> = []

  init(result: @escaping FlutterResult) {
    self.result = result
  }
}

private struct CharacteristicRequest {
  let deviceId: String
  let serviceUuid: String
  let characteristicUuid: String

  init?(arguments: Any?) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String,
      let serviceUuid = args["serviceUuid"] as? String,
      let characteristicUuid = args["characteristicUuid"] as? String
    else {
      return nil
    }
    self.deviceId = deviceId
    self.serviceUuid = serviceUuid
    self.characteristicUuid = characteristicUuid
  }
}

private struct DescriptorRequest {
  let deviceId: String
  let serviceUuid: String
  let characteristicUuid: String
  let descriptorUuid: String

  init?(arguments: Any?) {
    let args = arguments as? [String: Any] ?? [:]
    guard let deviceId = args["deviceId"] as? String,
      let serviceUuid = args["serviceUuid"] as? String,
      let characteristicUuid = args["characteristicUuid"] as? String,
      let descriptorUuid = args["descriptorUuid"] as? String
    else {
      return nil
    }
    self.deviceId = deviceId
    self.serviceUuid = serviceUuid
    self.characteristicUuid = characteristicUuid
    self.descriptorUuid = descriptorUuid
  }
}
