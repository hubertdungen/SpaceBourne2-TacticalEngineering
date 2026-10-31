![Tactical Engineering](docs/banner.png)

# Tactical Engineering — realistic deployable turrets for SpaceBourne 2

The turret perk stops being an instant MMO spawn and becomes real engineering. You carry one heavy
turret, kneel to set it up and to pack it up, and lose it if you leave it behind. Once it is
deployed it does the job, and the enemy treats it as a threat: they shoot back until it breaks.

Version 0.1.0 · [Nexus Mods page](https://www.nexusmods.com/spacebourne2/mods/10) · UE4SS Lua mod ·
works alone or with [Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism).

## What it does

- **Deploying takes time.** Tap **Delete**: you kneel and can't move for 6 seconds, then the
  turret stands 2 m in front of you, unfolds and opens fire. While you work, you are exposed.
- **It stays.** No 25–40 second lifetime and no self-destruct. It keeps firing until you pack it
  up, it is destroyed, or you leave it behind.
- **Packing up takes time too.** Tap **Delete** next to it: it stops firing at once, and you kneel
  for 5 seconds.
- **One turret, and it is heavy.** Packed, you carry it: you walk at 80 % speed and can't sprint.
  Damage stays with the turret.
- **Leave it behind and it is gone.** A turret still deployed when you leave the area is lost. So
  is a destroyed one. A replacement waits for you at your ship or a station, out of combat, 5
  minutes after the loss.
- **Smaller, not weaker.** It is 80 % the size of the vanilla perk turret, with the same belt-fed
  gun: 10 rounds/s at enemies within 100 m in line of sight, 3–5 s reloads between belts.
- **Limited ammo.** It carries 300 rounds. The ammo stays with it when you pack it up, and it is
  refilled from your ship: in space or on a station, out of combat, while you carry the turret.
  Empty, it stops firing.
- **It makes noise.** Setting it up or packing it up is metal work that enemies within about 15 m
  hear. A firing turret is heard about 60 m away. Unaware enemies turn to the noise.
- **It can be destroyed.** Rifle hits chip it, snipers and heavy weapons hurt, explosions wreck
  it. A destroyed turret stays as a dead wreck.
- **Enemies fight back.** Enemies hit by a turret, or near one that is firing, turn and shoot it:
  up to 3 at a time, for a few seconds, then they choose again between you and the turret.
- **Ally engineers (optional).** Squad soldiers, including the game's unused "Turretci" role, and
  companions can stop in a fight and deploy a turret of their own.
- **Off by default.** Nothing changes until you hold Delete for 2 seconds.

## Requirements

- SpaceBourne 2 (Steam).
- [UE4SS 3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1). Installing HTR
  installs it too.
- The turret perk is optional: Delete works without it. If the perk is in an action slot, its
  button deploys and packs too, which also works on a gamepad.
- Recommended: [Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism)
  0.4.2 or later; 0.4.8 or later gives the turret its own light caliber. HTR handles the
  ballistics of the turret's rounds and of the rounds fired at it.
  Tactical Engineering costs no suit energy and leaves other perks' cooldowns alone, so HTR's slower
  perk recharge applies unchanged.

## Install

1. Download `TacticalEngineering-0.1.0.zip` from the
   [releases](https://github.com/hubertdungen/SpaceBourne2-TacticalEngineering/releases).
2. Extract it into the game folder (`...\steamapps\common\SpaceBourne 2\`). It adds
   `SB2\Binaries\Win64\Mods\TacticalEngineering\`; the `enabled.txt` inside turns it on.
3. In game, on foot, **hold Delete for 2 seconds** to switch Tactical Engineering on (remembered
   between sessions).

Manual install: copy the `TacticalEngineering` folder from this repository into
`SpaceBourne 2\SB2\Binaries\Win64\Mods\`.

Uninstall: delete `SB2\Binaries\Win64\Mods\TacticalEngineering`. Tactical Engineering never writes
to your saves. It keeps its own state (on/off, your turret) in `te_state.txt` in its folder.

## Keys (on foot)

| Key | Action |
|---|---|
| **Delete** (tap) | Carrying: deploy. Next to your turret: pack it up. While working: cancel. |
| **Delete** (hold 2 s) | Tactical Engineering on / off |
| Turret perk button | Same as a Delete tap (if the turret perk is in an action slot) |
| Turret perk button, 3 quick taps | Tactical Engineering on / off (the gamepad way). While it is off, the first tap is still the vanilla perk. |

Each key press shows one short message on the HUD, without the game's "tu-tu-tu" alarm. Like HTR,
Tactical Engineering mutes that one sound for 2 seconds around its own messages. There is no
countdown, and damage to your turret is reported only at 75, 50 and 25 %.

Delete is unbound in the game. The plain key does nothing while Shift, Ctrl or Alt is held, so
**Shift+Delete** stays free for Gear Without Levels. The key can be changed in `scripts\config.lua`.

While Tactical Engineering is on, the vanilla instant turret perk is switched off: its icon shows
as cooling down. Switch Tactical Engineering off, and the vanilla perk works as before.

## Settings

Edit `Mods\TacticalEngineering\scripts\config.lua`. Every line is optional. The main ones:

- `Player`:
  - `DeploySeconds` / `PackSeconds` (6 / 5);
  - `PackRange`;
  - `CarrySpeed` (0.8) and `CarryNoSprint`;
  - `Resupply`: `"ship"`, `"level"` or `"never"`, and `ResupplyMinutes`.
- `Turret`:
  - `Scale` (0.8);
  - `Structure` (100) and `HitCost` per attacker type;
  - `DestroyedEffect`: `"wreck"`, or `"explode"` (the vanilla blast);
  - `Rounds` (300): 0 = unlimited.
- `Noise`:
  - `WorkRadius` (15 m) and `FireRadius` (60 m);
  - `AlertEnemies`.

  The noise events are also shared with other mods (for Silent Ops) through the UE4SS shared
  variable `SB2R_Noise`.
- `Enemies`:
  - whether enemies attack turrets;
  - how far a firing turret is noticed;
  - the chance per second;
  - at most how many at once, and for how long.
- `Allies`:
  - `Engineers` (off by default);
  - chances for squad soldiers and companions;
  - `MaxAllyTurrets` per level.

## Status and known limits

Tested in game on 2026-10-31, with HTR 0.4.7:
- limited ammo running out, then the refill at the ship;
- the noise of a deploy heard by an unaware enemy behind you, and of a firing turret;
- the noise shared as `SB2R_Noise`;
- the muted alarm;
- the damage notices at thresholds;
- the 3-tap toggle.

Tested in game on 2026-10-30, with HTR 0.4.5:
- on/off with the real key (hold), deploy and pack with real key taps, the perk button;
- kneeling and the movement lock, the carry slowdown and no sprint;
- the turret's lifetime, scale and placement;
- enemies killed by the turret;
- enemies turning on the turret and their rounds damaging it, down to a wreck;
- a turret left behind when the level changes;
- Shift+Delete staying quiet;
- frame times (see DESIGN.md, section 13).

Not tested yet:
- companions as engineers;
- the optional rare enemy engineers (vanilla mini-turrets);
- allies destroying an enemy mini-turret;
- the replacement after 5 minutes at a real ship or station on a planet run;
- the turret's own ballistics in HTR 0.4.8 (`turret_light`), and Silent Ops 0.2 hearing the turret.

Known limits:

- **Barricades stay vanilla for now.** The game's barricade perk (an energy-shield wall) keeps working
  as in vanilla: instant, short-lived. Turning it into real engineering (build time, carried,
  destructible) is planned for a later version.
- **No new animations.** Kneeling is the normal crouch, and the turret uses the vanilla perk's
  unfold animation. The packed turret isn't visible on your back.
- **Enemies notice it, they don't see it.** The game's enemies only "see" people. They turn on a
  turret once it shoots them or fires near them, not by spotting a silent one.
- **One short hitch per session.** The first deploy, and the first enemy that turns on a turret,
  can cost one frame of about 50 ms.
- **The state is not per save.** It is per game install: loading an older save keeps your current
  turret state.

Design notes, research and the full test log: [DESIGN.md](DESIGN.md).

## Part of the SpaceBourne 2 realism set

Separate mods that work alone or together:

| Mod | Status |
|---|---|
| **Hardcore Tactical Realism (HTR)** — realistic ballistics and tactical AI | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/4) · [Steam discussion](https://steamcommunity.com/app/1646850/discussions/0/573805072991123580) |
| **Silent Ops** — realistic stealth | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-SilentOps) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/6) |
| **Split Controls** — separate invert for ship and on foot | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-SplitControls) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/5) |
| **Gear Without Levels** — use gear regardless of level | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-GearWithoutLevels) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/7) |
| **Tactical Engineering** — deployable turrets (this mod) | released: [GitHub](https://github.com/hubertdungen/SpaceBourne2-TacticalEngineering) · [Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/10) |
| Faction Power | coming |
| Tactical First Person | coming |

## Thanks

TheCalcMan (Steam), for play-testing the realism set and for the ammo-limit idea.

## License

MIT. See [LICENSE](LICENSE).
