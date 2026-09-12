import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/security/attachment_policy.dart';

void main() {
  test('rejects spoofed photo and voice types', () {
    expect(AttachmentPolicy.accepts('photo', utf8.encode('not an image')),
        isFalse);
    expect(AttachmentPolicy.accepts('voice', utf8.encode('not audio data')),
        isFalse);
    expect(AttachmentPolicy.accepts('executable', [1, 2, 3]), isFalse);
  });

  test('accepts expected signatures and creates opaque controlled names',
      () async {
    final png = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
    ]);
    expect(AttachmentPolicy.accepts('photo', png), isTrue);
    final name =
        await AttachmentPolicy.safeStorageName('../../danger.exe', 'photo');
    expect(name, matches(RegExp(r'^[A-Za-z0-9_-]{43}\.png$')));
    expect(name, isNot(contains('..')));
  });
}
