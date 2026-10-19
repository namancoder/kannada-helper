import 'package:flutter_tts/flutter_tts.dart';

import 'engines.dart';

/// v1 audio engine: the phone's built-in text-to-speech.
/// Kannada needs its voice installed once in the phone's TTS settings.
class SystemTts implements TextToSpeech {
  SystemTts({this.speechRate = 0.4});

  /// Slower than normal so you can catch each syllable. Tweak to taste.
  final double speechRate;

  final FlutterTts _tts = FlutterTts();

  static String _locale(String lang) => switch (lang) {
        'kn' => 'kn-IN',
        'hi' => 'hi-IN',
        'en' => 'en-IN',
        _ => throw ArgumentError.value(lang, 'lang', 'Unsupported language'),
      };

  @override
  Future<bool> isAvailable(String lang) async {
    try {
      final dynamic result = await _tts.isLanguageAvailable(_locale(lang));
      return result == true || result == 1;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speak(String text, String lang) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.setLanguage(_locale(lang));
    await _tts.setSpeechRate(speechRate);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}
