import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../security/peer_session.dart';

/// Manages secure Diffie-Hellman cryptographic sessions between mesh peers.
class PeerSessionManager {
  PeerSessionManager();

  final Map<String, PeerSession> _activeSessions = {};

  bool hasSession(String peerId) => _activeSessions.containsKey(peerId);

  PeerSession? getSession(String peerId) => _activeSessions[peerId];

  /// Establish or derive an authenticated peer session using X25519 shared secret.
  Future<PeerSession> establishSession({
    required String peerId,
    required SecretKey sharedSecret,
    int keyEpoch = 1,
  }) async {
    final session = await PeerSession.derive(
      sharedSecret: sharedSecret,
      peerId: peerId,
      keyEpoch: keyEpoch,
    );
    _activeSessions[peerId] = session;
    return session;
  }

  /// Encrypt a cleartext payload destined for [peerId].
  Future<SessionEnvelope> encryptForPeer({
    required String peerId,
    required List<int> cleartext,
  }) async {
    final session = _activeSessions[peerId];
    if (session == null) {
      throw StateError('No active secure session with peer $peerId');
    }
    return await session.encrypt(cleartext);
  }

  /// Decrypt an incoming ciphertext from [peerId].
  Future<Uint8List> decryptFromPeer({
    required String peerId,
    required SessionEnvelope envelope,
  }) async {
    final session = _activeSessions[peerId];
    if (session == null) {
      throw StateError('No active secure session with peer $peerId');
    }
    return await session.decrypt(envelope);
  }

  /// Close and purge session upon peer disconnection.
  void closeSession(String peerId) {
    _activeSessions.remove(peerId);
  }

  void clearAll() {
    _activeSessions.clear();
  }
}
