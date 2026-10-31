# Changelog

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
