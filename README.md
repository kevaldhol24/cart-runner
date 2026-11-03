# Cart Runner

Downhill shopping-cart runner, built in Godot 4.5 (GL Compatibility renderer).

**Current build: game loop prototype.** Grab groceries on the road; the fuller the cart, the faster it goes and the lazier it steers. Speed bumps and hard swerves spill items. Hit a crate and the boy goes flying. Score = what's still in the cart when you crash.

## Controls
- Touch and hold left/right half of the screen to steer (keyboard: A/D or arrows)

## What to check on a phone
- Is "grab more vs keep control" fun for 5 minutes?
- Steering feel, camera, crash feel. Debug line (fps/speed/items) is bottom-left.

## Builds
Every push to `main` builds a debug APK via GitHub Actions and publishes it under **Releases** (`build-N`).

## Local test (headless)
```
xvfb-run godot --path . --rendering-driver opengl3 -- --autotest
```
Prints stats and saves screenshots to the user data folder.
