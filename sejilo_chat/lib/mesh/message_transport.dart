import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/universal_envelope.dart';

enum TransportType { bluetooth, wifi, internet }

enum TransportState { stopped, starting, active, disconnected, error }

class TransportPeerInfo {
  const TransportPeerInfo({
    required this.id,
    required this.displayName,
    required this.transportType,
    this.rssi = -60,
    this.address,
    this.publicKeyFingerprint,
    required this.lastSeen,
  });

  final String id;
  final String displayName;
  final TransportType transportType;
  final int rssi;
  final String? address;
  final String? publicKeyFingerprint;
  final DateTime lastSeen;

  TransportPeerInfo copyWith({
    String? id,
    String? displayName,
    TransportType? transportType,
    int? rssi,
    String? address,
    String? publicKeyFingerprint,
    DateTime? lastSeen,
  }) {
    return TransportPeerInfo(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      transportType: transportType ?? this.transportType,
      rssi: rssi ?? this.rssi,
      address: address ?? this.address,
      publicKeyFingerprint: publicKeyFingerprint ?? this.publicKeyFingerprint,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// Abstract base interface for all Sejilo mesh transports.
abstract class MessageTransport extends ChangeNotifier {
  String get name;
  TransportType get type;
  TransportState get state;
  bool get isAvailable;
  int get routeScore;

  Stream<UniversalEnvelope> get incomingEnvelopes;
  Stream<TransportPeerInfo> get peerDiscovered;
  Stream<String> get peerLost;

  Future<void> start();
  Future<void> stop();
  Future<bool> send(UniversalEnvelope envelope, {String? targetPeerId});

  Map<String, dynamic> get metrics => {
        'name': name,
        'type': type.name,
        'state': state.name,
        'isAvailable': isAvailable,
        'routeScore': routeScore,
      };
}
