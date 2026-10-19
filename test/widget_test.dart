import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kannada_helper/ui/result_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('ResultCard shows romanized, script and play button',
      (tester) async {
    var played = false;
    await tester.pumpWidget(_wrap(ResultCard(
      romanized: 'yeshtu',
      kannada: 'ಎಷ್ಟು',
      onPlay: () => played = true,
    )));

    expect(find.text('yeshtu'), findsOneWidget);
    expect(find.text('ಎಷ್ಟು'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up));
    expect(played, isTrue);
  });

  testWidgets('ResultCard hides play and shows hint without a voice',
      (tester) async {
    await tester.pumpWidget(_wrap(const ResultCard(
      romanized: 'yeshtu',
      kannada: 'ಎಷ್ಟು',
      audioHint: 'No Kannada voice found.',
    )));

    expect(find.byIcon(Icons.volume_up), findsNothing);
    expect(find.text('No Kannada voice found.'), findsOneWidget);
  });
}
