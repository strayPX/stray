-- stray – Einstellungsfenster (seit 0.23.0-alpha nach Leons Vorlage)
-- Kopf über die ganze Breite: Logo + „stray“ links, breites Suchfeld, Knopf „Bearbeitungsmodus“ und
-- Schließen rechts. Links die Navigation: Übersicht (Funktionsliste nach Seiten mit An/Aus, zuletzt
-- geändert), Automation, Sozial & Chat, Interface, Kampf, Welt, stray (System) und Alle Anzeigen, mit
-- schlichten Liniensymbolen (gewählt = lila Strich links + helle Fläche), unten die Profil-Auswahl.
-- Reiter ohne Optionen und Seiten ohne Reiter werden nicht angezeigt. Frühere Seitennamen
-- (V.LEGACY_PAGES) führen auf die neuen Seiten.
-- Rechts je Seite ein großer Titel mit Häkchen „Aktiv“ (Hauptschalter des Moduls bzw. Reiters),
-- darunter Reiter (die Bereiche der Seite). Inhalt einspaltig: Abschnitts-Überschriften in
-- Großbuchstaben mit feiner Linie (ALLGEMEIN, ANORDNUNG, POSITION), Zeilen mit Name und Bedienelement
-- rechts: Schalter, Regler mit Zahlenfeld (tippbar, Pfeile), Auswahl als Dropdown, Knöpfe.
-- Verschiebbare Anzeigen der Seite bekommen den Abschnitt POSITION (X/Y ab Bildschirmmitte wie im
-- Bearbeitungsmodus + Zentrieren). Fußzeile: „n Änderungen“, Verwerfen, Übernehmen (lädt nur neu,
-- wenn eine geänderte Einstellung das braucht). Größe unten rechts ziehen.
-- Die Optionen kommen aus dem Register in stray.lua (ns.AddOption). Der Bereichsname ordnet eine
-- Option einem Reiter zu; einzelne Schlüssel lassen sich über PAGES (keys/prefix) umsetzen.
-- Optionstexte werden beim Laden in der Client-Sprache aufgelöst und hier über ns.T übersetzt.
-- Beim Öffnen merkt sich das Fenster eine Kopie der Einstellungen; beim Schließen mit Änderungen
-- fragt ein Dialog: Übernehmen oder Verwerfen (Stand beim Öffnen wiederherstellen).
-- Verträge für andere Module:
--   ns.RegisterInstances(name, { {id=, label=, strayKey=?}, … } oder function, getSelected, setSelected)
--     Auswahlliste über dem Inhalt eines Reiters oder einer Seite (name = Reiter- oder Seitenname),
--     z. B. „DMG-Meter 2“. Frühestens ab ADDON_LOADED aufrufen (ui.lua lädt zuletzt).
--   ns.ConfirmOption / ns.ConflictHint (conflicts.lua): Nachfrage beim Einschalten, Hinweis-Kasten.
--   ns.EditSelected / ns.OnEditSelect (editmode.lua): „Im Spiel ausgewählt“, Sprung zur Seite.
--   ns.slashCommands[befehl] = fn: eigene Unterbefehle für /stray.
-- Stil „forever“ (style.lua): Rahmen, Schiefer, Gold, Reiter, Knöpfe, Eingabefelder. Das Fenster baut sich erst
-- in ns.OnLoaded auf (Build-Teile), weil der Stil aus ns.db kommt; im Stil „stray“ bleibt alles wie bisher.
-- Symbole in media/icons: Tabler Icons (MIT-Lizenz, tabler.io); „meditation“ ist eigenes stray-Symbol
-- im gleichen Stil. media/logo: stray-Siegel.

local _, ns = ...
local L = ns.L
local T = ns.T or function(text) return text end

---------------------------------------------------------------------------
-- Maße und Farben
---------------------------------------------------------------------------

local M = {
    WIDTH = 940, HEIGHT = 620,   -- Standardgröße (Doppelklick auf den Griff)
    MIN_W = 820, MIN_H = 500,
    SIDE_W = 200,                -- Navigation links
    TOP_H = 56,                  -- Kopf über die ganze Breite
    FOOT_H = 52,                 -- Fußzeile rechts
    PROFILE_H = 50,              -- Profil-Auswahl unten links
    CL = 24, CR = 28,            -- Abstand des Inhalts links/rechts
    SCROLL_W = 640,              -- Breite des Inhalts; folgt der Fenstergröße
    ROW_H = 34,
    HEAD_H = 34,                 -- Abschnitts-Überschrift
    TAB_H = 30,
    NUM_W = 78,                  -- Zahlenfeld
    DROP_W = 170,                -- Dropdown
    WHEEL = 40,
    NAV_H = 32,
}

local MEDIA = "Interface\\AddOns\\stray\\media\\"
local ICONS = MEDIA .. "icons\\"
local FONT = "Fonts\\ARIALN.TTF"

-- Grundfarben aus ns.Colors (stray.lua), dazu ein paar nur hier gebrauchte
local NC = ns.Colors or {}
local C = {
    window   = NC.bg or { 0.078, 0.078, 0.098, 0.96 },
    card     = NC.card or { 0.094, 0.094, 0.118, 1 },
    hover    = NC.hover or { 0.122, 0.122, 0.153, 1 },
    line     = NC.line or { 0.149, 0.149, 0.184, 1 },
    accent   = NC.accent or { 0.545, 0.486, 0.965, 1 },
    accentT  = NC.accentText or { 0.702, 0.659, 0.980, 1 },
    accentHi = { 0.612, 0.557, 0.976, 1 },
    text     = NC.text or { 0.902, 0.902, 0.925, 1 },
    grey     = NC.textDim or { 0.545, 0.545, 0.600, 1 },
    faint    = NC.textFaint or { 0.369, 0.369, 0.420, 1 },
    navText  = { 0.78, 0.78, 0.82, 1 },
    off      = { 0.169, 0.169, 0.208, 1 },
    amber    = { 0.961, 0.682, 0.290, 1 },
    amberBg  = { 0.961, 0.682, 0.290, 0.08 },
    white    = { 1, 1, 1, 1 },
}
C.hi = C.white            -- hervorgehobener Text (Titel, gewählte Einträge); Forever: Gold
C.hint = C.text           -- Text im Hinweis-Kasten
C.num = C.text            -- Text im Zahlenfeld
C.navSel = C.hover        -- Fläche des gewählten Seiteneintrags
C.rest = C.grey           -- Ruhefarbe kleiner Symbole (Schließen, Pfeile, Griff)

---------------------------------------------------------------------------
-- Stil „forever“ (style.lua)
-- ns.db und damit der Stil sind erst ab ADDON_LOADED bekannt. Alles, was das Fenster aufbaut, läuft
-- deshalb in Build()-Teilen, die ns.OnLoaded der Reihe nach ausführt. Im Stil „stray“ bleibt alles wie
-- bisher; die Forever-Werte gelten erst nach SetupStyle().
---------------------------------------------------------------------------

local FOREVER = false  -- Stil „forever“ aktiv
local P = 0            -- Abstand der Fensterteile zum Rahmen (Forever: Rahmenstärke)
local FSCALE = 1       -- Schriftgröße relativ (Friz Quadrata ist breiter als Arial Narrow)
local FONT_NUM = FONT  -- Schrift für Zahlen
local BUILD = {}       -- aufgeschobene Aufbau-Teile

local function Build(fn) table.insert(BUILD, fn) end

-- Schriftgröße im aktuellen Stil
local function FS(size)
    if FSCALE == 1 then return size end
    return math.max(10, math.floor(size * FSCALE + 0.5))
end

-- ns.Style-Aufruf ohne Fehler zu verschlucken: bei Fehler melden und nil zurückgeben; der Aufrufer
-- baut dann im Stil „stray“ (Aufruf im Stil „stray“ liefert ebenfalls nil)
local function FX(name, ...)
    local fn = FOREVER and ns.Style and ns.Style[name]
    if not fn then return nil end
    local ok, res = pcall(fn, ...)
    if not ok then
        geterrorhandler()(res)
        return nil
    end
    return res
end

local function SetupStyle()
    FOREVER = ns.Style and ns.Style.IsForever and ns.Style.IsForever() or false
    if not FOREVER then return end
    local NC = ns.Colors
    P = 10
    FSCALE = 0.92
    FONT = ns.Style.Font()
    FONT_NUM = ns.Style.FontNumbers()
    M.TOP_H = M.TOP_H + P
    M.SIDE_W = 220
    M.DROP_W = 200
    -- Palette: Gold für Hervorhebungen, warme Neutraltöne, gelbbrauner Hinweis; Lila bleibt Akzent
    C.hi = NC.gold
    C.num = NC.gold
    C.hint = { 0.894, 0.812, 0.541, 1 }
    C.navText = NC.text
    C.navSel = { C.accent[1], C.accent[2], C.accent[3], 0.20 }
    C.rest = NC.goldDim
    C.faint = { 0.478, 0.447, 0.388, 1 }  -- besser lesbar auf dem Schiefer als textFaint
    C.off = { 0.043, 0.043, 0.051, 1 }
    C.amber = { 0.851, 0.722, 0.290, 1 }
    C.amberBg = { 0.165, 0.137, 0.051, 1 }
end

---------------------------------------------------------------------------
-- Seiten, Reiter und Zuordnung
---------------------------------------------------------------------------

-- Jede Seite hat Reiter. Ein Reiter sammelt Optionen: zuerst ausdrücklich genannte Schlüssel (keys),
-- dann Schlüssel nach Muster (prefix, ohne exclude), zuletzt ganze Bereiche (sections).
-- master = Schlüssel des Hauptschalters („Aktiv“); am Reiter geht vor der Seite; "first" = erster
-- Schalter des Reiters. Seiten- und Reiternamen sind deutsche Schlüssel (Anzeige über L).
-- Die Seiten ordnen nach dem Ort im Spiel (höchstens 6 Reiter je Seite); „Übersicht“ (home) und
-- „Alle Anzeigen“ (displays) sind eigene Seiten ohne Reiter.
local PAGES = {
    { name = "Übersicht", icon = "home", home = true },
    { name = "Automation", icon = "adjustments", tabs = {
        { name = "Quests", sections = { "Quests" } },
        { name = "NPCs", sections = { "NPCs" } },
        { name = "Filmsequenzen", sections = { "Filmsequenzen" } },
        { name = "Händler", sections = { "Händler" } },
        { name = "Beute", sections = { "Beute" } },
        { name = "Taschen", sections = { "Taschen" } },
        { name = "Automatisch", sections = { "Automatisch" } },
    } },
    { name = "Sozial & Chat", icon = "map-2", tabs = {
        { name = "Sozial", sections = { "Sozial" } },
        { name = "Charaktere", sections = { "Charaktere" } },
        { name = "Chat", sections = { "Chat", "Chat-Fenster" } },
    } },
    { name = "Interface", icon = "layout-grid", tabs = {
        { name = "Ausblenden", sections = { "Ausblenden" } },
        { name = "Text", sections = { "Text" } },
        { name = "Tooltip", sections = { "Tooltip" } },
        { name = "Charakter", sections = { "Charakter" } },
        { name = "Interface", sections = { "Interface" } },
        { name = "Kamera", sections = { "Kamera & Karte" } },
    } },
    -- stray-Tasche: Reiter nehmen ausdrückliche Schlüssel zuerst; „Fenster“ fängt den Rest des Bereichs „Tasche“
    -- auf, „Bank“ den Bereich „Bank“, „Twinks“ alles mit Präfix bagOffline
    { name = "Tasche", icon = "backpack", master = "bagWindow", tabs = {
        { name = "Fenster", sections = { "Tasche" }, keys = { "bagWindow", "bagView", "bagColumns", "bagSlotSize",
            "bagLocked", "bagMerge", "bagShowAllEmpty", "bagSidebar" } },
        { name = "Abschnitte", keys = { "bagShowPinned", "bagHidePinnedInCategories", "bagShowRecent",
            "bagArmoryBySlot", "bagHideAddCategory" } },
        { name = "Symbole", keys = { "bagIconSlots", "bagIconJunk", "bagIconSort", "bagIconQuick", "bagJunkGrey" } },
        { name = "Automatik", prefix = "^bagAuto", keys = { "bagAutoMerchant", "bagAutoMail", "bagAutoAuction",
            "bagAutoBank", "bagAutoTrade", "bagAutoCraft", "bagOpenWithCharacter" } },
        { name = "Bank", sections = { "Bank" }, keys = { "bagBank", "bagBankColumns" }, prefix = "^bagBank", master = "bagBank" },
        { name = "Twinks", prefix = "^bagOffline" },
    } },
    { name = "Kampf", icon = "swords", tabs = {
        { name = "Bedrohung", sections = { "Bedrohung" } },
        { name = "DMG-Meter", sections = { "DMG-Meter" }, master = "dmShow" },
        { name = "Kampfhilfen", sections = { "Kampfhilfen" } },
        { name = "Zaubern", sections = { "Zaubern" } },
        { name = "Würfelfenster", keys = { "rollsMove" }, master = "rollsMove" },
    } },
    { name = "Welt", icon = "exclamation-circle", tabs = {
        { name = "Flugzeit", prefix = "^flight", master = "flightBar" },
        { name = "EP-Tracker", prefix = "^xpTracker", sections = { "Erfahrung" }, master = "xpTracker" },
        { name = "Grafik & Ton", sections = { "Grafik & Ton" } },
    } },
    { name = "stray", icon = "settings", tabs = {
        { name = "Profile", sections = { "Profile" } },
        { name = "Allgemein", keys = { "language", "uiStyle", "updateNotice", "disableAll" }, sections = { "stray-Oberfläche" } },
        { name = "Bearbeiten", sections = { "Bearbeiten" } },
    } },
    { name = "Alle Anzeigen", icon = "stack-2", displays = true },
}

-- Verschiebbare Anzeigen (Label aus ns.RegisterMovable, Anfang genügt) → Seite, Reiter, optional Schlüssel
-- des Schalters, der die Anzeige ein- und ausschaltet (sonst gilt der Hauptschalter des Reiters)
local MOVABLE_TABS = {
    { "Bedrohungsliste", "Kampf", "Bedrohung", "threatList" },
    { "Tank-Warnung", "Kampf", "Bedrohung", "threatTankWarn" },
    { "Aggro-Warnung", "Kampf", "Bedrohung", "threatAggroWarn" },
    { "DMG-Meter", "Kampf", "DMG-Meter" },
    { "Gefahr-Hinweis", "Kampf", "Kampfhilfen", "dangerWarn" },
    { "Würfelfenster", "Kampf", "Würfelfenster" },
    { "EP-Tracker", "Welt", "EP-Tracker" },
    { "Flugzeit", "Welt", "Flugzeit" },
    { "Haltbarkeit", "Interface", "Interface", "durability" },
    { "Taschenfenster", "Tasche", "Fenster", "bagWindow" },
    { "Bank", "Tasche", "Bank", "bagBank" },
}

-- Übersicht: Funktionen mit An/Aus, nach Seiten gruppiert (Überschrift = Seitenname)
local HOME = {
    { label = "Tasche", keys = { "bagWindow", "bagBank" } },
    { label = "Automation", keys = { "questAccept", "gossipSkip", "autoLoot", "autoSell", "autoRepair", "bagTriage" } },
    { label = "Sozial & Chat", keys = { "playerNotes", "inviteAcceptFriends", "chatLinks" } },
    { label = "Interface", keys = { "durability", "hideErrors", "cameraMax" } },
    { label = "Kampf", keys = { "threatList", "dmShow", "dangerWarn", "mouseoverCast" } },
    { label = "Welt", keys = { "xpTracker", "flightBar" } },
}

-- Weitere Bausteine der Seiten (gebündelt, um lokale Namen zu sparen)
local V = {}

-- Frühere Seiten- und Reiternamen (für ns.OpenConfig anderer Module)
V.LEGACY_PAGES = {
    ["Zentrale"] = "Übersicht", ["Aktionsleisten"] = "Interface", ["Einheiten"] = "Sozial & Chat",
    ["Taschen & Minimap"] = "Automation", ["Kampf & Anzeigen"] = "Kampf", ["Komfort"] = "Automation",
    ["Profile"] = "stray", ["Sprache & System"] = "stray",
    ["Leisten & Menü"] = "Interface", ["Karte & Gruppe"] = "Sozial & Chat", ["Taschen & Handel"] = "Automation",
    ["Welt & Quests"] = "Automation",
}
V.LEGACY_TABS = {
    ["Taschenfenster"] = "Fenster", ["Taschenleiste"] = "Taschen", ["Taschen- & Menüleiste"] = "Taschen",
    ["Minimap"] = "Kamera", ["Swing"] = "Kampfhilfen", ["EP-Leiste"] = "EP-Tracker",
    ["Vorrat"] = "Taschen", ["Gruppenrahmen"] = "Sozial", ["Begleiter"] = "Sozial",
    ["Aktionsleisten"] = "Interface", ["Leisten"] = "Interface", ["Tastenbelegung"] = "Interface",
    ["Abklingzeiten"] = "Kampfhilfen",
}

-- Beim Einschalten zuerst auch einen anderen Schalter einschalten (Schlüssel → Schlüssel)
local MASTER_REQUIRES = {}

