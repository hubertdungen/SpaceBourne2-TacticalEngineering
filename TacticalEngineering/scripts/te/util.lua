--[[
  Shared helpers, adapted from HTR's htr/util.lua (same safety rules):
   * Game objects are only touched inside hook callbacks or right after a lookup.
     No UObject is kept from one frame to the next (except engine singletons such as
     GameplayStatics and the PlayerController, re-checked with IsValid before each use, as
     in HTR); state is plain numbers/strings
     keyed by address. A turret is found again by its path (U.find), which costs
     ~0 ms while it exists - only look it up while its tick heartbeat is fresh,
     because a failed lookup costs ~37 ms.
   * Post-hooks on Blueprint functions only. Never hook native functions or LoadMap.
   * No FindAllOf / GetAllActorsOfClass in anything that runs during a fight.
]]

local U = {}

-- Mod folder (UE4SS may report ...\Scripts\ or ...\scripts\).
do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local lower = src:lower()
    local cut
    for i in lower:gmatch("()[\\/]scripts[\\/]") do cut = i end
    U.Dir = cut and src:sub(1, cut) or ".\\Mods\\TacticalEngineering\\"
end
U.LogFile = U.Dir .. "te.log"
U.Verbose = false

function U.log(...)
    if not U.Verbose then return end
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), table.concat(t, " "), "\n"); f:close() end
end

-- Always printed (UE4SS.log) and logged.
function U.warn(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local msg = table.concat(t, " ")
    print("[TE] " .. msg .. "\n")
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), "WARN ", msg, "\n"); f:close() end
end

function U.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v
end

function U.addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

function U.className(o)
    if not U.valid(o) then return nil end
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or nil
end

-- Object path usable with StaticFindObject ("Class /Game/...:PersistentLevel.Name" -> "/Game/...").
function U.path(o)
    local ok, s = pcall(function() return o:GetFullName() end)
    if not ok or type(s) ~= "string" then return nil end
    return s:match("^%S+%s+(.+)$") or s
end

-- Find an object again by path. Only call while you know it exists (a miss costs ~37 ms).
function U.find(path)
    if not path then return nil end
    local o = StaticFindObject(path)
    if U.valid(o) then return o end
    return nil
end

function U.get(o, prop, default)
    local ok, v = pcall(function() return o[prop] end)
    if ok and v ~= nil then return v end
    return default
end

function U.set(o, prop, value)
    return pcall(function() o[prop] = value end)
end

function U.location(actor)
    local ok, l = pcall(function() return actor:K2_GetActorLocation() end)
    if ok and l then return { X = l.X, Y = l.Y, Z = l.Z } end
    return nil
end

function U.dist(a, b)
    if not (a and b) then return 1e9 end
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function U.clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

local GS
function U.gameplayStatics()
    if not U.valid(GS) then GS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
    return GS
end

-- The player's pawn from any live object in the world (instant engine call).
function U.playerPawn(ctx)
    if ctx == nil then return nil end
    local ok, p = pcall(function() return U.gameplayStatics():GetPlayerPawn(ctx, 0) end)
    if ok and U.valid(p) then return p end
    return nil
end

-- Is Shift, Ctrl or Alt held right now? Asked of the game's own input, so the plain deploy key
-- stays quiet when the player presses Shift+Delete (a spare for other mods). Same as HTR 0.4.4's
-- U.modifierDown. Key presses only: the first call looks the controller up (~50 ms, once).
local PC
local MOD_KEYS = { "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt" }
local function controller()
    if not U.valid(PC) then PC = FindFirstOf("PlayerController") end
    return U.valid(PC) and PC or nil
end
function U.modifierDown()
    local pc = controller()
    if not pc then return false end
    for _, k in ipairs(MOD_KEYS) do
        local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if ok and down then return true end
    end
    return false
end

