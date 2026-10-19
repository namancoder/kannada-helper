import '../engines/engines.dart';

/// The shared "English/Hindi -> Kannada" step used by every input mode.
/// Caches results so repeating a phrase is instant.
class ToKannada {
  ToKannada(this.translator);

  final Translator translator;
  final Map<String, String> _cache = {};

  Future<String> call(String text, String from) async {
    final input = text.trim();
    if (input.isEmpty) return '';
    final key = '$from|${input.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final result = await translator.translate(input, from, 'kn');
    _cache[key] = result;
    return result;
  }
}
