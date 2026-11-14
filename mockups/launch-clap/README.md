# Clap launch verification

The PNGs are actual simulator screenshots of the SwiftUI view on simulator 8EA3CDAB-7762-4D9B-AA2C-615968BB49C2. `impact-034.png` is frozen at 0.34 seconds and `impact-060.png` at 0.60 seconds. `rest.png` is the resting frame at zero seconds. The arm angles use fractions of the 1.2 second clap; the two impact times are absolute seconds.

For repeatable screenshots, launch a Debug build with `-LaunchClapTime 0.34`, `-LaunchClapTime 0.60`, or `-LaunchClapTime 0`. This holds the real timeline at that time and prevents automatic dismissal. Release ignores the argument. Remove it for normal playback; Settings > Debug > Replay launch animation also plays the normal animation.

Both impact screenshots were opened and inspected. The left arm rotates clockwise and the right arm counterclockwise, placing the right arm's short edge against the long diagonal face of the left arm. The second frame includes the first impact's fading ripple and particles.

The 1206 by 2622 simulator's resting glyph bounds match the 3x launch asset composited at screen centre, within one antialiasing pixel. The storyboard pins the full 1024-space mark image to 160 by 160 points at the full screen centre. The history-loading placeholder uses the same resting SwiftUI mark.

No standalone wordmark exists in the checked assets: symbol is the mark alone and LaunchLogo combines mark and wordmark. This implementation therefore ships the mark without a wordmark, as requested. The first permission prompt seen during capture was traced to startup push registration; that request now runs after splash completion so it cannot obscure the animation.
