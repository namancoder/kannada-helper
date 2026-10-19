import 'package:flutter/material.dart';

import 'engines/engines.dart';
import 'engines/kannada_romanizer.dart';
import 'engines/mlkit_translator.dart';
import 'engines/platform_speech_to_text.dart';
import 'engines/system_tts.dart';
import 'services/language_packs.dart';
import 'ui/home_screen.dart';
import 'ui/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KannadaHelperApp(
    translator: MlKitTranslator(),
    tts: SystemTts(),
    romanizer: const KannadaRomanizer(),
    packs: LanguagePacks(),
    speech: PlatformSpeechToText(),
  ));
}

class KannadaHelperApp extends StatefulWidget {
  const KannadaHelperApp({
    super.key,
    required this.translator,
    required this.tts,
    required this.romanizer,
    required this.packs,
    required this.speech,
  });

  final Translator translator;
  final TextToSpeech tts;
  final Romanizer romanizer;
  final LanguagePacks packs;
  final SpeechToText speech;

  @override
  State<KannadaHelperApp> createState() => _KannadaHelperAppState();
}

class _KannadaHelperAppState extends State<KannadaHelperApp> {
  /// null = still checking, true = packs present, false = needs download.
  bool? _ready;

  @override
  void initState() {
    super.initState();
    _checkPacks();
  }

  Future<void> _checkPacks() async {
    bool ready;
    try {
      ready = (await widget.packs.missing()).isEmpty;
    } catch (_) {
      ready = false;
    }
    if (mounted) setState(() => _ready = ready);
  }

  @override
  void dispose() {
    widget.translator.dispose();
    widget.tts.stop();
    widget.speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget home = switch (_ready) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      false => SetupScreen(
          packs: widget.packs,
          onDone: () => setState(() => _ready = true),
        ),
      true => HomeScreen(
          translator: widget.translator,
          tts: widget.tts,
          romanizer: widget.romanizer,
          speech: widget.speech,
        ),
    };

    return MaterialApp(
      title: 'Kannada Helper',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: home,
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFD4372C), // Karnataka flag red
        brightness: brightness,
      );
}