-- Geänderte Schlüssel, nach denen „Übernehmen“ neu lädt (zusätzlich option.reload = true)
local RELOAD_KEYS = {
    language = true, accountCVars = true,
    rollsMove = true, -- Ausschalten: Blizzards Optik/Position erst nach /reload
}

-- Einheit hinter dem Zahlenfeld (zusätzlich option.unit)
local UNITS = {}

---------------------------------------------------------------------------
-- Stichwörter für die Suche (deutsch + englisch), zusätzlich zu option.keywords
---------------------------------------------------------------------------

local KEYWORDS = {
    uiStyle = { "stil", "style", "forever", "bronze", "gold", "design", "theme", "aussehen", "look", "oberfläche" },
    fastLoot = { "loot", "beute", "plündern", "schnell", "fast" },
    autoLoot = { "loot", "autoloot", "beute", "plündern" },
    autoSell = { "verkaufen", "sell", "junk", "müll", "grau", "vendor", "händler" },
    autoRepair = { "repair", "reparieren", "rüstung", "durability", "gold" },
    vendorPrice = { "preis", "price", "gold", "vendor", "tooltip", "wert" },
    knownColor = { "bekannt", "known", "rezept", "recipe", "grün", "green" },
    questItemSellWarn = { "quest", "sell", "verkaufen", "warnung", "warning" },
    mailAlts = { "mail", "post", "briefkasten", "twinks", "alts" },
    trainerLearnAll = { "trainer", "lehrer", "lernen", "learn", "skills", "fähigkeiten" },
    cinematicFast = { "cinematic", "cutscene", "video", "film", "skip", "überspringen" },
    cinematicAlways = { "cinematic", "cutscene", "video", "film", "skip", "überspringen" },
    chatLinks = { "chat", "links", "url", "copy", "kopieren" },
    chatCoords = { "chat", "koordinaten", "coords", "waypoint", "wegpunkt", "karte", "map" },
    deleteFill = { "delete", "löschen", "zerstören", "destroy" },
    deleteNoConfirm = { "delete", "löschen", "zerstören", "destroy", "confirm", "nachfrage" },
    questItemMarks = { "quest", "items", "gegenstände", "marker", "markieren" },
    freeSlots = { "bags", "slots", "plätze", "frei", "free", "inventar", "inventory" },
    bagTriage = { "bags", "voll", "full", "inventar", "inventory", "aufräumen" },
    gossipSkip = { "gossip", "dialog", "npc", "gespräch", "skip" },
    questAccept = { "quest", "accept", "annehmen", "auto" },
    questTurnIn = { "quest", "turn in", "abgeben", "auto", "complete" },
    questRewardMark = { "reward", "belohnung", "quest", "gold", "wert" },
    questMobMarks = { "quest", "mobs", "gegner", "marker", "nameplates" },
    threatList = { "aggro", "threat", "liste", "list", "tank" },
    threatPlates = { "aggro", "threat", "nameplates", "namensplaketten", "rahmen" },
    threatPercent = { "aggro", "threat", "nameplates", "prozent", "percent" },
    threatTankWarn = { "aggro", "threat", "tank", "warnung", "warning" },
    threatAggroWarn = { "aggro", "threat", "warnung", "warning" },
    dmShow = { "damage", "dps", "meter", "schaden", "heal", "hps", "heilung", "recount", "details" },
    dmAutoReset = { "damage", "meter", "reset", "zurücksetzen", "instanz", "dungeon" },
    dangerWarn = { "danger", "gefahr", "elite", "level", "warnung", "warning" },
    dangerLevels = { "danger", "gefahr", "level", "stufen" },
    mouseoverCast = { "mouseover", "heal", "heilen", "cast", "zaubern", "spell" },
    abRankCheck = { "rank", "rang", "zauber", "spell", "veraltet" },
    cameraMax = { "camera", "kamera", "zoom", "distance", "entfernung" },
    minimapWheel = { "minimap", "zoom", "mausrad", "mousewheel", "scroll" },
    flightBar = { "flight", "flug", "taxi", "greif", "timer", "flugmeister" },
    xpTracker = { "xp", "exp", "ep", "erfahrung", "tracker", "ep/h", "xp/h", "level", "stufe", "spielzeit", "played" },
    xpTrackerTable = { "xp", "exp", "ep", "tabelle", "table", "tracker", "verlauf", "history" },
    hideErrors = { "error", "errors", "fehler", "meldungen", "spam", "rote schrift" },
    durability = { "durability", "haltbarkeit", "repair", "reparieren", "rüstung" },
    rollsMove = { "roll", "rolls", "loot", "würfeln", "need", "greed", "bedarf", "gier" },
    declineDuels = { "duel", "duell", "ablehnen" },
    acceptRes = { "res", "resurrect", "wiederbeleben", "wiederbelebung", "rez" },
    acceptSummon = { "summon", "beschwörung", "portal", "hexenmeister" },
    inviteAcceptFriends = { "invite", "einladung", "gruppe", "friends", "freunde", "gilde", "guild" },
    inviteDeclineStrangers = { "invite", "einladung", "fremde", "strangers", "spam" },
    playerNotes = { "notes", "notiz", "notizen", "spieler", "player" },
    alts = { "alts", "twinks", "charaktere", "characters", "gold" },
    altsOpen = { "alts", "twinks", "übersicht", "overview" },
    accountCVars = { "cvar", "account", "einstellungen", "settings", "alle charaktere" },
    editModeButton = { "edit", "edit mode", "bearbeiten", "bearbeitungsmodus", "verschieben", "move", "position", "layout" },
    profileExport = { "profile", "profil", "export", "teilen", "share", "backup", "sichern" },
    profileImport = { "profile", "profil", "import", "laden", "load" },
}

-- Stichwörter je Bereich (gelten für alle Optionen darin)
local SECTION_KEYWORDS = {
    ["Beute"] = { "loot" },
    ["Händler"] = { "vendor", "merchant", "verkaufen" },
    ["NPCs"] = { "npc" },
    ["Chat"] = { "chat" },
    ["Taschen"] = { "bags", "bag", "inventar", "inventory" },
    ["Tasche"] = { "bags", "bag", "inventar", "inventory", "stray-tasche", "rucksack", "backpack" },
    ["Bank"] = { "bank", "bags", "bag", "inventar", "inventory" },
    ["Quests"] = { "quest", "quests" },
    ["Bedrohung"] = { "aggro", "threat" },
    ["DMG-Meter"] = { "dps", "damage", "meter", "schaden", "heal", "heilung" },
    ["Kampfhilfen"] = { "combat", "kampf" },
    ["Zaubern"] = { "cast", "spell", "zauber" },
    ["Kamera & Karte"] = { "camera", "kamera", "minimap", "map", "karte" },
    ["Erfahrung"] = { "xp", "exp", "ep", "experience", "erfahrung", "level" },
    ["Interface"] = { "ui", "interface" },
    ["Sozial"] = { "social", "sozial" },
    ["Charaktere"] = { "alts", "twinks", "characters" },
    ["Bearbeiten"] = { "edit", "bearbeiten", "bearbeitungsmodus" },
    ["Profile"] = { "profile", "profil" },
}

---------------------------------------------------------------------------
-- Kleine Bausteine
---------------------------------------------------------------------------

local function Text(parent, size, c, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, FS(size), "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

local function SetTextColor(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function Line(parent, c, layer)
    local t = parent:CreateTexture(nil, layer or "BORDER")
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

local function Icon(parent, name, size, c, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    t:SetTexture(ICONS .. name)
    if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return t
end

-- Abgerundetes Rechteck aus 7 Texturen: vier Viertelkreise als Ecken, Mitte und zwei Seitenstreifen.
-- Gibt ein Objekt mit SetColor(c) und SetShown(b) zurück.
local function RoundRect(parent, radius, c, layer, sub, inset)
    inset = inset or 0
    local rr = { parts = {} }
    if FOREVER then
        -- Forever: eckig, eine einzelne Farbfläche
        local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        t:SetPoint("TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", -inset, inset)
        table.insert(rr.parts, t)
        function rr:SetColor(col)
            t:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
        end
        function rr:SetShown(shown) t:SetShown(shown) end
        rr:SetColor(c)
        return rr
    end
    local function Part(isRound)
        local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        if isRound then t:SetTexture(MEDIA .. "round") else t:SetColorTexture(1, 1, 1, 1) end
        table.insert(rr.parts, t)
        return t
    end
    local tl, tr, bl, br = Part(true), Part(true), Part(true), Part(true)
    for _, t in ipairs({ tl, tr, bl, br }) do t:SetSize(radius, radius) end
    tl:SetPoint("TOPLEFT", inset, -inset); tl:SetTexCoord(0, 0.5, 0, 0.5)
    tr:SetPoint("TOPRIGHT", -inset, -inset); tr:SetTexCoord(0.5, 1, 0, 0.5)
    bl:SetPoint("BOTTOMLEFT", inset, inset); bl:SetTexCoord(0, 0.5, 0.5, 1)
    br:SetPoint("BOTTOMRIGHT", -inset, inset); br:SetTexCoord(0.5, 1, 0.5, 1)
    local mid = Part(false)
    mid:SetPoint("TOPLEFT", tl, "TOPRIGHT"); mid:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left = Part(false)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local right = Part(false)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    function rr:SetColor(col)
        for _, t in ipairs(self.parts) do t:SetVertexColor(col[1], col[2], col[3], col[4] or 1) end
    end
    function rr:SetShown(shown)
        for _, t in ipairs(self.parts) do t:SetShown(shown) end
    end
    rr:SetColor(c)
    return rr
end

-- Fläche mit 1-px-Rand: äußeres Rechteck in Randfarbe, inneres in Füllfarbe
local function Panel(frame, radius, fill, border, layer)
    local outer = RoundRect(frame, radius, border or C.line, layer, 0)
    local inner = RoundRect(frame, radius - 1, fill, layer, 1, 1)
    return inner, outer
end

-- Eingabefeld-Hintergrund: Forever schwarz mit Bronzerand (style.lua), sonst wie Panel.
-- Gibt (Fläche, Rand) mit SetColor(c) zurück.
local function InputBox(frame, radius)
    local fx = FX("EditBox", frame)
    if fx then
        local fill, border = {}, {}
        function fill:SetColor(c)
            if c == C.hover then
                fx.bg:SetColorTexture(0.075, 0.072, 0.068, 1)
            else
                fx.bg:SetColorTexture(0.043, 0.043, 0.051, 1)
            end
        end
        function border:SetColor(c)
            if c == C.line then c = ns.Colors.bronze end
            for _, t in ipairs(fx.border) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
        end
        return fill, border
    end
    return Panel(frame, radius, C.card, C.line, "BACKGROUND")
end

-- Fenster, Menü oder Dialog mit Rand: Forever Schiefer + Bronze-Rahmen (style.lua), sonst Panel
local function Boxed(frame, radius, size, corners)
    local fill = FX("Fill", frame, "window")
    local border = FX("Border", frame, { size = size, corners = corners })
    if not (fill and border) then Panel(frame, radius, C.card, C.line, "BACKGROUND") end
end

-- Flacher Knopf mit runden Ecken; style "primary" (lila gefüllt), "outline" (lila Rand) oder "dark"
local BUTTON_STYLE = {
    primary = { fill = C.accent, hover = C.accentHi, border = C.accent, text = C.white },
    outline = { fill = C.card, hover = C.hover, border = C.accent, text = C.white },
    dark = { fill = C.hover, hover = C.line, border = C.line, text = C.text },
}
local function MakeButton(parent, label, style, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height or 30)
    b.style = BUTTON_STYLE[style or "dark"] or BUTTON_STYLE.dark
    -- Forever: rot-bronzer Hauptknopf bzw. grau-bronzer Nebenknopf aus style.lua
    local fx = FX("Button", b, (style == "primary" or style == "outline") and "primary" or "secondary")
    if fx then
        b.fx = fx
        b.fill = { SetColor = function() end }
    else
        b.fill, b.border = Panel(b, 6, b.style.fill, b.style.border, "BACKGROUND")
    end
    b.text = Text(b, 13, fx and fx.textColor or b.style.text)
    b.text:SetPoint("CENTER")
    function b:SetLabel(text, minWidth)
        self.text:SetText(text)
        self:SetWidth(math.max(minWidth or 0, math.floor(self.text:GetStringWidth() + 28)))
    end
    function b:SetActive(active)
        self.inactive = not active
        self:SetAlpha(active and 1 or 0.4)
    end
    b:SetScript("OnEnter", function(self)
        if not self.inactive then self.fill:SetColor(self.style.hover) end
    end)
    b:SetScript("OnLeave", function(self)
        self.fill:SetColor(self.style.fill)
        GameTooltip:Hide()
    end)
    b:SetLabel(label or "")
    return b
end

-- Tooltip an einem Knopf zusätzlich zur Hover-Farbe. title/body: deutscher Schlüssel (wird erst beim
-- Anzeigen übersetzt) oder Funktion, die den fertigen Text liefert
local function ButtonTooltip(b, title, body)
    local onEnter = b:GetScript("OnEnter")
    b:SetScript("OnEnter", function(self)
        onEnter(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(type(title) == "function" and title() or L[title], 1, 1, 1)
        local text
        if type(body) == "function" then text = body() elseif body then text = L[body] end
        if text then GameTooltip:AddLine(text, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true) end
        GameTooltip:Show()
    end)
end

-- Schalter als Pille mit Kugel
local function MakeSwitch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(34, 18)
    -- Forever: schwarze Spur mit Bronzerand, rechteckiger Schieber; an = Lila
    local fx = FX("EditBox", s)
    if fx then
        s:SetSize(40, 20)
        s.knobEdge = s:CreateTexture(nil, "ARTWORK", nil, 1)
        s.knobEdge:SetSize(18, 16)
        s.knobEdge:SetColorTexture(0.04, 0.03, 0.02, 1)
        s.knob = s:CreateTexture(nil, "OVERLAY")
        s.knob:SetSize(16, 14)
        function s:SetState(on, enabled)
            self.knobEdge:ClearAllPoints()
            self.knob:ClearAllPoints()
            if on then
                fx.bg:SetColorTexture(0.24, 0.20, 0.52, 1)
                self.knobEdge:SetPoint("RIGHT", -2, 0)
                self.knob:SetColorTexture(0.88, 0.84, 0.73, 1)
            else
                fx.bg:SetColorTexture(0.043, 0.043, 0.051, 1)
                self.knobEdge:SetPoint("LEFT", 2, 0)
                self.knob:SetColorTexture(0.43, 0.40, 0.34, 1)
            end
            self.knob:SetPoint("CENTER", self.knobEdge, "CENTER")
            self:SetAlpha(enabled and 1 or 0.4)
        end
        return s
    end
    s.track = s:CreateTexture(nil, "ARTWORK")
    s.track:SetAllPoints()
    s.track:SetTexture(MEDIA .. "pill")
    s.knob = s:CreateTexture(nil, "OVERLAY")
    s.knob:SetSize(14, 14)
    s.knob:SetTexture(MEDIA .. "dot")
    function s:SetState(on, enabled)
        self.knob:ClearAllPoints()
        if on then
            self.track:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
            self.knob:SetPoint("RIGHT", -2, 0)
            self.knob:SetVertexColor(1, 1, 1, 1)
        else
            self.track:SetVertexColor(C.off[1], C.off[2], C.off[3], 1)
            self.knob:SetPoint("LEFT", 2, 0)
            self.knob:SetVertexColor(C.grey[1], C.grey[2], C.grey[3], 1)
        end
        self:SetAlpha(enabled and 1 or 0.4)
    end
    return s
end

-- Häkchen-Kästchen (z. B. „Aktiv“)
local function MakeCheck(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local fx = FX("EditBox", b)
    if fx then
        -- Forever: schwarzes Kästchen mit Bronzerand; an = lila Fläche und Gold-Rand
        b.mark = Icon(b, "check", 12, C.white, "OVERLAY")
        b.mark:SetPoint("CENTER")
        function b:SetState(on, enabled)
            local r, g, bl = 0.541, 0.416, 0.204
            if on then r, g, bl = ns.Colors.goldDim[1], ns.Colors.goldDim[2], ns.Colors.goldDim[3] end
            for _, t in ipairs(fx.border) do t:SetColorTexture(r, g, bl, 1) end
            if on then fx.bg:SetColorTexture(0.24, 0.20, 0.52, 1) else fx.bg:SetColorTexture(0.043, 0.043, 0.051, 1) end
            self.mark:SetShown(on and true or false)
            self:SetAlpha(enabled == false and 0.4 or 1)
        end
        return b
    end
    b.fill, b.border = Panel(b, 4, C.card, C.grey, "ARTWORK")
    b.mark = Icon(b, "check", 12, C.white, "OVERLAY")
    b.mark:SetPoint("CENTER")
    function b:SetState(on, enabled)
        self.fill:SetColor(on and C.accent or C.card)
        self.border:SetColor(on and C.accent or C.grey)
        self.mark:SetShown(on and true or false)
        self:SetAlpha(enabled == false and 0.4 or 1)
    end
    return b
end

-- Kleinbuchstaben/Großbuchstaben inklusive Umlaute (string.lower/upper kennen nur ASCII)
local function Lower(s)
    s = tostring(s or ""):lower()
    return (s:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"))
end
local function Upper(s)
    s = tostring(s or ""):upper()
    return (s:gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))
end

local function RoundInt(v) return math.floor(v + 0.5) end

-- Zahl ohne überflüssige Nachkommastellen
local function NumberText(value, step)
    if type(value) ~= "number" then return tostring(value or "–") end
    if (step or 1) < 1 then
        return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
    end
    return tostring(RoundInt(value))
end

-- Name einer Anzeige oder Auswahl übersetzen; „Aktionsleiste 3“ ohne eigene Übersetzung über den
-- Teil vor der Nummer
local function LabelText(label)
    if type(label) ~= "string" then return tostring(label or "") end
    local text = L[label]
    if text == label and not ns.isGerman then
        local base, num = label:match("^(.-) (%d+)$")
        if base and L[base] ~= base then text = L[base] .. " " .. num end
    end
    return text
end

---------------------------------------------------------------------------
-- Grundgerüst
---------------------------------------------------------------------------

local W = {} -- Bedienelemente des Fensters (gebündelt, um lokale Namen zu sparen)
local S = { selectedTabs = {}, instances = {} } -- Zustand

local frame = CreateFrame("Frame", "strayFrame", UIParent)
frame:SetSize(M.WIDTH, M.HEIGHT)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

-- Fenstergrund und Rahmen: Forever Schiefer + Bronze-Rahmen, sonst wie bisher
Build(function()
    local fill = FX("Fill", frame, "window")
    local border = FX("Border", frame, { size = P })
    if not (fill and border) then Panel(frame, 12, C.window, C.line, "BACKGROUND") end
end)

local function SavePoint(self)
    local point, _, relPoint, x, y = self:GetPoint()
    if point and ns.db then ns.db.point = { point, relPoint, x, y } end
end

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePoint(self)
end)

local Refresh, Changed -- weiter unten

---------------------------------------------------------------------------
-- Kopf: Logo, Suche, Bearbeitungsmodus, Schließen
---------------------------------------------------------------------------

Build(function()
    -- Forever: Titelleiste als bronzebraunes Band (zwei Hälften), darunter eine Bronze-Linie
    if FOREVER then
        local function Strip(top, height, r, g, b)
            local t = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
            t:SetPoint("TOPLEFT", frame, "TOPLEFT", P, -top)
            t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -P, -top)
            t:SetHeight(height)
            t:SetColorTexture(r, g, b, 1)
        end
        local half = math.floor((M.TOP_H - P) / 2)
        Strip(P, half, 0.231, 0.184, 0.102)
        Strip(P + half, M.TOP_H - P - half, 0.137, 0.106, 0.055)
    end
    local pad = FOREVER and P or 1 -- Abstand der Linien zum Fensterrand
    local lineColor = FOREVER and ns.Colors.bronze or C.line
    local lineSize = FOREVER and 2 or 1

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", 16 + P, -(M.TOP_H - 30) / 2 - P / 2)
    logo:SetTexture(MEDIA .. "logo")

    local name = Text(frame, 18, C.hi)
    name:SetPoint("LEFT", logo, "RIGHT", 9, 1)
    name:SetText("stray")
    W.version = Text(frame, 10, FOREVER and C.grey or C.faint)
    W.version:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 6, 2)

    local headLine = Line(frame, lineColor)
    headLine:SetPoint("TOPLEFT", pad, -M.TOP_H)
    headLine:SetPoint("TOPRIGHT", -pad, -M.TOP_H)
    headLine:SetHeight(lineSize)

    local sideLine = Line(frame, lineColor)
    sideLine:SetPoint("TOPLEFT", M.SIDE_W, -M.TOP_H - 1)
    sideLine:SetPoint("BOTTOMLEFT", M.SIDE_W, pad)
    sideLine:SetWidth(lineSize)

    -- Schließen
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -14 - P, -(M.TOP_H - 26) / 2 - P / 2)
    local closeFx = FX("Button", close, "primary") -- Forever: rot-bronzer Knopf
    local closeHover = closeFx and { SetShown = function() end } or RoundRect(close, 6, C.hover, "BACKGROUND")
    closeHover:SetShown(false)
    local closeRest = closeFx and closeFx.textColor or C.grey
    local closeIcon = Icon(close, "x", 14, closeRest)
    closeIcon:SetPoint("CENTER")
    close:SetScript("OnEnter", function()
        closeHover:SetShown(true)
        closeIcon:SetVertexColor(1, 1, 1, 1)
    end)
    close:SetScript("OnLeave", function()
        closeHover:SetShown(false)
        closeIcon:SetVertexColor(closeRest[1], closeRest[2], closeRest[3], 1)
    end)
    W.close = close

    -- Bearbeitungsmodus
    W.editButton = MakeButton(frame, L["Bearbeitungsmodus"], "dark", 30)
    W.editButton:SetPoint("RIGHT", close, "LEFT", -10, 0)

    -- Breites Suchfeld zwischen Logo und Knöpfen
    local search = CreateFrame("EditBox", nil, frame)
    search:SetHeight(32)
    search:SetPoint("LEFT", frame, "TOPLEFT", M.SIDE_W + 16, -M.TOP_H / 2 - P / 2)
    search:SetPoint("RIGHT", W.editButton, "LEFT", -24, 0)
    search:SetAutoFocus(false)
    search:SetFont(FONT, FS(13), "")
    search:SetTextColor(C.text[1], C.text[2], C.text[3])
    search:SetTextInsets(32, 10, 0, 0)
    local searchFill, searchBorder = InputBox(search, 7)
    local searchIcon = Icon(search, "search", 15, C.grey)
    searchIcon:SetPoint("LEFT", 11, 0)
    W.placeholder = Text(search, 13, C.faint)
    W.placeholder:SetPoint("LEFT", 32, 0)
    search:SetScript("OnEditFocusGained", function()
        searchFill:SetColor(C.hover)
        searchBorder:SetColor(C.accent)
    end)
    search:SetScript("OnEditFocusLost", function()
        searchFill:SetColor(C.card)
        searchBorder:SetColor(C.line)
    end)
    W.search = search
end)

---------------------------------------------------------------------------
-- Inhalt rechts: Titel, „Aktiv“, Reiter, Scrollbereich
---------------------------------------------------------------------------

local content = CreateFrame("Frame", nil, frame)
local scroll = CreateFrame("ScrollFrame", nil, content)
local scrollChild = CreateFrame("Frame", nil, scroll)

Build(function()
    content:SetPoint("TOPLEFT", M.SIDE_W + 1, -M.TOP_H - 1)
    content:SetPoint("BOTTOMRIGHT", -P, P)

    W.title = Text(content, 22, C.hi)
    W.title:SetPoint("TOPLEFT", M.CL, -18)
    W.title:SetPoint("RIGHT", content, "RIGHT", -150, 0)
    W.title:SetWordWrap(false)

    W.info = Text(content, 12, C.grey)
    W.info:SetPoint("TOPLEFT", M.CL, -52)
    W.info:SetPoint("RIGHT", content, "RIGHT", -M.CR, 0)
    W.info:SetWordWrap(false)

    -- Häkchen „Aktiv“ (Hauptschalter des Moduls bzw. Reiters)
    local active = CreateFrame("Button", nil, content)
    active:SetSize(90, 22)
    active:SetPoint("TOPRIGHT", -M.CR, -20)
    active.check = MakeCheck(active)
    active.label = Text(active, 14, C.text)
    active.label:SetPoint("RIGHT")
    active.check:SetPoint("RIGHT", active.label, "LEFT", -8, 0)
    active.check:EnableMouse(false)
    W.active = active

    -- Reiterleiste
    W.tabBar = CreateFrame("Frame", nil, content)
    W.tabBar:SetPoint("TOPLEFT", M.CL, -54)
    W.tabBar:SetPoint("RIGHT", content, "RIGHT", -M.CR, 0)
    W.tabBar:SetHeight(M.TAB_H)
    local tabLine = Line(W.tabBar, FOREVER and ns.Colors.bronze or C.line)
    tabLine:SetPoint("BOTTOMLEFT")
    tabLine:SetPoint("BOTTOMRIGHT")
    tabLine:SetHeight(FOREVER and 2 or 1)
    W.tabs = {}

    scroll:SetPoint("BOTTOMRIGHT", -M.CR, M.FOOT_H + 6)
    scroll:EnableMouseWheel(true)
    scrollChild:SetSize(M.SCROLL_W, 10)
    scroll:SetScrollChild(scrollChild)

    W.emptyText = Text(scrollChild, 13, C.grey)
    W.emptyText:SetPoint("TOPLEFT", 4, -6)
    W.emptyText:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)
    W.emptyText:SetWordWrap(true)
end)

