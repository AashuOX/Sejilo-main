import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/security/peer_session.dart';

void main() {
  test('encrypts per peer and rejects replayed envelopes', () async {
    final secret = SecretKey(List<int>.generate(32, (i) => i));
    final sender = await PeerSession.derive(
        sharedSecret: secret, peerId: 'peer-a', keyEpoch: 1);
    final receiver = await PeerSession.derive(
        sharedSecret: secret, peerId: 'peer-a', keyEpoch: 1);
    final envelope = await sender.encrypt(utf8.encode('private'));
    expect(utf8.decode(await receiver.decrypt(envelope)), 'private');
    await expectLater(
        receiver.decrypt(envelope), throwsA(isA<ReplayException>()));
  });

  test('authentication binds an envelope to its peer and epoch', () async {
    final secret = SecretKey(List<int>.filled(32, 7));
    final sender = await PeerSession.derive(
        sharedSecret: secret, peerId: 'peer-a', keyEpoch: 1);
    final wrongPeer = await PeerSession.derive(
        sharedSecret: secret, peerId: 'peer-b', keyEpoch: 1);
    final envelope = await sender.encrypt(const [1, 2, 3]);
    await expectLater(wrongPeer.decrypt(envelope), throwsA(anything));
  });
}
