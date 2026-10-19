import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'engines.dart';

/// v1 translation engine: Google ML Kit, fully on-device.
/// Free, offline, no quota. Models must be downloaded first (see LanguagePacks).
/// Pairs without English (hi -> kn, kn -> hi) pivot through English internally.
class MlKitTranslator implements Translator {
  final Map<String, OnDeviceTranslator> _translators = {};

  static TranslateLanguage languageFor(String code) => switch (code) {
        'en' => TranslateLanguage.english,
        'hi' => TranslateLanguage.hindi,
        'kn' => TranslateLanguage.kannada,
        _ => throw ArgumentError.value(code, 'code', 'Unsupported language'),
      };

  @override
  Future<String> translate(String text, String from, String to) async {
    final input = text.trim();
    if (input.isEmpty || from == to) return input;

    // Translators are cheap to keep and slow to create, so reuse per pair.
    final translator = _translators.putIfAbsent(
      '$from>$to',
      () => OnDeviceTranslator(
        sourceLanguage: languageFor(from),
        targetLanguage: languageFor(to),
      ),
    );
    return translator.translateText(input);
  }

  @override
  Future<void> dispose() async {
    for (final translator in _translators.values) {
      await translator.close();
    }
    _translators.clear();
  }
}
