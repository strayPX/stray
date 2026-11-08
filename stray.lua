-- stray – kleines Komfort-Addon für WoW Forever
-- Kern: gespeicherte Einstellungen, Event-Verteilung, Hilfsfunktionen, Optionsregister.

local ADDON_NAME, ns = ...
ns.name = ADDON_NAME
-- Version der Lua-Dateien. Beim Release zusammen mit „## Version:“ in stray.toc anheben:
-- WoW liest die toc nur beim Spielstart, der Vergleich beider Werte zeigt, ob nach einem Update
-- ein kompletter Neustart nötig ist (siehe PLAYER_LOGIN unten).
ns.VERSION = "1.1.0"
local L = ns.L

ns.defaults = {
    language = "auto", -- Sprache von stray: "auto" (Client), "deDE" oder "enUS"
    uiStyle = "stray", -- Oberflächen-Stil: "stray" (lila, flach) oder "forever" (Bronze & Gold), siehe style.lua
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
    -- DMG-Meter
    dmShow = false,
    dmAutoReset = false,
    dmMode = "damage", -- "damage" oder "healing"
    dmWidth = 230,
    dmHeight = 190,
    -- Gruppenrahmen
    partyFrames = false,
    partyHideBlizzard = false,
    partyWidth = 96,
    partyHeight = 42,
    partySpacing = 4,
    partyBrightness = 60,
    -- Oberfläche (hud.lua)
    hudMinimapColumn = false,
    hudClock = false,
    hudXPBar = false,
    -- Aktionsleisten (actionbars.lua)
    abEnabled = false,
    abSize = 36,
    abSpacing = 2,
    abKeybinds = true,
    -- je Leiste 1–5: anzeigen, Knopfgröße, Knöpfe pro Reihe (Standard: Leisten 1–4 an, 12 pro Reihe)
    abShow1 = true, abShow2 = true, abShow3 = true, abShow4 = true, abShow5 = false,
    abSize1 = 36, abSize2 = 36, abSize3 = 36, abSize4 = 36, abSize5 = 36,
    abCols1 = 12, abCols2 = 12, abCols3 = 12, abCols4 = 12, abCols5 = 12,
    -- Abklingzeiten (cooldowns.lua)
    cdManager = false,
    cdSize = 36,
    -- Taschenfenster (bagwindow.lua)
    bagWindow = false,
    bagColumns = 10,
    bagPinned = {},
    updateNotice = true, -- Chat-Hinweis nach einem Update (Reload oder Neustart)
    -- lastVersion: zuletzt gesehene Version, wird beim ersten Login gesetzt (kein Standardwert)
    minimapButton = true, -- Ausnahme: anfangs an, weil der Knopf der Zugang zum Fenster ist
    minimapAngle = 225,
    threatList = false,
    threatPlates = false,
    threatPercent = false,
    threatTankWarn = false,
    threatAggroWarn = false,
    positions = {}, -- verschobene Anzeigen: [Schlüssel] = { Punkt, relPunkt, x, y }
    scales = {},    -- Größe je Anzeige aus dem Bearbeitungsmodus: [Schlüssel] = Faktor (0.5–2), fehlt = 1
}

-- Einstellungen, die es nicht mehr gibt (Flugzeit 0.4.0-alpha, Questtracker nach 1.0.0)
local REMOVED_KEYS = { "flightTimer", "flightTimes", "questTracker", "questTrackerAlpha", "questTrackerCollapsed", "questTrackerGroup",
    "questTrackerHeight", "questTrackerHideBlizzard", "questTrackerRecipes", "questTrackerRecipesCollapsed", "questTrackerShowAll",
    "questTrackerSort", "questTrackerTop", "questTrackerWidth", "questTrackerZones" }

ns.GOLD = { 1, 0.82, 0 }
ns.GOLD_DARK = { 0.79, 0.64, 0.29 }
ns.GREY = { 0.5, 0.5, 0.5 }

-- Gemeinsame Farben im stray-Look (gedämpftes Lila, keine Verläufe). Alle Fenster und Anzeigen nutzen
-- diese Werte; Funktionsfarben (Klassen, Aggro, Qualität, Leben/Mana) bleiben eigene.
ns.Colors = {
    bg         = { 0.078, 0.078, 0.098, 0.96 }, -- #141419 Fenster
    card       = { 0.094, 0.094, 0.118, 1 },    -- #18181e Karten
    hover      = { 0.122, 0.122, 0.153, 1 },    -- #1f1f27 gewählt/Hover
    line       = { 0.149, 0.149, 0.184, 1 },    -- #26262f Linien
    accent     = { 0.545, 0.486, 0.965, 1 },    -- #8b7cf6 Akzent Lila
    accentText = { 0.702, 0.659, 0.980, 1 },    -- #b3a8fa Lila für Text (Titel)
    text       = { 0.902, 0.902, 0.925, 1 },    -- #e6e6ec
    textDim    = { 0.545, 0.545, 0.600, 1 },    -- #8b8b99
    textFaint  = { 0.369, 0.369, 0.420, 1 },    -- #5e5e6b
    -- Entsprechungen für den Stil „Forever UI“ (style.lua überschreibt sie dort mit Gold/Bronze/Rot);
    -- im Stil „stray“ im lila Ton, damit Module nicht verzweigen müssen
    gold        = { 0.702, 0.659, 0.980, 1 },    -- wie accentText
    goldDim     = { 0.545, 0.486, 0.965, 1 },    -- wie accent
    bronze      = { 0.298, 0.298, 0.369, 1 },
    bronzeLight = { 0.545, 0.545, 0.600, 1 },
    bronzeDark  = { 0.149, 0.149, 0.184, 1 },
    red         = { 0.890, 0.360, 0.360, 1 },
    redDim      = { 0.550, 0.220, 0.220, 1 },
}

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
        -- Ein Fehler in einem Modul darf die anderen Module nicht aufhalten
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
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
    -- Stil-Palette zuerst, damit alle folgenden Handler und Module die gewählten Farben sehen
    if ns.Style then ns.Style.Apply() end
    -- Sprache zuerst, damit alle folgenden Handler und ns.L die gewählte Sprache sehen
    if ns.SetLanguage then ns.SetLanguage(strayDB.language) end
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

