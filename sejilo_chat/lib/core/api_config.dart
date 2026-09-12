// api_config.dart — the one place that decides which backend a build talks to.
//
// The default used to be `http://localhost:8080`, decided separately in
// account_auth_controller.dart, while internet_relay_transport.dart had no
// default at all. Both were wrong for a real install:
//
//   * On a phone `localhost` is the phone. A build made without
//     `--dart-define=SEJILO_API_BASE_URL=…` could not reach any backend, so
//     every sign-in, feed load and upload failed on connection refused — which
//     from the outside looks exactly like broken authentication.
//   * The relay treated "no define" as "not configured" and reported
//     `unavailable`, so online delivery was off in every default build and only
//     Bluetooth remained.
//
// The default is now the deployed instance declared in render.yaml, so a plain
// `flutter build apk` produces an app that works off this network. A dart define
// still overrides it for local work, and Settings → Server overrides both at
// runtime, per install.
//
// A LAN address such as http://192.168.x.x:8080 is fine for the REST calls but
// the relay refuses plain http outside a debug build (see
// InternetRelayTransport._validateEndpoint), so use `flutter run` for that or
// point the define at an https tunnel.
class ApiConfig {
  const ApiConfig._();

  /// Compile-time override:
  /// `flutter build apk --dart-define=SEJILO_API_BASE_URL=http://10.0.2.2:8080`
  static const String _override = String.fromEnvironment('SEJILO_API_BASE_URL');

  /// The hosted backend from render.yaml — service `sejilo-backend`, free plan.
  ///
  /// Not a secret and not a credential: it is the public address of the API.
  static const String hostedBaseUrl = 'https://sejilo-backend.onrender.com';

  /// Where requests go when neither a define nor a stored setting says otherwise.
  static String get baseUrl =>
      _override.isNotEmpty ? _override : hostedBaseUrl;

  /// [baseUrl] as a [Uri], for the relay's socket and REST paths.
  static Uri get baseUri => Uri.parse(baseUrl);

  /// True when this build was pinned to a specific backend at compile time.
  static bool get isOverridden => _override.isNotEmpty;
}
