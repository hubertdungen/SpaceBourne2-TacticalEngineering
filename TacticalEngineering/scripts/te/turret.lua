--[[
  The player's turret (carry / deploy / pack / lose), turret spawning, turret damage,
  carry slowdown, and the turret registry shared with targeting.lua and allies.lua.
  See DESIGN.md sections 3-5.

  Tested in game 2026-10-30 (see DESIGN.md section 13).

  Object safety: no UObject is stored. A turret is registered by address with plain values
  (path, position, structure, clocks). Actions on a turret are queued and run inside that
  turret's own ReceiveTick hook, where the object is alive; or found again by path while
  its tick heartbeat is fresh (a successful StaticFindObject costs ~0 ms).
]]

local U = require("te.util")
local G = require("te.gamedefs")
local P = G.P

local T = {
    cfg = nil,
    on = false,            -- Tactical Engineering switched on (hold the deploy key); remembered
    hold = nil,            -- os.clock when the deploy key went down (tap vs hold)
    holdLock = false,      -- a hold just toggled: ignore the key until it is released
    keyName = nil,         -- the deploy key's Unreal name, for IsInputKeyDown
    toggleReq = nil,       -- "toggle" / "on" / "off" from a test command; handled with a live pawn
    state = "CARRIED",     -- CARRIED, DEPLOYING, DEPLOYED, PACKING, LOST, DESTROYED
    structure = 100,       -- the player's turret structure in % of its maximum, kept while carried
    turrets = {},          -- [address] = entry, see register()
    playerAddr = nil,
    playerCheckAt = 0,
    playerTickAt = -1e9,   -- os.clock of the player's last tick (pause / hitch detection)
    nextStep = 0, nextSlow = 0,
    pressed = false,       -- key or perk button; handled on the next player tick (live pawn)
    work = nil,            -- { kind = "deploy" | "pack", pawn, t0, duration, X, Y, Z, nextMsg, turret }
    lastPos = nil,
    levelId = 1,           -- bumped on arrival somewhere new (allies deploy once per level)
    arrived = false,       -- read by main.lua to wake the hook poller
    spawning = false,
    ammo = 0,              -- rounds left for the player's turret (Turret.Rounds; 0 there = unlimited)
    noise = {},            -- recent noise events { id, X, Y, Z, radius, kind, t, source }
    noiseId = 0,
    taps = {},             -- perk-button tap times (3 quick taps = on/off)
    keyBound = false,      -- an extra deploy key is set (DeployKey)
    turretUsable = false,  -- the turret perk is learned (refreshed every second)
    B = nil,               -- barricade.lua, when barricades are enabled
    extra = {},            -- more fields for the state file (barricades)
    loaded = {},           -- the state file as read at start
    orphans = {},          -- [address] = { path, X, Y, Z, lastTick }: perk turrets TE doesn't know (leftovers)
    lostEntry = nil,       -- { ammo, structure } of the player's turret when it was declared lost
}
local RECOVER_RANGE = 3000 -- cm: a turret that stops responding this close to you is recovered, not lost
local STATE_FILE = "te_state.txt"
local KEEP = { CARRIED = true, LOST = true, DESTROYED = true }

local function cfg() return T.cfg end

-- Perk levels ----------------------------------------------------------------------------
-- Bonus steps from a perk's level: 0 at level 1 (or not learned), 1 at level 2, 2 at level 3.
function T.levelStep(lv)
    return math.max(0, math.min(2, math.floor((tonumber(lv) or 0) - 1)))
end

function T.perkLevel(p, perk)
    local lv = 0
    pcall(function() lv = p[perk][P.PerkLevel] end)
    return tonumber(lv) or 0
end

function T.turretStep(p) return T.levelStep(T.perkLevel(p, P.PerkTurret)) end

-- Setup time shortened by Levels.SetupFaster per step.
function T.faster(seconds, step)
    return seconds * math.max(0.3, 1 - (cfg().Levels.SetupFaster or 0) * step)
end

-- Rounds the player's turret holds (0 = unlimited) and its structure, with the perk level.
function T.maxRounds(p)
    local r = cfg().Turret.Rounds
    if r <= 0 then return 0 end
    return r + (cfg().Levels.ExtraRounds or 0) * T.turretStep(p)
end

function T.maxStructure(p)
    return cfg().Turret.Structure * (1 + (cfg().Levels.ExtraStructure or 0) * T.turretStep(p))
end

-- State ------------------------------------------------------------------------------
function T.init(c)
    T.cfg = c
    local s = U.loadState(STATE_FILE)
    T.loaded = s
    if s.on ~= nil then T.on = (s.on == "on") else T.on = c.StartOn == true end
    if s.allies ~= nil then T.allies = (s.allies == "on") else T.allies = c.Allies.Engineers ~= false end
    T.structure = math.min(100, tonumber(s.structure) or 100) -- % (0.1.x stored points out of 100: the same)
    T.lostAt = tonumber(s.lostAt) or 0
    T.ammo = tonumber(s.ammo) or c.Turret.Rounds
    if KEEP[s.state or ""] then
        T.state = s.state
    elseif s.state then
        T.state = "LOST" -- the game closed while the turret was deployed: it stayed in that level
    else
        T.state = "CARRIED" -- first run: you own one turret
    end
    U.log("player turret state at start: " .. T.state .. ", structure " .. tostring(T.structure))
