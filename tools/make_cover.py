#!/usr/bin/env python3
"""Turns build/shots/*.ppm into assets/screenshots/*.png (3x, nearest) and composes the 630 by 500 assets/cover.png.
Run through tools/shots.sh. Needs Pillow."""
import os
from PIL import Image, ImageDraw, ImageFont

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
shots = os.path.join(root, "build", "shots")
out = os.path.join(root, "assets", "screenshots")
names = {"title": "01-title", "play": "02-play", "crashed": "03-crashed"}
imgs = {}
for src, dst in names.items():
    im = Image.open(os.path.join(shots, src + ".ppm")).convert("RGB")
    imgs[src] = im
    im.resize((im.width * 3, im.height * 3), Image.NEAREST).save(os.path.join(out, dst + ".png"))

# cover: the play frame at 2x, a darkened band and the title set in m5x7 at 8x
play = imgs["play"].resize((640, 480), Image.NEAREST)
cover = Image.new("RGB", (630, 500), (0, 0, 0))
cover.paste(play, (-5, 20))
band = Image.new("RGB", (630, 150), (0, 0, 0))
cover.paste(band, (0, 0))
font = ImageFont.truetype(os.path.join(root, "assets", "m5x7.ttf"), 16)
mask = Image.new("L", (80, 16), 0)
ImageDraw.Draw(mask).text((0, 12), "JETLAG", font=font, fill=255, anchor="ls")
box = mask.getbbox()
mask = mask.crop(box)
scale = 14
mask = mask.resize((mask.width * scale, mask.height * scale), Image.NEAREST)
yellow = Image.new("RGB", mask.size, (255, 255, 85))
cover.paste(yellow, ((630 - mask.width) // 2, 30), mask)
cover.save(os.path.join(root, "assets", "cover.png"))
print("cover", cover.size)
