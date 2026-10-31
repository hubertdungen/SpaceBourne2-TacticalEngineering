--[[
  Enemies notice turrets and shoot them (DESIGN.md section 6).

  Enemy eyes only accept the player, companions and squad soldiers (class casts in
  Q1_Shooter_AI), so no NPC ever picks a turret by itself. ET makes an enemy *aware* of a
  turret (it was shot by it, or is near one that is firing), and an aware enemy may
  *engage* it for a few seconds: LastDetectedActor = turret, focus, aim, StartShoot.
  The eye events would snap the target back to the player within 0.3 s, so the override
  is written again in post-hooks of those events.

  Tested in game 2026-10-30: enemies hit by a turret turn on it, their rounds damage it, and
  they keep it targeted through the eye events until they re-assess.
]]

local U = require("te.util")
local G = require("te.gamedefs")
local P = G.P

local A = {
    cfg = nil, T = nil, E = nil,
    aware = {},     -- [npc address] = { turret = address, untilT = clock }
    engaged = {},   -- [npc address] = { turret = address, untilT = clock }
    attackers = {}, -- [turret address] = count
}

function A.init(cfg, T, E)
    A.cfg, A.T, A.E = cfg, T, E
end

-- Point an enemy at a turret (all three are needed: JustShoot aims at ShooTarget if it is
-- valid, else at LastDetectedActor; the behaviour tree focuses LastDetectedActor).
-- Writing nil to an object field inside a struct clears it (verified by the Stealth session:
-- CurrentDetected.DetectedActor = nil).
local function point(npc, turret)
    U.set(npc, P.LastDetected, turret)
    pcall(function() npc[P.ShootTarget].DetectedActor = nil end)
    pcall(function() npc.Controller:K2_SetFocus(turret) end)
end

-- Searching (Noise.Search): the behaviour tree is stopped so it doesn't call the NPC back, and it
-- walks to a point near the noise (StopLogic + focal point + MoveToLocation: Silent Ops' method,
-- verified in game there). It ends when the NPC detects someone, engages a turret, dies, or after
-- Noise.SearchSeconds; then the behaviour tree restarts, still on alert.
A.searching = {} -- [npc address] = { untilT = clock }
local function brain(npc)
    local ok, b = pcall(function() return npc.Controller.BrainComponent end)
    if ok and U.valid(b) then return b end
    return nil
end

local function startSearch(npc, na, goal, now)
    local b = brain(npc)
    if b then pcall(function() b:StopLogic("TacticalEngineering") end) end
    pcall(function()
        local ctl = npc.Controller
        ctl:K2_SetFocalPoint(goal)
        ctl:MoveToLocation(goal, 100.0, true, true, true, false, nil, true)
    end)
    A.searching[na] = { untilT = now + (A.cfg.Noise.SearchSeconds or 12) }
end

function A.endSearch(npc, na)
    if not A.searching[na] then return end
    A.searching[na] = nil
    if not U.valid(npc) then return end
    pcall(function() npc.Controller:K2_ClearFocus() end)
    local b = brain(npc)
    if b then pcall(function() b:RestartLogic() end) end
end

local function stepSearch(npc, na, now)
    local okC, cur = pcall(function() return npc[P.CurrentDetected].DetectedActor end)
    if now > A.searching[na].untilT or (okC and U.valid(cur)) or U.get(npc, P.Dead, false) or not A.T.on then
        A.endSearch(npc, na)
        U.log("NPC " .. tostring(na) .. " search over")
    end
end

function A.engage(npc, na, ta, now)
    local turret = A.T.findTurret(ta)
    if not turret then return end
    if A.searching[na] then A.endSearch(npc, na) end
    local f = A.cfg.Enemies.FocusSeconds
    A.engaged[na] = { turret = ta, untilT = now + f[1] + math.random() * (f[2] - f[1]) }
    A.attackers[ta] = (A.attackers[ta] or 0) + 1
    point(npc, turret)
    pcall(function() npc:SetRotationMode(G.RotationMode.Aiming) end) -- RotationMode 2 enables JustShoot
    pcall(function() npc:StartShoot() end)
    U.log("NPC " .. tostring(na) .. " engages turret " .. tostring(ta))
