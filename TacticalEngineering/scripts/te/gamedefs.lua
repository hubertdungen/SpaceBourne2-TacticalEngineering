--[[
  Every SpaceBourne 2 internal name Tactical Engineering depends on.
  After a game update, this is the only file to fix.
  Read from the game's Blueprints (UE 4.27, build of 2026-10-26). Verified in game 2026-10-30 unless marked.
]]

local G = {}

-- Classes ----------------------------------------------------------------------
G.Player       = "/Game/1Data/Q1_Character.Q1_Character_C"
G.ALSBase      = "/Game/Locomotion/Blueprints/CharacterLogic/ALS_Base.ALS_Base_C"
G.Shooter      = "/Game/1Data/11_AI/Q1_Shooter_AI.Q1_Shooter_AI_C"
G.Soldier      = "/Game/1Data/11_AI/BattleAI/Master_Soldier.Master_Soldier_C"
-- the player's perk turret (plain Actor; Q1_Character references it, so it loads with the player)
G.PerkTurret   = "/Game/IndustrialMachine2/Blueprints/Player_PerkTurret.Player_PerkTurret_C"
G.PerkTurretCDO = "/Game/IndustrialMachine2/Blueprints/Player_PerkTurret.Default__Player_PerkTurret_C"
-- the minibosses' "MiniTurrets" turret (shoots the player and companions only)
G.MiniTurret   = "/Game/IndustrialMachine2/Blueprints/NPC_Shooter_Turret.NPC_Shooter_Turret_C"
-- the barricade perk's energy-shield wall (Delay(LifeTime) -> destroy; no damage events)
G.Barricade    = "/Game/1Data/Perks/CharacterPerks/Barricde.Barricde_C"
G.BarricadeCDO = "/Game/1Data/Perks/CharacterPerks/Barricde.Default__Barricde_C"
G.BarricadeAsset = "/Game/1Data/Perks/CharacterPerks/Barricde"
-- kneel-and-work montage used by the trip-mine perk
G.KneelMontage = "/Game/Locomotion/CharacterAssets/Animations/Mage_Beam_L_Loop_IP_Montage.Mage_Beam_L_Loop_IP_Montage"
G.GameplayStatics = "/Script/Engine.Default__GameplayStatics"

-- Short class names (GetClass():GetFName()) -------------------------------------
G.PlayerClassNames     = { Q1_Character_C = true }
G.PerkTurretClassNames = { Player_PerkTurret_C = true }
G.MiniTurretClassNames = { NPC_Shooter_Turret_C = true }
G.ShooterClassNames = { -- same list as HTR's gamedefs.lua
    Q1_Shooter_AI_C = true, Q1_GuardShooter_C = true, Q1_Shooter_Robot_C = true, Q1_Boss_C = true,
    Q1_MasterMiniBoss_C = true, SneakyMiniBoss_C = true, Q1_Companin_AI_C = true, Q1_Civil_Follower_C = true,
    CargoShooter_C = true, SalvageDungeonEnemy_C = true, EBP_Sister_C = true, EBP_SisterTween_C = true,
}
G.SoldierClassNames = { Master_Soldier_C = true }
-- Damage causers whose class name contains one of these count as explosions (grenades, rockets...).
-- A guess until P1 logs the real causer classes of radial damage.
G.ExplosiveNamePatterns = { "granede", "grenade", "rocket", "missile", "explos", "bomb", "mine" }

