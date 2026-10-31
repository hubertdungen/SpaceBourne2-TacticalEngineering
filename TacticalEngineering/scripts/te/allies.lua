--[[
  Engineers (DESIGN.md section 7): a few squad soldiers and companions carry a turret and
  deploy it in a fight (stop, kneel, wait, spawn a Player_PerkTurret_C, which shoots
  enemies). Optional rare enemy engineers use the vanilla MiniTurrets boss ability.
  Allied fire can destroy enemy mini-turrets (vanilla: only the player can).

  Tested in game 2026-10-30: squad engineers deploy (cap respected). Companion engineers,
  enemy engineers and allied damage to enemy mini-turrets are not tested yet.
]]

local U = require("te.util")
local G = require("te.gamedefs")
local P = G.P

local E = {
    cfg = nil, T = nil,
    engineer = {},    -- [address] = true/false, rolled once per NPC
    deploying = {},   -- [address] = { X, Y, Z, t0 }
    deployedIn = {},  -- [address] = levelId of its deployment (one per level)
    lastPos = {},     -- [address] = { X, Y, Z } at the previous check
    enemyRolled = {}, -- [address] = true once the enemy-engineer roll is done
}

function E.init(cfg, T)
    E.cfg, E.T = cfg, T
end

local function isEngineer(a, chance, forced)
    local r = E.engineer[a]
    if r == nil then
        r = forced or (math.random() < chance)
        E.engineer[a] = r
        if r then U.log("engineer: " .. tostring(a)) end
    end
    return r
end

-- Ally turrets placed this level plus those being set up right now (the cap counts both).
local function allyTurretsBusy()
    local n = E.T.allyTurretCount()
    for _, d in pairs(E.deploying) do if d.levelId == E.T.levelId then n = n + 1 end end
    return n
end

-- One check of an ally engineer. inCombat: it has a target. isShooter: Q1_Shooter_AI (can kneel).
local function step(npc, a, inCombat, isShooter)
    local T = E.T
    if E.deployedIn[a] == T.levelId then return end
    local pos = U.location(npc)
    if not pos then return end
    local now = os.clock()
    local d = E.deploying[a]
    if d then
        if not inCombat or U.dist(pos, d) > 150 or d.levelId ~= T.levelId then E.deploying[a] = nil; return end -- moved / fight over
        if now - d.t0 < E.cfg.Allies.DeploySeconds then return end
        E.deploying[a] = nil
        if T.allyTurretCount() >= E.cfg.Allies.MaxAllyTurrets then return end
        local ok, f = pcall(function() return npc:GetActorForwardVector() end)
        if not (ok and f) then return end
        local ok2, r = pcall(function() return npc:K2_GetActorRotation() end)
        local loc = { X = pos.X + f.X * 120, Y = pos.Y + f.Y * 120, Z = pos.Z - 90 } -- feet level (capsule half height)
        if T.spawnTurret(npc, loc, ok2 and r and r.Yaw or 0, "ally", a) then E.deployedIn[a] = T.levelId end
        return
    end
    local last = E.lastPos[a]
    E.lastPos[a] = pos
    if not inCombat or allyTurretsBusy() >= E.cfg.Allies.MaxAllyTurrets then return end
    if not last or U.dist(pos, last) > 100 then return end -- only once it has stopped moving
    E.deploying[a] = { X = pos.X, Y = pos.Y, Z = pos.Z, t0 = now, levelId = T.levelId }
    pcall(function() npc.Controller:StopMovement() end)
    if isShooter then pcall(function() npc:SetStance(G.Stance.Crouching) end) end
end

-- Post-hook of Master_Soldier:UpdateBattle (every 1.5 s per soldier).
function E.onSquadBattle(self)
    if not (E.T.on and E.T.allies) then return end
    local s = self:get()
    local a = U.addr(s)
    if not a or U.get(s, P.SoldierSide, 1) ~= G.AIType.Ally then return end
    local forced = E.cfg.Allies.TurretciAreEngineers and U.get(s, P.SoldierType, 0) == G.SoldierType.Turretci
    if not isEngineer(a, E.cfg.Allies.SquadEngineerChance, forced) then return end
    local inCombat = U.valid(U.get(s, P.SoldierTarget, nil)) and not U.get(s, P.Injured, false)
    step(s, a, inCombat, false)
end

-- From targeting.lua's 1 s think, for companions and other allied shooters.
function E.onCompanionThink(npc, a, now)
    if not E.T.allies then return end
    if not isEngineer(a, E.cfg.Allies.CompanionEngineerChance, false) then return end
    local inCombat = false
    pcall(function() inCombat = U.valid(npc[P.CurrentDetected].DetectedActor) end)
    step(npc, a, inCombat, true)
end

-- From targeting.lua's 1 s think, for enemies: rare extra engineers (vanilla MiniTurrets ability:
-- walks to an EQS spot, kneels ~3 s, deploys an NPC_Shooter_Turret_C). One roll per NPC, once it
-- has seen someone; never for bosses (they already have the ability).
function E.onEnemyThink(npc, a, now)
    local chance = E.cfg.Enemies.EngineerChance
    if chance <= 0 or E.enemyRolled[a] then return end
    if U.get(npc, P.IsBoss, false) then E.enemyRolled[a] = true; return end
    if not U.get(npc, P.CanSee, false) then return end
    E.enemyRolled[a] = true
    if math.random() < chance then
        pcall(function() npc:SelectAbility(G.BossAbility.MiniTurrets) end)
        U.log("enemy engineer " .. tostring(a) .. " deploys a mini-turret")
    end
end

-- Post-hook of NPC_Shooter_Turret_C:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser).
-- Vanilla only counts the player's hits; this adds allied hits (companions, squad, our turrets).
function E.onMiniTurretDamage(self, damage, damageType, instigatedBy, damageCauser)
    if not (E.T.on and E.cfg.Enemies.DamageEnemyMiniTurrets) then return end
    local t = self:get()
    if not U.get(t, P.ActiveNow, false) or U.get(t, P.TurretDead, false) then return end
    local c = damageCauser and damageCauser:get()
    local f = E.T.familyOf(c)
    local allied = f == "soldier" or f == "perkturret"
        or (f == "shooter" and (U.get(c, P.IsCompanion, false) or U.get(c, P.AIType, 0) == G.AIType.Ally))
    if not allied then return end -- the player's hits are already handled by vanilla
    local hp = U.get(t, P.CurrentHP, 0) - (damage:get() or 0) -- raw damage: tune in P3
    U.set(t, P.CurrentHP, hp)
    if hp <= 0 then
        U.set(t, P.TurretDead, true)
        pcall(function() t:Explode() end)
    end
end

return E
