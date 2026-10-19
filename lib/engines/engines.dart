// Engine interfaces. The UI only talks to these, so any engine can be swapped
// (e.g. ML Kit -> IndicTrans2) without touching screens. See PLAN.md §2.
//
// Language codes used everywhere: 'en', 'hi', 'kn'.
import 'dart:typed_data';

/// Reads Kannada text from an image. (Phase 3: Tesseract `kan`.)
abstract class Ocr {
  Future<String> read(Uint8List image);
}

/// Turns speech into text. (Phase 2: `speech_to_text`, later Vosk.)
abstract class SpeechToText {
  /// Emits partial and final transcripts while listening.
  Stream<String> listen(String lang);
  Future<void> stop();
}

/// Translates text between 'en', 'hi' and 'kn'.
abstract class Translator {
  Future<String> translate(String text, String from, String to);
  Future<void> dispose();
}

/// Speaks text aloud.
abstract class TextToSpeech {
  /// Whether a voice for [lang] is installed on the device.
  Future<bool> isAvailable(String lang);
  Future<void> speak(String text, String lang);
  Future<void> stop();
}

/// Converts Kannada script to readable English letters.
abstract class Romanizer {
  String toLatin(String kannada);
}
