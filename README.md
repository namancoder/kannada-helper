# Kannada Helper

Personal offline Flutter app (Android) to understand and speak basic Kannada.
One screen, three modes, no server, no API keys. See **PLAN.md** for the full plan.

**Status: Phases 0–3 done.**
- **Type:** English or Hindi in → Kannada in English letters (big) + Kannada script + ▶️ audio.
- **Speak:** tap the mic, speak English or Hindi → same result, played aloud automatically
  (toggle off with *Play Kannada automatically*).
- **Scan:** point the camera at Kannada text inside the box → English + Hindi meaning,
  plus the Kannada in English letters with ▶️ audio. *Freeze* takes a steadier still photo;
  the ⚡ button turns on the torch for dim menus.

---

## Run it

Needs Flutter (stable channel) and an Android phone with USB debugging on.

```bash
cd kannada_helper

# 1. Generate the Android platform folder (keeps the existing lib/ and test/)
flutter create --platforms=android --project-name kannada_helper --org dev.ng .

# 2. Add permissions, TTS/speech queries, minSdk 24 and the OCR bridge.
#    Safe to re-run; run it again after each new phase.
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

**Scan mode tips**
- First visit to Scan asks to download the Kannada reading model (a few MB, once),
  then asks for camera permission.
- Works best on **printed** text: menus, bills, bus boards. Fancy signboard fonts and
  handwriting often fail. Hold steady, fill the box, or tap **Freeze**.
- On the emulator the camera is a virtual room or your Mac's webcam. Hold a printed
  Kannada word up to the webcam, or test on the real phone.

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
    tesseract_ocr.dart          v1 Ocr: Tesseract `kan` via a native bridge, model downloaded once
  services/
    language_packs.dart         one-time translation model download
    to_kannada.dart             shared en/hi → kn step with cache (Type, Speak)
    from_kannada.dart           kn → en + hi with cache (Scan)
    scan_frame.dart             crop/rotate/contrast for the scan box (pure Dart)
  ui/
    home_screen.dart            the one screen: Type / Speak / Scan
    type_view.dart              Type mode
    speak_view.dart             Speak mode (mic → transcript → Kannada)
    scan_view.dart              Scan mode (camera → OCR → English + Hindi)
    source_toggle.dart          English | हिंदी switch
    kannada_result.dart         ResultCard wired to romanizer + TTS
    setup_screen.dart           first-launch download screen
    result_card.dart            romanized + script + play button
test/
  kannada_romanizer_test.dart   39 expectations for the romanizer
  widget_test.dart              ResultCard widget tests
  speak_view_test.dart          Speak flow with fake mic/translator/TTS
  scan_frame_test.dart          scan box crop/rotation + Kannada text cleanup
tool/android/
  MainActivity.kt               native OCR bridge (Tesseract4Android), copied
                                into android/ by patch_android.dart
tool/
  patch_android.dart            Android setup: manifest, minSdk, OCR bridge (re-runnable)
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

## Next: Phase 4 (Polish)
- Common phrases tab: hand-curated top 50 for autos, shops, food, office
- Recent translations, stored on the phone
