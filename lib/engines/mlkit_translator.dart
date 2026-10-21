import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'engines.dart';

/// v1 translation engine: Google ML Kit, fully on-device.
/// Free, offline, no quota. Models must be downloaded first (see LanguagePacks).
/// Pairs without English (hi -> kn, kn -> hi) pivot through English internally.
///
/// All calls run strictly one at a time. ML Kit's native library crashes
/// (SIGABRT, "InitGoogle() has not finished yet") if a second translator
/// starts while the first is still initialising, e.g. Scan asking for English
/// and Hindi together.
class MlKitTranslator implements Translator {
  final Map<String, OnDeviceTranslator> _translators = {};
  Future<void> _queue = Future.value();

  /// Runs [job] after every earlier job has finished (success or error).
  Future<T> _serial<T>(Future<T> Function() job) {
    final result = _queue.then((_) => job());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static TranslateLanguage languageFor(String code) => switch (code) {
        'en' => TranslateLanguage.english,
        'hi' => TranslateLanguage.hindi,
        'kn' => TranslateLanguage.kannada,
        _ => throw ArgumentError.value(code, 'code', 'Unsupported language'),
      };

  @override
  Future<String> translate(String text, String from, String to) {
    final input = text.trim();
    if (input.isEmpty || from == to) return Future.value(input);
    return _serial(() => _translate(input, from, to));
  }

  Future<String> _translate(String input, String from, String to) {
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
  Future<void> dispose() => _serial(() async {
        for (final translator in _translators.values) {
          await translator.close();
        }
        _translators.clear();
      });
}
