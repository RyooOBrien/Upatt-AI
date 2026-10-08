import 'package:flutter_test/flutter_test.dart';

import 'package:aichatbot/main.dart';

void main() {
  testWidgets('AI Chatbot app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const AIChatbotApp());

    expect(find.text('AI Chatbot'), findsOneWidget);
  });
}