---------------------------------------------------------------------------
-- Scrollbalken: Mausrad, Daumen ziehen oder in die Spur klicken
---------------------------------------------------------------------------

local function MaxScroll()
    return math.max(0, (scrollChild:GetHeight() or 0) - (scroll:GetHeight() or 0))
end

local function UpdateScrollBar()
    local track, thumb = W.scrollTrack, W.scrollThumb
    local view = scroll:GetHeight() or 0
    local total = scrollChild:GetHeight() or 0
    if view <= 0 or total <= view + 1 then
        track:Hide()
        return
    end
    local thumbH = math.max(24, view * view / total)
    local offset = (scroll:GetVerticalScroll() or 0) / (total - view) * (view - thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -offset)
    thumb:SetHeight(thumbH)
    track:Show()
end

local function CloseMenu() if W.menu then W.menu:Hide() end end

local function SetScroll(value)
    scroll:SetVerticalScroll(math.max(0, math.min(MaxScroll(), value)))
    if W.preview then W.preview:Hide() end
    CloseMenu()
    UpdateScrollBar()
end

Build(function()
    local track = CreateFrame("Button", nil, content)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 18, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 18, 0)
    track:SetWidth(12)
    track:EnableMouseWheel(true)
    local trackLine = track:CreateTexture(nil, "ARTWORK")
    trackLine:SetPoint("TOP"); trackLine:SetPoint("BOTTOM"); trackLine:SetWidth(4)
    trackLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(12)
    thumb:SetFrameLevel(track:GetFrameLevel() + 2)
    local thumbLine = thumb:CreateTexture(nil, "OVERLAY")
    thumbLine:SetPoint("TOP"); thumbLine:SetPoint("BOTTOM"); thumbLine:SetWidth(4)
    thumbLine:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    thumb:SetScript("OnEnter", function() thumbLine:SetWidth(6) end)
    thumb:SetScript("OnLeave", function(self) if not self.dragging then thumbLine:SetWidth(4) end end)
    W.scrollTrack, W.scrollThumb = track, thumb

    scroll:SetScript("OnMouseWheel", function(self, delta) SetScroll(self:GetVerticalScroll() - delta * M.WHEEL) end)
    track:SetScript("OnMouseWheel", function(_, delta) SetScroll(scroll:GetVerticalScroll() - delta * M.WHEEL) end)

    local function CursorY()
        local _, y = GetCursorPosition()
        return y / (track:GetEffectiveScale() or 1)
    end
    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self.dragging = true
        self.startY = CursorY()
        self.startScroll = scroll:GetVerticalScroll() or 0
        thumbLine:SetWidth(6)
        self:SetScript("OnUpdate", function(t)
            local free = (track:GetHeight() or 0) - (t:GetHeight() or 0)
            if free <= 0 then return end
            SetScroll(t.startScroll + (t.startY - CursorY()) / free * MaxScroll())
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        if not self:IsMouseOver() then thumbLine:SetWidth(4) end
    end)
    thumb:SetScript("OnHide", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)
    track:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local top = self:GetTop()
        local free = (self:GetHeight() or 0) - (thumb:GetHeight() or 0)
        if not top or free <= 0 then return end
        local pos = top - CursorY() - (thumb:GetHeight() or 0) / 2
        SetScroll(math.max(0, math.min(free, pos)) / free * MaxScroll())
    end)
end)

-- Hält die Scrollposition im gültigen Bereich (ohne Vorschau und Menü zu schließen)
local function ClampScroll()
    local current = scroll:GetVerticalScroll() or 0
    if current > MaxScroll() then scroll:SetVerticalScroll(MaxScroll()) end
    UpdateScrollBar()
end

---------------------------------------------------------------------------
-- Vorschau-Bild und Auswahlmenü (Dropdown)
---------------------------------------------------------------------------

Build(function()
    local preview = CreateFrame("Frame", nil, content)
    preview:SetSize(272, 150)
    preview:SetFrameLevel(content:GetFrameLevel() + 30)
    preview:EnableMouse(true)
    preview:SetScript("OnMouseUp", function(self) self:Hide() end)
    Boxed(preview, 8, 4, false)
    preview.image = preview:CreateTexture(nil, "ARTWORK")
    preview.image:SetSize(256, 128)
    preview.image:SetPoint("TOP", 0, -8)
    preview.caption = Text(preview, 11, C.grey)
    preview.caption:SetPoint("BOTTOMLEFT", 10, 4)
    preview:Hide()
    W.preview = preview

    -- Ein gemeinsames Menü für alle Dropdowns; ein unsichtbarer Fänger schließt es bei Klick daneben
    local catcher = CreateFrame("Button", nil, frame)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameLevel(frame:GetFrameLevel() + 58)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() CloseMenu() end)
    catcher:Hide()

    local menu = CreateFrame("Frame", nil, frame)
    menu:SetFrameLevel(frame:GetFrameLevel() + 60)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    Boxed(menu, 6, 4, false)
    menu.buttons = {}
    menu:SetScript("OnHide", function() catcher:Hide() end)
    menu:Hide()
    W.menu = menu

    -- items: { { value =, label =, onClick = (optional) , separator = (optional) } }
    function W.OpenMenu(owner, items, current, onSelect)
        if menu:IsShown() and menu.owner == owner then
            CloseMenu()
            return
        end
        GameTooltip:Hide()
        menu.owner = owner
        local e = FOREVER and 4 or 0 -- Forever: Platz für den Rahmen
        local y, width = 4 + e, owner:GetWidth() or 120
        for i, item in ipairs(items) do
            local b = menu.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, menu)
                b:SetHeight(24)
                b.hl = b:CreateTexture(nil, "BACKGROUND")
                b.hl:SetAllPoints()
                b.hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
                b.hl:Hide()
                b.text = Text(b, 13, C.text)
                b.text:SetPoint("LEFT", 10, 0)
                b.mark = Icon(b, "check", 12, C.accent)
                b.mark:SetPoint("RIGHT", -8, 0)
                b.sep = Line(b, C.line)
                b.sep:SetPoint("LEFT", 6, 0); b.sep:SetPoint("RIGHT", -6, 0); b.sep:SetHeight(1)
                b:SetScript("OnEnter", function(self) if not self.isSep then self.hl:Show() end end)
                b:SetScript("OnLeave", function(self) self.hl:Hide() end)
                menu.buttons[i] = b
            end
            b.isSep = item.separator and true or false
            b.sep:SetShown(b.isSep)
            b.text:SetShown(not b.isSep)
            b.text:SetText(item.label or "")
            b.mark:SetShown(not b.isSep and current ~= nil and item.value == current)
            b:SetHeight(b.isSep and 9 or 24)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 1 + e, -y)
            b:SetPoint("TOPRIGHT", -1 - e, -y)
            b:SetScript("OnClick", function()
                if b.isSep then return end
                CloseMenu()
                ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                if item.onClick then item.onClick() elseif onSelect then onSelect(item.value) end
            end)
            b:Show()
            y = y + b:GetHeight()
            width = math.max(width, math.floor((b.text:GetStringWidth() or 0) + 44))
        end
        for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
        menu:SetSize(width + 2 * e, y + 4 + e)
        menu:ClearAllPoints()
        local bottom = owner:GetBottom()
        if bottom and bottom - y - 8 < 4 then
            menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
        end
        catcher:Show()
        menu:Show()
    end
end)

-- Dropdown-Knopf: zeigt den aktuellen Wert; Klick öffnet das Menü
local function MakeDropdown(parent)
    local d = CreateFrame("Button", nil, parent)
    d:SetSize(M.DROP_W, 28)
    d.fill, d.border = InputBox(d, 5)
    d.text = Text(d, 13, C.text)
    d.text:SetPoint("LEFT", 10, 0)
    d.text:SetPoint("RIGHT", -26, 0)
    d.text:SetWordWrap(false)
    d.arrow = Icon(d, "chevron-down", 13, C.rest)
    d.arrow:SetPoint("RIGHT", -9, 0)
    d:SetScript("OnEnter", function(self)
        if not self.inactive then self.border:SetColor(C.accent) end
        if self.onEnter then self.onEnter(self) end
    end)
    d:SetScript("OnLeave", function(self)
        self.border:SetColor(C.line)
        GameTooltip:Hide()
    end)
    d:SetScript("OnClick", function(self)
        if self.inactive or not self.items then return end
        W.OpenMenu(self, self.items, self.current, self.onSelect)
    end)
    -- items: { { value =, label = } }, current: gewählter Wert
    function d:SetItems(items, current, onSelect, enabled)
        self.items, self.current, self.onSelect = items, current, onSelect
        local label
        for _, item in ipairs(items) do
            if item.value == current then label = item.label end
        end
        self.text:SetText(label or tostring(current or "–"))
        self.inactive = enabled == false
        self:SetAlpha(enabled == false and 0.4 or 1)
    end
    return d
end

