--[[
  Tactical Engineering (TE) for SpaceBourne 2 - realistic deployable turrets.
  UE4SS Lua mod. Entry point: loads settings, wires hooks and the key, nothing else.

  Layout:
    config.lua        user settings
    te/gamedefs.lua   every game-internal name (the only file to fix after a game patch)
    te/util.lua       helpers (logging, safe property access, keys, HUD messages, state file)
    te/hooks.lua      safe lazy hook registration (same design as HTR's)
    te/turret.lua     the player's turret: carry / deploy / pack / lose, spawning, damage, carry weight,
                      perk-level bonuses
    te/barricade.lua  the barricade perk as field engineering: build / pack / carry / restock / wear down
    te/targeting.lua  enemies notice turrets and shoot them
    te/allies.lua     ally engineers, rare enemy engineers, allies vs enemy mini-turrets
  Design notes and the test log: DESIGN.md in the repository.
]]

local VERSION = "0.2.4"

local U = require("te.util")

-- Settings -------------------------------------------------------------------------
local defaults = {
    Enabled = true, StartOn = true, ToggleHoldSeconds = 2.0, TripleTapSeconds = 1.5, DeployKey = "",
    UseTurretPerkButton = true, BlockVanillaTurretPerk = true,
    Player = { DeploySeconds = 6.0, PackSeconds = 5.0, PackRange = 300, CarrySpeed = 0.8, CarryNoSprint = true,
        Resupply = "ship", ResupplyMinutes = 5, HolsterWhileWorking = true },
    Turret = { Scale = 0.6, Structure = 100, DestroyedEffect = "wreck", Rounds = 300,
        HitCost = { npc_rifle = 3, npc_boss = 4, npc_heavy = 8, npc_sniper = 12, npc_melee = 6,
            explosion = 40, player = 3, ally = 3, other = 3 } },
    Levels = { SetupFaster = 0.15, ExtraRounds = 100, ExtraStructure = 0.20 },
    Barricades = { Enabled = true, BuildSeconds = 4.0, PackSeconds = 3.0, PackRange = 300, Carried = 1,
        ExtraPerLevel = 1, Structure = 150 },
    Enemies = { AttackTurrets = true, AwareRadius = 2500, TargetChance = 0.6, MaxAttackers = 3,
        FocusSeconds = { 4, 8 }, SimulatedHits = false, DamageEnemyMiniTurrets = true, EngineerChance = 0.0 },
    Allies = { Enabled = true, Engineers = true, TurretciAreEngineers = true, SquadEngineerChance = 0.10,
        CompanionEngineerChance = 0.15, DeploySeconds = 8.0, MaxAllyTurrets = 2 },
    Noise = { WorkRadius = 1500, FireRadius = 6000, AlertEnemies = true, Search = true, SearchRadius = 400,
        SearchSeconds = 12 },
    Messages = { Quiet = true },
    Debug = { Log = false, SlowHookMs = 8, TestCommands = false },
}

-- Fill missing keys from defaults (nested tables too, except plain lists).
local function fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        elseif type(v) == "table" and type(dst[k]) == "table" and k ~= "FocusSeconds" then
            fill(dst[k], v)
        end
    end
end

local okCfg, cfg = pcall(require, "config")
if not okCfg or type(cfg) ~= "table" then
    U.warn("config.lua could not be read (" .. tostring(cfg) .. "); using defaults")
    cfg = {}
end
fill(cfg, defaults)
U.Verbose = cfg.Debug.Log == true
U.Quiet = cfg.Messages.Quiet ~= false

if cfg.Enabled == false then
    U.warn("Tactical Engineering " .. VERSION .. " loaded, disabled in config.lua (Enabled = false)")
    return
end

TE = { version = VERSION, cfg = cfg }

local H = require("te.hooks")
local GT = require("te.gametick") -- timed work on the game thread (no LoopAsync: UE4SS crash, 0.2.3)
GT.log = function(msg) U.warn(msg) end
H.SLOW = cfg.Debug.SlowHookMs / 1000
local G = require("te.gamedefs")
local T = require("te.turret")
local A = require("te.targeting")
local E = require("te.allies")
T.init(cfg)
E.init(cfg, T)
A.init(cfg, T, E)
local B = nil
if cfg.Barricades.Enabled then
    B = require("te.barricade")
    B.init(cfg, T)
end

U.warn(string.format("=== Tactical Engineering %s loaded: %s, turret %s ===", VERSION, T.on and "ON" or "OFF", T.state))

-- Hooks (all post-hooks on Blueprint functions; each returns at once while TE is off) --------
-- player
-- The player tick also pumps the timed work (gametick.lua), on the game thread.
H.add(G.Fn.PlayerTick, T.onPlayerTick, "player tick", nil, function() GT.pump("foot") end)
if cfg.BlockVanillaTurretPerk or B then H.add(G.Fn.Regenerators, T.onRegenerators, "vanilla perk block") end
if B then
    H.add(G.Fn.BarricadePerk, B.onPerkButton, "barricade perk button")
    for i, path in ipairs(G.ShooterProjectileHits) do H.add(path, B.onShooterHit, "barricade hit " .. i) end
end
if cfg.UseTurretPerkButton then H.add(G.Fn.SpawnTurretsPerk, T.onPerkButton, "turret perk button") end
if cfg.Player.CarrySpeed < 1 then H.add(G.Fn.MoveSettings, T.onMoveSettings, "carry speed") end
if cfg.Player.CarryNoSprint then H.add(G.Fn.CanSprint, T.onCanSprint, "carry no sprint") end
-- turrets
H.add(G.Fn.TurretBeginPlay, T.onTurretBeginPlay, "turret begin play")
H.add(G.Fn.TurretTick, T.onTurretTick, "turret tick")
H.add(G.Fn.TurretDamage, T.onTurretDamage, "turret damage")
-- shooters (enemies and companions)
if cfg.Enemies.AttackTurrets or cfg.Allies.Enabled ~= false or cfg.Enemies.EngineerChance > 0 or cfg.Noise.AlertEnemies then
    H.add(G.Fn.NpcThink, A.onNpcThink, "NPC think")
end
if cfg.Enemies.AttackTurrets then
    H.add(G.Fn.NpcPointDamage, A.onNpcPointDamage, "NPC hit")
    H.add(G.Fn.NpcSightDetected, A.onNpcEye, "NPC sight detected")
    H.add(G.Fn.NpcSightUpdated, A.onNpcEye, "NPC sight updated")
    H.add(G.Fn.NpcRifleDetected, A.onNpcEye, "NPC rifle detected")
    H.add(G.Fn.NpcRifleUpdated, A.onNpcEye, "NPC rifle updated")
    if cfg.Enemies.SimulatedHits then H.add(G.Fn.NpcJustShoot, A.onNpcJustShoot, "NPC simulated hits") end
end
if cfg.Enemies.DamageEnemyMiniTurrets then H.add(G.Fn.MiniTurretDamage, E.onMiniTurretDamage, "mini-turret damage") end
-- squad soldiers: often not loaded, so look for the class at most every 60 s (+ on arrival)
-- (registered even while ally engineers are switched off: 4 quick perk-button taps switch them on)
if cfg.Allies.Enabled ~= false then H.add(G.Fn.SquadBattle, E.onSquadBattle, "squad engineer", 60) end

-- Development commands (Debug.TestCommands): one per line in te_cmd.txt, read once a second.
local CMD_FILE = U.Dir .. "te_cmd.txt"
local function testCommands()
    local f = io.open(CMD_FILE, "r")
    if not f then return end
    local text = f:read("a") or ""
    f:close()
    os.remove(CMD_FILE)
    for line in text:gmatch("[^\r\n]+") do
        local cmd = line:match("^%s*(%S+)")
        if cmd == "press" then
            T.pressed = true
        elseif cmd == "bpress" and B then
            B.pressed = true
        elseif cmd == "toggle" or cmd == "on" or cmd == "off" then
            T.toggleReq = cmd
        elseif cmd == "status" then
            U.warn("status: " .. T.status() .. " | " .. A.status() .. (B and (" | " .. B.status()) or ""))
        elseif cmd == "profile" then
            U.warn("profile: " .. H.profile())
        end
    end
end

-- Hook poll ----------------------------------------------------------------------------
-- On the game thread, pumped by the player tick (gametick.lua). Until 0.2.2 this was LoopAsync +
-- ExecuteInGameThread: from UE4SS's async thread that writes a map all mods share without a lock,
-- and two mods at once crashed the game (UE4SS.dll+0x87c104). After each load or possession
-- (ClientRestart) the player tick is looked for right away, so the pump starts by itself.
local lastStatus, profileAt = "", os.clock() + 30
GT.boot(function() H.prime(G.Fn.PlayerTick) end)
GT.every(1.0, function(t0)
    local ok, err = pcall(function()
        if T.arrived then T.arrived = false; H.wake() end
        H.poll(t0)
        if cfg.Debug.TestCommands then testCommands() end
    end)
    if not ok then U.warn("poll: " .. tostring(err)) end
    if t0 > profileAt then
        profileAt = t0 + 30
        local prof = H.profile()
        if U.Verbose and prof ~= "" then U.log("profile 30 s: " .. prof .. " | timed work: " .. GT.report()) end
    end
    local on, off = H.status()
    local s = string.format("hooks active %d, waiting %d", on, off)
    if s ~= lastStatus then lastStatus = s; U.log(s) end
end)

-- Deploy key ------------------------------------------------------------------------------
-- Same rules as HTR 0.4.4 and the realism set's shared key plan:
--   * a UE4SS key name ("DEL", "F11"...), optionally with Shift: "Shift+DEL";
--   * keys the game uses itself (F1-F6, F8 quick load, F10, F11 fullscreen, F12) are refused
--     without a modifier and the default (Delete) is used instead;
--   * a plain key stays quiet while Shift / Ctrl / Alt is held, so Shift+Delete stays free.
local GAME_KEYS = { F1 = 1, F2 = 1, F3 = 1, F4 = 1, F5 = 1, F6 = 1, F8 = 1, F10 = 1, F11 = 1, F12 = 1 }
local KEY_ALIAS = { INSERT = "INS", DELETE = "DEL", PAGEDOWN = "PAGE_DOWN", PAGEUP = "PAGE_UP", ESC = "ESCAPE" }
local MODS = { CTRL = "CONTROL", CONTROL = "CONTROL", SHIFT = "SHIFT", ALT = "ALT" }
local function parseKey(spec)
    if type(spec) ~= "string" or spec == "" then return nil end
    local mods, key = {}, nil
    for part in spec:upper():gsub("%s", ""):gmatch("[^+]+") do
        if MODS[part] then mods[#mods + 1] = MODS[part] else key = KEY_ALIAS[part] or part end
    end
    if not (key and Key and Key[key]) then return nil end
    if #mods == 0 and GAME_KEYS[key] then return nil, "the game uses " .. key end
    return key, mods
end
local function bindKey(spec, fn, fallback, what)
    local key, mods = parseKey(spec)
    if not key and fallback and spec ~= "" then
        U.warn(string.format("%s key '%s' not usable (%s); using %s", what, tostring(spec), tostring(mods or "unknown key"), fallback))
        key, mods = parseKey(fallback)
    end
    if not key then return nil end
    if #mods > 0 and ModifierKey then
        local list = {}
        for _, m in ipairs(mods) do list[#list + 1] = ModifierKey[m] end
        RegisterKeyBind(Key[key], list, function() ExecuteInGameThread(fn) end)
    else
        RegisterKeyBind(Key[key], function()
            ExecuteInGameThread(function() if not U.modifierDown() then fn() end end)
        end)
    end
    return key
end
local key = bindKey(cfg.DeployKey, T.onKey, "DEL", "deploy")
T.keyBound = key ~= nil
T.keyName = U.unrealKey(key)
T.keyLabel = U.keyLabel(key)
U.log("deploy key " .. tostring(key) .. " (hold check: " .. tostring(T.keyName) .. ")")
