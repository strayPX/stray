-- stray – kleines Komfort-Addon für WoW Forever
-- Kern: gespeicherte Einstellungen, Event-Verteilung, Hilfsfunktionen, Optionsregister.

local ADDON_NAME, ns = ...
ns.name = ADDON_NAME

ns.defaults = {
    fastLoot = false,
    autoSell = false,
    autoRepair = false,
    deleteFill = false,
    deleteNoConfirm = false,
    questAccept = false,
    questTurnIn = false,
    cinematicFast = false,
    cinematicAlways = false,
    flightTimer = false,
    flightTimes = {}, -- gemessene Flugzeiten: ["Start > Ziel"] = Sekunden
}

ns.GOLD = { 1, 0.82, 0 }
ns.GOLD_DARK = { 0.79, 0.64, 0.29 }
ns.GREY = { 0.5, 0.5, 0.5 }

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local handlers = {}
local eventFrame = CreateFrame("Frame")

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do
        fn(...)
    end
end)

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    strayDB = strayDB or {}
    for key, value in pairs(ns.defaults) do
        if strayDB[key] == nil then
            strayDB[key] = (type(value) == "table") and {} or value
        end
    end
    ns.db = strayDB
    if ns.OnLoaded then ns.OnLoaded() end
end)

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

function ns.GetCVarOn(name)
    if C_CVar and C_CVar.GetCVarBool then
        return C_CVar.GetCVarBool(name)
    end
    return GetCVarBool(name)
end

function ns.SetCVarValue(name, value)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar(name, value)
    else
        SetCVar(name, value)
    end
end

function ns.GetVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return getMeta and getMeta(ADDON_NAME, "Version") or ""
end

function ns.Sound(kit)
    if kit then PlaySound(kit) end
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100stray|r: " .. msg)
end

function ns.FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- Gold-Betrag hübsch formatieren (mit Münzsymbolen, falls verfügbar)
function ns.FormatMoney(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return GetMoneyString and GetMoneyString(copper) or tostring(copper)
end

---------------------------------------------------------------------------
-- Optionsregister: Funktionsmodule melden hier ihre Checkboxen an,
-- ui.lua baut daraus das Fenster (Spalte → Abschnitte → Optionen).
---------------------------------------------------------------------------

ns.columns = { {}, {} }

function ns.AddOption(column, sectionName, option)
    local sections = ns.columns[column]
    local section
    for _, s in ipairs(sections) do
        if s.name == sectionName then section = s break end
    end
    if not section then
        section = { name = sectionName, options = {} }
        table.insert(sections, section)
    end
    if not option.get then
        option.get = function() return ns.db[option.key] end
    end
    if not option.set then
        option.set = function(value) ns.db[option.key] = value end
    end
    table.insert(section.options, option)
end
