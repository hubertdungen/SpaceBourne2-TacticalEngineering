--[[
  Barricades: the game's barricade perk (Barricde_C, an energy-shield wall that vanilla puts
  up instantly for 10-20 s) as field engineering. See DESIGN.md section 8.

  - The barricade perk button builds one where vanilla puts it (kneel Barricades.BuildSeconds),
    or packs up your nearest one within PackRange (PackSeconds). A tap while working cancels.
  - You carry a few: Carried + ExtraPerLevel per barricade perk level above 1. They are
    restocked at your ship or a station, out of combat. One left behind is lost.
  - Enemy rounds wear it down (the shooters' OnProjectileHit hooks, the same HTR uses);
    at 0 it collapses. A packed one recharges (it is an energy shield).
  - The vanilla instant barricade is blocked by keeping BarrierCD set while TE is on.

  No UObject is stored: a placed barricade is kept by address and path.
]]

local U = require("te.util")
local G = require("te.gamedefs")
local P = G.P

local B = {
    cfg = nil, T = nil,
    carried = nil,   -- barricades you carry (nil until the first tick with a pawn)
    placed = {},     -- [address] = { path, X, Y, Z, structure, max, notice }
    work = nil,      -- { kind = "build" | "pack", pawn, t0, duration, X, Y, Z, target }
    pressed = false,
    hits = 0,        -- enemy rounds stopped (status line)
}

local function c() return B.cfg.Barricades end

function B.init(cfg, T)
    B.cfg, B.T = cfg, T
    T.B = B
    B.carried = tonumber(T.loaded.barricades)
end

function B.save()
    B.T.extra.barricades = B.carried
    B.T.save()
end

function B.level(p) return B.T.perkLevel(p, P.PerkBarricade) end

-- How many you can carry: none without the perk, then Carried + ExtraPerLevel per level above 1.
function B.maxCarried(p)
    local lv = B.level(p)
    if lv <= 0 then return 0 end
    return math.max(1, math.floor(c().Carried + c().ExtraPerLevel * B.T.levelStep(lv)))
end

local function count()
    local n = 0
    for _ in pairs(B.placed) do n = n + 1 end
    return n
end

-- Spawning (same CDO LifeTime trick as the turret: Barricde_C reads LifeTime once, in BeginPlay).
local function spawn(p, loc, yaw)
    local cls = U.find(G.Barricade)
    if not cls then
        pcall(function() LoadAsset(G.BarricadeAsset) end)
        cls = U.find(G.Barricade)
    end
    if not cls then U.warn("barricade class not loaded"); return nil end
    local cdo = U.find(G.BarricadeCDO)
    if cdo then U.set(cdo, P.LifeTime, 1e7) end
    local world
    pcall(function() world = p:GetWorld() end)
    if not U.valid(world) then return nil end
    local ok, actor = pcall(function()
        return world:SpawnActor(cls, { X = loc.X, Y = loc.Y, Z = loc.Z }, { Pitch = 0, Yaw = yaw or 0, Roll = 0 })
    end)
    if not ok or not U.valid(actor) then U.warn("barricade spawn failed: " .. tostring(actor)); return nil end
    return actor
end

-- Work (build / pack) ----------------------------------------------------------------------
local function startWork(p, kind, duration, target)
    local pos = U.location(p)
    if not pos then return end
    B.work = { kind = kind, pawn = U.addr(p), t0 = os.clock(), duration = duration,
        X = pos.X, Y = pos.Y, Z = pos.Z, target = target }
    B.T.kneel(p, true)
    U.notify(p, string.format("%s barricade - %d s", kind == "build" and "Building" or "Packing up",
        math.floor(duration + 0.5)))
    B.T.makeNoise(pos, B.cfg.Noise.WorkRadius, "barricade", "player")
end

function B.cancel(p, why)
    if not B.work then return end
    B.work = nil
    if U.valid(p) then B.T.kneel(p, false) end
    if why then U.notify(p, "Barricade: " .. why) end
end

local function nearest(p)
    local pos = U.location(p)
    if not pos then return nil end
    local best, bestD
    for a, e in pairs(B.placed) do
        local d = U.dist(pos, e)
        if not bestD or d < bestD then best, bestD = a, d end
    end
    return best, bestD
end

local function handlePress(p)
    if B.work then return B.cancel(p, "cancelled") end
    if B.T.work then return end -- busy with the turret
    local ok, why = B.T.canWork(p)
    if not ok then if why then U.notify(p, why) end return end
    local lv = B.level(p)
    if lv <= 0 then return U.notify(p, "Requires the Barricade perk") end
    local step = B.T.levelStep(lv)
    local a, d = nearest(p)
    if a and d <= c().PackRange then
        return startWork(p, "pack", B.T.faster(c().PackSeconds, step), a)
    end
    if B.carried <= 0 then
        U.notify(p, "No barricades left - restock at your ship")
        return
    end
    startWork(p, "build", B.T.faster(c().BuildSeconds, step))
end

