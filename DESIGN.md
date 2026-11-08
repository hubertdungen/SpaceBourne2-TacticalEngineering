# Tactical Engineering (TE): design

Status: **0.1.0 implemented and tested in game on 2026-10-30.** Section 13 is the test log, with the
results. Sections 1–12 are the research and design the implementation follows. Where 0.1.0 differs
from the original plan, the text says so.

Name history: this started as "Engineering Turrets (ET)". The release name is **Tactical Engineering**,
the mod folder is `TacticalEngineering`, and its Lua modules live in `te/`.

**0.2.0 in short** (details in the sections below; 0.2 additions in §8):
- **On/off**: on by default since 0.1.1 (`StartOn = true`; the user's rule: a mod you install should
  come active). Three quick taps on the turret or barricade perk button switch it off or on, and the
  setting is remembered in `te_state.txt`.
- **Controls** (since 0.2, the user's rule: no invented keys): the game's perk buttons only. The turret
  perk button deploys, packs or cancels; the barricade perk button builds, packs or cancels. Delete
  (0.1's key) is now an optional `DeployKey`, unset by default; the shared key plan still reserves it.
- **Perk levels** and **barricades**: §8.
- **Resupply** (`"ship"`): at your ship (`WhereIsPlayer` 0) or a station (4/5), out of combat, and
  `ResupplyMinutes` (5) after the loss. The minutes are real minutes, kept across restarts.
- **Ally engineers**: implemented and tested with the squad, but off by default.

Facts marked *(read)* come from the game's Blueprints (build of 2026-10-26). Facts marked *(verified)*
were seen in game.

Goal: make the engineering perks real engineering, starting with the turret.

- Deploying a turret takes a few seconds. You kneel, you can't move, and you are exposed.
- Packing it up takes time too. Packed, it is heavy: you walk slower and can't sprint.
- You own one turret. Whatever you leave deployed at the end of a level is lost.
- Once deployed, the turret is effective: smaller than the vanilla one, but no less lethal.
- It can be destroyed, and enemies notice it and try to destroy it.
- A few allied NPCs carry one and deploy it like engineers.

The mod is a separate UE4SS Lua mod (`TacticalEngineering/`). It ships **on by default** (since 0.1.1):
hold Delete to switch it off. It works with or without HTR. With HTR, see §11 for an optional HTR-side improvement.

---------------------------------------------------------------------------------------------------

## 1. What the game does today *(read)*

### 1.1 Player engineering perks (`Q1_Character`)

`UsePerkAtSlot(SlotIndex)` reads the perk in that action slot and calls one Blueprint function per perk:
`SpawnTurrets`, `ActiavateBarricate` (sic), `ActivateTripMine`, `FrontShield`, `AreaForce`,
`ActivateDash`, `LaunchGranede`, `SlowTimeActivate`, `ActivateChainLaser`. All of them are instant.

| perk | function | checks and cost | what it spawns |
|---|---|---|---|
| Turret | `SpawnTurrets()` | `P_Turret.Level > 0`; `P_Turret.CD` ≥ 30/30/25/20 s (perk level 0–3); energy 80/80/60/40 % of `MaxEnergy` | **Explodes every existing `Player_PerkTurret_C`** (only one at a time), then spawns a new one at the `BarricadeLocation` component (about 2 m in front of you) with `MaxHP = 45` and `LifeTime` 25/25/30/40 s. Sets `P_Turret.CD = 0`. |
| Barricade | `ActiavateBarricate()` | `P_Barricade.Level > 0`; `BarrierCD` flag; 60 % energy | `Barricde_C` at `BarricadeLocation`, `LifeTime` 10/10/15/20 s; `BarrierCD` clears after 20/20/15/10 s |
| Trip mine | `ActivateTripMine()` | `P_TripMine.Level > 0`; at most 1/3/4/5 `PerkMineSpawner_C`; energy | Kneels: `DesiredStance = 1`, `Crouch()`, `DisableMove = true` for 0.5 s, plays `Mage_Beam_L_Loop_IP_Montage` |

`P_Turret`, `P_Barricade` and `P_TripMine` are `Perk_Learned_DAta` structs. Their member names carry GUID
suffixes: `Level_8_5CAAAC454DB7C9AFB663B48B7761E974` and `CD_11_004AEE844C3C3A073EF8EAAC2B628430`.

Cooldowns and energy live in `ALS_Base`. Its `Regenerators()` Blueprint function runs on a 0.25 s timer.
Each time, it raises each perk's `CD` by 0.25 until the perk's threshold, and regenerates `CurrentEnergy`
toward `MaxEnergy` at `EnergyRegenRate`. **HTR 0.4.2** (in progress) slows perk energy regeneration and these
cooldowns on foot, with a toggle key, on by default. ET must sit on top of that, not fight it (§3.7, §11).

### 1.2 The player's perk turret: `Player_PerkTurret_C`

Path: `/Game/IndustrialMachine2/Blueprints/Player_PerkTurret.Player_PerkTurret_C`. It is a plain `Actor`:
no AI controller, no tags, and no `XVisionTarget` component. `Q1_Character` references the class directly,
so it is loaded whenever the player character is.

- **BeginPlay**: sets `ActiveNow? = false`, `ShootRate = 0.1`, `MaxAmmo = 40`, ammo class, sound and
  `In Projectile Speed = 10000`. It plays a "build" sound and particle, then runs `Timeline_0`, which unfolds
  the gun. When the timeline finishes, it sets `ActiveNow? = true`. In parallel, a latent `Delay(LifeTime)`
  ends in `Explode()`. **`LifeTime` is read once, at BeginPlay.**
- **Targeting** (`CollectTargets`, every 1 s): sphere trace of 100 m radius for pawns. It takes the first one
  that is either a `Q1_Shooter_AI` with `AIType == 0` (enemy) and not `NPCDead`, or any `Character` tagged
  `Enemy` and not `Dead`. The target also needs a clear line from the turret's `Arrow`. That target becomes
  `LastDetectedActor`, and the turret calls `StartShoot()`.
- **Firing** (`JustShoot` on a 0.1 s timer, only while `ActiveNow?`): 10 rounds/s at the target's actor
  location, ±0.005 spread, 10 000 cm/s. A 40-round belt, then a 3–5 s reload. Each hit calls
  `ApplyPointDamage(HitActor, WeaponDamageAI)` with the turret as `DamageCauser`.
  `WeaponDamageAI = Character_Stats['Damage'](player level) × 1.5`.
- **ReceiveTick**: turns the gun toward `LastDetectedActor`. With no target, it slowly spins.
- **ReceiveAnyDamage**: does nothing. `CurrentHP` is never lowered, so **the vanilla turret is invulnerable**.
  `AddProgress` only shows the HP bar.
- **Explode()**: radial damage 1000 (full within 0.5 m, falling to 100 at 5 m) with no ignore list, so it can
  hurt you. Then 10 shrapnel projectiles and `K2_DestroyActor()`.
- Unused by the player perk: `Throw(ThrowVelocity)` (physics toss), and the `OwnerShooter` / `MechOwner` vars.

### 1.3 Enemy mini-turret: `NPC_Shooter_Turret_C`

Path: `/Game/IndustrialMachine2/Blueprints/NPC_Shooter_Turret.NPC_Shooter_Turret_C`. It is the boss ability
`MiniTurrets`. `BossSpecialAttacks` values: 0 AOE, 1 Hommining, 2 Dush, 3 Vanish, 4 Stealth, 5 Flame,
**6 MiniTurrets**, 7 Teleport, 8 WindAOE, 9 Shield, 10 KatanaHit.

- **Who uses it**: minibosses roll `HurtAbility` from {9 Shield, 6 MiniTurrets, 7 Teleport}.
  `Q1_Shooter_AI.SelectAbility(6)` then runs this sequence: stand up, EQS `Fint_Turret_Location`,
  `MoveTo` (2 m acceptance), kneel for about 3 s, spawn the turret at the NPC's `DropHead`.
  The spawned turret gets `MaxHP = CurrentHP = owner.MaxHP / 10`, the owner's `WeaponDamageAI`, and
  `OwnerShooter = owner`. **So the game already has an enemy engineer behaviour.**
- **Targets**: its own `RifleEye` accepts only `Q1_Character` or `Q1_Companin_AI`. Its tick aims at the
  player pawn. It can never be turned to our side.
- **Damage**: only from the player. A `Q1_Character` causer removes `4 × random(base…1.25·base)` of the
  player's weapon damage. At 0 HP it calls `Explode()`. Companions, the squad and turrets can't hurt it.

### 1.4 Team-battle turret: `RTS_Turret_C`

Path: `/Game/1Data/11_AI/TeamBattle/BattleObjects/RTS_Turret`, a child of `MasterBattleObject_C`.
HTR already gives its rounds the `turret` caliber.

- **Tags**: `Live`, `Turret`, `Defender`/`Attacker`, `Ally`/`Enemy`. `RakipTagi` holds the rival tag.
- **Activation**: `ToggleActivate(true)` calls `CalculateStats`, which reads `TurretHP`, `TurretDamage` and
  `TurretShotRate` from the battle's `BattleBorder`. It then switches its `XVisionEye` on. It fires every
  `ShootRate` (1.5 s).
- **Damage**: only while `BattleStarted`, and only from causers tagged with `RakipTagi`. At 0 HP,
  `ForceDead()` disables collision, clears tags, destroys the eyes, plays an explosion and droops the gun.
- **Why not use it**: too big (it has fence walls, though `HideBarried?` removes them). It needs a
  `BattleBorder` for its stats. **It is the only turret with a death model and an `XVisionTarget`.**

### 1.5 How enemies pick targets *(read; see `analysis/npc_ai.md` in the main checkout)*

- **Filters**: both of `Q1_Shooter_AI`'s eyes (`XVisionEye` for sight, `RifleEye` for the barrel cone) filter
  by **class cast**. They accept only `Q1_Character`, `Q1_Companin_AI` and `Master_Soldier`. There is no team
  system. **No NPC will ever choose a turret as a target on its own.**
- **Aim point**: `JustShoot` aims at `ShooTarget.DetectedPoints` (shuffled) if `ShooTarget` is valid,
  otherwise at `LastDetectedActor`'s location.
- **Target refresh**: `XVisionEye.OnTargetUpdated` refreshes `CurrentDetected` / `LastDetectedActor` every
  0.3 s, and `RifleEye.OnTargetDetected` sets `ShooTarget`. Anything Lua writes there is overwritten within
  0.3 s unless it is re-asserted in those same events.
- **Focus**: the behaviour tree's `Val_Focus_Task` focuses `LastDetectedActor` (else the player).
- **Exposure**: `CheckMeleeDistance` runs every 1 s on every shooter (HTR uses it as its NPC "think").

### 1.6 Allies

- **Companions** (`Q1_Companin_AI`): `Q1_Shooter_AI` with `IsCompanian = true`. They target only non-companion,
  alive `Q1_Shooter_AI`.
- **Squad** (`Master_Soldier` ← `Importend_Character_C`): `UpdateBattle` runs every 1.5 s, picks the nearest
  `Enemy`-tagged actor with line of sight into `C_Target`, and shoots in bursts. Other fields: `AI_Type`
  (1 = our side), `InInjuredMode`.
- **Roles**: `SoldierType` (`GroundSoldierType`) is 0 Assulter, 1 Tank, 2 Medic, 3 Lazer, 4 Mech, 5 AntiMissile,
  6 Sniper, **7 Turretci** (Turkish: "turret operator"). `Master_Soldier` only implements types 0–3.
  **The turret soldier was planned and never built.**

### 1.7 Movement (ALS v4 in `ALS_Base`)

- **Speed**: `UpdateDynamicMovementSettings(AllowedGait)` rebuilds `CurrentMovementSettings` from the movement
  table. It then writes `CharacterMovement.MaxWalkSpeed` (walk/run/sprint) on every update, so a one-off
  speed write is overwritten.
- **Sprint**: `CanSprint(out CanSprint)` is a Blueprint pure function, so its out parameter can be overwritten
  in a post-hook.
- **Input lock**: `DisableMove` (bool, `ALS_Base`) zeroes the player's movement input. The trip-mine perk
  uses it.
- **Location**: `WhereIsPlayer` (`Q1_Character`) is 0 Space, 1 PlanetSurface, 2 Dungeon, 3 Wormhole,
  4 StationTrans, 5 StationSubLevel.

---------------------------------------------------------------------------------------------------

## 2. Feasibility: Lua only vs Blueprint/pak

| feature | UE4SS Lua alone? | how / why not |
|---|---|---|
| Deploy / pack timers, kneeling, input lock | **Yes** | Own state machine; `DisableMove`, `Crouch()`, `DesiredStance` on the pawn |
| Persistent turret (no 25–40 s lifetime) | **Yes** | Write `LifeTime` before BeginPlay: deferred spawn, or the class default object (§3.3) |
| One turret, carried between levels, lost if left behind | **Yes** | Lua state survives level loads; plus a state file (`et_state.txt`) |
| Carry weight: slower, no sprint | **Yes** | Post-hooks on `ALS_Base:UpdateDynamicMovementSettings` and `ALS_Base:CanSprint` |
| Block / convert the vanilla turret perk | **Yes** | Pin `P_Turret.CD` at 0 in a post-hook of `ALS_Base:Regenerators` (vanilla returns early), react in a post-hook of `SpawnTurrets` |
| Smaller turret | **Yes** (scaled) | `SetActorScale3D`. A truly new, smaller model needs a pak. |
| Turret HP and destruction | **Yes** | Post-hook `Player_PerkTurret_C:ReceiveAnyDamage` (the BP event exists, empty) |
| Enemies attack the turret | **Partly** | Lua forces targets (`LastDetectedActor`, focus, `StartShoot`) and re-asserts them in the eye events. Enemies still don't *see* it natively; that needs a BP edit of the eye filters. |
| NPC rounds actually hitting the turret | **Unknown** | Depends on the turret's collision vs the NPC projectile channel. Fallback: simulated hits (§5.3). |
| Companions/squad can destroy enemy mini-turrets | **Yes** | Post-hook `NPC_Shooter_Turret_C:ReceiveAnyDamage` |
| Ally engineers (squad, companions) | **Yes, basic** | Lua drives stop → kneel → wait → spawn `Player_PerkTurret_C` (targets enemies). AI that packs up and re-deploys is much harder. |
| Rare enemy engineers | **Yes** | `npc:SelectAbility(6)` uses the vanilla MiniTurrets ability (walks to a spot, kneels, deploys) |
| Turret visible on your back while carried | **Maybe** | Spawn a mesh actor and attach it to a socket. Fiddly; polish phase. |
| Kneel/work animation | **Probably** | `PlayAnimMontage` with the trip-mine montage (`/Game/Locomotion/CharacterAssets/Animations/Mage_Beam_L_Loop_IP_Montage`) |
| Deploy progress bar, turret HP on the HUD | **Text only** | `TMWPerkWarning(FText)` messages *(verified)*. A real progress bar or HUD widget needs a pak. |
| New inventory item / buying turrets | **No** | Needs item data tables and UI (pak). Lua can only fake ownership in its state file. |
| Barricades as real fortifications | **Partly** | `Barricde_C` has no damage events, so hits must be caught in the shooters' projectile-hit hooks (§8) |

**Needs Blueprint or pak modding:**

- A new smaller turret mesh.
- Native enemy perception of turrets (XVision class filters).
- A real HUD progress bar and turret HP widget.
- Inventory items and a shop.
- New animations.
- Squad AI that packs and re-deploys on its own.

---------------------------------------------------------------------------------------------------

## 3. The player's turret

### 3.1 State machine

```
            deploy key, on foot, still              DeploySeconds elapse
  CARRIED ------------------------------> DEPLOYING ---------------------> DEPLOYED
     ^   <------------------------------    |  key again / pushed away        |  |
     |              cancel                  |                                 |  | HP <= 0
     |                                      v                                 |  v
     |        PackSeconds elapse        (back to CARRIED)    pack key in range |  DESTROYED --+
     +------------------------------------ PACKING <---------------------------+              |
                                                                                              |
  DEPLOYED and the turret disappears without being packed (level end, quit)  ->  LOST  -------+
  LOST / DESTROYED --(resupply rule, §3.6)--> CARRIED
```

These are plain Lua values. Each one is saved to `et_state.txt` when it changes. The file holds the state,
the turret's remaining structure, and the time it was lost.

### 3.2 Input

- **`DeployKey`** (default `DEL`, the Delete key) toggles: deploy when carried; pack when deployed and in
  range; cancel while working. The game doesn't bind Delete. F6 / F8 / F10 are the game's quick save, quick
  load and bug report, and the realism set's shared key plan avoids them.
  Same key rules as HTR 0.4.4:
  - the plain key does nothing while Shift, Ctrl or Alt is held (checked with
    `PlayerController:IsInputKeyDown`), so Shift+Delete stays a spare for the set;
  - `"Shift+DEL"`-style strings work;
  - a plain game key (F1–F6, F8, F10, F11, F12) is refused and falls back to Delete.
- **`UseTurretPerkButton`**: the vanilla turret perk button does the same thing. With `P_Turret.CD` kept at 0,
  the vanilla `SpawnTurrets()` returns before it spends energy or touches any turret. A post-hook on
  `Q1_Character:SpawnTurrets` then acts as the deploy/pack button. This gives gamepad players a button for
  free. It only works if the turret perk is learned and placed in an action slot.

### 3.3 Deploy flow (`DeploySeconds`, default 6 s)

1. Preconditions:
   - on foot and on the ground (`Flying?` false, not falling);
   - not in a dialog;
   - not on a station (`WhereIsPlayer` ∉ {4, 5});
   - state `CARRIED`.
2. Kneel and lock: `pawn.DesiredStance = 1`, `pawn:Crouch(false)`, `pawn.DisableMove = true`.
   Holster (`HolsterWhileWorking`, on since 0.2.4: weapon away, keys locked, drawn again after; see
   0.2.4 below). The trip-mine montage is still to do.
3. Every 0.25 s, show a progress message ("Deploying turret… 3 s"). Cancel if:
   - the key is pressed again;
   - you were pushed more than 0.5 m;
   - you died.
   Taking hits does **not** cancel. You are simply exposed: no movement, and no shooting (holstered).
   A melee swing cancels (0.2.4).
4. At the end, spawn the turret at `pawn.BarricadeLocation:K2_GetComponentLocation()` (where vanilla spawns
   it), facing your yaw:
   - **The skeleton's path**: set `LifeTime = 1e7` on the class default object
     (`.../Player_PerkTurret.Default__Player_PerkTurret_C`), then call
     `pawn:GetWorld():SpawnActor(cls, loc, rot)`. It only uses calls HTR's dev tests already made (they
     spawned NPCs and `RTS_Turret` with `World:SpawnActor`). The new instance copies `LifeTime` from the
     default object before its BeginPlay. The vanilla perk always sets its own `LifeTime`, and it is blocked
     anyway.
   - **Alternative**: `GameplayStatics:BeginDeferredActorSpawnFromClass(pawn, cls, transform, 1, nil)`, then
     set `LifeTime`, then `GameplayStatics:FinishSpawningActor(actor, transform)`. Untested: passing an
     `FTransform` as a Lua table.
   - Then `SetActorScale3D(Turret.Scale)`. Register the turret's address and object path as ours.
     Structure is tracked in Lua (§5), not in `CurrentHP`.
5. Unlock (`DisableMove = false`, stand up). The turret's own unfold timeline (about 1–2 s) runs, then it fires.

### 3.4 Pack-up flow (`PackSeconds`, default 5 s)

1. Preconditions: state `DEPLOYED`, turret alive, and within `PackRange` (2.5 m).
2. Immediately make the turret safe: `ActiveNow? = false`, `StopShoot()`.
3. Kneel and lock as in deploy, with the same progress and cancel rules. On cancel, set `ActiveNow? = true` again.
4. At the end, call `K2_DestroyActor()`. State becomes `CARRIED`, and the remaining structure is kept: damage
   carries over.

### 3.5 Carrying

- **Speed**: post-hook on `ALS_Base:UpdateDynamicMovementSettings`. When `self` is the player and the state
  is `CARRIED`, multiply `CharacterMovement.MaxWalkSpeed` (and `MaxWalkSpeedCrouched`) by `CarrySpeed`
  (0.8). This runs after ALS writes its own value, so it holds every update.
- **No sprint**: post-hook on `ALS_Base:CanSprint` that sets the out param `CanSprint = false`.
- **Optional**: block the jetpack. Not planned; open question.
- **The cost of owning one**: carried, you are slower. Deployed, you are back to full speed, but the turret
  stays where it is.

### 3.6 Ownership, loss and resupply

- **One per player**: deploy is refused unless you are in state `CARRIED`.
- **Lost**: if the turret is deployed and it disappears without being packed, it is lost. Causes include a
  level change, quitting the game, or a vanilla `Explode()`. Detection: our turret's `ReceiveTick` hook stops
  arriving (see §10), while the player's tick keeps arriving. Both stop while the game is paused, so a pause
  is not mistaken for a loss.
- **Resupply** (`Resupply`, **open question**):
  - `"ship"` (proposed default): a replacement is issued the next time you are in space or on a station
    (`WhereIsPlayer` ∈ {0, 4, 5}).
  - `"level"`: at the next level.
  - `"never"`: not replaced.
- **Saves**: the state file is per game install, not per save slot. Loading an old save keeps the mod's
  current state (a known limitation).

### 3.7 Blocking the vanilla turret perk

`SpawnTurrets()` explodes every `Player_PerkTurret_C`, including ours, because it is the same class.

- **How**: a post-hook on `ALS_Base:Regenerators()` (the 0.25 s timer that raises the cooldowns) sets
  `P_Turret.CD = 0` for the player right after vanilla raises it (`BlockVanillaTurretPerk`). The vanilla
  check (CD ≥ 20–30 s) then always fails before any energy is spent.
- **What you see**: the perk icon shows as cooling down. Its button becomes our deploy/pack button (§3.2).

**On top of HTR 0.4.2, not against it.** HTR 0.4.2 slows perk energy regeneration and cooldowns.

- **One field only**: ET writes `P_Turret.CD`, which belongs to the perk ET replaces. It never writes
  `CurrentEnergy`, `EnergyRegenRate` or any other perk's cooldown, so the barricade, trip mine and the rest
  keep HTR's slower rules.
- **No race**: if HTR rescales `P_Turret.CD` in its own `Regenerators` post-hook, the result stays far below
  the threshold whichever hook runs first.
- **Energy**: deploying is mechanical work and costs **no suit energy** by default. An optional
  `Player.DeployEnergy` (percent of `MaxEnergy`, paid at the end of the deploy) is an open question (§14).
  If added, it is paid from `CurrentEnergy`, so it naturally refills at HTR's slower rate. Turrets have no
  cooldown of their own: the deploy and pack times are the limit.

---------------------------------------------------------------------------------------------------

## 4. Turret stats: "smaller, no less lethal"

| | vanilla perk turret | ET turret |
|---|---|---|
| Size | 1.0 | `Scale` 0.8 |
| Lifetime | 25–40 s, then it explodes | unlimited, until packed, destroyed or lost |
| Durability | invulnerable | `Structure` 100 points (§5) |
| Fire | 10 rds/s, 40-round belts, 3–5 s reload, ±0.005 spread | same (a belt-fed light machine gun is realistic) |
| Ammo | unlimited | `AmmoBelts` (0 = unlimited; open question) |
| Damage per hit | `Character_Stats.Damage(level) × 1.5` | with HTR: proposed caliber `turret_light` (§11); without HTR: vanilla |
| Targets | enemies within 100 m with line of sight | same |

**Ammo budget** (if `AmmoBelts > 0`):
- **Count**: a post-hook on `Player_PerkTurret_C:JustShoot` counts rounds. It is per shot, but only one or two
  turrets exist, and the cost is a counter increment.
- **Out of ammo**: `ActiveNow? = false` and the message "Turret out of ammo".
- **Refill**: packing up and resupplying refills it.

---------------------------------------------------------------------------------------------------

## 5. Destruction

### 5.1 Damage intake

Post-hook on `Player_PerkTurret_C:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)`. The
vanilla body does nothing, so the hook decides everything.

- **Not ours**: if the turret's address is not registered, ignore it, unless `Turret.AllVanilla` is set.
- **Classify the causer once per class**, as in HTR's `classify.lua`:
  - `Q1_Shooter_AI` family: `npc_rifle` / `npc_heavy` / `npc_sniper` / `npc_boss`, using the same fields HTR
    reads;
  - grenades and explosions: radial damage arrives here too, with `DamageCauser` the grenade or projectile;
  - `Q1_Character`: friendly fire counts;
  - squad, companions, other turrets.
- **Structure lost per hit** comes from `Turret.HitCost` (structure points per hit by family). The defaults
  mean about 30 rifle hits, 8 sniper hits or 2–3 grenades. Small arms mostly chip a light armored gun, while
  explosives and heavy weapons are the real threat.
- **Notice**: a turret that took damage in the last 10 s reports "Turret hit — 62 %", at most every 3 s.

### 5.2 Death

At 0 structure, `Turret.DestroyedEffect` decides what happens:

- `"wreck"` (proposed default):
  - set `NPCDead = true`, `ActiveNow? = false`;
  - call `StopShoot()` and `SetActorTickEnabled(false)`;
  - the turret stays as a dead husk. `CollectTargets` still runs every 1 s, but `StartShoot` needs
    `ActiveNow?`. Packing a wreck gives nothing back.
- `"explode"`: vanilla `Explode()`. Blast plus shrapnel; it hurts anyone within 5 m, including you.

The state becomes `DESTROYED`, and the resupply rule applies.

### 5.3 If NPC rounds don't collide with the turret

NPC projectiles use trace channel 10 (`SpawnProjectileSingleByChannel(..., 10)`). The turret's meshes and box
may ignore that channel, which is untested. If so, use **simulated hits**: a post-hook on
`Q1_Shooter_AI:JustShoot` for NPCs currently engaging the turret (§6). Each shot rolls a hit chance by distance
(100 % at 5 m, 25 % at 40 m) and applies the hit cost directly. This is cheap: only the few engaging NPCs pass
the address check.

### 5.4 Enemy mini-turrets

Post-hook `NPC_Shooter_Turret_C:ReceiveAnyDamage` (`DamageEnemyMiniTurrets`). If the causer is not the player,
call `CurrentHP -= vanilla-equivalent`, and `Explode()` at 0, mirroring the vanilla player branch. Companions,
the squad and our turrets can then kill them too.

---------------------------------------------------------------------------------------------------

## 6. Enemies target the turret

Enemies can't see a turret natively (§1.5), so ET gives them **awareness** and then **forces the target** for a
while.

1. **Awareness** (per NPC address, expires after 20 s):
   - post-hook `Q1_Shooter_AI:ReceivePointDamage`: the `DamageCauser` is a registered turret, so the NPC was
     shot by it;
   - in the 1 s think: the NPC is within `AwareRadius` (25 m) of a turret that fired in the last 2 s, so the
     noise and tracers reveal it.
2. **Decision** in the 1 s think (post-hook `Q1_Shooter_AI:CheckMeleeDistance`; `self` is the NPC):
   - skip companions, allies, the dead, and NPCs that are not `Ready?`;
   - chance to engage = `TargetChance` (0.6), × 1.5 if the turret is closer than the player, × 0.5 if the NPC
     can see the player (`CanSeeTheTarget`);
   - at most `MaxAttackers` (3) NPCs engage one turret at a time.
3. **Engage** for a random `FocusSeconds` (4–8 s):
   - set `npc.LastDetectedActor = turret`;
   - clear `npc.ShooTarget.DetectedActor`, so `JustShoot` falls back to `LastDetectedActor`. HTR showed struct
     member writes work: `t.CurrentDetected.DetectedActor = x`.
   - `npc.Controller:K2_SetFocus(turret)`, `npc:SetRotationMode(2)`, `npc:StartShoot()`.
4. **Keep it**: post-hooks on the four eye events, `XVisionEye` / `RifleEye` × `OnTargetDetected` /
   `OnTargetUpdated`. If this NPC is engaging a turret, write the turret back into `LastDetectedActor` and clear
   `ShooTarget`. Otherwise the BP snaps back to the player within 0.3 s.
5. **Stop** when:
   - the time runs out;
   - the turret is dead, packed or lost;
   - the NPC was just hit by the player (`ReceivePointDamage`, causer `Q1_Character`): it turns to the real
     threat.

   On stop, clear the override and let the eyes re-acquire.

**Aim point.** `LastDetectedActor`'s location is the turret's root. If that is at ground level, rounds may hit
the floor. Options, in this order:
1. Leave it, if the root is near the gun.
2. Write `ShooTarget.DetectedPoints = { gun location }` (TArray write from Lua is untested).
3. Simulated hits (§5.3).

**Later (optional)**: grenades at turrets. `ThrowGranede()` throws at the player (`End Pos`). Redirecting it
needs an `End Pos` override inside the throw, which needs research.

---------------------------------------------------------------------------------------------------

## 7. Ally engineers

### 7.1 Squad soldiers (`Master_Soldier`)

**Hook**: post-hook `Master_Soldier:UpdateBattle` (every 1.5 s per soldier; `self` is the soldier).

**Who is an engineer**:
- `SoldierType == 7` ("Turretci") always, if `TurretciAreEngineers`;
- otherwise a one-time roll per soldier address with `SquadEngineerChance` (0.1).

**Deploy when all of these hold**:
- `AI_Type == 1`;
- `C_Target` is valid (in battle);
- not `InInjuredMode`;
- the soldier moved less than 1 m since the last check (it has stopped);
- it hasn't deployed this level;
- fewer than `MaxAllyTurrets` (2) ally turrets exist.

**Flow**:
1. `Controller:StopMovement()`.
2. Wait `AllyDeploySeconds` (8 s), checked on each `UpdateBattle`. Cancel if it moved more than 1.5 m or got
   injured.
3. Spawn `Player_PerkTurret_C` 1.2 m in front of the soldier (same spawn path as §3.3), and register it as an
   ally turret with the owner's address.

`Player_PerkTurret_C` already shoots `Q1_Shooter_AI` enemies and any `Enemy`-tagged character. That covers
enemy squad soldiers in ground battles.

### 7.2 Companions (`Q1_Companin_AI`)

**Hook**: the same 1 s think as §6, with `IsCompanian` true. A one-time roll with `CompanionEngineerChance`
(0.15).

**In combat**: `CurrentDetected` is valid, or BB `InCombat?`.

**Flow**:
1. `Controller:StopMovement()`, `SetStance(1)` (kneel).
2. Wait.
3. Spawn.

### 7.3 Limits (first version)

- **No pack-up**: AI engineers don't pack. Their turret stays until the level ends. Later: pack when the owner
  is more than 40 m away and out of combat.
- **No HP for ally turrets**: they use the same HP and destruction rules (§5), and enemies may target them (§6).

### 7.4 Rare enemy engineers (optional, `EnemyEngineerChance`, default 0 = vanilla)

In the 1 s think, a non-boss enemy that has seen the player and is in cover may call `npc:SelectAbility(6)`, at
most once per NPC. The vanilla MiniTurrets ability already does the realistic part: it walks to a spot, kneels
about 3 s, and deploys. Its turret has `owner.MaxHP / 10` HP and becomes destructible by allies through §5.4.

---------------------------------------------------------------------------------------------------

## 8. 0.2: perk levels and barricades (the user's ideas, 2026-10-31)

### 8.1 Perk levels

What vanilla levels change (§1.1): the turret perk's level only shortens the cooldown (30/25/20 s),
lowers the energy cost (80/60/40 %) and lengthens the lifetime (25/30/40 s). TE removes all three, so
without a bonus a higher level would mean nothing. 0.2 gives small, practical steps instead. The level
is read from `P_Turret.Level` (`P_Barricade.Level` for barricades). Level 1 or not learned is the base,
level 2 is one step and level 3 two.

| per step | turret | barricade |
|---|---|---|
| `Levels.SetupFaster` 15 % | deploy 6 → 5.1 → 4.2 s, pack 5 → 4.25 → 3.5 s | build 4 → 3.4 → 2.8 s, pack 3 → 2.55 → 2.1 s |
| `Levels.ExtraRounds` +100 | 300 → 400 → 500 rounds (refilled at the ship) | — |
| `Levels.ExtraStructure` +20 % | structure 100 → 120 → 140 | 150 → 180 → 210 |
| `Barricades.ExtraPerLevel` +1 | — | carried 1 → 2 → 3 |

Not changed: tracking and accuracy. The 1 s target scan and the ±0.005 spread live in the turret's
Blueprint; faking them in Lua would cost per-shot work for little gain.

### 8.2 Barricades

**Vanilla** (`Barricde_C`): an energy-shield wall (`P_GunShield_Fast`, two collision meshes), put up instantly
at `BarricadeLocation` for 10/15/20 s (`Delay(LifeTime)`, then destroy). `ActiavateBarricate` (sic) needs
`P_Barricade.Level > 0`, the `BarrierCD` flag clear and 60 % energy. It has no damage events.

**0.2:**
- **Same input.** The barricade perk button. While TE is on, `BarrierCD` is kept set in the `Regenerators`
  post-hook, so vanilla returns early. The post-hook of `ActiavateBarricate` is our button. Without the perk
  learned, there are no barricades (as in vanilla); no extra key is used.
- **Building takes time.** You kneel and can't move for `BuildSeconds`; moving cancels. It is metal work:
  `Noise.WorkRadius`, shared as `SB2R_Noise` (Silent Ops).
- **Pack it up.** The button next to one of yours (`PackRange`) packs it in `PackSeconds`. A packed shield
  recharges: it comes back at full strength.
- **Limited.** You carry `Carried` (+1 per level step). They are restocked at your ship or a station, out of
  combat. One left standing when you leave the area is lost.
- **Destructible.** The shooters' `OnProjectileHit` post-hooks (the same functions HTR hooks) compare
  `OutHitResult.Actor` with our barricades' addresses: one table check per enemy round while a barricade
  stands, none otherwise. Each hit costs `Turret.HitCost`; at 0 it collapses (destroyed). A notice at 50 %.
- **Long life.** Spawned like the turret: `LifeTime` 1e7 on the class default object, then `SpawnActor`.

**The perks are required** (the user's rule): no barricades without `P_Barricade.Level > 0`, no
turret without `P_Turret.Level > 0`, also with `DeployKey` ("Requires the Turret / Barricade perk").
Without the turret perk you own no turret: no carry slowdown, no ammo messages (`T.turretUsable`,
read once a second). "In an action slot" can't be read cheaply; the perk buttons imply it.

### 8.3 Enemies search for the noise (the user's idea)

Silent Ops off (or older than 0.2): an unaware enemy that hears TE's noise (deploy, pack, barricade
work, turret fire) gets the vanilla alert (`CheckForFirstFocus`: alert / in combat, so HTR's alert
sight range applies), then searches: `BrainComponent:StopLogic`, focal point and `MoveToLocation` to
a point within `Noise.SearchRadius` (4 m) of the noise. That is Silent Ops' method. The search ends
when it detects someone, engages a turret, dies, after `Noise.SearchSeconds` (12), or when TE is
switched off; then `RestartLogic`. Without `StopLogic` the behaviour tree called it back within 2 s
(seen in game).

Silent Ops 0.2+ on (`SilentOps_On`): TE does none of this. Silent Ops hears turret setup (turret
`BeginPlay`, 12 m, "suspect") and fire ("hunt") through its own hooks, and packing from
`SB2R_Noise` ("suspect"). It does not read `barricade` yet. Test: one pack at 6 m raised the meter to
0.29, under `SuspiciousAt` 0.35: no look, no search. Proposed to the Silent Ops session: read
`barricade` too, and make TE work noise "search" (or a bigger bump). The turret's structure is now kept in % of its maximum, so a carried turret at full
strength deploys at full strength after a level-up.

**Cover for NPCs: not in 0.2.** The game's AI has no cover search to plug a barricade into. The wall still
stops rounds physically, for anyone standing behind it.

**Trip mines** and **energy perks** (front shield, area force) stay out of scope.

---------------------------------------------------------------------------------------------------

## 9. Configuration (`scripts/config.lua`)

**Defaults**: everything is off until `Enabled = true`. Inside the mod, features have realistic defaults, and
the experimental ones (ally engineers, enemy engineers, ammo limits) start off.

| key | default | meaning |
|---|---|---|
| `Enabled` | `false` | master switch; with `false`, nothing is hooked |
| `DeployKey` | `"DEL"` | deploy / pack / cancel (Delete) |
| `UseTurretPerkButton` | `true` | the vanilla turret perk's button does the same thing |
| `BlockVanillaTurretPerk` | `true` | keep the vanilla instant turret off (required: it would explode ours) |
| `Player.DeploySeconds` / `PackSeconds` | 6 / 5 | time kneeling to set up / tear down |
| `Player.HolsterWhileWorking` | `true` (0.2.4) | put the weapon away while working, lock the weapon keys, draw it again after |
| `Player.PackRange` | 250 | cm |
| `Player.CarrySpeed` | 0.8 | speed while carrying |
| `Player.CarryNoSprint` | `true` | no sprint while carrying |
| `Player.Resupply` | `"ship"` | `"ship"`, `"level"` or `"never"` |
| `Turret.Scale` | 0.8 | visual size |
| `Turret.Structure` | 100 | durability points |
| `Turret.HitCost` | table | points lost per hit, by attacker family |
| `Turret.DestroyedEffect` | `"wreck"` | `"wreck"` or `"explode"` |
| `Turret.AmmoBelts` | 0 | 0 = unlimited; else 40-round belts per deployment |
| `Enemies.AttackTurrets` | `true` | enemies notice and shoot turrets |
| `Enemies.AwareRadius` / `TargetChance` / `MaxAttackers` / `FocusSeconds` | 2500 / 0.6 / 3 / {4, 8} | |
| `Enemies.DamageEnemyMiniTurrets` | `true` | allies can destroy enemy mini-turrets |
| `Enemies.EngineerChance` | 0 | extra enemy engineers (vanilla MiniTurrets ability) |
| `Allies.Engineers` | `true` (0.2.1) | squad soldiers / companions deploy turrets; 4 taps switch (remembered) |
| `Allies.TurretciAreEngineers` / `SquadEngineerChance` / `CompanionEngineerChance` | `true` / 0.1 / 0.15 | |
| `Allies.DeploySeconds` / `MaxAllyTurrets` | 8 / 2 | |
| `Debug.Log` / `SlowHookMs` | `false` / 8 | same meaning as HTR |

---------------------------------------------------------------------------------------------------

## 10. Performance

HTR's measured rules apply:

- one `FindAllOf` ≈ 50 ms;
- a failed `StaticFindObject` ≈ 37 ms;
- a successful one ≈ 0 ms;
- `GetPlayerPawn(ctx, 0)` is instant;
- `DeltaSeconds` is clamped, so use `os.clock`.

| hook / work | how often | budget and safeguards |
|---|---|---|
| `ALS_Base:Regenerators` (vanilla turret perk block) | 4/s × every ALS character that runs the timer | Address compare, then one struct write for the player |
| `ALS_Base:ReceiveTick` (player heartbeat, deploy timer) | every frame × every ALS character | Compare the address first; real work at most every 0.1 s, for the player only. Measure: if NPCs are ALS characters too, this is the largest per-frame cost. Alternative: drive the timers from `LoopAsync` with a ctx from the last hook. |
| `ALS_Base:UpdateDynamicMovementSettings`, `CanSprint` | every movement update × every ALS character | Early return unless the state is `CARRIED` and `self` is the player. Only hooked when `CarrySpeed < 1` / `CarryNoSprint`. |
| `Player_PerkTurret_C:ReceiveTick` | every frame × turrets (1–3) | Heartbeat plus the command mailbox; throttled to 10 Hz |
| `Player_PerkTurret_C:ReceiveAnyDamage` | per hit on a turret | Cheap table lookups; the class family is cached per class name |
| `Player_PerkTurret_C:JustShoot` (only if `AmmoBelts > 0`) | 10/s per turret | One counter increment |
| `Q1_Shooter_AI:CheckMeleeDistance` (think) | 1/s per shooter | Distance math only; no traces, no scans |
| `Q1_Shooter_AI` eye events (4) | 3–5/s per NPC that sees someone | Return at once unless this NPC address is engaging (table lookup) |
| `Q1_Shooter_AI:ReceivePointDamage` | per hit on an NPC | Address compare of `DamageCauser` against registered turrets |
| `Q1_Shooter_AI:JustShoot` (only if §5.3 fallback is used) | 10/s per shooter | Address lookup; most return at once. Measure. |
| `Master_Soldier:UpdateBattle` (only if `Allies.Engineers`) | 1/1.5 s per soldier | Cheap |
| Spawning a turret | on deploy | Once; measure (deferred spawn + finish) |
| Class lookups | at start | `Player_PerkTurret_C` loads with `Q1_Character`, so the lookup is a hit. Missing classes use HTR's backoff (1, 2, 4… 16 s, one miss per poll). |

**Never**:
- `FindAllOf` in combat code;
- `GetAllActorsOfClass` with a Lua out-table (corrupts the Lua state);
- hooks on native functions or `LoadMap`;
- game objects kept from one frame to the next.

**Object safety**:
- Turret-side actions (stop, destroy, set flags) are **queued by turret address**. They run inside that
  turret's own `ReceiveTick` / `ReceiveAnyDamage` hook, where the object is alive.
- When an NPC hook needs the turret object (§6 re-assert), it is found again by its stored path with
  `StaticFindObject`. That costs about 0 ms while the turret exists, and it is only tried while the turret's
  tick heartbeat is under 0.3 s old, which avoids the 37 ms miss.
- Per-turret Lua state is plain numbers and strings keyed by address, like HTR's NPC state.

**Squad hooks**: `Master_Soldier` is usually not loaded outside battles. Its hooks retry the class lookup at
most every 60 s, plus right after arriving somewhere new. HTR also probes this class, so the two mods pay for
separate misses.

**Release gate** (same as HTR): frame-time test in game, with Debug.Log profile output. Measure each hook's
calls and ms over 30 s in a firefight with 10+ NPCs, a deployed turret and the squad.

---------------------------------------------------------------------------------------------------

## 11. Working with HTR

- ET doesn't need HTR, and HTR doesn't need ET. Both can hook the same functions (UE4SS allows several
  callbacks).
- **HTR 0.4.2 perk energy/cooldown slowdown**: ET only pins the turret perk's own cooldown, and adds no energy
  cost or cooldown of its own (§3.7). With HTR's slowdown on or off, every other perk behaves exactly as HTR
  decides.
- **HTR-side change** to propose, not done here:
  - **The problem**: HTR classifies damage causers by class. `Player_PerkTurret_C` is not in
    `G.TurretClassNames`, so today its rounds are `generic` (dmg 50, pen 40) and its side is `other`.
  - **The fix**: add a light-turret family. In `gamedefs.lua`: `G.LightTurretClassNames = { Player_PerkTurret_C = true }`.
    In `ballistics.lua`: caliber `turret_light = { dmg = 55, pen = 50 }`, a belt-fed light machine gun about
    as lethal as a rifle. In `classify.lua`: side `ally` for that family.
  - **Why not the heavy caliber**: using `RTS_Turret`'s `turret` caliber (100/72) at 10 rounds/s would be far
    too strong.
- **Duplicate classification**: ET's own hit-cost table (§5.1) uses the same NPC fields as HTR's
  `classify.lua`. Later, both mods could share one small `common/` module.

---------------------------------------------------------------------------------------------------

## 12. Phased implementation plan

| phase | content | done when |
|---|---|---|
| **P0** (this commit) | Research, this document, the skeleton mod (hooks and calls stubbed, marked untested) | reviewed |
| **P1** discovery | **Every hook and setter is logged; no behaviour changes.** Log `Player_PerkTurret_C` BeginPlay/Tick/AnyDamage, `SpawnTurrets`, `UsePerkAtSlot`, `BarricadeLocation` world position vs feet, turret root height, and `P_Turret` reads/writes. | log shows each hook firing with sane values |
| **P2** deploy / pack / carry | State machine, deploy and pack timers, kneel and lock, spawn with long `LifeTime`, scale, block vanilla perk, perk-button input, carry slowdown, loss at level end, state file, resupply | §13 tests 1–9 pass, frame time unchanged |
| **P3** destruction | `ReceiveAnyDamage` intake, hit-cost table, wreck/explode, HP notices; enemy mini-turrets destructible by allies | tests 10–13 |
| **P4** enemy targeting | Awareness, decision, forced target + re-assert in eye events, attacker cap; collision check → simulated-hit fallback if needed | tests 14–17 |
| **P5** ally engineers | Squad (`UpdateBattle`), companions, limits; optional enemy engineers (`SelectAbility(6)`) | tests 18–20 |
| **P6** barricades | Same flow for `Barricde_C`, hit detection via projectile-hit hooks | own test list |
| **P7** polish | Kneel montage, carried mesh on the back, sounds, HTR caliber integration, docs (README + Nexus/Steam text) | release checklist |

---------------------------------------------------------------------------------------------------

## 13. In-game test plan

Run with `Debug.Log = true`. Test on a planet surface level with enemies, in a dungeon floor (elevators), and
in a ground battle with the squad. Record frame times before and after each phase.

1. **Off is off**: `Enabled = false`. No hooks registered (log), and the vanilla turret perk works as before.
2. **Lookups**: `Enabled = true` at the main menu. Class lookups hit, with no stutter while loading (log
   timings).
3. **Deploy**: press Delete on foot. You kneel and can't move. The progress messages count down. The turret
   appears at the vanilla spot, smaller, unfolds and fires at enemies. It stays more than 60 s (no vanilla
   explosion). Pressing Delete does not trigger any game action. Shift+Delete (and Ctrl/Alt+Delete) does
   nothing.
4. **Cancel**: press Delete again mid-deploy. You stand up, nothing spawns, and the state is still `CARRIED`.
5. **Pack**: walk to the turret and press Delete. It stops firing at once, you kneel, it disappears, and you are
   slower with no sprint. Out of range shows "Too far from the turret".
6. **One only**: with a turret deployed, pressing Delete far away does nothing (message). The vanilla turret
   perk button never spawns a second turret, never explodes ours, and never spends energy.
7. **Carry speed**: compare walk/run speed and sprint, carried vs not (debug log of `MaxWalkSpeed`).
8. **Level end**: deploy, then take the elevator or leave the level. The message says the turret is lost, and
   the state is `LOST`. With `Resupply = "ship"`, boarding the ship gives a new one.
9. **Persistence**: pack, quit, and restart. Still `CARRIED`, with the same structure.
10. **Damage intake**: an enemy shoots the turret. Log `ReceiveAnyDamage` (causer class, damage) and the
    structure going down. Check that hits register at all; if not, enable the §5.3 fallback.
11. **Grenade**: a grenade next to the turret costs a large chunk.
12. **Death**: wreck mode stops firing and stays; explode mode blasts (you take damage within 5 m).
13. **Enemy mini-turret**: a companion or our turret kills a miniboss's mini-turret.
14. **Targeting**: enemies hit by the turret turn and shoot it (focus visible). At most 3 at a time.
15. **Snap-back**: an engaging NPC keeps shooting the turret even with the player in view. After 4–8 s, or when
    you shoot it, it returns to you.
16. **Aim height**: NPC rounds don't all hit the floor in front of the turret.
17. **No regressions** with HTR running: HTR's suppression, cover and grenades still work. With HTR 0.4.2's
    perk slowdown on, then off: other perks' cooldowns and energy regen follow HTR, and the turret perk stays
    blocked.
18. **Squad engineer**: in a ground battle, a squad engineer stops, waits about 8 s, and a turret appears that
    shoots enemy soldiers, not the player or the squad.
19. **Companion engineer**: same as 18, for a companion.
20. **Enemy engineer** (`EnemyEngineerChance > 0`): a regular enemy walks to a spot, kneels and deploys.
21. **Frame time**: firefight with 10+ NPCs, 3 turrets and the squad. Per-hook profile over 30 s. No hook above
    `SlowHookMs`, and no stutter on deploy or pack.

---------------------------------------------------------------------------------------------------

## 14. Open questions (for the author)

1. **Keys**: Delete is the default, following the realism set's shared key plan (F6 is the game's quick save).
   Should the vanilla turret perk button also be the deploy/pack button (gamepad support)? Proposed: yes.
