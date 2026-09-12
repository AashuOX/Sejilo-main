import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/design_system/components/sejilo_app_bar.dart';

void main() {
  testWidgets('renders SejiloAppBar brand title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: SejiloAppBar(title: 'SejiloChat'),
        ),
      ),
    );

    expect(find.text('SejiloChat'), findsOneWidget);
  });
}
