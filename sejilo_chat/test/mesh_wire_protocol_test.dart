import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/mesh_frames.dart';
import 'package:sejilo_chat/core/mesh_wire_protocol.dart';
import 'package:sejilo_chat/security/device_identity.dart';

void main() {
  late DeviceIdentity identity;
  late DeviceIdentity otherIdentity;
  late MeshContentCodec contentCodec;

  setUp(() async {
    final keyPair = await Ed25519().newKeyPair();
    final extracted = await keyPair.extract();
    identity = DeviceIdentity.ed25519Only(
      publicKey: await extracted.extractPublicKey(),
      keyPair: extracted,
    );
    final otherPair = await Ed25519().newKeyPair();
    final otherExtracted = await otherPair.extract();
    otherIdentity = DeviceIdentity.ed25519Only(
      publicKey: await otherExtracted.extractPublicKey(),
      keyPair: otherExtracted,
    );
    contentCodec = MeshContentCodec();
  });

  test('signed message verifies and binds the short ID to the public key',
      () async {
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final encoded = await contentCodec.sign(
      type: MeshContentType.publicMessage,
      id: 'message-1',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 7,
      identity: identity,
      body: 'hello across the mesh',
    );

    final decoded = await contentCodec.decodeAndVerify(
      encoded,
      now: createdAt.add(const Duration(seconds: 1)),
    );

    expect(decoded, isNotNull);
    expect(decoded!.senderId, identity.shortId);
    expect(decoded.body, 'hello across the mesh');
    expect(decoded.maxHops, 7);
  });

  test('tampered signed content is rejected', () async {
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final encoded = await contentCodec.sign(
      type: MeshContentType.publicMessage,
      id: 'message-2',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 7,
      identity: identity,
      body: 'original',
    );
    final map = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    map['body'] = 'forged';

    final decoded = await contentCodec.decodeAndVerify(
      Uint8List.fromList(utf8.encode(jsonEncode(map))),
      now: createdAt,
    );

    expect(decoded, isNull);
  });

  test('short verification code is stable and restores from fingerprint', () {
    final code = identity.verificationCode;

    expect(code, matches(RegExp(r'^SJ-[A-Z2-9]{4}-[A-Z2-9]{4}-\d{3}$')));
    expect(
      DeviceIdentity.verificationCodeForFingerprint(identity.fingerprint),
      code,
    );
    expect(
      DeviceIdentity.verificationCodeForFingerprint('not-a-public-key'),
      isNull,
    );
  });

  test('signed photo attachment survives verification and fragmentation',
      () async {
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final photo = Uint8List.fromList(
      List<int>.generate(80 * 1024, (index) => index % 251),
    );
    photo
        .setRange(0, 8, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final encoded = await contentCodec.sign(
      type: MeshContentType.publicMessage,
      id: 'photo-1',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 7,
      identity: identity,
      attachmentType: 'photo',
      attachmentBytes: photo,
    );
    final digest = await Sha256().hash(encoded);
    const wireCodec = MeshWireFrameCodec();
    final fragments = const MeshFragmenter(
      maxPayloadBytes: MeshWireFrameCodec.maxFragmentPayloadBytes,
    ).fragment(
      messageId: wireCodec.transferIdForDigest(digest.bytes),
      ciphertext: encoded,
    );
    final reassembler = MeshReassembler();
    Uint8List? assembled;
    for (final fragment in fragments.reversed) {
      assembled = reassembler.add(fragment) ?? assembled;
    }

    final decoded = await contentCodec.decodeAndVerify(
      assembled!,
      now: createdAt,
    );
    expect(decoded?.attachmentType, 'photo');
    expect(decoded?.attachmentBytes, photo);
    expect(decoded?.body, isNull);
  });

  test('voice and locality group fields are signed against tampering',
      () async {
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final voice = Uint8List.fromList(List<int>.generate(2048, (i) => i % 127));
    voice.setRange(4, 8, ascii.encode('ftyp'));
    final encoded = await contentCodec.sign(
      type: MeshContentType.groupMessage,
      id: 'group-voice-1',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 7,
      identity: identity,
      body: 'voice update',
      groupId: 'geo:tuvz4',
      attachmentType: 'voice',
      attachmentBytes: voice,
    );

    final decoded = await contentCodec.decodeAndVerify(encoded, now: createdAt);
    expect(decoded?.groupId, 'geo:tuvz4');
    expect(decoded?.attachmentType, 'voice');
    expect(decoded?.attachmentBytes, voice);

    final tampered = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    tampered['group'] = 'geo:other';
    expect(
      await contentCodec.decodeAndVerify(
        Uint8List.fromList(utf8.encode(jsonEncode(tampered))),
        now: createdAt,
      ),
      isNull,
    );
  });

  test('small document payload is signed and size bounded', () async {
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final document = Uint8List.fromList(utf8.encode('offline field notes'));
    final encoded = await contentCodec.sign(
      type: MeshContentType.directMessage,
      id: 'document-1',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 4,
      identity: identity,
      body: 'field-notes.txt',
      recipientId: identity.fingerprint,
      attachmentType: 'file',
      attachmentBytes: document,
    );

    final decoded = await contentCodec.decodeAndVerify(encoded, now: createdAt);
    expect(decoded?.attachmentType, 'file');
    expect(decoded?.attachmentBytes, document);
  });

  test('direct message cryptographically binds the recipient fingerprint',
      () async {
    final recipientPair = await Ed25519().newKeyPair();
    final recipientPublicKey = await recipientPair.extractPublicKey();
    final recipientFingerprint =
        base64Url.encode(recipientPublicKey.bytes).replaceAll('=', '');
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final encoded = await contentCodec.sign(
      type: MeshContentType.directMessage,
      id: 'direct-1',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 7,
      identity: identity,
      body: 'for the intended installation',
      recipientId: recipientFingerprint,
    );

    final decoded = await contentCodec.decodeAndVerify(encoded, now: createdAt);
    expect(decoded?.recipientId, recipientFingerprint);

    final tampered = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    tampered['to'] = identity.fingerprint;
    expect(
      await contentCodec.decodeAndVerify(
        Uint8List.fromList(utf8.encode(jsonEncode(tampered))),
        now: createdAt,
      ),
      isNull,
    );
  });

  test('future timestamps outside the clock-skew window are rejected',
      () async {
    final now = DateTime.utc(2026, 8, 4, 10);
    final encoded = await contentCodec.sign(
      type: MeshContentType.announce,
      id: 'announce-1',
      author: 'alice',
      createdAt: now.add(const Duration(minutes: 3)),
      maxHops: 7,
      identity: identity,
    );

    expect(await contentCodec.decodeAndVerify(encoded, now: now), isNull);
  });

  test('wire fragments reassemble out of order without losing signed bytes',
      () async {
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final encoded = await contentCodec.sign(
      type: MeshContentType.publicMessage,
      id: 'message-large',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 7,
      identity: identity,
      body: List.filled(800, 'x').join(),
    );
    const wireCodec = MeshWireFrameCodec();
    final digest = await Sha256().hash(encoded);
    final transferId = wireCodec.transferIdForDigest(digest.bytes);
    final fragments = const MeshFragmenter(
      maxPayloadBytes: MeshWireFrameCodec.maxFragmentPayloadBytes,
    ).fragment(messageId: transferId, ciphertext: encoded);
    final onWire = fragments
        .map((fragment) => wireCodec.encode(fragment, hopsTravelled: 2))
        .toList()
        .reversed;
    final reassembler = MeshReassembler();
    Uint8List? assembled;

    for (final bytes in onWire) {
      final decodedFrame = wireCodec.decode(bytes);
      expect(decodedFrame, isNotNull);
      expect(decodedFrame!.hopsTravelled, 2);
      assembled = reassembler.add(decodedFrame.frame) ?? assembled;
    }

    expect(assembled, encoded);
    final verified = await contentCodec.decodeAndVerify(
      assembled!,
      now: createdAt,
    );
    expect(verified?.body, List.filled(800, 'x').join());
  });

  test('malformed and over-count frames are rejected', () {
    const wireCodec = MeshWireFrameCodec();
    final malformed = Uint8List(MeshWireFrameCodec.headerBytes + 1);
    expect(wireCodec.decode(malformed), isNull);

    final transferId = wireCodec.transferIdForDigest(List<int>.filled(32, 7));
    expect(
      () => wireCodec.encode(
        MeshFrame(
          messageId: transferId,
          fragmentIndex: 0,
          fragmentCount: 1025,
          payload: Uint8List.fromList([1]),
        ),
        hopsTravelled: 0,
      ),
      throwsArgumentError,
    );
  });

  test('encrypted direct message carries kx and is signed against tampering',
      () async {
    final recipientFingerprint = otherIdentity.fingerprint;
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final encoded = await contentCodec.sign(
      type: MeshContentType.directMessage,
      id: 'encrypted-direct-1',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 7,
      identity: identity,
      body: 'ciphertext-blob',
      recipientId: recipientFingerprint,
      kxPublicKey: Uint8List.fromList(List<int>.filled(32, 9)),
      encryptedBody: true,
    );

    final decoded = await contentCodec.decodeAndVerify(encoded, now: createdAt);
    expect(decoded, isNotNull);
    expect(decoded!.recipientId, recipientFingerprint);
    expect(decoded.encryptedBody, isTrue);
    expect(decoded.kxPublicKey, Uint8List.fromList(List<int>.filled(32, 9)));

    // The encryption flag and kx are inside the signed payload, so tampering
    // with either invalidates the signature.
    final tampered = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    tampered['enc'] = 0;
    expect(
      await contentCodec.decodeAndVerify(
        Uint8List.fromList(utf8.encode(jsonEncode(tampered))),
        now: createdAt,
      ),
      isNull,
    );

    final stripped = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    stripped.remove('kx');
    expect(
      await contentCodec.decodeAndVerify(
        Uint8List.fromList(utf8.encode(jsonEncode(stripped))),
        now: createdAt,
      ),
      isNull,
    );
  });

  test('v3 packets are still decoded for backward compatibility', () async {
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final keyPair = await Ed25519().newKeyPair();
    final extracted = await keyPair.extract();
    final legacyIdentity = DeviceIdentity.ed25519Only(
      publicKey: await extracted.extractPublicKey(),
      keyPair: extracted,
    );
    final unsigned = <String, dynamic>{
      'v': 3,
      't': MeshContentType.publicMessage.index,
      'id': 'legacy-1',
      'sid': legacyIdentity.shortId,
      'name': 'old-device',
      'ts': createdAt.millisecondsSinceEpoch,
      'mh': 7,
      'pub': base64Url.encode(legacyIdentity.publicKey.bytes).replaceAll('=', ''),
      'body': 'hello from an older install',
    };
    final signature = await (Ed25519()).sign(
      utf8.encode(jsonEncode(unsigned)),
      keyPair: extracted,
    );
    final legacy = Uint8List.fromList(utf8.encode(jsonEncode({
      ...unsigned,
      'sig': base64Url.encode(signature.bytes).replaceAll('=', ''),
    })));

    final decoded = await contentCodec.decodeAndVerify(legacy, now: createdAt);
    expect(decoded, isNotNull);
    expect(decoded!.body, 'hello from an older install');
    expect(decoded.kxPublicKey, isNull);
    expect(decoded.encryptedBody, isFalse);
  });

  test('announce can carry an X25519 key-exchange key', () async {
    final createdAt = DateTime.utc(2026, 8, 4, 10);
    final x25519 = X25519();
    final kxPair = await x25519.newKeyPair();
    final kxPublic = await kxPair.extractPublicKey();
    final encoded = await contentCodec.sign(
      type: MeshContentType.announce,
      id: 'announce-kx-1',
      author: 'alice',
      createdAt: createdAt,
      maxHops: 7,
      identity: identity,
      kxPublicKey: Uint8List.fromList(kxPublic.bytes),
    );

    final decoded = await contentCodec.decodeAndVerify(encoded, now: createdAt);
    expect(decoded, isNotNull);
    expect(decoded!.kxPublicKey, kxPublic.bytes);
    expect(decoded.encryptedBody, isFalse);
  });
}
