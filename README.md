# Cart Runner

Downhill shopping-cart runner, built in Godot 4.5 (GL Compatibility renderer).

**Current build: performance stress test.** Endless downhill road, a cart full of physics groceries, crates to crash into, speed bumps that spill items.

## Controls
- Touch and hold left/right half of the screen to steer (keyboard: A/D or arrows)
- Buttons: toggle shadows, +10 items (stress physics), restart

## What to check on a phone
- FPS shown top-left (current + minimum). Note it with shadows ON and OFF, and with 30 / 60 items.
- Does it load at all on low-end devices?

## Builds
Every push to `main` builds a debug APK via GitHub Actions and publishes it under **Releases** (`build-N`).

## Local test (headless)
```
xvfb-run godot --path . --rendering-driver opengl3 -- --autotest
```
Prints stats and saves screenshots to the user data folder.
