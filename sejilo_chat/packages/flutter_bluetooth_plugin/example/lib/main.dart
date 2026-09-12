import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin.dart';

void main() {
  runApp(const BluetoothTestApp());
}

class BluetoothTestApp extends StatelessWidget {
  const BluetoothTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      title: '蓝牙实验室',
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.activeBlue,
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
        textTheme: CupertinoTextThemeData(
          navLargeTitleTextStyle: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: CupertinoColors.label,
          ),
        ),
      ),
      home: BluetoothTesterPage(),
    );
  }
}

class BluetoothTesterPage extends StatefulWidget {
  const BluetoothTesterPage({super.key});

  @override
  State<BluetoothTesterPage> createState() => _BluetoothTesterPageState();
}

class _BluetoothTesterPageState extends State<BluetoothTesterPage> {
  static const Duration _scanTimeout = Duration(seconds: 15);
  static const String _sampleServiceUuid =
      '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String _sampleCharacteristicUuid =
      '0000fff1-0000-1000-8000-00805f9b34fb';
  static const String _classicSerialPortUuid =
      '00001101-0000-1000-8000-00805f9b34fb';

  final FlutterBluetoothPlugin _bluetooth = const FlutterBluetoothPlugin();
  final TextEditingController _writeController = TextEditingController(
    text: '你好',
  );
  final TextEditingController _adapterNameController = TextEditingController(
    text: 'Flutter 蓝牙',
  );
  final TextEditingController _serviceFilterController =
      TextEditingController();
  final TextEditingController _descriptorWriteController =
      TextEditingController(text: '01 00');
  final TextEditingController _classicWriteController = TextEditingController(
    text: '经典蓝牙测试',
  );
  final ScrollController _scrollController = ScrollController();
  final Map<String, BluetoothScanResult> _scanResults =
      <String, BluetoothScanResult>{};
  final List<String> _logs = <String>[];

  late final List<StreamSubscription<dynamic>> _subscriptions;
  Timer? _scanTimer;

  String _platformVersion = '加载中...';
  bool _supported = false;
  bool _peripheralSupported = false;
  bool _busy = false;
  bool _scanning = false;
  bool _advertising = false;
  bool _allowDuplicates = false;
  BluetoothScanMode _scanMode = BluetoothScanMode.ble;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  Map<String, BluetoothPermissionStatus> _permissions =
      <String, BluetoothPermissionStatus>{};
  BluetoothAdapterInfo? _adapterInfo;
  List<BluetoothDevice> _bondedDevices = <BluetoothDevice>[];
  List<BluetoothDevice> _connectedDevices = <BluetoothDevice>[];
  String _deviceLookupSummary = '尚未查询';

