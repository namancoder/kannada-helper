import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kannada_helper/engines/engines.dart';
import 'package:kannada_helper/engines/kannada_romanizer.dart';
import 'package:kannada_helper/services/to_kannada.dart';
import 'package:kannada_helper/ui/speak_view.dart';

/// Test double: the test pushes transcripts in by hand.
class FakeSpeech implements SpeechToText {
  StreamController<Transcript>? session;
  String? lastLang;
  int stops = 0;

  @override
  Future<bool> initialize() async => true;

  @override
  Stream<Transcript> listen(String lang) {
    lastLang = lang;
    session = StreamController<Transcript>();
    return session!.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    await session?.close();
  }
}

class FakeTranslator implements Translator {
  final calls = <String>[];

  @override
  Future<String> translate(String text, String from, String to) async {
    calls.add('$from>$to:$text');
    return 'ಎಷ್ಟು';
  }

  @override
  Future<void> dispose() async {}
}

class FakeTts implements TextToSpeech {
  final spoken = <String>[];

  @override
  Future<bool> isAvailable(String lang) async => true;

  @override
  Future<void> speak(String text, String lang) async => spoken.add(text);

  @override
  Future<void> stop() async {}
}

void main() {
  late FakeSpeech speech;
  late FakeTranslator translator;
  late FakeTts tts;

  Widget app({bool active = true}) => MaterialApp(
        home: Scaffold(
          body: SpeakView(
            speech: speech,
            toKannada: ToKannada(translator),
            tts: tts,
            romanizer: const KannadaRomanizer(),
            voiceInstalled: true,
            active: active,
          ),
        ),
      );

  setUp(() {
    speech = FakeSpeech();
    translator = FakeTranslator();
    tts = FakeTts();
  });

  testWidgets('speak -> partial -> final -> Kannada shown and auto-played',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('mic')));
    await tester.pump();

    expect(speech.lastLang, 'en');
    expect(find.text('Listening… tap to stop'), findsOneWidget);

    speech.session!.add(const Transcript('how much'));
    await tester.pump();
    expect(find.text('“how much”'), findsOneWidget);
    expect(translator.calls, isEmpty, reason: 'partials are not translated');

    speech.session!.add(const Transcript('how much is this', isFinal: true));
    await speech.session!.close();
    await tester.pumpAndSettle();

    expect(translator.calls, ['en>kn:how much is this']);
    expect(find.text('yeshtu'), findsOneWidget);
    expect(find.text('ಎಷ್ಟು'), findsOneWidget);
    expect(tts.spoken, ['ಎಷ್ಟು']);
  });

  testWidgets('session ending without a final result still translates once',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('mic')));
    await tester.pump();

    speech.session!.add(const Transcript('water'));
    await speech.session!.close();
    await tester.pumpAndSettle();

    expect(translator.calls, ['en>kn:water']);
  });

  testWidgets('no speech shows a friendly error and translates nothing',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('mic')));
    await tester.pump();

    speech.session!.addError(const SpeechException('error_no_match'));
    await speech.session!.close();
    await tester.pumpAndSettle();

    expect(find.text('Didn\'t catch that. Tap the mic and try again.'),
        findsOneWidget);
    expect(translator.calls, isEmpty);
  });

  testWidgets('Hindi source is passed to the recognizer and translator',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('हिंदी'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mic')));
    await tester.pump();

    expect(speech.lastLang, 'hi');
    speech.session!.add(const Transcript('पानी', isFinal: true));
    await speech.session!.close();
    await tester.pumpAndSettle();

    expect(translator.calls, ['hi>kn:पानी']);
  });

  testWidgets('switching away from Speak mode stops listening',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('mic')));
    await tester.pump();

    await tester.pumpWidget(app(active: false));
    await tester.pumpAndSettle();

    expect(speech.stops, 1);
  });

  testWidgets('a misheard word can be fixed and translated again',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('mic')));
    await tester.pump();
    speech.session!.add(const Transcript('how much is dish', isFinal: true));
    await speech.session!.close();
    await tester.pumpAndSettle();

    expect(translator.calls, ['en>kn:how much is dish']);
    final field = find.byKey(const Key('heard'));
    expect(field, findsOneWidget);
    expect(find.text('how much is dish'), findsOneWidget);

    // Unchanged text: nothing to re-translate yet.
    IconButton retry() =>
        tester.widget<IconButton>(find.byKey(const Key('retranslate')));
    expect(retry().onPressed, isNull);

    await tester.enterText(field, 'how much is this');
    await tester.pump();
    expect(retry().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('retranslate')));
    await tester.pumpAndSettle();
    expect(translator.calls, ['en>kn:how much is dish', 'en>kn:how much is this']);
    expect(retry().onPressed, isNull, reason: 'result now matches the text');
  });

  test('error codes map to helpful messages', () {
    String msg(String code) => speechErrorMessage(SpeechException(code));
    expect(msg('error_permission'), contains('microphone'));
    expect(msg('error_network'), contains('internet'));
    expect(msg('error_weird'), 'Mic error (error_weird). Try again.');
  });
}
