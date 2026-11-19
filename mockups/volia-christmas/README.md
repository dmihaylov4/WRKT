# Christmas mark explorations

The original VOLIA polygons remain at their supplied coordinates in every SVG. Each hat sits on the right arm's y=285 top edge; its brim overlaps the arm by 19 logo units. All artwork uses solid fills, straight edges and 45 degree cuts, with no outlines, shadows or gradients. B also tests a circular pompom.

- A (chosen): a soft red hat tilted along the right arm, with a rounded fur brim pulled over the arm's top and a round pompom. Curved on purpose: the straight-edged version looked placed on the mark, not worn.
- B: Polar pennant folds toward the open centre of the mark, using a white cap with lime brim and a round lime pompom.
- C: Signal cap uses an upright lime crown, red brim and white cut-corner pompom for a compact, more abstract seasonal accent.

A is the strongest option: its red and white silhouette reads as Santa immediately at 60 px, while the angular fold follows the mark's construction. B is the quieter brand-only alternative, and C puts the red accent into the brim to separate the lime hat from the lime arm.

Each option includes an SVG and black-background PNG exports at 1024, 180 and 60 px. `comparison.png` shows all three options at all three native sizes inside rounded icon masks; `comparison-overview.png` is a smaller overview. The mask is a rounded icon approximation with a 22.5 percent corner radius, not an exported Apple mask. The hat bounds are inside the icon's rounded safe region; the mark is neither moved nor scaled to make room.

The first 60 px review showed C reading like a thin antenna. Its crown was widened and made upright before regenerating the final exports. A's fold was also simplified to keep its red silhouette solid at small sizes.

Regenerate with `python3 mockups/volia-christmas/render.py` (ImageMagick and Pillow). These are design artifacts only; no app icon or asset catalog is changed by this exploration.

## Plush hat icon (installed)

`plush-source.png` is the owner-supplied 1254 px AI image (black V on lime, soft 3D Santa hat on the right arm). Two candidates were made from it with `python3 mockups/volia-christmas/build_plush.py` (Pillow and numpy):

- `plush-A-as-supplied.png`: the supplied image resized to 1024 with Lanczos, nothing else changed.
- `plush-B-clean.png` (installed): the exact `VMarkShape` polygons on flat #CCFF00, with only the hat matted out of the supplied image and placed where it sits there relative to the right arm. `plush-hat-cutout.png` is that hat on a transparent 1024 canvas.

How B was made: the supplied V's edges were measured to fit a uniform scale of 1.2238, anchored on the right arm's top-right corner, between icon and source pixels. The hat matte uses a solid core (pixels far from both lime and black), the background behind each edge pixel taken from nearby clean lime or black in the source, and the hat colour pushed outward from the core; alpha is the projection of each pixel onto that background-to-hat line. The hat is then mapped into icon space (2x bicubic, Lanczos down) and composited over the vector V. The generated V's right arm is slightly wider under the hat than the real mark (its upper diagonal is steeper), so in B a little lime shows under the left end of the fur band where the source had black.

All three `AppIcon.appiconset` slots (default, dark, tinted) were pixel-identical before, so all three get the same file. The installed files are opaque RGB PNGs with an embedded sRGB profile. To swap in A, copy `plush-A-as-supplied.png` over `volia3.png`, `volia3 1.png` and `volia3 2.png`.