-- Zahlenfeld mit Pfeilen: get() → Zahl, set(v), step, fmt(v) → Anzeigetext, raw(v) → Text beim Tippen.
-- Enter übernimmt, Esc verwirft, Pfeile ±step, Mausrad ±step nur mit Fokus.
local function MakeNumberField(parent, width)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width or M.NUM_W, 28)
    box.fill, box.border = InputBox(box, 5)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetPoint("TOPLEFT", 1, -1)
    eb:SetPoint("BOTTOMRIGHT", -18, 1)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT_NUM, FOREVER and 14 or 13, "")
    eb:SetTextColor(C.num[1], C.num[2], C.num[3])
    eb:SetTextInsets(9, 2, 0, 0)
    eb:SetMaxLetters(10)
    box.eb = eb
    box.step = 1

    local function Value() if box.get then local ok, v = pcall(box.get) if ok then return v end end end
    local function Commit(v)
        if v == nil or not box.set or box.inactive then return end
        local ok, err = pcall(box.set, v)
        if not ok then geterrorhandler()(err) end
    end
    function box:Refresh()
        if eb:HasFocus() then return end
        local v = Value()
        if v == nil then eb:SetText("–") return end
        eb:SetText(self.fmt and self.fmt(v) or NumberText(v, self.step))
    end
    function box:SetActive(on)
        self.inactive = not on
        self:SetAlpha(on and 1 or 0.4)
        eb:EnableMouse(on and true or false)
        if not on and eb:HasFocus() then eb:ClearFocus() end
    end

    local function Arrow(name, dir)
        local b = CreateFrame("Button", nil, box)
        b:SetSize(16, 12)
        b.icon = Icon(b, name, 10, C.rest)
        b.icon:SetPoint("CENTER")
        b:SetScript("OnEnter", function(self) if not box.inactive then self.icon:SetVertexColor(1, 1, 1, 1) end end)
        b:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.rest[1], C.rest[2], C.rest[3], 1) end)
        b:SetScript("OnClick", function()
            local v = Value()
            if type(v) ~= "number" then return end
            if eb:HasFocus() then eb:ClearFocus() end
            Commit(v + dir * (box.step or 1))
            box:Refresh()
        end)
        return b
    end
    box.up = Arrow("chevron-up", 1)
    box.up:SetPoint("TOPRIGHT", -2, -2)
    box.down = Arrow("chevron-down", -1)
    box.down:SetPoint("BOTTOMRIGHT", -2, 2)

    eb:SetScript("OnEnterPressed", function(self)
        local text = (self:GetText() or ""):gsub(",", ".")
        local v = tonumber(text:match("%-?%d+%.?%d*") or "")
        self:ClearFocus()
        Commit(v)
        box:Refresh()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        box:Refresh()
    end)
    eb:SetScript("OnEditFocusGained", function(self)
        box.border:SetColor(C.accent)
        local v = Value()
        if type(v) == "number" then self:SetText(NumberText(v, box.step)) end
        self:HighlightText()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        box.border:SetColor(C.line)
        self:HighlightText(0, 0)
        box:Refresh()
    end)
    eb:EnableMouseWheel(true)
    eb:SetScript("OnMouseWheel", function(self, delta)
        local v = Value()
        if not self:HasFocus() or type(v) ~= "number" then
            SetScroll(scroll:GetVerticalScroll() - delta * M.WHEEL)
            return
        end
        Commit(v + delta * (box.step or 1))
        local nv = Value()
        if type(nv) == "number" then self:SetText(NumberText(nv, box.step)) end
    end)
    eb:SetScript("OnEnter", function() if box.onEnter then box.onEnter(box) end end)
    eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return box
end

---------------------------------------------------------------------------
-- Fußzeile
---------------------------------------------------------------------------

Build(function()
    if FOREVER then
        -- Forever: dunkles Band für die Fußzeile
        local band = content:CreateTexture(nil, "BACKGROUND", nil, -5)
        band:SetPoint("BOTTOMLEFT", 0, 0)
        band:SetPoint("BOTTOMRIGHT", 0, 0)
        band:SetHeight(M.FOOT_H)
        band:SetColorTexture(0.075, 0.068, 0.06, 0.9)
    end
    local footLine = Line(content, FOREVER and ns.Colors.bronze or C.line)
    footLine:SetPoint("BOTTOMLEFT", 0, M.FOOT_H)
    footLine:SetPoint("BOTTOMRIGHT", FOREVER and 0 or -1, M.FOOT_H)
    footLine:SetHeight(FOREVER and 2 or 1)

    W.footDot = content:CreateTexture(nil, "ARTWORK")
    W.footDot:SetSize(8, 8)
    W.footDot:SetPoint("BOTTOMLEFT", M.CL, M.FOOT_H / 2 - 4)
    W.footDot:SetTexture(MEDIA .. "dot")

    W.footText = Text(content, 13, C.grey)
    W.footText:SetPoint("LEFT", W.footDot, "RIGHT", 8, 0)
    W.footText:SetWordWrap(false)

    W.applyButton = MakeButton(content, L["Übernehmen"], "outline", 30)
    W.applyButton:SetPoint("BOTTOMRIGHT", -M.CR, (M.FOOT_H - 30) / 2)
    W.discardButton = MakeButton(content, L["Verwerfen"], "dark", 30)
    W.discardButton:SetPoint("RIGHT", W.applyButton, "LEFT", -10, 0)
    W.footText:SetPoint("RIGHT", W.discardButton, "LEFT", -12, 0)
end)

---------------------------------------------------------------------------
-- Größe ziehen: Griff unten rechts
---------------------------------------------------------------------------

local function ScreenSize()
    local w = UIParent and UIParent:GetWidth() or 0
    local h = UIParent and UIParent:GetHeight() or 0
    if w < M.MIN_W then w = 4000 end
    if h < M.MIN_H then h = 4000 end
    return w, h
end

local function MinHeight()
    return math.max(M.MIN_H, math.ceil((S.navBottom or 0) + M.PROFILE_H + 12 + P))
end

local function UpdateResizeBounds()
    local maxW, maxH = ScreenSize()
    local minH = math.min(MinHeight(), maxH)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(M.MIN_W, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(M.MIN_W, minH) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
end

-- Größe in die Grenzen bringen und setzen
local function ApplySize(w, h)
    local maxW, maxH = ScreenSize()
    w = math.max(M.MIN_W, math.min(maxW, tonumber(w) or M.WIDTH))
    h = math.max(math.min(MinHeight(), maxH), math.min(maxH, tonumber(h) or M.HEIGHT))
    frame:SetSize(math.floor(w + 0.5), math.floor(h + 0.5))
end

Build(function()
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", FOREVER and -(P + 8) or -3, FOREVER and P + 8 or 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:RegisterForClicks("LeftButtonUp")
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gripTex:SetVertexColor(C.rest[1], C.rest[2], C.rest[3], 1)
    grip:SetScript("OnEnter", function(self)
        gripTex:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Größe ändern"], 1, 1, 1)
        GameTooltip:AddLine(L["Ziehen: Fenster größer oder kleiner.\nDoppelklick: Standardgröße."], ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self)
        if not self.sizing then gripTex:SetVertexColor(C.rest[1], C.rest[2], C.rest[3], 1) end
        GameTooltip:Hide()
    end)
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        UpdateResizeBounds()
        self.sizing = true
        GameTooltip:Hide()
        CloseMenu()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    local function StopSizing(self)
        if not self.sizing then return end
        self.sizing = false
        frame:StopMovingOrSizing()
        if not self:IsMouseOver() then gripTex:SetVertexColor(C.rest[1], C.rest[2], C.rest[3], 1) end
        if ns.db then
            ns.db.uiSize = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
        end
        SavePoint(frame)
    end
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)
    grip:SetScript("OnDoubleClick", function()
        -- nach dem Loslassen auf Standardgröße (StopMovingOrSizing des zweiten Klicks ist dann durch)
        C_Timer.After(0, function()
            ApplySize(M.WIDTH, M.HEIGHT)
            if ns.db then ns.db.uiSize = nil end
            SavePoint(frame)
        end)
    end)
end)

---------------------------------------------------------------------------
-- Optionen aus dem Register sammeln und auf Seiten/Reiter verteilen
---------------------------------------------------------------------------

local R = {
    pages = {},        -- sichtbare Seiten (Kopie der PAGES-Einträge mit tabs[i].options)
    allOptions = {},   -- alle Optionen in Register-Reihenfolge
    sectionOf = {},    -- Option → Bereichsname
    tabOf = {},        -- Option → Reiter
    pageOfTab = {},    -- Reiter → Seite
    byKey = {},        -- Schlüssel → Liste der Optionen
    sections = {},     -- Bereichsname → Liste der Optionen
}

local function CollectOptions()
    for _, column in ipairs(ns.columns) do
        for _, section in ipairs(column) do
            R.sections[section.name] = R.sections[section.name] or {}
            for _, option in ipairs(section.options) do
                table.insert(R.sections[section.name], option)
                table.insert(R.allOptions, option)
                R.sectionOf[option] = section.name
                if option.key then
                    R.byKey[option.key] = R.byKey[option.key] or {}
                    table.insert(R.byKey[option.key], option)
                end
            end
        end
    end

    -- Regeln: Schlüssel, Muster, Bereich → Reiter
    local byKey, rules, bySection = {}, {}, {}
    local pageList = {}
    for _, def in ipairs(PAGES) do
        local page = { name = def.name, icon = def.icon, home = def.home, displays = def.displays, master = def.master, tabs = {} }
        table.insert(pageList, page)
        for _, tdef in ipairs(def.tabs or {}) do
            local tab = { name = tdef.name, master = tdef.master, options = {} }
            table.insert(page.tabs, tab)
            R.pageOfTab[tab] = page
            for _, key in ipairs(tdef.keys or {}) do byKey[key] = byKey[key] or tab end
            if tdef.prefix then table.insert(rules, { pattern = tdef.prefix, exclude = tdef.exclude, tab = tab }) end
            for _, name in ipairs(tdef.sections or {}) do bySection[name] = bySection[name] or tab end
        end
    end

    local other -- Seite „Weitere“ für Bereiche ohne Platz
    for _, option in ipairs(R.allOptions) do
        local key = option.key
        local tab = key and byKey[key]
        if not tab and type(key) == "string" then
            for _, rule in ipairs(rules) do
                if key:find(rule.pattern) and not (rule.exclude and rule.exclude[key]) then
                    tab = rule.tab
                    break
                end
            end
        end
        local section = R.sectionOf[option]
        tab = tab or bySection[section]
        if not tab then
            if not other then
                other = { name = "Weitere", icon = "adjustments", tabs = {} }
                table.insert(pageList, other)
            end
            for _, t in ipairs(other.tabs) do
                if t.name == section then tab = t end
            end
            if not tab then
                tab = { name = section, options = {} }
                table.insert(other.tabs, tab)
                R.pageOfTab[tab] = other
            end
        end
        table.insert(tab.options, option)
        R.tabOf[option] = tab
    end

    -- Nur Reiter mit Optionen, nur Seiten mit Reitern (Übersicht und Alle Anzeigen immer)
    for _, page in ipairs(pageList) do
        local tabs = {}
        for _, tab in ipairs(page.tabs) do
            if #tab.options > 0 then table.insert(tabs, tab) end
        end
        page.tabs = tabs
        if page.home or page.displays or #tabs > 0 then table.insert(R.pages, page) end
    end
end

local function OptionEnabled(option)
    if not option.isEnabled then return true end
    local ok, enabled = pcall(option.isEnabled)
    return not ok or enabled and true or false
end

local function SafeGet(option)
    local ok, value = pcall(option.get)
    if ok then return value end
end

local function FindPage(name)
    for _, p in ipairs(R.pages) do
        if p.name == name then return p end
    end
end

local function FindTab(pageName, tabName)
    local page = FindPage(pageName)
    if not page then return end
    for i, tab in ipairs(page.tabs) do
        if tab.name == tabName then return page, tab, i end
    end
end

-- Seite und Reiter zu einem Ziel auflösen; frühere Namen (V.LEGACY_*) und Reiter auf anderer Seite
-- werden auf die neue Seite abgebildet. Gibt (Seite, Reiter-Name) oder nil zurück.
function V.Resolve(pageName, tabName)
    if tabName == nil and pageName == "Profile" then tabName = "Profile" end
    local page = FindPage(pageName) or FindPage(V.LEGACY_PAGES[pageName])
    local wanted = tabName and (V.LEGACY_TABS[tabName] or tabName)
    if wanted and not (page and FindTab(page.name, wanted)) then
        for _, p in ipairs(R.pages) do
            if FindTab(p.name, wanted) then
                page = p
                break
            end
        end
    end
    if page then return page, wanted end
end

-- Schalter-Option zu einem Schlüssel („@Bereich“ = erster Schalter dieses Bereichs)
local function SwitchOption(key)
    if type(key) ~= "string" then return nil end
    if key:sub(1, 1) == "@" then
        for _, option in ipairs(R.sections[key:sub(2)] or {}) do
            if not option.type then return option end
        end
        return nil
    end
    for _, option in ipairs(R.byKey[key] or {}) do
        if not option.type then return option end
    end
end

-- Hauptschalter eines Reiters (am Reiter geht vor der Seite)
local function TabMaster(page, tab)
    local key = (tab and tab.master) or (page and page.master)
    if key == "first" then
        for _, option in ipairs(tab and tab.options or {}) do
            if not option.type then return option end
        end
        return nil
    end
    return SwitchOption(key)
end

local function CurrentTab(page)
    if not page or page.home or page.displays or #page.tabs == 0 then return nil, 0 end
    local i = S.selectedTabs[page.name] or 1
    if i > #page.tabs then i = 1 end
    return page.tabs[i], i
end

---------------------------------------------------------------------------
-- Schnappschuss beim Öffnen, Zähler und Verwerfen
---------------------------------------------------------------------------

-- Laufende Daten (keine Einstellungen): zählen nicht als Änderung und werden nie zurückgesetzt
local DATA_KEYS = {
    point = true, uiSize = true, altData = true, accountCVarData = true, flightRouteTimes = true,
    mailAltList = true, playerNoteData = true, xpHistory = true, recentChanges = true,
}
local function IsDataKey(key)
    if DATA_KEYS[key] then return true end
    if type(key) ~= "string" then return false end
    return key:find("Data$") or key:find("History$") or key:find("Times$") or false
end

-- Tabellen, deren Einträge einzeln zählen (je Anzeige)
local PER_ENTRY = { positions = true, scales = true }

-- Bereiche mit Anzeigen/Rahmen: im Kampf erst nach dem Kampf zurücksetzen
local DEFER_SECTIONS = {
    ["Erfahrung"] = true, ["Kamera & Karte"] = true, ["Zaubern"] = true, ["Taschen"] = true,
    ["Tasche"] = true, ["Bank"] = true,
}

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end

local function DeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Kampf-Merker: PLAYER_REGEN_DISABLED kommt kurz bevor InCombatLockdown() wahr wird
local function InCombat()
    return S.combat or InCombatLockdown()
end
ns.On("PLAYER_REGEN_DISABLED", function() S.combat = true end)
ns.On("PLAYER_REGEN_ENABLED", function() S.combat = false end)

-- Optionen, deren Wert nicht in ns.db liegt (z. B. CVars wie Automatisch plündern)
local function IsOutsideOption(option)
    return option.key and option.type ~= "button" and option.type ~= "choice" and not option.noExport
        and ns.db[option.key] == nil
end

local function TakeSnapshot()
    local db = {}
    for key, value in pairs(ns.db) do
        if not IsDataKey(key) then db[key] = DeepCopy(value) end
    end
    local opts = {}
    for _, option in ipairs(R.allOptions) do
        if IsOutsideOption(option) then
            local value = SafeGet(option)
            local t = type(value)
            if not ns.IsSecret(value) and (t == "boolean" or t == "number" or t == "string") then
                opts[option] = value
            end
        end
    end
    S.snapshot = { db = db, opts = opts }
end

-- Liste der geänderten Einträge: { key =, sub = (für positions/scales) } und geänderte Außen-Optionen
local function Changes()
    local list, outside = {}, {}
    local snapshot = S.snapshot
    if not snapshot or not ns.db then return list, outside end
    local seen = {}
    local function Check(key)
        if seen[key] or IsDataKey(key) then return end
        seen[key] = true
        local old, new = snapshot.db[key], ns.db[key]
        -- erst nach dem Öffnen angelegte Tabellen sind Laufzeitdaten der Module
        if old == nil and type(new) == "table" then return end
        if PER_ENTRY[key] and type(old) == "table" and type(new) == "table" then
            local subs = {}
            for k in pairs(old) do subs[k] = true end
            for k in pairs(new) do subs[k] = true end
            for k in pairs(subs) do
                if not DeepEqual(old[k], new[k]) then table.insert(list, { key = key, sub = k }) end
            end
        elseif not DeepEqual(old, new) then
            table.insert(list, { key = key })
        end
    end
    for key in pairs(snapshot.db) do Check(key) end
    for key in pairs(ns.db) do Check(key) end
    for option, old in pairs(snapshot.opts) do
        local value = SafeGet(option)
        if not ns.IsSecret(value) and value ~= old then table.insert(outside, option) end
    end
    return list, outside
end

local function CountChanges()
    local list, outside = Changes()
    return #list + #outside
