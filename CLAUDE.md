# Lost on Armageddon — handoff notes

Dark, rainy Gotham-style 3D story game. City: **Oxwag City** (Qumvia Land). Hero: **Vaynara**.
Engine: **Godot 4.7.2**, renderer **gl_compatibility** (must stay; target GPU is old).

## Target machine (the owner's PC — every change must run well here)
- CPU Core 2 Quad Q9500 (no SSE4.2 → only the **32-bit** Windows export runs), GPU GeForce GT 740, Windows 10, 1600x900.
- Goal: **medium preset ≥ 60 FPS**. Never lower visual quality to get speed; find cheaper ways to draw the same thing.
- Use `PERFORMANS_TESTI.bat` (runs `LostOnArmageddon_32bit.exe -- --benchmark`) → writes `benchmark_report.txt` next to the exe.

## Language / people
- UI and dialogue are Turkish first (`data/` strings via `scripts/loc.gd`), plus English and German.
- The owner speaks Turkish; progress reports to them are in Turkish.

## Layout
- `scripts/` game code (autoloads: Settings, Loc, Game). `scripts/main.gd` boots menu → city → game.
- `scripts/world/city.gd` loads `data/layout.json` (chunks, props, lamps, colliders, vehicles…).
- `assets/models/**.scn` native Godot scenes (city chunks, vehicles, characters, props, animation libraries).
- `shaders/` all materials are custom shaders; global shader uniforms are in `project.godot`.
- `scripts/dev/shot_driver.gd` — headless test driver. Run with
  `OXWAG_SHOT=cmds.json OXWAG_SHOT_DIR=out xvfb-run -a godot --rendering-driver opengl3 --resolution 1600x900`
  (commands: wait, start, place, look, cam/at, hour, weather, press/release, eval, shot, quit).

## History note
The original generator scripts (Python/Blender) were lost with a container reset in Nov 2026; the project was
recovered from the v0.2.3 executable (scripts decompiled — comments were lost, assets converted back to source
formats). New geometry is built with Blender (`pip install bpy`) or Godot tool scripts kept under `tools/`.

## Rules
- Only CC0 / OFL / free assets (CC-BY allowed with credit in the credits screen).
- Release builds: 64-bit + 32-bit exe, zipped in parts with `KURULUM.bat`, version folder on the owner's desktop.
