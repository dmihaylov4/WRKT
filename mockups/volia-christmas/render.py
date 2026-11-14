"""Rebuild the vector explorations and their size and mask checks.

Run: python3 mockups/volia-christmas/render.py
Requires ImageMagick and Pillow. No app assets are read or changed.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess

ROOT = Path(__file__).resolve().parent
MARK = '''<g id="volia-mark" fill="#CCFF00">
  <polygon points="132,290 290,290 582,582 582,742 438,742 132,438"/>
  <polygon points="735,285 890,285 890,437 735,592 582,592 582,437"/>
</g>'''
BRIM = '720,264 736,248 888,248 904,264 904,288 888,304 736,304 720,288'
OPTIONS = {
    'A-classic': ('Classic fold', '''<g id="santa-hat">
  <polygon fill="#F2384E" points="728,272 728,224 824,128 856,128 920,192 920,240 888,240 872,224 872,272"/>
  <polygon fill="#FFFFFF" points="''' + BRIM + '''"/>
  <polygon fill="#FFFFFF" points="896,216 928,216 944,232 944,264 928,280 896,280 880,264 880,232"/>
</g>'''),
    'B-brand': ('Polar pennant', '''<g id="santa-hat">
  <polygon fill="#FFFFFF" points="744,272 744,224 680,160 680,128 744,128 888,272"/>
  <polygon fill="#FFFFFF" points="680,128 632,176 632,224 664,224 744,144 744,128"/>
  <polygon fill="#CCFF00" points="''' + BRIM + '''"/>
  <circle fill="#CCFF00" cx="648" cy="232" r="32"/>
</g>'''),
    'C-signal-cap': ('Signal cap', '''<g id="santa-hat">
  <polygon fill="#CCFF00" points="728,272 728,240 808,160 840,160 888,208 888,272"/>
  <polygon fill="#F2384E" points="''' + BRIM + '''"/>
  <polygon fill="#FFFFFF" points="800,120 832,120 848,136 848,168 832,184 800,184 784,168 784,136"/>
</g>'''),
}

def svg(body):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n<rect width="1024" height="1024" fill="#000000"/>\n' + MARK + '\n' + body + '\n</svg>\n'

for key, (title, body) in OPTIONS.items():
    source = ROOT / f'{key}.svg'
    source.write_text(svg(body))
    for size in (1024, 180, 60):
        subprocess.run(['magick', '-background', 'black', str(source), '-resize', f'{size}x{size}', str(ROOT / f'{key}-{size}.png')], check=True)

# Each row displays the exported PNG at its actual pixel size, under a rounded icon mask.
# The large sheet intentionally keeps the 1024 row at full size for inspection.
font_path = '/System/Library/Fonts/Helvetica.ttc'
font = ImageFont.truetype(font_path, 28)
small = ImageFont.truetype(font_path, 22)
sheet = Image.new('RGB', (3304, 1660), '#181A1D')
draw = ImageDraw.Draw(sheet)
for column, (key, (title, _)) in enumerate(OPTIONS.items()):
    x = 64 + column * 1080
    draw.text((x, 28), f'{key[0]}: {title}', fill='white', font=font)
    for size, y in ((1024, 86), (180, 1190), (60, 1480)):
        icon = Image.open(ROOT / f'{key}-{size}.png').convert('RGB')
        # Supersampling keeps the 60 px mask smooth. Artwork remains native size.
        mask = Image.new('L', (size * 4, size * 4))
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=size * 4 * 0.225, fill=255)
        mask = mask.resize((size, size), Image.Resampling.LANCZOS)
        sheet.paste(icon, (x + (1024 - size) // 2, y), mask)
        draw.text((x + (1024 - size) // 2, y + size + 15), f'{size} px', fill='#A4A7AB', font=small)
sheet.save(ROOT / 'comparison.png')
# A compact overview for review; use comparison.png for the native 60 px checks.
sheet.resize((1322, 664), Image.Resampling.LANCZOS).save(ROOT / 'comparison-overview.png')