end

-- Braucht eine der Änderungen ein Neuladen?
local function NeedsReload()
    local list, outside = Changes()
    for _, change in ipairs(list) do
        if RELOAD_KEYS[change.key] then return true end
        for _, option in ipairs(R.byKey[change.key] or {}) do
            if option.reload then return true end
        end
    end
    for _, option in ipairs(outside) do
        if option.reload then return true end
    end
    return false
end

-- Im Kampf aufgeschobene Rücksetzungen
local pending = { options = {}, positions = {}, any = false }

local function RestoreMovable(key)
    for _, entry in ipairs(ns.movables or {}) do
        local f = entry.frame
        if f and f.strayKey == key then
            if f.strayDefault or (ns.db.positions and ns.db.positions[key]) then
                pcall(ns.RestorePosition, f)
            end
            if ns.db.scales ~= nil and ns.ApplyScale then pcall(ns.ApplyScale, f) end
        end
    end
end

-- Alle Einstellungen auf den Stand beim Öffnen zurücksetzen und sofort wieder anwenden
local function Revert()
    local snapshot = S.snapshot
    if not snapshot then return end
    local list, outside = Changes()
    if #list == 0 and #outside == 0 then return end
    local combat = InCombat()

    -- 1. Werte zurückschreiben
    local changedKeys, movedKeys = {}, {}
    for _, change in ipairs(list) do
        changedKeys[change.key] = true
        if change.sub ~= nil then movedKeys[change.sub] = true end
    end
    for key in pairs(changedKeys) do
        local old, current = snapshot.db[key], ns.db[key]
        if type(old) == "table" and type(current) == "table" then
            for k in pairs(current) do current[k] = nil end
            for k, v in pairs(old) do current[k] = DeepCopy(v) end
        else
            ns.db[key] = DeepCopy(old)
        end
    end

    -- 2. Optionen neu anwenden (set mit dem alten Wert)
    local applied = {}
    local function Apply(option, value)
        if applied[option] or option.type == "button" then return end
        applied[option] = true
        if combat and DEFER_SECTIONS[R.sectionOf[option]] then
            pending.options[option] = { value = value }
            pending.any = true
            return
        end
        if value == nil then value = SafeGet(option) end
        pcall(option.set, value)
    end
    for _, option in ipairs(outside) do Apply(option, snapshot.opts[option]) end
    for _, option in ipairs(R.allOptions) do
        if option.key and changedKeys[option.key] then Apply(option) end
    end
    -- Schlüssel ohne eigene Option (z. B. Werte je Leiste): verwandte Optionen gleichen Präfixes neu anwenden
    for key in pairs(changedKeys) do
        if not R.byKey[key] and not PER_ENTRY[key] and type(key) == "string" then
            local prefix = key:match("^%l+")
            if prefix and #prefix >= 2 then
                for _, option in ipairs(R.allOptions) do
                    if option.key and option.key:match("^%l+") == prefix then Apply(option) end
                end
            end
        end
    end

    -- 3. Positionen und Größen der Anzeigen
    for key in pairs(movedKeys) do
        if combat then
            pending.positions[key] = true
            pending.any = true
        else
            RestoreMovable(key)
        end
    end

    if combat and pending.any then
        ns.Print(L["Leisten und Rahmen werden nach dem Kampf zurückgesetzt."])
    end
    if Refresh and frame:IsShown() then Refresh() end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if not pending.any then return end
    local options, positions = pending.options, pending.positions
    pending.options, pending.positions, pending.any = {}, {}, false
    for _, option in ipairs(R.allOptions) do
        local entry = options[option]
        if entry then
            local value = entry.value
            if value == nil then value = SafeGet(option) end
            pcall(option.set, value)
        end
    end
    for key in pairs(positions) do RestoreMovable(key) end
    if Refresh and frame:IsShown() then Refresh() end
end)

---------------------------------------------------------------------------
-- Werte setzen (mit Konflikt-Nachfrage)
---------------------------------------------------------------------------

-- Nach jeder Änderung: Fenster neu zeichnen (Ausgrauen, Fußzeile)
function Changed()
    if Refresh then Refresh() end
end

-- Die letzten 5 geänderten Einstellungen (Schlüssel) in ns.db.recentChanges; Laufdaten, kein Profilwert
local function RecordChange(option)
    local key = option and option.key
    if type(key) ~= "string" or not ns.db then return end
    local list = ns.db.recentChanges
    if type(list) ~= "table" then
        list = {}
        ns.db.recentChanges = list
    end
    if list[1] == key then return end
    -- Auf der Übersicht bleibt die Reihenfolge stehen: sonst springt die Zeile unter der Maus (Regler beim Ziehen)
    local current = FindPage(S.selected) or R.pages[1]
    if current and current.home then
        for _, k in ipairs(list) do
            if k == key then return end
        end
    end
    for i = #list, 1, -1 do
        if list[i] == key then table.remove(list, i) end
    end
    table.insert(list, 1, key)
    while #list > 5 do table.remove(list) end
end

local function SetOptionValue(option, value)
    local done = false
    local function apply()
        if done then return end
        done = true
        if value == true then
            local required = SwitchOption(MASTER_REQUIRES[option.key])
            if required and not SafeGet(required) then pcall(required.set, true) end
        end
        local ok, err = pcall(option.set, value)
        if not ok then geterrorhandler()(err) end
        RecordChange(option)
        Changed()
    end
    if value == true and option.key and ns.ConfirmOption then
        -- Abbrechen: gespeicherter Wert bleibt, Anzeige neu zeichnen (Schalter springt zurück)
        local ok, err = pcall(ns.ConfirmOption, option.key, value, apply, function() Changed() end)
        if not ok then
            geterrorhandler()(err)
            apply()
        end
    else
        apply()
    end
end