local function finish(p)
    local w = B.work
    B.work = nil
    B.T.kneel(p, false)
    if w.kind == "build" then
        local loc = B.T.deployPoint(p)
        local actor = loc and spawn(p, loc, B.T.yawOf(p))
        local a = actor and U.addr(actor)
        if not a then U.notify(p, "Barricade: can't build here"); return end
        local mx = c().Structure * (1 + (B.cfg.Levels.ExtraStructure or 0) * B.T.levelStep(B.level(p)))
        B.placed[a] = { path = U.path(actor), X = loc.X, Y = loc.Y, Z = loc.Z, structure = mx, max = mx, notice = 100 }
        B.carried = B.carried - 1
        B.save()
        U.log(string.format("barricade %s built at %.0f %.0f %.0f, structure %.0f", tostring(a), loc.X, loc.Y, loc.Z, mx))
        U.notify(p, string.format("Barricade up - %d left", B.carried))
    else
        local e = B.placed[w.target]
        if not e then U.notify(p, "Barricade: it is gone"); return end
        B.placed[w.target] = nil
        local actor = U.find(e.path)
        if actor then pcall(function() actor:K2_DestroyActor() end) end
        B.carried = B.carried + 1
        B.save()
        U.notify(p, string.format("Barricade packed - you carry %d", B.carried))
    end
end

local function stepWork(p, now)
    local w = B.work
    if not w then return end
    if w.pawn ~= B.T.playerAddr then B.work = nil; return end -- new pawn (death, respawn)
    local pos = U.location(p)
    if pos and U.dist(pos, w) > 50 then return B.cancel(p, "interrupted") end
    if B.cfg.Player.HolsterWhileWorking and U.get(p, P.MeleeAttack, false) then
        return B.cancel(p, "interrupted") -- the melee swing doesn't check the weapon lock
    end
    U.set(p, P.DisableMove, true) -- other game code may clear it
    if now - w.t0 >= w.duration then finish(p) end
end

-- Called by turret.lua ------------------------------------------------------------------------
-- Player tick, every 0.1 s while TE is on.
function B.step(p, now)
    if B.carried == nil then
        B.carried = B.maxCarried(p)
        B.save()
    end
    if B.pressed then B.pressed = false; handlePress(p) end
    stepWork(p, now)
end

-- TE was switched off: stop any work, and give the vanilla perk back (vanilla clears BarrierCD
-- only after its own use). Placed barricades stay until you leave the area.
function B.off(p)
    B.pressed = false
    if B.work then B.cancel(p, nil) end
    if B.pinned then
        B.pinned = false
        pcall(function() p[P.BarrierCD] = false end)
    end
end

-- Arrived somewhere new (new level, elevator): placed barricades stayed behind.
function B.onArrival(p)
    if B.work then B.cancel(p, nil) end
    local n = count()
    if n > 0 then
        B.placed = {}
        U.notify(p, n == 1 and "A barricade was left behind - lost" or string.format("%d barricades left behind - lost", n))
    end
end

-- At your ship or a station, out of combat (checked once a second).
function B.restock(p)
    local m = B.maxCarried(p) - count() -- ones still standing here count too
    if m < 0 then m = 0 end
    if B.carried ~= nil and B.carried < m then
        B.carried = m
        B.save()
        U.notify(p, string.format("Barricades restocked from your ship - %d", m))
    end
end

-- Post-hook of ALS_Base:Regenerators (via turret.lua): keep the vanilla barricade "cooling down",
-- so ActiavateBarricate returns before spending energy or spawning its 10-20 s wall.
function B.pin(p)
    if pcall(function() p[P.BarrierCD] = true end) then B.pinned = true end
end

-- Hooks -----------------------------------------------------------------------------------------
-- Post-hook of Q1_Character:ActiavateBarricate (the barricade perk button).
function B.onPerkButton(self)
    if B.T.playerAddr == nil or U.addr(self:get()) ~= B.T.playerAddr then return end
    if B.T.tripleTap() then return end -- 3 quick taps: TE on / off (as on the turret perk button)
    if B.T.on then B.pressed = true end
end

-- Post-hook of Q1_Shooter_AI:OnProjectileHit_*(OutProjectileObject, OutHitResult, ...): an enemy
-- round hit something. Per-shot cost: one table check while no barricade stands.
function B.onShooterHit(self, proj, hitP)
    if next(B.placed) == nil then return end
    local victim
    pcall(function() victim = hitP:get().Actor:Get() end)
    local a = U.addr(victim)
    local e = a and B.placed[a]
    if not e then return end
    B.hits = B.hits + 1
    e.structure = e.structure - B.T.hitCost(self:get())
    if e.structure > 0 then
        if e.notice > 50 and e.structure <= e.max / 2 then
            e.notice = 50
            U.notify(U.playerPawn(victim), "A barricade is at half strength")
        end
        return
    end
    B.placed[a] = nil
    pcall(function() victim:K2_DestroyActor() end)
    U.log("barricade " .. tostring(a) .. " collapsed")
    U.notify(U.playerPawn(victim), "A barricade collapsed")
end

function B.status()
    local parts = { string.format("barricades carried=%s placed=%d hits=%d work=%s", tostring(B.carried), count(), B.hits,
        B.work and B.work.kind or "-") }
    for a, e in pairs(B.placed) do
        parts[#parts + 1] = string.format("[%s %.0f/%.0f]", tostring(a), e.structure, e.max)
    end
    return table.concat(parts, " ")
end

return B
