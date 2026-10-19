# Kannada Helper

Personal offline Flutter app (Android) to understand and speak basic Kannada.
One screen, three modes, no server, no API keys. See **PLAN.md** for the full plan.

**Status: Phases 0–2 done.**
- **Type:** English or Hindi in → Kannada in English letters (big) + Kannada script + ▶️ audio.
- **Speak:** tap the mic, speak English or Hindi → same result, played aloud automatically
  (toggle off with *Play Kannada automatically*).
- **Scan** (Phase 3) shows a placeholder.

---

## Run it

Needs Flutter (stable channel) and an Android phone with USB debugging on.

```bash
cd kannada_helper

# 1. Generate the Android platform folder (keeps the existing lib/ and test/)
flutter create --platforms=android --project-name kannada_helper --org dev.ng .

# 2. Add permissions (internet, microphone) + TTS/speech queries to AndroidManifest.xml
#    Safe to re-run; already patched for Phase 1? Run it again for Phase 2.
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

**Speak mode tips**
- The first mic tap asks for microphone permission.
- Speech uses the phone's Google speech engine. English works offline on most phones;
  Hindi may need internet unless you download the offline Hindi speech pack in your
  phone's speech/voice-typing settings.
- The mic stops by itself after ~3 s of silence, or tap it again to stop.

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
    platform_speech_to_text.dart  v1 SpeechToText: phone's recognizer
  services/
    language_packs.dart         one-time translation model download
    to_kannada.dart             shared en/hi → kn step with cache (all modes use it)
  ui/
    home_screen.dart            the one screen: Type / Speak / Scan
    type_view.dart              Type mode
    speak_view.dart             Speak mode (mic → transcript → Kannada)
    source_toggle.dart          English | हिंदी switch
    kannada_result.dart         ResultCard wired to romanizer + TTS
    setup_screen.dart           first-launch download screen
    result_card.dart            romanized + script + play button
test/
  kannada_romanizer_test.dart   39 expectations for the romanizer
  widget_test.dart              ResultCard widget tests
  speak_view_test.dart          Speak flow with fake mic/translator/TTS
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

## Next: Phase 3 (Scan mode)
- Camera preview with a scan box, ~1 frame/sec
- Tesseract `kan` OCR behind the `Ocr` interface, run off the UI thread
- Kannada → English + Hindi result card, with a freeze button
