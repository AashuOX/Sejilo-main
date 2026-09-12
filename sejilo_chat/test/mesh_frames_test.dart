import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/mesh_frames.dart';

void main() {
  test('fragments and reassembles BLE-sized encrypted payloads out of order',
      () {
    final bytes =
        Uint8List.fromList(List<int>.generate(401, (index) => index % 255));
    final frames = const MeshFragmenter(maxPayloadBytes: 160)
        .fragment(messageId: 'm1', ciphertext: bytes);
    final reassembler = MeshReassembler();

    expect(reassembler.add(frames[2]), isNull);
    expect(reassembler.add(frames[0]), isNull);
    expect(reassembler.add(frames[1]), bytes);
  });

  test('rejects duplicate and inconsistent fragments', () {
    final reassembler = MeshReassembler();
    final frame = MeshFrame(
        messageId: 'm2',
        fragmentIndex: 0,
        fragmentCount: 2,
        payload: Uint8List.fromList(const [1]));
    expect(reassembler.add(frame), isNull);
    expect(reassembler.add(frame), isNull);
    expect(
        reassembler.add(MeshFrame(
            messageId: 'm2',
            fragmentIndex: 1,
            fragmentCount: 3,
            payload: Uint8List.fromList(const [2]))),
        isNull);
  });

  test('drops a poisoned set and accepts a clean retransmission', () {
    final reassembler = MeshReassembler();
    MeshFrame frame(int index, List<int> payload) => MeshFrame(
          messageId: 'retryable',
          fragmentIndex: index,
          fragmentCount: 2,
          payload: Uint8List.fromList(payload),
        );

    expect(reassembler.add(frame(0, const [1])), isNull);
    expect(reassembler.bufferedBytes, 1);
    expect(reassembler.add(frame(0, const [9])), isNull);
    expect(reassembler.bufferedBytes, 0);
    expect(reassembler.pendingMessageCount, 0);

    expect(reassembler.add(frame(0, const [1])), isNull);
    expect(reassembler.add(frame(1, const [2])), Uint8List.fromList([1, 2]));
    expect(reassembler.bufferedBytes, 0);
  });

  test('enforces a global fragment memory budget with accurate cleanup', () {
    final reassembler = MeshReassembler(
      maxMessageBytes: 4,
      maxGlobalBytes: 7,
      fragmentTtl: const Duration(seconds: 1),
    );
    final now = DateTime.utc(2026, 8, 10);
    MeshFrame frame(String id, int index, List<int> payload) => MeshFrame(
          messageId: id,
          fragmentIndex: index,
          fragmentCount: 2,
          payload: Uint8List.fromList(payload),
        );

    expect(reassembler.add(frame('a', 0, const [1, 2, 3]), now: now), isNull);
    expect(reassembler.add(frame('b', 0, const [4, 5, 6]), now: now), isNull);
    expect(reassembler.bufferedBytes, 6);

    // This new set would exceed the process-wide budget and is discarded.
    expect(reassembler.add(frame('c', 0, const [7, 8]), now: now), isNull);
    expect(reassembler.pendingMessageCount, 2);
    expect(reassembler.bufferedBytes, 6);

    expect(reassembler.add(frame('a', 1, const [4]), now: now),
        Uint8List.fromList([1, 2, 3, 4]));
    expect(reassembler.bufferedBytes, 3);

    // Any later input performs bounded expiry cleanup.
    expect(
      reassembler.add(
        frame('d', 0, const [8]),
        now: now.add(const Duration(seconds: 2)),
      ),
      isNull,
    );
    expect(reassembler.pendingMessageCount, 1);
    expect(reassembler.bufferedBytes, 1);
  });
}
