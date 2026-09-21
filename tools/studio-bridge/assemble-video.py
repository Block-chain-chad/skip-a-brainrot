"""assemble-video.py -- turn a burst-capture folder into a real-time MP4.

    python tools/studio-bridge/assemble-video.py <frames-dir> <out.mp4> --speed 0.25 [--start-ms 0] [--end-ms N] [--width 1100] [--fps 60]

The run was recorded in slow motion (`--speed` is the hatch's speed multiplier), so each
frame's real duration is divided by 1/speed to bring the clip back to real time; capture
jitter is preserved as per-frame durations through ffmpeg's concat demuxer. The output
is resampled to a constant frame rate for players that dislike VFR.
"""
import argparse, os, re, subprocess, sys, tempfile

ap = argparse.ArgumentParser()
ap.add_argument("frames")
ap.add_argument("out")
ap.add_argument("--speed", type=float, default=0.25)
ap.add_argument("--start-ms", type=int, default=0)
ap.add_argument("--end-ms", type=int, default=10**9)
ap.add_argument("--width", type=int, default=1100)
ap.add_argument("--fps", type=int, default=60)
ap.add_argument("--tail", type=float, default=0.4, help="seconds of real time to hold the last frame")
ap.add_argument("--no-auto-trim", dest="auto_trim", action="store_false")
a = ap.parse_args()

from PIL import Image, ImageStat

frames = []
for n in sorted(os.listdir(a.frames)):
    m = re.match(r"f_(\d+)_(\d+)\.(?:png|jpg)", n)
    if m:
        ms = int(m.group(2))
        if a.start_ms <= ms <= a.end_ms:
            frames.append((ms, os.path.join(a.frames, n)))
if len(frames) < 2:
    sys.exit("not enough frames")

# drop black frames (PrintWindow occasionally returns an empty surface) and auto-trim to
# the stretch where the picture actually changes against the first frame
def thumb(path):
    return Image.open(path).convert("L").resize((64, 36))
ref = ImageStat.Stat(thumb(frames[0][1])).mean[0]
keep, changed = [], []
for ms, path in frames:
    t = thumb(path)
    m = ImageStat.Stat(t).mean[0]
    if m < 2.0:
        continue
    keep.append((ms, path))
    changed.append(m < ref - 9.0)   # the grade darkens the frame for the whole run
if a.auto_trim and any(changed):
    first = changed.index(True)
    last = len(changed) - 1 - changed[::-1].index(True)
    lead = int(0.35 / a.speed * 1000)   # real ms of lead-in before the first change
    t0 = keep[first][0] - lead
    t1 = keep[last][0] + int(0.25 / a.speed * 1000)
    keep = [f for f in keep if t0 <= f[0] <= t1]
frames = keep
if len(frames) < 2:
    sys.exit("not enough frames after trim")

lst = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8")
for i, (ms, path) in enumerate(frames):
    nxt = frames[i + 1][0] if i + 1 < len(frames) else ms + int(a.tail * 1000 / a.speed)
    dur = max(1, nxt - ms) / 1000.0 * a.speed
    lst.write("file '%s'\nduration %.4f\n" % (path.replace("\\", "/"), dur))
# concat demuxer needs the last file repeated to honour its duration
lst.write("file '%s'\n" % frames[-1][1].replace("\\", "/"))
lst.close()

cmd = [
    "ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst.name,
    "-vf", "scale=%d:-2:flags=lanczos,pad=ceil(iw/2)*2:ceil(ih/2)*2,fps=%d" % (a.width - (a.width % 2), a.fps),
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "19", "-preset", "medium", "-movflags", "+faststart",
    a.out,
]
subprocess.check_call(cmd)
os.unlink(lst.name)
total = (frames[-1][0] - frames[0][0]) / 1000.0 * a.speed + a.tail
print("wrote %s: %d frames, %.2fs real time (captured %.1fs at speed %.2f)" % (a.out, len(frames), total, (frames[-1][0] - frames[0][0]) / 1000.0, a.speed))
