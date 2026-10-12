"""Voxelize the darrel portrait photo.

Downsamples to a coarse grid, quantizes to a small palette, emits:
  1. darrel_preview.png â€” upscaled preview for human approval
  2. darrel_voxel.lua  â€” Luau chunk building the relief panel in Studio
     (one cube per cell, luminance-based depth for a 2.5D relief)
"""
from pathlib import Path
from PIL import Image

SRC = Path(r"C:\Users\m\Downloads\Skip rocks for brainrots\image-1785387211848.webp")
OUT = SRC.parent
GRID_W = 44            # cubes wide
CUBE = 0.2             # studs per cube
PALETTE_COLORS = 16

from PIL import ImageEnhance, ImageOps

img = Image.open(SRC).convert("RGB")
w, h = img.size
# tight face+hand crop: subject fills the middle-upper 3:4 region
target = 3 / 4
cw = int(w * 0.86)
ch = int(cw / target)
left = (w - cw) // 2
top = int(h * 0.12)
if top + ch > h:
    ch = h - top
    cw = int(ch * target)
    left = (w - cw) // 2
img = img.crop((left, top, left + cw, top + ch))

# rescue the low-light photo BEFORE quantizing: contrast stretch, lift, saturate
img = ImageOps.autocontrast(img, cutoff=1)
img = ImageEnhance.Brightness(img).enhance(1.45)
img = ImageEnhance.Contrast(img).enhance(1.15)
img = ImageEnhance.Color(img).enhance(1.35)
# warm white-balance: kill the car-interior blue cast (skin must read warm)
r_ch, g_ch, b_ch = img.split()
r_ch = r_ch.point(lambda v: min(255, int(v * 1.14)))
g_ch = g_ch.point(lambda v: min(255, int(v * 1.03)))
b_ch = b_ch.point(lambda v: int(v * 0.82))
img = Image.merge("RGB", (r_ch, g_ch, b_ch))

grid_h = int(GRID_W / target)
small = img.resize((GRID_W, grid_h), Image.LANCZOS)
quant = small.quantize(colors=PALETTE_COLORS, method=Image.MEDIANCUT).convert("RGB")

# preview at 20x
quant.resize((GRID_W * 20, grid_h * 20), Image.NEAREST).save(OUT / "darrel_preview.png")

# Luau chunk
lines = [
    "-- Darrel voxel portrait (auto-generated). Relief panel, one cube per cell.",
    'local staging = Instance.new("Model")',
    'staging.Name = "DarrelPortrait"',
    "local CUBE = %s" % CUBE,
    "local function cube(x, y, z, r, g, b)",
    "\tlocal p = Instance.new(\"Part\")",
    "\tp.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false",
    "\tp.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth",
    "\tp.Material = Enum.Material.SmoothPlastic",
    "\tp.Color = Color3.fromRGB(r, g, b)",
    "\tp.Size = Vector3.new(CUBE, CUBE, CUBE * (1 + z))",
    "\tp.CFrame = CFrame.new(x * CUBE, y * CUBE, z * CUBE * 0.5)",
    "\tp.Parent = staging",
    "end",
]
px = quant.load()
for gy in range(grid_h):
    for gx in range(GRID_W):
        r, g, b = px[gx, gy]
        lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        depth = 1 if lum > 0.45 else 0   # brighter cells pop forward (face/hand relief)
        x = gx - GRID_W // 2
        y = (grid_h - 1 - gy) - grid_h // 2
        lines.append(f"cube({x}, {y}, {depth}, {r}, {g}, {b})")
lines += [
    "staging.Parent = game.ServerStorage",
    'return "built " .. #staging:GetChildren() .. " cubes"',
]
(OUT / "darrel_voxel.lua").write_text("\n".join(lines))
print(f"grid {GRID_W}x{grid_h} = {GRID_W*grid_h} cubes; palette {PALETTE_COLORS}; preview + lua written")