  BluetoothDevice? _activeDevice;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  List<BluetoothGattService> _services = <BluetoothGattService>[];
  BluetoothGattCharacteristic? _selectedCharacteristic;
  BluetoothGattDescriptor? _selectedDescriptor;
  Uint8List _lastCharacteristicValue = Uint8List(0);
  Uint8List _lastDescriptorValue = Uint8List(0);
  int? _lastRssi;
  int? _lastMtu;
  BluetoothPhyEvent? _lastPhy;
  BluetoothConnectionState _classicState =
      BluetoothConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _subscriptions = <StreamSubscription<dynamic>>[
      _bluetooth.adapterState.listen((BluetoothAdapterState state) {
        if (!mounted) return;
        setState(() => _adapterState = state);
        _addLog('适配器状态：${_adapterStateLabel(state)}');
      }),
      _bluetooth.scanResults.listen((BluetoothScanResult result) {
        if (!mounted) return;
        setState(() => _scanResults[result.device.id] = result);
      }),
      _bluetooth.connectionState.listen((BluetoothConnectionStateEvent event) {
        if (!mounted) return;
        if (_activeDevice?.id == event.deviceId) {
          setState(() => _connectionState = event.state);
        }
        _addLog('连接 ${event.deviceId}：${_connectionStateLabel(event.state)}');
      }),
      _bluetooth.characteristicValues.listen((
        BluetoothCharacteristicValue value,
      ) {
        if (!mounted) return;
        setState(() => _lastCharacteristicValue = value.value);
        _addLog(
          '特征值 ${value.characteristicUuid}：${_bytesPreview(value.value)}',
        );
      }),
      _bluetooth.descriptorValues.listen((BluetoothDescriptorValue value) {
        if (!mounted) return;
        setState(() => _lastDescriptorValue = value.value);
        _addLog('描述符 ${value.descriptorUuid}：${_bytesPreview(value.value)}');
      }),
      _bluetooth.rssiUpdates.listen((BluetoothRssiEvent event) {
        if (!mounted) return;
        setState(() => _lastRssi = event.rssi);
        _addLog('RSSI ${event.deviceId}：${event.rssi} dBm');
      }),
      _bluetooth.mtuUpdates.listen((BluetoothMtuEvent event) {
        if (!mounted) return;
        setState(() => _lastMtu = event.mtu);
        _addLog('MTU ${event.deviceId}：${event.mtu}');
      }),
      _bluetooth.bondState.listen((BluetoothBondStateEvent event) {
        if (!mounted) return;
        _addLog('绑定 ${event.deviceId}：${_bondStateLabel(event.state)}');
      }),
      _bluetooth.advertisingState.listen((
        BluetoothAdvertisingStateEvent event,
      ) {
        if (!mounted) return;
        setState(() => _advertising = event.isAdvertising);
        _addLog(
          '广播：${event.isAdvertising ? '开启' : '关闭'} ${event.message ?? ''}',
        );
      }),
      _bluetooth.gattServerRequests.listen((BluetoothGattServerRequest event) {
        if (!mounted) return;
        _addLog(
          'GATT 服务端 ${event.event}：${event.deviceId} ${event.characteristicUuid ?? event.serviceUuid ?? ''}',
        );
      }),
      _bluetooth.phyUpdates.listen((BluetoothPhyEvent event) {
        if (!mounted) return;
        setState(() => _lastPhy = event);
        _addLog(
          'PHY ${event.deviceId}：发送=${_phyLabel(event.txPhy)} 接收=${_phyLabel(event.rxPhy)}',
        );
      }),
      _bluetooth.classicConnectionState.listen((
        BluetoothClassicConnectionEvent event,
      ) {
        if (!mounted) return;
        setState(() => _classicState = event.state);
        _addLog('经典蓝牙 ${event.deviceId}：${_connectionStateLabel(event.state)}');
      }),
      _bluetooth.classicData.listen((BluetoothClassicDataEvent event) {
        if (!mounted) return;
        _addLog('经典蓝牙数据 ${event.deviceId}：${_bytesPreview(event.value)}');
      }),
    ];
    unawaited(_refreshAll());
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      subscription.cancel();
    }
    _writeController.dispose();
    _adapterNameController.dispose();
    _serviceFilterController.dispose();
    _descriptorWriteController.dispose();
    _classicWriteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('蓝牙实验室'),
        trailing: _busy
            ? const CupertinoActivityIndicator(radius: 10)
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _refreshAll,
                child: const Icon(CupertinoIcons.refresh),
              ),
      ),
      child: CupertinoScrollbar(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          children: <Widget>[
            _heroPanel(context),
            const SizedBox(height: 14),
            _diagnosticsSection(context),
            _permissionsSection(context),
            _scanSection(context),
            _connectionSection(context),
            _gattSection(context),
            _peripheralSection(context),
            _classicSection(context),
            _logSection(context),
          ],
        ),
      ),
    );
  }

  Widget _heroPanel(BuildContext context) {
    final Color accent = _adapterColor(context, _adapterState);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.20),
            CupertinoColors.systemIndigo
                .resolveFrom(context)
                .withValues(alpha: 0.08),
            CupertinoColors.white.withValues(alpha: 0.90),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    CupertinoIcons.bluetooth,
                    color: accent,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '原生蓝牙测试台',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _platformVersion,
                        style: TextStyle(
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _StatusPill(
                  label: _supported ? '支持' : '不支持',
                  color: _supported
                      ? CupertinoColors.activeGreen.resolveFrom(context)
                      : CupertinoColors.systemRed.resolveFrom(context),
                ),
                _StatusPill(
                  label: _adapterStateLabel(_adapterState),
                  color: accent,
                ),
                _StatusPill(
                  label: _connectionStateLabel(_connectionState),
                  color: _connectionColor(context, _connectionState),
                ),
                _StatusPill(
                  label: _peripheralSupported ? '外设模式可用' : '仅中心模式',
                  color: _peripheralSupported
                      ? CupertinoColors.activeGreen.resolveFrom(context)
                      : CupertinoColors.systemGrey.resolveFrom(context),
                ),
                if (_advertising)
                  _StatusPill(
                    label: '广播中',
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
                if (_lastRssi != null)
                  _StatusPill(
                    label: 'RSSI $_lastRssi dBm',
                    color: CupertinoColors.systemOrange.resolveFrom(context),
                  ),
                if (_lastMtu != null)
                  _StatusPill(
                    label: 'MTU $_lastMtu',
                    color: CupertinoColors.systemPurple.resolveFrom(context),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionsSection(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: const Text('权限'),
      footer: const Text(
        '扫描前请先处理权限。Android 会请求运行时权限；iOS 会在需要时触发 CoreBluetooth 授权。',
      ),
      children: <Widget>[
        CupertinoListTile(
          title: const Text('当前权限'),
          subtitle: Text(_permissionSummary()),
          leading: const Icon(CupertinoIcons.lock_shield),
        ),
        CupertinoListTile(
          title: const Text('适配器信息'),
          subtitle: Text(_adapterInfoSummary()),
          leading: const Icon(CupertinoIcons.info_circle),
        ),
        CupertinoListTile(
          title: const Text('请求权限'),
          leading: const Icon(CupertinoIcons.checkmark_shield),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: () => _guard('请求权限', () async {
            final Map<String, BluetoothPermissionStatus> permissions =
                await _bluetooth.requestPermissions();
            setState(() => _permissions = permissions);
          }),
        ),
        CupertinoListTile(
          title: const Text('请求开启蓝牙'),
          subtitle: const Text('Android 支持弹出开启蓝牙；iOS 无法由应用直接开启。'),
          leading: const Icon(CupertinoIcons.power),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: () => _guard('请求开启蓝牙', () async {
            final bool enabled = await _bluetooth.requestEnable();
            _addLog('请求开启蓝牙结果：$enabled');
            await _readPlatformState();
          }),
        ),
        CupertinoListTile(
          title: const Text('打开蓝牙设置'),
          leading: const Icon(CupertinoIcons.settings),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: () => _guard('打开设置', _bluetooth.openBluetoothSettings),
        ),
      ],
    );
  }

  Widget _diagnosticsSection(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: const Text('诊断'),
      footer: const Text('用于测试适配器改名、扫描状态、已连接设备查询、单个/批量设备查询和当前连接状态 API。'),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          child: CupertinoTextField(
            controller: _adapterNameController,
            placeholder: '适配器/本地名称',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.tag, size: 18),
            ),
          ),
        ),
        CupertinoListTile(
          title: const Text('设置适配器名称'),
          subtitle: const Text(
            'Android/Linux 可能生效；Apple、Windows 和 Web 通常返回 false。',
          ),
          leading: const Icon(CupertinoIcons.pencil_circle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _setAdapterName,
        ),
        CupertinoListTile(
          title: const Text('读取 isScanning()'),
          subtitle: Text(_scanning ? '上次状态：扫描中' : '上次状态：空闲'),
          leading: const Icon(CupertinoIcons.scope),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _checkScanningFlag,
        ),
        CupertinoListTile(
          title: const Text('加载已连接设备'),
          subtitle: Text(
            _connectedDevices.isEmpty
                ? '暂无已连接设备缓存'
                : '已连接 ${_connectedDevices.length} 个设备',
          ),
          leading: const Icon(CupertinoIcons.list_bullet_below_rectangle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _loadConnectedDevices,
        ),
        for (final BluetoothDevice device in _connectedDevices)
          CupertinoListTile(
            title: Text(_deviceTitle(device)),
            subtitle: Text('${device.id} · ${_deviceTypeLabel(device.type)}'),
            leading: const Icon(CupertinoIcons.checkmark_circle),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('使用'),
              onPressed: () => setState(() => _activeDevice = device),
            ),
          ),
        CupertinoListTile(
          title: const Text('查询活动/扫描设备'),
          subtitle: Text(_deviceLookupSummary),
          leading: const Icon(CupertinoIcons.search_circle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _lookupSingleDevice,
        ),
        CupertinoListTile(
          title: const Text('查询全部可见设备'),
          subtitle: const Text('使用扫描、已绑定、已连接设备 ID 调用 getDevices()。'),
          leading: const Icon(CupertinoIcons.square_stack_3d_up),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _lookupKnownDevices,
        ),
        CupertinoListTile(
          title: const Text('读取活动连接状态'),
          subtitle: Text(_connectionStateLabel(_connectionState)),
          leading: const Icon(CupertinoIcons.dot_radiowaves_left_right),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _activeDevice == null ? null : _refreshConnectionState,
        ),
      ],
    );
  }

  Widget _scanSection(BuildContext context) {
    final List<BluetoothScanResult> results = _scanResults.values.toList()
      ..sort(
        (BluetoothScanResult a, BluetoothScanResult b) =>
            b.rssi.compareTo(a.rssi),
      );

    return CupertinoListSection.insetGrouped(
      header: const Text('扫描'),
      footer: Text('发现 ${results.length} 个设备。Service UUID 过滤器在 Web 上尤其重要。'),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: CupertinoTextField(
            controller: _serviceFilterController,
            placeholder: 'Service UUID 过滤器，用逗号分隔',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.slider_horizontal_3, size: 18),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
          child: CupertinoSlidingSegmentedControl<BluetoothScanMode>(
            groupValue: _scanMode,
            children: const <BluetoothScanMode, Widget>{
              BluetoothScanMode.ble: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('BLE'),
              ),
              BluetoothScanMode.classic: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('经典'),
              ),
              BluetoothScanMode.dual: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('双模式'),
              ),
            },
            onValueChanged: (BluetoothScanMode? value) {
              if (value != null) {
                setState(() => _scanMode = value);
              }
            },
          ),
        ),
        CupertinoListTile(
          title: const Text('允许重复扫描事件'),
          leading: const Icon(CupertinoIcons.repeat),
          trailing: CupertinoSwitch(
            value: _allowDuplicates,
            onChanged: (bool value) => setState(() => _allowDuplicates = value),
          ),
        ),
        CupertinoListTile(
          title: Text(_scanning ? '停止扫描' : '开始 15 秒扫描'),
          subtitle: Text(
            _scanning
                ? '正在以 ${_scanModeLabel(_scanMode)} 模式扫描'
                : '扫描模式：${_scanModeLabel(_scanMode)}',
          ),
          leading: Icon(
            _scanning
                ? CupertinoIcons.stop_circle
                : CupertinoIcons.waveform_path_ecg,
          ),
          trailing: _scanning
              ? const CupertinoActivityIndicator(radius: 10)
              : const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _scanning ? _stopScan : _startScan,
        ),
        CupertinoListTile(
          title: const Text('加载已绑定设备'),
          subtitle: Text(
            _bondedDevices.isEmpty
                ? '暂无已绑定设备缓存'
                : '已绑定 ${_bondedDevices.length} 个设备',
          ),
          leading: const Icon(CupertinoIcons.link),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _loadBondedDevices,
        ),
        for (final BluetoothDevice device in _bondedDevices)
          CupertinoListTile(
            title: Text(_deviceTitle(device)),
            subtitle: Text('已绑定 · ${_deviceTypeLabel(device.type)}'),
            leading: const Icon(CupertinoIcons.link_circle),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('连接'),
              onPressed: () => _connect(device),
            ),
          ),
        for (final BluetoothScanResult result in results)
          CupertinoListTile(
            title: Text(_deviceTitle(result.device)),
            subtitle: Text(
              '${_deviceTypeLabel(result.device.type)} · RSSI ${result.rssi} · ${result.device.id}',
            ),
            leading: Icon(
              result.device.type == 'classic'
                  ? CupertinoIcons.device_phone_portrait
                  : CupertinoIcons.bluetooth,
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('连接'),
              onPressed: () => _connect(result.device),
            ),
          ),
      ],
    );
  }

  Widget _connectionSection(BuildContext context) {
    final BluetoothDevice? device = _activeDevice;
    return CupertinoListSection.insetGrouped(
      header: const Text('连接'),
      footer: const Text('请先连接设备，然后发现服务并测试 GATT 操作。'),
      children: <Widget>[
        CupertinoListTile(
          title: Text(device == null ? '暂无活动设备' : _deviceTitle(device)),
          subtitle: Text(
            device == null
                ? '请从扫描结果中选择设备'
                : '${device.id} · ${_connectionStateLabel(_connectionState)}',
          ),
          leading: const Icon(CupertinoIcons.dot_radiowaves_left_right),
        ),
        CupertinoListTile(
          title: const Text('发现服务'),
          subtitle: Text('已加载 ${_services.length} 个服务'),
          leading: const Icon(CupertinoIcons.square_stack_3d_down_right),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _discoverServices,
        ),
        CupertinoListTile(
          title: const Text('读取 RSSI'),
          subtitle: Text(
            _lastRssi == null ? '暂无 RSSI' : '上次 RSSI：$_lastRssi dBm',
          ),
          leading: const Icon(CupertinoIcons.antenna_radiowaves_left_right),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _readRssi,
        ),
        CupertinoListTile(
          title: const Text('请求 MTU 247'),
          subtitle: Text(
            _lastMtu == null
                ? 'Android 会协商 MTU；iOS 返回最大写入长度'
                : '上次 MTU：$_lastMtu',
          ),
          leading: const Icon(CupertinoIcons.resize),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : () => _requestMtu(247),
        ),
        CupertinoListTile(
          title: const Text('最大写入长度'),
          subtitle: const Text(
            'iOS 返回 CoreBluetooth 最大值；Android 使用当前 MTU - 3。',
          ),
          leading: const Icon(CupertinoIcons.arrow_left_right),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _getMaximumWriteLength,
        ),
        CupertinoListTile(
          title: const Text('读取 PHY'),
          subtitle: Text(
            _lastPhy == null
                ? 'Android 8+ 支持；iOS 返回未知'
                : '发送=${_phyLabel(_lastPhy!.txPhy)}，接收=${_phyLabel(_lastPhy!.rxPhy)}',
          ),
          leading: const Icon(CupertinoIcons.dot_radiowaves_right),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _readPhy,
        ),
        CupertinoListTile(
          title: const Text('优先使用 2M PHY'),
          subtitle: const Text('仅 Android 8+'),
          leading: const Icon(CupertinoIcons.bolt_horizontal_circle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _prefer2MPhy,
        ),
        CupertinoListTile(
          title: const Text('连接优先级'),
          subtitle: const Text('仅 Android。可测试均衡/高/低功耗连接提示。'),
          leading: const Icon(CupertinoIcons.speedometer),
          trailing: device == null
              ? null
              : Wrap(
                  spacing: 6,
                  children: <Widget>[
                    _InlineAction(
                      label: '均衡',
                      onPressed: () => _requestPriority(
                        BluetoothConnectionPriority.balanced,
                      ),
                    ),
                    _InlineAction(
                      label: '高速',
                      onPressed: () =>
                          _requestPriority(BluetoothConnectionPriority.high),
                    ),
                    _InlineAction(
                      label: '低功耗',
                      onPressed: () => _requestPriority(
                        BluetoothConnectionPriority.lowPower,
                      ),
                    ),
                  ],
                ),
        ),
        CupertinoListTile(
          title: const Text('创建绑定'),
          subtitle: const Text('仅 Android'),
          leading: const Icon(CupertinoIcons.plus_circle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _createBond,
        ),
        CupertinoListTile(
          title: const Text('移除绑定'),
          subtitle: const Text('仅 Android'),
          leading: const Icon(CupertinoIcons.minus_circle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _removeBond,
        ),
        CupertinoListTile(
          title: const Text('断开连接'),
          leading: const Icon(CupertinoIcons.xmark_circle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _disconnect,
        ),
      ],
    );
  }

  Widget _gattSection(BuildContext context) {
    final BluetoothGattCharacteristic? selected = _selectedCharacteristic;
    final BluetoothGattDescriptor? descriptor = _selectedDescriptor;
    return CupertinoListSection.insetGrouped(
      header: const Text('GATT 浏览器'),
      footer: const Text('点击特征或描述符后，可对目标执行读、写和通知操作。'),
      children: <Widget>[
        if (_services.isEmpty)
          const CupertinoListTile(
            title: Text('尚未发现服务'),
            subtitle: Text('连接后请点击“发现服务”。'),
            leading: Icon(CupertinoIcons.square_stack_3d_down_right),
          ),
        for (final BluetoothGattService service in _services) ...<Widget>[
          CupertinoListTile(
            title: Text(service.uuid),
            subtitle: Text(service.isPrimary ? '主服务' : '次级服务'),
            leading: const Icon(CupertinoIcons.cube_box),
          ),
          for (final BluetoothGattCharacteristic characteristic
              in service.characteristics)
            CupertinoListTile(
              title: Text(characteristic.uuid),
              subtitle: Text(_propertySummary(characteristic.properties)),
              leading: Icon(
                selected?.uuid == characteristic.uuid &&
                        selected?.serviceUuid == characteristic.serviceUuid
                    ? CupertinoIcons.largecircle_fill_circle
                    : CupertinoIcons.circle,
              ),
              trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
              onTap: () {
                setState(() {
                  _selectedCharacteristic = characteristic;
                  _selectedDescriptor = null;
                });
              },
            ),
          for (final BluetoothGattCharacteristic characteristic
              in service.characteristics)
            for (final BluetoothGattDescriptor item
                in characteristic.descriptors)
              CupertinoListTile(
                title: Text(item.uuid),
                subtitle: Text('${characteristic.uuid} 的描述符'),
                leading: Icon(
                  descriptor?.uuid == item.uuid &&
                          descriptor?.characteristicUuid == characteristic.uuid
                      ? CupertinoIcons.smallcircle_fill_circle
                      : CupertinoIcons.smallcircle_circle,
                ),
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: () {
                  setState(() {
                    _selectedCharacteristic = characteristic;
                    _selectedDescriptor = item;
                  });
                },
              ),
        ],
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '已选择特征',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  selected.uuid,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: _writeController,
                  placeholder: '文本或十六进制字节，例如 你好 / 01 02',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(CupertinoIcons.text_cursor, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _SmallActionButton(
                      label: '读取',
                      onPressed: _readCharacteristic,
                    ),
                    _SmallActionButton(
                      label: '写入',
                      onPressed: _writeCharacteristic,
                    ),
                    _SmallActionButton(
                      label: '无响应写入',
                      onPressed: _writeCharacteristicWithoutResponse,
                    ),
                    _SmallActionButton(
                      label: '开启通知',
                      onPressed: () => _setNotification(true),
                    ),
                    _SmallActionButton(
                      label: '关闭通知',
                      onPressed: () => _setNotification(false),
                    ),
                  ],
                ),
                if (_lastCharacteristicValue.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text('上次值：${_bytesPreview(_lastCharacteristicValue)}'),
                ],
              ],
            ),
          ),
        if (descriptor != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '已选择描述符',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  descriptor.uuid,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: _descriptorWriteController,
                  placeholder: '十六进制字节，例如 01 00',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(CupertinoIcons.number, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _SmallActionButton(
                      label: '读取描述符',
                      onPressed: _readDescriptor,
                    ),
                    _SmallActionButton(
                      label: '写入描述符',
                      onPressed: _writeDescriptor,
                    ),
                  ],
                ),
                if (_lastDescriptorValue.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text('上次描述符：${_bytesPreview(_lastDescriptorValue)}'),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _peripheralSection(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: const Text('外设 / 广播'),
      footer: const Text(
        '创建示例 GATT Server 并进行广播。iOS 支持本地名称和服务 UUID；Android 还支持厂商/服务数据。',
      ),
      children: <Widget>[
        CupertinoListTile(
          title: const Text('外设模式支持'),
          subtitle: Text(_peripheralSupported ? '可用' : '不可用'),
          leading: const Icon(CupertinoIcons.antenna_radiowaves_left_right),
        ),
        CupertinoListTile(
          title: const Text('安装示例 GATT 服务'),
          subtitle: const Text('FFF0 服务，包含 FFF1 读/写/通知特征'),
          leading: const Icon(CupertinoIcons.cube_box_fill),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _setSampleGattServer,
        ),
        CupertinoListTile(
          title: Text(_advertising ? '停止广播' : '开始广播'),
          subtitle: Text(_advertising ? '正在广播示例服务' : _sampleServiceUuid),
          leading: Icon(
            _advertising
                ? CupertinoIcons.stop_circle
                : CupertinoIcons.radiowaves_right,
          ),
          trailing: _advertising
              ? const CupertinoActivityIndicator(radius: 10)
              : const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _advertising ? _stopAdvertising : _startAdvertising,
        ),
        CupertinoListTile(
          title: const Text('通知示例值'),
          subtitle: const Text('将写入框中的文本发送给已订阅的中心设备'),
          leading: const Icon(CupertinoIcons.bell),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _notifySampleCharacteristic,
        ),
        CupertinoListTile(
          title: const Text('指示示例值'),
          subtitle: const Text('平台支持时使用 confirm: true。'),
          leading: const Icon(CupertinoIcons.bell_circle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: () => _notifySampleCharacteristic(confirm: true),
        ),
        CupertinoListTile(
          title: const Text('清空 GATT 服务'),
          subtitle: const Text('停止暴露本地示例服务。'),
          leading: const Icon(CupertinoIcons.clear_circled),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _clearGattServerServices,
        ),
      ],
    );
  }

  Widget _classicSection(BuildContext context) {
    final BluetoothDevice? device = _activeDevice;
    return CupertinoListSection.insetGrouped(
      header: const Text('经典蓝牙 RFCOMM'),
      footer: const Text('仅 Android。默认使用 Serial Port Profile UUID。'),
      children: <Widget>[
        CupertinoListTile(
          title: const Text('经典蓝牙 Socket 状态'),
          subtitle: Text(_connectionStateLabel(_classicState)),
          leading: const Icon(CupertinoIcons.device_phone_portrait),
        ),
        CupertinoListTile(
          title: const Text('启动 RFCOMM 服务端'),
          subtitle: Text(_classicSerialPortUuid),
          leading: const Icon(CupertinoIcons.tray_full),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _startClassicServer,
        ),
        CupertinoListTile(
          title: const Text('停止 RFCOMM 服务端'),
          leading: const Icon(CupertinoIcons.stop),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: _stopClassicServer,
        ),
        CupertinoListTile(
          title: const Text('通过 RFCOMM 连接活动设备'),
          subtitle: Text(device == null ? '请先选择已扫描到的经典/双模式设备' : device.id),
          leading: const Icon(CupertinoIcons.link),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _connectClassic,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
          child: CupertinoTextField(
            controller: _classicWriteController,
            placeholder: '经典蓝牙 Socket 文本或十六进制字节',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.text_bubble, size: 18),
            ),
          ),
        ),
        CupertinoListTile(
          title: const Text('写入经典蓝牙数据'),
          leading: const Icon(CupertinoIcons.paperplane),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _writeClassic,
        ),
        CupertinoListTile(
          title: const Text('断开经典蓝牙 Socket'),
          leading: const Icon(CupertinoIcons.xmark_circle),
          trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
          onTap: device == null ? null : _disconnectClassic,
        ),
      ],
    );
  }

  Widget _logSection(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: const Text('事件日志'),
      children: <Widget>[
        if (_logs.isEmpty)
          const CupertinoListTile(
            title: Text('暂无事件'),
            leading: Icon(CupertinoIcons.doc_text),
          ),
        for (final String log in _logs.take(18))
          CupertinoListTile(
            title: Text(log),
            leading: const Icon(CupertinoIcons.chevron_right_circle),
          ),
      ],
    );
  }

  Future<void> _refreshAll() async {
    await _guard('刷新平台状态', _readPlatformState, silentSuccess: true);
  }

  Future<void> _readPlatformState() async {
    final String version = await _bluetooth.getPlatformVersion() ?? '未知平台';
    final bool supported = await _bluetooth.isSupported();
    final bool peripheralSupported = await _bluetooth.isPeripheralSupported();
    final BluetoothAdapterState state = await _bluetooth.getAdapterState();
    final bool scanning = await _bluetooth.isScanning();
    final BluetoothAdapterInfo adapterInfo = await _bluetooth.getAdapterInfo();
    final Map<String, BluetoothPermissionStatus> permissions = await _bluetooth
        .checkPermissions();
    if (!mounted) return;
    setState(() {
      _platformVersion = version;
      _supported = supported;
      _peripheralSupported = peripheralSupported;
      _adapterState = state;
      _scanning = scanning;
      _adapterInfo = adapterInfo;
      _permissions = permissions;
    });
  }

  Future<void> _setAdapterName() async {
    await _guard('设置适配器名称', () async {
      final String name = _adapterNameController.text.trim();
      if (name.isEmpty) {
        await _showError('适配器名称', '请先输入非空名称。');
        return;
      }
      final bool changed = await _bluetooth.setAdapterName(name);
      _addLog('适配器名称修改结果：$changed');
      final BluetoothAdapterInfo adapterInfo = await _bluetooth
          .getAdapterInfo();
      setState(() => _adapterInfo = adapterInfo);
    });
  }

  Future<void> _checkScanningFlag() async {
    await _guard('读取 isScanning()', () async {
      final bool scanning = await _bluetooth.isScanning();
      setState(() => _scanning = scanning);
      _addLog('isScanning()：$scanning');
    });
  }

  Future<void> _startScan() async {
    await _guard('开始扫描', () async {
      setState(() {
        _scanResults.clear();
        _scanning = true;
      });
      await _bluetooth.startScan(
        serviceUuids: _serviceFilters(),
        scanMode: _scanMode,
        timeout: _scanTimeout,
        allowDuplicates: _allowDuplicates,
      );
      _scanTimer?.cancel();
      _scanTimer = Timer(_scanTimeout, () {
        if (mounted) {
          setState(() => _scanning = false);
        }
      });
    });
  }

  Future<void> _loadConnectedDevices() async {
    await _guard('加载已连接设备', () async {
      final List<BluetoothDevice> devices = await _bluetooth
          .getConnectedDevices(serviceUuids: _serviceFilters());
      setState(() => _connectedDevices = devices);
    });
  }

  Future<void> _lookupSingleDevice() async {
    await _guard('查询单个设备', () async {
      final List<String> ids = _candidateDeviceIds();
      final String? deviceId = ids.isEmpty ? null : ids.first;
      if (deviceId == null) {
        await _showError('查询设备', '请先扫描或选择设备。');
        return;
      }
      final BluetoothDevice? device = await _bluetooth.getDevice(deviceId);
      setState(() {
        _deviceLookupSummary = device == null
            ? '未找到设备：$deviceId'
            : '${_deviceTitle(device)} · ${device.id}';
      });
    });
  }

  Future<void> _lookupKnownDevices() async {
    await _guard('查询已知设备', () async {
      final List<String> ids = _candidateDeviceIds();
      if (ids.isEmpty) {
        await _showError('查询设备', '请先扫描或加载设备。');
        return;
      }
      final List<BluetoothDevice> devices = await _bluetooth.getDevices(ids);
      setState(() {
        _deviceLookupSummary = '已解析 ${devices.length}/${ids.length} 个可见设备';
      });
    });
  }

  Future<void> _stopScan() async {
    await _guard('停止扫描', () async {
      await _bluetooth.stopScan();
      _scanTimer?.cancel();
      setState(() => _scanning = false);
    });
  }

  Future<void> _loadBondedDevices() async {
    await _guard('加载已绑定设备', () async {
      final List<BluetoothDevice> devices = await _bluetooth.getBondedDevices();
      setState(() => _bondedDevices = devices);
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    await _guard('连接 ${device.name ?? device.id}', () async {
      await _bluetooth.connect(device.id, timeout: const Duration(seconds: 15));
      final BluetoothConnectionState state = await _bluetooth
          .getConnectionState(device.id);
      setState(() {
        _activeDevice = device;
        _connectionState = state;
        _services = <BluetoothGattService>[];
        _selectedCharacteristic = null;
        _selectedDescriptor = null;
      });
    });
  }

  Future<void> _refreshConnectionState() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('读取连接状态', () async {
      final BluetoothConnectionState state = await _bluetooth
          .getConnectionState(device.id);
      setState(() => _connectionState = state);
    });
  }

  Future<void> _disconnect() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('断开连接', () async {
      await _bluetooth.disconnect(device.id);
      setState(() {
        _connectionState = BluetoothConnectionState.disconnected;
        _services = <BluetoothGattService>[];
        _selectedCharacteristic = null;
        _selectedDescriptor = null;
      });
    });
  }

  Future<void> _discoverServices() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('发现服务', () async {
      final List<BluetoothGattService> services = await _bluetooth
          .discoverServices(device.id);
      setState(() {
        _services = services;
        _selectedCharacteristic = null;
        _selectedDescriptor = null;
      });
    });
  }

  Future<void> _readCharacteristic() async {
    final CharacteristicTarget? target = _characteristicTarget();
    if (target == null) return;
    await _guard('读取特征', () async {
      final Uint8List value = await _bluetooth.readCharacteristic(
        deviceId: target.deviceId,
        serviceUuid: target.characteristic.serviceUuid,
        characteristicUuid: target.characteristic.uuid,
      );
      setState(() => _lastCharacteristicValue = value);
    });
  }

  Future<void> _writeCharacteristic() async {
    await _writeSelectedCharacteristic(BluetoothWriteType.withResponse);
  }

  Future<void> _writeCharacteristicWithoutResponse() async {
    await _writeSelectedCharacteristic(BluetoothWriteType.withoutResponse);
  }

  Future<void> _writeSelectedCharacteristic(
    BluetoothWriteType writeType,
  ) async {
    final CharacteristicTarget? target = _characteristicTarget();
    if (target == null) return;
    await _guard('写入特征', () async {
      await _bluetooth.writeCharacteristic(
        deviceId: target.deviceId,
        serviceUuid: target.characteristic.serviceUuid,
        characteristicUuid: target.characteristic.uuid,
        value: _parseBytes(_writeController.text),
        writeType: writeType,
      );
    });
  }

  Future<void> _setNotification(bool enable) async {
    final CharacteristicTarget? target = _characteristicTarget();
    if (target == null) return;
    await _guard(enable ? '开启通知' : '关闭通知', () async {
      await _bluetooth.setCharacteristicNotification(
        deviceId: target.deviceId,
        serviceUuid: target.characteristic.serviceUuid,
        characteristicUuid: target.characteristic.uuid,
        enable: enable,
      );
    });
  }

  Future<void> _readDescriptor() async {
    final DescriptorTarget? target = _descriptorTarget();
    if (target == null) return;
    await _guard('读取描述符', () async {
      final Uint8List value = await _bluetooth.readDescriptor(
        deviceId: target.deviceId,
        serviceUuid: target.characteristic.serviceUuid,
        characteristicUuid: target.characteristic.uuid,
        descriptorUuid: target.descriptor.uuid,
      );
      setState(() => _lastDescriptorValue = value);
    });
  }

  Future<void> _writeDescriptor() async {
    final DescriptorTarget? target = _descriptorTarget();
    if (target == null) return;
    await _guard('写入描述符', () async {
      await _bluetooth.writeDescriptor(
        deviceId: target.deviceId,
        serviceUuid: target.characteristic.serviceUuid,
        characteristicUuid: target.characteristic.uuid,
        descriptorUuid: target.descriptor.uuid,
        value: _parseBytes(_descriptorWriteController.text),
      );
    });
  }

  Future<void> _readRssi() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('读取 RSSI', () async {
      final int rssi = await _bluetooth.readRssi(device.id);
      setState(() => _lastRssi = rssi);
    });
  }

  Future<void> _requestMtu(int mtu) async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('请求 MTU', () async {
      final int resolvedMtu = await _bluetooth.requestMtu(device.id, mtu);
      setState(() => _lastMtu = resolvedMtu);
    });
  }

  Future<void> _getMaximumWriteLength() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('获取最大写入长度', () async {
      final int withoutResponse = await _bluetooth.getMaximumWriteLength(
        device.id,
      );
      final int withResponse = await _bluetooth.getMaximumWriteLength(
        device.id,
        withoutResponse: false,
      );
      _addLog('最大写入长度：无响应=$withoutResponse，有响应=$withResponse');
    });
  }

  Future<void> _readPhy() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('读取 PHY', () async {
      final BluetoothPhyEvent phy = await _bluetooth.readPhy(device.id);
      setState(() => _lastPhy = phy);
    });
  }

  Future<void> _prefer2MPhy() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('优先使用 2M PHY', () async {
      await _bluetooth.setPreferredPhy(
        deviceId: device.id,
        txPhy: BluetoothPhy.le2m,
        rxPhy: BluetoothPhy.le2m,
      );
    });
  }

  Future<void> _requestPriority(BluetoothConnectionPriority priority) async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('请求 ${_priorityLabel(priority)} 优先级', () async {
      final bool accepted = await _bluetooth.requestConnectionPriority(
        device.id,
        priority,
      );
      _addLog('${_priorityLabel(priority)} 优先级结果：$accepted');
    });
  }

  Future<void> _createBond() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('创建绑定', () async {
      final bool started = await _bluetooth.createBond(device.id);
      _addLog('创建绑定已开始：$started');
    });
  }

  Future<void> _removeBond() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('移除绑定', () async {
      final bool removed = await _bluetooth.removeBond(device.id);
      _addLog('移除绑定结果：$removed');
    });
  }

  Future<void> _setSampleGattServer() async {
    await _guard('安装示例 GATT 服务', () async {
      await _bluetooth.setGattServerServices(<BluetoothGattService>[
        BluetoothGattService(
          uuid: _sampleServiceUuid,
          characteristics: <BluetoothGattCharacteristic>[
            BluetoothGattCharacteristic(
              uuid: _sampleCharacteristicUuid,
              serviceUuid: _sampleServiceUuid,
              properties: <String>[
                'read',
                'write',
                'writeWithoutResponse',
                'notify',
              ],
              permissions: <String>['read', 'write'],
              value: Uint8List.fromList(<int>[72, 101, 108, 108, 111]),
              descriptors: <BluetoothGattDescriptor>[
                BluetoothGattDescriptor(
                  uuid: '00002901-0000-1000-8000-00805f9b34fb',
                  characteristicUuid: _sampleCharacteristicUuid,
                  value: Uint8List.fromList(<int>[83, 97, 109, 112, 108, 101]),
                ),
              ],
            ),
          ],
        ),
      ]);
    });
  }

  Future<void> _startAdvertising() async {
    await _guard('开始广播', () async {
      await _bluetooth.startAdvertising(
        advertisementData: BluetoothAdvertisementData(
          localName: _adapterNameController.text.trim().isEmpty
              ? 'Flutter 蓝牙'
              : _adapterNameController.text.trim(),
          serviceUuids: <String>[_sampleServiceUuid],
          includeDeviceName: true,
          includeTxPowerLevel: true,
          manufacturerData: <int, Uint8List>{
            0xffff: Uint8List.fromList(<int>[0x46, 0x42]),
          },
          serviceData: <String, Uint8List>{
            _sampleServiceUuid: Uint8List.fromList(<int>[0x01, 0x02]),
          },
        ),
        scanResponse: BluetoothAdvertisementData(
          localName: 'Flutter 蓝牙测试',
          serviceUuids: <String>[_sampleServiceUuid],
          manufacturerData: <int, Uint8List>{
            0xffff: Uint8List.fromList(<int>[0x54, 0x45, 0x53, 0x54]),
          },
        ),
        settings: const BluetoothAdvertisingSettings(
          mode: BluetoothAdvertisingMode.lowLatency,
          txPowerLevel: BluetoothTxPowerLevel.high,
          connectable: true,
          timeout: Duration(minutes: 3),
        ),
      );
      setState(() => _advertising = true);
    });
  }

  Future<void> _stopAdvertising() async {
    await _guard('停止广播', () async {
      await _bluetooth.stopAdvertising();
      setState(() => _advertising = false);
    });
  }

  Future<void> _notifySampleCharacteristic({bool confirm = false}) async {
    await _guard(confirm ? '指示示例特征' : '通知示例特征', () async {
      final Uint8List value = _parseBytes(_writeController.text);
      await _bluetooth.updateLocalCharacteristicValue(
        serviceUuid: _sampleServiceUuid,
        characteristicUuid: _sampleCharacteristicUuid,
        value: value,
      );
      final bool sent = await _bluetooth.notifyGattServerCharacteristic(
        serviceUuid: _sampleServiceUuid,
        characteristicUuid: _sampleCharacteristicUuid,
        value: value,
        confirm: confirm,
      );
      _addLog('本地${confirm ? '指示' : '通知'}发送结果：$sent');
    });
  }

  Future<void> _clearGattServerServices() async {
    await _guard('清空 GATT 服务', _bluetooth.clearGattServerServices);
  }

  Future<void> _connectClassic() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('连接经典蓝牙', () async {
      await _bluetooth.connectClassic(
        deviceId: device.id,
        serviceUuid: _classicSerialPortUuid,
        timeout: const Duration(seconds: 15),
      );
    });
  }

  Future<void> _startClassicServer() async {
    await _guard('启动经典蓝牙服务端', () async {
      await _bluetooth.startClassicServer(
        serviceUuid: _classicSerialPortUuid,
        serviceName: 'FlutterBluetoothPlugin',
      );
    });
  }

  Future<void> _stopClassicServer() async {
    await _guard('停止经典蓝牙服务端', _bluetooth.stopClassicServer);
  }

  Future<void> _writeClassic() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('写入经典蓝牙数据', () async {
      await _bluetooth.writeClassic(
        device.id,
        _parseBytes(_classicWriteController.text),
      );
    });
  }

  Future<void> _disconnectClassic() async {
    final BluetoothDevice? device = _activeDevice;
    if (device == null) return;
    await _guard('断开经典蓝牙', () async {
      await _bluetooth.disconnectClassic(device.id);
    });
  }

  CharacteristicTarget? _characteristicTarget() {
    final BluetoothDevice? device = _activeDevice;
    final BluetoothGattCharacteristic? characteristic = _selectedCharacteristic;
    if (device == null || characteristic == null) {
      unawaited(_showError('选择目标', '请先连接设备并选择一个特征。'));
      return null;
    }
    return CharacteristicTarget(device.id, characteristic);
  }

  DescriptorTarget? _descriptorTarget() {
    final CharacteristicTarget? characteristicTarget = _characteristicTarget();
    final BluetoothGattDescriptor? descriptor = _selectedDescriptor;
    if (characteristicTarget == null) return null;
    if (descriptor == null) {
      unawaited(_showError('选择目标', '请先选择一个描述符。'));
      return null;
    }
    return DescriptorTarget(
      characteristicTarget.deviceId,
      characteristicTarget.characteristic,
      descriptor,
    );
  }

  Future<void> _guard(
    String label,
    Future<void> Function() operation, {
    bool silentSuccess = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (!silentSuccess) {
        _addLog('$label 完成');
      }
    } on PlatformException catch (error) {
      final String message = error.message ?? error.code;
      _addLog('$label 失败：$message');
      await _showError(label, message);
    } catch (error) {
      _addLog('$label 失败：$error');
      await _showError(label, error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showError(String title, String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.insert(
        0,
        '${DateTime.now().toIso8601String().substring(11, 19)}  $message',
      );
      if (_logs.length > 80) {
        _logs.removeRange(80, _logs.length);
      }
    });
  }

  String _permissionSummary() {
    if (_permissions.isEmpty) {
      return '未知';
    }
    return _permissions.entries
        .map(
          (MapEntry<String, BluetoothPermissionStatus> entry) =>
              '${entry.key}: ${_permissionStatusLabel(entry.value)}',
        )
        .join('\n');
  }

  String _adapterInfoSummary() {
    final BluetoothAdapterInfo? info = _adapterInfo;
    if (info == null) {
      return '未知';
    }
    return <String>[
      '状态：${_adapterStateLabel(info.state)}',
      if (info.name != null) '名称：${info.name}',
      if (info.address != null) '地址：${info.address}',
      'BLE: ${info.isBleSupported}',
      '广播：${info.isMultipleAdvertisementSupported}',
      '2M PHY: ${info.isLe2MPhySupported}',
      'Coded PHY：${info.isLeCodedPhySupported}',
      '发现中：${info.isDiscovering}',
    ].join('\n');
  }

  String _adapterStateLabel(BluetoothAdapterState state) {
    return switch (state) {
      BluetoothAdapterState.unknown => '未知',
      BluetoothAdapterState.unsupported => '不支持',
      BluetoothAdapterState.unauthorized => '未授权',
      BluetoothAdapterState.poweredOff => '已关闭',
      BluetoothAdapterState.poweredOn => '已开启',
      BluetoothAdapterState.resetting => '重置中',
      BluetoothAdapterState.turningOn => '开启中',
      BluetoothAdapterState.turningOff => '关闭中',
    };
  }

  String _permissionStatusLabel(BluetoothPermissionStatus status) {
    return switch (status) {
      BluetoothPermissionStatus.unknown => '未知',
      BluetoothPermissionStatus.notDetermined => '未决定',
      BluetoothPermissionStatus.granted => '已授权',
      BluetoothPermissionStatus.denied => '已拒绝',
      BluetoothPermissionStatus.restricted => '受限制',
      BluetoothPermissionStatus.permanentlyDenied => '永久拒绝',
      BluetoothPermissionStatus.notApplicable => '不适用',
    };
  }

  String _scanModeLabel(BluetoothScanMode mode) {
    return switch (mode) {
      BluetoothScanMode.ble => 'BLE',
      BluetoothScanMode.classic => '经典',
      BluetoothScanMode.dual => '双模式',
    };
  }

  String _connectionStateLabel(BluetoothConnectionState state) {
    return switch (state) {
      BluetoothConnectionState.disconnected => '已断开',
      BluetoothConnectionState.connecting => '连接中',
      BluetoothConnectionState.connected => '已连接',
      BluetoothConnectionState.disconnecting => '断开中',
      BluetoothConnectionState.unknown => '未知',
    };
  }

  String _bondStateLabel(BluetoothBondState state) {
    return switch (state) {
      BluetoothBondState.none => '未绑定',
      BluetoothBondState.bonding => '绑定中',
      BluetoothBondState.bonded => '已绑定',
      BluetoothBondState.unknown => '未知',
    };
  }

  String _phyLabel(BluetoothPhy phy) {
    return switch (phy) {
      BluetoothPhy.le1m => 'LE 1M',
      BluetoothPhy.le2m => 'LE 2M',
      BluetoothPhy.leCoded => 'LE Coded',
      BluetoothPhy.unknown => '未知',
    };
  }

  String _priorityLabel(BluetoothConnectionPriority priority) {
    return switch (priority) {
      BluetoothConnectionPriority.balanced => '均衡',
      BluetoothConnectionPriority.high => '高速',
      BluetoothConnectionPriority.lowPower => '低功耗',
    };
  }

  String _deviceTypeLabel(String? type) {
    return switch (type) {
      null || '' => '未知',
      'ble' => 'BLE',
      'classic' => '经典',
      'dual' => '双模式',
      _ => type,
    };
  }

  String _propertySummary(List<String> properties) {
    if (properties.isEmpty) {
      return '无属性';
    }
    return properties.map(_propertyLabel).join('、');
  }

  String _propertyLabel(String property) {
    return switch (property) {
      'read' => '读取',
      'write' => '写入',
      'writeWithoutResponse' => '无响应写入',
      'notify' => '通知',
      'indicate' => '指示',
      'broadcast' => '广播',
      'extendedProperties' => '扩展属性',
      'notifyEncryptionRequired' => '加密通知',
      'indicateEncryptionRequired' => '加密指示',
      _ => property,
    };
  }

  List<String> _serviceFilters() {
    return _serviceFilterController.text
        .split(RegExp(r'[\s,;]+'))
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _candidateDeviceIds() {
    return <String>{
      if (_activeDevice != null) _activeDevice!.id,
      for (final BluetoothScanResult result in _scanResults.values)
        result.device.id,
      for (final BluetoothDevice device in _bondedDevices) device.id,
      for (final BluetoothDevice device in _connectedDevices) device.id,
    }.toList(growable: false);
  }

  String _deviceTitle(BluetoothDevice device) {
    return device.name?.isNotEmpty == true ? device.name! : device.id;
  }

  Uint8List _parseBytes(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return Uint8List(0);

    final RegExp hexLike = RegExp(
      r'^(0x)?[0-9a-fA-F]{2}([\s,;:\-]*[0-9a-fA-F]{2})*$',
    );
    if (hexLike.hasMatch(trimmed)) {
      final String hex = trimmed
          .replaceFirst(RegExp(r'^0x'), '')
          .replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      return Uint8List.fromList(<int>[
        for (int index = 0; index < hex.length; index += 2)
          int.parse(hex.substring(index, index + 2), radix: 16),
      ]);
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  String _bytesPreview(Uint8List bytes) {
    if (bytes.isEmpty) return '<空>';
    final String hex = bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final String text = utf8.decode(bytes, allowMalformed: true);
    return '$hex  ·  "$text"';
  }

  Color _adapterColor(BuildContext context, BluetoothAdapterState state) {
    return switch (state) {
      BluetoothAdapterState.poweredOn =>
        CupertinoColors.activeGreen.resolveFrom(context),
      BluetoothAdapterState.poweredOff =>
        CupertinoColors.systemOrange.resolveFrom(context),
      BluetoothAdapterState.unauthorized =>
        CupertinoColors.systemRed.resolveFrom(context),
      BluetoothAdapterState.unsupported =>
        CupertinoColors.systemGrey.resolveFrom(context),
      _ => CupertinoColors.activeBlue.resolveFrom(context),
    };
  }

  Color _connectionColor(BuildContext context, BluetoothConnectionState state) {
    return switch (state) {
      BluetoothConnectionState.connected =>
        CupertinoColors.activeGreen.resolveFrom(context),
      BluetoothConnectionState.connecting ||
      BluetoothConnectionState.disconnecting =>
        CupertinoColors.systemOrange.resolveFrom(context),
      BluetoothConnectionState.disconnected =>
        CupertinoColors.systemGrey.resolveFrom(context),
      BluetoothConnectionState.unknown =>
        CupertinoColors.activeBlue.resolveFrom(context),
    };
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      color: CupertinoColors.activeBlue.resolveFrom(context),
      borderRadius: BorderRadius.circular(12),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InlineAction extends StatelessWidget {
  const _InlineAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: CupertinoColors.systemGrey5.resolveFrom(context),
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: CupertinoColors.activeBlue.resolveFrom(context),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CharacteristicTarget {
  const CharacteristicTarget(this.deviceId, this.characteristic);

  final String deviceId;
  final BluetoothGattCharacteristic characteristic;
}

class DescriptorTarget {
  const DescriptorTarget(this.deviceId, this.characteristic, this.descriptor);

  final String deviceId;
  final BluetoothGattCharacteristic characteristic;
  final BluetoothGattDescriptor descriptor;
}
