-- stray – Interface-Einstellungen für alle Charaktere
-- Der Client speichert manche Einstellungen (CVars) je Charakter auf dem Server
-- (C_CVar.GetCVarInfo → isStoredServerCharacter). stray merkt sich ihre Werte vom zuletzt
-- gespielten Charakter und übernimmt sie beim Einloggen eines anderen Charakters.
-- Nur Interface-CVars: keine Grafik-, Ton-, Netz- oder Debug-CVars, keine geschützten,
-- schreibgeschützten oder gesperrten CVars. Im Kampf wird nichts gesetzt, sondern nachgeholt.

local _, ns = ...
local L = ns.L

ns.defaults.accountCVars = false
ns.defaults.accountCVarData = {} -- { source = "Name-Realm", time = Zeitpunkt, values = { [cvar] = Wert } }

local START_DELAY = 3     -- Sekunden nach dem Einloggen, bis die Charakter-CVars sicher geladen sind
local CAPTURE_DELAY = 2   -- Änderungen bündeln

-- Konsolen-Kategorien (Enum.ConsoleCategory), die nichts mit dem Interface zu tun haben
local SKIP_CATEGORIES = { [0] = true, [1] = true, [2] = true, [6] = true, [7] = true, [8] = true } -- Debug, Grafik, Konsole, Netz, Ton, GM
local CVAR_TYPE = 0 -- Enum.ConsoleCommandType.Cvar

-- CVars, die Spielstand statt Einstellung sind (zuletzt gewählter Reiter, gesehene Hinweise,
-- verfolgte Quests, Filter …) – die sollen je Charakter bleiben
local SKIP_PATTERNS = {
    "^last", "[Tt]utorial", "^closed", "[Ss]een", "[Tt]racked", "[Tt]racking",
    "[Ff]ilter", "[Ss]ort", "[Cc]ollapsed", "[Ff]avorite", "[Vv]ersion", "[Hh]istory",
    "[Ss]elected", "[Ll]oadout", "[Tt]alent", "[Ss]pec", "[Cc]alendar", "[Ff]lagged",
    "Shown$", "Index$", "ID$", "Id$", "Time$", "Date$",
}

if Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar then
    CVAR_TYPE = Enum.ConsoleCommandType.Cvar
end
if Enum and Enum.ConsoleCategory then
    local cat = Enum.ConsoleCategory
    SKIP_CATEGORIES = {}
    for _, name in ipairs({ "Debug", "Graphics", "Console", "Net", "Sound", "Gm" }) do
        if cat[name] then SKIP_CATEGORIES[cat[name]] = true end
    end
end

---------------------------------------------------------------------------
-- Ereignisse (eigener Rahmen, unbekannte Ereignisse ohne Fehler)
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

