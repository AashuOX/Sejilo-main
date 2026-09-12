package com.yuanzhihong.flutter_bluetooth_plugin

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.util.Locale
import java.util.UUID
import kotlin.concurrent.thread

/** Flutter Bluetooth plugin for Android Bluetooth Classic discovery and BLE GATT central APIs. */
class FlutterBluetoothPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    // Access Android's main looper only when an operation actually needs it.
    // This keeps construction side-effect free and allows JVM unit tests to
    // cover method dispatch without requiring a device or Robolectric.
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: Result? = null
    private var pendingEnableResult: Result? = null

    private var scanCallback: ScanCallback? = null
    private var activeScanMode: String = "ble"
    private var allowDuplicateScanResults = false
    private val seenScanDevices = mutableSetOf<String>()
    private val stopScanRunnable = Runnable { stopScanInternal() }

    private val gatts = mutableMapOf<String, BluetoothGatt>()
    private val connectionStates = mutableMapOf<String, String>()
    private val pendingConnectResults = mutableMapOf<String, Result>()
    private val pendingConnectTimeouts = mutableMapOf<String, Runnable>()
    private val pendingServiceDiscoveries = mutableMapOf<String, Result>()
    private val pendingCharacteristicReads = mutableMapOf<String, Result>()
    private val pendingCharacteristicWrites = mutableMapOf<String, Result>()
    private val pendingDescriptorReads = mutableMapOf<String, Result>()
    private val pendingDescriptorWrites = mutableMapOf<String, Result>()
    private val pendingNotificationWrites = mutableMapOf<String, Result>()
    private val pendingRssiReads = mutableMapOf<String, Result>()
    private val pendingMtuRequests = mutableMapOf<String, Result>()
    private val pendingPhyReads = mutableMapOf<String, Result>()
    private val knownMtus = mutableMapOf<String, Int>()

    private var gattServer: BluetoothGattServer? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var pendingAdvertiseResult: Result? = null
    private var pendingGattServerServicesResult: Result? = null
    private var pendingGattServerServiceCount = 0
    private val localCharacteristicValues = mutableMapOf<String, ByteArray>()
    private val localDescriptorValues = mutableMapOf<String, ByteArray>()

    private val classicSockets = mutableMapOf<String, BluetoothSocket>()
    private var classicServerSocket: BluetoothServerSocket? = null
    @Volatile private var classicServerRunning = false

    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context,
                intent: Intent,
            ) {
                when (intent.action) {
                    BluetoothAdapter.ACTION_STATE_CHANGED -> {
                        val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                        sendEvent(mapOf("type" to "adapterState", "state" to adapterStateString(state)))
                    }
                    BluetoothDevice.ACTION_FOUND -> handleClassicDeviceFound(intent)
                    BluetoothDevice.ACTION_BOND_STATE_CHANGED -> handleBondStateChanged(intent)
                }
            }
        }
    private var receiverRegistered = false

    private val bluetoothManager: BluetoothManager?
        get() = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager

    private val adapter: BluetoothAdapter?
        get() = bluetoothManager?.adapter

    private val scanner: BluetoothLeScanner?
        get() = adapter?.bluetoothLeScanner

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_bluetooth_plugin")
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_bluetooth_plugin/events")
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        registerReceiver()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopScanInternal()
        stopAdvertisingInternal()
        closeGattServer()
        stopClassicServerInternal()
        closeAllClassicSockets()
        closeAllGatts()
        unregisterReceiver()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        eventSink = events
        sendEvent(mapOf("type" to "adapterState", "state" to currentAdapterStateString()))
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        try {
            when (call.method) {
                "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
                "isSupported" -> result.success(isSupported())
                "getAdapterState" -> result.success(currentAdapterStateString())
                "getAdapterInfo" -> result.success(adapterInfoMap())
                "isScanning" -> result.success(isScanning())
                "setAdapterName" -> setAdapterName(call, result)
                "checkPermissions" -> result.success(permissionMap())
                "requestPermissions" -> requestPermissions(result)
                "requestEnable" -> requestEnable(result)
                "openBluetoothSettings" -> openBluetoothSettings(result)
                "startScan" -> startScan(call, result)
                "stopScan" -> {
                    stopScanInternal()
                    result.success(null)
                }
                "getBondedDevices" -> getBondedDevices(result)
                "getConnectedDevices" -> getConnectedDevices(result)
                "getDevice" -> getDevice(call, result)
                "getDevices" -> getDevices(call, result)
                "connect" -> connect(call, result)
                "disconnect" -> disconnect(call, result)
                "getConnectionState" -> getConnectionState(call, result)
                "discoverServices" -> discoverServices(call, result)
                "readCharacteristic" -> readCharacteristic(call, result)
                "writeCharacteristic" -> writeCharacteristic(call, result)
                "setCharacteristicNotification" -> setCharacteristicNotification(call, result)
                "readDescriptor" -> readDescriptor(call, result)
                "writeDescriptor" -> writeDescriptor(call, result)
                "readRssi" -> readRssi(call, result)
                "requestMtu" -> requestMtu(call, result)
                "getMaximumWriteLength" -> getMaximumWriteLength(call, result)
                "setPreferredPhy" -> setPreferredPhy(call, result)
                "readPhy" -> readPhy(call, result)
                "requestConnectionPriority" -> requestConnectionPriority(call, result)
                "createBond" -> createBond(call, result)
                "removeBond" -> removeBond(call, result)
                "isPeripheralSupported" -> result.success(isPeripheralSupported())
                "startAdvertising" -> startAdvertising(call, result)
                "stopAdvertising" -> {
                    stopAdvertisingInternal()
                    result.success(null)
                }
                "setGattServerServices" -> setGattServerServices(call, result)
                "clearGattServerServices" -> {
                    gattServer?.clearServices()
                    localCharacteristicValues.clear()
                    localDescriptorValues.clear()
                    result.success(null)
                }
                "updateLocalCharacteristicValue" -> updateLocalCharacteristicValue(call, result)
                "notifyGattServerCharacteristic" -> notifyGattServerCharacteristic(call, result)
                "connectClassic" -> connectClassic(call, result)
                "startClassicServer" -> startClassicServer(call, result)
                "stopClassicServer" -> {
                    stopClassicServerInternal()
                    result.success(null)
                }
                "disconnectClassic" -> disconnectClassic(call, result)
                "writeClassic" -> writeClassic(call, result)
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) {
            result.error("permission_denied", error.message ?: "Bluetooth permission denied.", null)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_arguments", error.message, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_PERMISSIONS_CODE) {
            return false
        }
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        result.success(permissionMap())
        return true
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_ENABLE_CODE) {
            return false
        }
        val result = pendingEnableResult ?: return true
        pendingEnableResult = null
        result.success(resultCode == Activity.RESULT_OK || adapter?.isEnabled == true)
        return true
    }

    private fun isSupported(): Boolean {
        return adapter != null || context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
    }

    private fun currentAdapterStateString(): String {
        return adapterStateString(adapter?.state ?: BluetoothAdapter.ERROR)
    }

    private fun adapterStateString(state: Int): String {
        return when (state) {
            BluetoothAdapter.STATE_OFF -> "poweredOff"
            BluetoothAdapter.STATE_TURNING_ON -> "turningOn"
            BluetoothAdapter.STATE_ON -> "poweredOn"
            BluetoothAdapter.STATE_TURNING_OFF -> "turningOff"
            else -> if (adapter == null) "unsupported" else "unknown"
        }
    }

    @SuppressLint("MissingPermission")
    private fun adapterInfoMap(): Map<String, Any?> {
        val adapter = adapter
        return mapOf(
            "isSupported" to (adapter != null),
            "state" to currentAdapterStateString(),
            "name" to if (hasConnectPermission()) adapter?.name else null,
            "address" to if (hasConnectPermission()) adapter?.address else null,
            "isBleSupported" to context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE),
            "isMultipleAdvertisementSupported" to (adapter?.isMultipleAdvertisementSupported == true),
            "isOffloadedFilteringSupported" to (adapter?.isOffloadedFilteringSupported == true),
            "isOffloadedScanBatchingSupported" to (adapter?.isOffloadedScanBatchingSupported == true),
            "isLe2MPhySupported" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) adapter?.isLe2MPhySupported == true else false,
            "isLeCodedPhySupported" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) adapter?.isLeCodedPhySupported == true else false,
            "isLeExtendedAdvertisingSupported" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) adapter?.isLeExtendedAdvertisingSupported == true else false,
            "isLePeriodicAdvertisingSupported" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) adapter?.isLePeriodicAdvertisingSupported == true else false,
            "isDiscovering" to (adapter?.isDiscovering == true || scanCallback != null),
        ).withoutNullValues()
    }

    private fun isScanning(): Boolean {
        return scanCallback != null || adapter?.isDiscovering == true
    }

    @SuppressLint("MissingPermission")
    private fun setAdapterName(
        call: MethodCall,
        result: Result,
    ) {
        val name = call.argument<String>("name") ?: return result.error("invalid_arguments", "name is required.", null)
        val adapter = adapter ?: return result.success(false)
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        @Suppress("DEPRECATION")
        result.success(adapter.setName(name))
    }

    private fun permissionMap(): Map<String, String> {
        return mapOf(
            "bluetooth" to if (adapter == null) "notApplicable" else "granted",
            "bluetoothScan" to permissionStatus(Manifest.permission.BLUETOOTH_SCAN, Build.VERSION_CODES.S),
            "bluetoothConnect" to permissionStatus(Manifest.permission.BLUETOOTH_CONNECT, Build.VERSION_CODES.S),
            "bluetoothAdvertise" to permissionStatus(Manifest.permission.BLUETOOTH_ADVERTISE, Build.VERSION_CODES.S),
            "locationWhenInUse" to locationPermissionStatus(),
        )
    }

    private fun permissionStatus(
        permission: String,
        minSdk: Int,
    ): String {
        if (Build.VERSION.SDK_INT < minSdk) {
            return "notApplicable"
        }
        return if (context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            "granted"
        } else if (activity?.shouldShowRequestPermissionRationale(permission) == false) {
            "denied"
        } else {
            "denied"
        }
    }

    private fun locationPermissionStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return "notApplicable"
        }
        val permission = Manifest.permission.ACCESS_FINE_LOCATION
        return if (context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            "granted"
        } else {
            "denied"
        }
    }

    private fun requestPermissions(result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(permissionMap())
            return
        }
        val activity = activity
        if (activity == null) {
            result.error("activity_required", "Requesting Bluetooth permissions requires a foreground Activity.", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("operation_in_progress", "A permission request is already in progress.", null)
            return
        }

        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_SCAN
            permissions += Manifest.permission.BLUETOOTH_CONNECT
            permissions += Manifest.permission.BLUETOOTH_ADVERTISE
        } else {
            permissions += Manifest.permission.ACCESS_FINE_LOCATION
        }
        val missing = permissions.filter { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) {
            result.success(permissionMap())
            return
        }

        pendingPermissionResult = result
        activity.requestPermissions(missing.toTypedArray(), REQUEST_PERMISSIONS_CODE)
    }

    @SuppressLint("MissingPermission")
    private fun requestEnable(result: Result) {
        val adapter = adapter
        if (adapter == null) {
            result.success(false)
            return
        }
        if (adapter.isEnabled) {
            result.success(true)
            return
        }
        val activity = activity
        if (activity == null) {
            result.error("activity_required", "Requesting Bluetooth enable requires a foreground Activity.", null)
            return
        }
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required to request enabling Bluetooth.", null)
            return
        }
        if (pendingEnableResult != null) {
            result.error("operation_in_progress", "A Bluetooth enable request is already in progress.", null)
            return
        }
        pendingEnableResult = result
        activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE_CODE)
    }

    private fun openBluetoothSettings(result: Result) {
        val intent = Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        result.success(null)
    }

    @SuppressLint("MissingPermission")
    private fun startScan(
        call: MethodCall,
        result: Result,
    ) {
        val adapter = adapter
        if (adapter == null) {
            result.error("unsupported", "Bluetooth is not supported on this device.", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_unavailable", "Bluetooth is not powered on.", currentAdapterStateString())
            return
        }
        if (!hasScanPermission()) {
            result.error("permission_denied", "Bluetooth scan permission is required.", null)
            return
        }

        stopScanInternal()
        seenScanDevices.clear()

        val mode = call.argument<String>("scanMode") ?: "ble"
        val serviceUuids = call.argument<List<String>>("serviceUuids") ?: emptyList()
        allowDuplicateScanResults = call.argument<Boolean>("allowDuplicates") ?: false
        activeScanMode = mode

        if (mode == "ble" || mode == "dual") {
            val leScanner = scanner
            if (leScanner == null) {
                result.error("scanner_unavailable", "BLE scanner is unavailable.", null)
                return
            }
            val filters = serviceUuids.map { ScanFilter.Builder().setServiceUuid(ParcelUuid(normalizeUuid(it))).build() }
            val filtersOrNull = if (filters.isEmpty()) null else filters
            val settings =
                ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .build()
            scanCallback = createScanCallback()
            leScanner.startScan(filtersOrNull, settings, scanCallback)
        }

        if (mode == "classic" || mode == "dual") {
            if (adapter.isDiscovering) {
                adapter.cancelDiscovery()
            }
            adapter.startDiscovery()
        }

        call.argument<Int>("timeoutMs")?.takeIf { it > 0 }?.let {
            mainHandler.postDelayed(stopScanRunnable, it.toLong())
        }
        result.success(null)
    }

    @SuppressLint("MissingPermission")
    private fun stopScanInternal() {
        mainHandler.removeCallbacks(stopScanRunnable)
        scanCallback?.let { callback ->
            runCatching { scanner?.stopScan(callback) }
        }
        scanCallback = null
        runCatching { adapter?.takeIf { it.isDiscovering }?.cancelDiscovery() }
    }

    private fun createScanCallback(): ScanCallback {
        return object : ScanCallback() {
            override fun onScanResult(
                callbackType: Int,
                result: ScanResult,
            ) {
                handleBleScanResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach { handleBleScanResult(it) }
            }

            override fun onScanFailed(errorCode: Int) {
                sendEvent(mapOf("type" to "scanError", "code" to errorCode))
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun handleBleScanResult(result: ScanResult) {
        val device = result.device ?: return
        val id = device.address ?: return
        if (!allowDuplicateScanResults && !seenScanDevices.add(id)) {
            return
        }
        val record = result.scanRecord
        val manufacturerData = mutableMapOf<String, ByteArray>()
        record?.manufacturerSpecificData?.let { data ->
            for (index in 0 until data.size()) {
                manufacturerData[data.keyAt(index).toString()] = data.valueAt(index)
            }
        }
        val serviceData = mutableMapOf<String, ByteArray>()
        record?.serviceData?.forEach { (uuid, bytes) -> serviceData[uuid.uuid.toString()] = bytes }
        sendEvent(
            mapOf(
                "type" to "scanResult",
                "device" to deviceMap(device),
                "rssi" to result.rssi,
                "localName" to (record?.deviceName ?: device.safeName()),
                "serviceUuids" to (record?.serviceUuids?.map { it.uuid.toString() } ?: emptyList<String>()),
                "manufacturerData" to manufacturerData,
                "serviceData" to serviceData,
                "txPowerLevel" to record?.txPowerLevel,
                "isConnectable" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) result.isConnectable else null,
            ).withoutNullValues(),
        )
    }

    @SuppressLint("MissingPermission")
    private fun handleClassicDeviceFound(intent: Intent) {
        if (activeScanMode != "classic" && activeScanMode != "dual") {
            return
        }
        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        } ?: return
        val id = device.address ?: return
        if (!allowDuplicateScanResults && !seenScanDevices.add(id)) {
            return
        }
        val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE).toInt()
        sendEvent(
            mapOf(
                "type" to "scanResult",
                "device" to deviceMap(device),
                "rssi" to if (rssi == Short.MIN_VALUE.toInt()) 0 else rssi,
                "localName" to device.safeName(),
                "serviceUuids" to emptyList<String>(),
                "manufacturerData" to emptyMap<String, ByteArray>(),
                "serviceData" to emptyMap<String, ByteArray>(),
            ),
        )
    }

    @SuppressLint("MissingPermission")
    private fun handleBondStateChanged(intent: Intent) {
        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        } ?: return
        sendEvent(
            mapOf(
                "type" to "bondState",
                "deviceId" to device.address,
                "state" to bondStateString(device.bondState),
            ),
        )
    }

    @SuppressLint("MissingPermission")
    private fun getBondedDevices(result: Result) {
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        result.success(adapter?.bondedDevices?.map { deviceMap(it) } ?: emptyList<Map<String, Any?>>())
    }

    @SuppressLint("MissingPermission")
    private fun getConnectedDevices(result: Result) {
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        val devices = bluetoothManager?.getConnectedDevices(BluetoothProfile.GATT)?.map { deviceMap(it) }
            ?: emptyList()
        result.success(devices)
    }

    @SuppressLint("MissingPermission")
    private fun getDevice(
        call: MethodCall,
        result: Result,
    ) {
        val device = remoteDevice(call)
        result.success(device?.let { deviceMap(it) })
    }

    @SuppressLint("MissingPermission")
    private fun getDevices(
        call: MethodCall,
        result: Result,
    ) {
        val ids = call.argument<List<String>>("deviceIds") ?: emptyList()
        val adapter = adapter
        if (adapter == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        result.success(
            ids.mapNotNull { id ->
                runCatching { adapter.getRemoteDevice(id) }.getOrNull()?.let { deviceMap(it) }
            },
        )
    }

    @SuppressLint("MissingPermission")
    private fun connect(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val adapter = adapter ?: return result.error("unsupported", "Bluetooth is not supported on this device.", null)
        if (!adapter.isEnabled) {
            result.error("bluetooth_unavailable", "Bluetooth is not powered on.", currentAdapterStateString())
            return
        }
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        if (pendingConnectResults.containsKey(deviceId)) {
            result.error("operation_in_progress", "Connection is already in progress for this device.", null)
            return
        }

        val device = adapter.getRemoteDevice(deviceId)
        val autoConnect = call.argument<Boolean>("autoConnect") ?: false
        connectionStates[deviceId] = "connecting"
        sendConnectionState(deviceId, "connecting", null)
        val callback = createGattCallback(deviceId)
        val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, autoConnect, callback, BluetoothDevice.TRANSPORT_LE)
        } else {
            @Suppress("DEPRECATION")
            device.connectGatt(context, autoConnect, callback)
        }
        if (gatt == null) {
            connectionStates[deviceId] = "disconnected"
            result.error("connect_failed", "Unable to create BluetoothGatt.", null)
            return
        }
        gatts[deviceId] = gatt

        if (autoConnect) {
            result.success(null)
        } else {
            pendingConnectResults[deviceId] = result
        }
        call.argument<Int>("timeoutMs")?.takeIf { it > 0 }?.let { timeoutMs ->
            val timeoutRunnable = Runnable {
                pendingConnectResults.remove(deviceId)?.error("connect_timeout", "Connection timed out.", null)
                connectionStates[deviceId] = "disconnected"
                sendConnectionState(deviceId, "disconnected", null)
                gatt.disconnect()
                gatt.close()
                gatts.remove(deviceId)
            }
            pendingConnectTimeouts[deviceId] = timeoutRunnable
            mainHandler.postDelayed(timeoutRunnable, timeoutMs.toLong())
        }
    }

    @SuppressLint("MissingPermission")
    private fun disconnect(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val gatt = gatts[deviceId]
        if (gatt == null) {
            connectionStates[deviceId] = "disconnected"
            result.success(null)
            return
        }
        connectionStates[deviceId] = "disconnecting"
        sendConnectionState(deviceId, "disconnecting", null)
        gatt.disconnect()
        result.success(null)
    }

    private fun getConnectionState(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        result.success(connectionStates[deviceId] ?: "disconnected")
    }

    @SuppressLint("MissingPermission")
    private fun discoverServices(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val gatt = gatts[deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        if (pendingServiceDiscoveries.containsKey(deviceId)) {
            result.error("operation_in_progress", "Service discovery is already in progress.", null)
            return
        }
        pendingServiceDiscoveries[deviceId] = result
        if (!gatt.discoverServices()) {
            pendingServiceDiscoveries.remove(deviceId)
            result.error("service_discovery_failed", "discoverServices returned false.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun readCharacteristic(
        call: MethodCall,
        result: Result,
    ) {
        val request = characteristicRequest(call) ?: return result.error("invalid_arguments", "Missing characteristic arguments.", null)
        val gatt = gatts[request.deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        val characteristic = findCharacteristic(gatt, request.serviceUuid, request.characteristicUuid)
            ?: return result.error("characteristic_not_found", "Characteristic was not found. Discover services first.", null)
        val key = characteristicKey(request.deviceId, request.serviceUuid, request.characteristicUuid)
        pendingCharacteristicReads[key] = result
        if (!gatt.readCharacteristic(characteristic)) {
            pendingCharacteristicReads.remove(key)
            result.error("read_failed", "readCharacteristic returned false.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeCharacteristic(
        call: MethodCall,
        result: Result,
    ) {
        val request = characteristicRequest(call) ?: return result.error("invalid_arguments", "Missing characteristic arguments.", null)
        val gatt = gatts[request.deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        val characteristic = findCharacteristic(gatt, request.serviceUuid, request.characteristicUuid)
            ?: return result.error("characteristic_not_found", "Characteristic was not found. Discover services first.", null)
        val value = byteArrayArg(call.argument<Any>("value"))
        val writeType = if (call.argument<String>("writeType") == "withoutResponse") {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        }
        val key = characteristicKey(request.deviceId, request.serviceUuid, request.characteristicUuid)

        if (writeType == BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE) {
            val started = writeCharacteristicCompat(gatt, characteristic, value, writeType)
            if (started) result.success(null) else result.error("write_failed", "writeCharacteristic returned false.", null)
            return
        }

        pendingCharacteristicWrites[key] = result
        if (!writeCharacteristicCompat(gatt, characteristic, value, writeType)) {
            pendingCharacteristicWrites.remove(key)
            result.error("write_failed", "writeCharacteristic returned false.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun setCharacteristicNotification(
        call: MethodCall,
        result: Result,
    ) {
        val request = characteristicRequest(call) ?: return result.error("invalid_arguments", "Missing characteristic arguments.", null)
        val gatt = gatts[request.deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        val characteristic = findCharacteristic(gatt, request.serviceUuid, request.characteristicUuid)
            ?: return result.error("characteristic_not_found", "Characteristic was not found. Discover services first.", null)
        val enable = call.argument<Boolean>("enable") ?: false
        if (!gatt.setCharacteristicNotification(characteristic, enable)) {
            result.error("notification_failed", "setCharacteristicNotification returned false.", null)
            return
        }

        val cccd = characteristic.getDescriptor(CCCD_UUID)
        if (cccd == null) {
            result.success(null)
            return
        }
        val value = when {
            !enable -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0 -> BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            else -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        }
        val key = characteristicKey(request.deviceId, request.serviceUuid, request.characteristicUuid)
        pendingNotificationWrites[key] = result
        if (!writeDescriptorCompat(gatt, cccd, value)) {
            pendingNotificationWrites.remove(key)
            result.error("notification_failed", "Writing CCC descriptor returned false.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun readDescriptor(
        call: MethodCall,
        result: Result,
    ) {
        val request = descriptorRequest(call) ?: return result.error("invalid_arguments", "Missing descriptor arguments.", null)
        val gatt = gatts[request.deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        val descriptor = findDescriptor(gatt, request)
            ?: return result.error("descriptor_not_found", "Descriptor was not found. Discover services first.", null)
        val key = descriptorKey(request.deviceId, request.serviceUuid, request.characteristicUuid, request.descriptorUuid)
        pendingDescriptorReads[key] = result
        if (!gatt.readDescriptor(descriptor)) {
            pendingDescriptorReads.remove(key)
            result.error("descriptor_read_failed", "readDescriptor returned false.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeDescriptor(
        call: MethodCall,
        result: Result,
    ) {
        val request = descriptorRequest(call) ?: return result.error("invalid_arguments", "Missing descriptor arguments.", null)
        val gatt = gatts[request.deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        val descriptor = findDescriptor(gatt, request)
            ?: return result.error("descriptor_not_found", "Descriptor was not found. Discover services first.", null)
        val key = descriptorKey(request.deviceId, request.serviceUuid, request.characteristicUuid, request.descriptorUuid)
        val value = byteArrayArg(call.argument<Any>("value"))
        pendingDescriptorWrites[key] = result
        if (!writeDescriptorCompat(gatt, descriptor, value)) {
            pendingDescriptorWrites.remove(key)
            result.error("descriptor_write_failed", "writeDescriptor returned false.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun readRssi(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val gatt = gatts[deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        pendingRssiReads[deviceId] = result
        if (!gatt.readRemoteRssi()) {
            pendingRssiReads.remove(deviceId)
            result.error("rssi_failed", "readRemoteRssi returned false.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestMtu(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val mtu = call.argument<Int>("mtu") ?: return result.error("invalid_arguments", "mtu is required.", null)
        val gatt = gatts[deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        pendingMtuRequests[deviceId] = result
        if (!gatt.requestMtu(mtu)) {
            pendingMtuRequests.remove(deviceId)
            result.error("mtu_failed", "requestMtu returned false.", null)
        }
    }

    private fun getMaximumWriteLength(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        if (!gatts.containsKey(deviceId)) {
            result.error("not_connected", "Device is not connected.", null)
            return
        }
        result.success(lastKnownMtu(deviceId) - 3)
    }

    @SuppressLint("MissingPermission")
    private fun setPreferredPhy(
        call: MethodCall,
        result: Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "LE PHY APIs require Android 8.0 or newer.", null)
            return
        }
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val gatt = gatts[deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        val txPhy = androidPhy(call.argument<String>("txPhy"))
        val rxPhy = androidPhy(call.argument<String>("rxPhy"))
        val phyOptions = call.argument<Int>("phyOptions") ?: 0
        gatt.setPreferredPhy(txPhy, rxPhy, phyOptions)
        result.success(null)
    }

    @SuppressLint("MissingPermission")
    private fun readPhy(
        call: MethodCall,
        result: Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(mapOf("deviceId" to (call.argument<String>("deviceId") ?: ""), "txPhy" to "unknown", "rxPhy" to "unknown"))
            return
        }
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val gatt = gatts[deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        pendingPhyReads[deviceId] = result
        gatt.readPhy()
    }

    @SuppressLint("MissingPermission")
    private fun requestConnectionPriority(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val priorityName = call.argument<String>("priority") ?: "balanced"
        val priority = when (priorityName) {
            "high" -> BluetoothGatt.CONNECTION_PRIORITY_HIGH
            "lowPower" -> BluetoothGatt.CONNECTION_PRIORITY_LOW_POWER
            else -> BluetoothGatt.CONNECTION_PRIORITY_BALANCED
        }
        val gatt = gatts[deviceId] ?: return result.error("not_connected", "Device is not connected.", null)
        result.success(gatt.requestConnectionPriority(priority))
    }

    @SuppressLint("MissingPermission")
    private fun createBond(
        call: MethodCall,
        result: Result,
    ) {
        val device = remoteDevice(call) ?: return result.error("invalid_arguments", "deviceId is required.", null)
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        result.success(device.createBond())
    }

    @SuppressLint("MissingPermission")
    private fun removeBond(
        call: MethodCall,
        result: Result,
    ) {
        val device = remoteDevice(call) ?: return result.error("invalid_arguments", "deviceId is required.", null)
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        val method = device.javaClass.getMethod("removeBond")
        result.success(method.invoke(device) as? Boolean ?: false)
    }

    @SuppressLint("MissingPermission")
    private fun createGattCallback(deviceId: String): BluetoothGattCallback {
        return object : BluetoothGattCallback() {
            override fun onConnectionStateChange(
                gatt: BluetoothGatt,
                status: Int,
                newState: Int,
            ) {
                val state = if (newState == BluetoothProfile.STATE_CONNECTED) "connected" else "disconnected"
                connectionStates[deviceId] = state
                if (state == "connected") {
                    clearConnectTimeout(deviceId)
                    pendingConnectResults.remove(deviceId)?.success(null)
                } else {
                    clearConnectTimeout(deviceId)
                    pendingConnectResults.remove(deviceId)?.let { pending ->
                        if (status == BluetoothGatt.GATT_SUCCESS) {
                            pending.success(null)
                        } else {
                            pending.error("connect_failed", "GATT connection failed with status $status.", status)
                        }
                    }
                    closeGatt(deviceId)
                }
                sendConnectionState(deviceId, state, status)
            }

            override fun onPhyUpdate(
                gatt: BluetoothGatt,
                txPhy: Int,
                rxPhy: Int,
                status: Int,
            ) {
                sendPhyEvent(deviceId, txPhy, rxPhy, status)
            }

            override fun onPhyRead(
                gatt: BluetoothGatt,
                txPhy: Int,
                rxPhy: Int,
                status: Int,
            ) {
                val event = phyEventMap(deviceId, txPhy, rxPhy, status)
                pendingPhyReads.remove(deviceId)?.success(event)
                sendEvent(event)
            }

            override fun onServicesDiscovered(
                gatt: BluetoothGatt,
                status: Int,
            ) {
                val result = pendingServiceDiscoveries.remove(deviceId) ?: return
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    result.success(gatt.services.map { serviceMap(it) })
                } else {
                    result.error("service_discovery_failed", "Service discovery failed with status $status.", status)
                }
            }

            @Deprecated("Deprecated in Android 13")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                handleCharacteristicRead(deviceId, characteristic, characteristic.value ?: ByteArray(0), status)
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int,
            ) {
                handleCharacteristicRead(deviceId, characteristic, value, status)
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                val key = characteristicKey(deviceId, characteristic.service.uuid.toString(), characteristic.uuid.toString())
                val result = pendingCharacteristicWrites.remove(key) ?: return
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    result.success(null)
                } else {
                    result.error("write_failed", "Characteristic write failed with status $status.", status)
                }
            }

            @Deprecated("Deprecated in Android 13")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                handleCharacteristicChanged(deviceId, characteristic, characteristic.value ?: ByteArray(0))
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                handleCharacteristicChanged(deviceId, characteristic, value)
            }

            @Deprecated("Deprecated in Android 13")
            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                handleDescriptorRead(deviceId, descriptor, descriptor.value ?: ByteArray(0), status)
            }

            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
                value: ByteArray,
            ) {
                handleDescriptorRead(deviceId, descriptor, value, status)
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                handleDescriptorWrite(deviceId, descriptor, status)
            }

            override fun onReadRemoteRssi(
                gatt: BluetoothGatt,
                rssi: Int,
                status: Int,
            ) {
                pendingRssiReads.remove(deviceId)?.let { result ->
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        result.success(rssi)
                    } else {
                        result.error("rssi_failed", "RSSI read failed with status $status.", status)
                    }
                }
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    sendEvent(mapOf("type" to "rssi", "deviceId" to deviceId, "rssi" to rssi))
                }
            }

            override fun onMtuChanged(
                gatt: BluetoothGatt,
                mtu: Int,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    knownMtus[deviceId] = mtu
                }
                pendingMtuRequests.remove(deviceId)?.let { result ->
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        result.success(mtu)
                    } else {
                        result.error("mtu_failed", "MTU request failed with status $status.", status)
                    }
                }
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    sendEvent(mapOf("type" to "mtu", "deviceId" to deviceId, "mtu" to mtu))
                }
            }
        }
    }

    private fun handleCharacteristicRead(
        deviceId: String,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        status: Int,
    ) {
        val key = characteristicKey(deviceId, characteristic.service.uuid.toString(), characteristic.uuid.toString())
        val result = pendingCharacteristicReads.remove(key) ?: return
        if (status == BluetoothGatt.GATT_SUCCESS) {
            result.success(value)
            sendCharacteristicValue(deviceId, characteristic, value)
        } else {
            result.error("read_failed", "Characteristic read failed with status $status.", status)
        }
    }

    private fun handleCharacteristicChanged(
        deviceId: String,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
    ) {
        sendCharacteristicValue(deviceId, characteristic, value)
    }

    private fun handleDescriptorRead(
        deviceId: String,
        descriptor: BluetoothGattDescriptor,
        value: ByteArray,
        status: Int,
    ) {
        val characteristic = descriptor.characteristic
        val key = descriptorKey(deviceId, characteristic.service.uuid.toString(), characteristic.uuid.toString(), descriptor.uuid.toString())
        val result = pendingDescriptorReads.remove(key) ?: return
        if (status == BluetoothGatt.GATT_SUCCESS) {
            result.success(value)
            sendDescriptorValue(deviceId, descriptor, value)
        } else {
            result.error("descriptor_read_failed", "Descriptor read failed with status $status.", status)
        }
    }

    private fun handleDescriptorWrite(
        deviceId: String,
        descriptor: BluetoothGattDescriptor,
        status: Int,
    ) {
        val characteristic = descriptor.characteristic
        val descriptorKey = descriptorKey(deviceId, characteristic.service.uuid.toString(), characteristic.uuid.toString(), descriptor.uuid.toString())
        val characteristicKey = characteristicKey(deviceId, characteristic.service.uuid.toString(), characteristic.uuid.toString())
        val result = pendingDescriptorWrites.remove(descriptorKey) ?: pendingNotificationWrites.remove(characteristicKey) ?: return
        if (status == BluetoothGatt.GATT_SUCCESS) {
            result.success(null)
        } else {
            result.error("descriptor_write_failed", "Descriptor write failed with status $status.", status)
        }
    }

    private fun sendCharacteristicValue(
        deviceId: String,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
    ) {
        sendEvent(
            mapOf(
                "type" to "characteristicValue",
                "deviceId" to deviceId,
                "serviceUuid" to characteristic.service.uuid.toString(),
                "characteristicUuid" to characteristic.uuid.toString(),
                "value" to value,
            ),
        )
    }

    private fun sendDescriptorValue(
        deviceId: String,
        descriptor: BluetoothGattDescriptor,
        value: ByteArray,
    ) {
        val characteristic = descriptor.characteristic
        sendEvent(
            mapOf(
                "type" to "descriptorValue",
                "deviceId" to deviceId,
                "serviceUuid" to characteristic.service.uuid.toString(),
                "characteristicUuid" to characteristic.uuid.toString(),
                "descriptorUuid" to descriptor.uuid.toString(),
                "value" to value,
            ),
        )
    }

    private fun sendConnectionState(
        deviceId: String,
        state: String,
        status: Int?,
    ) {
        sendEvent(
            mapOf(
                "type" to "connectionState",
                "deviceId" to deviceId,
                "state" to state,
                "status" to status,
            ).withoutNullValues(),
        )
    }

    private fun sendPhyEvent(
        deviceId: String,
        txPhy: Int,
        rxPhy: Int,
        status: Int,
    ) {
        sendEvent(phyEventMap(deviceId, txPhy, rxPhy, status))
    }

    private fun phyEventMap(
        deviceId: String,
        txPhy: Int,
        rxPhy: Int,
        status: Int,
    ): Map<String, Any?> {
        return mapOf(
            "type" to "phy",
            "deviceId" to deviceId,
            "txPhy" to phyString(txPhy),
            "rxPhy" to phyString(rxPhy),
            "status" to status,
        )
    }

    private fun androidPhy(value: String?): Int {
        return when (value) {
            "le2m" -> BluetoothDevice.PHY_LE_2M
            "leCoded" -> BluetoothDevice.PHY_LE_CODED
            else -> BluetoothDevice.PHY_LE_1M
        }
    }

    private fun phyString(value: Int): String {
        return when (value) {
            BluetoothDevice.PHY_LE_1M -> "le1m"
            BluetoothDevice.PHY_LE_2M -> "le2m"
            BluetoothDevice.PHY_LE_CODED -> "leCoded"
            else -> "unknown"
        }
    }

    private fun lastKnownMtu(deviceId: String): Int {
        return knownMtus[deviceId] ?: 23
    }

    private fun clearConnectTimeout(deviceId: String) {
        pendingConnectTimeouts.remove(deviceId)?.let { mainHandler.removeCallbacks(it) }
    }

    @SuppressLint("MissingPermission")
    private fun closeGatt(deviceId: String) {
        runCatching { gatts.remove(deviceId)?.close() }
        knownMtus.remove(deviceId)
    }

    @SuppressLint("MissingPermission")
    private fun closeAllGatts() {
        gatts.keys.toList().forEach { closeGatt(it) }
        connectionStates.clear()
    }

    private fun isPeripheralSupported(): Boolean {
        val adapter = adapter ?: return false
        return context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) &&
            adapter.bluetoothLeAdvertiser != null
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertising(
        call: MethodCall,
        result: Result,
    ) {
        if (!hasAdvertisePermission()) {
            result.error("permission_denied", "BLUETOOTH_ADVERTISE permission is required.", null)
            return
        }
        val advertiser = adapter?.bluetoothLeAdvertiser
        if (advertiser == null) {
            result.error("unsupported", "BLE advertising is not supported on this device.", null)
            return
        }
        if (pendingAdvertiseResult != null) {
            result.error("operation_in_progress", "An advertising request is already in progress.", null)
            return
        }
        stopAdvertisingInternal()
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val settings = advertisingSettings(args["settings"] as? Map<*, *>)
        val advertiseData = advertiseData(args["advertisementData"] as? Map<*, *>)
        val scanResponse = (args["scanResponse"] as? Map<*, *>)?.let { advertiseData(it) }
        pendingAdvertiseResult = result
        advertiseCallback =
            object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                    pendingAdvertiseResult?.success(null)
                    pendingAdvertiseResult = null
                    sendEvent(mapOf("type" to "advertisingState", "isAdvertising" to true))
                }

                override fun onStartFailure(errorCode: Int) {
                    pendingAdvertiseResult?.error("advertising_failed", "Advertising failed with code $errorCode.", errorCode)
                    pendingAdvertiseResult = null
                    advertiseCallback = null
                    sendEvent(mapOf("type" to "advertisingState", "isAdvertising" to false, "errorCode" to errorCode))
                }
            }
        advertiser.startAdvertising(settings, advertiseData, scanResponse, advertiseCallback)
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvertisingInternal() {
        advertiseCallback?.let { callback ->
            runCatching { adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback) }
        }
        advertiseCallback = null
        sendEvent(mapOf("type" to "advertisingState", "isAdvertising" to false))
    }

    private fun advertisingSettings(raw: Map<*, *>?): AdvertiseSettings {
        val mode =
            when (raw?.get("mode") as? String) {
                "lowPower" -> AdvertiseSettings.ADVERTISE_MODE_LOW_POWER
                "lowLatency" -> AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
                else -> AdvertiseSettings.ADVERTISE_MODE_BALANCED
            }
        val txPower =
            when (raw?.get("txPowerLevel") as? String) {
                "ultraLow" -> AdvertiseSettings.ADVERTISE_TX_POWER_ULTRA_LOW
                "low" -> AdvertiseSettings.ADVERTISE_TX_POWER_LOW
                "high" -> AdvertiseSettings.ADVERTISE_TX_POWER_HIGH
                else -> AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM
            }
        return AdvertiseSettings.Builder()
            .setAdvertiseMode(mode)
            .setTxPowerLevel(txPower)
            .setConnectable(raw?.get("connectable") as? Boolean ?: true)
            .setTimeout((raw?.get("timeoutMs") as? Number)?.toInt() ?: 0)
            .build()
    }

    private fun advertiseData(raw: Map<*, *>?): AdvertiseData {
        val builder = AdvertiseData.Builder()
            .setIncludeDeviceName(raw?.get("includeDeviceName") as? Boolean ?: false)
            .setIncludeTxPowerLevel(raw?.get("includeTxPowerLevel") as? Boolean ?: false)
        (raw?.get("serviceUuids") as? List<*>)?.forEach { uuid ->
            if (uuid != null) builder.addServiceUuid(ParcelUuid(normalizeUuid(uuid.toString())))
        }
        (raw?.get("manufacturerData") as? Map<*, *>)?.forEach { (key, value) ->
            val id = key.toString().toIntOrNull()
            if (id != null) builder.addManufacturerData(id, byteArrayArg(value))
        }
        (raw?.get("serviceData") as? Map<*, *>)?.forEach { (key, value) ->
            builder.addServiceData(ParcelUuid(normalizeUuid(key.toString())), byteArrayArg(value))
        }
        return builder.build()
    }

    @SuppressLint("MissingPermission")
    private fun setGattServerServices(
        call: MethodCall,
        result: Result,
    ) {
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        if (pendingGattServerServicesResult != null) {
            result.error("operation_in_progress", "A GATT service update is already in progress.", null)
            return
        }
        val server = ensureGattServer() ?: return result.error("unsupported", "Unable to open a GATT server.", null)
        server.clearServices()
        localCharacteristicValues.clear()
        localDescriptorValues.clear()
        val services = call.argument<List<Map<String, Any?>>>("services") ?: emptyList()
        if (services.isEmpty()) {
            result.error("invalid_arguments", "At least one GATT service is required.", null)
            return
        }
        pendingGattServerServicesResult = result
        pendingGattServerServiceCount = services.size
        services.forEach { serviceMap ->
            if (!server.addService(localGattService(serviceMap))) {
                pendingGattServerServicesResult?.error(
                    "gatt_service_failed",
                    "Android could not add the local GATT service.",
                    null,
                )
                pendingGattServerServicesResult = null
                pendingGattServerServiceCount = 0
                return
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun ensureGattServer(): BluetoothGattServer? {
        if (gattServer == null) {
            gattServer = bluetoothManager?.openGattServer(context, createGattServerCallback())
        }
        return gattServer
    }

    @SuppressLint("MissingPermission")
    private fun closeGattServer() {
        pendingGattServerServicesResult?.error(
            "gatt_server_closed",
            "The local GATT server was closed before setup completed.",
            null,
        )
        pendingGattServerServicesResult = null
        pendingGattServerServiceCount = 0
        runCatching { gattServer?.close() }
        gattServer = null
        localCharacteristicValues.clear()
        localDescriptorValues.clear()
    }

    private fun localGattService(map: Map<String, Any?>): BluetoothGattService {
        val serviceUuid = normalizeUuid(map["uuid"].toString())
        val type = if (map["isPrimary"] == false) BluetoothGattService.SERVICE_TYPE_SECONDARY else BluetoothGattService.SERVICE_TYPE_PRIMARY
        val service = BluetoothGattService(serviceUuid, type)
        val characteristics = map["characteristics"] as? List<*> ?: emptyList<Any?>()
        characteristics.forEach { item ->
            val characteristicMap = item as? Map<*, *> ?: return@forEach
            val characteristic = localGattCharacteristic(serviceUuid.toString(), characteristicMap)
            service.addCharacteristic(characteristic)
        }
        return service
    }

    private fun localGattCharacteristic(
        serviceUuid: String,
        map: Map<*, *>,
    ): BluetoothGattCharacteristic {
        val uuid = normalizeUuid(map["uuid"].toString())
        val properties = androidCharacteristicProperties(map["properties"] as? List<*>)
        val permissions = androidAttributePermissions(map["permissions"] as? List<*>)
        val characteristic = BluetoothGattCharacteristic(uuid, properties, permissions)
        val value = byteArrayArg(map["value"])
        localCharacteristicValues[characteristicKey("local", serviceUuid, uuid.toString())] = value
        val descriptors = map["descriptors"] as? List<*> ?: emptyList<Any?>()
        descriptors.forEach { item ->
            val descriptorMap = item as? Map<*, *> ?: return@forEach
            val descriptorUuid = normalizeUuid(descriptorMap["uuid"].toString())
            val descriptor = BluetoothGattDescriptor(descriptorUuid, permissions)
            @Suppress("DEPRECATION")
            descriptor.value = byteArrayArg(descriptorMap["value"])
            localDescriptorValues[descriptorKey("local", serviceUuid, uuid.toString(), descriptorUuid.toString())] =
                descriptor.value ?: ByteArray(0)
            characteristic.addDescriptor(descriptor)
        }
        return characteristic
    }

    private fun androidCharacteristicProperties(raw: List<*>?): Int {
        var value = 0
        val names = raw?.map { it.toString() } ?: emptyList()
        if ("broadcast" in names) value = value or BluetoothGattCharacteristic.PROPERTY_BROADCAST
        if ("read" in names) value = value or BluetoothGattCharacteristic.PROPERTY_READ
        if ("writeWithoutResponse" in names) value = value or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
        if ("write" in names) value = value or BluetoothGattCharacteristic.PROPERTY_WRITE
        if ("notify" in names) value = value or BluetoothGattCharacteristic.PROPERTY_NOTIFY
        if ("indicate" in names) value = value or BluetoothGattCharacteristic.PROPERTY_INDICATE
        if ("authenticatedSignedWrites" in names) value = value or BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE
        if ("extendedProperties" in names) value = value or BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS
        return value
    }

    private fun androidAttributePermissions(raw: List<*>?): Int {
        var value = 0
        val names = raw?.map { it.toString() } ?: emptyList()
        if ("read" in names || names.isEmpty()) value = value or BluetoothGattCharacteristic.PERMISSION_READ
        if ("readEncrypted" in names) value = value or BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
        if ("readEncryptedMitm" in names) value = value or BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED_MITM
        if ("write" in names || names.isEmpty()) value = value or BluetoothGattCharacteristic.PERMISSION_WRITE
        if ("writeEncrypted" in names) value = value or BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED
        if ("writeEncryptedMitm" in names) value = value or BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED_MITM
        if ("writeSigned" in names) value = value or BluetoothGattCharacteristic.PERMISSION_WRITE_SIGNED
        if ("writeSignedMitm" in names) value = value or BluetoothGattCharacteristic.PERMISSION_WRITE_SIGNED_MITM
        return value
    }

    private fun updateLocalCharacteristicValue(
        call: MethodCall,
        result: Result,
    ) {
        val serviceUuid = call.argument<String>("serviceUuid") ?: return result.error("invalid_arguments", "serviceUuid is required.", null)
        val characteristicUuid = call.argument<String>("characteristicUuid") ?: return result.error("invalid_arguments", "characteristicUuid is required.", null)
        val value = byteArrayArg(call.argument<Any>("value"))
        localCharacteristicValues[characteristicKey("local", serviceUuid, characteristicUuid)] = value
        findLocalCharacteristic(serviceUuid, characteristicUuid)?.let {
            @Suppress("DEPRECATION")
            it.value = value
        }
        result.success(null)
    }

    @SuppressLint("MissingPermission")
    private fun notifyGattServerCharacteristic(
        call: MethodCall,
        result: Result,
    ) {
        val serviceUuid = call.argument<String>("serviceUuid") ?: return result.error("invalid_arguments", "serviceUuid is required.", null)
        val characteristicUuid = call.argument<String>("characteristicUuid") ?: return result.error("invalid_arguments", "characteristicUuid is required.", null)
        val characteristic = findLocalCharacteristic(serviceUuid, characteristicUuid)
            ?: return result.error("characteristic_not_found", "Local characteristic was not found.", null)
        val value = byteArrayArg(call.argument<Any>("value"))
        val confirm = call.argument<Boolean>("confirm") ?: false
        @Suppress("DEPRECATION")
        characteristic.value = value
        localCharacteristicValues[characteristicKey("local", serviceUuid, characteristicUuid)] = value
        val server = gattServer ?: return result.error("gatt_server_unavailable", "GATT server is not open.", null)
        val deviceId = call.argument<String>("deviceId")
        val devices = if (deviceId == null) {
            bluetoothManager?.getConnectedDevices(BluetoothProfile.GATT_SERVER) ?: emptyList()
        } else {
            listOfNotNull(adapter?.getRemoteDevice(deviceId))
        }
        val sent = devices.map { device ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                server.notifyCharacteristicChanged(device, characteristic, confirm, value) == ANDROID_STATUS_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                server.notifyCharacteristicChanged(device, characteristic, confirm)
            }
        }
        result.success(sent.any { it })
    }

    private fun findLocalCharacteristic(
        serviceUuid: String,
        characteristicUuid: String,
    ): BluetoothGattCharacteristic? {
        return gattServer
            ?.getService(normalizeUuid(serviceUuid))
            ?.getCharacteristic(normalizeUuid(characteristicUuid))
    }

    @SuppressLint("MissingPermission")
    private fun createGattServerCallback(): BluetoothGattServerCallback {
        return object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(
                device: BluetoothDevice,
                status: Int,
                newState: Int,
            ) {
                sendEvent(
                    mapOf(
                        "type" to "gattServerRequest",
                        "event" to "connectionState",
                        "deviceId" to device.address,
                        "state" to if (newState == BluetoothProfile.STATE_CONNECTED) "connected" else "disconnected",
                        "status" to status,
                    ),
                )
            }

            override fun onServiceAdded(
                status: Int,
                service: BluetoothGattService,
            ) {
                val pendingResult = pendingGattServerServicesResult
                if (pendingResult != null) {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        pendingGattServerServicesResult = null
                        pendingGattServerServiceCount = 0
                        pendingResult.error(
                            "gatt_service_failed",
                            "Android could not add local GATT service (${service.uuid}); status $status.",
                            status,
                        )
                    } else {
                        pendingGattServerServiceCount -= 1
                        if (pendingGattServerServiceCount == 0) {
                            pendingGattServerServicesResult = null
                            pendingResult.success(null)
                        }
                    }
                }
                sendEvent(
                    mapOf(
                        "type" to "gattServerRequest",
                        "event" to "serviceAdded",
                        "deviceId" to "",
                        "serviceUuid" to service.uuid.toString(),
                        "status" to status,
                    ),
                )
            }

            override fun onCharacteristicReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                characteristic: BluetoothGattCharacteristic,
            ) {
                val key = characteristicKey("local", characteristic.service.uuid.toString(), characteristic.uuid.toString())
                val value = localCharacteristicValues[key] ?: ByteArray(0)
                val response = value.drop(offset.coerceAtMost(value.size)).toByteArray()
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, response)
                sendGattServerRequest("characteristicRead", device, requestId, offset, characteristic, null, response, false, true)
            }

            override fun onCharacteristicWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                characteristic: BluetoothGattCharacteristic,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray,
            ) {
                val key = characteristicKey("local", characteristic.service.uuid.toString(), characteristic.uuid.toString())
                localCharacteristicValues[key] = value
                @Suppress("DEPRECATION")
                characteristic.value = value
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
                sendGattServerRequest("characteristicWrite", device, requestId, offset, characteristic, null, value, preparedWrite, responseNeeded)
            }

            override fun onDescriptorReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                descriptor: BluetoothGattDescriptor,
            ) {
                val characteristic = descriptor.characteristic
                val key = descriptorKey("local", characteristic.service.uuid.toString(), characteristic.uuid.toString(), descriptor.uuid.toString())
                val value = localDescriptorValues[key] ?: ByteArray(0)
                val response = value.drop(offset.coerceAtMost(value.size)).toByteArray()
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, response)
                sendGattServerRequest("descriptorRead", device, requestId, offset, characteristic, descriptor, response, false, true)
            }

            override fun onDescriptorWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                descriptor: BluetoothGattDescriptor,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray,
            ) {
                val characteristic = descriptor.characteristic
                val key = descriptorKey("local", characteristic.service.uuid.toString(), characteristic.uuid.toString(), descriptor.uuid.toString())
                localDescriptorValues[key] = value
                @Suppress("DEPRECATION")
                descriptor.value = value
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
                sendGattServerRequest("descriptorWrite", device, requestId, offset, characteristic, descriptor, value, preparedWrite, responseNeeded)
                if (descriptor.uuid == CCCD_UUID) {
                    val subscribed = value.any { byte -> byte.toInt() != 0 }
                    sendEvent(
                        mapOf(
                            "type" to "gattServerRequest",
                            "event" to if (subscribed) "subscribed" else "unsubscribed",
                            "deviceId" to device.address,
                            "serviceUuid" to characteristic.service.uuid.toString(),
                            "characteristicUuid" to characteristic.uuid.toString(),
                            "descriptorUuid" to descriptor.uuid.toString(),
                            "value" to value,
                        ),
                    )
                }
            }

            override fun onNotificationSent(
                device: BluetoothDevice,
                status: Int,
            ) {
                sendEvent(
                    mapOf(
                        "type" to "gattServerRequest",
                        "event" to "notificationSent",
                        "deviceId" to device.address,
                        "status" to status,
                    ),
                )
            }
        }
    }

    private fun sendGattServerRequest(
        event: String,
        device: BluetoothDevice,
        requestId: Int,
        offset: Int,
        characteristic: BluetoothGattCharacteristic,
        descriptor: BluetoothGattDescriptor?,
        value: ByteArray,
        preparedWrite: Boolean,
        responseNeeded: Boolean,
    ) {
        sendEvent(
            mapOf(
                "type" to "gattServerRequest",
                "event" to event,
                "deviceId" to device.address,
                "serviceUuid" to characteristic.service.uuid.toString(),
                "characteristicUuid" to characteristic.uuid.toString(),
                "descriptorUuid" to descriptor?.uuid?.toString(),
                "requestId" to requestId,
                "offset" to offset,
                "value" to value,
                "preparedWrite" to preparedWrite,
                "responseNeeded" to responseNeeded,
            ).withoutNullValues(),
        )
    }

    @SuppressLint("MissingPermission")
    private fun connectClassic(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val serviceUuid = call.argument<String>("serviceUuid") ?: return result.error("invalid_arguments", "serviceUuid is required.", null)
        val secure = call.argument<Boolean>("secure") ?: true
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        val device = adapter?.getRemoteDevice(deviceId) ?: return result.error("unsupported", "Bluetooth is not supported.", null)
        sendClassicConnection(deviceId, "connecting", null)
        thread(name = "flutter-bt-classic-connect-$deviceId") {
            try {
                val socket = if (secure) {
                    device.createRfcommSocketToServiceRecord(normalizeUuid(serviceUuid))
                } else {
                    device.createInsecureRfcommSocketToServiceRecord(normalizeUuid(serviceUuid))
                }
                adapter?.cancelDiscovery()
                socket.connect()
                classicSockets[deviceId] = socket
                mainHandler.post { result.success(null) }
                sendClassicConnection(deviceId, "connected", null)
                startClassicReadLoop(deviceId, socket)
            } catch (error: Exception) {
                mainHandler.post { result.error("classic_connect_failed", error.message, null) }
                sendClassicConnection(deviceId, "disconnected", error.message)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startClassicServer(
        call: MethodCall,
        result: Result,
    ) {
        val serviceUuid = call.argument<String>("serviceUuid") ?: return result.error("invalid_arguments", "serviceUuid is required.", null)
        val serviceName = call.argument<String>("serviceName") ?: "FlutterBluetoothPlugin"
        val secure = call.argument<Boolean>("secure") ?: true
        if (!hasConnectPermission()) {
            result.error("permission_denied", "BLUETOOTH_CONNECT permission is required.", null)
            return
        }
        val adapter = adapter ?: return result.error("unsupported", "Bluetooth is not supported.", null)
        stopClassicServerInternal()
        classicServerSocket = if (secure) {
            adapter.listenUsingRfcommWithServiceRecord(serviceName, normalizeUuid(serviceUuid))
        } else {
            adapter.listenUsingInsecureRfcommWithServiceRecord(serviceName, normalizeUuid(serviceUuid))
        }
        classicServerRunning = true
        thread(name = "flutter-bt-classic-server") {
            while (classicServerRunning) {
                try {
                    val socket = classicServerSocket?.accept() ?: break
                    val deviceId = socket.remoteDevice.address
                    classicSockets[deviceId] = socket
                    sendClassicConnection(deviceId, "connected", null)
                    startClassicReadLoop(deviceId, socket)
                } catch (error: Exception) {
                    if (classicServerRunning) {
                        sendClassicConnection("", "disconnected", error.message)
                    }
                    break
                }
            }
        }
        result.success(null)
    }

    private fun stopClassicServerInternal() {
        classicServerRunning = false
        runCatching { classicServerSocket?.close() }
        classicServerSocket = null
    }

    private fun disconnectClassic(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        closeClassicSocket(deviceId)
        result.success(null)
    }

    private fun writeClassic(
        call: MethodCall,
        result: Result,
    ) {
        val deviceId = call.argument<String>("deviceId") ?: return result.error("invalid_arguments", "deviceId is required.", null)
        val value = byteArrayArg(call.argument<Any>("value"))
        val socket = classicSockets[deviceId] ?: return result.error("not_connected", "Classic socket is not connected.", null)
        thread(name = "flutter-bt-classic-write-$deviceId") {
            try {
                socket.outputStream.write(value)
                socket.outputStream.flush()
                mainHandler.post { result.success(null) }
            } catch (error: Exception) {
                mainHandler.post { result.error("classic_write_failed", error.message, null) }
                closeClassicSocket(deviceId)
            }
        }
    }

    private fun startClassicReadLoop(
        deviceId: String,
        socket: BluetoothSocket,
    ) {
        thread(name = "flutter-bt-classic-read-$deviceId") {
            val buffer = ByteArray(1024)
            try {
                while (classicSockets[deviceId] == socket) {
                    val count = socket.inputStream.read(buffer)
                    if (count < 0) break
                    sendEvent(mapOf("type" to "classicData", "deviceId" to deviceId, "value" to buffer.copyOf(count)))
                }
            } catch (error: Exception) {
                sendClassicConnection(deviceId, "disconnected", error.message)
            } finally {
                closeClassicSocket(deviceId)
            }
        }
    }

    private fun sendClassicConnection(
        deviceId: String,
        state: String,
        error: String?,
    ) {
        sendEvent(
            mapOf(
                "type" to "classicConnection",
                "deviceId" to deviceId,
                "state" to state,
                "error" to error,
            ).withoutNullValues(),
        )
    }

    private fun closeClassicSocket(deviceId: String) {
        runCatching { classicSockets.remove(deviceId)?.close() }
        sendClassicConnection(deviceId, "disconnected", null)
    }

    private fun closeAllClassicSockets() {
        classicSockets.keys.toList().forEach { closeClassicSocket(it) }
    }

    private fun characteristicRequest(call: MethodCall): CharacteristicRequest? {
        val deviceId = call.argument<String>("deviceId") ?: return null
        val serviceUuid = call.argument<String>("serviceUuid") ?: return null
        val characteristicUuid = call.argument<String>("characteristicUuid") ?: return null
        return CharacteristicRequest(deviceId, serviceUuid, characteristicUuid)
    }

    private fun descriptorRequest(call: MethodCall): DescriptorRequest? {
        val deviceId = call.argument<String>("deviceId") ?: return null
        val serviceUuid = call.argument<String>("serviceUuid") ?: return null
        val characteristicUuid = call.argument<String>("characteristicUuid") ?: return null
        val descriptorUuid = call.argument<String>("descriptorUuid") ?: return null
        return DescriptorRequest(deviceId, serviceUuid, characteristicUuid, descriptorUuid)
    }

    private fun findCharacteristic(
        gatt: BluetoothGatt,
        serviceUuid: String,
        characteristicUuid: String,
    ): BluetoothGattCharacteristic? {
        return gatt.getService(normalizeUuid(serviceUuid))?.getCharacteristic(normalizeUuid(characteristicUuid))
    }

    private fun findDescriptor(
        gatt: BluetoothGatt,
        request: DescriptorRequest,
    ): BluetoothGattDescriptor? {
        return findCharacteristic(gatt, request.serviceUuid, request.characteristicUuid)?.getDescriptor(normalizeUuid(request.descriptorUuid))
    }

    @SuppressLint("MissingPermission")
    private fun remoteDevice(call: MethodCall): BluetoothDevice? {
        val deviceId = call.argument<String>("deviceId") ?: return null
        return adapter?.getRemoteDevice(deviceId)
    }

    @SuppressLint("MissingPermission")
    private fun deviceMap(device: BluetoothDevice): Map<String, Any?> {
        return mapOf(
            "id" to device.address,
            "address" to device.address,
            "name" to device.safeName(),
            "type" to deviceTypeString(device.type),
            "isConnected" to (connectionStates[device.address] == "connected"),
            "isBonded" to (device.bondState == BluetoothDevice.BOND_BONDED),
        ).withoutNullValues()
    }

    private fun deviceTypeString(type: Int): String {
        return when (type) {
            BluetoothDevice.DEVICE_TYPE_CLASSIC -> "classic"
            BluetoothDevice.DEVICE_TYPE_LE -> "ble"
            BluetoothDevice.DEVICE_TYPE_DUAL -> "dual"
            else -> "unknown"
        }
    }

    private fun bondStateString(state: Int): String {
        return when (state) {
            BluetoothDevice.BOND_NONE -> "none"
            BluetoothDevice.BOND_BONDING -> "bonding"
            BluetoothDevice.BOND_BONDED -> "bonded"
            else -> "unknown"
        }
    }

    private fun serviceMap(service: BluetoothGattService): Map<String, Any?> {
        return mapOf(
            "uuid" to service.uuid.toString(),
            "isPrimary" to (service.type == BluetoothGattService.SERVICE_TYPE_PRIMARY),
            "includedServices" to emptyList<String>(),
            "characteristics" to service.characteristics.map { characteristicMap(service, it) },
        )
    }

    private fun characteristicMap(
        service: BluetoothGattService,
        characteristic: BluetoothGattCharacteristic,
    ): Map<String, Any?> {
        return mapOf(
            "uuid" to characteristic.uuid.toString(),
            "serviceUuid" to service.uuid.toString(),
            "properties" to characteristicProperties(characteristic.properties),
            "permissions" to characteristicPermissions(characteristic.permissions),
            "descriptors" to characteristic.descriptors.map { descriptorMap(characteristic, it) },
        )
    }

    @Suppress("DEPRECATION")
    private fun descriptorMap(
        characteristic: BluetoothGattCharacteristic,
        descriptor: BluetoothGattDescriptor,
    ): Map<String, Any?> {
        return mapOf(
            "uuid" to descriptor.uuid.toString(),
            "characteristicUuid" to characteristic.uuid.toString(),
            "value" to (descriptor.value ?: ByteArray(0)),
        )
    }

    private fun characteristicProperties(properties: Int): List<String> {
        val values = mutableListOf<String>()
        if (properties and BluetoothGattCharacteristic.PROPERTY_BROADCAST != 0) values += "broadcast"
        if (properties and BluetoothGattCharacteristic.PROPERTY_READ != 0) values += "read"
        if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) values += "writeWithoutResponse"
        if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) values += "write"
        if (properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) values += "notify"
        if (properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0) values += "indicate"
        if (properties and BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE != 0) values += "authenticatedSignedWrites"
        if (properties and BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS != 0) values += "extendedProperties"
        return values
    }

    private fun characteristicPermissions(permissions: Int): List<String> {
        val values = mutableListOf<String>()
        if (permissions and BluetoothGattCharacteristic.PERMISSION_READ != 0) values += "read"
        if (permissions and BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED != 0) values += "readEncrypted"
        if (permissions and BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED_MITM != 0) values += "readEncryptedMitm"
        if (permissions and BluetoothGattCharacteristic.PERMISSION_WRITE != 0) values += "write"
        if (permissions and BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED != 0) values += "writeEncrypted"
        if (permissions and BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED_MITM != 0) values += "writeEncryptedMitm"
        if (permissions and BluetoothGattCharacteristic.PERMISSION_WRITE_SIGNED != 0) values += "writeSigned"
        if (permissions and BluetoothGattCharacteristic.PERMISSION_WRITE_SIGNED_MITM != 0) values += "writeSignedMitm"
        return values
    }

    @SuppressLint("MissingPermission")
    private fun writeCharacteristicCompat(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        writeType: Int,
    ): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(characteristic, value, writeType) == ANDROID_STATUS_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = value
            characteristic.writeType = writeType
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeDescriptorCompat(
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
        value: ByteArray,
    ): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(descriptor, value) == ANDROID_STATUS_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = value
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(descriptor)
        }
    }

    private fun hasScanPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun hasConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasAdvertisePermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        receiverRegistered = true
    }

    private fun unregisterReceiver() {
        if (!receiverRegistered) return
        runCatching { context.unregisterReceiver(receiver) }
        receiverRegistered = false
    }

    private fun sendEvent(event: Map<String, Any?>) {
        val payload = event.withoutNullValues()
        mainHandler.post { eventSink?.success(payload) }
    }

    private fun normalizeUuid(uuid: String): UUID {
        val value = uuid.lowercase(Locale.US)
        val expanded = when (value.length) {
            4 -> "0000$value-0000-1000-8000-00805f9b34fb"
            8 -> "$value-0000-1000-8000-00805f9b34fb"
            else -> value
        }
        return UUID.fromString(expanded)
    }

    private fun characteristicKey(
        deviceId: String,
        serviceUuid: String,
        characteristicUuid: String,
    ): String {
        return listOf(deviceId, normalizeUuid(serviceUuid), normalizeUuid(characteristicUuid)).joinToString("|")
    }

    private fun descriptorKey(
        deviceId: String,
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String,
    ): String {
        return listOf(deviceId, normalizeUuid(serviceUuid), normalizeUuid(characteristicUuid), normalizeUuid(descriptorUuid)).joinToString("|")
    }

    @SuppressLint("MissingPermission")
    private fun BluetoothDevice.safeName(): String? {
        return runCatching { name }.getOrNull()
    }

    private fun byteArrayArg(value: Any?): ByteArray {
        return when (value) {
            is ByteArray -> value
            is IntArray -> value.map { it.toByte() }.toByteArray()
            is List<*> -> value.mapNotNull { (it as? Number)?.toByte() }.toByteArray()
            else -> ByteArray(0)
        }
    }

    private fun <T> Map<String, T?>.withoutNullValues(): Map<String, T> {
        return entries.mapNotNull { entry -> entry.value?.let { entry.key to it } }.toMap()
    }

    private data class CharacteristicRequest(
        val deviceId: String,
        val serviceUuid: String,
        val characteristicUuid: String,
    )

    private data class DescriptorRequest(
        val deviceId: String,
        val serviceUuid: String,
        val characteristicUuid: String,
        val descriptorUuid: String,
    )

    companion object {
        private const val REQUEST_PERMISSIONS_CODE = 8711
        private const val REQUEST_ENABLE_CODE = 8712
        private const val ANDROID_STATUS_SUCCESS = 0
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
