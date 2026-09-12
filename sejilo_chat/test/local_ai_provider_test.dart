import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/ai/ai_provider.dart';
import 'package:sejilo_chat/ai/local_ai_provider.dart';

void main() {
  const provider = LocalAiProvider();

  test('processes only the selected draft on device', () async {
    final result = await provider.process(AiRequest(
      operation: AiOperation.makeProfessional,
      selectedText: "hey, i'm late",
      context: const ['SECRET CONTEXT MUST NOT APPEAR'],
    ));
    expect(result.location, AiExecutionLocation.onDevice);
    expect(result.text, isNot(contains('SECRET')));
    expect(result.text, 'Hello, I am late.');
  });

  test('bounds AI inputs and fails closed for missing translation model',
      () async {
    expect(
      () => AiRequest(
        operation: AiOperation.summarize,
        selectedText: 'x' * (AiRequest.maximumSelectedCharacters + 1),
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.process(AiRequest(
        operation: AiOperation.translate,
        selectedText: 'नमस्ते',
      )),
      throwsA(isA<AiUnavailableException>()),
    );
  });

  test('scam aid warns without deleting or claiming certainty', () async {
    final result = await provider.process(AiRequest(
      operation: AiOperation.scanForScam,
      selectedText: 'URGENT: send your password at https://example.test',
    ));
    expect(result.text, 'Potentially suspicious message');
    expect(result.warnings, hasLength(2));
  });
}
