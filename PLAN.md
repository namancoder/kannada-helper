# Kannada Helper — Build Plan (Client-only, Offline)

A personal Flutter app (Android first) to understand and speak basic Kannada around Bangalore.

**Principles**
- **Simplest UX, no BS:** one screen, three buttons, no login.
- **Client-side only:** no server, no API keys, no quotas, no monthly bills.
- **Offline after first launch:** models download once, then everything runs on the phone.

---

## 1. What the app does

| Mode | Input | Output |
|---|---|---|
| 📷 **Scan** | Camera pointed at Kannada text (boards, menus, bills) | English + Hindi meaning, refreshed every ~1–2s |
| 🎤 **Speak** | Your voice in English or Hindi | Kannada script + Kannada in English letters + ▶️ audio |
| ⌨️ **Type** | English or Hindi text | Same as Speak |

**Out of scope for v1:** accounts, cloud sync, AR overlays, Kannada speech as input.

---

## 2. Architecture

```
┌──────────────────────── Flutter app (all on-device) ────────────────────────┐
│                                                                             │
│  Scan:  camera stream → crop box → OCR (Tesseract, kan) ──┐                 │
│  Speak: mic → SpeechToText (en / hi) ─────────────────────┤                 │
│  Type:  text field ───────────────────────────────────────┤                 │
│                                                           ▼                 │
│                                         Translator (interface)              │
│                                     v1: ML Kit on-device                    │
│                                     v2: IndicTrans2 ONNX (open source)      │
│                                                           ▼                 │
│                         Romanizer (Dart) ── TextToSpeech (kn) ── UI         │
│                                                                             │
│  Local cache (sqlite / shared_preferences) for recent + common phrases      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key design rule:** every engine sits behind a small Dart interface so you can swap the implementation without touching the UI.

```dart
abstract class Ocr          { Future<String> read(Uint8List image); }
abstract class SpeechToText { Stream<String> listen(String lang); Future<void> stop(); }
abstract class Translator   { Future<String> translate(String text, String from, String to); }
abstract class TextToSpeech { Future<void> speak(String text, String lang); }
abstract class Romanizer    { String toLatin(String kannada); }
```

---

## 3. Engine choices: two stages

### Stage v1: free, unlimited, fast to build (some closed-source parts)

| Job | Choice | License / notes |
|---|---|---|
| OCR | Tesseract + `kan.traineddata` (tessdata_fast) via a Flutter wrapper | Apache 2.0. **ML Kit OCR does NOT support Kannada script**, so don't use it |
| Translate | Google ML Kit on-device translation (`google_mlkit_translation`) | Free, offline, no quota, closed source. Each language model is a one-time download. Non-English pairs (kn→hi) pivot through English |
| Voice → text | `speech_to_text` (Android's built-in recognizer) | Free. May need internet for best Hindi results |
| Kannada audio | `flutter_tts` (Android system TTS) | Free. Install the Kannada voice in the phone's TTS settings once |
| Romanization | Your own Dart class (see §5) | Yours |

### Stage v2: fully open source (heavy lifting)

| Job | Choice | Size (approx) |
|---|---|---|
| Translate en→kn | IndicTrans2 en-indic distilled 200M, INT8 ONNX | ~360 MB |
| Translate kn→en | IndicTrans2 indic-en distilled 200M, INT8 ONNX | ~260 MB |
| Translate kn→hi (direct) | IndicTrans2 indic-indic distilled 320M, INT8 ONNX | ~370 MB (optional; else pivot via English) |
| Voice → text | Vosk (`vosk_flutter`), models `en-in` + `hi` | ~50 MB each, Apache 2.0 |
| Kannada audio | AI4Bharat Indic-TTS (FastPitch + HiFi-GAN), ONNX | check model card |
| Runtime | `onnxruntime` Flutter package | |

> ⚠️ ONNX conversions of IndicTrans2 are **community** exports (MIT), not official AI4Bharat releases. Spot-check output quality against the official model or the AI4Bharat demo before trusting them.

> ⚠️ Check each pub.dev package's last update date and Android support before adding it. Tesseract and Vosk wrappers in particular come and go.

---

## 4. Model management (no server needed)

- **Don't bundle models in the APK.** On first launch, show one screen: "Download language pack (~X MB)" → download from Hugging Face / GitHub release URLs directly to app storage.
- Verify each file with a SHA-256 checksum (hardcode the hashes in the app).
- Show progress; resume on failure; Wi-Fi only by default.
- ML Kit models: use its own model manager to pre-download `en`, `kn`, `hi`.
- A settings row: "Language packs: 820 MB, delete / re-download". That's the only setting.

---

## 5. Romanizer (Kannada → English letters), pure Dart

Rule-based, ~100–150 lines, no library needed:
1. **Consonants** carry an inherent "a": ಕ → `ka`, ನ → `na`.
2. **Vowel signs** replace the inherent "a": ಕಿ → `ki`, ಕೊ → `ko`.
3. **Virama (್)** removes the "a": ಕ್ → `k` (this is how clusters like ಸ್ಕ → `sk` form).
4. **Independent vowels:** ಅ `a`, ಆ `aa`, ಇ `i`, ಈ `ee`, ಉ `u`, ಊ `oo`, ಎ `e`, ಏ `e`, ಐ `ai`, ಒ `o`, ಓ `o`, ಔ `au`.
5. **Anusvara (ಂ)** → `m` before labials (ಪ ಬ ಮ), else `n`. **Visarga (ಃ)** → `h`.
6. Kannada Unicode block: `U+0C80–U+0CFF`. Pass anything else through unchanged.

Aim for **casual readable spelling** ("namaskara", "yeshtu"), not academic transliteration. Write unit tests with ~30 known words.

---

## 6. Build phases

### Phase 0: Setup (½ day)
- [ ] `flutter create kannada_helper`, run on your phone
- [ ] Install the Kannada voice in Android TTS settings; test `flutter_tts` speaking "ನಮಸ್ಕಾರ"
- [ ] Define the 5 interfaces from §2

### Phase 1: Type mode on v1 engines (1 day): **first usable app**
- [ ] ML Kit translator: pre-download `en`, `kn`, `hi` models
- [ ] Screen: text field, EN/HI toggle, result card with:
  - Romanized Kannada (**big**, since that's what you'll actually read)
  - Kannada script (small)
  - ▶️ play button
- [ ] Romanizer + unit tests

### Phase 2: Speak mode (½–1 day)
- [ ] Mic button → `speech_to_text` (`en_IN` / `hi_IN`) → fill the field → auto-translate
- [ ] Handle mic permission denial and silence timeouts

### Phase 3: Scan mode (2–3 days, the hard part)
- [ ] Full-screen camera with a centered scan box
- [ ] Image stream throttled to ~1 frame/sec; drop frames while OCR is busy (run OCR in an isolate)
- [ ] Crop to box → grayscale → Tesseract `kan`
- [ ] Only translate if the text **changed** and has ≥2 Kannada characters
- [ ] Bottom card shows English + Hindi; keep the last good result (no flicker)
- [ ] "Freeze" button: grab one sharp frame for better accuracy
- [ ] Stop the camera stream when the app is backgrounded (battery)

### Phase 4: Polish (1–2 days)
- [ ] "Common phrases" tab: hand-curated top 50 (auto, shop, food, office). Machine translation is often too formal for street Kannada
- [ ] Recent translations, stored locally
- [ ] First-launch language-pack download screen (§4)

### Phase 5: Go fully open source (v2, 1–2 weeks, learning project)
- [ ] Download the IndicTrans2 INT8 ONNX models (en→kn, kn→en) and run them in Python first to confirm quality
- [ ] Port preprocessing to Dart/Kotlin: script conversion, language tags, SentencePiece tokenization, `</s>` handling. **This is the real work; follow the model card exactly**
- [ ] Run the encoder/decoder with `onnxruntime`; **greedy decoding** (beam = 1) for speed
- [ ] Implement `IndicTransTranslator implements Translator` and swap it in
- [ ] Replace `speech_to_text` with Vosk (`en-in`, `hi` models)
- [ ] Optionally replace system TTS with AI4Bharat Indic-TTS ONNX
- [ ] Benchmark: target < 2s per short sentence on your phone

---

## 7. Known risks

| Risk | Mitigation |
|---|---|
| Tesseract is weak on stylized signboard fonts | Scan box + freeze button; printed text works best |
| ML Kit quality is "casual" and kn→hi pivots via English | Fine for v1; IndicTrans2 in v2 |
| IndicTrans2 on-device latency (~1–6s per sentence depending on phone and beam) | Greedy decoding, short inputs, cache results |
| App storage ~0.7–1 GB with all v2 models | Download on demand; make kn→hi direct optional |
| ONNX preprocessing mismatch → garbage output | Validate in Python first; unit-test tokenizer against known outputs |
| Formal vs spoken Kannada | Curated phrase list |
| Battery / heat in Scan mode | 1 fps throttle, OCR in isolate, stop stream when hidden |

---

## 8. Definition of done (v1)
- Works in **airplane mode** (after language packs are downloaded)
- Type or speak "how much is this?" → hear correct Kannada within ~2s
- Point at a printed Kannada menu → read the English meaning within ~2s
- App opens straight to the 3 buttons

---

## 9. Reference links
- ML Kit translation languages: https://developers.google.com/ml-kit/language/translation/translation-language-support
- ML Kit OCR scripts (why it's not used for scanning): https://developers.google.com/ml-kit/vision/text-recognition/languages
- Tesseract fast models (`kan.traineddata`): https://github.com/tesseract-ocr/tessdata_fast
- IndicTrans2 (official): https://github.com/AI4Bharat/IndicTrans2
- IndicTrans2 INT8 ONNX (community): https://huggingface.co/remiai3/TRANSLATION_MODELS
- On-device IndicTrans2 notes + benchmark: https://huggingface.co/mobilebytesensei/betterflow-indictrans2-indic-en-200m-int8
- EchoBharat (offline Android Indic translator, good reference): https://huggingface.co/RaunakSaha/echobharat-models
- Vosk: https://github.com/alphacep/vosk-api
