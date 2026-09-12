import 'ai_provider.dart';

/// Small deterministic offline assistant. It intentionally makes no model or
/// language-quality claims; larger local models can replace this provider.
class LocalAiProvider implements AiProvider {
  const LocalAiProvider();

  @override
  String get name => 'Sejilo Local Assistant';

  @override
  AiExecutionLocation get location => AiExecutionLocation.onDevice;

  @override
  Set<AiFeature> get supportedFeatures => const {
        AiFeature.rewrite,
        AiFeature.smartReplies,
        AiFeature.summary,
        AiFeature.priority,
        AiFeature.scamDetection,
        AiFeature.explanation,
        AiFeature.diagnostics,
      };

  @override
  Future<AiResult> process(AiRequest request) async {
    final input = _normalize(request.selectedText);
    return switch (request.operation) {
      AiOperation.makeProfessional => _text(_professional(input), 'AI rewrite'),
      AiOperation.makeFriendly => _text(_friendly(input), 'AI rewrite'),
      AiOperation.makeShorter => _text(_shorter(input), 'AI rewrite'),
      AiOperation.makeClearer => _text(_clearer(input), 'AI rewrite'),
      AiOperation.fixGrammar =>
        _text(_sentenceCase(input), 'AI grammar suggestion'),
      AiOperation.customRewrite => _customRewrite(input, request.instruction),
      AiOperation.smartReplies => _smartReplies(input),
      AiOperation.summarize || AiOperation.catchUp => _summarize(request),
      AiOperation.detectTone => _tone(input),
      AiOperation.explain => _explain(input),
      AiOperation.scanForScam => _scam(input),
      AiOperation.diagnoseNetwork => _diagnose(input),
      AiOperation.translate => throw const AiUnavailableException(
          'No verified offline translation model is installed.'),
    };
  }

  AiResult _text(String value, String label) => AiResult(
        location: location,
        label: '$label · On Device 🔒',
        text: value,
      );

  String _normalize(String input) => input
      .trim()
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');

  String _sentenceCase(String input) {
    if (input.isEmpty) return input;
    final result = '${input[0].toUpperCase()}${input.substring(1)}';
    return RegExp(r'[.!?]$').hasMatch(result) ? result : '$result.';
  }

  String _professional(String input) {
    var value = input
        .replaceAll(RegExp(r"\bcan't\b", caseSensitive: false), 'cannot')
        .replaceAll(RegExp(r"\bwon't\b", caseSensitive: false), 'will not')
        .replaceAll(RegExp(r"\bi'm\b", caseSensitive: false), 'I am')
        .replaceAll(RegExp(r'\bhey\b', caseSensitive: false), 'Hello');
    return _sentenceCase(value);
  }

  String _friendly(String input) {
    var value = _sentenceCase(input);
    if (!RegExp(r'\b(please|thanks|thank you)\b', caseSensitive: false)
        .hasMatch(value)) {
      value = '$value Thanks!';
    }
    return value;
  }

