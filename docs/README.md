# Evertrail — The Ninefold Vault

A playable original mobile action-RPG prototype built on the user's existing Godot testbed. See `START_HERE.txt` for phone setup and controls.

## Included

- 640 × 360 landscape canvas, nearest-filtered sprites, Compatibility renderer.
- Dedicated lower control strip, two-finger movement/combat, focus-loss input reset.
- Animated four-direction hero; detailed original generated environment, NPC and enemy atlases; ground-depth sorting; sword trails; water animation.
- Sword, directional shield, bow, stunning boomerang, bombs, fire, ice and lantern.
- A safe village with NPC guidance and free shop replenishment; castle, cave and water branches.
- 27 vault rooms arranged as nine puzzle / key / guardian wings.
- Torch puzzles, block pressure plates, key seals, guardian seals, persistent opened chests and cleared rooms.
- Swim fins, pits with safe-position recovery, grass/bush/pot destruction, pickups and elemental interactions.
- Route map, touch equipment assignment, pause, audio toggle, new game / continue, local autosave.
- Six synthesized original music tracks and 22 sound effects inherited from the user's source build.

## Design scope and limitations

This is an original mechanics prototype, not a 1:1 reconstruction of A Link to the Past. Rooms use repeated procedural floor patterns and reusable layouts, with a linear vault route. It does not include an entire commercial-scale campaign, dual worlds, cutscenes, every reference-game interaction or exact console-era timing. Several bosses share artwork while varying behavior. NPC/enemy animation uses simple movement/bobbing; hero walking has a four-direction frame sheet and a procedural sword overlay.

The 36-room route is accessible immediately; six items are available for testing. Keys and solved seals control progression within the vault. Magic regenerates to prevent elemental resource softlocks. Device-specific comfort, framerate and Android lifecycle behavior require testing on the user's phone.

## Editing

Open `project.godot` in Godot 4.3. Main scene: `Main.tscn`. Gameplay and drawing: `scripts/Game.gd`. This revision deliberately preserves the source project's single-script architecture. Artwork prompts and provenance are in this folder. No external downloads are needed to run.

Desktop: WASD/arrows move; J/Space sword; K guard; L/I items; E talk; P/Esc equipment. Mouse can operate the visible stick and buttons.

## Save compatibility

`project.godot` sets `config/use_custom_user_dir=true` and `config/custom_user_dir_name="godot/app_userdata/Chronicle Clash Link - Ninefold Mobile"`. This keeps the save folder from before the Evertrail rename, so existing saves (`user://ccl_mobile_v1.save`) still load. Don't change these settings or the save file name, or existing saves disappear. (Godot drops comments from `project.godot` when it rewrites the file, so this note lives here.)

## Verification

Godot 4.3 imports and compiles the project. `tests/mobile_smoke.gd` checks reciprocal room links, touch equipment assignment, simultaneous move/attack, reachable east/south transitions, puzzle/key/boss seals, persistent opened chests, save/load, all room/boss updates, and the final victory flag. It uses its own separate test save.

Run: `godot --headless --path . --script res://tests/mobile_smoke.gd`

The gameplay screenshots in `screenshots/` were captured from the running Godot 4.3 Compatibility renderer, not from a mockup. Rendering was checked at 1280 × 720 with software OpenGL. No physical Android-device benchmark has been performed.
