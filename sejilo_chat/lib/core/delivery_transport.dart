import 'universal_envelope.dart';

enum DeliveryTransportKind { ble, lan, internet, gateway }

enum DeliveryTransportState {
  stopped,
  connecting,
  ready,
  degraded,
  unavailable
}

class DeliveryRoute {
  const DeliveryRoute({
    required this.kind,
    required this.state,
    required this.latency,
    required this.cost,
    required this.isMetered,
  });

  final DeliveryTransportKind kind;
  final DeliveryTransportState state;
  final Duration latency;
  final int cost;
  final bool isMetered;

  int get score {
    if (state == DeliveryTransportState.stopped ||
        state == DeliveryTransportState.unavailable) {
      return -1000000;
    }
    final readiness = state == DeliveryTransportState.ready ? 10000 : 2000;
    final localBonus = switch (kind) {
      DeliveryTransportKind.lan => 900,
      DeliveryTransportKind.ble => 500,
      DeliveryTransportKind.internet => 300,
      DeliveryTransportKind.gateway => 100,
    };
    return readiness +
        localBonus -
        latency.inMilliseconds.clamp(0, 5000) -
        (cost * 100) -
        (isMetered ? 400 : 0);
  }
}

abstract interface class DeliveryTransport {
  DeliveryTransportKind get kind;
  DeliveryTransportState get state;
  Stream<DeliveryTransportState> get stateChanges;
  Stream<UniversalEnvelope> get receivedEnvelopes;

  Future<void> start();
  Future<void> stop();
  Future<void> send(UniversalEnvelope envelope);
}

class DeliveryRouter {
  const DeliveryRouter();

  DeliveryRoute? best(Iterable<DeliveryRoute> routes) {
    final usable = routes.where((route) => route.score >= 0).toList()
      ..sort((left, right) => right.score.compareTo(left.score));
    return usable.isEmpty ? null : usable.first;
  }
}
