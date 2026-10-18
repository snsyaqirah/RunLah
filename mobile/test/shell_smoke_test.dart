import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runlah/features/shell/shell.dart';

import 'helpers.dart';

void main() {
  testWidgets('shell renders and demo director opens', (tester) async {
    await pumpScreen(tester, (_) => const Shell());
    expect(find.text('Home'), findsWidgets);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Demo director'), findsOneWidget);
  });
}