local function SafeOn(event, fn)
    if not eventHandlers[event] then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return end
        eventHandlers[event] = {}
    end
    table.insert(eventHandlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(eventHandlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function PlayerKey()
    local ok, name = pcall(UnitName, "player")
    if not ok or ns.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if ns.IsSecret(realm) or type(realm) ~= "string" or realm == "" then return name, name end
    return name .. "-" .. realm, name
end

local function Data()
    if not ns.db then return nil end
    if type(ns.db.accountCVarData) ~= "table" then ns.db.accountCVarData = {} end
    local data = ns.db.accountCVarData
    if type(data.values) ~= "table" then data.values = {} end
    return data
end

local function AllCommands()
    local getAll = (C_Console and C_Console.GetAllCommands) or ConsoleGetAllCommands
    if not getAll then return nil end
    local ok, list = pcall(getAll)
    if ok and type(list) == "table" then return list end
    return nil
end

local function GetValue(name)
    if not C_CVar or not C_CVar.GetCVar then return nil end
    local ok, value = pcall(C_CVar.GetCVar, name)
    if not ok or ns.IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

local function Skipped(name)
    for _, pattern in ipairs(SKIP_PATTERNS) do
        if name:find(pattern) then return true end
    end
    return false
end

-- Liste der charakterbezogenen Interface-CVars (einmal je Sitzung ermittelt)
local candidates

local function Candidates()
    if candidates then return candidates end
    local list = {}
    local commands = AllCommands()
    if commands and C_CVar and C_CVar.GetCVarInfo then
        for _, info in ipairs(commands) do
            local name = type(info) == "table" and info.command
            if type(name) == "string" and info.commandType == CVAR_TYPE
                and not SKIP_CATEGORIES[info.category] and not Skipped(name) then
                local ok, value, _, _, perCharacter, locked, secure, readOnly = pcall(C_CVar.GetCVarInfo, name)
                if ok and type(value) == "string" and perCharacter == true
                    and not locked and not secure and not readOnly then
                    list[name] = true
                end
            end
        end
    end
    candidates = list
    return list
end

local function CountCandidates()
    local n = 0
    for _ in pairs(Candidates()) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Speichern und Übernehmen
---------------------------------------------------------------------------

local ready = false     -- erst nach dem Übernehmen speichern, sonst überschriebe der neue Charakter alles
local applying = false
local pendingApply = false

local function Capture()
    if not ready or applying or not ns.db or not ns.db.accountCVars then return end
    local data = Data()
    local key = PlayerKey()
    if not data or not key then return end
    local values = {}
    for name in pairs(Candidates()) do
        local value = GetValue(name)
        if value then values[name] = value end
    end
    data.values = values
    data.source = key
    data.time = time()
end

local captureQueued = false

local function CaptureSoon()
    if not ready or applying or captureQueued then return end
    captureQueued = true
    C_Timer.After(CAPTURE_DELAY, function()
        captureQueued = false
        Capture()
    end)
end

local function Apply()
    if not ns.db or not ns.db.accountCVars then
        ready = true
        return
    end
    if InCombat() then
        pendingApply = true
        return
    end
    pendingApply = false
    local data = Data()
    local key = PlayerKey()
    if not data or not key then
        ready = true
        return
    end
    local count = 0
    if data.source and data.source ~= key and C_CVar and C_CVar.SetCVar then
        applying = true
        local list = Candidates()
        for name, value in pairs(data.values) do
            if list[name] and type(value) == "string" then
                local current = GetValue(name)
                if current and current ~= value then
                    local ok, success = pcall(C_CVar.SetCVar, name, value)
                    if ok and success ~= false then count = count + 1 end
                end
            end
        end
        applying = false
        if count > 0 then
            local source = data.source:match("^([^%-]+)") or data.source
            ns.Print(count == 1 and L("%d Einstellung von %s übernommen.", count, source)
                or L("%d Einstellungen von %s übernommen.", count, source))
        end
    end
    ready = true
    Capture()
end

SafeOn("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
    if ready then return end
    if not isInitialLogin and not isReloadingUi then return end
    C_Timer.After(START_DELAY, function()
        local ok, err = pcall(Apply)
        if not ok then
            applying = false
            ready = true
            geterrorhandler()(err)
        end
    end)
end)

SafeOn("PLAYER_REGEN_ENABLED", function()
    if pendingApply then Apply() end
end)

SafeOn("CVAR_UPDATE", CaptureSoon)
SafeOn("PLAYER_LOGOUT", Capture)

---------------------------------------------------------------------------
-- Option
---------------------------------------------------------------------------

ns.AddOption(3, "Charaktere", {
    key = "accountCVars",
    label = L["Interface-Einstellungen für alle Charaktere"],
    tooltip = L["Manche Interface-Einstellungen speichert das Spiel je Charakter. stray merkt sie sich vom zuletzt gespielten Charakter und übernimmt sie beim Einloggen eines anderen.\nGrafik und Ton gelten ohnehin für den ganzen Rechner und bleiben unberührt. Im Kampf wird nichts geändert."],
    set = function(value)
        ns.db.accountCVars = value
        if not value then return end
        local ok, n = pcall(CountCandidates)
        if not ok then return end
        if n == 0 then
            ns.Print(L["Dieser Client speichert keine Interface-Einstellungen je Charakter – es gibt nichts zu übernehmen."])
        else
            ns.Print(L("%d Interface-Einstellungen werden je Charakter gespeichert und ab jetzt für alle übernommen.", n))
        end
        -- Ab jetzt gilt dieser Charakter als Vorlage
        if ready then pcall(Capture) end
    end,
})
