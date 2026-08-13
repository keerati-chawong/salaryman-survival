# Salaryman Survival

A pixel-art office-survival RPG prototype built in Godot 4.7.

**Play in browser:** https://keerati-chawong.github.io/salaryman-survival/

## Features

- **Main menu** — New Start / Continue / Option / Credit, all wired up. Continue stays disabled until a save exists.
- **Turn-based battle** — ATK / DEF / ITEM / RUN against the Overworked Manager, with animated HP/MP bars that change colour as HP drops, floating damage numbers, screen shake and hit flashes.
- **Options** — six working tabs (Display, Audio, Controls, Gameplay, Language, Others). Resolution, window mode, brightness, three volume buses, difficulty, toggles and UI scale all apply live and persist to disk.
- **Credits** — team screen with a working Back button.
- `Esc` backs out of any screen.

## Architecture notes

The screens are real Godot UI, not overlays drawn on top of the concept-art mockups:

- `scripts/Settings.gd` is an autoload singleton that owns the audio buses, the
  global brightness overlay and the theme's font scale, so an option changed in
  the menu takes effect in every scene and survives a restart.
- `theme/ui_theme.tres` styles every control type in one place.
- The Options screen is built from `MarginContainer` / `HBoxContainer` /
  `GridContainer` in code, with a `ScrollContainer` around the content pane, so
  controls cannot overlap at any window size or UI scale.
- Sprites in `assets/ui/` (sidebar tabs, battle buttons, portrait frame, title
  chip) were sliced out of the original mockups;
  `assets/backgrounds/combat_room.png` is the battle art with the painted-on HUD
  removed so the live HUD can sit in its place.

## Running locally

Open the project folder in Godot 4.7+ and press play, or open
`scenes/MainMenu.tscn` directly.

## Building the web export

```
godot --headless --export-release "Web" docs/index.html
```

GitHub Pages serves the result from the `docs/` folder on `master`.