-- Hooked Blueprint functions (post-hooks only) -----------------------------------
local XV = ":BndEvt__Q1_Shooter_AI_XVisionEye_K2Node_ComponentBoundEvent_"
local RE = ":BndEvt__Q1_Shooter_AI_RifleEye_K2Node_ComponentBoundEvent_"
G.Fn = {
    -- player
    PlayerTick       = G.ALSBase .. ":ReceiveTick",                     -- every frame, every ALS character
    MoveSettings     = G.ALSBase .. ":UpdateDynamicMovementSettings",   -- (AllowedGait); rewrites MaxWalkSpeed
    CanSprint        = G.ALSBase .. ":CanSprint",                       -- (out CanSprint)
    Regenerators     = G.ALSBase .. ":Regenerators",                    -- 0.25 s timer: energy regen, perk cooldowns +0.25
    SpawnTurretsPerk = G.Player .. ":SpawnTurrets",                     -- the vanilla turret perk button
    BarricadePerk    = G.Player .. ":ActiavateBarricate",               -- (sic) the vanilla barricade perk button
    -- turrets
    TurretBeginPlay  = G.PerkTurret .. ":ReceiveBeginPlay",
    TurretTick       = G.PerkTurret .. ":ReceiveTick",                  -- (DeltaSeconds)
    TurretDamage     = G.PerkTurret .. ":ReceiveAnyDamage",             -- (Damage, DamageType, InstigatedBy, DamageCauser); vanilla body is empty
    TurretShoot      = G.PerkTurret .. ":JustShoot",                    -- one round
    MiniTurretDamage = G.MiniTurret .. ":ReceiveAnyDamage",             -- vanilla: player damage only
    -- enemy / companion shooters
    NpcThink         = G.Shooter .. ":CheckMeleeDistance",              -- every 1 s on every shooter
    NpcPointDamage   = G.Shooter .. ":ReceivePointDamage",              -- (..., InstigatedBy, DamageCauser, HitInfo)
    NpcJustShoot     = G.Shooter .. ":JustShoot",                       -- only for the simulated-hit fallback
    NpcSightDetected = G.Shooter .. XV .. "0_OnTargetDetected__DelegateSignature",
    NpcSightUpdated  = G.Shooter .. XV .. "2_OnTargetUpdated__DelegateSignature",
    NpcRifleDetected = G.Shooter .. RE .. "3_OnTargetDetected__DelegateSignature",
    NpcRifleUpdated  = G.Shooter .. RE .. "5_OnTargetUpdated__DelegateSignature",
    -- squad soldiers
    SquadBattle      = G.Soldier .. ":UpdateBattle",                    -- every 1.5 s per soldier
}
-- An enemy round hit something: (OutProjectileObject, OutHitResult, ...). Same functions HTR hooks.
G.ShooterProjectileHits = {
    G.Shooter .. ":OnProjectileHit_03F94406443931C1DCEDC2920A189A84",
    G.Shooter .. ":OnProjectileHit_EA71D2CB4AF2DDD1487199994F37FD32",
}

-- Properties (exact Blueprint names; some contain '?' or GUID suffixes) ----------
G.P = {
    -- player (Q1_Character / ALS_Base)
    DisableMove = "DisableMove", DesiredStance = "DesiredStance", Flying = "Flying?", AtDialog = "AtDialog?",
    WhereIsPlayer = "WhereIsPlayer", BarricadeLocation = "BarricadeLocation", Movement = "CharacterMovement",
    PerkTurret = "P_Turret",                                  -- Perk_Learned_DAta struct
    PerkBarricade = "P_Barricade",                            -- Perk_Learned_DAta struct
    BarrierCD  = "BarrierCD",                                 -- vanilla barricade cooldown flag (true = cooling down)
    PerkCD     = "CD_11_004AEE844C3C3A073EF8EAAC2B628430",    -- seconds since last use (vanilla needs >= 20-30)
    PerkLevel  = "Level_8_5CAAAC454DB7C9AFB663B48B7761E974",
    -- Player_PerkTurret_C / NPC_Shooter_Turret_C
    ActiveNow = "ActiveNow?", TurretDead = "NPCDead", LifeTime = "LifeTime", MaxHP = "MaxHP", CurrentHP = "CurrentHP",
    TurretTarget = "LastDetectedActor", OwnerShooter = "OwnerShooter", Ammo = "Ammo",
    InCombat = "PlayerInCombat",                             -- Q1_Character
    -- Q1_Shooter_AI
    Ready = "Ready?", Dead = "NPCDead", AIType = "AIType", IsCompanion = "IsCompanian", CanSee = "CanSeeTheTarget",
    ShootTarget = "ShooTarget", CurrentDetected = "CurrentDetected", LastDetected = "LastDetectedActor",
    SubType = "SubType", IsBoss = "IsBoss", Sniper = "IsSniper?", SwordAttack = "SwordAttackOn",
    -- Master_Soldier
    SoldierSide = "AI_Type", SoldierTarget = "C_Target", SoldierType = "SoldierType", Injured = "InInjuredMode",
}

-- Enums -----------------------------------------------------------------------------
G.Where       = { Space = 0, PlanetSurface = 1, Dungeon = 2, Wormhole = 3, StationTrans = 4, StationSubLevel = 5 }
G.AIType      = { Enemy = 0, Ally = 1, Civil = 2, Natural = 3, Guard = 4 }
G.SubType     = { Shooter = 0, Tank = 1, Melee = 2, Mage = 3 }
G.SoldierType = { Assulter = 0, Tank = 1, Medic = 2, Lazer = 3, Mech = 4, AntiMissile = 5, Sniper = 6, Turretci = 7 }
G.BossAbility = { MiniTurrets = 6 }     -- Q1_Shooter_AI:SelectAbility(6)
G.Stance      = { Standing = 0, Crouching = 1 }
G.RotationMode = { Aiming = 2 }

return G
