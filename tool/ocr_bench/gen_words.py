"""Render a synthetic Kannada word benchmark.

64 everyday words (menus, signs, places) x 4 fonts x 3 conditions:
  clean   - black on white, crisp (best case: printed menu, held steady)
  photo   - low contrast, blur, slight tilt, noise, JPEG (phone camera)
  inverse - light text on coloured board (typical shop/bus signboard)

Usage: python3 -I gen_words.py <fonts_dir> <out_dir>
Writes <out_dir>/<condition>/<font>_<idx>.png and <out_dir>/labels.tsv
"""
import io
import os
import random
import sys
import unicodedata

from PIL import Image, ImageDraw, ImageFilter, ImageFont, features

WORDS = """
ಬೆಂಗಳೂರು ಕನ್ನಡ ನಮಸ್ಕಾರ ಹೋಟೆಲ್ ಊಟ ಕಾಫಿ ಟೀ ದೋಸೆ ಇಡ್ಲಿ ವಡೆ ಉಪ್ಪಿಟ್ಟು ಮಸಾಲೆ
ಅನ್ನ ಸಾರು ಮೊಸರು ಹಾಲು ನೀರು ಬಸ್ ನಿಲ್ದಾಣ ರೈಲು ಮೆಟ್ರೋ ಆಸ್ಪತ್ರೆ ಔಷಧ ಅಂಗಡಿ
ಬ್ಯಾಂಕ್ ಶಾಲೆ ಕಾಲೇಜು ರಸ್ತೆ ಮಾರುಕಟ್ಟೆ ಪೊಲೀಸ್ ಠಾಣೆ ಪ್ರವೇಶ ನಿರ್ಗಮನ ಎಚ್ಚರಿಕೆ ನಿಷೇಧ
ಸ್ವಾಗತ ಧನ್ಯವಾದಗಳು ಬೆಲೆ ರೂಪಾಯಿ ಉಚಿತ ತೆರೆದಿದೆ ಮುಚ್ಚಲಾಗಿದೆ ಶೌಚಾಲಯ ಮಹಿಳೆಯರು
ಪುರುಷರು ವಿಮಾನ ಕರ್ನಾಟಕ ಸರ್ಕಾರ ಮೈಸೂರು ಮಂಗಳೂರು ಹುಬ್ಬಳ್ಳಿ ಜಯನಗರ ಮಲ್ಲೇಶ್ವರಂ
ಕೋರಮಂಗಲ ಸರ್ಜಾಪುರ ವೃತ್ತ ಕ್ಷಮಿಸಿ ದಯವಿಟ್ಟು ಸಿಹಿ ತಿಂಡಿ ಬಿಸಿ ಚಪಾತಿ ಹಣ್ಣು ತರಕಾರಿ
""".split()

BOARD_COLOURS = [((20, 40, 120), (255, 255, 255)), ((160, 20, 20), (255, 230, 60)),
                 ((10, 90, 40), (255, 255, 255)), ((30, 30, 30), (250, 200, 40))]


def render(word, font_path, size, fg, bg, pad):
    font = ImageFont.truetype(font_path, size, layout_engine=ImageFont.Layout.RAQM)
    box = ImageDraw.Draw(Image.new('RGB', (1, 1))).textbbox((0, 0), word, font=font, language='kn')
    w, h = box[2] - box[0], box[3] - box[1]
    img = Image.new('RGB', (w + 2 * pad, h + 2 * pad), bg)
    ImageDraw.Draw(img).text((pad - box[0], pad - box[1]), word, font=font, fill=fg, language='kn')
    return img


def camera(img, rnd):
    img = img.rotate(rnd.uniform(-3, 3), resample=Image.BICUBIC, expand=True,
                     fillcolor=img.getpixel((0, 0)))
    # Shrink like a distant word, then let OCR resize it back up.
    scale = rnd.uniform(0.45, 0.7)
    img = img.resize((max(8, int(img.width * scale)), max(8, int(img.height * scale))), Image.BILINEAR)
    img = img.filter(ImageFilter.GaussianBlur(rnd.uniform(0.5, 1.0)))
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = px[x, y]
            n = int(rnd.gauss(0, 10))
            px[x, y] = (min(255, max(0, r + n)), min(255, max(0, g + n)), min(255, max(0, b + n)))
    buf = io.BytesIO()
    img.save(buf, 'JPEG', quality=rnd.randint(35, 60))
    return Image.open(io.BytesIO(buf.getvalue())).convert('RGB')


def main():
    assert features.check('raqm'), 'Pillow needs libraqm for correct Kannada shaping'
    fonts_dir, out = sys.argv[1], sys.argv[2]
    fonts = sorted(f for f in os.listdir(fonts_dir) if f.endswith('.ttf'))
    rnd = random.Random(42)
    rows = []
    for cond in ('clean', 'photo', 'inverse'):
        os.makedirs(os.path.join(out, cond), exist_ok=True)
    for font in fonts:
        fp = os.path.join(fonts_dir, font)
        name = font[:-4]
        for i, word in enumerate(WORDS):
            word = unicodedata.normalize('NFC', word)
            imgs = {
                'clean': render(word, fp, 48, (0, 0, 0), (255, 255, 255), 10),
                'photo': camera(render(word, fp, 48, (60, 55, 50), (200, 195, 180), 10), rnd),
                'inverse': render(word, fp, 48, *reversed(BOARD_COLOURS[i % 4]), 12).filter(
                    ImageFilter.GaussianBlur(0.6)),
            }
            for cond, img in imgs.items():
                rel = f'{cond}/{name}_{i:02d}.png'
                img.save(os.path.join(out, rel))
                rows.append((rel, cond, name, word))
    with open(os.path.join(out, 'labels.tsv'), 'w', encoding='utf-8') as f:
        for r in rows:
            f.write('\t'.join(r) + '\n')
    print(f'{len(rows)} images, {len(WORDS)} words, fonts: {", ".join(f[:-4] for f in fonts)}')


if __name__ == '__main__':
    main()
