"""Build the two plush-hat app icon candidates from plush-source.png.

Run: python3 mockups/volia-christmas/build_plush.py
Requires Pillow and numpy. Writes into this folder only:

- plush-A-as-supplied.png: the supplied image resized to 1024 with Lanczos.
- plush-B-clean.png: the exact VMarkShape polygons on flat #CCFF00, with
  the hat matted out of the supplied image and placed at the same spot
  relative to the right arm.
- plush-hat-cutout.png: the matted hat on a transparent 1024 canvas, for
  inspection and re-use.

Both icons are written opaque RGB with an embedded sRGB profile.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'plush-source.png'
SIZE = 1024
LIME = (204, 255, 0)  # #CCFF00

# VMarkShape.leftArm / rightArm from DesignSystem/Cut/CutShapes.swift (1024 square).
LEFT_ARM = [(132, 290), (290, 290), (582, 582), (582, 742), (438, 742), (132, 438)]
RIGHT_ARM = [(735, 285), (890, 285), (890, 437), (735, 592), (582, 592), (582, 437)]

# Source px = icon px * scale + offset, fitted on the visible V edges of the
# supplied image (left 162.55, centre 714.4, right 1092.35, top 355.5,
# right-arm bottom 724.6, left-arm bottom 907.15). The generated V is very
# slightly anisotropic (x 1.227, y 1.221); a single uniform scale anchored on
# the right arm's top-right corner keeps the hat undistorted and within half a
# pixel of the arm edges it touches.
SCALE = 1.2238
ANCHOR_ICON = (890.0, 285.0)
ANCHOR_SRC = (1092.35, 349.9)
OFFSET = (ANCHOR_SRC[0] - ANCHOR_ICON[0] * SCALE, ANCHOR_SRC[1] - ANCHOR_ICON[1] * SCALE)

# Region of the source that contains the hat (source px).
HAT_BOX = (780, 140, 1240, 470)


def srgb_profile():
    return ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()


def save_icon(img, path):
    img.convert('RGB').save(path, icc_profile=srgb_profile(), optimize=True)


def v_mask(size, scale=1.0, offset=(0.0, 0.0), ss=4):
    """Anti-aliased coverage of the exact V, mapped by scale and offset."""
    big = Image.new('L', (size * ss, size * ss), 0)
    d = ImageDraw.Draw(big)
    for arm in (LEFT_ARM, RIGHT_ARM):
        d.polygon([((x * scale + offset[0]) * ss, (y * scale + offset[1]) * ss) for x, y in arm], fill=255)
    return np.asarray(big.resize((size, size), Image.Resampling.BOX)).astype(float) / 255.0


def blur(x, radius):
    """Approximate Gaussian: three separable box blurs (Pillow cannot blur float images)."""
    k = 2 * radius + 1
    for _ in range(3):
        for axis in (0, 1):
            p = np.pad(x, [(radius, radius) if i == axis else (0, 0) for i in range(2)], mode='edge')
            c = np.cumsum(p, axis=axis)
            c = np.concatenate([np.zeros_like(np.take(c, [0], axis=axis)), c], axis=axis)
            x = (np.take(c, range(k, c.shape[axis]), axis=axis) - np.take(c, range(0, c.shape[axis] - k), axis=axis)) / k
    return x


def fill_from(a, known):
    """Keep colours where known; elsewhere use a normalised blur of nearby known colours."""
    fg = a * known[..., None]
    wgt = known.astype(float)
    out, done = a.copy(), known.copy()
    for radius in (1, 2, 4, 8, 16):
        bf = np.stack([blur(fg[..., c], radius) for c in range(3)], axis=2)
        bw = blur(wgt, radius)
        take = ~done & (bw > 1e-3)
        out[take] = bf[take] / bw[take][:, None]
        done |= take
    return out


def candidate_a(src):
    return src.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def matte_hat(src):
    """Return (alpha, foreground) float arrays in source space."""
    a = np.asarray(src).astype(float)
    h, w, _ = a.shape
    lime_src = np.median(a[30:300, 30:300].reshape(-1, 3), axis=0)
    roi = np.zeros((h, w), bool)
    x0, y0, x1, y1 = HAT_BOX
    roi[y0:y1, x0:x1] = True

    # The generated V does not follow the exact geometry under the hat (its
    # right arm's upper diagonal is steeper and up to 15 px wider), so the
    # background behind each fringe pixel is taken from the source itself:
    # pixels that are clearly lime or clearly black, pushed outward.
    d_lime = np.linalg.norm(a - lime_src, axis=2)
    d_black = np.linalg.norm(a, axis=2)
    known_bg = (d_lime < 25) | (d_black < 25)
    bg = fill_from(a, known_bg)

    dist = np.minimum(d_lime, d_black)
    core = roi & (dist > 70)
    # Keep only the hat: drop specks, then erode so the core is all solid hat.
    core_img = Image.fromarray((core * 255).astype(np.uint8))
    core_img = core_img.filter(ImageFilter.MinFilter(5))
    core = np.asarray(core_img) > 0
    near = np.asarray(core_img.filter(ImageFilter.MaxFilter(13))) > 0  # within 6 px of the core

    # Foreground colour estimate: push the core colours outward with a
    # normalised blur so each fringe pixel gets the colour of the hat next to it.
    F = fill_from(a, core)

    # Alpha: project the observed colour onto the background-to-foreground line.
    d = F - bg
    alpha = ((a - bg) * d).sum(2) / np.maximum((d * d).sum(2), 1.0)
    alpha = np.clip(alpha, 0, 1)
    alpha[core] = 1.0
    alpha[~near] = 0.0
    alpha[~roi] = 0.0
    alpha[alpha < 0.04] = 0.0
    alpha[alpha > 0.97] = 1.0
    return alpha, F


def hat_layer(src):
    """Matted hat transformed into the 1024 icon space, premultiplied floats."""
    alpha, F = matte_hat(src)
    h, w = alpha.shape
    rgba = np.dstack([np.clip(F, 0, 255), alpha * 255]).astype(np.uint8)
    layer = Image.fromarray(rgba, 'RGBA').convert('RGBa')
    # icon = (src - offset) / scale. Render at 2x then Lanczos down for quality.
    ss = 2
    inv = (SCALE / ss, 0, OFFSET[0], 0, SCALE / ss, OFFSET[1])
    big = layer.transform((SIZE * ss, SIZE * ss), Image.Transform.AFFINE, inv, Image.Resampling.BICUBIC)
    small = big.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return small.convert('RGBA'), alpha


def candidate_b(src):
    hat, alpha_src = hat_layer(src)
    cover = v_mask(SIZE)
    base = (1 - cover)[..., None] * np.array(LIME, float)[None, None, :]
    h = np.asarray(hat).astype(float)
    ha = h[..., 3:4] / 255.0
    out = h[..., :3] * ha + base * (1 - ha)
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), 'RGB'), hat, alpha_src


def main():
    src = Image.open(SOURCE).convert('RGB')
    save_icon(candidate_a(src), ROOT / 'plush-A-as-supplied.png')
    b, hat, alpha_src = candidate_b(src)
    save_icon(b, ROOT / 'plush-B-clean.png')
    hat.save(ROOT / 'plush-hat-cutout.png')
    # Report how much exact-V black is left uncovered where the source shows hat
    # or lime, which would be a visible mismatch around the hat.
    print('matte: solid px', int((alpha_src == 1).sum()), 'partial px', int(((alpha_src > 0) & (alpha_src < 1)).sum()))


if __name__ == '__main__':
    main()
