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
    chatLinks = false,
    cameraMax = false,
    minimapWheel = false,
    hideErrors = false,
    durability = false,
    declineDuels = false,
    acceptRes = false,
    acceptSummon = false,
    questItemMarks = false,
    questItemSellWarn = false,
    gossipSkip = false,
    freeSlots = false,
    -- Schadensmesser
    dmShow = false,
    dmAutoReset = false,
    dmMode = "damage", -- "damage" oder "healing"
    -- Gruppenrahmen
    partyFrames = false,
    partyHideBlizzard = false,
    partyWidth = 96,
    partyHeight = 42,
    partySpacing = 4,
    partyBrightness = 60,
    lockFrames = false, -- Griffleisten an den Anzeigen (false = entsperrt)
    minimapButton = true, -- Ausnahme: anfangs an, weil der Knopf der Zugang zum Fenster ist
    minimapAngle = 225,
    threatList = false,
    threatPlates = false,
    threatPercent = false,
    threatTankWarn = false,
    threatAggroWarn = false,
    positions = {}, -- verschobene Anzeigen: [Schlüssel] = { Punkt, relPunkt, x, y }
}

-- Einstellungen, die es nicht mehr gibt (Flugzeit, entfernt in 0.4.0-alpha)
local REMOVED_KEYS = { "flightTimer", "flightTimes" }

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
    for _, key in ipairs(REMOVED_KEYS) do
        strayDB[key] = nil
    end
    ns.db = strayDB
    if ns.OnLoaded then ns.OnLoaded() end
end)

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

-- WoW Forever kann Werte versiegeln („secret values“, z. B. im Kampf).
-- Damit darf ein Addon nicht vergleichen oder rechnen – vorher prüfen.
function ns.IsSecret(value)
    if not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

-- Gibt den Wert zurück, oder nil, wenn er versiegelt ist
function ns.Public(value)
    if ns.IsSecret(value) then return nil end
    return value
end

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

-- Gold-Betrag hübsch formatieren (mit Münzsymbolen, falls verfügbar)
function ns.FormatMoney(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return GetMoneyString and GetMoneyString(copper) or tostring(copper)
end

---------------------------------------------------------------------------
-- Kleine Anzeigen am Bildschirm (Haltbarkeit, Bedrohung):
-- einheitlicher Rahmen, mit Shift + linker Maustaste verschiebbar
---------------------------------------------------------------------------

ns.BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

function ns.ApplyBackdrop(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)
    frame:SetBackdropBorderColor(ns.GOLD_DARK[1], ns.GOLD_DARK[2], ns.GOLD_DARK[3], 0.9)
end

function ns.MakeMovable(frame, key, defaultPoint)
    frame.strayKey = key
    frame.strayDefault = defaultPoint
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.positions[key] = { point, relPoint, x, y }
    end)
end

function ns.RestorePosition(frame)
    local pos = (ns.db and ns.db.positions[frame.strayKey]) or frame.strayDefault
    frame:ClearAllPoints()
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end

-- Ist das stray-Fenster offen oder läuft der Bearbeiten-Modus?
-- (Anzeigen zeigen dann Beispielwerte, damit man sie sehen und verschieben kann)
ns.editMode = false

function ns.IsConfigOpen()
    if ns.editMode then return true end
    return strayFrame and strayFrame:IsShown() or false
end

ns.configCallbacks = {}

-- fn(open) wird aufgerufen, wenn das stray-Fenster bzw. der Bearbeiten-Modus auf- oder zugeht
function ns.OnConfig(fn)
    table.insert(ns.configCallbacks, fn)
end

function ns.NotifyConfig()
    local open = ns.IsConfigOpen()
    for _, fn in ipairs(ns.configCallbacks) do pcall(fn, open) end
end

-- Verschiebbare Anzeigen für den Bearbeiten-Modus.
-- frame braucht strayKey/strayDefault (über ns.MakeMovable). preview(on) blendet bei Bedarf
-- Beispielinhalt ein, den die Anzeige sonst nur bei offenem stray-Fenster zeigt.
ns.movables = {}

-- opts.grip = false: keine Griffleiste (z. B. Warntexte, die nur kurz erscheinen)
function ns.RegisterMovable(frame, label, preview, opts)
    table.insert(ns.movables, { frame = frame, label = label, preview = preview, grip = not (opts and opts.grip == false) })
end

---------------------------------------------------------------------------
-- Optionsregister: Funktionsmodule melden hier ihre Checkboxen an,
-- ui.lua baut daraus das Fenster (Spalte → Abschnitte → Optionen).
---------------------------------------------------------------------------

ns.columns = { {}, {}, {} }

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
