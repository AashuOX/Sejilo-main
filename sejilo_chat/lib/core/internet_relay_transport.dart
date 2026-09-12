import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/device_identity.dart';
import 'api_config.dart';
import 'delivery_transport.dart';
import 'universal_envelope.dart';

/// Authenticated store-and-forward transport for already encrypted envelopes.
///
/// The endpoint comes from [ApiConfig], so a build with no `--dart-define`
/// reaches the hosted backend instead of reporting itself unavailable — which is
/// what used to happen, leaving Bluetooth as the only delivery path in every
/// default build.
class InternetRelayTransport implements DeliveryTransport {
  InternetRelayTransport({
    required DeviceIdentity identity,
    required FlutterSecureStorage secureStorage,
    Uri? baseUri,
    HttpClient? httpClient,
  })  : _identity = identity,
        _storage = secureStorage,
        _baseUri = baseUri ?? ApiConfig.baseUri,
        _http = httpClient ?? HttpClient();

  static const _tokenKey = 'relay.session.token.v1';
  static const _refreshTokenKey = 'relay.session.refresh.v1';
  static const _deviceIdKey = 'relay.device.id.v1';

  final DeviceIdentity _identity;
  final FlutterSecureStorage _storage;
  final Uri? _baseUri;
  final HttpClient _http;
  final _states = StreamController<DeliveryTransportState>.broadcast();
  final _received = StreamController<UniversalEnvelope>.broadcast();
  final Set<String> _seenPacketIds = <String>{};
  WebSocket? _socket;
  Timer? _reconnectTimer;
  DeliveryTransportState _state = DeliveryTransportState.stopped;
  String? _token;
  String? _refreshToken;
  String? _deviceId;
  bool _stopping = false;
  int _reconnectAttempt = 0;

  @override
  DeliveryTransportKind get kind => DeliveryTransportKind.internet;

  @override
  DeliveryTransportState get state => _state;

  @override
  Stream<DeliveryTransportState> get stateChanges => _states.stream;

  @override
  Stream<UniversalEnvelope> get receivedEnvelopes => _received.stream;

  bool get isConfigured => _baseUri != null;
  String? get authenticatedDeviceId => _deviceId;