2. **Resupply**: when a turret is lost or destroyed, how do you get a new one? A free replacement on the ship or
   station (proposed), at the next level, never, or a credits cost (needs research on money fields)?
3. **Ammo**: unlimited (vanilla), or a few belts per deployment, refilled on resupply?
4. **Destroyed turret**: a silent wreck (proposed), or the vanilla explosion that also hurts people nearby?
5. **Times and weight**: 6 s to deploy, 5 s to pack, 80 % speed and no sprint while carrying. Is the jetpack
   allowed while carrying? Can you leave the turret on the ship, so you move at full speed when you don't
   need it?
6. **Exposure while working**: keep your weapon (but kneeling and unable to move), or holster it?
   *Answered 2026-11-07: holster it, no drawing until done or cancelled (0.2.4).*
7. **Ally engineers**: only the unused `Turretci` squad role, or also a random 10 % of squad soldiers and 15 %
   of companions? Should they ever pack up and follow?
8. **Enemy engineers**: keep vanilla (only some minibosses), or add rare regular enemy engineers?
9. **Scope**: turret first, then barricades. Are trip mines wanted too?
10. **HTR**: give the turret its own caliber in HTR (`turret_light`, about rifle-lethal at 10 rds/s)?
11. **Energy**: should deploying also cost suit energy (for example 20 % of `MaxEnergy`, refilled at HTR 0.4.2's
    slower rate), or only time, as proposed?