end

function T.save()
    local s = { on = T.on and "on" or "off", allies = T.allies and "on" or "off", state = T.state,
        structure = math.floor(T.structure + 0.5),
        lostAt = T.lostAt or 0, ammo = math.floor(T.ammo or 0) }
    for k, v in pairs(T.extra) do s[k] = v end
    U.saveState(STATE_FILE, s)
end

function T.setState(s)
    if T.state == s then return end
    U.log("state " .. T.state .. " -> " .. s)
    if (s == "LOST" or s == "DESTROYED") and T.state ~= "LOST" and T.state ~= "DESTROYED" then
        T.lostAt = os.time() -- real time: the resupply wait survives restarts
    end
    T.state = s
    T.save()
end

-- Registry ---------------------------------------------------------------------------
local function register(actor, kind, owner, loc)
    local a = U.addr(actor)
    if not a then return nil end
    T.turrets[a] = {
        kind = kind, owner = owner, path = U.path(actor),
        structure = cfg().Turret.Structure, max = cfg().Turret.Structure,
        X = loc.X, Y = loc.Y, Z = loc.Z,
        lastTick = os.clock(), firedAt = -1e9, hitAt = -1e9, noticeAt = -1e9, noiseAt = -1e9,
        rounds = 0, dead = false, queue = {}, levelId = T.levelId,
        ammo = cfg().Turret.Rounds, -- rounds left (0 in config = unlimited); set by the caller for the player's
        notice = 100,               -- last damage notice threshold (%)
    }
    return a
end

