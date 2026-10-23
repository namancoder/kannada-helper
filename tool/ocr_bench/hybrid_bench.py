"""End-to-end check of Scan mode's OCR: multi-word, multi-line scan-box images.

Mirrors the app: grayscale + contrast stretch (like scan_frame.dart), then
  A) Tesseract alone (what Scan used before), and
  B) hybrid: Tesseract word boxes -> margin crop -> PARSeq ONNX per word,
     words grouped into lines (same rules as MainActivity.kt).

python3 hybrid_bench.py <fonts_dir> <tessdata_dir> <ipo_src> <kannada.ckpt> <model.onnx>
"""
import os
import random
import re
import subprocess
import sys
import tempfile
import time
import unicodedata

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_words import WORDS, camera  # noqa: E402
from run_bench import edit_distance  # noqa: E402

ZERO = re.compile('(?<=[ಅ-ಹಾ-ೌ])೦')


def clean_kannada(raw):
    """Same as cleanKannada() in scan_frame.dart."""
    words = []
    for tok in raw.split():
        kept = ''.join(c for c in tok if 'ಀ' <= c <= '೿')
        letters = sum(1 for c in kept if 'ಅ' <= c <= 'ಔ' or 'ಕ' <= c <= 'ಹ')
        if letters >= 2:
            words.append(kept)
    return ' '.join(words)


def stretch(gray):
    """Same 2%/98% contrast stretch as scan_frame.dart."""
    a = np.asarray(gray, dtype=np.float32)
    lo, hi = np.percentile(a, 2), np.percentile(a, 98)
    if hi - lo >= 16:
        a = np.clip((a - lo) * 255.0 / (hi - lo), 0, 255)
    return Image.fromarray(a.astype(np.uint8))


