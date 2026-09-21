"""beat-sheet.py -- pick the frames of a slow-motion burst nearest to given AUTHORED times.

    python tools/studio-bridge/beat-sheet.py <frames-dir> <out.png> --speed 0.25 --times 0,0.25,0.44,... [--width 440] [--cols 4] [--crop x0,y0,x1,y1]

t = 0 is the first frame that differs from the first captured frame (the grade ramp
starting), so times line up with Config.BEATS to about one capture interval.
"""
import argparse, os, re, sys
from PIL import Image, ImageDraw, ImageStat

ap = argparse.ArgumentParser()
ap.add_argument("frames")
ap.add_argument("out")
ap.add_argument("--speed", type=float, default=0.25)
ap.add_argument("--times", type=str, required=True)
ap.add_argument("--width", type=int, default=440)
ap.add_argument("--cols", type=int, default=4)
ap.add_argument("--crop", type=str, default=None)
ap.add_argument("--lead", type=float, default=0.0, help="authored seconds to add to every time (calibration)")
a = ap.parse_args()

frames = []
for n in sorted(os.listdir(a.frames)):
    m = re.match(r"f_(\d+)_(\d+)\.(?:png|jpg)", n)
    if m:
        frames.append((int(m.group(2)), os.path.join(a.frames, n)))
def thumb(p):
    return Image.open(p).convert("L").resize((64, 36))
# t = 0: the grade darkens the whole frame within ~0.18 s authored of the egg entering, so
# the first frame whose brightness drops well below the opening frames marks the start
ref = ImageStat.Stat(thumb(frames[0][1])).mean[0]
start = None
for ms, p in frames:
    t = thumb(p)
    m = ImageStat.Stat(t).mean[0]
    if m < 2.0:
        continue
    if m < ref - 9.0:
        start = ms - int(0.10 / a.speed * 1000)
        break
if start is None:
    sys.exit("no change detected")
times = [float(x) for x in a.times.split(",")]
picks = []
for t in times:
    want = start + int((t + a.lead) / a.speed * 1000)
    best = min(frames, key=lambda f: abs(f[0] - want))
    picks.append((t, best))
crop = [int(v) for v in a.crop.split(",")] if a.crop else None
first = Image.open(picks[0][1][1])
if crop:
    first = first.crop(crop)
scale = a.width / first.width
tw, th = a.width, int(first.height * scale)
label_h = 18
rows = (len(picks) + a.cols - 1) // a.cols
sheet = Image.new("RGB", (a.cols * tw, rows * (th + label_h)), (24, 24, 24))
draw = ImageDraw.Draw(sheet)
for i, (t, (ms, path)) in enumerate(picks):
    im = Image.open(path).convert("RGB")
    if crop:
        im = im.crop(crop)
    im = im.resize((tw, th), Image.LANCZOS)
    x, y = (i % a.cols) * tw, (i // a.cols) * (th + label_h)
    sheet.paste(im, (x, y + label_h))
    draw.text((x + 4, y + 2), "t=%.2fs  (frame @%.2fs real)" % (t, ms / 1000.0), fill=(255, 255, 255))
sheet.save(a.out)
print("wrote", a.out, "start(ms)=", start)
