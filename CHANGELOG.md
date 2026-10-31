# Changelog

## 0.2.0 — 2026-10-31

Ideas by hubertdungen (the author): perk levels that matter, barricades as field engineering,
only the game's own perk buttons, the perks required, enemies searching for the noise, and a smaller
turret.

- **Barricades.** The barricade perk's energy-shield wall is no longer instant and short-lived.
  Press the barricade perk button: you kneel for 4 s, and the wall stays until you pack it up
  (3 s, next to it) or leave the area. You carry 1, plus 1 per perk level above 1, restocked at
  your ship or a station out of combat. It stops enemy rounds, which wear it down until it
  collapses; packed, it recharges. Building is noisy, and the noise is shared with Silent Ops.
  Without the barricade perk there are no barricades, as in vanilla.
- **Perk levels matter.** Vanilla levels only shortened the cooldown and the energy cost and made
  the turret last longer, and Tactical Engineering removes all three. Now each level above 1 sets
  up 15 % faster and adds 20 % structure (turret and barricade), and each turret level adds 100
  rounds (300 / 400 / 500).
- **Perk buttons only.** The turret perk button deploys and packs, and the barricade perk button
  builds and packs. Three quick taps on either one switch the whole mod off / on.
  Delete is no longer bound by default; set `DeployKey = "DEL"` in the config to get it back.
- **The perks are required.** No turret before you learn the turret perk, no barricades before the
  barricade perk (also with `DeployKey`): "Requires the Turret perk" / "Requires the Barricade
  perk". Without the turret perk you don't carry one either (no slowdown).
- **Smaller turret.** 60 % of the vanilla perk turret (was 80 %), same gun. Its rounds still leave
  from the muzzle, which scales with it; enemies still hit it.
- **Enemies search for the noise.** Unaware enemies who hear a turret or barricade being set up or
  packed, or a turret firing, go on alert (HTR's alert sight range then applies) and walk to
  search around the noise for up to 12 s. With Silent Ops 0.2+, Silent Ops handles it instead.

## 0.1.1 — 2026-10-31

- **On by default.** Installed, Tactical Engineering is on: you downloaded it because you want it.
  Hold Delete for 2 s (or tap the turret perk button 3 times) to switch it off, and the vanilla
  turret perk comes back. If you switched it off in 0.1.0, it stays off until you switch it on.
- F11 (the game's fullscreen key, and HTR's) can't be set as the plain deploy key any more.

## 0.1.0 — 2026-10-30

First release.

- **Deploying takes time.** Tap Delete: you kneel and can't move for 6 s, then the turret stands
  2 m in front of you. It is 80 % the size of the vanilla perk turret, with the same belt-fed gun.
- **It stays.** No 25–40 s lifetime and no self-destruct: it stays until you pack it up, it is
  destroyed, or you leave it behind.
- **Packing up.** Tap Delete next to it: it stops firing at once, and you kneel for 5 s.
- **One turret, and it is heavy.** While you carry it packed, you walk at 80 % speed and can't
  sprint. Damage stays with the turret between deployments.
- **Left behind or destroyed, it is gone.** A replacement waits at your ship or a station, out of
  combat, 5 minutes after the loss.
- **Limited ammo.** 300 rounds that stay with the turret and are refilled from your ship (in space
  or on a station, out of combat). Idea: TheCalcMan.
- **Noise.** Setting up and packing up are heard about 15 m away, a firing turret about 60 m. Unaware
  enemies turn to the noise. The events are shared with other mods as `SB2R_Noise` (Silent Ops).
- **Quieter HUD.** One message per key press (the game's HUD warning has an alert sound), and damage
  is reported only at 75 / 50 / 25 %.
- **Gamepad.** Three quick taps on the turret perk button switch the mod on / off.
- **It can be destroyed.** It has 100 structure points. Rifle hits chip 3, snipers 12, explosions
  40. A destroyed turret stays as a dead wreck.
- **Enemies fight back.** Enemies hit by a turret, or near one that is firing, turn and shoot it
  (at most 3 at a time, for 4–8 s, then they reassess).
- **Ally engineers** (optional, off by default). Squad soldiers, including the game's unused
  "Turretci" role, and companions in a fight stop and deploy a turret (at most 2 per level).
- **Off by default.** Hold Delete for 2 s to switch it on or off (remembered between sessions).
  While it is on, the vanilla instant turret perk is off, and its button deploys / packs instead.
- Works alone or with HTR. No energy cost, and it doesn't touch other perks' cooldowns, so HTR's
  slower perk recharge applies unchanged.
- Tested in game (see DESIGN.md, section 13).
