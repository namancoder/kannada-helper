"""Score OCR engines on the synthetic Kannada word set.

python3 run_bench.py <engine> <data_dir> <out.tsv> [args]
  engine = torch     args: <ipo_src_dir> <kannada.ckpt>
           onnx      args: <ipo_src_dir> <kannada.ckpt> <model.onnx> [threads]
           tesseract args: <tessdata_dir>
Writes per-image predictions and prints accuracy per condition + timing.
"""
import os
import subprocess
import sys
import time
import unicodedata

from PIL import Image


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def main():
    engine, data, out = sys.argv[1:4]
    args = sys.argv[4:]
    rows = [l.rstrip('\n').split('\t') for l in open(os.path.join(data, 'labels.tsv'), encoding='utf-8')]

    if engine in ('torch', 'onnx'):
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import parseq_kn
        import numpy as np
        model, tok, _ = parseq_kn.load(args[1], args[0])
        if engine == 'torch':
            import torch
            torch.set_num_threads(4)

            def predict(img):
                x = torch.from_numpy(parseq_kn.preprocess(img))
                with torch.inference_mode():
                    logits = model(tok, x).numpy()
                return parseq_kn.decode_logits(logits, tok)
        else:
            import onnxruntime as ort
            so = ort.SessionOptions()
            so.intra_op_num_threads = int(args[3]) if len(args) > 3 else 4
            sess = ort.InferenceSession(args[2], so, providers=['CPUExecutionProvider'])
            name = sess.get_inputs()[0].name
            itype = sess.get_inputs()[0].type

            def predict(img):
                x = parseq_kn.preprocess(img)
                if 'float16' in itype:
                    x = x.astype(np.float16)
                logits = sess.run(None, {name: x})[0].astype(np.float32)
                return parseq_kn.decode_logits(logits, tok)
    elif engine == 'tesseract':
        tessdata = args[0]

        def predict(img_path):
            r = subprocess.run(['tesseract', img_path, 'stdout', '-l', 'kan', '--psm', '8',
                                '--tessdata-dir', tessdata], capture_output=True, text=True)
            return unicodedata.normalize('NFC', r.stdout.strip()), None
    else:
        raise SystemExit(f'unknown engine {engine}')

    stats = {}
    times = []
    with open(out, 'w', encoding='utf-8') as f:
        for rel, cond, font, label in rows:
            path = os.path.join(data, rel)
            t0 = time.perf_counter()
            pred, _ = predict(path if engine == 'tesseract' else Image.open(path))
            times.append(time.perf_counter() - t0)
            label = unicodedata.normalize('NFC', label)
            d = edit_distance(pred, label)
            s = stats.setdefault(cond, [0, 0, 0, 0])
            s[0] += 1
            s[1] += pred == label
            s[2] += d
            s[3] += len(label)
            f.write(f'{rel}\t{label}\t{pred}\t{d}\n')

    print(f'engine={engine} {" ".join(os.path.basename(a) for a in args[2:3])}')
    tot = [0, 0, 0, 0]
    for cond in ('clean', 'photo', 'inverse'):
        n, ok, d, L = stats[cond]
        tot = [a + b for a, b in zip(tot, stats[cond])]
        print(f'  {cond:8s} words {ok / n:6.1%}   chars {1 - d / L:6.1%}   (n={n})')
    n, ok, d, L = tot
    print(f'  {"ALL":8s} words {ok / n:6.1%}   chars {1 - d / L:6.1%}')
    times.sort()
    print(f'  time/word: median {times[len(times) // 2] * 1000:.0f} ms, p90 {times[int(len(times) * .9)] * 1000:.0f} ms')


if __name__ == '__main__':
    main()
