--[[
  Tactical Engineering (TE) for SpaceBourne 2
  ===========================================
  USER SETTINGS. Edit with any text editor, then restart the game.
  Everything here is optional: delete a line and the default is used.
]]

return {
    -- false = the mod does nothing at all (not even the on/off key).
    Enabled = true,

    -- Tactical Engineering starts ON. In game, on foot, HOLD the deploy key for
    -- ToggleHoldSeconds to switch it off or on (remembered between sessions).
    -- While off, the vanilla turret perk works as usual. false = start off.
    StartOn = true,
    ToggleHoldSeconds = 2.0,
    -- Gamepad: tap the turret perk button 3 times within this many seconds to switch on / off.
    TripleTapSeconds = 1.5,

    -- Deploy key. Tap: deploy your turret, pack it up (when you are next to it) or cancel.
    -- Any UE4SS key name (DEL = Delete, F11, NUM_ZERO, ...), optionally with Shift: "Shift+DEL".
    -- "" = no key. Delete is unbound in the game. Keys the game uses itself (F1-F6, F8 quick load,
    -- F10, F11 fullscreen, F12) are refused without a modifier. The plain key does nothing while Shift, Ctrl or
    -- Alt is held, so Shift+Delete stays free for other mods (realism set key plan).
    DeployKey = "DEL",

    -- The vanilla turret perk's button also deploys / packs (works with a gamepad).
    -- Needs the turret perk learned and placed in an action slot.
    UseTurretPerkButton = true,

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
        Scale           = 0.8,     -- size vs the vanilla perk turret
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

    -- Noise: setting up / packing up is metal work that nearby enemies hear; a firing turret is
    -- heard much farther. Unaware enemies in range turn to the noise (the game's own alert).
    -- The events are also shared with other mods (Silent Ops) as "SB2R_Noise".
    Noise = {
        WorkRadius   = 1500, -- cm
        FireRadius   = 6000, -- cm
        AlertEnemies = true,
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