def render_phrase(lines, font_path, size, fg, bg):
    font = ImageFont.truetype(font_path, size, layout_engine=ImageFont.Layout.RAQM)
    d = ImageDraw.Draw(Image.new('RGB', (1, 1)))
    boxes = [d.textbbox((0, 0), l, font=font, language='kn') for l in lines]
    w = max(b[2] - b[0] for b in boxes) + 60
    lh = int(size * 1.7)
    img = Image.new('RGB', (w, lh * len(lines) + 40), bg)
    dr = ImageDraw.Draw(img)
    for i, (l, b) in enumerate(zip(lines, boxes)):
        dr.text((30 - b[0], 20 + i * lh - b[1] + (lh - (b[3] - b[1])) // 2), l, font=font, fill=fg,
                language='kn')
    return img


def tesseract_tsv(path, tessdata, psm):
    out = subprocess.run(['tesseract', path, 'stdout', '-l', 'kan', '--psm', str(psm),
                          '--tessdata-dir', tessdata, '-c', 'tessedit_create_tsv=1'],
                         capture_output=True, text=True).stdout
    words = []
    for line in out.splitlines()[1:]:
        f = line.split('\t')
        if len(f) == 12 and f[0] == '5' and f[11].strip():
            l, t, w, h = map(int, f[6:10])
            words.append((l, t, l + w, t + h, f[11], float(f[10])))
    return words


def group_lines(boxes):
    lines = []
    for b in sorted(boxes, key=lambda b: (b[1] + b[3]) / 2):
        cy = (b[1] + b[3]) / 2
        if lines and min(x[1] for x in lines[-1]) <= cy <= max(x[3] for x in lines[-1]):
            lines[-1].append(b)
        else:
            lines.append([b])
    return [sorted(l, key=lambda b: b[0]) for l in lines]


def main():
    fonts_dir, tessdata, src, ckpt, onnx_path = sys.argv[1:6]
    import parseq_kn
    _, tok, _ = parseq_kn.load(ckpt, src)
    so = ort.SessionOptions()
    so.intra_op_num_threads = 2
    sess = ort.InferenceSession(onnx_path, so, providers=['CPUExecutionProvider'])
    inp = sess.get_inputs()[0].name

    def read_word(img):
        x = img.convert('RGB').resize((128, 32), Image.BILINEAR)  # Android createScaledBitmap
        x = ((np.asarray(x, dtype=np.float32) / 255.0) - 0.5) / 0.5
        z = sess.run(None, {inp: x.transpose(2, 0, 1)[None]})[0][0]
        z = z - z.max(-1, keepdims=True)
        p = np.exp(z) / np.exp(z).sum(-1, keepdims=True)
        out, logp = [], []
        for row in p:  # same decode + confidence as MainActivity.kt
            i = int(row.argmax())
            logp.append(np.log(row[i]))
            if i == tok.eos_id:
                break
            out.append(tok._itos[i])
        conf = float(np.exp(np.mean(logp))) * 100
        return ZERO.sub('ಂ', ''.join(out).strip()), conf

    rnd = random.Random(7)
    fonts = sorted(f for f in os.listdir(fonts_dir) if f.endswith('.ttf'))
    stats = {}
    times = {'tess': [], 'hybrid': []}
    tmp = tempfile.mkdtemp()
    no_boxes = {}
    for n in range(120):
        nlines = rnd.choice([1, 1, 2])
        lines = [' '.join(rnd.sample(WORDS, rnd.choice([1, 2, 3]))) for _ in range(nlines)]
        label = ' '.join(lines)
        font = os.path.join(fonts_dir, fonts[n % len(fonts)])
        cond = ('clean', 'photo', 'inverse')[n % 3]
        if cond == 'clean':
            img = render_phrase(lines, font, 44, (0, 0, 0), (255, 255, 255))
        elif cond == 'photo':
            img = camera(render_phrase(lines, font, 44, (60, 55, 50), (200, 195, 180)), rnd)
        else:
            img = render_phrase(lines, font, 44, (255, 255, 255), (20, 40, 120)).filter(
                ImageFilter.GaussianBlur(0.6))
        gray = stretch(img.convert('L'))
        path = os.path.join(tmp, f'{n}.png')
        gray.save(path)

        t0 = time.perf_counter()
        r = subprocess.run(['tesseract', path, 'stdout', '-l', 'kan', '--psm', '6',
                            '--tessdata-dir', tessdata], capture_output=True, text=True).stdout
        tess = clean_kannada(unicodedata.normalize('NFC', ZERO.sub('ಂ', r)))
        times['tess'].append(time.perf_counter() - t0)

        t0 = time.perf_counter()
        boxes = tesseract_tsv(path, tessdata, 6)
        no_boxes[cond] = no_boxes.get(cond, 0) + (not boxes)
        if not boxes:
            boxes = [(0, 0, gray.width, gray.height, '', -1.0)]
        words, best = [], []
        for line in group_lines(boxes):
            for (l, t, r_, b, ttxt, tconf) in line:
                h = b - t
                crop = gray.crop((max(0, l - int(h * .15)), max(0, t - int(h * .25)),
                                  min(gray.width, r_ + int(h * .15)), min(gray.height, b + int(h * .25))))
                if crop.width >= 4 and crop.height >= 6:
                    pw, pconf = read_word(crop)
                    words.append(pw)
                    tw = clean_kannada(unicodedata.normalize('NFC', ZERO.sub('\u0C82', ttxt)))
                    # Per word: keep whichever engine is more sure.
                    best.append(pw if pconf >= tconf or not tw else tw)
        hybrid = clean_kannada(unicodedata.normalize('NFC', ' '.join(w for w in words if w)))
        ensemble = clean_kannada(unicodedata.normalize('NFC', ' '.join(w for w in best if w)))
        times['hybrid'].append(time.perf_counter() - t0)

        label = unicodedata.normalize('NFC', label)
        for eng, pred in (('tess', tess), ('hybrid', hybrid), ('best', ensemble)):
            s = stats.setdefault((eng, cond), [0, 0, 0, 0, 0, 0])
            s[0] += 1
            s[1] += pred == label
            s[2] += edit_distance(pred, label)
            s[3] += len(label)
            lw, pw = label.split(), pred.split()
            s[4] += sum(1 for w in lw if w in pw)
            s[5] += len(lw)

    print('120 scan-box images, 1-2 lines, 1-3 words per line, grayscale + contrast stretch')
    print('images where Tesseract found no word boxes:', no_boxes)
    names = {'tess': 'Tesseract alone', 'hybrid': 'Hybrid (Tesseract boxes + PARSeq)',
             'best': 'Best-of-both (per word, higher confidence wins)'}
    for eng in ('tess', 'hybrid', 'best'):
        print(f'== {names[eng]}')
        tot = [0] * 6
        for cond in ('clean', 'photo', 'inverse'):
            s = stats[(eng, cond)]
            tot = [a + b for a, b in zip(tot, s)]
            print(f'  {cond:8s} whole text {s[1] / s[0]:6.1%}  words {s[4] / s[5]:6.1%}  chars {1 - s[2] / s[3]:6.1%}')
        print(f'  {"ALL":8s} whole text {tot[1] / tot[0]:6.1%}  words {tot[4] / tot[5]:6.1%}  chars {1 - tot[2] / tot[3]:6.1%}')
        ts = sorted(times['hybrid' if eng == 'best' else eng])
        print(f'  time per image: median {ts[len(ts) // 2] * 1000:.0f} ms')


if __name__ == '__main__':
    main()
