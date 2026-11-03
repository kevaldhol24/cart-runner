# Cart Runner — handoff notes for Claude

Read this first. It's the state of the project and how we work, written at the end of the first build session (2026-11-03).

## Who / how we work
- Owner: Keval (developer, India). He playtests on his phone and gives blunt, specific feedback; Claude does nearly all building, testing and design.
- Keep replies concise and direct. Push back with reasons when something won't work; give honest expectations, not optimistic ones.
- Every build Keval tests is an APK from GitHub Releases. He judges feel and looks; Claude judges bugs via headless runs + screenshots.

## The game
3D downhill shopping-cart runner (Subway Surfers-like), portrait, Android, Godot 4.5.1, GL Compatibility renderer.
- Core loop (tested, Keval likes it): drive through groceries on the road → they drop into the cart as physics objects. Fuller cart = faster + lazier steering. Bumps/hard swerves spill items. Hit an obstacle = crash. Score = items still in the cart at the crash. Best score saved in `user://save.cfg`.
- Controls: hold left/right half of screen to steer (A/D or arrows on desktop).
- Look test (build-4): Indian market street (procedural shophouses, awnings, shop signs atlas, bunting, wires), curved-world toon shader, CC0 Quaternius models (boy, cow, fruit, taxi, streetlight), procedural auto-rickshaw / fruit cart / shopping cart, CPU particles, crash slow-mo + shake.

## Feedback history (what was fixed and why)
- Full-width speed bumps were unfair (spilled everything, couldn't dodge) → now lane-sized bumps, always a gap; lower so a hit costs a few items.
- Cart drifted sideways after steering → yaw lock toward downhill with a small steer lean.
- Scraping the curb counted as a crash → soft road edge pushes the cart back.
- Flat cart bottom caught road-chunk seams → sphere wheel colliders + overlapping road boxes.
- Crash was "good, not super cool" → slow-mo, shake, boy launched forward over the cart, bigger burst.
- Performance: Oppo Reno-class phone held 60 fps up to 90 physics items with shadows (stress test). Look-test build is heavier (~13k tris per 30 m chunk, 8 chunks) — FPS on phone still unverified.
- **Keval was NOT happy with the build-4 look.** It reads as programmer art: flat boxes, no textures, noisy/busy, generic small adult character not holding the cart, primitive procedural props clashing with real models, default-font UI.

## Open decisions (ask Keval before big work)
1. **Art source.** Options:
   - Synty POLYGON City Pack ($19.99, one-time, perpetual, any engine, ships a Godot 4.5.1 project, 5 seats). Licence forbids sharing source files outside the team (→ repo must go private first) and has generative-AI clauses (no AI model generation / datasets). Keval was advised to email Synty to confirm an AI coding assistant may import/arrange/recolor assets. Avoid modifying Synty geometry in Blender.
   - Free CC0: Kenney City Kit (Commercial, Roads, Suburban) + Car Kit + Quaternius animated characters. Simpler/toy-like but no licence issues.
   - Plan was: build the same test scene in both styles and compare.
2. **Which game.** Keval liked the Synty city look and asked about a different game with it. Options discussed: parking-jam/traffic puzzle (most commercially reliable, no animation needed), delivery-rider rush (Indian theme, most distinctive), cart runner city version (keeps all work), idle shop tycoon. Not decided.
3. **Animation.** Synty characters ship without animations. Plan: Godot humanoid retargeting of CC0 Quaternius animations; Mixamo (download on their own rig, don't upload Synty models) for more variety.
4. **Motivation/meta (agreed direction, not built):** checkout lanes to bank the cart (fixes "all work lost"), mom's grocery list, fragile items (eggs), streak multiplier, coins + cart upgrades, daily missions, rewarded-ad revive. Build order suggested: checkouts + list → coins + upgrades → rewarded revive → missions/locations.

## Repo layout
- `main.gd` — whole game: street variants (pre-baked merged meshes, one draw call each), chunk recycling, obstacles, pickups, cart physics, crash, HUD, test bot.
- `art.gd` — `Art` class: curved-world toon shader (global shader params `curve_origin`, `curve_amount` in project.godot), merged-mesh builder `Art.MB`, model loader `Art.model(path, size, axis, recolor)`, procedural auto/thela/cart, shop-sign atlas.
- `assets/` — CC0 Quaternius models converted to .glb (see CREDITS.md).
- `tools/blend2glb.py` — Blender (bpy) script: opens an old .blend, rebuilds legacy materials as Principled BSDF (keeps textures/colors), exports .glb. Old Quaternius FBX imports lose colors — convert from .blend instead.
- `tools/preview.tscn` — renders all assets in a grid to `user://preview.png`.
- `.github/workflows/android.yml` — on push to main: installs Godot 4.5.1 + export templates, makes a debug keystore, exports `build/cart-runner.apk`, publishes a GitHub Release `build-N` (Keval downloads from there on his phone). Bump `version/code` in `export_presets.cfg` each build.

## How to test headless
```
xvfb-run -a -s "-screen 0 600x1000x24" godot --path . --rendering-driver opengl3 --resolution 540x960 -- --autotest
```
- `--autotest` starts immediately, drives a bot (chases pickups, dodges obstacles/bumps), prints stats, saves `user://shot_60.png`, `shot_150.png`, `shot_300.png`, `shot_crash.png` (Linux: `~/.local/share/godot/app_userdata/Cart Runner/`), then quits.
- `-- --autotest --hitbumps` makes the bot hit every bump (to measure spill severity).
- Always look at the screenshots; several bugs were only visible there. FPS in headless software rendering is meaningless.
- Blender: `pip install bpy` (needs Python 3.13 for bpy 5.2) in a venv; run scripts with `python -I`.

## Next step when resuming
Ask Keval which art route he chose (Synty bought? Kenney downloaded?) and which game direction, then do a side-by-side look test before building features.