12. **Barricades**: the vanilla barricade perk (`Barricde_C`) exists in the game; 0.1.0 leaves it vanilla.
    Convert it next (section 8)?

---------------------------------------------------------------------------------------------------

## Status / next steps (paused 2026-10-31)

**Done (commit 6191f21 and the commit after it):** 0.1.0 implemented and tested in game on 2026-10-30
with HTR 0.4.5. Verified:
- keys: hold Delete toggles on/off, tap deploys / packs / cancels, Shift+Delete stays quiet, and the perk
  button works (no vanilla spawn, no energy spent);
- deploy and pack: kneel + movement lock; placement at `BarricadeLocation`; scale 0.8; `LifeTime` 1e7
  through the class default object;
- combat: the turret kills enemies; enemies turn on it and damage it down to a wreck;
- carrying: pack-up keeps damage; carry speed 375 → 300 and no sprint;
- loss: a turret left behind is lost on a level change;
- allies: squad engineers deploy, with the 2-turret cap.

**Fixed after the first tests:**
- firing detection now uses the ammo count;
- resupply needs `ResupplyMinutes` out of combat (the test map counts as "ship");
- the ally cap counts turrets being set up.

**Frames, mod on:**
- idle: 96 fps, median 10 ms, p99 21 ms, max 26 ms;
- deploy: one 62 ms spike at the first spawn of a session;
- firefight: 87 fps, median 11 ms, p99 23 ms, max 79 ms.