end

function A.release(npc, na)
    local eng = A.engaged[na]
    if not eng then return end
    A.engaged[na] = nil
    A.attackers[eng.turret] = math.max(0, (A.attackers[eng.turret] or 1) - 1)
    if U.valid(npc) then
        -- back to the player; the eyes re-acquire whoever they really see
        local p = U.playerPawn(npc)
        if p then U.set(npc, P.LastDetected, p) end
        pcall(function() npc.Controller:K2_ClearFocus() end)
    end
end

-- Post-hook of Q1_Shooter_AI:ReceivePointDamage(Damage, DamageType, HitLocation, HitNormal,
-- HitComponent, BoneName, ShotFromDirection, InstigatedBy, DamageCauser, HitInfo).
function A.onNpcPointDamage(self, damage, damageType, hitLocation, hitNormal, hitComponent, boneName,
                            shotFromDirection, instigatedBy, damageCauser)
    if not A.T.on then return end
    local c = damageCauser and damageCauser:get()
    local ca = U.addr(c)
    if not ca then return end
    local npc = self:get()
    local na = U.addr(npc)
    if not na then return end
    if A.T.turrets[ca] then
        A.aware[na] = { turret = ca, untilT = os.clock() + 20 } -- shot by a turret: it knows where it is
    elseif A.engaged[na] and A.T.familyOf(c) == "player" then
        A.release(npc, na) -- the player is the bigger threat now
    end
end

-- Noise (Noise.AlertEnemies): an enemy that has not seen anyone yet hears a recent deploy /
-- pack-up / barricade work (the player is the source) or a firing turret (the turret is) within
-- its radius. It goes on alert through the game's own alert (CheckForFirstFocus: alert / in
-- combat, so HTR's alert sight range applies) and, with Noise.Search, walks to search around the
-- noise (MoveToLocation, as Silent Ops does). Each noise is heard once.
-- With Silent Ops on, TE does none of this: Silent Ops hears turret setup and fire through the
-- turret's own hooks, and the rest (packing, barricades) from the shared variable "SB2R_Noise",
-- and runs its own suspicion -> search -> alert.
A.heard = {} -- [npc address] = last noise id heard
A.soOverride = nil -- tests only: true / false replaces the SilentOps_On reading
local silentOps, silentOpsAt = false, -1e9
local function silentOpsOn(now) -- Silent Ops 0.2+ publishes "SilentOps_On"; it then handles noise itself
    if A.soOverride ~= nil then return A.soOverride end
    if now - silentOpsAt > 2 then
        silentOpsAt = now
        local ok, v = pcall(function() return ModRef and ModRef:GetSharedVariable("SilentOps_On") end)
        silentOps = ok and v == true
    end
    return silentOps
end
function A.hear(npc, na, now)
    if not A.cfg.Noise.AlertEnemies or #A.T.noise == 0 or silentOpsOn(now) then return end
    local okC, cur = pcall(function() return npc[P.CurrentDetected].DetectedActor end)
    if okC and U.valid(cur) then return end -- already fighting someone
    local pos = U.location(npc)
    if not pos then return end
    for _, n in ipairs(A.T.noise) do
        if n.id > (A.heard[na] or 0) and now - n.t < 1.5 and U.dist(pos, n) <= n.radius then
            A.heard[na] = n.id
            local src
            if n.source == "player" then
                src = U.playerPawn(npc)
            else
                src = A.T.findTurret(n.source)
                if src then A.aware[na] = { turret = n.source, untilT = now + 20 } end
            end
            if src then
                pcall(function() npc:CheckForFirstFocus(src) end)
                if A.cfg.Noise.Search and not A.engaged[na] then
                    -- search: a point near the noise, not the exact spot (it was only heard)
                    local ang, d = math.random() * 2 * math.pi, math.random() * (A.cfg.Noise.SearchRadius or 0)
                    startSearch(npc, na, { X = n.X + d * math.cos(ang), Y = n.Y + d * math.sin(ang), Z = n.Z }, now)
                end
                U.log(string.format("NPC %s heard %s at %.0f m: alert%s", tostring(na), n.kind, U.dist(pos, n) / 100,
                    A.cfg.Noise.Search and ", searching" or ""))
            end
            return
        end
    end
