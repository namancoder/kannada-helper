import 'package:flutter_test/flutter_test.dart';
import 'package:kannada_helper/engines/kannada_romanizer.dart';

void main() {
  const r = KannadaRomanizer();

  group('everyday words', () {
    const cases = {
      'ನಮಸ್ಕಾರ': 'namaskaara',
      'ಕನ್ನಡ': 'kannada',
      'ಬೆಂಗಳೂರು': 'bengalooru',
      'ಹೌದು': 'haudu',
      'ಇಲ್ಲ': 'illa',
      'ಬೇಕು': 'beku',
      'ಬೇಡ': 'beda',
      'ಎಷ್ಟು': 'yeshtu',
      'ಎಲ್ಲಿ': 'yelli',
      'ಏನು': 'yenu',
      'ಧನ್ಯವಾದಗಳು': 'dhanyavaadagalu',
      'ಸ್ವಲ್ಪ': 'swalpa',
      'ನೀರು': 'neeru',
      'ಊಟ': 'oota',
      'ಹೆಸರು': 'hesaru',
      'ಗೊತ್ತಿಲ್ಲ': 'gottilla',
      'ಮನೆ': 'mane',
      'ಅಮ್ಮ': 'amma',
      'ಐದು': 'aidu',
      'ಕೈ': 'kai',
      'ಔಷಧ': 'aushadha',
      'ಹೇಗಿದ್ದೀರಾ': 'hegiddeeraa',
      'ನಿಲ್ದಾಣ': 'nildaana',
    };
    cases.forEach((kannada, expected) {
      test('$kannada -> $expected', () => expect(r.toLatin(kannada), expected));
    });
  });

  group('special rules', () {
    test('anusvara before labial is m', () {
      expect(r.toLatin('ಸಂಬಳ'), 'sambala');
    });
    test('anusvara before other consonants is n', () {
      expect(r.toLatin('ಶಾಂತಿ'), 'shaanti');
    });
    test('anusvara at word end is m', () {
      expect(r.toLatin('ಕಿರಣಂ'), 'kiranam');
    });
    test('jña cluster is gn', () {
      expect(r.toLatin('ಜ್ಞಾನ'), 'gnaana');
    });
    test('vocalic r', () {
      expect(r.toLatin('ಕೃಷ್ಣ'), 'krushna');
    });
    test('visarga is h', () {
      expect(r.toLatin('ದುಃಖ'), 'duhkha');
    });
    test('ಎ mid-sentence after a space is still word-initial', () {
      expect(r.toLatin('ಇದು ಏನು'), 'idu yenu');
    });
  });

  group('pass-through', () {
    test('empty string', () => expect(r.toLatin(''), ''));
    test('punctuation kept', () {
      expect(r.toLatin('ಹೌದು, ಬೇಕು!'), 'haudu, beku!');
    });
    test('question mark kept', () {
      expect(r.toLatin('ಎಲ್ಲಿ?'), 'yelli?');
    });
    test('mixed English and Kannada', () {
      expect(r.toLatin('Bus ನಿಲ್ದಾಣ'), 'Bus nildaana');
    });
    test('Kannada digits become ASCII', () {
      expect(r.toLatin('೧೨೩'), '123');
    });
    test('zero-width joiners are ignored', () {
      expect(r.toLatin('ಕ‍ನ'), 'kana');
    });
  });

  test('simplifyLongVowels collapses aa/ee/oo', () {
    const simple = KannadaRomanizer(simplifyLongVowels: true);
    expect(simple.toLatin('ನಮಸ್ಕಾರ'), 'namaskara');
    expect(simple.toLatin('ನೀರು'), 'niru');
    expect(simple.toLatin('ಊಟ'), 'uta');
  });
}
