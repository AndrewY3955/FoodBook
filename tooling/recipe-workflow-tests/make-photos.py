"""Generates phone-sized (4032x3024) JPEG photos with real detail.

Usage: python make-photos.py <out_dir> [count]

Each photo is a blurred colour field plus noise, so the encoder produces
files of several MB like a real camera would. A raw photo is written, plus a
`-web` copy at 1600px for the API tests that bypass the app's client-side
resize and must stay under the bucket's 5 MB limit.
"""
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]
count = int(sys.argv[2]) if len(sys.argv) > 2 else 6
os.makedirs(out, exist_ok=True)

for n in range(count):
    rng = np.random.default_rng(n)
    w, h = 4032, 3024
    small = rng.integers(0, 255, (24, 32, 3), dtype=np.uint8)
    base = Image.fromarray(small).resize((w, h), Image.BICUBIC)
    draw = ImageDraw.Draw(base)
    for _ in range(60):
        x, y = random.randint(0, w), random.randint(0, h)
        r = random.randint(80, 500)
        draw.ellipse([x - r, y - r, x + r, y + r],
                     fill=tuple(random.randint(0, 255) for _ in range(3)))
    base = base.filter(ImageFilter.GaussianBlur(6))
    noise = rng.normal(0, 14, (h, w, 3))
    arr = np.clip(np.asarray(base, dtype=np.float32) + noise, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr)
    img.save(os.path.join(out, f"photo-{n}.jpg"), quality=92)
    img.resize((1600, 1200), Image.LANCZOS).save(
        os.path.join(out, f"photo-{n}-web.jpg"), quality=85)
    print(f"photo-{n}.jpg", os.path.getsize(os.path.join(out, f"photo-{n}.jpg")))
