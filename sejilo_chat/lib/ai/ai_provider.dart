enum AiFeature {
  rewrite,
  smartReplies,
  summary,
  translation,
  transcription,
  semanticSearch,
  priority,
  scamDetection,
  explanation,
  diagnostics,
}

enum AiOperation {
  makeProfessional,
  makeFriendly,
  makeShorter,
  makeClearer,
  fixGrammar,
  customRewrite,
  smartReplies,
  summarize,
  catchUp,
  detectTone,
  explain,
  translate,
  scanForScam,
  diagnoseNetwork,
}

enum AiExecutionLocation { onDevice, cloud }

class AiRequest {
  AiRequest({
    required this.operation,
    required this.selectedText,
    this.context = const [],
    this.instruction,
    this.targetLanguage,
  }) {
    final selectedBytes = selectedText.length;
    if (selectedBytes == 0 || selectedBytes > maximumSelectedCharacters) {
      throw ArgumentError(
          'AI selection must contain 1..$maximumSelectedCharacters characters.');
    }
    if (context.length > maximumContextItems ||
        context.any((item) => item.length > maximumContextCharactersPerItem)) {
      throw ArgumentError('AI context exceeds the local privacy boundary.');
    }
    if ((instruction?.length ?? 0) > maximumInstructionCharacters) {
      throw ArgumentError('AI instruction is too long.');
    }
  }

  static const maximumSelectedCharacters = 16 * 1024;
  static const maximumContextItems = 100;
  static const maximumContextCharactersPerItem = 4096;
  static const maximumInstructionCharacters = 1024;

  final AiOperation operation;
  final String selectedText;
  final List<String> context;
  final String? instruction;
  final String? targetLanguage;
}

class AiResult {
  const AiResult({
    required this.location,
    required this.label,
    this.text,
    this.suggestions = const [],
    this.warnings = const [],
  });

  final AiExecutionLocation location;
  final String label;
  final String? text;
  final List<String> suggestions;
  final List<String> warnings;
}

class AiUnavailableException implements Exception {
  const AiUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class AiProvider {
  String get name;
  AiExecutionLocation get location;
  Set<AiFeature> get supportedFeatures;

  Future<AiResult> process(AiRequest request);
}

/// Cloud calls must carry a fresh, content-specific consent produced only
/// after the UI shows the exact selected content that will leave the device.
class AiCloudConsent {
  const AiCloudConsent({
    required this.contentDigest,
    required this.approvedAt,
  });

  static const lifetime = Duration(minutes: 5);
  final String contentDigest;
  final DateTime approvedAt;

  bool isValidAt(DateTime now) =>
      !approvedAt.toUtc().isAfter(now.toUtc()) &&
      now.toUtc().difference(approvedAt.toUtc()) <= lifetime;
}

abstract interface class CloudAiProvider implements AiProvider {
  Future<AiResult> processWithConsent(
    AiRequest request,
    AiCloudConsent consent,
  );
}