end

-- Post-hook of Q1_Shooter_AI:CheckMeleeDistance: runs every 1 s on every shooter.
function A.onNpcThink(self)
    local npc = self:get()
    local na = U.addr(npc)
    if not na then return end
    local now = os.clock()
    if A.searching[na] then stepSearch(npc, na, now) end -- also ends searches when TE was switched off
    if not A.T.on then return end
    if U.get(npc, P.Dead, false) or not U.get(npc, P.Ready, false) then
        if A.engaged[na] then A.release(nil, na) end
        return
    end
    if U.get(npc, P.IsCompanion, false) or U.get(npc, P.AIType, 0) == G.AIType.Ally then
        A.E.onCompanionThink(npc, na, now)
        return
    end
    if U.get(npc, P.AIType, 0) ~= G.AIType.Enemy then return end
    A.E.onEnemyThink(npc, na, now)
    A.hear(npc, na, now)
    if not A.cfg.Enemies.AttackTurrets then return end

    local eng = A.engaged[na]
    if eng then
        if now > eng.untilT or not A.T.alive(eng.turret) then A.release(npc, na) end
        return
    end
    local pos = U.location(npc)
    if not pos then return end
    local aw = A.aware[na]
    if aw and now > aw.untilT then A.aware[na] = nil; aw = nil end
    if not aw then
        local ta = A.T.nearestFiring(pos, A.cfg.Enemies.AwareRadius, now)
        if ta then aw = { turret = ta, untilT = now + 20 }; A.aware[na] = aw end
    end
    if not aw or not A.T.alive(aw.turret) then return end
    if (A.attackers[aw.turret] or 0) >= A.cfg.Enemies.MaxAttackers then return end
    local chance = A.cfg.Enemies.TargetChance
    local e = A.T.turrets[aw.turret]
    local p = U.playerPawn(npc)
    if U.dist(pos, e) < U.dist(pos, p and U.location(p)) then chance = chance * 1.5 end
    if U.get(npc, P.CanSee, false) then chance = chance * 0.5 end
    if math.random() < chance then A.engage(npc, na, aw.turret, now) end
end

-- Post-hook of the four eye events (XVisionEye / RifleEye x OnTargetDetected / OnTargetUpdated).
-- Cheap for everyone not engaging a turret: one address lookup.
function A.onNpcEye(self)
    local npc = self:get()
    local na = U.addr(npc)
    local eng = na and A.engaged[na]
    if not eng then return end
    local turret = A.T.findTurret(eng.turret)
    if not turret then return A.release(npc, na) end
    point(npc, turret)
end

-- Fallback if NPC rounds pass through turrets (DESIGN.md 5.3): post-hook of
-- Q1_Shooter_AI:JustShoot, only hooked with Enemies.SimulatedHits. Hit chance falls with distance.
function A.onNpcJustShoot(self)
    local npc = self:get()
    local na = U.addr(npc)
    local eng = na and A.engaged[na]
    if not eng then return end
    local e = A.T.turrets[eng.turret]
    if not e or e.dead then return end
    local d = U.dist(U.location(npc), e)
    local chance = U.clamp(1.0 - (d - 500) / 4500 * 0.75, 0.25, 1.0) -- 100 % at 5 m, 25 % at 50 m
    if math.random() < chance then
        A.T.damage(eng.turret, A.T.hitCost(npc), nil, nil) -- queued: runs on the turret's next tick
    end
end

function A.status()
    local aware, engaged = 0, 0
    for _ in pairs(A.aware) do aware = aware + 1 end
    for _ in pairs(A.engaged) do engaged = engaged + 1 end
    local att = {}
    for ta, n in pairs(A.attackers) do att[#att + 1] = tostring(ta) .. ":" .. n end
    return string.format("aware=%d engaged=%d attackers={%s}", aware, engaged, table.concat(att, ","))
end

return A
