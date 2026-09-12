import 'dart:collection';
import 'dart:typed_data';

class MeshFrame {
  MeshFrame({
    required this.messageId,
    required this.fragmentIndex,
    required this.fragmentCount,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload);

  final String messageId;
  final int fragmentIndex;
  final int fragmentCount;
  final Uint8List payload;

  bool get isValid =>
      messageId.isNotEmpty &&
      fragmentCount > 0 &&
      fragmentIndex >= 0 &&
      fragmentIndex < fragmentCount &&
      payload.isNotEmpty;
}

class MeshFragmenter {
  const MeshFragmenter({this.maxPayloadBytes = 160});

  final int maxPayloadBytes;

  List<MeshFrame> fragment(
      {required String messageId, required Uint8List ciphertext}) {
    if (messageId.isEmpty || ciphertext.isEmpty || maxPayloadBytes <= 0) {
      throw ArgumentError(
          'A message ID, ciphertext, and positive frame size are required.');
    }
    final count = (ciphertext.length / maxPayloadBytes).ceil();
    return List<MeshFrame>.generate(count, (index) {
      final start = index * maxPayloadBytes;
      final end = (start + maxPayloadBytes).clamp(0, ciphertext.length);
      return MeshFrame(
        messageId: messageId,
        fragmentIndex: index,
        fragmentCount: count,
        payload: Uint8List.sublistView(ciphertext, start, end),
      );
    }, growable: false);
  }
}

class MeshReassembler {
  MeshReassembler(
      {this.maxPendingMessages = 128,
      this.fragmentTtl = const Duration(minutes: 2),
      this.maxFragmentCount = 1024,
      this.maxMessageBytes = 144 * 1024,
      this.maxGlobalBytes = 1024 * 1024})
      : assert(maxPendingMessages > 0),
        assert(maxFragmentCount > 0),
        assert(maxMessageBytes > 0),
        assert(maxGlobalBytes >= maxMessageBytes);

  final int maxPendingMessages;
  final Duration fragmentTtl;
  final int maxFragmentCount;
  final int maxMessageBytes;
  final int maxGlobalBytes;
  final LinkedHashMap<String, _PendingMessage> _pending = LinkedHashMap();
  int _bufferedBytes = 0;

  int get pendingMessageCount => _pending.length;
  int get bufferedBytes => _bufferedBytes;

  Uint8List? add(MeshFrame frame, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    _purgeExpired(timestamp);
    if (!frame.isValid ||
        frame.fragmentCount > maxFragmentCount ||
        frame.payload.length > maxMessageBytes) {
      return null;
    }
    var pending = _pending[frame.messageId];
    if (pending != null && pending.fragmentCount != frame.fragmentCount) {
      _remove(frame.messageId);
      return null;
    }
    if (pending == null) {
      while (_pending.length >= maxPendingMessages) {
        _remove(_pending.keys.first);
      }
      pending = _PendingMessage(frame.fragmentCount, timestamp);
      _pending[frame.messageId] = pending;
    }

    final existing = pending.fragments[frame.fragmentIndex];
    if (existing != null) {
      if (!_bytesEqual(existing, frame.payload)) {
        // Conflicting bytes for one index poison the transfer. Drop the whole
        // set so a clean retransmission can start immediately.
        _remove(frame.messageId);
      }
      return null;
    }
    if (pending.totalBytes + frame.payload.length > maxMessageBytes ||
        _bufferedBytes + frame.payload.length > maxGlobalBytes) {
      _remove(frame.messageId);
      return null;
    }
    pending.fragments[frame.fragmentIndex] = frame.payload;
    pending.totalBytes += frame.payload.length;
    _bufferedBytes += frame.payload.length;
    if (pending.fragments.length != pending.fragmentCount) return null;

    final bytes = BytesBuilder(copy: false);
    for (var index = 0; index < pending.fragmentCount; index++) {
      final fragment = pending.fragments[index];
      if (fragment == null) return null;
      bytes.add(fragment);
    }
    _remove(frame.messageId);
    return bytes.takeBytes();
  }

  void _purgeExpired(DateTime now) {
    final expired = _pending.entries
        .where((entry) => now.difference(entry.value.createdAt) > fragmentTtl)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final messageId in expired) {
      _remove(messageId);
    }
    while (_pending.length > maxPendingMessages) {
      _remove(_pending.keys.first);
    }
  }

  void _remove(String messageId) {
    final removed = _pending.remove(messageId);
    if (removed != null) {
      _bufferedBytes -= removed.totalBytes;
      if (_bufferedBytes < 0) _bufferedBytes = 0;
    }
  }

  bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class _PendingMessage {
  _PendingMessage(this.fragmentCount, this.createdAt);

  final int fragmentCount;
  final DateTime createdAt;
  final Map<int, Uint8List> fragments = <int, Uint8List>{};
  int totalBytes = 0;
}
