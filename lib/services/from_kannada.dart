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

    final results = await Future.wait([
      translator.translate(input, 'kn', 'en'),
      translator.translate(input, 'kn', 'hi'),
    ]);
    final result = (en: results[0], hi: results[1]);
    _cache[input] = result;
    return result;
  }
}