-- Noise ------------------------------------------------------------------------------------
-- Recent noise events, for the vanilla alert (targeting.lua) and other mods (Silent Ops) through
-- the UE4SS shared variable "SB2R_Noise": "id,x,y,z,radius_cm,kind,time;..." (last ~2 s).
function T.makeNoise(pos, radius, kind, source)
    if not pos or not radius or radius <= 0 then return end
    local now = os.clock()
    T.noiseId = T.noiseId + 1
    T.noise[#T.noise + 1] = { id = T.noiseId, X = pos.X, Y = pos.Y, Z = pos.Z, radius = radius, kind = kind,
        t = now, source = source }
    local keep, parts = {}, {}
    for _, n in ipairs(T.noise) do
        if now - n.t < 2.0 then
            keep[#keep + 1] = n
            parts[#parts + 1] = string.format("%d,%.0f,%.0f,%.0f,%.0f,%s,%.2f", n.id, n.X, n.Y, n.Z, n.radius, n.kind, n.t)
        end
    end
    T.noise = keep
    if ModRef then pcall(function() ModRef:SetSharedVariable("SB2R_Noise", table.concat(parts, ";")) end) end
    U.log(string.format("noise %s r=%.0f", kind, radius))
end

function T.playerTurret()
    for a, e in pairs(T.turrets) do
        if e.kind == "player" then return e, a end
    end
    return nil
end

function T.allyTurretCount()
    local n = 0
    for _, e in pairs(T.turrets) do
        if e.kind == "ally" and e.levelId == T.levelId and not e.dead then n = n + 1 end
    end
    return n
end

-- Alive and ticking right now (safe to look up by path).
function T.alive(a)
    local e = T.turrets[a]
    return e ~= nil and not e.dead and os.clock() - e.lastTick < 0.3
end

function T.findTurret(a)
    if not T.alive(a) then return nil end
    return U.find(T.turrets[a].path)
end

-- Nearest turret that fired in the last 2 s within radius of pos.
function T.nearestFiring(pos, radius, now)
    local best, bestD
    for a, e in pairs(T.turrets) do
        if not e.dead and now - e.firedAt < 2.0 then
            local d = U.dist(pos, e)
            if d <= radius and (not bestD or d < bestD) then best, bestD = a, d end
        end
    end
    return best, bestD
end

function T.queue(a, cmd)
    local e = a and T.turrets[a]
    if e then e.queue[#e.queue + 1] = cmd end
end

-- Spawning ---------------------------------------------------------------------------
-- Verified in game: World:SpawnActor(cls, loc, rot) with LifeTime set on the class default object.
-- LifeTime is read once in BeginPlay (Delay(LifeTime) -> Explode), so it is set on the class
-- default object first; the instance copies it. (Alternative: GameplayStatics
-- BeginDeferredActorSpawnFromClass / FinishSpawningActor, if an FTransform can be passed.)
function T.spawnTurret(ctx, loc, yaw, kind, owner)
    local cls = U.find(G.PerkTurret) -- loads with Q1_Character: a hit, ~0 ms
    if not cls then U.warn("turret class not loaded"); return nil end
    local cdo = U.find(G.PerkTurretCDO)
    if cdo then U.set(cdo, P.LifeTime, 1e7) end
    local world
    pcall(function() world = ctx:GetWorld() end)
    if not U.valid(world) then return nil end
    T.spawning = true
    local ok, actor = pcall(function()
        return world:SpawnActor(cls, { X = loc.X, Y = loc.Y, Z = loc.Z }, { Pitch = 0, Yaw = yaw or 0, Roll = 0 })
    end)
    T.spawning = false
    if not ok or not U.valid(actor) then
        U.warn("turret spawn failed: " .. tostring(actor))
        return nil
    end
    local s = cfg().Turret.Scale
    if s and s ~= 1 then pcall(function() actor:SetActorScale3D({ X = s, Y = s, Z = s }) end) end -- verified: 0.8 shows as 0.8
    local a = register(actor, kind, owner, loc) -- owner: address of the ally engineer (bookkeeping only)
    U.log(string.format("spawned %s turret %s at %.0f %.0f %.0f", kind, tostring(a), loc.X, loc.Y, loc.Z))
    return a
end

-- Where vanilla puts the perk turret: the player's BarricadeLocation component (~2 m ahead).
local function deployPoint(p)
    local ok, l = pcall(function() return p[P.BarricadeLocation]:K2_GetComponentLocation() end)
    if ok and l then return { X = l.X, Y = l.Y, Z = l.Z } end
    local pos = U.location(p)
    local ok2, f = pcall(function() return p:GetActorForwardVector() end)
    if pos and ok2 and f then return { X = pos.X + f.X * 150, Y = pos.Y + f.Y * 150, Z = pos.Z - 90 } end
    return nil
end

local function yawOf(actor)
    local ok, r = pcall(function() return actor:K2_GetActorRotation() end)
    return ok and r and r.Yaw or 0
end

-- Player work (deploy / pack) -----------------------------------------------------------
local function kneel(p, on)
    U.set(p, P.DisableMove, on) -- zeroes movement input (used by the trip-mine perk)
    if on then
        U.set(p, P.DesiredStance, G.Stance.Crouching)
        pcall(function() p:Crouch(false) end)
    else
        U.set(p, P.DesiredStance, G.Stance.Standing)
        pcall(function() p:UnCrouch(false) end)
    end
    -- TODO(P7): HolsterWhileWorking (ToggleCurrentWeapon) and the kneel montage (G.KneelMontage).
end

local function canWork(p)
    if U.get(p, P.Flying, false) then return false, "Not while flying" end
    if U.get(p, P.AtDialog, false) then return false, nil end
    local w = U.get(p, P.WhereIsPlayer, G.Where.PlanetSurface)
    if w == G.Where.StationTrans or w == G.Where.StationSubLevel then return false, "Not on a station" end
    local falling = false
    pcall(function() falling = p[P.Movement]:IsFalling() end)
    if falling then return false, nil end
    return true
end
T.kneel, T.canWork, T.deployPoint, T.yawOf = kneel, canWork, deployPoint, yawOf -- shared with barricade.lua

-- Deploy key went down (no modifier held; game thread). A tap deploys / packs / cancels,
-- holding it (ToggleHoldSeconds) switches Tactical Engineering on or off. Decided in stepHold.
function T.onKey()
    if T.holdLock then return end
    if T.hold and os.clock() - T.hold < 5 then return end -- key repeat while held
    T.hold = os.clock()
end

-- Quick taps on a perk button TE uses (turret or barricade), all within TripleTapSeconds:
-- 3 = Tactical Engineering on / off, 4 = ally engineers on / off. The third tap waits for the
-- window to close (step() decides), so a fourth can still come. Works while off.
-- Returns true when this tap is part of a gesture (3rd or 4th) and must not act as a press.
function T.tripleTap()
    local now = os.clock()
    local w = cfg().TripleTapSeconds or 1.5
    T.taps[#T.taps + 1] = now
    while #T.taps > 0 and now - T.taps[1] > w do table.remove(T.taps, 1) end
    if #T.taps >= 4 then
        T.taps, T.tapDecideAt = {}, nil
        T.toggleReq = "allies"
        return true
    end
    if #T.taps == 3 then
        T.tapDecideAt = T.taps[1] + w
        return true
    end
    return false
end

function T.toggleAllies(p)
    T.allies = not T.allies
    T.save()
    U.warn("ally engineers " .. (T.allies and "ON" or "OFF"))
    U.notify(p, "Ally engineers " .. (T.allies and "ON" or "OFF") .. (T.on and "" or " (Tactical Engineering is off)"))
end

function T.onPerkButton(self)
    -- Post-hook of Q1_Character:SpawnTurrets. With P_Turret.CD kept at 0 the vanilla body
    -- returned early (no energy spent, no turret touched); treat it as our button.
    if T.tripleTap() then return end
    if T.on then T.pressed = true end
end

-- Switch Tactical Engineering on or off (want: true / false / nil = flip).
function T.toggle(p, want)
    if want == nil then want = not T.on end
    if want == T.on then return end
    if not want and (T.state == "DEPLOYING" or T.state == "DEPLOYED" or T.state == "PACKING") then
        U.notify(p, "Pack up your turret first")
        return
    end
    T.on = want
    T.save()
    U.warn("Tactical Engineering " .. (want and "ON" or "OFF"))
    U.notify(p, want and ("Tactical Engineering ON - " .. (T.keyLabel and ("tap " .. T.keyLabel .. " or a perk button")
        or "use your turret / barricade perk buttons")) or "Tactical Engineering OFF - vanilla perks")
end

local function startWork(p, kind, duration, turretAddr)
    local pos = U.location(p)
    if not pos then return end
    T.work = { kind = kind, pawn = U.addr(p), t0 = os.clock(), duration = duration,
        X = pos.X, Y = pos.Y, Z = pos.Z, turret = turretAddr }
    kneel(p, true)
    -- one message per key press (the game's HUD warning plays an alert sound, so no countdown)
    U.notify(p, string.format("%s turret - %d s", kind == "deploy" and "Deploying" or "Packing up", math.floor(duration + 0.5)))
    T.makeNoise(pos, cfg().Noise.WorkRadius, kind, "player") -- metal work: nearby enemies come to look
end

function T.cancelWork(p, why)
    local w = T.work
    if not w then return end
    T.work = nil
    if U.valid(p) then kneel(p, false) end
    if w.kind == "deploy" then
        T.setState("CARRIED")
    else
        T.queue(w.turret, "resume")
        T.setState("DEPLOYED")
    end
    if why then U.notify(p, "Turret: " .. why) end
end

local function startDeploy(p)
    local ok, why = canWork(p)
    if not ok then if why then U.notify(p, why) end return end
    T.setState("DEPLOYING")
    startWork(p, "deploy", T.faster(cfg().Player.DeploySeconds, T.turretStep(p)))
end

local function finishDeploy(p)
    T.work = nil
    kneel(p, false)
    local loc = deployPoint(p)
    local a = loc and T.spawnTurret(p, loc, yawOf(p), "player", T.playerAddr)
    if not a then
        T.setState("CARRIED")
        U.notify(p, "Turret: can't deploy here")
        return
    end
    local e = T.turrets[a]
    e.max = T.maxStructure(p)
    e.structure = e.max * T.structure / 100
    e.ammo = T.ammo
    T.setState("DEPLOYED")
    if cfg().Turret.Rounds > 0 and T.ammo <= 0 then
        e.outOfAmmo = true
        T.queue(a, "stop")
        U.notify(p, "Turret deployed - no ammo left")
    elseif cfg().Turret.Rounds > 0 then
        U.notify(p, string.format("Turret deployed - %d rounds", T.ammo))
    else
        U.notify(p, "Turret deployed")
    end
end

local function startPack(p)
    local e, a = T.playerTurret()
    if not e or e.dead then U.notify(p, "Your turret is wrecked"); return end
    if U.dist(U.location(p), e) > cfg().Player.PackRange then U.notify(p, "Too far from your turret"); return end
    local ok, why = canWork(p)
    if not ok then if why then U.notify(p, why) end return end
    T.queue(a, "stop") -- make it safe first
    T.setState("PACKING")
    startWork(p, "pack", T.faster(cfg().Player.PackSeconds, T.turretStep(p)), a)
end

local function finishPack(p)
    local a = T.work.turret
    T.work = nil
    kneel(p, false)
    local e = T.turrets[a]
    if not e or e.dead then
        T.setState(e and "DESTROYED" or "LOST")
        return
    end
    T.structure = 100 * e.structure / e.max
    if cfg().Turret.Rounds > 0 then T.ammo = math.max(0, e.ammo or 0) end -- its ammo goes with it
    e.packed = true
    T.queue(a, "destroy")
    T.setState("CARRIED")
    U.notify(p, cfg().Turret.Rounds > 0 and string.format("Turret packed - you are carrying it (%d rounds)", T.ammo)
        or "Turret packed - you are carrying it")
end

-- Stop a turret's fire and its effects: StopShoot pauses its shoot timer and switches off the muzzle
-- flash and the tracer (read in Player_PerkTurret). Vanilla only stops by itself when its target is a
-- dead Q1_Shooter_AI, so a turret TE has lost track of can keep its firing effect.
function T.silence(t)
    U.set(t, P.ActiveNow, false)
    pcall(function() t:StopShoot() end)
end

-- Give the player back a turret found standing (it stopped responding, or a leftover near you).
local function recovered(p, t, msg)
    if t then T.silence(t); pcall(function() t:K2_DestroyActor() end) end
    local le = T.lostEntry or {}
    T.lostEntry = nil
    T.structure = math.max(1, math.min(100, le.structure or T.structure))
    if cfg().Turret.Rounds > 0 and le.ammo then T.ammo = math.max(0, le.ammo) end
    T.setState("CARRIED")
    U.notify(p, cfg().Turret.Rounds > 0 and string.format("%s (%d rounds)", msg, T.ammo) or msg)
end

-- With no turret (lost / destroyed), a press next to a perk turret TE doesn't know recovers it.
local function recoverNearby(p)
    local pos = U.location(p)
    if not pos then return false end
    local range, found = cfg().Player.PackRange * 2, nil
    for a, o in pairs(T.orphans) do
        if o.X and U.dist(pos, o) <= range then
            T.orphans[a] = nil
            found = U.find(o.path)
            if found then break end
        end
    end
    if not found then -- a standing turret that doesn't even tick: look once (~50 ms, only on a press)
        local list
        pcall(function() list = FindAllOf(G.PerkTurretShort) end)
        for _, t in ipairs(list or {}) do
            local a = U.addr(t)
            if a and U.valid(t) and not T.turrets[a] and U.dist(pos, U.location(t)) <= range then found = t break end
        end
    end
    if not found then return false end
    U.warn("recovered a perk turret TE had lost track of (state " .. T.state .. ")")
    recovered(p, found, "Turret recovered - you are carrying it")
    return true
end

local function handlePress(p)
    if T.work then return T.cancelWork(p, "cancelled") end
    if T.B and T.B.work then return T.B.cancel(p, "cancelled") end
    if not T.turretUsable and T.state ~= "DEPLOYED" then return U.notify(p, "Requires the Turret perk") end
    if T.state == "CARRIED" then return startDeploy(p) end
    if T.state == "DEPLOYED" then return startPack(p) end
    if T.state == "LOST" or T.state == "DESTROYED" then
        if recoverNearby(p) then return end
        local r = cfg().Player.Resupply
        local msg = "it is gone"
        if r == "level" then
            msg = "a new one at the next level"
        elseif r == "ship" then
            local left = math.ceil(((cfg().Player.ResupplyMinutes or 0) * 60 - (os.time() - (T.lostAt or 0))) / 60)
            msg = left > 0 and string.format("a new one at your ship in %d min", left) or "a new one waits at your ship"
        end
        U.notify(p, "No turret - " .. msg)
    end
end

local function stepWork(p, now)
    local w = T.work
    if not w then return end
    if w.pawn ~= T.playerAddr then return T.cancelWork(nil) end -- new pawn (death, respawn)
    if w.abort then -- the turret was destroyed while being packed (state already set)
        T.work = nil
        kneel(p, false)
        return
    end
    local pos = U.location(p)
    if pos and U.dist(pos, w) > 50 then return T.cancelWork(p, "interrupted") end
    U.set(p, P.DisableMove, true) -- other game code may clear it
    if now - w.t0 >= w.duration then
        if w.kind == "deploy" then finishDeploy(p) else finishPack(p) end
    end
end

-- Loss, arrival and resupply ---------------------------------------------------------------
-- The deployed turret stopped ticking for 3 s: it went with the area (a level or floor change), or it
-- is still standing but no longer runs (seen in a dungeon: it kept its firing effect without shooting,
-- and TE said you had no turret). A standing one is silenced and removed; if it is close to you, you
-- get it back (with its ammo and damage), else it is lost.
local function checkLost(p, now)
    if T.state ~= "DEPLOYED" and T.state ~= "PACKING" then return end
    local e, a = T.playerTurret()
    if e and (e.dead or now - e.lastTick < 3.0) then return end
    if T.work then T.work = nil; kneel(p, false) end
    local ghost = nil
    if e then
        T.turrets[a] = nil
        T.lostEntry = { ammo = e.ammo, structure = 100 * math.max(0, e.structure) / e.max }
        ghost = U.find(e.path) -- ~0 ms if it still exists, ~37 ms once if it is gone
    end
    if ghost then
        local pos = U.location(p)
        if pos and U.dist(pos, e) <= RECOVER_RANGE then
            U.warn("player turret stopped responding nearby: recovered")
            return recovered(p, ghost, "Your turret stopped responding - recovered, you are carrying it")
        end
        T.silence(ghost)
        pcall(function() ghost:K2_DestroyActor() end)
    end
    T.setState("LOST")
    U.notify(p, "Your turret was left behind - lost")
end

local function onArrival(p)
    T.levelId = T.levelId + 1
    T.arrived = true
    local now = os.clock()
    for a, e in pairs(T.turrets) do
        if now - e.lastTick > 1.0 and e.kind ~= "player" then T.turrets[a] = nil end -- gone with the old level
    end
    if (T.state == "LOST" or T.state == "DESTROYED") and cfg().Player.Resupply == "level" then
        T.resupply(p)
    end
    if T.B then T.B.onArrival(p) end
end

function T.resupply(p)
    T.structure = 100
    T.ammo = T.maxRounds(p)
    for a, e in pairs(T.turrets) do if e.kind == "player" then T.turrets[a] = nil end end
    T.setState("CARRIED")
    U.notify(p, "New turret issued - you are carrying it")
end

-- At your ship (in space) or a station, out of combat.
local function atShip(p)
    if U.get(p, P.InCombat, false) then return false end
    local w = U.get(p, P.WhereIsPlayer, G.Where.PlanetSurface)
    return w == G.Where.Space or w == G.Where.StationTrans or w == G.Where.StationSubLevel
end

-- "ship": a replacement waits for you at your ship or a station, out of combat, at least
-- ResupplyMinutes after the loss (real time). A carried turret's ammo is refilled there too.
local function checkResupply(p)
    if T.B and atShip(p) then T.B.restock(p) end
    if not T.turretUsable then return end
    local rounds = T.maxRounds(p)
    if T.state == "CARRIED" and rounds > 0 and T.ammo < rounds and atShip(p) then
        T.ammo = rounds
        T.save()
        U.notify(p, string.format("Turret ammo refilled from your ship - %d rounds", rounds))
        return
    end
    if T.state ~= "LOST" and T.state ~= "DESTROYED" then return end
    if cfg().Player.Resupply ~= "ship" then return end
    if os.time() - (T.lostAt or 0) < (cfg().Player.ResupplyMinutes or 0) * 60 then return end
    if atShip(p) then T.resupply(p) end
end

-- Tap or hold of the deploy key (polled while it is down).
local function stepHold(p, now)
    if T.holdLock then
        if not U.keyDown(T.keyName) then T.holdLock = false end
        return
    end
    if not T.hold then return end
    local hold = cfg().ToggleHoldSeconds
    if hold > 0 and now - T.hold >= hold then
        T.hold, T.holdLock = nil, true
        return T.toggle(p)
    end
    if hold > 0 and T.keyName and U.keyDown(T.keyName) then return end -- still held: wait
    T.hold = nil
    if T.on then
        T.pressed = true
    else
        U.notify(p, "Tactical Engineering is off - hold " .. (T.keyLabel or "Delete") .. " to switch it on")
    end
end

-- Player tick (ALS_Base:ReceiveTick: every frame for every ALS character) -----------------
local function step(p, now)
    local pos = U.location(p)
    if pos and T.lastPos and U.dist(pos, T.lastPos) > 1500 then onArrival(p) end -- elevator / new level
    T.lastPos = pos
    stepHold(p, now)
    if T.tapDecideAt and now >= T.tapDecideAt then -- 3 taps and no fourth: on / off
        T.tapDecideAt, T.taps = nil, {}
        T.toggleReq = "toggle"
    end
    if T.toggleReq then
        local r, want = T.toggleReq, nil
        T.toggleReq = nil
        if r == "allies" then
            T.toggleAllies(p)
        else
            if r == "on" then want = true elseif r == "off" then want = false end
            T.toggle(p, want)
        end
    end
    if not T.on then
        T.pressed = false
        if T.B then T.B.off(p) end
        return
    end
    if T.pressed then T.pressed = false; handlePress(p) end
    stepWork(p, now)
    if T.B then T.B.step(p, now) end
    if now >= T.nextSlow then
        T.nextSlow = now + 1.0
        checkLost(p, now)
        checkResupply(p)
    end
end

function T.onPlayerTick(self)
    local p = self:get()
    local now = os.clock()
    if now >= T.playerCheckAt then
        T.playerCheckAt = now + 1.0
        local pp = U.playerPawn(p) -- instant engine call; nil while the pawn is a ship
        local pa = pp and U.addr(pp) or nil
        if pa and not G.PlayerClassNames[U.className(pp) or ""] then pa = nil end
        T.playerAddr = pa
        -- the turret needs the game's turret perk: before you learn it, you have none
        if pa then T.turretUsable = T.perkLevel(pp, P.PerkTurret) > 0 end
    end
    if T.playerAddr == nil or U.addr(p) ~= T.playerAddr then return end
    if now - T.playerTickAt > 0.5 then
        -- pause or hitch: nothing ticked meanwhile, so don't count it against the turrets
        for _, e in pairs(T.turrets) do e.lastTick = now end
    end
    T.playerTickAt = now
    if now < T.nextStep then return end
    T.nextStep = now + 0.1
    step(p, now)
end

-- Vanilla turret perk block ---------------------------------------------------------------
-- Post-hook of ALS_Base:Regenerators (0.25 s timer): vanilla (and HTR 0.4.2's slower perk
-- cooldowns, if present) have just raised the cooldowns; pin the turret perk's at 0 so the
-- vanilla SpawnTurrets() always returns before spending energy or exploding our turret.
-- Only P_Turret.CD is touched: energy and every other perk keep vanilla / HTR rules.
function T.onRegenerators(self)
    if not T.on or T.playerAddr == nil then return end
    local p = self:get()
    if U.addr(p) ~= T.playerAddr then return end
    if cfg().BlockVanillaTurretPerk then pcall(function() p[P.PerkTurret][P.PerkCD] = 0.0 end) end
    if T.B then T.B.pin(p) end
end

-- Carrying ------------------------------------------------------------------------------
-- Post-hook of ALS_Base:UpdateDynamicMovementSettings(AllowedGait): ALS has just written
-- MaxWalkSpeed; scale it while the packed turret is carried.
function T.onMoveSettings(self)
    if not T.on or T.state ~= "CARRIED" or T.playerAddr == nil or not T.turretUsable then return end
    local p = self:get()
    if U.addr(p) ~= T.playerAddr then return end
    local f = cfg().Player.CarrySpeed
    local m = U.get(p, P.Movement, nil)
    if not m then return end
    local s = U.get(m, "MaxWalkSpeed", nil)
    if s then
        U.set(m, "MaxWalkSpeed", s * f)
        U.set(m, "MaxWalkSpeedCrouched", s * f)
    end
end

-- Post-hook of ALS_Base:CanSprint(out CanSprint).
function T.onCanSprint(self, canSprint)
    if not T.on or T.state ~= "CARRIED" or T.playerAddr == nil or not T.turretUsable then return end
    if U.addr(self:get()) ~= T.playerAddr then return end
    canSprint:set(false)
end

-- Turret hooks ---------------------------------------------------------------------------
local function run(t, a, e, cmd)
    if cmd == "stop" then
        e.stopped = true -- kept off in the tick: the unfold animation switches it on ~3 s after spawn
        U.set(t, P.ActiveNow, false)
        pcall(function() t:StopShoot() end)
    elseif cmd == "resume" then
        e.stopped = false
        if not e.dead and not e.outOfAmmo then U.set(t, P.ActiveNow, true) end
    elseif cmd == "wreck" then
        U.set(t, P.TurretDead, true)
        U.set(t, P.ActiveNow, false)
        pcall(function() t:StopShoot() end)
        pcall(function() t:SetActorTickEnabled(false) end)
    elseif cmd == "explode" then
        T.turrets[a] = nil
        pcall(function() t:Explode() end) -- vanilla blast + shrapnel + destroy (hurts anyone within 5 m)
    elseif cmd == "destroy" then
        T.turrets[a] = nil
        pcall(function() t:K2_DestroyActor() end)
    end
end

function T.onTurretBeginPlay(self)
    -- P1 discovery: log every perk turret that appears (ours are spawned with T.spawning set).
    local t = self:get()
    U.log(string.format("perk turret BeginPlay %s ours=%s LifeTime=%s", tostring(U.addr(t)), tostring(T.spawning),
        tostring(U.get(t, P.LifeTime, "?"))))
end

-- Post-hook of Player_PerkTurret_C:ReceiveTick(DeltaSeconds): heartbeat + command queue.
-- A perk turret TE doesn't know is ticking. While TE is on, vanilla can't spawn one, so it is a
-- leftover (one TE lost track of). Keep it silent. If you have your own turret, remove it; if yours
-- was lost or destroyed, leave it for a press next to it (recoverNearby).
local function onOrphanTick(t, a)
    if not T.on or not a then return end
    local now = os.clock()
    local o = T.orphans[a]
    if not o then
        o = { path = U.path(t), nextLook = 0 }
        T.orphans[a] = o
        U.warn("perk turret " .. tostring(a) .. " not known to TE (state " .. T.state .. "): silenced")
    end
    o.lastTick = now
    if U.get(t, P.ActiveNow, false) or (not o.quiet and U.get(t, P.Shooting, false)) then
        T.silence(t)
        o.quiet = true
    end
    if T.state ~= "LOST" and T.state ~= "DESTROYED" then
        T.orphans[a] = nil
        pcall(function() t:K2_DestroyActor() end)
        return
    end
    if now >= o.nextLook then
        o.nextLook = now + 1.0
        local l = U.location(t)
        if l then o.X, o.Y, o.Z = l.X, l.Y, l.Z end
    end
end

function T.onTurretTick(self)
    local t = self:get()
    local a = U.addr(t)
    local e = a and T.turrets[a]
    if not e then return onOrphanTick(t, a) end
    local now = os.clock()
    e.lastTick = now
    if #e.queue > 0 then
        local q = e.queue
        e.queue = {}
        for _, cmd in ipairs(q) do
            if T.turrets[a] then run(t, a, e, cmd) end
        end
        if not T.turrets[a] then return end
    end
    -- Rounds fired = drops of its belt count (a reload refills the belt: not counted).
    local belt = U.get(t, P.Ammo, nil)
    if belt ~= nil then
        if e.lastBelt ~= nil and belt < e.lastBelt then
            e.firedAt = now
            local rounds = cfg().Turret.Rounds
            if rounds > 0 and not e.outOfAmmo then
                e.ammo = (e.ammo or rounds) - (e.lastBelt - belt)
                if e.ammo <= 0 then
                    e.ammo, e.outOfAmmo = 0, true
                    if e.kind == "player" then
                        T.ammo = 0
                        U.notify(U.playerPawn(t), "Your turret is out of ammo")
                    end
                end
            end
            if now - e.noiseAt > 1.5 then -- a firing turret is loud
                e.noiseAt = now
                T.makeNoise({ X = e.X, Y = e.Y, Z = e.Z }, cfg().Noise.FireRadius, "turret_fire", a)
            end
        end
        e.lastBelt = belt
    end
    -- stopped / empty: keep it off, firing effect included (its timer can be left running). Its stop
    -- routine runs once until it is switched on again and each shot sets Shooting, so after one stop,
    -- stop again only if it is switched on or fires.
    if (e.outOfAmmo or e.stopped) and not e.dead then
        if U.get(t, P.ActiveNow, false) or e.firedAt == now or (not e.quiet and U.get(t, P.Shooting, false)) then
            T.silence(t)
            e.quiet = true
        end
    else
        e.quiet = nil
    end
    if now >= (e.nextLook or 0) then
        e.nextLook = now + 0.25
        local l = U.location(t)
        if l then e.X, e.Y, e.Z = l.X, l.Y, l.Z end
    end
end

-- Attacker family, cached per class name (walks the parent chain once, like HTR's classify.lua).
local family = {}
function T.familyOf(o)
    local cn = U.className(o)
    if not cn then return nil end
    local f = family[cn]
    if f ~= nil then return f or nil end
    f = false
    pcall(function()
        local cls = o:GetClass()
        for _ = 1, 10 do
            if not (cls and cls:IsValid()) then break end
            local n = cls:GetFName():ToString()
            if G.PlayerClassNames[n] then f = "player" break end
            if G.ShooterClassNames[n] then f = "shooter" break end
            if G.SoldierClassNames[n] then f = "soldier" break end
            if G.PerkTurretClassNames[n] then f = "perkturret" break end
            if G.MiniTurretClassNames[n] then f = "miniturret" break end
            cls = cls:GetSuperStruct()
        end
    end)
    if not f then
        local l = cn:lower()
        for _, pat in ipairs(G.ExplosiveNamePatterns) do
            if l:find(pat, 1, true) then f = "explosion" break end
        end
    end
    family[cn] = f
    return f or nil
end

-- Structure points a hit from `causer` costs (Turret.HitCost).
function T.hitCost(causer)
    local HC = cfg().Turret.HitCost
    local f = T.familyOf(causer)
    if f == "player" then return HC.player end
    if f == "explosion" or f == "miniturret" then return HC.explosion end
    if f == "soldier" or f == "perkturret" then return HC.ally end
    if f == "shooter" then
        if U.get(causer, P.IsCompanion, false) or U.get(causer, P.AIType, 0) == G.AIType.Ally then return HC.ally end
        if U.get(causer, P.SwordAttack, false) then return HC.npc_melee end
        if U.get(causer, P.Sniper, false) then return HC.npc_sniper end
        if U.get(causer, P.SubType, 0) == G.SubType.Tank then return HC.npc_heavy end
        if U.get(causer, P.IsBoss, false) then return HC.npc_boss end
        return HC.npc_rifle
    end
    return HC.other
end

-- Apply structure damage to a registered turret. `t` = the live actor if we are inside one
-- of its hooks, else nil (the result is queued for its next tick).
function T.damage(a, cost, t, pawnCtx)
    local e = T.turrets[a]
    if not e or e.dead then return end
    local now = os.clock()
    e.structure = e.structure - cost
    e.hitAt = now
    if e.kind == "player" then T.structure = math.max(0, 100 * e.structure / e.max) end
    if e.structure > 0 then
        -- one notice per threshold crossed (75 / 50 / 25 %): the HUD warning has an alert sound
        local pct = 100 * e.structure / e.max
        if e.kind == "player" then
            for _, th in ipairs({ 25, 50, 75 }) do
                if pct <= th and e.notice > th then
                    e.notice = th
                    local p = pawnCtx or (t and U.playerPawn(t))
                    U.notify(p, string.format("Your turret is damaged - %d%%", math.floor(pct + 0.5)))
                    break
                end
            end
        end
        return
    end
    e.dead = true
    local cmd = (cfg().Turret.DestroyedEffect == "explode") and "explode" or "wreck"
    if t then run(t, a, e, cmd) else T.queue(a, cmd) end
    if e.kind == "player" then
        T.structure = 0
        if T.work and T.work.turret == a then T.work.abort = true end -- stepWork unlocks the player
        T.setState("DESTROYED")
        U.notify(pawnCtx or (t and U.playerPawn(t)), "Your turret was destroyed")
    end
end

-- Post-hook of Player_PerkTurret_C:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser).
-- The vanilla body ignores all damage (the perk turret is invulnerable), so this decides everything.
function T.onTurretDamage(self, damage, damageType, instigatedBy, causer)
    local t = self:get()
    local a = U.addr(t)
    if not (a and T.turrets[a]) then return end
    local c = causer and causer:get()
    if U.addr(c) == a then return end -- its own shrapnel
    T.damage(a, T.hitCost(c), t)
end

-- One line for te.log (Debug.TestCommands "status").
function T.status()
    local now = os.clock()
    local parts = { string.format("on=%s allies=%s state=%s structure=%.0f ammo=%s work=%s player=%s", tostring(T.on),
        tostring(T.allies), T.state,
        T.structure, tostring(T.ammo), T.work and (T.work.kind .. string.format(" %.1fs", now - T.work.t0)) or "-", tostring(T.playerAddr)) }
    for a, e in pairs(T.turrets) do
        parts[#parts + 1] = string.format("[%s %s structure=%.0f dead=%s tick=%.1fs fired=%.1fs ammo=%s]", e.kind,
            tostring(a), e.structure, tostring(e.dead), now - e.lastTick, now - e.firedAt, tostring(e.ammo))
    end
    return table.concat(parts, " ")
end

return T
