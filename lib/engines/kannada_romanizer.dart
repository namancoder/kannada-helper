import 'engines.dart';

/// Rule-based Kannada -> English letters, tuned for casual, readable spelling
/// a learner can pronounce ("namaskaara", "yeshtu", "swalpa"), not academic
/// transliteration. Pure Dart, no dependencies. See PLAN.md §5.
///
/// Rules:
/// * Consonants carry an inherent "a": ಕ -> ka.
/// * Vowel signs replace that "a": ಕಿ -> ki. Virama (್) removes it: ಕ್ -> k.
/// * Long vowels are doubled (aa, ee, oo) so you know to stretch them.
///   Pass `simplifyLongVowels: true` for plain a / i / u.
/// * Word-initial ಎ / ಏ -> "ye" (how they're spoken: ಎಷ್ಟು -> yeshtu).
/// * ವ right after a consonant cluster -> "w" (ಸ್ವಲ್ಪ -> swalpa).
/// * ಜ್ಞ -> "gn" (ಜ್ಞಾನ -> gnaana).
/// * Anusvara (ಂ) -> "m" before p/b/m and at word end, else "n".
/// * Visarga (ಃ) -> "h". Kannada digits -> 0-9. Everything else passes through.
class KannadaRomanizer implements Romanizer {
  const KannadaRomanizer({this.simplifyLongVowels = false});

  final bool simplifyLongVowels;

  static const int _virama = 0x0CCD;
  static const int _anusvara = 0x0C82;
  static const int _visarga = 0x0C83;
  static const int _nukta = 0x0CBC;
  static const int _ja = 0x0C9C;
  static const int _nya = 0x0C9E;
  static const int _va = 0x0CB5;

  /// Characters that are silently dropped: nukta, length marks, ZWNJ, ZWJ.
  static const Set<int> _ignored = {_nukta, 0x0CD5, 0x0CD6, 0x200C, 0x200D};

  static const Map<int, String> _independentVowels = {
    0x0C85: 'a', // ಅ
    0x0C86: 'aa', // ಆ
    0x0C87: 'i', // ಇ
    0x0C88: 'ee', // ಈ
    0x0C89: 'u', // ಉ
    0x0C8A: 'oo', // ಊ
    0x0C8B: 'ru', // ಋ
    0x0C8E: 'e', // ಎ
    0x0C8F: 'e', // ಏ
    0x0C90: 'ai', // ಐ
    0x0C92: 'o', // ಒ
    0x0C93: 'o', // ಓ
    0x0C94: 'au', // ಔ
  };

  static const Map<int, String> _vowelSigns = {
    0x0CBE: 'aa', // ಾ
    0x0CBF: 'i', // ಿ
    0x0CC0: 'ee', // ೀ
    0x0CC1: 'u', // ು
    0x0CC2: 'oo', // ೂ
    0x0CC3: 'ru', // ೃ
    0x0CC6: 'e', // ೆ
    0x0CC7: 'e', // ೇ
    0x0CC8: 'ai', // ೈ
    0x0CCA: 'o', // ೊ
    0x0CCB: 'o', // ೋ
    0x0CCC: 'au', // ೌ
  };

  static const Map<int, String> _consonants = {
    0x0C95: 'k', 0x0C96: 'kh', 0x0C97: 'g', 0x0C98: 'gh', 0x0C99: 'n', // ಕ-ಙ
    0x0C9A: 'ch', 0x0C9B: 'chh', 0x0C9C: 'j', 0x0C9D: 'jh', 0x0C9E: 'n', // ಚ-ಞ
    0x0C9F: 't', 0x0CA0: 'th', 0x0CA1: 'd', 0x0CA2: 'dh', 0x0CA3: 'n', // ಟ-ಣ
    0x0CA4: 't', 0x0CA5: 'th', 0x0CA6: 'd', 0x0CA7: 'dh', 0x0CA8: 'n', // ತ-ನ
    0x0CAA: 'p', 0x0CAB: 'ph', 0x0CAC: 'b', 0x0CAD: 'bh', 0x0CAE: 'm', // ಪ-ಮ
    0x0CAF: 'y', 0x0CB0: 'r', 0x0CB1: 'r', 0x0CB2: 'l', 0x0CB3: 'l', // ಯ-ಳ
    0x0CB5: 'v', 0x0CB6: 'sh', 0x0CB7: 'sh', 0x0CB8: 's', 0x0CB9: 'h', // ವ-ಹ
    0x0CDE: 'l', // ೞ (archaic)
  };

  /// ಪ ಫ ಬ ಭ ಮ: anusvara before these sounds like "m".
  static const Set<int> _labials = {0x0CAA, 0x0CAB, 0x0CAC, 0x0CAD, 0x0CAE};

  @override
  String toLatin(String kannada) {
    final chars = kannada.runes.toList(growable: false);
    final out = StringBuffer();
    var pendingA = false; // a consonant was written and still owes its "a"

    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      final next = i + 1 < chars.length ? chars[i + 1] : null;

      if (_ignored.contains(c)) continue;

      final sign = _vowelSigns[c];
      if (sign != null) {
        pendingA = false;
        out.write(_vowel(sign));
        continue;
      }

      if (c == _virama) {
        pendingA = false;
        continue;
      }

      if (pendingA) {
        out.write('a');
        pendingA = false;
      }

      final consonant = _consonants[c];
      if (consonant != null) {
        // ಜ್ಞ -> gn
        if (c == _ja &&
            next == _virama &&
            i + 2 < chars.length &&
            chars[i + 2] == _nya) {
          out.write('gn');
          i += 2;
          pendingA = true;
          continue;
        }
        // ವ after a cluster (ಸ್ವ, ತ್ವ, ದ್ವ ...) -> w
        final afterCluster = i >= 2 &&
            chars[i - 1] == _virama &&
            _consonants.containsKey(chars[i - 2]);
        out.write(c == _va && afterCluster ? 'w' : consonant);
        pendingA = true;
        continue;
      }

      final vowel = _independentVowels[c];
      if (vowel != null) {
        final isE = c == 0x0C8E || c == 0x0C8F;
        out.write(isE && _isWordStart(chars, i) ? 'ye' : _vowel(vowel));
        continue;
      }

      if (c == _anusvara) {
        final atWordEnd = next == null || !_isKannadaLetter(next);
        out.write(atWordEnd || _labials.contains(next) ? 'm' : 'n');
        continue;
      }

      if (c == _visarga) {
        out.write('h');
        continue;
      }

      if (c >= 0x0CE6 && c <= 0x0CEF) {
        out.write(c - 0x0CE6); // Kannada digits ೦-೯
        continue;
      }

      out.writeCharCode(c);
    }

    if (pendingA) out.write('a');
    return out.toString();
  }

  String _vowel(String v) {
    if (!simplifyLongVowels) return v;
    return switch (v) { 'aa' => 'a', 'ee' => 'i', 'oo' => 'u', _ => v };
  }

  static bool _isKannadaLetter(int c) =>
      _consonants.containsKey(c) || _independentVowels.containsKey(c);

  static bool _isWordStart(List<int> chars, int i) {
    if (i == 0) return true;
    final prev = chars[i - 1];
    final isKannada = prev >= 0x0C80 && prev <= 0x0CFF;
    final isAsciiWordChar = (prev >= 0x30 && prev <= 0x39) ||
        (prev >= 0x41 && prev <= 0x5A) ||
        (prev >= 0x61 && prev <= 0x7A);
    return !isKannada && !isAsciiWordChar;
  }
}
