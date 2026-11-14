# Christmas mark explorations

The original VOLIA polygons remain at their supplied coordinates in every SVG. Each hat sits on the right arm's y=285 top edge; its brim overlaps the arm by 19 logo units. All artwork uses solid fills, straight edges and 45 degree cuts, with no outlines, shadows or gradients. B also tests a circular pompom.

- A: Classic fold uses a red cap, white cut-corner brim and square pompom for the clearest Santa association at small sizes.
- B: Polar pennant folds toward the open centre of the mark, using a white cap with lime brim and a round lime pompom.
- C: Signal cap uses an upright lime crown, red brim and white cut-corner pompom for a compact, more abstract seasonal accent.

A is the strongest option: its red and white silhouette reads as Santa immediately at 60 px, while the angular fold follows the mark's construction. B is the quieter brand-only alternative, and C puts the red accent into the brim to separate the lime hat from the lime arm.

Each option includes an SVG and black-background PNG exports at 1024, 180 and 60 px. `comparison.png` shows all three options at all three native sizes inside rounded icon masks; `comparison-overview.png` is a smaller overview. The mask is a rounded icon approximation with a 22.5 percent corner radius, not an exported Apple mask. The hat bounds are inside the icon's rounded safe region; the mark is neither moved nor scaled to make room.

The first 60 px review showed C reading like a thin antenna. Its crown was widened and made upright before regenerating the final exports. A's fold was also simplified to keep its red silhouette solid at small sizes.

Regenerate with `python3 mockups/volia-christmas/render.py` (ImageMagick and Pillow). These are design artifacts only; no app icon or asset catalog is changed by this exploration.
