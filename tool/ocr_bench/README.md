# Kannada OCR benchmark + model export

Compares Tesseract (`kan`, what the app uses today) with IndicPhotoOCR's
Kannada PARSeq model, and converts PARSeq to a phone-ready ONNX file.

```bash
pip install torch timm onnx onnxruntime pillow   # Pillow must have libraqm
pip download --no-deps IndicPhotoOCR && unzip indicphotoocr-*.whl -d ipo_src
curl -LO https://github.com/anikde/STocr/releases/download/V2.0.0/kannada.ckpt   # 382 MB

python3 gen_words.py <fonts_dir_with_kannada_ttfs> data          # 768 test images
python3 export_onnx.py ipo_src kannada.ckpt onnx                  # makes int8 model
python3 run_bench.py onnx data res_int8.tsv ipo_src kannada.ckpt onnx/kannada_parseq_int8.onnx 1
python3 run_bench.py tesseract data res_tess.tsv <tessdata_dir>
```

Results (2026-10-23, synthetic words, 4 fonts x 64 words x clean/photo/signboard,
word already cropped; after mapping digit zero after a letter to the anusvara):

| Engine | Words exact | Characters | Size | Time / word (1 CPU core, server) |
|---|---|---|---|---|
| Tesseract `kan` fast | 53% | 91% | 3.6 MB | ~50 ms |
| PARSeq int8 (ONNX) | 95% | 99% | 35 MB | ~41 ms |

Synthetic text is easier than real photos; re-run on real phone samples.
Model input: RGB 32x128, scaled to [-1, 1]. Output: logits [1, 26, 100];
argmax per position, stop at class 0 (end). Common confusion: ಂ read as ೦.
