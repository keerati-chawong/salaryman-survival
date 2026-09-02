# Salaryman Survival

A pixel-art office-survival RPG prototype. Survive the office, get paid, stay alive.

**Play it now:** https://keerati-chawong.github.io/salaryman-survival/

## About

You're a first jobber grinding through the corporate ladder. Each shift you type
your way through a chaotic open office to build up Energy and Coins, then face
your manager (or HR, or the CEO) in a turn-based war of words — pick the right
kind of comeback for their weaknesses, or get worn down by theirs.

Beat every rank on the ladder — Rookie, Work-Dodger, Team Lead, HR Compliance,
and finally the CEO — to win the run.

## How to play

**Work Phase** — a top-down typing minigame. Type the target word exactly to
earn Energy and Coins; a clean, mistake-free word builds a Combo that
multiplies your payout. Dodge periodic "distraction" pop-ups with a quick
reflex key (Space/Alt/Ctrl/Enter) before they cost you Patience. Survive the
clock to head into the confrontation.

**Battle** — a turn-based fight. Spend Energy on one of four word-attack
types — Corporate Jargon, Direct Insult, Passive-Aggressive, or Logic & Facts —
each strong or weak against a given opponent, shown on the Promotion screen's
weakness chart before every fight. Use snacks and drinks from the Shop to heal,
recharge, or buff yourself mid-fight. Run out of Patience and the shift ends.

**Shop** — spend coins earned from typing and winning fights at the office
vending machine for consumables, or buy Noise-Cancelling Headphones for a
damage-reducing buff you can't get anywhere else.

### Controls

| Action | Key |
|---|---|
| Move (Work Phase) | WASD / Arrow keys |
| Dodge a distraction | Space, Alt, Ctrl, or Enter (as prompted) |
| Confirm / select | Enter, Space, or Left Click |
| Pause / menu | Esc, or the Menu button (top-right) |

## Tech

Built in [Godot 4.7](https://godotengine.org) (GDScript, GL Compatibility
renderer), exported to WebAssembly for the browser build.

## Running it locally

Open the project folder in Godot 4.7+ and press Play, or open
`scenes/MainMenu.tscn` directly and run that scene.

### Building the web export

The live build is published from `docs/` on the `master` branch:

```
godot --headless --export-release "Web" docs/index.html
```

Commit the regenerated `docs/` output after any gameplay change intended for
the live build.

## Project structure

```
scenes/     Godot scenes - one per screen (MainMenu, WorkPhase, Battle, ...)
scripts/    GDScript - per-scene logic plus shared autoload singletons
theme/      Shared UI theme resource
assets/     Sprites, backgrounds, fonts, and audio
docs/       The exported web build (served via GitHub Pages)
```

Screen flow is a simple state machine (`get_tree().change_scene_to_file`), with
run state, design data, settings, and audio shared through autoload
singletons (`GameState`, `GameData`, `Settings`, `SoundManager`).