  String _shorter(String input) {
    var value = input
        .replaceAll(
            RegExp(r'\b(I just wanted to|I wanted to)\b', caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\b(really|very|basically|actually)\b',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    final sentences = value.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length > 2) value = sentences.take(2).join(' ');
    return _sentenceCase(value);
  }

  String _clearer(String input) {
    final segments =
        input.split(RegExp(r'\s*(?:;|\band then\b)\s*', caseSensitive: false));
    return segments.map(_sentenceCase).join(' ');
  }

  AiResult _customRewrite(String input, String? instruction) {
    final normalized = instruction?.trim().toLowerCase() ?? '';
    if (normalized.contains('short')) {
      return _text(_shorter(input), 'AI custom rewrite');
    }
    if (normalized.contains('friend')) {
      return _text(_friendly(input), 'AI custom rewrite');
    }
    if (normalized.contains('professional') || normalized.contains('formal')) {
      return _text(_professional(input), 'AI custom rewrite');
    }
    throw const AiUnavailableException(
      'This offline assistant supports short, friendly, or professional custom rewrites.',
    );
  }

  AiResult _smartReplies(String input) {
    final lower = input.toLowerCase();
    final suggestions = lower.contains('?')
        ? const [
            'Yes, that works for me.',
            'I’ll check and let you know.',
            'Could you share more details?'
          ]
        : lower.contains(RegExp(r'\b(thanks|thank you)\b'))
            ? const ['You’re welcome!', 'Happy to help.', 'Anytime!']
            : const [
                'Sounds good.',
                'I’ll check it.',
                'Thanks for the update.'
              ];
    return AiResult(
      location: location,
      label: 'AI suggestions · On Device 🔒',
      suggestions: suggestions,
    );
  }

  AiResult _summarize(AiRequest request) {
    final source = [request.selectedText, ...request.context].join('\n');
    final lines = source
        .split(RegExp(r'(?:\r?\n|(?<=[.!?])\s+)'))
        .map((line) => line.trim())
        .where((line) => line.length >= 8)
        .take(4)
        .toList();
    return _text(
      lines.isEmpty
          ? 'No clear summary points found.'
          : lines.map((line) => '• $line').join('\n'),
      'AI-generated summary',
    );
  }

  AiResult _tone(String input) {
    final warnings = <String>[];
    final upperLetters = input.replaceAll(RegExp('[^A-Z]'), '').length;
    final letters = input.replaceAll(RegExp('[^A-Za-z]'), '').length;
    if (letters > 8 && upperLetters / letters > .65) {
      warnings.add('Mostly uppercase; it may read as harsh.');
    }
    if (RegExp(r'!{2,}').hasMatch(input)) {
      warnings.add('Repeated exclamation marks increase intensity.');
    }
    final label = RegExp(r'\b(please|thank|could you)\b', caseSensitive: false)
            .hasMatch(input)
        ? 'Polite'
        : RegExp(r'\b(hi|hey|thanks)\b', caseSensitive: false).hasMatch(input)
            ? 'Friendly / casual'
            : 'Neutral';
    return AiResult(
      location: location,
      label: 'Draft tone · On Device 🔒',
      text: label,
      warnings: warnings,
    );
  }

  AiResult _explain(String input) => _text(
        input.length <= 180 ? input : '${input.substring(0, 177)}…',
        'Simplified selection',
      );

  AiResult _scam(String input) {
    final warnings = <String>[];
    if (RegExp(r'https?://|www\.', caseSensitive: false).hasMatch(input)) {
      warnings.add(
          'Contains an external link. Verify its destination before opening.');
    }
    if (RegExp(
            r'\b(urgent|act now|password|verification code|gift card|crypto|wallet)\b',
            caseSensitive: false)
        .hasMatch(input)) {
      warnings
          .add('Contains wording commonly used in scams or credential theft.');
    }
    return AiResult(
      location: location,
      label: 'Safety aid · On Device 🔒',
      text: warnings.isEmpty
          ? 'No deterministic warning signs found.'
          : 'Potentially suspicious message',
      warnings: warnings,
    );
  }

  AiResult _diagnose(String input) {
    final lower = input.toLowerCase();
    final findings = <String>[];
    if (lower.contains('permission') && lower.contains('denied')) {
      findings.add('A required permission is disabled.');
    }
    if (lower.contains('advertisement') && lower.contains('0 live')) {
      findings.add('No live Bluetooth advertisement was observed.');
    }
    if (lower.contains('timeout')) {
      findings.add('A connection or response timed out.');
    }
    if (lower.contains('relay') && lower.contains('unreachable')) {
      findings.add('The Internet relay is unreachable.');
    }
    return _text(
      findings.isEmpty
          ? 'No verified failure pattern was found. Check the raw sanitized diagnostics.'
          : findings.map((finding) => '• $finding').join('\n'),
      'Deterministic diagnosis',
    );
  }
}