-- Größe je Anzeige (ns.db.scales[strayKey]) anwenden. Ohne Eintrag bleibt der Maßstab unberührt,
-- außer stray hat die Anzeige vorher vergrößert/verkleinert: dann zurück auf 1.
-- Geschützte Rahmen (z. B. Aktionsleisten) nur außerhalb des Kampfes.
local scaled = {} -- [frame] = true, solange stray einen Maßstab ungleich 1 gesetzt hat

function ns.ApplyScale(frame)
    local key = frame and frame.strayKey
    if not key or not ns.db or type(ns.db.scales) ~= "table" then return end
    local s = tonumber(ns.db.scales[key])
    if s then
        s = math.max(0.5, math.min(2, s))
    elseif scaled[frame] then
        s = 1
    else
        return
    end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end
    if math.abs((frame:GetScale() or 1) - s) > 0.001 then
        local ok, err = pcall(frame.SetScale, frame, s)
        if not ok then geterrorhandler()(err) return end
    end
    scaled[frame] = (s ~= 1) or nil
end

function ns.RestorePosition(frame)
    ns.ApplyScale(frame)
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
-- opts (optional) für das Fenster je Anzeige im Bearbeitungsmodus:
--   widthKey / heightKey = Schlüssel einer vorhandenen Slider-Option (ns.AddOption, type="slider");
--     das Fenster zeigt dann Breite/Höhe und ändert den Wert über deren set (Grenzen min/max/step).
--     Gibt es keine solche Option, gelten widthMin/widthMax bzw. heightMin/heightMax: der Wert landet
--     in ns.db[Schlüssel], danach läuft onSize(welche, wert) mit welche = "width" oder "height".
--   noScale = true blendet „Größe %“ aus (für Anzeigen, bei denen SetScale nichts bewirkt).
ns.movables = {}

function ns.RegisterMovable(frame, label, preview, opts)
    if type(opts) ~= "table" then opts = nil end
    table.insert(ns.movables, { frame = frame, label = label, preview = preview, opts = opts })
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
    -- Optionale Stichwörter für die Suche (deutsch + englisch): keywords = { "aggro", "threat" }
    if type(option.keywords) == "string" then
        option.keywords = { option.keywords }
    elseif type(option.keywords) ~= "table" then
        option.keywords = nil
    end
    table.insert(section.options, option)
end

---------------------------------------------------------------------------
-- Update-Hinweis im Chat: Neustart nötig oder nur „aktualisiert“ (einmal pro Login)
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    local db = ns.db
    if type(db) ~= "table" then return end
    local current = ns.VERSION
    local show = db.updateNotice ~= false
    -- toc-Version = Stand beim Spielstart (ändert sich bei /reload nicht)
    local ok, tocVersion = pcall(ns.GetVersion)
    if not ok or type(tocVersion) ~= "string" or tocVersion == "" then return end -- nicht lesbar: nichts melden
    if tocVersion ~= current then
        -- Dateien sind neuer als beim Spielstart: Reload reicht nicht, lastVersion bleibt unberührt
        if show then
            ns.Print("|cffff8000" .. string.format(
                L["stray wurde aktualisiert (Version %s). Bitte WoW komplett neu starten – ein /reload reicht nicht, weil neue Dateien erst beim Start geladen werden."],
                current) .. "|r")
        end
        return
    end
    local last = db.lastVersion
    if type(last) == "string" and last ~= current and show then
        ns.Print(string.format(L["stray wurde auf Version %s aktualisiert. Neuerungen: /stray"], current))
    end
    db.lastVersion = current
end)

ns.AddOption(3, "Profile", {
    key = "updateNotice",
    label = L["Update-Hinweis im Chat"],
    tooltip = L["Zeigt nach einem Update im Chat, ob ein /reload reicht oder WoW neu gestartet werden muss."],
    keywords = { "update", "version", "neustart", "reload", "hinweis", "restart", "notice" },
})

---------------------------------------------------------------------------
-- Sprache (Seite System, Bereich Profile; wirkt nach dem Neuladen)
---------------------------------------------------------------------------

ns.AddOption(3, "Profile", {
    key = "language",
    type = "choice",
    label = L["Sprache"],
    values = { "auto", "deDE", "enUS" },
    labels = { L["Automatisch"], "Deutsch", "English" },
    tooltip = L["Sprache von stray. „Automatisch“ folgt der Sprache des Spiels.\nWird nach dem Neuladen wirksam."],
    keywords = { "sprache", "language", "deutsch", "german", "englisch", "english", "übersetzung", "translation" },
})
