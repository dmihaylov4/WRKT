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
    # Chosen direction: a soft hat tilted along the arm, fur brim pulled over the arm's top.
    'A-classic': ('Classic, worn at a tilt', '''<g id="santa-hat">
<path fill="#F2384E" d="M738.2,268.0 C756.8,193.3 818.6,123.2 893.8,127.5 C948.6,130.8 975.8,178.8 964.7,248.2 L932.2,246.3 C935.1,218.2 927.3,199.7 905.0,198.3 C908.9,232.2 905.1,272.5 896.3,307.4 Z"/><path fill="#C92A3F" d="M905.0,198.3 C927.3,199.7 935.1,218.2 932.2,246.3 L964.7,248.2 C969.5,216.4 966.1,188.8 954.0,167.2 C935.1,168.7 918.1,178.9 905.0,198.3 Z"/>
<polygon fill="#FFFFFF" points="754.7,239.1 748.0,238.3 741.3,238.9 734.9,241.0 729.2,244.4 724.3,249.1 720.6,254.7 718.3,261.0 717.4,267.6 718.0,274.3 720.1,280.7 723.6,286.5 728.2,291.3 733.9,295.0 740.2,297.4 883.8,333.2 890.4,334.0 897.1,333.4 903.5,331.3 909.2,327.9 914.1,323.2 917.8,317.6 920.1,311.3 921.0,304.6 920.4,298.0 918.3,291.6 914.8,285.8 910.2,281.0 904.6,277.3 898.3,274.9"/>
<circle fill="#FFFFFF" cx="945.3" cy="268.1" r="29.0"/>
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
