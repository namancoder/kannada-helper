# Kannada Helper

Personal offline Flutter app (Android) to understand and speak basic Kannada.
One screen, three modes, no server, no API keys. See **PLAN.md** for the full plan.

**Status: Phase 0–1 done.** Type mode works end to end:
English or Hindi in → Kannada in English letters (big) + Kannada script + ▶️ audio.
Speak (Phase 2) and Scan (Phase 3) show placeholders.

---

## Run it

Needs Flutter (stable channel) and an Android phone with USB debugging on.

```bash
cd kannada_helper

# 1. Generate the Android platform folder (keeps the existing lib/ and test/)
flutter create --platforms=android --project-name kannada_helper --org dev.ng .

# 2. Add INTERNET permission + TTS query to AndroidManifest.xml
dart run tool/patch_android.dart

# 3. Fetch packages and run the tests
flutter pub get
flutter test

# 4. Run on your phone
flutter run
```

**First launch** shows a one-time screen that downloads the English, Hindi and
Kannada translation packs. After that, translation works in airplane mode.

**No sound?** The app needs a Kannada voice in the phone's text-to-speech engine.
Install or update *Speech Services by Google*, set it as the preferred TTS engine,
and download the Kannada voice from its settings. The app shows a hint when no
Kannada voice is found.

### If the build complains
- **minSdk errors:** set `minSdk = 21` (or higher) in `android/app/build.gradle(.kts)`.
- **Package version conflicts:** run `flutter pub upgrade --major-versions`.
- This code was written without a local Flutter SDK, so a first-build fix or two
  is possible. Paste the error into Claude (or let Claude Code run the build) and fix from there.

---

## Project layout

```
lib/
  main.dart                     app entry, picks Setup vs Home screen
  engines/
    engines.dart                the 5 swappable interfaces (Ocr, SpeechToText,
                                Translator, TextToSpeech, Romanizer)
    kannada_romanizer.dart      Kannada script → English letters, pure Dart
    mlkit_translator.dart       v1 Translator: Google ML Kit, on-device
    system_tts.dart             v1 TextToSpeech: phone's built-in TTS
  services/
    language_packs.dart         one-time translation model download
  ui/
    home_screen.dart            the one screen: Type / Speak / Scan
    setup_screen.dart           first-launch download screen
    result_card.dart            romanized + script + play button
test/
  kannada_romanizer_test.dart   39 expectations for the romanizer
  widget_test.dart              ResultCard widget tests
tool/
  patch_android.dart            one-off AndroidManifest patcher
```

**Swapping engines:** the UI only depends on the interfaces in `engines.dart`.
For v2 (PLAN.md Phase 5), write `IndicTransTranslator implements Translator`
and change one line in `main.dart`.

---

## Romanizer cheat sheet

| Kannada | Output | Rule |
|---|---|---|
| ನಮಸ್ಕಾರ | namaskaara | long vowels doubled (`simplifyLongVowels: true` → namaskara) |
| ಎಷ್ಟು, ಏನು | yeshtu, yenu | word-initial ಎ/ಏ → "ye", as spoken |
| ಸ್ವಲ್ಪ | swalpa | ವ after a cluster → "w" |
| ಬೆಂಗಳೂರು | bengalooru | ಂ → "n", or "m" before p/b/m |
| ಜ್ಞಾನ | gnaana | ಜ್ಞ → "gn" |

---

## Next: Phase 2 (Speak mode)
- Add `speech_to_text`, implement `SpeechToText` in `lib/engines/`
- Mic button in Speak mode → transcript into the same translate flow as Type
- Handle mic permission denial and silence timeouts
