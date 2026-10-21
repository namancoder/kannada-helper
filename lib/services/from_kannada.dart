import '../engines/engines.dart';

/// Kannada -> English and Hindi, together. Used by Scan mode.
/// Caches results so re-reading the same sign costs nothing.
class FromKannada {
  FromKannada(this.translator);

  final Translator translator;
  final Map<String, ({String en, String hi})> _cache = {};

  Future<({String en, String hi})> call(String kannada) async {
    final input = kannada.trim();
    if (input.isEmpty) return (en: '', hi: '');
    final cached = _cache[input];
    if (cached != null) return cached;

    // One after the other on purpose: ML Kit can crash when two translators
    // start up at the same time.
    final en = await translator.translate(input, 'kn', 'en');
    final hi = await translator.translate(input, 'kn', 'hi');
    final result = (en: en, hi: hi);
    _cache[input] = result;
    return result;
  }
}
