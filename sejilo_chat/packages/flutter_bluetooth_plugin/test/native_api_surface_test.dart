import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple platform implementations cover every MethodChannel API', () {
    final methods = _methodChannelApiNames();
    expect(methods, isNotEmpty);

    for (final path in <String>[
      'ios/flutter_bluetooth_plugin/Sources/flutter_bluetooth_plugin/FlutterBluetoothPlugin.swift',
      'macos/flutter_bluetooth_plugin/Sources/flutter_bluetooth_plugin/FlutterBluetoothPlugin.swift',
    ]) {
      final source = File(path).readAsStringSync();
      for (final method in methods) {
        final block = _swiftCaseBlock(source, method);
        expect(block, isNotNull, reason: '$path is missing $method');
        expect(
          block,
          isNot(contains('FlutterMethodNotImplemented')),
          reason: '$path returns FlutterMethodNotImplemented for $method',
        );
      }
    }
  });
}

Set<String> _methodChannelApiNames() {
  final source = File('lib/flutter_bluetooth_plugin_method_channel.dart')
      .readAsStringSync();
  final pattern = RegExp(
    r"methodChannel\s*\.\s*invoke(?:Method|ListMethod|MapMethod)"
    r"(?:<[^>]+>)?\(\s*'([^']+)'",
    multiLine: true,
    dotAll: true,
  );
  return pattern.allMatches(source).map((match) => match.group(1)!).toSet();
}

String? _swiftCaseBlock(String source, String method) {
  final lines = source.split('\n');
  final start = lines.indexWhere((line) {
    return line.trimLeft().startsWith('case ') && line.contains('"$method"');
  });
  if (start == -1) {
    return null;
  }

  var end = lines.length;
  for (var index = start + 1; index < lines.length; index += 1) {
    final trimmed = lines[index].trimLeft();
    if (trimmed.startsWith('case ') || trimmed.startsWith('default:')) {
      end = index;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}
