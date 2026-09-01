# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Salaryman Survival — a pixel-art office-survival RPG prototype built in Godot 4.7 (GDScript, GL Compatibility renderer). Live web build: https://keerati-chawong.github.io/salaryman-survival/

## Running and building

There is no separate test suite or linter — this is a Godot project, verified by running it in the editor.

- **Run locally**: open the project folder in Godot 4.7+ and press play, or open `scenes/MainMenu.tscn` directly and run that scene.
- **Build the web export** (publishes to GitHub Pages from `docs/` on `master`):
  ```
  godot --headless --export-release "Web" docs/index.html
  ```
  The exported files (`docs/index.html`, `.wasm`, `.pck`, `.js`, worklets) are committed to the repo — after any gameplay change intended for the live build, re-run the export and commit the regenerated `docs/` output.

## Architecture

### Scene flow (state machine, not a tree of persistent nodes)

Each screen is its own scene, and navigation is `get_tree().change_scene_to_file(...)` — there is no scene stays resident. Shared state lives in autoload singletons instead:

```
MainMenu → WorkPhase → Battle → Promotion → (WorkPhase again, or MainMenu on win/loss)
        → OptionsMenu / CreditsMenu (dead-end, Back/Esc returns to MainMenu)
```

- **WorkPhase** (`scripts/WorkPhase.gd`, `scenes/WorkPhase.tscn`): top-down minigame. Move with WASD/arrows, dodge flying insults, collect documents toward a quota, and hit QTE prompts — all of it trades Patience for Anger before the fight. Reaching quota transitions to Battle; running out of Patience (`_burn_out`) ends the run.
- **Battle** (`scripts/Battle.gd`, `scenes/Battle.tscn`): turn-based confrontation. Player spends Anger on one of four "word type" attacks (see below) or an item; the enemy replies with a plain attack or its one signature skill (~40% chance per turn). Winning calls `GameState.advance_stage()` and goes to Promotion; losing deletes the save and returns to MainMenu.
- **Promotion** (`scripts/Promotion.gd`, `scenes/Promotion.tscn`): recap screen between fights showing the next enemy's weakness/resistance chart, or the win screen after the final boss.
- **MainMenu / OptionsMenu / CreditsMenu**: standard menu screens, built from real Godot `Control` nodes (not overlays on the concept-art mockups).

### Autoload singletons (`project.godot` `[autoload]`, load order matters: Settings → GameData → GameState → SoundManager)

- **`scripts/Settings.gd`** — persisted user preferences (resolution, window mode, brightness, volumes, screen shake, UI scale, difficulty, etc). Owns the audio buses, a global brightness tint overlay (`CanvasLayer` layer 128), and the shared theme's font sizes, so a change in Options takes effect everywhere immediately and survives restart. Saved to `user://settings.cfg`. Note `is_window_locked()` — web export can't resize/fullscreen its own window, so `apply_window()` is skipped there.
- **`scripts/GameData.gd`** — static design data only, no mutable state: the four `WORDS` (attack types with cost/power/color/flavor lines), the `ENEMIES` ladder (each with an HP pool, damage range, one signature `skill` id resolved inside `Battle.gd`, and a `mult` weakness/resistance table keyed by word id), and the three `ITEMS`. Damage multiplier bands: `0.0` = immune, `<1.0` = resisted, `1.0` = neutral, `>1.0` = weakness, `>=2.0` = critical.
- **`scripts/GameState.gd`** — the mutable run: `stage_index`, `patience` (HP), `anger` (MP/resource spent on attacks), `rank`, `inventory`. Also registers the WASD/arrow movement `InputMap` actions at runtime (`_ready`) rather than editing them into `project.godot`. Persisted to `user://save.dat` as JSON via `save_game()`/`load_game()`; `has_save()` gates the MainMenu's Continue button. `advance_stage()` is the win-flow hook: promotes rank, restocks a little inventory, and carries over half of current Anger (`ANGER_CARRY`) into the next fight.
- **`scripts/SoundManager.gd`** — audio hub: one `AudioStreamPlayer` for music (crossfades between tracks via `play_music()`, ducks under `duck_music()`/`unduck_music()`/`duck_music_briefly()` — reference-counted so overlapping duck requests don't stomp each other's restore) plus a round-robin pool of `AudioStreamPlayer`s for one-shot `play_sfx()` calls, all routed through Settings' "Music"/"SFX" buses. Assets live under `assets/audio/{music,sfx/...}`; each `SFX` dictionary key maps to an `Array[AudioStream]` so repeated cues (UI clicks, enemy voice barks) pick a random take via `play_sfx()`/`play_enemy_voice(enemy_id)`. `play_lose()` is the one deliberately jarring exception — it cuts the music and every other SFX so only a single random "lose" line plays.

### Conventions worth knowing before editing gameplay

- Enemy skills are a simple `match` on a string id (`pile_on`, `interrupt`, `silence`, `gaslight`) inside `Battle.gd`'s `_try_skill()` — adding an enemy skill means adding both the id/effect pair in `GameData.ENEMIES` and a case in that `match`.
- UI feedback (damage popups, screen shake, hit flashes) all check `Settings.show_damage` / `Settings.screen_shake` before playing, and difficulty (`Settings.difficulty`, 0-2) scales enemy damage in `Battle._enemy_turn()`.
- Tweens on dynamically spawned nodes (e.g. `WorkPhase._spawn_document`'s bob animation) are bound to that node via `node.create_tween()`, not `self.create_tween()` — this lets Godot auto-kill the tween when the node is freed instead of erroring on a dangling reference (an "Infinite loop" tween error the Web export handles badly).
- `theme/ui_theme.tres` is the single theme resource for every control; `Settings.apply_ui_scale()` mutates its font sizes at runtime rather than scenes overriding fonts individually.