-- „Alles deaktivieren“: schaltet alle eingeschalteten Schalter aus (Werte, Auswahlen und Positionen bleiben);
-- zählt wie jede Änderung: „Übernehmen“ lädt neu, „Verwerfen“ nimmt es zurück
do
    local function DisableAll()
        local n = 0
        for _, option in ipairs(R.allOptions) do
            if option.key and not option.type and option.key ~= "updateNotice" and SafeGet(option) == true then
                SetOptionValue(option, false)
                n = n + 1
            end
        end
        ns.Print(string.format(L["%d Optionen ausgeschaltet. „Übernehmen“ lädt neu, „Verwerfen“ nimmt es zurück."], n))
    end
    StaticPopupDialogs["STRAY_DISABLE_ALL"] = {
        text = "",
        button1 = "",
        button2 = CANCEL,
        OnAccept = function() DisableAll() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    ns.AddOption(3, "Profile", {
        key = "disableAll",
        type = "button",
        label = L["Alles deaktivieren"],
        buttonText = L["Alles ausschalten"],
        keywords = { "alles", "deaktivieren", "ausschalten", "zurücksetzen", "alle optionen", "disable all", "turn off", "everything", "reset" },
        tooltip = L["Schaltet alle eingeschalteten Optionen von stray aus. Einstellungen wie Werte, Auswahlen und Positionen bleiben erhalten. Danach „Übernehmen“ (lädt neu) oder „Verwerfen“."],
        onClick = function()
            StaticPopupDialogs["STRAY_DISABLE_ALL"].text = L["Alle Optionen von stray ausschalten?"]
            StaticPopupDialogs["STRAY_DISABLE_ALL"].button1 = L["Alles ausschalten"]
            StaticPopup_Show("STRAY_DISABLE_ALL")
        end,
    })
end

local function ConflictText(option)
    if not option or not option.key or not ns.ConflictHint then return nil end
    local ok, text = pcall(ns.ConflictHint, option.key)
    if ok and type(text) == "string" and text ~= "" then return text end
end

local function SliderUnit(option)
    return option.unit or UNITS[option.key]
end

-- Reglerwert auf Grenzen und Raster bringen und setzen
local function SetSliderValue(option, v)
    if type(v) ~= "number" or not OptionEnabled(option) then return end
    local min, max, step = option.min or 0, option.max or 100, option.step or 1
    v = math.max(min, math.min(max, v))
    v = min + math.floor((v - min) / step + 0.5) * step
    if step >= 1 then v = RoundInt(v) else v = tonumber(string.format("%.4f", v)) end
    if SafeGet(option) ~= v then
        option.set(v)
        RecordChange(option)
        Changed()
    end
end

---------------------------------------------------------------------------
-- Tooltip und Vorschau
---------------------------------------------------------------------------

local function ShowTooltip(row)
    local option = row.option
    if not option then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(T(option.label), 1, 1, 1)
    if option.tooltip then
        GameTooltip:AddLine(T(option.tooltip), ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    elseif option.desc then
        GameTooltip:AddLine(T(option.desc), ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    end
    if option.type == "slider" then
        GameTooltip:AddLine(L["Wert eintippen und Enter drücken oder die Pfeile nutzen. Mausrad mit gedrückter Umschalttaste verstellt den Regler."], C.grey[1], C.grey[2], C.grey[3], true)
    end
    if not OptionEnabled(option) and option.disabledHint then
        GameTooltip:AddLine(T(option.disabledHint), 1, 0.3, 0.3, true)
    end
    if option.key == "language" then
        GameTooltip:AddLine(L["Umschalten zählt als Änderung: „Übernehmen“ lädt neu und setzt die Sprache um."], C.grey[1], C.grey[2], C.grey[3], true)
    end
    if row.nav then
        GameTooltip:AddLine(L["Klick auf den Namen öffnet die Seite."], C.accentT[1], C.accentT[2], C.accentT[3], true)
    end
    GameTooltip:Show()
end

local function ShowPreview(option, row)
    local preview = W.preview
    if preview:IsShown() and preview.option == option then
        preview:Hide()
        return
    end
    preview.option = option
    preview:ClearAllPoints()
    local rowBottom, scrollBottom = row and row:GetBottom(), scroll:GetBottom()
    if row and rowBottom and scrollBottom and rowBottom - 160 < scrollBottom then
        preview:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 4)
    elseif row then
        preview:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -4)
    else
        preview:SetPoint("CENTER", scroll, "CENTER")
    end
    preview.image:SetTexture(MEDIA .. option.preview)
    preview.caption:SetText(L("Beispielbild: %s", T(option.label) or ""))
    preview:Show()
end

---------------------------------------------------------------------------
-- Elemente des Inhalts (Pools je Art)
---------------------------------------------------------------------------

local pools = { option = {}, heading = {}, hint = {}, position = {}, instance = {}, quick = {}, map = {}, display = {} }
local used = {}

local function Take(kind, create)
    used[kind] = (used[kind] or 0) + 1
    local list = pools[kind]
    local el = list[used[kind]]
    if not el then
        el = create()
        el:SetFrameLevel(scrollChild:GetFrameLevel() + 3)
        list[used[kind]] = el
    end
    el:Show()
    return el
end

-- Optionszeile: Name links, Bedienelement rechts
local function CreateOptionRow()
    local row = CreateFrame("Button", nil, scrollChild)
    row:RegisterForClicks("LeftButtonUp")
    row.hl = RoundRect(row, 6, { C.hover[1], C.hover[2], C.hover[3], 0.6 }, "BACKGROUND")
    row.hl:SetShown(false)

    row.label = Text(row, 13, C.text)
    row.label:SetPoint("LEFT", 12, 0)
    row.label:SetWordWrap(false)
    row.sub = Text(row, 12, C.faint)
    row.sub:SetJustifyH("RIGHT")
    row.sub:SetWordWrap(false)

    row.switch = MakeSwitch(row)
    row.switch:SetPoint("RIGHT", -12, 0)
    row.switch:SetScript("OnClick", function()
        local option = row.option
        if not option or not OptionEnabled(option) then return end
        local value = not SafeGet(option)
        ns.Sound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        SetOptionValue(option, value)
    end)
    row.switch:SetScript("OnEnter", function() ShowTooltip(row) end)
    row.switch:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.previewButton = MakeButton(row, L["Vorschau"], "dark", 22)
    row.previewButton.text:SetFont(FONT, FS(11), "")
    row.previewButton:SetLabel(L["Vorschau"])
    row.previewButton:SetPoint("RIGHT", row.switch, "LEFT", -10, 0)
    row.previewButton:SetScript("OnClick", function() if row.option then ShowPreview(row.option, row) end end)

    -- Regler mit Zahlenfeld
    -- Forever: schwarze Spur mit Bronzerand als eigener Rahmen unter dem Regler
    local holder, trackFx
    if FOREVER then
        holder = CreateFrame("Frame", nil, row)
        holder:SetHeight(8)
        trackFx = FX("EditBox", holder)
    end
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:EnableMouseWheel(true)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    slider:SetThumbTexture(thumb)
    slider.fill = slider:CreateTexture(nil, "ARTWORK", nil, 1)
    if trackFx then
        holder:SetPoint("LEFT", slider, "LEFT")
        holder:SetPoint("RIGHT", slider, "RIGHT")
        slider.holder = holder
        -- Schieber: schmaler Bronze-Griff mit dunklem Rand; Füllung Lila
        local edge = slider:CreateTexture(nil, "OVERLAY", nil, -1)
        edge:SetPoint("TOPLEFT", thumb, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(0.04, 0.03, 0.02, 1)
        thumb:SetSize(10, 18)
        thumb:SetColorTexture(0.84, 0.76, 0.54, 1)
        slider.fill:SetHeight(6)
        slider.fill:SetPoint("LEFT", holder, "LEFT", 1, 0)
        slider.fill:SetPoint("RIGHT", thumb, "CENTER")
        slider.fill:SetColorTexture(C.accent[1] * 0.75, C.accent[2] * 0.75, C.accent[3] * 0.85, 1)
    else
        if holder then holder:Hide() end
        slider.track = slider:CreateTexture(nil, "ARTWORK")
        slider.track:SetPoint("LEFT"); slider.track:SetPoint("RIGHT"); slider.track:SetHeight(4)
        slider.track:SetTexture(MEDIA .. "pill")
        slider.track:SetVertexColor(C.off[1], C.off[2], C.off[3], 1)
        thumb:SetSize(14, 14)
        thumb:SetTexture(MEDIA .. "dot")
        thumb:SetVertexColor(1, 1, 1, 1)
        slider.fill:SetHeight(4)
        slider.fill:SetPoint("LEFT", slider.track, "LEFT")
        slider.fill:SetPoint("RIGHT", thumb, "CENTER")
        slider.fill:SetTexture(MEDIA .. "pill")
        slider.fill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        local option = row.option
        if not option or option.type ~= "slider" then return end
        SetSliderValue(option, value)
    end)
    -- Mausrad scrollt die Seite; nur mit gedrückter Umschalttaste verstellt es den Regler
    slider:SetScript("OnMouseWheel", function(self, delta)
        local option = row.option
        if not IsShiftKeyDown() or not option or not OptionEnabled(option) then
            SetScroll(scroll:GetVerticalScroll() - delta * M.WHEEL)
            return
        end
        self:SetValue(self:GetValue() + delta * (option.step or 1))
    end)
    slider:SetScript("OnEnter", function() ShowTooltip(row) end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.slider = slider

    row.num = MakeNumberField(row)
    row.num:SetPoint("RIGHT", -12, 0)
    row.num.get = function() return row.option and SafeGet(row.option) end
    row.num.set = function(v) if row.option then SetSliderValue(row.option, v) end end
    row.num.onEnter = function() ShowTooltip(row) end

    -- Auswahl als Dropdown
    row.drop = MakeDropdown(row)
    row.drop:SetPoint("RIGHT", -12, 0)
    row.drop.onEnter = function() ShowTooltip(row) end

    -- Knopf für Aktionen (type = "button")
    row.action = MakeButton(row, "", "dark", 28)
    row.action:SetPoint("RIGHT", -12, 0)
    row.action:SetScript("OnClick", function()
        local option = row.option
        if not option or option.type ~= "button" or not OptionEnabled(option) then return end
        ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if option.onClick then
            local ok, err = pcall(option.onClick)
            if not ok then geterrorhandler()(err) end
        end
        Changed()
    end)
    local actionEnter = row.action:GetScript("OnEnter")
    row.action:SetScript("OnEnter", function(self) actionEnter(self); ShowTooltip(row) end)

    row:SetScript("OnEnter", function(self)
        self.hl:SetShown(true)
        ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:SetShown(false)
        GameTooltip:Hide()
    end)
    -- Klick auf die Zeile: Seite öffnen (Zentrale) bzw. Schalter umschalten
    row:SetScript("OnClick", function(self)
        if self.nav then
            S.Navigate(self.nav.page, self.nav.tab)
        elseif self.option and not self.option.type then
            self.switch:Click()
        end
    end)
    return row
end

local function ChoiceItems(option)
    local items = {}
    for i, v in ipairs(option.values or {}) do
        local label = option.labels and option.labels[i]
        items[i] = { value = v, label = label and T(label) or tostring(v) }
    end
    return items
end

-- Zeile füllen und anordnen; gibt die Zeilenhöhe zurück
local function FillOptionRow(row, option, width, item)
    local enabled = OptionEnabled(option)
    row.option = option
    row.nav = item.nav
    row.label:SetText(T(option.label))
    SetTextColor(row.label, enabled and C.text or C.grey)
    row.sub:SetText(item.sub or "")
    row.sub:SetShown(item.sub ~= nil)

    local kind = option.type
    local isSwitch = kind == nil
    row.switch:SetShown(isSwitch)
    row.previewButton:SetShown(isSwitch and option.preview ~= nil)
    row.slider:SetShown(kind == "slider")
    if row.slider.holder then row.slider.holder:SetShown(kind == "slider") end
    row.num:SetShown(kind == "slider")
    row.drop:SetShown(kind == "choice")
    row.action:SetShown(kind == "button")
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 12, 0)
    row.sub:ClearAllPoints()

    local controlW
    if kind == "slider" then
        local slider = row.slider
        slider.updating = true
        slider:SetMinMaxValues(option.min or 0, option.max or 100)
        slider:SetValueStep(option.step or 1)
        local value = SafeGet(option)
        if type(value) ~= "number" then value = option.min or 0 end
        slider:SetValue(value)
        slider.updating = false
        slider:EnableMouse(enabled)
        slider:SetAlpha(enabled and 1 or 0.4)
        if slider.holder then slider.holder:SetAlpha(enabled and 1 or 0.4) end
        local unit = SliderUnit(option)
        row.num.step = option.step or 1
        row.num.fmt = function(v)
            if option.format then
                local ok, text = pcall(option.format, v)
                if ok and text then return tostring(text) end
            end
            return NumberText(v, option.step) .. (unit and (" " .. unit) or "")
        end
        row.num:SetActive(enabled)
        row.num:Refresh()
        -- Name · Regler · Zahlenfeld
        local wide = FOREVER and 1.25 or 1 -- Friz Quadrata braucht mehr Platz
        local nameW = math.floor(math.min(240 * wide, math.max(130 * wide, width * 0.36 * wide)))
        row.label:SetWidth(nameW)
        slider:ClearAllPoints()
        slider:SetPoint("LEFT", row, "LEFT", 12 + nameW + 12, 0)
        slider:SetPoint("RIGHT", row.num, "LEFT", -18, 0)
        return M.ROW_H
    elseif kind == "button" then
        row.action:SetLabel(T(option.buttonText or option.label), 80)
        row.action:SetActive(enabled)
        controlW = row.action:GetWidth()
    elseif kind == "choice" then
        row.drop:SetItems(ChoiceItems(option), SafeGet(option), function(value)
            if OptionEnabled(option) then
                option.set(value)
                RecordChange(option)
                Changed()
            end
        end, enabled)
        row.drop:SetWidth(M.DROP_W)
        controlW = M.DROP_W
    else
        row.switch:SetState(SafeGet(option) and true or false, enabled)
        controlW = row.switch:GetWidth() + (option.preview and (row.previewButton:GetWidth() + 10) or 0)
    end
    if item.sub then
        row.sub:SetPoint("RIGHT", row, "RIGHT", -(12 + controlW + 16), 0)
        row.label:SetPoint("RIGHT", row.sub, "LEFT", -12, 0)
    else
        row.label:SetPoint("RIGHT", row, "RIGHT", -(12 + controlW + 12), 0)
    end
    return M.ROW_H
end

-- Abschnitts-Überschrift: Großbuchstaben, feine Linie bis zum Rand
local function CreateHeading()
    local h = CreateFrame("Frame", nil, scrollChild)
    h.text = Text(h, FOREVER and 13 or 11, FOREVER and C.gold or C.grey)
    h.text:SetPoint("BOTTOMLEFT", 12, 8)
    h.line = Line(h, FOREVER and { ns.Colors.bronze[1], ns.Colors.bronze[2], ns.Colors.bronze[3], 0.8 } or C.line)
    h.line:SetPoint("LEFT", h.text, "RIGHT", 12, 0)
    h.line:SetPoint("RIGHT", h, "RIGHT", -4, 0)
    h.line:SetHeight(FOREVER and 2 or 1)
    return h
end

-- Hinweis-Kasten (z. B. Konflikt mit einem anderen Addon)
local function CreateHint()
    local h = CreateFrame("Frame", nil, scrollChild)
    h.fill, h.border = Panel(h, 6, C.amberBg, { C.amber[1], C.amber[2], C.amber[3], FOREVER and 0.8 or 0.45 }, "BACKGROUND")
    h.bar = Line(h, C.amber, "ARTWORK")
    h.bar:SetPoint("TOPLEFT", 1, -6)
    h.bar:SetPoint("BOTTOMLEFT", 1, 6)
    h.bar:SetWidth(2)
    h.text = Text(h, 12, C.hint)
    h.text:SetPoint("TOPLEFT", 14, -9)
    h.text:SetWordWrap(true)
    h.text:SetJustifyV("TOP")
    return h
end

-- Zeile POSITION: [Name] X [Feld] Y [Feld] [Zentrieren]
local function CreatePositionRow()
    local row = CreateFrame("Frame", nil, scrollChild)
    row.name = Text(row, 13, C.text)
    row.name:SetPoint("LEFT", 12, 0)
    row.name:SetWordWrap(false)
    row.xl = Text(row, 13, C.grey)
    row.xl:SetText("X")
    row.x = MakeNumberField(row, 96)
    row.yl = Text(row, 13, C.grey)
    row.yl:SetText("Y")
    row.y = MakeNumberField(row, 96)
    row.center = MakeButton(row, L["Zentrieren"], "dark", 28)
    row.center:SetPoint("RIGHT", -12, 0)

    local function Center()
        local f = row.entry and row.entry.frame
        if not f or not ns.GetMovableCenter then return end
        return ns.GetMovableCenter(f)
    end
    local function Move(x, y)
        local f = row.entry and row.entry.frame
        if not f or not ns.SetMovableCenter or InCombat() then return end
        ns.SetMovableCenter(f, x, y)
        Changed()
    end
    row.x.get = function() local x = Center() return x end
    row.x.set = function(v) Move(v, nil) end
    row.y.get = function() local _, y = Center() return y end
    row.y.set = function(v) Move(nil, v) end
    local function Tip(box, title, body)
        box.onEnter = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(L[body], ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
            GameTooltip:Show()
        end
    end
    Tip(row.x, "X", "Waagerechter Abstand der Mitte zur Bildschirmmitte in Pixeln (negativ = links), wie im Bearbeitungsmodus. Enter übernimmt.")
    Tip(row.y, "Y", "Senkrechter Abstand der Mitte zur Bildschirmmitte in Pixeln (negativ = unten), wie im Bearbeitungsmodus. Enter übernimmt.")
    row.center:SetScript("OnClick", function()
        if IsShiftKeyDown() then Move(0, 0) else Move(0, nil) end
    end)
    ButtonTooltip(row.center, "Zentrieren", "Setzt die Anzeige waagerecht auf die Bildschirmmitte (X = 0). Mit Shift auch senkrecht (Y = 0).")
    function row:Refresh()
        local ok = Center() ~= nil and not InCombat()
        self.x:SetActive(ok)
        self.y:SetActive(ok)
        self.center:SetActive(ok)
        self.x:Refresh()
        self.y:Refresh()
    end
    return row
end

-- Auswahlliste für mehrere gleiche Anzeigen („Aktionsleiste 1“) + „Im Spiel ausgewählt“
local function CreateInstanceRow()
    local row = CreateFrame("Frame", nil, scrollChild)
    row.drop = MakeDropdown(row)
    row.drop:SetWidth(220)
    row.drop:SetPoint("LEFT", 0, 0)
    row.picked = Text(row, 12, C.accentT)
    row.picked:SetPoint("LEFT", row.drop, "RIGHT", 16, 0)
    return row
end

-- Zentrale: Schnellzugriff
local function CreateQuickRow()
    local row = CreateFrame("Frame", nil, scrollChild)
    row.buttons = {}
    return row
end

---------------------------------------------------------------------------
-- Mehrere gleiche Anzeigen (Vertrag für Module)
---------------------------------------------------------------------------

function ns.RegisterInstances(name, list, getSelected, setSelected)
    if type(name) ~= "string" then return end
    S.instances[name] = { list = list, get = getSelected, set = setSelected }
    if frame:IsShown() and Refresh then Refresh() end
end

local function InstanceList(inst)
    local list = inst.list
    if type(list) == "function" then
        local ok, res = pcall(list)
        list = ok and res or nil
    end
    return type(list) == "table" and list or {}
end

-- Passt ein Listeneintrag zur Anzeige mit diesem strayKey? Über strayKey/id/key oder über den Namen
-- („DMG-Meter 2“ = Anzeige „DMG-Meter 2“, „DMG-Meter 1“ = Anzeige „DMG-Meter“)
local function InstanceMatches(e, key)
    if key == nil then return false end
    if e.strayKey == key or e.id == key or e.key == key then return true end
    if not e.label then return false end
    for _, entry in ipairs(ns.movables or {}) do
        if entry.frame and entry.frame.strayKey == key then
            local a, b = LabelText(entry.label), LabelText(e.label)
            return a == b or (a .. " 1") == b
        end
    end
    return false
end

local function InstanceFor(page, tab)
    local inst = (tab and S.instances[tab.name]) or (page and S.instances[page.name])
    if inst then return inst end
end

local function InstanceCurrent(inst)
    if not inst.get then return nil end
    local ok, v = pcall(inst.get)
    if ok then return v end
end

---------------------------------------------------------------------------
-- Verschiebbare Anzeigen je Reiter
---------------------------------------------------------------------------

local function MovableTab(label)
    if type(label) ~= "string" then return end
    for _, m in ipairs(MOVABLE_TABS) do
        if label:sub(1, #m[1]) == m[1] then return m[2], m[3], m[4] end
    end
end

local function MovablesFor(page, tab)
    local list = {}
    for _, entry in ipairs(ns.movables or {}) do
        local f = entry.frame
        if f and f.strayKey then
            local p, t = MovableTab(entry.label)
            if (p == page.name and t == tab.name) or (not p and entry.label == tab.name) then
                table.insert(list, entry)
            end
        end
    end
    -- Bei einer Auswahlliste nur die gewählte Anzeige (wenn sie sich zuordnen lässt)
    local inst = InstanceFor(page, tab)
    if inst and #list > 1 then
        local current = InstanceCurrent(inst)
        for _, e in ipairs(InstanceList(inst)) do
            if e.id == current then
                for _, entry in ipairs(list) do
                    if InstanceMatches(e, entry.frame.strayKey) then return { entry } end
                end
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Alle Anzeigen: Zeilen
---------------------------------------------------------------------------

-- Zeile der Seite „Alle Anzeigen“: Name · Ort · Sichtbar/Aus; Klick springt zur Einstellung
local function CreateDisplayRow()
    local row = CreateFrame("Button", nil, scrollChild)
    row:RegisterForClicks("LeftButtonUp")
    row.hl = RoundRect(row, 6, { C.hover[1], C.hover[2], C.hover[3], 0.6 }, "BACKGROUND")
    row.hl:SetShown(false)
    row.label = Text(row, 14, C.text)
    row.label:SetPoint("LEFT", 12, 0)
    row.label:SetWordWrap(false)
    row.state = Text(row, 13, C.grey)
    row.state:SetPoint("RIGHT", -14, 0)
    row.state:SetWidth(90)
    row.state:SetJustifyH("RIGHT")
    row.sub = Text(row, 12, C.grey)
    row.sub:SetWordWrap(false)
    function row:Fill(item, width)
        local nameW = math.floor(width * (FOREVER and 0.36 or 0.32))
        self.label:SetWidth(nameW)
        self.label:SetText(item.text)
        self.sub:ClearAllPoints()
        self.sub:SetPoint("LEFT", self, "LEFT", 12 + nameW + 8, 0)
        self.sub:SetPoint("RIGHT", self.state, "LEFT", -8, 0)
        self.sub:SetText(item.sub or "")
        self.state:SetText(item.active and L["Sichtbar"] or L["Aus"])
        SetTextColor(self.state, item.active and C.accentT or C.faint)
        SetTextColor(self.label, item.active and C.text or C.grey)
        self.nav = item.nav
    end
    row:SetScript("OnEnter", function(self)
        self.hl:SetShown(true)
        if self.nav then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine(L["Klick: Einstellungen"], C.grey[1], C.grey[2], C.grey[3])
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:SetShown(false)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local nav = self.nav
        if not nav then return end
        S.Navigate(nav.page, nav.tab)
        -- Bei mehreren gleichen Anzeigen (Aktionsleiste 2, DMG-Meter 3) gleich die richtige wählen
        local page, tab = FindTab(nav.page, nav.tab)
        local inst = page and InstanceFor(page, tab)
        if inst and inst.set and nav.key then
            for _, e in ipairs(InstanceList(inst)) do
                if InstanceMatches(e, nav.key) then
                    pcall(inst.set, e.id)
                    break
                end
            end
            Refresh()
        end
    end)
    return row
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function UpdateMetrics()
    local w = (frame:GetWidth() or M.WIDTH) - M.SIDE_W - 1 - M.CL - M.CR - P
    M.SCROLL_W = math.max(300, math.floor(w))
    scrollChild:SetWidth(M.SCROLL_W)
end

-- items: { kind = "heading" | "option" | "hint" | "position" | "instance" | "quick", … }
local function Layout(items)
    UpdateMetrics()
    for kind in pairs(pools) do used[kind] = 0 end
    local width = M.SCROLL_W
    local y = 0
    for i, item in ipairs(items) do
        local el, h
        if item.kind == "heading" then
            el = Take("heading", CreateHeading)
            el.text:SetText(item.text)
            h = (i == 1) and (M.HEAD_H - 8) or M.HEAD_H
        elseif item.kind == "option" then
            el = Take("option", CreateOptionRow)
            h = FillOptionRow(el, item.option, width, item)
        elseif item.kind == "hint" then
            el = Take("hint", CreateHint)
            el.text:SetWidth(width - 2 * 12 - 16)
            el.text:SetText(item.text)
            h = math.max(30, math.floor((el.text:GetStringHeight() or 14) + 18))
            y = y + 2
        elseif item.kind == "position" then
            el = Take("position", CreatePositionRow)
            el.entry = item.entry
            el.name:SetShown(item.showName and true or false)
            el.name:SetText(LabelText(item.entry.label))
            el.xl:ClearAllPoints()
            if item.showName then
                el.name:SetWidth(math.floor(math.min(200, width * 0.3)))
                el.xl:SetPoint("LEFT", el.name, "RIGHT", 10, 0)
            else
                el.xl:SetPoint("LEFT", 14, 0)
            end
            el.x:ClearAllPoints()
            el.x:SetPoint("LEFT", el.xl, "RIGHT", 10, 0)
            el.yl:ClearAllPoints()
            el.yl:SetPoint("LEFT", el.x, "RIGHT", 22, 0)
            el.y:ClearAllPoints()
            el.y:SetPoint("LEFT", el.yl, "RIGHT", 10, 0)
            el:Refresh()
            h = M.ROW_H + 4
        elseif item.kind == "instance" then
            el = Take("instance", CreateInstanceRow)
            local inst = item.inst
            local items2, current = {}, InstanceCurrent(inst)
            local picked = false
            for _, e in ipairs(InstanceList(inst)) do
                table.insert(items2, { value = e.id, label = LabelText(e.label or tostring(e.id)) })
                if e.id == current and InstanceMatches(e, ns.EditSelected) then picked = true end
            end
            el.drop:SetItems(items2, current, function(value)
                if inst.set then
                    local ok, err = pcall(inst.set, value)
                    if not ok then geterrorhandler()(err) end
                end
                Changed()
            end)
            el.picked:SetText(picked and L["Im Spiel ausgewählt"] or "")
            h = 40
        elseif item.kind == "quick" then
            el = Take("quick", CreateQuickRow)
            local x = 12
            for bi, def in ipairs(item.buttons) do
                local b = el.buttons[bi]
                if not b then
                    b = MakeButton(el, "", "dark", 30)
                    ButtonTooltip(b, function() return b.tipTitle end, function() return b.tipBody end)
                    el.buttons[bi] = b
                end
                b:SetLabel(def.label, 120)
                b.tipTitle, b.tipBody = def.label, def.tip
                b:SetScript("OnClick", function(self) if not self.inactive then def.onClick() end end)
                b:SetActive(def.enabled ~= false)
                b:ClearAllPoints()
                b:SetPoint("LEFT", el, "LEFT", x, 0)
                b:Show()
                x = x + b:GetWidth() + 10
            end
            for bi = #item.buttons + 1, #el.buttons do el.buttons[bi]:Hide() end
            h = 44
        elseif item.kind == "display" then
            el = Take("display", CreateDisplayRow)
            el:Fill(item, width)
            h = M.ROW_H - 4
        end
        if el then
            el:ClearAllPoints()
            el:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            el:SetWidth(width)
            el:SetHeight(h)
            y = y + h
        end
    end
    for kind, list in pairs(pools) do
        for i = (used[kind] or 0) + 1, #list do
            list[i].option, list[i].entry, list[i].nav = nil, nil, nil
            list[i]:Hide()
        end
    end
    scrollChild:SetHeight(math.max(1, y + 8))
    ClampScroll()
end

---------------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------------

local searchCache = {} -- Option → { keywords = {…}, label = "…", rest = "…" }

local function SearchData(option)
    local data = searchCache[option]
    if data then return data end
    local section = R.sectionOf[option] or ""
    local tab = R.tabOf[option]
    local page = tab and R.pageOfTab[tab]
    local words = {}
    local function Add(list)
        if type(list) ~= "table" then return end
        for _, w in ipairs(list) do table.insert(words, Lower(w)) end
    end
    Add(option.keywords)
    Add(option.key and KEYWORDS[option.key])
    Add(SECTION_KEYWORDS[section])
    -- Name, Beschreibung, Bereich, Reiter und Seite jeweils deutsch und englisch
    local EN = ns.LocaleEN or {}
    local function Both(text)
        if type(text) ~= "string" or text == "" then return "" end
        if ns.TBoth then
            local de, en = ns.TBoth(text)
            return de .. " " .. en
        end
        return text
    end
    local function BothKey(key)
        if not key or key == "" then return "" end
        local en = EN[key]
        return key .. " " .. (type(en) == "string" and en or "")
    end
    data = {
        keywords = words,
        label = Lower(Both(option.label)),
        rest = Lower(Both(option.tooltip) .. " " .. BothKey(section) .. " " .. BothKey(tab and tab.name)
            .. " " .. BothKey(page and page.name)),
    }
    searchCache[option] = data
    return data
end

-- Punkte für eine Option: 0 = kein Treffer; Stichwort-Treffer zählen am meisten
local function Score(option, tokens)
    local data = SearchData(option)
    local total = 0
    for _, token in ipairs(tokens) do
        local best = 0
        for _, w in ipairs(data.keywords) do
            if w:find(token, 1, true) then best = 3 break end
        end
        if best == 0 and data.label:find(token, 1, true) then best = 2 end
        if best == 0 and data.rest:find(token, 1, true) then best = 1 end
        if best == 0 then return 0 end
        total = total + best
    end
    return total
end

-- Treffer nach Reitern gruppiert, beste zuerst; gibt Blöcke und Anzahl zurück
local function SearchResults(query)
    local tokens = {}
    for token in Lower(query):gmatch("%S+") do table.insert(tokens, token) end
    local blocks, count, order = {}, 0, 0
    if #tokens == 0 then return blocks, 0 end
    for _, page in ipairs(R.pages) do
        for _, tab in ipairs(page.tabs) do
            local found, best = {}, 0
            for i, option in ipairs(tab.options) do
                local score = Score(option, tokens)
                if score > 0 then
                    table.insert(found, { option = option, score = score, i = i })
                    if score > best then best = score end
                end
            end
            if #found > 0 then
                table.sort(found, function(a, b)
                    if a.score ~= b.score then return a.score > b.score end
                    return a.i < b.i
                end)
                local options = {}
                for _, f in ipairs(found) do table.insert(options, f.option) end
                count = count + #options
                order = order + 1
                table.insert(blocks, { page = page, tab = tab, options = options, score = best, order = order })
            end
        end
    end
    table.sort(blocks, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    return blocks, count
end

Build(function()
    W.search:SetScript("OnTextChanged", function(self)
        W.placeholder:SetShown(self:GetText() == "")
        SetScroll(0)
        if Refresh then Refresh() end
    end)
    W.search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    W.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
end)

---------------------------------------------------------------------------
-- Navigation links und Profil-Auswahl
---------------------------------------------------------------------------

local navButtons = {}

-- Seite (und optional Reiter) wählen
function S.Navigate(pageName, tabName)
    local page
    page, tabName = V.Resolve(pageName, tabName)
    if not page then return end
    pageName = page.name
    if S.selected ~= pageName or W.search:GetText() ~= "" then SetScroll(0) end
    S.selected = pageName
    if tabName then
        for i, tab in ipairs(page.tabs) do
            if tab.name == tabName then S.selectedTabs[pageName] = i end
        end
    end
    W.search:SetText("")
    W.search:ClearFocus()
    W.preview:Hide()
    CloseMenu()
    ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    Refresh()
end

-- Öffnet das stray-Fenster auf einer Seite (und Reiter), z. B. aus dem Zahnrad des DMG-Meters
function ns.OpenConfig(pageName, tabName)
    if not strayFrame then return end
    if not strayFrame:IsShown() then strayFrame:Show() end
    S.Navigate(pageName, tabName)
end

local function BuildNav()
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", P, -M.TOP_H - 1)
    side:SetPoint("BOTTOMLEFT", P, P)
    side:SetWidth(M.SIDE_W - P)
    FX("Fill", side, "inset") -- Forever: dunkler Schiefer hinter der Navigation

    local y = -12
    for _, page in ipairs(R.pages) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(M.SIDE_W - 16 - P, M.NAV_H)
        b:SetPoint("TOPLEFT", 8, y)
        b.page = page
        b.bg = RoundRect(b, 6, C.hover, "BACKGROUND")
        b.bg:SetShown(false)
        b.bar = Line(b, C.accent, "ARTWORK")
        b.bar:SetPoint("TOPLEFT", 0, -6)
        b.bar:SetPoint("BOTTOMLEFT", 0, 6)
        b.bar:SetWidth(3)
        b.icon = Icon(b, page.icon or "adjustments", 17, C.grey)
        b.icon:SetPoint("LEFT", 14, 0)
        b.text = Text(b, 14, C.navText)
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 11, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self) S.Navigate(self.page.name) end)
        b:SetScript("OnEnter", function(self)
            if not self.isSelected then
                self.bg:SetColor({ C.hover[1], C.hover[2], C.hover[3], 0.6 })
                self.bg:SetShown(true)
            end
        end)
        b:SetScript("OnLeave", function(self)
            if not self.isSelected then self.bg:SetShown(false) end
        end)
        table.insert(navButtons, b)
        y = y - M.NAV_H - 2
    end
    S.navBottom = -y + M.TOP_H

    -- Profil-Auswahl unten links
    local line = Line(side, FOREVER and ns.Colors.bronze or C.line)
    line:SetPoint("BOTTOMLEFT", 1, M.PROFILE_H)
    line:SetPoint("BOTTOMRIGHT", -1, M.PROFILE_H)
    line:SetHeight(1)
    local drop = MakeDropdown(side)
    drop:SetPoint("BOTTOMLEFT", 12, (M.PROFILE_H - 28) / 2)
    drop:SetPoint("BOTTOMRIGHT", -12, (M.PROFILE_H - 28) / 2)
    drop.onEnter = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Profil"], 1, 1, 1)
        GameTooltip:AddLine(L["Aktives Profil. Im Menü: Profil wechseln (falls vorhanden), exportieren oder importieren."], ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
        GameTooltip:Show()
    end
    W.profileDrop = drop
end

-- Profil-Menü: nutzt eine Profil-Schnittstelle aus profiles.lua, falls vorhanden
-- (ns.Profiles.GetList/GetActive/SetActive); sonst „Standard“ + Export/Import über deren Optionen.
local function ProfileMenu()
    local items, current = {}, "default"
    local api = type(ns.Profiles) == "table" and ns.Profiles or nil
    if api and api.GetList and api.GetActive then
        local okList, list = pcall(api.GetList)
        local okActive, active = pcall(api.GetActive)
        if okList and type(list) == "table" then
            for _, name in ipairs(list) do table.insert(items, { value = name, label = tostring(name) }) end
        end
        if okActive then current = active end
    end
    if #items == 0 then items[1] = { value = "default", label = L["Standard"] } end
    local label = L["Standard"]
    for _, item in ipairs(items) do
        if item.value == current then label = item.label end
    end
    table.insert(items, { separator = true })
    for _, key in ipairs({ "profileExport", "profileImport" }) do
        local option = R.byKey[key] and R.byKey[key][1]
        if option and option.onClick then
            table.insert(items, { value = key, label = T(option.label) .. " …", onClick = function()
                local ok, err = pcall(option.onClick)
                if not ok then geterrorhandler()(err) end
            end })
        end
    end
    table.insert(items, { value = "page", label = L["Profile verwalten"], onClick = function() S.Navigate("stray", "Profile") end })
    return items, current, label, api
end

local function UpdateProfile()
    local drop = W.profileDrop
    if not drop then return end
    local items, current, label, api = ProfileMenu()
    drop:SetItems(items, current, function(value)
        if api and api.SetActive then
            local ok, err = pcall(api.SetActive, value)
            if not ok then geterrorhandler()(err) end
            Changed()
        end
    end)
    drop.text:SetText(L["Profil:"] .. "  |cff" .. (FOREVER and "e3c27a" or "ffffff") .. label .. "|r")
end

local function EnsureBuilt()
    if S.built then return end
    S.built = true
    CollectOptions()
    S.selected = R.pages[1] and R.pages[1].name
    BuildNav()
    -- Mindesthöhe kennt erst jetzt die Navigation: gespeicherte Größe nochmals prüfen
    UpdateResizeBounds()
    ApplySize(frame:GetWidth(), frame:GetHeight())
end

---------------------------------------------------------------------------
-- Fußzeile und Dialog
---------------------------------------------------------------------------

local dialog -- weiter unten angelegt

local function UpdateFooter()
    local n = CountChanges()
    local text
    if n > 0 then
        W.footDot:SetVertexColor(C.amber[1], C.amber[2], C.amber[3], 1)
        SetTextColor(W.footText, C.text)
        text = n == 1 and L["1 Änderung"] or L("%d Änderungen", n)
        if NeedsReload() then text = text .. " · " .. L["Übernehmen lädt neu"] end
    else
        W.footDot:SetVertexColor(C.faint[1], C.faint[2], C.faint[3], 1)
        SetTextColor(W.footText, C.grey)
        text = L["Keine Änderungen"]
    end
    W.footText:SetText(text)
    local combat = InCombat()
    W.discardButton:SetActive(n > 0)
    W.applyButton:SetActive(n > 0 and not combat)
    W.editButton:SetActive(not combat)
    if dialog and dialog:IsVisible() then dialog:Update(n) end
    return n
end

-- Übernehmen: neu laden, wenn nötig; sonst gilt der jetzige Stand als neuer Ausgangspunkt
local function Apply()
    if CountChanges() == 0 then return true end
    if NeedsReload() then
        if InCombat() then return false end
        ReloadUI()
        return true
    end
    TakeSnapshot()
    ns.Print(L["Änderungen übernommen."])
    if frame:IsShown() then Refresh() end
    return true
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------

-- Für Module: Fenster neu zeichnen, wenn sich ein Wert von außen geändert hat
function ns.RefreshConfig()
    if frame:IsShown() and Refresh then Refresh() end
end

local function UpdateNav(searching)
    for _, b in ipairs(navButtons) do
        local isSelected = b.page.name == S.selected and not searching
        b.isSelected = isSelected
        b.text:SetText(L[b.page.name])
        b.bg:SetColor(C.navSel)
        b.bg:SetShown(isSelected)
        b.bar:SetShown(isSelected)
        local ic = isSelected and (FOREVER and C.accentT or C.white) or C.grey
        b.icon:SetVertexColor(ic[1], ic[2], ic[3], 1)
        SetTextColor(b.text, isSelected and C.hi or C.navText)
    end
end

-- Reiterleiste füllen (bricht bei wenig Platz in eine zweite Reihe um); gibt die Höhe zurück
local function UpdateTabs(page, current)
    local bar = W.tabBar
    local width = (bar:GetWidth() or M.SCROLL_W)
    if width < 50 then width = M.SCROLL_W end
    local x, rows = 0, 1
    for i, tab in ipairs(page.tabs) do
        local b = W.tabs[i]
        if not b then
            b = CreateFrame("Button", nil, bar)
            b:SetHeight(M.TAB_H)
            b.fx = FX("Tab", b, false) -- Forever: Trapez-Reiter mit lila Oberkante (gewählt)
            b.text = Text(b, 14, C.grey)
            b.text:SetPoint("CENTER", 0, 1)
            if not b.fx then
                b.line = Line(b, C.accent, "ARTWORK")
                b.line:SetPoint("BOTTOMLEFT", 2, 0)
                b.line:SetPoint("BOTTOMRIGHT", -2, 0)
                b.line:SetHeight(2)
            end
            b:SetScript("OnEnter", function(self) if not self.isSelected then SetTextColor(self.text, C.text) end end)
            b:SetScript("OnLeave", function(self) if not self.isSelected then SetTextColor(self.text, C.grey) end end)
            b:SetScript("OnClick", function(self)
                S.selectedTabs[self.pageName] = self.index
                SetScroll(0)
                ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                Refresh()
            end)
            W.tabs[i] = b
        end
        b.pageName, b.index = page.name, i
        b.isSelected = i == current
        b.text:SetText(L[tab.name])
        SetTextColor(b.text, b.isSelected and C.hi or C.grey)
        if b.fx then b.fx:SetSelected(b.isSelected) else b.line:SetShown(b.isSelected) end
        local w = math.floor((b.text:GetStringWidth() or 40) + (b.fx and 38 or 26))
        if x > 0 and x + w > width then
            x = 0
            rows = rows + 1
        end
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -(rows - 1) * M.TAB_H)
        b:Show()
        x = x + w + (b.fx and 2 or 6)
    end
    for i = #page.tabs + 1, #W.tabs do W.tabs[i]:Hide() end
    local h = rows * M.TAB_H
    bar:SetHeight(h)
    return h
end

-- Optionen eines Reiters in Abschnitte teilen: ALLGEMEIN (Schalter, Auswahl, Knöpfe), ANORDNUNG
-- (Regler); option.group legt einen eigenen Abschnitt an
local function AddOptionItems(items, options, skip, skip2)
    local groups, order = {}, {}
    for _, option in ipairs(options) do
        if option ~= skip and option ~= skip2 then
            local g = option.group and T(option.group)
                or (option.type == "slider" and L["ANORDNUNG"] or L["ALLGEMEIN"])
            if not groups[g] then
                groups[g] = {}
                table.insert(order, g)
            end
            table.insert(groups[g], option)
        end
    end
    -- ALLGEMEIN zuerst
    for i, g in ipairs(order) do
        if g == L["ALLGEMEIN"] and i > 1 then
            table.remove(order, i)
            table.insert(order, 1, g)
            break
        end
    end
    for _, g in ipairs(order) do
        table.insert(items, { kind = "heading", text = Upper(g) })
        for _, option in ipairs(groups[g]) do
            table.insert(items, { kind = "option", option = option })
            local hint = ConflictText(option)
            if hint then table.insert(items, { kind = "hint", text = hint }) end
        end
    end
end

local function HomeItems(items)
    local quick = {
        { label = L["Bearbeitungsmodus"], enabled = not InCombat(),
            tip = L["Schließt dieses Fenster und blendet alle eingeschalteten stray-Anzeigen zum Verschieben ein."],
            onClick = function() if not InCombat() and ns.EnterEditMode then ns.EnterEditMode() end end },
    }
    table.insert(quick, { label = L["Profile"], tip = L["Profile exportieren und importieren."],
        onClick = function() S.Navigate("stray", "Profile") end })
    table.insert(items, { kind = "heading", text = L["SCHNELLZUGRIFF"] })
    table.insert(items, { kind = "quick", buttons = quick })

    -- Zuletzt geänderte Einstellungen (ns.db.recentChanges, neueste zuerst); Klick öffnet die Einstellung
    local recent = {}
    for _, key in ipairs(ns.db and ns.db.recentChanges or {}) do
        local option = R.byKey[key] and R.byKey[key][1]
        local tab = option and R.tabOf[option]
        local page = tab and R.pageOfTab[tab]
        if option and page and #recent < 5 then
            -- Regler haben in der Zeile keinen Platz für den Ort
            local sub = option.type ~= "slider" and (L[page.name] .. " · " .. L[tab.name]) or nil
            table.insert(recent, { kind = "option", option = option, sub = sub,
                nav = { page = page.name, tab = tab.name } })
        end
    end
    if #recent > 0 then
        table.insert(items, { kind = "heading", text = L["ZULETZT GEÄNDERT"] })
        for _, row in ipairs(recent) do table.insert(items, row) end
    end

    for _, group in ipairs(HOME) do
        local rows = {}
        for _, key in ipairs(group.keys) do
            local option = SwitchOption(key)
            local tab = option and R.tabOf[option]
            local page = tab and R.pageOfTab[tab]
            if option and page then
                -- Überschrift = Seite, Zeile zeigt den Reiter
                table.insert(rows, { kind = "option", option = option, sub = L[tab.name],
                    nav = { page = page.name, tab = tab.name } })
            end
        end
        if #rows > 0 then
            table.insert(items, { kind = "heading", text = Upper(L[group.label]) })
            for _, row in ipairs(rows) do table.insert(items, row) end
        end
    end
end

-- Alle Anzeigen: Knopf zum Bearbeitungsmodus, darunter jede verschiebbare Anzeige mit Ort und Zustand
local function DisplaysItems(items)
    table.insert(items, { kind = "quick", buttons = { {
        label = L["Bearbeitungsmodus starten"], enabled = not InCombat(),
        tip = L["Schließt dieses Fenster und blendet alle eingeschalteten stray-Anzeigen zum Verschieben ein."],
        onClick = function() if not InCombat() and ns.EnterEditMode then ns.EnterEditMode() end end,
    } } })
    local rows = {}
    for n, entry in ipairs(ns.movables or {}) do
        local mf = entry.frame
        if mf and mf.strayKey then
            local pageName, tabName, switchKey = MovableTab(entry.label)
            local page, tab, index = FindTab(pageName, tabName)
            -- Zustand: eigener Schalter, sonst Hauptschalter des Reiters, sonst ob die Anzeige gerade steht
            local option = switchKey and SwitchOption(switchKey) or (page and TabMaster(page, tab))
            local active
            if option then active = SafeGet(option) and true or false else active = mf:IsShown() and true or false end
            local order = 1000 + n
            if page then
                for pi, p in ipairs(R.pages) do
                    if p == page then order = pi * 100 + index break end
                end
            end
            table.insert(rows, { kind = "display", text = LabelText(entry.label), active = active, order = order, n = n,
                sub = page and (L[page.name] .. " · " .. L[tab.name]) or nil,
                nav = page and { page = page.name, tab = tab.name, key = mf.strayKey } or nil })
        end
    end
    table.sort(rows, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.n < b.n
    end)
    table.insert(items, { kind = "heading", text = L["ANZEIGEN"] })
    for _, row in ipairs(rows) do table.insert(items, row) end
end

function Refresh()
    if not ns.db or not S.built then return end
    local query = W.search:GetText()
    local searching = query ~= ""
    UpdateNav(searching)
    UpdateProfile()

    local items = {}
    local masterOption
    local top -- Oberkante des Scrollbereichs unter dem Kopf
    W.emptyText:SetText("")
    if searching then
        local blocks, count = SearchResults(query)
        W.title:SetText(L("„%s“", query))
        W.info:SetText(count == 0 and L["Nichts gefunden."]
            or (count == 1 and L["1 Option gefunden."] or L("%d Optionen gefunden.", count)))
        W.info:Show()
        W.tabBar:Hide()
        top = 80
        for _, block in ipairs(blocks) do
            local name = L[block.tab.name]
            if block.tab.name ~= block.page.name then name = L[block.page.name] .. " · " .. name end
            table.insert(items, { kind = "heading", text = Upper(name) })
            for _, option in ipairs(block.options) do
                table.insert(items, { kind = "option", option = option,
                    nav = nil })
                local hint = ConflictText(option)
                if hint then table.insert(items, { kind = "hint", text = hint }) end
            end
        end
        if count == 0 then
            W.emptyText:SetText(L["Versuch ein anderes Wort, z. B. „Taschen“, „aggro“ oder „xp“."])
        end
    else
        local page = FindPage(S.selected) or R.pages[1]
        W.title:SetText(page and L[page.name] or "")
        if not page or page.home then
            W.info:SetText(L["Alle Module auf einen Blick – Klick auf einen Namen öffnet seine Seite."])
            W.info:Show()
            W.tabBar:Hide()
            top = 80
            HomeItems(items)
        elseif page.displays then
            W.info:SetText(L["Alle verschiebbaren Anzeigen – Klick auf eine Zeile öffnet ihre Einstellung."])
            W.info:Show()
            W.tabBar:Hide()
            top = 80
            DisplaysItems(items)
        else
            W.info:Hide()
            local tab, index = CurrentTab(page)
            local h = UpdateTabs(page, index)
            W.tabBar:Show()
            top = 54 + h + 10
            masterOption = TabMaster(page, tab)
            local hint = ConflictText(masterOption)
            if hint then table.insert(items, { kind = "hint", text = hint }) end
            local inst = InstanceFor(page, tab)
            if inst then table.insert(items, { kind = "instance", inst = inst }) end
            AddOptionItems(items, tab.options, masterOption, inst and inst.option)
            -- POSITION für verschiebbare Anzeigen dieses Reiters
            local movables = MovablesFor(page, tab)
            if #movables > 0 and ns.GetMovableCenter then
                table.insert(items, { kind = "heading", text = L["POSITION"] })
                for _, entry in ipairs(movables) do
                    table.insert(items, { kind = "position", entry = entry, showName = #movables > 1 })
                end
            end
        end
    end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", M.CL, -top)
    scroll:SetPoint("BOTTOMRIGHT", -M.CR, M.FOOT_H + 6)

    -- Häkchen „Aktiv“
    W.active.option = masterOption
    if masterOption then
        W.active.label:SetText(L["Aktiv"])
        W.active:SetWidth(math.floor((W.active.label:GetStringWidth() or 30) + 30))
        W.active.check:SetState(SafeGet(masterOption) and true or false, OptionEnabled(masterOption))
        W.active:Show()
    else
        W.active:Hide()
    end

    Layout(items)
    W.emptyText:SetShown(#items == 0)
    UpdateFooter()
end

Build(function()
    W.active:SetScript("OnClick", function(self)
        local option = self.option
        if not option or not OptionEnabled(option) then return end
        local value = not SafeGet(option)
        ns.Sound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        -- Immer über die set-Funktionen der Optionen, damit die Module ihr Apply ausführen
        SetOptionValue(option, value)
    end)
    W.active:SetScript("OnEnter", function(self)
        local option = self.option
        if not option then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(T(option.label), 1, 1, 1)
        if option.tooltip then GameTooltip:AddLine(T(option.tooltip), ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true) end
        if not OptionEnabled(option) and option.disabledHint then
            GameTooltip:AddLine(T(option.disabledHint), 1, 0.3, 0.3, true)
        end
        GameTooltip:Show()
    end)
    W.active:SetScript("OnLeave", function() GameTooltip:Hide() end)
end)

---------------------------------------------------------------------------
-- Schließen mit Nachfrage
---------------------------------------------------------------------------

-- Esc: statt des Fensters steht ein unsichtbarer Fänger in UISpecialFrames. Versteckt Esc ihn,
-- entscheidet stray selbst: Menü zu, ohne Änderung schließen, sonst nachfragen; im Dialog = zurück.
local escCatcher = CreateFrame("Frame", "strayFrameEsc", UIParent)
escCatcher:SetSize(1, 1)
escCatcher:SetPoint("TOPLEFT")
escCatcher:Hide()
tinsert(UISpecialFrames, "strayFrameEsc")

local function CloseNow()
    S.snapshot = nil
    S.quietHide = true
    frame:Hide()
    S.quietHide = false
end

local function RequestClose()
    if not frame:IsShown() then return end
    if UpdateFooter() == 0 then
        CloseNow()
        return
    end
    dialog:Open()
end

escCatcher:SetScript("OnHide", function(self)
    if S.quietHide or self:IsShown() then return end -- selbst versteckt bzw. nur UIParent ausgeblendet
    if not frame:IsShown() then return end
    if W.menu:IsShown() then
        CloseMenu()
    elseif dialog:IsVisible() then
        dialog:Hide() -- Esc im Dialog = zurück ins Fenster
    else
        RequestClose()
    end
    -- Fänger wieder scharf machen, solange das Fenster offen ist
    C_Timer.After(0, function()
        if frame:IsShown() and not escCatcher:IsShown() then escCatcher:Show() end
    end)
end)

Build(function()
    W.close:SetScript("OnClick", function() RequestClose() end)
end)

-- Dialog in stray-Optik über dem Fenster
local shade = CreateFrame("Frame", nil, frame)
shade:SetAllPoints()
shade:SetFrameLevel(frame:GetFrameLevel() + 40)
shade:EnableMouse(true)
shade:EnableMouseWheel(true)
shade:SetScript("OnMouseWheel", function() end)
Build(function()
    RoundRect(shade, 12, { 0, 0, 0, 0.55 }, "BACKGROUND", nil, P) -- Forever: innerhalb des Rahmens
end)
shade:Hide()

dialog = CreateFrame("Frame", nil, shade)
dialog:SetSize(420, 190)
dialog:SetPoint("CENTER", frame, "CENTER", 0, 20)
dialog:SetFrameLevel(shade:GetFrameLevel() + 5)
dialog:EnableMouse(true)

Build(function()
    Boxed(dialog, 12, 8, true)
    dialog.title = Text(dialog, 16, C.hi)
    dialog.title:SetPoint("TOPLEFT", 20, -20)
    dialog.text = Text(dialog, 13, C.grey)
    dialog.text:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -10)
    dialog.text:SetWidth(380)
    dialog.text:SetWordWrap(true)
    dialog.text:SetJustifyV("TOP")
    dialog.apply = MakeButton(dialog, L["Übernehmen"], "primary")
    dialog.apply:SetPoint("BOTTOMRIGHT", -16, 16)
    dialog.discard = MakeButton(dialog, L["Verwerfen"], "dark")
    dialog.discard:SetPoint("RIGHT", dialog.apply, "LEFT", -8, 0)
    dialog.back = MakeButton(dialog, L["Zurück"], "dark")
    dialog.back:SetPoint("RIGHT", dialog.discard, "LEFT", -8, 0)
end)

function dialog:Update(n)
    local text = (n == 1 and L["Du hast 1 Einstellung geändert."] or L("Du hast %d Einstellungen geändert.", n))
        .. " " .. L["„Übernehmen“ behält alles (und lädt neu, wenn nötig), „Verwerfen“ stellt den Stand beim Öffnen wieder her."]
    local blocked = InCombat() and NeedsReload()
    if InCombat() then
        text = text .. "\n" .. L["Im Kampf: Leisten und Rahmen werden erst nach dem Kampf zurückgesetzt."]
    end
    self.text:SetText(text)
    self.apply:SetActive(not blocked)
end

function dialog:Open()
    GameTooltip:Hide()
    W.preview:Hide()
    CloseMenu()
    W.search:ClearFocus()
    shade:Show()
    self:Show()
    self:Update(CountChanges())
end

dialog:SetScript("OnHide", function() shade:Hide() end)
shade:SetScript("OnHide", function() dialog:Hide() end)

Build(function()
dialog.back:SetScript("OnClick", function() dialog:Hide() end)
dialog.discard:SetScript("OnClick", function()
    Revert()
    dialog:Hide()
    CloseNow()
end)
dialog.apply:SetScript("OnClick", function(self)
    if self.inactive then return end
    if Apply() then
        dialog:Hide()
        CloseNow()
    end
end)
ButtonTooltip(dialog.apply, "Übernehmen", function()
    if InCombat() and NeedsReload() then return L["Im Kampf nicht möglich."] end
    return NeedsReload() and L["Lädt die Oberfläche neu, damit alle Änderungen sicher übernommen werden."]
        or L["Behält alle Änderungen; ein Neuladen ist nicht nötig."]
end)

-- Fußzeilen-Knöpfe
W.discardButton:SetScript("OnClick", function(self)
    if self.inactive then return end
    ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    Revert()
    Refresh()
end)
ButtonTooltip(W.discardButton, "Verwerfen", "Setzt alle Einstellungen auf den Stand beim Öffnen des Fensters zurück und wendet sie sofort wieder an.")

W.applyButton:SetScript("OnClick", function(self)
    if self.inactive then return end
    ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    Apply()
end)
ButtonTooltip(W.applyButton, "Übernehmen", function()
    if CountChanges() == 0 then return L["Keine Änderungen."] end
    if InCombat() and NeedsReload() then return L["Im Kampf nicht möglich."] end
    return NeedsReload() and L["Lädt die Oberfläche neu, damit alle Änderungen sicher übernommen werden."]
        or L["Behält alle Änderungen; ein Neuladen ist nicht nötig."]
end)

W.editButton:SetScript("OnClick", function(self)
    if self.inactive or InCombat() then return end
    -- Fenster schließt sich für den Bearbeitungsmodus; ungespeicherte Änderungen bleiben gezählt
    if ns.EnterEditMode then ns.EnterEditMode() end
end)
ButtonTooltip(W.editButton, "Bearbeitungsmodus", "Schließt dieses Fenster und blendet alle eingeschalteten stray-Anzeigen zum Verschieben ein. „Fertig“ oder Esc beendet den Modus. Auch per /stray edit.")
end)

ns.On("PLAYER_REGEN_DISABLED", function() if frame:IsShown() then UpdateFooter() end end)
ns.On("PLAYER_REGEN_ENABLED", function() if frame:IsShown() then UpdateFooter() end end)

---------------------------------------------------------------------------
-- Auswahl im Bearbeitungsmodus → Seite der Anzeige
---------------------------------------------------------------------------

if ns.OnEditSelect then
    ns.OnEditSelect(function(key)
        if key then S.editKey = key end
        if frame:IsShown() and Refresh then Refresh() end
    end)
end

-- Beim Öffnen: zuletzt im Spiel gewählte Anzeige (einmal) auf ihrer Seite zeigen
local function JumpToEditSelection()
    local key = S.editKey
    if not key or key == S.jumpedKey then return end
    S.jumpedKey = key
    for _, entry in ipairs(ns.movables or {}) do
        if entry.frame and entry.frame.strayKey == key then
            local pageName, tabName = MovableTab(entry.label)
            local page, tab, index = FindTab(pageName, tabName)
            if page then
                S.selected = page.name
                S.selectedTabs[page.name] = index
                local inst = InstanceFor(page, tab)
                if inst and inst.set then
                    for _, e in ipairs(InstanceList(inst)) do
                        if InstanceMatches(e, key) then pcall(inst.set, e.id) break end
                    end
                end
            end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Öffnen und Schließen
---------------------------------------------------------------------------

-- Zähler und Positionsfelder regelmäßig nachziehen (z. B. Anzeige per Shift-Ziehen verschoben)
do
    local timer = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        timer = timer + elapsed
        if timer < 0.5 then return end
        timer = 0
        UpdateFooter()
        for i = 1, used.position or 0 do
            local row = pools.position[i]
            if row and row:IsShown() then row:Refresh() end
        end
    end)
end

frame:SetScript("OnShow", function()
    EnsureBuilt()
    UpdateResizeBounds()
    ApplySize(frame:GetWidth(), frame:GetHeight())
    -- Fenster und Bearbeitungsmodus nicht gleichzeitig
    if ns.editMode and ns.ExitEditMode then ns.ExitEditMode() end
    -- Schnappschuss nur, wenn keiner mehr offen ist (z. B. nach dem Bearbeitungsmodus behalten)
    if not S.snapshot then TakeSnapshot() end
    JumpToEditSelection()
    ns.Sound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    shade:Hide()
    escCatcher:Show()
    Refresh()
    ns.NotifyConfig()
end)

frame:SetScript("OnHide", function()
    ns.Sound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    S.quietHide = true
    escCatcher:Hide()
    S.quietHide = false
    shade:Hide()
    CloseMenu()
    W.search:ClearFocus()
    W.preview:Hide()
    GameTooltip:Hide()
    -- Nicht über stray geschlossen (z. B. Bearbeitungsmodus): Schnappschuss bleibt, damit die
    -- Änderungen beim nächsten Öffnen weiter zählen. Nur leere Schnappschüsse verwerfen.
    if S.snapshot and CountChanges() == 0 then S.snapshot = nil end
    ns.NotifyConfig()
end)

-- Falls Einstellungen woanders geändert werden (z. B. Blizzard-Optionen)
ns.On("CVAR_UPDATE", function()
    if frame:IsShown() then Refresh() end
end)

-- Feste Texte, die beim Laden der Datei gesetzt wurden: nach ns.SetLanguage in der gewählten Sprache
local function SetStaticTexts()
    W.placeholder:SetText(L["Einstellungen durchsuchen …"])
    W.editButton:SetLabel(L["Bearbeitungsmodus"])
    W.applyButton:SetLabel(L["Übernehmen"], 100)
    W.discardButton:SetLabel(L["Verwerfen"], 90)
    dialog.title:SetText(L["Ungespeicherte Änderungen"])
    dialog.apply:SetLabel(L["Übernehmen"])
    dialog.discard:SetLabel(L["Verwerfen"])
    dialog.back:SetLabel(L["Zurück"])
end

-- Größe geändert: Inhalt neu anordnen, höchstens einmal je Bild
do
    local layoutPending = false
    frame:SetScript("OnSizeChanged", function()
        if layoutPending then return end
        layoutPending = true
        C_Timer.After(0, function()
            layoutPending = false
            if frame:IsShown() and Refresh then Refresh() end
        end)
    end)
end

function ns.OnLoaded()
    -- Stil festlegen (ns.db ist jetzt da) und das Fenster aufbauen
    SetupStyle()
    for _, fn in ipairs(BUILD) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
    SetStaticTexts()
    W.version:SetText((ns.GetVersion() or ""):upper())
    if type(ns.db.uiSize) == "table" then
        ApplySize(ns.db.uiSize[1], ns.db.uiSize[2])
    end
    if ns.db.point then
        frame:ClearAllPoints()
        frame:SetPoint(ns.db.point[1], UIParent, ns.db.point[2], ns.db.point[3], ns.db.point[4])
    end
end

---------------------------------------------------------------------------
-- Slash-Befehl
---------------------------------------------------------------------------

SLASH_STRAY1 = "/stray"
SlashCmdList["STRAY"] = function(msg)
    if not ns.db then
        ns.Print(L["noch nicht geladen."])
        return
    end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    -- Unterbefehle anderer Module (ns.slashCommands[befehl] = fn)
    if type(ns.slashCommands) == "table" and type(ns.slashCommands[msg]) == "function" then
        local ok, err = pcall(ns.slashCommands[msg])
        if not ok then geterrorhandler()(err) end
        return
    end
    if (msg == "alts" or msg == "twinks") and ns.ToggleAlts then
        ns.ToggleAlts()
        return
    end
    if (msg == "edit" or msg == "bearbeiten") and ns.EnterEditMode then
        ns.EnterEditMode()
        return
    end
    if frame:IsShown() then
        if dialog:IsVisible() then dialog:Hide() else RequestClose() end
    else
        frame:Show()
    end
end