  @override
  Future<void> start() async {
    if (_state != DeliveryTransportState.stopped) return;
    _stopping = false;
    if (_baseUri == null) {
      _setState(DeliveryTransportState.unavailable);
      return;
    }
    _validateEndpoint(_baseUri);
    _setState(DeliveryTransportState.connecting);
    try {
      await _authenticate();
      await fetchPending();
      await _connectSocket();
      _reconnectAttempt = 0;
      _setState(DeliveryTransportState.ready);
    } catch (error, stackTrace) {
      _setState(DeliveryTransportState.degraded);
      _received.addError(error, stackTrace);
      _scheduleReconnect();
    }
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) await socket.close(WebSocketStatus.normalClosure);
    _setState(DeliveryTransportState.stopped);
  }

  @override
  Future<void> send(UniversalEnvelope envelope) async {
    envelope.validate(now: DateTime.now().toUtc());
    await _ensureAuthenticated();
    if (envelope.senderDeviceId != _deviceId) {
      throw StateError('Envelope sender does not match this relay identity.');
    }
    await _request('POST', '/v1/messages', body: envelope.toJson());
  }

  Future<void> acknowledge(String messageId, {bool read = false}) async {
    if (!RegExp(r'^[A-Za-z0-9._~-]{16,128}$').hasMatch(messageId)) {
      throw ArgumentError.value(messageId, 'messageId', 'Invalid message ID.');
    }
    await _ensureAuthenticated();
    await _request(
      'POST',
      '/v1/messages/$messageId/acknowledgements',
      body: {'state': read ? 'read' : 'delivered_to_device'},
    );
  }

  Future<void> fetchPending() async {
    await _ensureAuthenticated();
    final response = await _request('GET', '/v1/messages/pending?limit=100');
    final envelopes = response['envelopes'];
    if (envelopes is! List<Object?>) {
      throw const FormatException('Relay returned malformed pending messages.');
    }
    for (final value in envelopes) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('Relay returned a malformed envelope.');
      }
      final envelope = UniversalEnvelope.fromJson(value);
      if (_seenPacketIds.add(envelope.packetId)) _received.add(envelope);
    }
    if (_seenPacketIds.length > 4096) _seenPacketIds.clear();
  }

  Future<void> _ensureAuthenticated() async {
    if (_baseUri == null) throw StateError('Internet relay is not configured.');
    if (_token == null || _deviceId == null) await _authenticate();
  }

  Future<void> _authenticate() async {
    _token = await _storage.read(key: _tokenKey);
    _refreshToken = await _storage.read(key: _refreshTokenKey);
    _deviceId = await _storage.read(key: _deviceIdKey);
    if (_token != null && _deviceId != null) return;

    final storedDeviceId = await _storage.read(key: _deviceIdKey);
    final purpose = storedDeviceId == null ? 'register' : 'login';
    final challenge = await _request(
      'POST',
      '/v1/auth/challenges',
      body: {
        'purpose': purpose,
        if (storedDeviceId != null) 'deviceId': storedDeviceId,
      },
      authenticated: false,
    );
    final challengeId = challenge['challengeId'] as String?;
    final payload = challenge['payload'] as String?;
    if (challengeId == null || payload == null) {
      throw const FormatException('Relay returned a malformed challenge.');
    }
    final signature = await Ed25519().sign(
      utf8.encode(payload),
      keyPair: _identity.keyPair,
    );
    final signatureText = _base64Url(signature.bytes);
    late final Map<String, Object?> session;
    if (storedDeviceId == null) {
      session = await _request(
        'POST',
        '/v1/devices/register',
        body: {
          'challengeId': challengeId,
          'publicKey': _base64Url(_identity.publicKey.bytes),
          'signature': signatureText,
          'platform': _platformName,
          'protocolVersions': [UniversalEnvelope.currentProtocolVersion],
          'capabilities': ['encrypted-relay-v1'],
        },
        authenticated: false,
      );
    } else {
      session = await _request(
        'POST',
        '/v1/sessions',
        body: {
          'challengeId': challengeId,
          'deviceId': storedDeviceId,
          'signature': signatureText,
        },
        authenticated: false,
      );
    }
    _token = session['token'] as String?;
    _refreshToken = session['refreshToken'] as String?;
    _deviceId = session['deviceId'] as String?;
    if (_token == null || _refreshToken == null || _deviceId == null) {
      throw const FormatException('Relay returned a malformed session.');
    }
    await _storage.write(key: _tokenKey, value: _token);
    await _storage.write(key: _refreshTokenKey, value: _refreshToken);
    await _storage.write(key: _deviceIdKey, value: _deviceId);
  }

  Future<void> _connectSocket() async {
    final base = _baseUri!;
    final socketUri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/v1/ws',
      query: null,
    );
    final socket = await WebSocket.connect(
      socketUri.toString(),
      headers: {HttpHeaders.authorizationHeader: 'Bearer $_token'},
    );
    socket.pingInterval = const Duration(seconds: 25);
    _socket = socket;
    socket.listen(
      (event) {
        if (event is! String) return;
        try {
          final message = jsonDecode(event);
          if (message is Map<String, Object?> &&
              (message['type'] == 'messages' || message['type'] == 'ready')) {
            unawaited(fetchPending());
          }
        } on FormatException {
          // Ignore unknown control frames; message bodies only arrive via HTTPS.
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _received.addError(error, stackTrace);
      },
      onDone: () {
        _socket = null;
        if (!_stopping) {
          _setState(DeliveryTransportState.degraded);
          _scheduleReconnect();
        }
      },
      cancelOnError: false,
    );
  }

  void _scheduleReconnect() {
    if (_stopping || _reconnectTimer != null) return;
    final seconds = (1 << _reconnectAttempt.clamp(0, 6));
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      _reconnectTimer = null;
      if (_stopping) return;
      _setState(DeliveryTransportState.connecting);
      try {
        await _authenticate();
        await fetchPending();
        await _connectSocket();
        _reconnectAttempt = 0;
        _setState(DeliveryTransportState.ready);
      } catch (error, stackTrace) {
        _received.addError(error, stackTrace);
        _setState(DeliveryTransportState.degraded);
        _scheduleReconnect();
      }
    });
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
    bool allowRefresh = true,
  }) async {
    final uri = _baseUri!.resolve(path);
    final request = await _http.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (authenticated) {
      await _ensureAuthenticated();
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    }
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final responseText = await utf8.decoder.bind(response).join();
    final decoded =
        responseText.isEmpty ? <String, Object?>{} : jsonDecode(responseText);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == HttpStatus.unauthorized && authenticated) {
        _token = null;
        await _storage.delete(key: _tokenKey);
        if (allowRefresh && await _refreshSession()) {
          return _request(
            method,
            path,
            body: body,
            authenticated: authenticated,
            allowRefresh: false,
          );
        }
      }
      throw HttpException('Relay request failed (${response.statusCode}).',
          uri: uri);
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Relay returned a non-object response.');
    }
    return decoded;
  }

  Future<bool> _refreshSession() async {
    _refreshToken ??= await _storage.read(key: _refreshTokenKey);
    if (_refreshToken == null) return false;
    try {
      final session = await _request(
        'POST',
        '/v1/sessions/refresh',
        body: {'refreshToken': _refreshToken},
        authenticated: false,
        allowRefresh: false,
      );
      _token = session['token'] as String?;
      _refreshToken = session['refreshToken'] as String?;
      _deviceId = session['deviceId'] as String?;
      if (_token == null || _refreshToken == null || _deviceId == null) {
        throw const FormatException(
            'Relay returned a malformed refreshed session.');
      }
      await _storage.write(key: _tokenKey, value: _token);
      await _storage.write(key: _refreshTokenKey, value: _refreshToken);
      await _storage.write(key: _deviceIdKey, value: _deviceId);
      return true;
    } on Object {
      _refreshToken = null;
      await _storage.delete(key: _refreshTokenKey);
      return false;
    }
  }

  void _setState(DeliveryTransportState value) {
    if (_state == value) return;
    _state = value;
    _states.add(value);
  }

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static void _validateEndpoint(Uri uri) {
    if (uri.scheme == 'https') return;
    final localDebug = kDebugMode &&
        uri.scheme == 'http' &&
        {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
    if (!localDebug) {
      throw ArgumentError(
          'The relay URL must use HTTPS outside local debug builds.');
    }
  }

  static String get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    throw UnsupportedError('Unsupported relay platform.');
  }
}
