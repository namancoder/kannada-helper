// Engine interfaces. The UI only talks to these, so any engine can be swapped
// (e.g. ML Kit -> IndicTrans2) without touching screens. See PLAN.md §2.
//
// Language codes used everywhere: 'en', 'hi', 'kn'.
import 'dart:typed_data';

/// Reads Kannada text from an image. (Phase 3: Tesseract `kan`.)
abstract class Ocr {
  Future<String> read(Uint8List image);
}

/// One piece of recognized speech.
class Transcript {
  const Transcript(this.text, {this.isFinal = false});

  final String text;

  /// True once the recognizer has settled on this text.
  final bool isFinal;
}

/// Something went wrong while listening (no permission, no speech, ...).
class SpeechException implements Exception {
  const SpeechException(this.code, {this.permanent = true});

  /// Engine error code, e.g. 'error_no_match', 'error_permission'.
  final String code;
  final bool permanent;

  @override
  String toString() => 'SpeechException($code)';
}

/// Turns speech into text. (Phase 2: `speech_to_text`, later Vosk.)
abstract class SpeechToText {
  /// Prepares the engine and asks for mic permission the first time.
  /// Returns false if speech recognition can't be used.
  Future<bool> initialize();

  /// Starts one listening session. Emits partial transcripts, then a final
  /// one, then closes. Errors arrive as [SpeechException] on the stream.
  Stream<Transcript> listen(String lang);

  /// Stops listening early; whatever was heard is still delivered.
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
