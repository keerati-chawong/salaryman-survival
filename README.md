# Salaryman Survival

A pixel-art office-survival RPG prototype built in Godot 4.7.

**Play in browser:** https://keerati-chawong.github.io/salaryman-survival/

## Features

- Main menu with New Start / Continue / Option / Credit, all fully wired up
- Continue is disabled until a save exists
- Turn-based combat demo (ATK / DEF / ITEM / RUN) against the Overworked Manager boss, with screen shake, hit flashes, and animated HP/MP bars
- Fully functional Options screen: resolution, window mode, brightness, volume, UI scale, toggles — all persisted to disk
- Credits screen

## Running locally

Open the project folder in Godot 4.7+ and run, or open `scenes/MainMenu.tscn` directly.

## Building the web export

```
godot --headless --export-release "Web" docs/index.html
```
