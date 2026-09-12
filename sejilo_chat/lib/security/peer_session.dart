import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class SessionEnvelope {
  const SessionEnvelope({
    required this.keyEpoch,
    required this.counter,
    required this.cipherText,
    required this.mac,
  });

  final int keyEpoch;
  final int counter;
  final List<int> cipherText;
  final List<int> mac;
}

class ReplayException implements Exception {
  const ReplayException();
}

/// An authenticated per-peer session. Counters are part of the AEAD associated
/// data and must be persisted by callers before transmitting an envelope.
class PeerSession {
  PeerSession._(this._key, this.peerId, this.keyEpoch, this.createdAt);

  static const rotateAfter = Duration(hours: 24);
  static const maxMessagesPerKey = 10000;
  final Cipher _cipher = Chacha20.poly1305Aead();
  final SecretKey _key;
  final String peerId;
  int keyEpoch;
  final DateTime createdAt;
  int _sendCounter = 0;
  int _highestReceivedCounter = -1;

  static Future<PeerSession> derive({
    required SecretKey sharedSecret,
    required String peerId,
    required int keyEpoch,
    DateTime? now,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('sejilo-session-v1'),
      info: utf8.encode('$peerId:$keyEpoch'),
    );
    return PeerSession._(
        key, peerId, keyEpoch, (now ?? DateTime.now()).toUtc());
  }

  bool shouldRotate(DateTime now) =>
      _sendCounter >= maxMessagesPerKey ||
      now.toUtc().difference(createdAt) >= rotateAfter;

  Future<SessionEnvelope> encrypt(List<int> clearText) async {
    if (clearText.isEmpty) throw ArgumentError.value(clearText, 'clearText');
    if (_sendCounter >= maxMessagesPerKey) {
      throw StateError('Session key rotation required');
    }
    final counter = _sendCounter++;
    final aad = _associatedData(counter);
    final box = await _cipher.encrypt(clearText,
        secretKey: _key, nonce: _nonce(counter), aad: aad);
    return SessionEnvelope(
      keyEpoch: keyEpoch,
      counter: counter,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  Future<Uint8List> decrypt(SessionEnvelope envelope) async {
    if (envelope.keyEpoch != keyEpoch ||
        envelope.counter <= _highestReceivedCounter) {
      throw const ReplayException();
    }
    final clear = await _cipher.decrypt(
      SecretBox(envelope.cipherText,
          nonce: _nonce(envelope.counter), mac: Mac(envelope.mac)),
      secretKey: _key,
      aad: _associatedData(envelope.counter),
    );
    // Advance only after authentication succeeds, preventing forged packets
    // from consuming the replay window.
    _highestReceivedCounter = envelope.counter;
    return Uint8List.fromList(clear);
  }

  List<int> _associatedData(int counter) =>
      utf8.encode('sejilo-v1|$peerId|$keyEpoch|$counter');

  List<int> _nonce(int counter) {
    final bytes = ByteData(12)..setUint64(4, counter, Endian.big);
    return bytes.buffer.asUint8List();
  }
}