One ~45 ms hitch at the first enemy engagement per session. Every engagement call times at 0 ms, so it is
probably a first-use asset load.

**Unexplained:** one test run froze or closed about 3 s after loading (allies on, no crash dump). The next
allies-on run was stable through a full fight.

**Next steps:**
1. Frame baseline with the mod off: same `te_frames.ps1` run, `te_setup.ps1 -NoMod`. It was interrupted.
   Compare with the numbers above.
2. Optional retests:
   - companion engineers;
   - enemy engineers (`SelectAbility(6)`): test enemies died before `Ready?`; spawn them closer, without
     the Enemy tag;
   - `AmmoBelts` > 0.
3. Publish per `side-session-notes\publish-checklist.md`:
   1. Public repo `SpaceBourne2-TacticalEngineering` with `TacticalEngineering/` (scripts + `enabled.txt`),
      README, CHANGELOG, DESIGN, LICENSE and `docs/banner.png` (v2).
   2. Release v0.1.0 with the lite zip (`SB2\Binaries\Win64\Mods\TacticalEngineering\...`).
   3. Nexus page.
   4. Replace the README's `mods/0` placeholder links.
   5. Ask the user for the final "sim" first.
4. Test harness for the next session: in the scratchpad `tedev\`. It has `te_setup`, `te_launch`,
   `te_run` (a dev runner in TE's own Lua state, test build only), `te_frames`, `te_key` (foreground
   check), `te_stop` and `te_restore`. Never ship the dev runner.

### Retest 2026-10-31 (HTR 0.4.7 installed)

**Backlog C/D features, all pass in game:**
- limited ammo (a 60-round test load ran dry in about 6 s of fire, then the turret stopped);
- refill at the ship once `PlayerInCombat` cleared;
- deploy noise heard by an unaware enemy 14 m behind (it turned);
- turret-fire noise every 1.5 s, heard by enemies 10–20 m away, who then engaged the turret (3 = cap);
- `SB2R_Noise` published (`1,-223873,4352,-174,1500,deploy,100.15`);
- GUI_Cant muted 2.0 → 0.0 during a message, then back to 2.0, with `SB2R_CantVolume` = 2.0;
- damage notices only at thresholds (73 %, 49 %);
- the 3-tap perk-button toggle: on / off / on. While the mod is off, the first tap is the vanilla perk.

**Frames, each run from a fresh launch, same scenario:**

| | mod on | mod not loaded |
|---|---|---|
| idle | 57 fps, median 18 ms, p99 30 ms, max 41 ms | 56 fps, median 18 ms, p99 30 ms, max 37 ms |
| firefight | 52 fps, median 19 ms, p99 38 ms, max 84 ms | 52 fps, median 19 ms, p99 33 ms, max 91 ms |

The only extra spike is 64 ms at the first deploy of a session, the turret's first asset load. No new
periodic spikes.

### Released 0.1.0 (2026-10-31)

- GitHub: https://github.com/hubertdungen/SpaceBourne2-TacticalEngineering (release `v0.1.0`, lite zip).
- Nexus Mods: https://www.nexusmods.com/spacebourne2/mods/10 (Main file 0.1.0, UE4SS 3.0.1 as an external
  requirement, MIT licence as custom permissions).
- The README's `mods/0` placeholder links now point to `mods/10`.

### 0.1.1 (2026-10-31)

On by default (`StartOn = true`), at the user's request ("e aos mods virem já ativos"), and plain F11
refused as the deploy key. A saved `te_state.txt` still wins, so a player who switched 0.1.0 off keeps
it off.

Checked in game on 2026-10-31 (HTR 0.4.8 installed), fresh install with no `te_state.txt`: the mod loads
ON, and a real Delete tap deploys the turret (6 s, then "Turret deployed - 300 rounds"). No errors.

### 0.2.0 test (2026-10-31, HTR 0.4.8 installed, one launch)

Test save: turret perk level 2, barricade perk not learned; set to 3 and 2 with the dev runner.
- `ActiavateBarricate()` with TE on: `BarrierCD` read `true` (pinned), no vanilla wall, energy 108.9 →
  108.9. TE built one in 3.4 s ("3 s"), `Barricde_C` with `LifeTime` 1e7, structure 180.
- Enemy rounds: the shooters' `OnProjectileHit` reports `Barricde_C` / `BarricadeCollision1` when the
  wall is in the line of fire, so it does stop them. 18 hits took it from 180 to 126 (3 each). With the
  structure set to 5, the next hit collapsed it: "half strength" and "collapsed" notices, the actor gone
  (FindAllOf keeps listing it until garbage collection, about 30-45 s).
- Pack: 2.55 s ("3 s"), carried back to 2. One 46 ms player-tick hitch at the pack (the actor's destroy).
- Turret at perk level 3: "Deploying turret - 4 s" (4.2 s), "Turret deployed - 500 rounds".
- Hook cost: "barricade hit" 29 calls in 30 s = 1 ms in a firefight. No errors.
- Found and fixed: on the test map (counted as "ship") the restock refilled right after a build;
  restock now counts barricades still standing.

Changed after that test, at the user's request: perk buttons only (no Delete by default), 3 taps on the
barricade button too, no turret carried without the turret perk, structure in %. Also fixed: switching
TE off now clears `BarrierCD` once, or the vanilla barricade would stay "cooling down".

**Final check of the release build** (same day, second launch, default config):
- "deploy key nil": no key bound; `turretUsable` true (turret perk learned).
- 3 calls of the barricade perk → "Tactical Engineering OFF"; `BarrierCD` false; the vanilla perk then
  works as vanilla (energy 108.9 → 43.6, a wall with `LifeTime` 15 at level 2).
- 3 more → "Tactical Engineering ON", `BarrierCD` pinned again.
- The turret perk call → "Deploying turret - 4 s" → "Turret deployed - 500 rounds". No errors.

**Noise search and perk requirement** (three more launches, HTR 0.4.8):
- Silent Ops off: an unaware enemy 11–14 m behind "heard deploy: alert, searching". Without
  `StopLogic` it walked 1.6 m and turned back; with it, 11 → 7.6 m toward the noise, looked around,
  "search over" after 12 s, back to its routine.
- The user's install has Silent Ops 0.1.0 (no `SilentOps_On`, no turret hooks): TE searched, Silent Ops
  stayed calm. No double alert.
- Silent Ops current build (0.3.0-dev, from its session's branch; installed only for the test, the
  user's 0.1.0 restored and hash-checked): `SilentOps_On` = true, TE heard nothing. Silent Ops: deploy at
  16 m unheard (its radius is 12 m); "heard turret pack at 6 m", meter 0.29 (no look).
- Both perks at level 0: "Requires the Turret perk", "Requires the Barricade perk"; a deployed turret
  can still be packed.

### 0.2.1 (2026-10-31): ally engineers on by default, in-game switch

The user's rule: features on by default and easy to switch, never config-only. Ally engineers were off
because of one unexplained freeze in a 2026-10-30 allies-on test. Since then the Ammo Discipline session
found that the game dies at start-up while Windows is on the lock screen, with no crash report, which
fits that freeze; the next allies-on run, and this one, were stable.

- `T.allies` (state file `allies=on|off`; first start from `Allies.Engineers`, now true). The squad
  hook is always registered; `E.onSquadBattle` / `E.onCompanionThink` read `T.allies`.
- Gesture on the existing perk buttons (no new key): taps within `TripleTapSeconds` (1.5 s). 4 taps =
  ally engineers on / off (HUD "Ally engineers ON/OFF"). 3 taps = the whole mod, decided when the window
  closes, so a fourth tap can still come. Taps 1-2 act as normal presses (deploy, then cancel).
- In game (one launch, chances 1.0 for the test): 4 taps → "Ally engineers OFF", 4 more → "ON"; 3 taps →
  "Tactical Engineering OFF" after the window. In a fight, two squad soldiers each deployed a turret (the
  cap is 2), both active. One 34 ms hitch at the first ally spawn. No errors.

**Turret scale 0.6** (the user's request; was 0.8). `JustShoot` spawns its rounds with
`SpawnProjectileSingleByChannel` at `self.Muzzle:K2_GetComponentLocation()` (read), a component that
follows the actor scale. In game: the muzzle was 96 cm from the root (dz 82) at 0.6 and 160 cm (dz 136)
at 1.0, a ratio of 0.60. The root stayed at the player's feet height (-264), so the base doesn't sink.
The turret fired and killed the enemies; invulnerable enemies then engaged it and their rounds took it
from 140 to 0 in about 4 s (notices at 49 % and 25 %). One launch, no errors.

**Not checked in game:** the real slot press of the barricade perk. The test called
`ActiavateBarricate()` directly; the bytecode shows `UsePerkAtSlot` calls it with no check of its own
(§1.1), the same path the turret perk button uses (verified with the real button in 0.1.0).

Still not tested in game: companion engineers, the rare enemy engineers, the HTR 0.4.8 `turret_light`
caliber, and Silent Ops 0.2 hearing the turret.
### 0.2.2 (2026-11-06, code only, the display was off): bugs 18 and 19

**18, a ghost turret mid-dungeon** (firing effect, no rounds, no damage; TE said there was no turret).
No log of the moment (te.log had only load lines). Most likely chain, from the Blueprint (read):
`JustShoot` switches on the muzzle flash and tracer each round, and only `StopShoot` switches them off;
vanilla calls it only when the target is a dead `Q1_Shooter_AI`. TE declared the turret LOST after 3 s
without a tick (a floor change or streaming can do that) but left the actor standing, and it stayed
registered. A press then said "No turret". Fix:
- `T.silence(t)`: `ActiveNow = false` + `StopShoot()`. Used for stopped / empty turrets too, now also
  when only `Shooting` is still true.
- `checkLost`: the turret leaves the registry; `T.lostEntry` keeps its ammo and damage. If the actor still
  exists (`U.find(path)`, one lookup): within 30 m it is recovered (removed, the player carries it, ammo
  and damage kept); farther it is silenced and removed, and lost.
- `onOrphanTick`: a ticking perk turret TE doesn't know, while TE is on, is silenced. If the player has a
  turret it is removed; if theirs was lost or destroyed, it waits.
- A press with no turret (LOST / DESTROYED) recovers a perk turret TE doesn't know within 2× PackRange:
  first the ticking orphans, then one `FindAllOf("Player_PerkTurret_C")` (~50 ms, only on that press).

**19, ammo kept on pack**: it already was (`finishPack` copies the turret's count; deploy gives it back;
the state file keeps it, e.g. `ammo=400` in the user's file). The pack message now shows it.

**Tested in game 2026-11-06** (test slot, two launches, all passed):
1. Ammo: deployed with 400, it fired 6 rounds at test enemies, packed: "Turret packed - you are carrying it
   (394 rounds)", state file `ammo=394`; deployed again: "Turret deployed - 394 rounds", damage kept (117/120).
2. Ghost near: ticks stopped from the dev runner the moment it was shooting (`Shooting` and the muzzle flash
   on). 3 s later: "Your turret stopped responding - recovered, you are carrying it (386 rounds)", damage
   kept, the actor removed. Ghost far: moved 40 m, ticks stopped: 3 s later "Your turret was left behind -
   lost", the actor removed.
3. Orphan: a press while LOST with nothing near: "No turret - a new one at your ship in 5 min". An
   unregistered perk turret spawned next to the player while LOST: "not known to TE (state LOST): silenced",
   no round fired in 10 s; a press: "Turret recovered - you are carrying it (386 rounds)". While CARRIED a
   new one is removed on its first tick. While LOST, one with its tick off is found by the press
   (`FindAllOf`) and recovered.
4. Out of ammo (3 rounds left): "Your turret is out of ammo", `ActiveNow` false, flash and tracer off, no
   more rounds (belt count frozen). `Shooting` stays true: `StopShoot` is a DoOnce that reopens only when
   the tick sees `ActiveNow`, and `JustShoot` sets `Shooting` each round. 0.2.2 first re-ran `T.silence`
   every tick for that flag (turret tick 0.065 ms instead of ~0.03); now it stops again only when the
   turret is switched on or fires (`e.quiet`, same for orphans). Retested after the change.
- At a ship or station, out of combat, a carried turret is refilled to full (older feature): forcing LOST
  in the test showed 400 again for that reason, not a bug.

### 0.2.3 (2026-11-06): gametick

Made and published from the public repo by the htr-fixes session (no LoopAsync / ExecuteWithDelay; the
hook poll and the unmute run from the shared `te/gametick.lua`, pumped once per frame). Copied back here
unchanged before 0.2.4.

### 0.2.4 (2026-11-08): weapon away while working, ally engineers back on

The user's requests (2026-11-07): "por predefinição liga os engenheiros no turrets" and "quando se monta
turrets não se deve poder ter armas na mão, elas fazem holster".

**Ally engineers.** `Allies.Engineers` was already true, but `T.save()` wrote `allies=on|off` on every
save, so the user's `allies=off` (seen in their `te_state.txt`; no toggle in their te.log) outlived the
default change. Now only an explicit 4-tap choice is stored, as `alliesChoice`; the old `allies` key is
ignored and dropped at the next save. Everyone starts with them on once.

**Weapon away while working** (read from `Q1_Character`'s ubergraph, TFP's `kdec` dump; not committed):
- Weapon in hand: `OverlayState` 6 = pistol (slot 0), 5 = rifle (slot 1 or 2), 0 = none. Slots 1 and 2
  share 5; `RefreshAllWeapons` hides the body mesh of the weapon in hand (`PistolSM`, `Slot_1_SKM`,
  `Slot_2_SKM`, `MiscMesh`), so the hidden one names the slot.
- `W_1` / `W_2` / `W_3` are custom events that jump into the key 1 / 2 / 3 handlers (the switch button's
  tap calls them). The key of the weapon in hand puts it away: the pistol at once
  (`GameBuilder:UnEquipHandWeaponFromHand(0, true)`, `RemoveAllWeapons(true)`, `BPI_Set_OverlayState(0)`),
  a rifle with `RifleToBackMontage` and the same calls on its `State` notify. Any other key draws.
- Each handler first returns if `SwitchingWeapon` is true (the game sets it while drawing / holstering and
  clears it from a 2 s delay). The perk-button dispatcher never reads it. So holding `SwitchingWeapon`
  true blocks keys 1/2/3 and the switch button's tap, and leaves the perk buttons (cancel, 3/4 taps) free.
- `AtWeaponRestrictedArea` (what the game uses when you faint, and in cyborg mode) also blocks the keys,
  but the perk dispatcher checks it too: a tap couldn't cancel. Not used.
- Melee (`MeleeAttackOn?`) checks neither flag: a swing cancels the work ("interrupted").
- The misc beam (slot 3) has no `W_` event: it is put away at once with the calls above
  (`FindFirstOf("God_GameBuilder")`); so is any weapon still in hand after two key tries 1.5 s apart.

`stepWeapon` runs every player step (0.1 s), also while TE is off: busy (turret or barricade work) = put
away and hold the lock; not busy = release once, then draw the slot you had (`W_n` again) when nothing is
in hand and the game isn't switching, or give up after 3 s (you drew one yourself). A new pawn drops it.

**Test plan (tonight, test slot):**
1. Allies: the user's `te_state.txt` has `allies=off`: after load the status says `allies=true`; 4 taps:
   "Ally engineers OFF", state file `alliesChoice=off`, restart: still off; 4 taps back on.
2. Rifle in hand, turret perk button: the rifle goes to the back with its animation, keys 1/2/3 and the
   switch button do nothing while kneeling; done: the rifle comes back. Log: "weapon slot 1 put away
   (try 1)", "weapon slot 1 drawn again".
3. Same with the pistol (instant), and with nothing in hand (nothing drawn after).
4. Cancel with a tap mid-setup: weapon back. Pack up: same. Barricade build: same.
5. Melee swing while kneeling: "Turret: interrupted", weapon back.
6. Draw attempts during the work: nothing, and after the work the keys work normally (no stuck lock).
7. Frame time of the player step with the lock held (profile).

**Tested in game 2026-11-08 03:20-03:29** (test slot, one launch, HTR 0.4.14 + TE + dev console, all
passed; the dev runner now runs from TE's gametick instead of LoopAsync):
1. State file with the old `allies=off`: `allies=true`, `alliesChoice=nil`. 4 taps (`toggleReq`): "Ally
   engineers OFF", file `alliesChoice=off` and no `allies=` line; again: `alliesChoice=on`.
2. Rifle (`W_2`, overlay 5, `Slot_1_SKM` hidden), turret deploy: "weapon slot 1 put away (try 1)"; overlay
   0 about 1.5 s later (the animation), `SwitchingWeapon` true; `W_2` and `W_1` during the work: overlay
   stays 0. Turret up: "weapon slot 1 drawn again", overlay 5, lock released.
3. Pistol (overlay 6, `PistolSM` hidden), pack up: overlay 0 within 0.3 s; `W_2` blocked; pistol back after.
4. Empty hands, deploy: lock held, nothing drawn after, `SwitchingWeapon` false again.
5. Rifle, pack, tap at 3 s: "Turret: cancelled", rifle back.
6. Rifle, pack, `MeleeAttackOn?` set: "Turret: interrupted", rifle back.
7. Barricades (perk set to 2 for the test save): build, pack, a tap to cancel ("Barricade: cancelled"),
   melee ("Barricade: interrupted"): the rifle away during the work each time and back after.
8. After all: `W_2` holsters and draws normally.
9. Cost: player tick ~0.02 ms per frame idle, ~0.03-0.05 ms while working (the lock step runs every
   0.1 s). Hitches seen: 24 ms on the first deploy and 57 ms on a barricade build, both known (section
   "Known limits" in the README).
- Screenshot `docs/holster.jpg`: packing up a barricade, kneeling, both weapons on the back.

**UE4SS 3.0.1 Lua leak audit (2026-11-08, htr-fixes' notes `ue4ss-301-lua-leaks-2026-11-08.md`).** TE
calls no UFunction with out parameters (no `K2_Set*` / `K2_Add*` with a hit result, no traces, view
points, screen projection or bounds), per frame or otherwise. `K2_SetFocus` / `K2_SetFocalPoint`
(targeting.lua) take inputs only and run per engagement, not per frame. The 0.2.4 calls (`W_1..3`,
`IsVisible`, `UnEquipHandWeaponFromHand`, `RemoveAllWeapons`, `BPI_Set_OverlayState`) have no out
parameters either. Open, as in HTR (same design): `hooks.lua` registers a group's hooks again when the
class reappears at a new address, without `UnregisterHook` of the old pair, so the old callback may
stay and both fire. For TE that matters only for classes that unload (squad soldiers, shooters);
not changed here, to be fixed the same way across the set.