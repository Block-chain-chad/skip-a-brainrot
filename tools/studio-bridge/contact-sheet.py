"""contact-sheet.py -- tile burst-capture frames into one labelled PNG.

    python tools/studio-bridge/contact-sheet.py <frames-dir> <out.png> [--cols 4] [--width 450] [--every 1] [--start 0] [--end N]

Each tile is labelled with the frame index and its ms-since-burst-start (parsed from the
f_<idx>_<ms>.png name), so a sheet reads as a timeline.
"""
import argparse, os, re, sys
from PIL import Image, ImageDraw

ap = argparse.ArgumentParser()
ap.add_argument("frames")
ap.add_argument("out")
ap.add_argument("--cols", type=int, default=4)
ap.add_argument("--width", type=int, default=450)
ap.add_argument("--every", type=int, default=1)
ap.add_argument("--start", type=int, default=0)
ap.add_argument("--end", type=int, default=10**9)
a = ap.parse_args()

names = sorted(n for n in os.listdir(a.frames) if n.endswith(".png") or n.endswith(".jpg"))
pick = []
for n in names:
    m = re.match(r"f_(\d+)_(\d+)\.(?:png|jpg)", n)
    if not m:
        continue
    idx, ms = int(m.group(1)), int(m.group(2))
    if idx < a.start or idx > a.end or (idx - a.start) % a.every:
        continue
    pick.append((idx, ms, n))
if not pick:
    sys.exit("no frames")

first = Image.open(os.path.join(a.frames, pick[0][2]))
scale = a.width / first.width
tw, th = a.width, int(first.height * scale)
label_h = 18
cols = a.cols
rows = (len(pick) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + label_h)), (24, 24, 24))
draw = ImageDraw.Draw(sheet)
for i, (idx, ms, n) in enumerate(pick):
    im = Image.open(os.path.join(a.frames, n)).convert("RGB").resize((tw, th), Image.LANCZOS)
    x, y = (i % cols) * tw, (i // cols) * (th + label_h)
    sheet.paste(im, (x, y + label_h))
    draw.text((x + 4, y + 2), "#%d  %.2fs" % (idx, ms / 1000.0), fill=(255, 255, 255))
sheet.save(a.out)
print("wrote", a.out, sheet.size, "tiles", len(pick))