-- Is this key held right now? name: an Unreal key name ("Delete", "F11"...). Polled only while
-- the deploy key is down (tap vs hold).
function U.keyDown(name)
    if not name then return false end
    local pc = controller()
    if not pc then return false end
    local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(name) }) end)
    return ok and down == true
end

-- UE4SS key name -> Unreal key name (for U.keyDown).
local UE_KEY = { DEL = "Delete", INS = "Insert", HOME = "Home", END = "End", PAGE_UP = "PageUp",
    PAGE_DOWN = "PageDown", ESCAPE = "Escape", SPACE = "SpaceBar", TAB = "Tab", BACKSPACE = "BackSpace" }
local UE_LABEL = { DEL = "Delete", INS = "Insert", PAGE_UP = "Page Up", PAGE_DOWN = "Page Down" }
function U.unrealKey(ue4ssName)
    if not ue4ssName then return nil end
    if UE_KEY[ue4ssName] then return UE_KEY[ue4ssName] end
    if ue4ssName:match("^F%d+$") or ue4ssName:match("^%u$") then return ue4ssName end
    return nil -- unknown: taps still work, holding to switch on/off does not
end
function U.keyLabel(ue4ssName)
    return UE_LABEL[ue4ssName or ""] or ue4ssName
end

-- The HUD warning plays the game's "can't do that" alarm (GUI_Cant, "tu-tu-tu"). Like HTR 0.4.6,
-- with U.Quiet that one sound is muted for 2 s around our own messages (a SoundWave's Volume is
-- applied while it plays); the game's own warnings keep their sound. If another mod (HTR) has it
-- muted right now, its normal volume (2.0) is assumed instead of saving 0 as "normal".
local CANT = "/Game/11Misc/LGUI/Audio/GUI_Cant.GUI_Cant"
local CANT_NORMAL = 2.0
local cantVolume, unmuteAt = nil, 0
local function muteAlarm()
    if not U.Quiet then return end
    local snd = StaticFindObject(CANT) -- loaded with the HUD (the warning widgets reference it)
    if not U.valid(snd) then return end
    if cantVolume == nil then
        -- the set agrees on the normal volume through "SB2R_CantVolume" (HTR 0.4.8, Silent Ops 0.2)
        local okS, shared = pcall(function() return ModRef and ModRef:GetSharedVariable("SB2R_CantVolume") end)
        if okS and type(shared) == "number" and shared > 0 then
            cantVolume = shared
        else
            local ok, v = pcall(function() return snd.Volume end)
            if not (ok and type(v) == "number") then return end
            cantVolume = (v > 0) and v or CANT_NORMAL
            pcall(function() ModRef:SetSharedVariable("SB2R_CantVolume", cantVolume) end)
        end
    end
    pcall(function() snd.Volume = 0.0 end)
    unmuteAt = os.clock() + 2.0
    -- on the game thread (gametick.lua; 0.2.2 and earlier used ExecuteWithDelay: UE4SS crash risk)
    require("te.gametick").after(2.1, function(now)
        if now < unmuteAt then return end -- a newer message keeps it quiet a bit longer
        local s = StaticFindObject(CANT)
        if U.valid(s) and cantVolume then pcall(function() s.Volume = cantVolume end) end
    end)
end

-- On-screen message on foot (verified in HTR 0.4.1: the HUD warning used for "No Target Nearby").
function U.notify(pawn, text)
    if not U.valid(pawn) then return false end
    U.log("msg: " .. tostring(text))
    pcall(muteAlarm)
    return pcall(function() pawn:TMWPerkWarning(FText(text)) end)
end

-- Simple key=value state file next to the mod.
function U.loadState(file)
    local t = {}
    local f = io.open(U.Dir .. file, "r")
    if not f then return t end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then t[k] = tonumber(v) or v end
    end
    f:close()
    return t
end

function U.saveState(file, t)
    local f = io.open(U.Dir .. file, "w")
    if not f then return false end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(k, "=", tostring(t[k]), "\n") end
    f:close()
    return true
end

return U
