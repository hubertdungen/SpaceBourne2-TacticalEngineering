--[[
  Tactical Engineering (TE) for SpaceBourne 2
  ===========================================
  USER SETTINGS. Edit with any text editor, then restart the game.
  Everything here is optional: delete a line and the default is used.
]]

return {
    -- false = the mod does nothing at all (not even the on/off key).
    Enabled = true,

    -- Tactical Engineering starts ON. While off, the vanilla perks work as usual. false = start off.
    StartOn = true,
    -- Tap the turret or barricade perk button 3 times within this many seconds to switch
    -- Tactical Engineering off / on (remembered between sessions). Works on keyboard and gamepad.
    TripleTapSeconds = 1.5,

    -- Controls: the game's own perk buttons, wherever you put the perks (action slots).
    -- Turret perk button: deploy your turret, pack it up (next to it) or cancel.
    -- Barricade perk button: build a barricade, pack one up (next to it) or cancel.
    -- Each needs its perk learned and in an action slot, as in vanilla.
    UseTurretPerkButton = true,

    -- Optional extra key for the turret (still needs the turret perk learned). "" = none (default).
    -- Any UE4SS key name, e.g. "DEL" (Delete, unbound in the game), optionally with Shift: "Shift+DEL".
    -- Tap: same as the turret perk button; hold ToggleHoldSeconds: Tactical Engineering on / off.
    -- Keys the game uses itself (F1-F6, F8 quick load, F10, F11 fullscreen, F12) are refused without a
    -- modifier. The plain key does nothing while Shift, Ctrl or Alt is held (realism set key plan:
    -- Shift+Delete belongs to Gear Without Levels).
    DeployKey = "",
    ToggleHoldSeconds = 2.0,

    -- While Tactical Engineering is on, the vanilla instant turret perk is switched off
    -- (it would explode every turret of its class, including yours). Leave this on.
    BlockVanillaTurretPerk = true,

    Player = {
        DeploySeconds       = 6.0,  -- kneeling, unable to move, to set the turret up
        PackSeconds         = 5.0,  -- kneeling to tear it down
        PackRange           = 300,  -- cm: how close you must be to pack it up
        CarrySpeed          = 0.8,  -- walk/run speed while carrying the packed turret (1.0 = normal)
        CarryNoSprint       = true, -- no sprinting while carrying it
        -- A lost (left behind) or destroyed turret is replaced:
        --   "ship"  at your ship (in space) or a station, out of combat, at least
        --           ResupplyMinutes after the loss (real minutes, kept across restarts)
        --   "level" at the next level
        --   "never" not replaced
        Resupply            = "ship",
        ResupplyMinutes     = 5,
    },

    Turret = {
        Scale           = 0.6,     -- size vs the vanilla perk turret (rounds still leave from its muzzle)
        Structure       = 100,     -- durability points
        -- Structure lost per hit, by who fired. Small arms chip it; explosives and heavy weapons wreck it.
        HitCost = {
            npc_rifle = 3, npc_boss = 4, npc_heavy = 8, npc_sniper = 12, npc_melee = 6,
            explosion = 40, player = 3, ally = 3, other = 3,
        },
        DestroyedEffect = "wreck", -- "wreck": stops working and stays; "explode": vanilla blast (hurts anyone within 5 m)
        -- Ammo the turret carries (rounds; it fires 10/s in belts with 3-5 s reloads). It stays with
        -- the turret when you pack it, and is refilled from your ship (in space or on a station,
        -- out of combat) while you carry the turret. 0 = unlimited (vanilla).
        Rounds          = 300,
    },

    -- Perk levels: each level of the game's turret perk above 1 (and of the barricade perk, for
    -- barricades) gives a small, practical edge. Level 3 = two steps. 0 = no bonus.
    Levels = {
        SetupFaster    = 0.15, -- deploy / pack / build time -15 % per step (6 s -> 5.1 s -> 4.2 s)
        ExtraRounds    = 100,  -- turret rounds +100 per step (300 -> 400 -> 500)
        ExtraStructure = 0.20, -- turret and barricade structure +20 % per step
    },

    -- Barricades: the game's barricade perk (an energy-shield wall) as field engineering.
    -- Its perk button builds one where vanilla puts it, or packs up your nearest one.
    -- Needs the barricade perk learned and in an action slot.
    Barricades = {
        Enabled       = true,
        BuildSeconds  = 4.0,  -- kneeling, can't move
        PackSeconds   = 3.0,
        PackRange     = 300,  -- cm
        Carried       = 1,    -- barricades you carry at perk level 1 ...
        ExtraPerLevel = 1,    -- ... plus this per level above 1. Restocked at your ship, out of combat.
        Structure     = 150,  -- enemy rounds wear it down (Turret.HitCost); at 0 it collapses
    },

    -- Noise: setting up / packing up (turret or barricade) is metal work that nearby enemies hear;
    -- a firing turret is heard much farther. Unaware enemies in range go on alert (the game's own
    -- alert, so HTR's alert sight range applies) and come to search around the noise.
    -- With Silent Ops on, Silent Ops handles all of this with its own suspicion -> search -> alert:
    -- the events are shared with it as "SB2R_Noise".
    Noise = {
        WorkRadius   = 1500, -- cm
        FireRadius   = 6000, -- cm
        AlertEnemies = true,
        Search       = true, -- alerted enemies walk to a point near the noise
        SearchRadius = 400,  -- cm around the noise
        SearchSeconds = 12,  -- then they go back to their own behaviour (still alert)
    },

    Enemies = {
        AttackTurrets   = true,    -- enemies notice turrets that shoot near them and fire at them
        AwareRadius     = 2500,    -- cm: a firing turret is noticed within this distance
        TargetChance    = 0.6,     -- per second, for an aware enemy
        MaxAttackers    = 3,       -- enemies shooting one turret at the same time
        FocusSeconds    = { 4, 8 },-- how long an enemy keeps shooting the turret before re-assessing
        SimulatedHits   = false,   -- only if NPC rounds pass through turrets: roll hits by distance
        DamageEnemyMiniTurrets = true, -- your companions, squad and turrets can destroy enemy mini-turrets
        EngineerChance  = 0.0,     -- chance a regular enemy deploys a mini-turret (0 = vanilla: some minibosses only)
    },

    Allies = {
        Engineers               = false, -- some squad soldiers / companions carry and deploy a turret
        TurretciAreEngineers    = true,  -- squad soldiers with the game's unused "Turretci" role always are
        SquadEngineerChance     = 0.10,
        CompanionEngineerChance = 0.15,
        DeploySeconds           = 8.0,
        MaxAllyTurrets          = 2,     -- per level
    },

    -- HUD messages use the game's warning, which plays an alarm sound. Quiet = mute that sound
    -- for 2 s around Tactical Engineering's own messages (the game's own warnings keep it).
    Messages = { Quiet = true },

    Debug = {
        Log          = false, -- write TacticalEngineering\te.log (errors are always written)
        SlowHookMs   = 8,     -- TE code slower than this is reported in te.log
        TestCommands = false, -- development: run commands from te_cmd.txt (press, toggle, status)
    },
}
