-- stray – Einstellungsfenster „Zentrale“
-- Flaches, dunkles Fenster mit ruhigem Lila: links Logo, Suche und Seiten in Gruppen (mit eigenen
-- Symbolen und Zähler an/gesamt), rechts Kopf mit Hauptschalter, Bereiche als Karten in zwei Spalten
-- und eine Fußzeile mit ungespeicherten Änderungen, Verwerfen, Bearbeitungsmodus und Neu laden.
-- Die Optionen kommen aus dem Register in stray.lua (ns.AddOption); die Spaltennummer dort stammt
-- aus dem alten Fenster und wird hier nicht gebraucht.
-- Beim Öffnen merkt sich das Fenster eine Kopie der Einstellungen. Beim Schließen mit Änderungen
-- fragt ein Dialog: Neu laden (behalten) oder Verwerfen (Stand beim Öffnen wiederherstellen).
-- Symbole in media/icons: Tabler Icons (MIT-Lizenz, tabler.io).

local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Maße und Farben
---------------------------------------------------------------------------

local WIDTH, HEIGHT = 900, 570
local SIDE_W = 210
local HEAD_H = 96          -- Kopfbereich rechts
local FOOT_H = 60          -- Fußzeile rechts
local SCROLL_W = 644       -- Breite des Inhalts (zwei Spalten)
local COL_GAP = 12
local COL_W = (SCROLL_W - COL_GAP) / 2
local CARD_HEAD = 36       -- Kartenkopf
local CARD_PAD = 6         -- Luft unter der letzten Zeile
local PAD = 12             -- Innenabstand in Karten
local WHEEL_STEP = 40

local MEDIA = "Interface\\AddOns\\stray\\media\\"
local ICONS = MEDIA .. "icons\\"
local ROUND = MEDIA .. "round"
local FONT = "Fonts\\ARIALN.TTF"

local C = {
    window   = { 0.078, 0.078, 0.098, 0.98 },  -- #141419
    card     = { 0.094, 0.094, 0.118, 1 },     -- #18181e
    hover    = { 0.122, 0.122, 0.153, 1 },     -- #1f1f27
    line     = { 0.149, 0.149, 0.184, 1 },     -- #26262f
    accent   = { 0.545, 0.486, 0.965, 1 },     -- #8b7cf6
    accentHi = { 0.612, 0.557, 0.976, 1 },
    text     = { 0.902, 0.902, 0.925, 1 },     -- #e6e6ec
    grey     = { 0.545, 0.545, 0.600, 1 },     -- #8b8b99
    faint    = { 0.369, 0.369, 0.420, 1 },     -- #5e5e6b
    off      = { 0.169, 0.169, 0.208, 1 },     -- Schalter aus
    red      = { 0.878, 0.478, 0.478, 1 },
    amber    = { 0.961, 0.682, 0.290, 1 },
    white    = { 1, 1, 1, 1 },
}

-- Seiten in Gruppen; die Bereiche der Module (ns.AddOption) werden auf einer Seite zu Karten
local GROUPS = {
    { label = "ALLTAG", pages = {
        { name = "Komfort", icon = "coins", sections = { "Beute", "Händler", "NPCs", "Filmsequenzen", "Chat" } },
        { name = "Taschen", icon = "backpack", sections = { "Taschen", "Vorrat" } },
        { name = "Quests", icon = "exclamation-circle", sections = { "Quests" } },
    } },
    { label = "KAMPF & GRUPPE", pages = {
        { name = "Kampf", icon = "swords", sections = { "Bedrohung", "DMG-Meter", "Kampfhilfen", "Zaubern" } },
        { name = "Aktionsleisten", icon = "layout-grid", sections = { "Aktionsleisten", "Abklingzeiten" } },
        { name = "Gruppe", icon = "users-group", sections = { "Gruppenrahmen" } },
    } },
    { label = "OBERFLÄCHE", pages = {
        { name = "Oberfläche", icon = "map-2", sections = { "stray-Oberfläche", "Kamera & Karte", "Erfahrung", "Interface" } },
        { name = "Sozial", icon = "message-circle", sections = { "Sozial", "Charaktere" } },
        { name = "System", icon = "adjustments", sections = { "Bearbeiten", "Profile" } },
    } },
}

local PAGE_SUBTITLES = {
    ["Komfort"] = "Beute, Händler, Post und Lehrer, Filmsequenzen und Chat.",
    ["Taschen"] = "Taschen, Taschenfenster und Vorrat.",
    ["Quests"] = "Quests annehmen, abgeben und im Blick behalten.",
    ["Kampf"] = "Bedrohung, DMG-Meter, Kampfhilfen und Zaubern.",
    ["Aktionsleisten"] = "Eigene Leisten statt Blizzard – Größe, Raster, leere Plätze, Rang-Prüfung.",
    ["Gruppe"] = "Deine 5er-Gruppe als Heiler-Rahmen, mit Begleitern.",
    ["Oberfläche"] = "stray-Oberfläche, Kamera, Karte, Minimap, Erfahrung und Interface.",
    ["Sozial"] = "Mitspieler, Einladungen und deine Charaktere.",
    ["System"] = "Bearbeitungsmodus und Profile.",
    ["Weitere"] = "Optionen ohne feste Seite.",
}

-- Hauptschalter „Modul aktiv“ im Kopf (nur wo eindeutig); die Option fehlt dann in den Karten
local MASTER = {
    ["Aktionsleisten"] = "abEnabled",
    ["Oberfläche"] = "strayUI",
    ["Gruppe"] = "partyFrames",
}

-- Beim Einschalten eines Hauptschalters zuerst auch diesen Schalter einschalten
-- (eigene Aktionsleisten gehören zur stray-Oberfläche)
local MASTER_REQUIRES = {
    abEnabled = "strayUI",
}

---------------------------------------------------------------------------
-- Stichwörter für die Suche (deutsch + englisch), zusätzlich zu option.keywords
---------------------------------------------------------------------------

local KEYWORDS = {
    -- Komfort
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
    -- Taschen
    deleteFill = { "delete", "löschen", "zerstören", "destroy" },
    deleteNoConfirm = { "delete", "löschen", "zerstören", "destroy", "confirm", "nachfrage" },
    questItemMarks = { "quest", "items", "gegenstände", "marker", "markieren" },
    freeSlots = { "bags", "slots", "plätze", "frei", "free", "inventar", "inventory" },
    bagTriage = { "bags", "voll", "full", "inventar", "inventory", "aufräumen" },
    bagWindow = { "bags", "bag", "inventar", "inventory", "rucksack", "sortieren", "sort" },
    bagColumns = { "bags", "spalten", "columns", "inventar", "breite" },
    bagHeightReset = { "bags", "höhe", "height", "inventar" },
    supplies = { "supplies", "vorrat", "erinnerung", "reminder", "reagenzien" },
    supReagents = { "reagenzien", "reagents", "vorrat" },
    supAmmo = { "ammo", "munition", "pfeile", "arrows", "kugeln", "bullets", "jäger", "hunter" },
    supFood = { "food", "drink", "essen", "trinken", "wasser", "water" },
    supBuffs = { "buff", "buffs", "stärkung" },
    supThreshold = { "schwelle", "threshold", "anzahl", "stück" },
    -- Quests
    gossipSkip = { "gossip", "dialog", "npc", "gespräch", "skip" },
    questAccept = { "quest", "accept", "annehmen", "auto" },
    questTurnIn = { "quest", "turn in", "abgeben", "auto", "complete" },
    questRewardMark = { "reward", "belohnung", "quest", "gold", "wert" },
    questMobMarks = { "quest", "mobs", "gegner", "marker", "nameplates" },
    -- Kampf
    threatList = { "aggro", "threat", "liste", "list", "tank" },
    threatPlates = { "aggro", "threat", "nameplates", "namensplaketten", "rahmen" },
    threatPercent = { "aggro", "threat", "nameplates", "prozent", "percent" },
    threatTankWarn = { "aggro", "threat", "tank", "warnung", "warning" },
    threatAggroWarn = { "aggro", "threat", "warnung", "warning" },
    dmShow = { "damage", "dps", "meter", "schaden", "heal", "hps", "heilung", "recount", "details" },
    dm2Show = { "damage", "dps", "meter", "zweites", "second", "fenster", "window" },
    dmAutoReset = { "damage", "meter", "reset", "zurücksetzen", "instanz", "dungeon" },
    dangerWarn = { "danger", "gefahr", "elite", "level", "warnung", "warning" },
    dangerLevels = { "danger", "gefahr", "level", "stufen" },
    swingTimer = { "swing", "timer", "nahkampf", "melee", "auto attack", "autoangriff" },
    swingWidth = { "swing", "breite", "width" },
    swingRanged = { "swing", "ranged", "fernkampf", "bogen", "bow", "auto shot", "jäger" },
    mouseoverCast = { "mouseover", "heal", "heilen", "cast", "zaubern", "spell" },
    abRankCheck = { "rank", "rang", "zauber", "spell", "veraltet" },
    -- Aktionsleisten
    abEnabled = { "actionbar", "actionbars", "bars", "leisten", "buttons", "knöpfe" },
    abKeybinds = { "keybind", "keybinds", "hotkey", "tasten", "binding", "kürzel" },
    abSpacing = { "abstand", "spacing", "actionbar" },
    abShowEmpty = { "empty", "leer", "grid", "raster", "plätze" },
    abEmptyAlpha = { "empty", "leer", "alpha", "deckkraft", "transparenz" },
    abEdit = { "actionbar", "leiste" },
    abShowSel = { "actionbar", "leiste", "anzeigen", "show" },
    abSizeSel = { "actionbar", "größe", "size", "scale" },
    abColsSel = { "actionbar", "reihe", "row", "columns", "spalten" },
    cdManager = { "cooldown", "cooldowns", "cd", "abklingzeit", "timer" },
    cdSize = { "cooldown", "cd", "größe", "size", "symbol" },
    -- Gruppe
    partyFrames = { "party", "group", "gruppe", "raid", "heal", "heilen", "heiler", "healer", "frames", "rahmen" },
    partyHideBlizzard = { "party", "blizzard", "hide", "ausblenden" },
    partyWidth = { "party", "breite", "width", "size" },
    partyHeight = { "party", "höhe", "height", "size" },
    partySpacing = { "party", "abstand", "spacing" },
    partyBrightness = { "party", "helligkeit", "brightness", "farbe" },
    -- Oberfläche
    strayUI = { "ui", "oberfläche", "interface", "hud", "blizzard" },
    cameraMax = { "camera", "kamera", "zoom", "distance", "entfernung" },
    minimapWheel = { "minimap", "zoom", "mausrad", "mousewheel", "scroll" },
    minimapButton = { "minimap", "button", "icon", "knopf" },
    squareMinimap = { "minimap", "square", "eckig", "karte" },
    squareMinimapSize = { "minimap", "größe", "size" },
    minimapMiddleMenu = { "minimap", "menü", "menu", "mittelklick", "middle click" },
    flightBar = { "flight", "flug", "taxi", "greif", "timer", "flugmeister" },
    hudMinimapColumn = { "minimap", "buttons", "knöpfe", "addons" },
    hudClock = { "clock", "uhr", "uhrzeit", "fps", "zeit", "time", "latenz", "latency", "ping" },
    hudXPBar = { "xp", "exp", "ep", "erfahrung", "experience", "level", "stufe" },
    questXPBar = { "xp", "exp", "ep", "quest", "erfahrung", "experience" },
    xpTracker = { "xp", "exp", "ep", "erfahrung", "tracker", "ep/h", "xp/h", "level", "stufe", "spielzeit", "played" },
    xpTrackerTable = { "xp", "exp", "ep", "tabelle", "table", "tracker", "verlauf", "history" },
    bottomBar = { "bags", "taschen", "taschenleiste", "bag bar", "menü", "menu", "unten" },
    xpBarWidth = { "xp", "ep", "erfahrung", "breite", "width" },
    xpBarHeight = { "xp", "ep", "erfahrung", "höhe", "height" },
    xpBarFontSize = { "xp", "ep", "erfahrung", "schrift", "font", "größe" },
    bottomMicroButtons = { "menu", "menü", "micro", "mikromenü", "knöpfe" },
    bottomBarSize = { "bags", "taschen", "taschenleiste", "größe", "size" },
    hideErrors = { "error", "errors", "fehler", "meldungen", "spam", "rote schrift" },
    durability = { "durability", "haltbarkeit", "repair", "reparieren", "rüstung" },
    rollsMove = { "roll", "rolls", "loot", "würfeln", "need", "greed", "bedarf", "gier" },
    -- Sozial
    declineDuels = { "duel", "duell", "ablehnen" },
    acceptRes = { "res", "resurrect", "wiederbeleben", "wiederbelebung", "rez" },
    acceptSummon = { "summon", "beschwörung", "portal", "hexenmeister" },
    inviteAcceptFriends = { "invite", "einladung", "gruppe", "friends", "freunde", "gilde", "guild" },
    inviteDeclineStrangers = { "invite", "einladung", "fremde", "strangers", "spam" },
    playerNotes = { "notes", "notiz", "notizen", "spieler", "player" },
    alts = { "alts", "twinks", "charaktere", "characters", "gold" },
    altsOpen = { "alts", "twinks", "übersicht", "overview" },
    accountCVars = { "cvar", "account", "einstellungen", "settings", "alle charaktere" },
    -- System
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
    ["Vorrat"] = { "supplies", "reagents", "reagenzien" },
    ["Quests"] = { "quest", "quests" },
    ["Bedrohung"] = { "aggro", "threat" },
    ["DMG-Meter"] = { "dps", "damage", "meter", "schaden", "heal", "heilung" },
    ["Kampfhilfen"] = { "combat", "kampf" },
    ["Zaubern"] = { "cast", "spell", "zauber" },
    ["Aktionsleisten"] = { "actionbar", "actionbars", "bars", "leisten" },
    ["Abklingzeiten"] = { "cooldown", "cd" },
    ["Gruppenrahmen"] = { "party", "group", "heal", "heilen", "rahmen", "frames", "pet", "begleiter" },
    ["stray-Oberfläche"] = { "ui", "hud", "oberfläche", "interface" },
    ["Kamera & Karte"] = { "camera", "kamera", "minimap", "map", "karte" },
    ["Leisten & Minimap"] = { "minimap", "hud" },
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
    fs:SetFont(FONT, size, "")
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

-- Abgerundetes Rechteck aus 7 Texturen: vier Viertelkreise als Ecken, Mitte und zwei Seitenstreifen.
-- Gibt ein Objekt mit SetColor(c) und SetShown(b) zurück.
local function RoundRect(parent, radius, c, layer, sub, inset)
    inset = inset or 0
    local rr = { parts = {} }
    local function Part(isRound)
        local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        if isRound then t:SetTexture(ROUND) else t:SetColorTexture(1, 1, 1, 1) end
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

-- Fläche mit 1-px-Rand: äußeres Rechteck in Linienfarbe, inneres in Füllfarbe
local function Panel(frame, radius, fill, border, layer)
    local outer = RoundRect(frame, radius, border or C.line, layer, 0)
    local inner = RoundRect(frame, radius - 1, fill, layer, 1, 1)
    return inner, outer
end

-- Flacher Knopf mit runden Ecken; style "primary" (lila) oder "dark"
local function MakeButton(parent, label, style, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height or 30)
    b.style = style or "dark"
    b.fill, b.border = Panel(b, 6, b.style == "primary" and C.accent or C.hover,
        b.style == "primary" and C.accent or C.line, "BACKGROUND")
    b.text = Text(b, 13, b.style == "primary" and C.white or C.text)
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
        if self.inactive then return end
        self.fill:SetColor(self.style == "primary" and C.accentHi or C.line)
    end)
    b:SetScript("OnLeave", function(self)
        self.fill:SetColor(self.style == "primary" and C.accent or C.hover)
        GameTooltip:Hide()
    end)
    b:SetLabel(label or "")
    return b
end

-- Tooltip an einem Knopf zusätzlich zur Hover-Farbe
local function ButtonTooltip(b, title, body)
    local onEnter = b:GetScript("OnEnter")
    b:SetScript("OnEnter", function(self)
        onEnter(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
        local text = type(body) == "function" and body() or body
        if text then GameTooltip:AddLine(text, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true) end
        GameTooltip:Show()
    end)
end

-- Schalter als Pille mit Kugel
local function MakeSwitch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(32, 18)
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

-- Kurzbeschreibung: erster Satz des Tooltips (Abkürzungen wie „z. B.“ überspringen)
local function ShortDesc(option)
    if option.desc then return option.desc end
    local text = (option.tooltip or ""):match("^[^\n]*") or ""
    local start = 1
    while true do
        local pos = text:find("[%.!%?] ", start)
        if not pos then return text end
        local before = text:sub(math.max(1, pos - 2), pos - 1)
        local abbreviation = before:match("^[%s%.]%a$") or before:match("^%a$")
        if pos > 25 and not abbreviation then return text:sub(1, pos) end
        start = pos + 1
    end
end

-- Kleinbuchstaben inklusive Umlaute (string.lower kennt nur ASCII)
local function Lower(s)
    s = tostring(s or ""):lower()
    s = s:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü")
    return s
end

local function FormatValue(option, value)
    if option.format then
        local ok, text = pcall(option.format, value)
        if ok and text then return tostring(text) end
    end
    if type(value) == "number" and (option.step or 1) < 1 then
        return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
    end
    return tostring(value)
end

---------------------------------------------------------------------------
-- Grundgerüst
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "strayFrame", UIParent)
frame:SetSize(WIDTH, HEIGHT)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

Panel(frame, 12, C.window, C.line, "BACKGROUND")

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.point = { point, relPoint, x, y }
end)

-- Trennlinie zwischen Navigation und Inhalt
local sideLine = Line(frame, C.line)
sideLine:SetPoint("TOPLEFT", SIDE_W, -1)
sideLine:SetPoint("BOTTOMLEFT", SIDE_W, 1)
sideLine:SetWidth(1)

---------------------------------------------------------------------------
-- Navigation links: Logo, Suche, Seiten
---------------------------------------------------------------------------

local side = CreateFrame("Frame", nil, frame)
side:SetPoint("TOPLEFT", 0, 0)
side:SetPoint("BOTTOMLEFT", 0, 0)
side:SetWidth(SIDE_W)

local logoTile = CreateFrame("Frame", nil, side)
logoTile:SetSize(30, 30)
logoTile:SetPoint("TOPLEFT", 16, -18)
RoundRect(logoTile, 8, C.accent, "BACKGROUND")
local logoS = Text(logoTile, 19, C.white)
logoS:SetPoint("CENTER", 0, 1)
logoS:SetText("s")

local logoName = Text(side, 17, C.white)
logoName:SetPoint("TOPLEFT", logoTile, "TOPRIGHT", 10, 1)
logoName:SetText("stray")

local versionText = Text(side, 10, C.faint)
versionText:SetPoint("TOPLEFT", logoName, "BOTTOMLEFT", 0, -2)

-- Suchfeld
local search = CreateFrame("EditBox", nil, side)
search:SetSize(SIDE_W - 28, 30)
search:SetPoint("TOPLEFT", 14, -62)
search:SetAutoFocus(false)
search:SetFont(FONT, 13, "")
search:SetTextColor(C.text[1], C.text[2], C.text[3])
search:SetTextInsets(30, 8, 0, 0)
local searchFill = Panel(search, 7, C.card, C.line, "BACKGROUND")
local searchIcon = search:CreateTexture(nil, "ARTWORK")
searchIcon:SetSize(14, 14)
searchIcon:SetPoint("LEFT", 10, 0)
searchIcon:SetTexture(ICONS .. "search")
searchIcon:SetVertexColor(C.grey[1], C.grey[2], C.grey[3], 1)
local placeholder = Text(search, 13, C.faint)
placeholder:SetPoint("LEFT", 30, 0)
placeholder:SetText(L["Suchen …"])
search:SetScript("OnEditFocusGained", function() searchFill:SetColor(C.hover) end)
search:SetScript("OnEditFocusLost", function() searchFill:SetColor(C.card) end)

---------------------------------------------------------------------------
-- Inhalt rechts: Kopf
---------------------------------------------------------------------------

local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", SIDE_W + 1, 0)
content:SetPoint("BOTTOMRIGHT", 0, 0)

local groupLine = Text(content, 10, C.accent)
groupLine:SetPoint("TOPLEFT", 22, -22)

local title = Text(content, 24, C.white)
title:SetPoint("TOPLEFT", groupLine, "BOTTOMLEFT", 0, -6)

local subtitle = Text(content, 12, C.grey)
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
subtitle:SetPoint("RIGHT", content, "RIGHT", -180, 0)
subtitle:SetWordWrap(false)

local headLine = Line(content, C.line)
headLine:SetPoint("TOPLEFT", 0, -HEAD_H)
headLine:SetPoint("TOPRIGHT", -1, -HEAD_H)
headLine:SetHeight(1)

-- Schließen oben rechts
local close = CreateFrame("Button", nil, content)
close:SetSize(22, 22)
close:SetPoint("TOPRIGHT", -10, -10)
local closeHover = RoundRect(close, 6, C.hover, "BACKGROUND")
closeHover:SetShown(false)
local closeIcon = close:CreateTexture(nil, "ARTWORK")
closeIcon:SetSize(14, 14)
closeIcon:SetPoint("CENTER")
closeIcon:SetTexture(ICONS .. "x")
closeIcon:SetVertexColor(C.grey[1], C.grey[2], C.grey[3], 1)
close:SetScript("OnEnter", function()
    closeHover:SetShown(true)
    closeIcon:SetVertexColor(1, 1, 1, 1)
end)
close:SetScript("OnLeave", function()
    closeHover:SetShown(false)
    closeIcon:SetVertexColor(C.grey[1], C.grey[2], C.grey[3], 1)
end)

-- Hauptschalter „Modul aktiv“
local master = CreateFrame("Frame", nil, content)
master:SetSize(130, 22)
master:SetPoint("TOPRIGHT", -42, -44)
local masterSwitch = MakeSwitch(master)
masterSwitch:SetPoint("RIGHT")
local masterLabel = Text(master, 13, C.grey)
masterLabel:SetPoint("RIGHT", masterSwitch, "LEFT", -10, 0)
masterLabel:SetText(L["Modul aktiv"])
master:Hide()

---------------------------------------------------------------------------
-- Inhalt rechts: scrollbarer Bereich mit Karten
---------------------------------------------------------------------------

local scroll = CreateFrame("ScrollFrame", nil, content)
scroll:SetPoint("TOPLEFT", 18, -(HEAD_H + 14))
scroll:SetPoint("BOTTOMRIGHT", -26, FOOT_H + 10)
scroll:EnableMouseWheel(true)

local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(SCROLL_W, 10)
scroll:SetScrollChild(scrollChild)

-- Scrollbalken: Mausrad, Daumen ziehen oder in die Spur klicken
local scrollTrack = CreateFrame("Button", nil, content)
scrollTrack:SetPoint("TOPRIGHT", -8, -(HEAD_H + 14))
scrollTrack:SetPoint("BOTTOMRIGHT", -8, FOOT_H + 10)
scrollTrack:SetWidth(12)
scrollTrack:EnableMouseWheel(true)
local trackLine = scrollTrack:CreateTexture(nil, "ARTWORK")
trackLine:SetPoint("TOP")
trackLine:SetPoint("BOTTOM")
trackLine:SetWidth(4)
trackLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)

local scrollThumb = CreateFrame("Button", nil, scrollTrack)
scrollThumb:SetWidth(12)
scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 2)
local thumbLine = scrollThumb:CreateTexture(nil, "OVERLAY")
thumbLine:SetPoint("TOP")
thumbLine:SetPoint("BOTTOM")
thumbLine:SetWidth(4)
thumbLine:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
scrollThumb:SetScript("OnEnter", function() thumbLine:SetWidth(6) end)
scrollThumb:SetScript("OnLeave", function(self) if not self.dragging then thumbLine:SetWidth(4) end end)

local function MaxScroll()
    return math.max(0, (scrollChild:GetHeight() or 0) - (scroll:GetHeight() or 0))
end

local function UpdateScrollBar()
    local view = scroll:GetHeight() or 0
    local total = scrollChild:GetHeight() or 0
    if view <= 0 or total <= view + 1 then
        scrollTrack:Hide()
        return
    end
    local thumbH = math.max(24, view * view / total)
    local maxScroll = total - view
    local offset = (scroll:GetVerticalScroll() or 0) / maxScroll * (view - thumbH)
    scrollThumb:ClearAllPoints()
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -offset)
    scrollThumb:SetHeight(thumbH)
    scrollTrack:Show()
end

local preview -- weiter unten angelegt

local function SetScroll(value)
    scroll:SetVerticalScroll(math.max(0, math.min(MaxScroll(), value)))
    if preview then preview:Hide() end
    UpdateScrollBar()
end

scroll:SetScript("OnMouseWheel", function(self, delta)
    SetScroll(self:GetVerticalScroll() - delta * WHEEL_STEP)
end)
scrollTrack:SetScript("OnMouseWheel", function(_, delta)
    SetScroll(scroll:GetVerticalScroll() - delta * WHEEL_STEP)
end)

-- Cursor-Höhe in Fensterkoordinaten
local function CursorY()
    local _, y = GetCursorPosition()
    return y / (scrollTrack:GetEffectiveScale() or 1)
end

-- Daumen ziehen: Mausbewegung in Scrollweg umrechnen
scrollThumb:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    self.dragging = true
    self.startY = CursorY()
    self.startScroll = scroll:GetVerticalScroll() or 0
    thumbLine:SetWidth(6)
    self:SetScript("OnUpdate", function(thumb)
        local free = (scrollTrack:GetHeight() or 0) - (thumb:GetHeight() or 0)
        if free <= 0 then return end
        local moved = thumb.startY - CursorY()
        SetScroll(thumb.startScroll + moved / free * MaxScroll())
    end)
end)
scrollThumb:SetScript("OnMouseUp", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    if not self:IsMouseOver() then thumbLine:SetWidth(4) end
end)
scrollThumb:SetScript("OnHide", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
end)

-- Klick in die Spur: Daumen springt dorthin
scrollTrack:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local top = self:GetTop()
    local free = (self:GetHeight() or 0) - (scrollThumb:GetHeight() or 0)
    if not top or free <= 0 then return end
    local pos = top - CursorY() - (scrollThumb:GetHeight() or 0) / 2
    SetScroll(math.max(0, math.min(free, pos)) / free * MaxScroll())
end)

local emptyText = Text(scrollChild, 13, C.grey)
emptyText:SetPoint("TOPLEFT", 4, -6)

-- Vorschau-Bild: schwebt unter der Zeile, deren „Vorschau“ geklickt wurde
preview = CreateFrame("Frame", nil, content)
preview:SetSize(272, 150)
preview:SetFrameLevel(content:GetFrameLevel() + 30)
preview:EnableMouse(true)
preview:SetScript("OnMouseUp", function(self) self:Hide() end)
Panel(preview, 8, C.card, C.line, "BACKGROUND")
local previewImage = preview:CreateTexture(nil, "ARTWORK")
previewImage:SetSize(256, 128)
previewImage:SetPoint("TOP", 0, -8)
local previewCaption = Text(preview, 11, C.grey)
previewCaption:SetPoint("BOTTOMLEFT", 10, 4)
preview:Hide()

---------------------------------------------------------------------------
-- Fußzeile
---------------------------------------------------------------------------

local footLine = Line(content, C.line)
footLine:SetPoint("BOTTOMLEFT", 0, FOOT_H)
footLine:SetPoint("BOTTOMRIGHT", -1, FOOT_H)
footLine:SetHeight(1)

local footDot = content:CreateTexture(nil, "ARTWORK")
footDot:SetSize(8, 8)
footDot:SetPoint("BOTTOMLEFT", 22, FOOT_H / 2 - 4)
footDot:SetTexture(MEDIA .. "dot")

local footText = Text(content, 13, C.grey)
footText:SetPoint("LEFT", footDot, "RIGHT", 8, 0)

local applyButton = MakeButton(content, L["Übernehmen & neu laden"], "primary")
applyButton:SetPoint("BOTTOMRIGHT", -18, (FOOT_H - 30) / 2)

local editButton = MakeButton(content, L["Bearbeitungsmodus"], "dark")
editButton:SetPoint("RIGHT", applyButton, "LEFT", -8, 0)

local discardButton = MakeButton(content, L["Verwerfen"], "dark")
discardButton:SetPoint("RIGHT", editButton, "LEFT", -8, 0)

---------------------------------------------------------------------------
-- Bereiche aus dem Register sammeln
---------------------------------------------------------------------------

local sections = {}      -- Bereichsname → Liste der Optionen
local pages = {}         -- { name, icon, group, sections = { Bereichsnamen } } in Anzeige-Reihenfolge
local allOptions = {}    -- alle Optionen in Register-Reihenfolge
local sectionOf = {}     -- Option → Bereichsname
local pageOf = {}        -- Bereichsname → Seitenname
local optionsByKey = {}  -- Schlüssel → Liste der Optionen
local built = false

local function CollectSections()
    for _, column in ipairs(ns.columns) do
        for _, section in ipairs(column) do
            if not sections[section.name] then sections[section.name] = {} end
            for _, option in ipairs(section.options) do
                table.insert(sections[section.name], option)
                table.insert(allOptions, option)
                sectionOf[option] = section.name
                if option.key then
                    optionsByKey[option.key] = optionsByKey[option.key] or {}
                    table.insert(optionsByKey[option.key], option)
                end
            end
        end
    end
    local placed = {}
    local lastGroup
    for _, group in ipairs(GROUPS) do
        for _, page in ipairs(group.pages) do
            local list = {}
            for _, name in ipairs(page.sections) do
                if sections[name] and not placed[name] then
                    table.insert(list, name)
                    placed[name] = true
                    pageOf[name] = page.name
                end
            end
            if #list > 0 then
                table.insert(pages, { name = page.name, icon = page.icon, group = group.label, sections = list })
            end
            lastGroup = group.label
        end
    end
    -- Bereiche, die keiner Seite zugeordnet sind, landen auf „Weitere“
    local rest = {}
    for name in pairs(sections) do
        if not placed[name] then table.insert(rest, name) end
    end
    if #rest > 0 then
        table.sort(rest)
        for _, name in ipairs(rest) do pageOf[name] = "Weitere" end
        table.insert(pages, { name = "Weitere", icon = "adjustments", group = lastGroup, sections = rest })
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
    for _, p in ipairs(pages) do
        if p.name == name then return p end
    end
end

-- Hauptschalter einer Seite (Schalter-Option mit dem Schlüssel aus MASTER, egal in welchem Bereich;
-- z. B. liegt abEnabled im Bereich „stray-Oberfläche“, steuert aber auch die Seite Aktionsleisten)
local function SwitchOption(key)
    if not key or not optionsByKey[key] then return nil end
    for _, option in ipairs(optionsByKey[key]) do
        if not option.type then return option end
    end
end

local function MasterOption(page)
    return SwitchOption(page and MASTER[page.name])
end

-- Zähler an/gesamt: zählt die Schalter-Optionen der Seite
local function PageCount(page)
    local on, total = 0, 0
    for _, name in ipairs(page.sections) do
        for _, option in ipairs(sections[name]) do
            if not option.type then
                total = total + 1
                if SafeGet(option) and OptionEnabled(option) then on = on + 1 end
            end
        end
    end
    return on, total
end

---------------------------------------------------------------------------
-- Schnappschuss beim Öffnen, Zähler und Verwerfen
---------------------------------------------------------------------------

-- Laufende Daten (keine Einstellungen): zählen nicht als Änderung und werden nie zurückgesetzt
local DATA_KEYS = {
    point = true, altData = true, accountCVarData = true, flightRouteTimes = true,
    mailAltList = true, playerNoteData = true, xpHistory = true,
}
local function IsDataKey(key)
    if DATA_KEYS[key] then return true end
    if type(key) ~= "string" then return false end
    return key:find("Data$") or key:find("History$") or key:find("Times$") or false
end

-- Tabellen, deren Einträge einzeln zählen (je Anzeige)
local PER_ENTRY = { positions = true, scales = true }

-- Bereiche mit Leisten/Rahmen: im Kampf erst nach dem Kampf zurücksetzen
local DEFER_SECTIONS = {
    ["Aktionsleisten"] = true, ["Abklingzeiten"] = true, ["Gruppenrahmen"] = true,
    ["stray-Oberfläche"] = true, ["Leisten & Minimap"] = true, ["Erfahrung"] = true,
    ["Kamera & Karte"] = true, ["Zaubern"] = true, ["Taschen"] = true,
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

local snapshot -- { db = Kopie, opts = { [Option] = Wert } } oder nil

-- Kampf-Merker: PLAYER_REGEN_DISABLED kommt kurz bevor InCombatLockdown() wahr wird
local combatFlag = false
local function InCombat()
    return combatFlag or InCombatLockdown()
end
ns.On("PLAYER_REGEN_DISABLED", function() combatFlag = true end)
ns.On("PLAYER_REGEN_ENABLED", function() combatFlag = false end)

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
    for _, option in ipairs(allOptions) do
        if IsOutsideOption(option) then
            local value = SafeGet(option)
            local t = type(value)
            if not ns.IsSecret(value) and (t == "boolean" or t == "number" or t == "string") then
                opts[option] = value
            end
        end
    end
    snapshot = { db = db, opts = opts }
end

-- Liste der geänderten Einträge: { key =, sub = (für positions/scales) } und geänderte Außen-Optionen
local function Changes()
    local list, outside = {}, {}
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

-- Im Kampf aufgeschobene Rücksetzungen
local pendingOptions, pendingPositions = {}, {}
local hasPending = false

local function RestoreMovable(key)
    for _, entry in ipairs(ns.movables or {}) do
        local f = entry.frame
        if f and f.strayKey == key then
            if f.strayDefault or (ns.db.positions and ns.db.positions[key]) then
                pcall(ns.RestorePosition, f)
            end
            if ns.db.scales ~= nil then
                if ns.ApplyScale then
                    pcall(ns.ApplyScale, f)
                else
                    local s = type(ns.db.scales) == "table" and ns.db.scales[key]
                    if type(s) ~= "number" then s = 1 elseif s > 5 then s = s / 100 end
                    pcall(f.SetScale, f, s)
                end
            end
        end
    end
end

local Refresh

-- Alle Einstellungen auf den Stand beim Öffnen zurücksetzen und sofort wieder anwenden
local function Revert()
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
        if combat and DEFER_SECTIONS[sectionOf[option]] then
            pendingOptions[option] = { value = value }
            hasPending = true
            return
        end
        if value == nil then value = SafeGet(option) end
        pcall(option.set, value)
    end
    for _, option in ipairs(outside) do Apply(option, snapshot.opts[option]) end
    for _, option in ipairs(allOptions) do
        if option.key and changedKeys[option.key] then Apply(option) end
    end
    -- Schlüssel ohne eigene Option (z. B. Werte je Leiste): verwandte Optionen gleichen Präfixes neu anwenden
    for key in pairs(changedKeys) do
        if not optionsByKey[key] and not PER_ENTRY[key] and type(key) == "string" then
            local prefix = key:match("^%l+")
            if prefix and #prefix >= 2 then
                for _, option in ipairs(allOptions) do
                    if option.key and option.key:match("^%l+") == prefix then Apply(option) end
                end
            end
        end
    end

    -- 3. Positionen und Größen der Anzeigen
    for key in pairs(movedKeys) do
        if combat then
            pendingPositions[key] = true
            hasPending = true
        else
            RestoreMovable(key)
        end
    end

    if combat and hasPending then
        ns.Print(L["Leisten und Rahmen werden nach dem Kampf zurückgesetzt."])
    end
    if Refresh and frame:IsShown() then Refresh() end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if not hasPending then return end
    hasPending = false
    local options, positions = pendingOptions, pendingPositions
    pendingOptions, pendingPositions = {}, {}
    for _, option in ipairs(allOptions) do
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
-- Optionszeilen
---------------------------------------------------------------------------

local function ShowTooltip(row)
    local option = row.option
    if not option then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(option.label, 1, 1, 1)
    if option.tooltip then
        GameTooltip:AddLine(option.tooltip, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    end
    if option.type == "slider" then
        GameTooltip:AddLine(L["Mausrad mit gedrückter Umschalttaste verstellt den Regler."], C.grey[1], C.grey[2], C.grey[3], true)
    elseif option.type == "choice" and row.cycle and row.cycle:IsShown() then
        GameTooltip:AddLine(L["Linksklick: weiter, Rechtsklick: zurück."], C.grey[1], C.grey[2], C.grey[3], true)
    end
    if not OptionEnabled(option) and option.disabledHint then
        GameTooltip:AddLine(option.disabledHint, 1, 0.3, 0.3, true)
    end
    GameTooltip:Show()
end

local function ShowPreview(option, row)
    if preview:IsShown() and preview.option == option then
        preview:Hide()
        return
    end
    preview.option = option
    preview:ClearAllPoints()
    -- Unter die Zeile; reicht der Platz nicht, darüber
    local rowBottom = row and row:GetBottom()
    local scrollBottom = scroll:GetBottom()
    if row and rowBottom and scrollBottom and rowBottom - 160 < scrollBottom then
        preview:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 4)
    elseif row then
        preview:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -4)
    else
        preview:SetPoint("CENTER", scroll, "CENTER")
    end
    previewImage:SetTexture(MEDIA .. option.preview)
    previewCaption:SetText(L("Beispielbild: %s", option.label or ""))
    preview:Show()
end

-- Nach jeder Änderung: Fenster neu zeichnen (Zähler, Ausgrauen, Fußzeile)
local function Changed()
    if Refresh then Refresh() end
end

local rows = {}

local function CreateRow()
    local row = CreateFrame("Frame", nil, scrollChild)
    row:EnableMouse(true)

    row.line = Line(row, C.line)
    row.line:SetPoint("TOPLEFT", PAD, 0)
    row.line:SetPoint("TOPRIGHT", -PAD, 0)
    row.line:SetHeight(1)

    row.label = Text(row, 13, C.text)
    row.label:SetWordWrap(false)
    row.desc = Text(row, 11, C.grey)
    row.desc:SetWordWrap(false)

    -- Schalter
    local switch = MakeSwitch(row)
    switch:SetPoint("RIGHT", -PAD, 0)
    switch:SetScript("OnClick", function()
        local option = row.option
        if not option or not OptionEnabled(option) then return end
        local value = not SafeGet(option)
        ns.Sound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        option.set(value)
        Changed()
    end)
    switch:SetScript("OnEnter", function() ShowTooltip(row) end)
    switch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.switch = switch

    -- „Vorschau“-Knopf für Optionen mit Beispielbild
    local previewButton = MakeButton(row, L["Vorschau"], "dark", 20)
    previewButton.text:SetFont(FONT, 11, "")
    previewButton:SetLabel(L["Vorschau"])
    previewButton:SetPoint("RIGHT", switch, "LEFT", -10, 0)
    previewButton:SetScript("OnClick", function() if row.option then ShowPreview(row.option, row) end end)
    row.previewButton = previewButton

    -- Regler (type = "slider")
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:EnableMouseWheel(true)
    slider.track = slider:CreateTexture(nil, "ARTWORK")
    slider.track:SetPoint("LEFT"); slider.track:SetPoint("RIGHT"); slider.track:SetHeight(4)
    slider.track:SetTexture(MEDIA .. "pill")
    slider.track:SetVertexColor(C.off[1], C.off[2], C.off[3], 1)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 14)
    thumb:SetTexture(MEDIA .. "dot")
    thumb:SetVertexColor(1, 1, 1, 1)
    slider:SetThumbTexture(thumb)
    slider.fill = slider:CreateTexture(nil, "ARTWORK", nil, 1)
    slider.fill:SetHeight(4)
    slider.fill:SetPoint("LEFT", slider.track, "LEFT")
    slider.fill:SetPoint("RIGHT", thumb, "CENTER")
    slider.fill:SetTexture(MEDIA .. "pill")
    slider.fill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider.value = Text(row, 12, C.text)
    slider.value:SetJustifyH("RIGHT")
    slider:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        local option = row.option
        if not option or option.type ~= "slider" or not OptionEnabled(option) then return end
        local step = option.step or 1
        value = math.floor(value / step + 0.5) * step
        self.value:SetText(FormatValue(option, value))
        if SafeGet(option) ~= value then
            option.set(value)
            Changed()
        end
    end)
    -- Mausrad scrollt die Seite; nur mit gedrückter Umschalttaste verstellt es den Regler
    slider:SetScript("OnMouseWheel", function(self, delta)
        local option = row.option
        if not IsShiftKeyDown() or not option or not OptionEnabled(option) then
            SetScroll(scroll:GetVerticalScroll() - delta * WHEEL_STEP)
            return
        end
        self:SetValue(self:GetValue() + delta * (option.step or 1))
    end)
    slider:SetScript("OnEnter", function() ShowTooltip(row) end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.slider = slider

    -- Knopf für Aktionen (type = "button")
    local action = MakeButton(row, "", "dark", 26)
    action:SetPoint("RIGHT", -PAD, 0)
    action:SetScript("OnClick", function()
        local option = row.option
        if not option or option.type ~= "button" or not OptionEnabled(option) then return end
        ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if option.onClick then
            local ok, err = pcall(option.onClick)
            if not ok then geterrorhandler()(err) end
        end
        Changed()
    end)
    local actionLeave = action:GetScript("OnLeave")
    local actionEnter = action:GetScript("OnEnter")
    action:SetScript("OnEnter", function(self) actionEnter(self); ShowTooltip(row) end)
    action:SetScript("OnLeave", function(self) actionLeave(self) end)
    row.action = action

    -- Auswahl als Segmentknöpfe (type = "choice" mit wenigen Werten)
    local choice = CreateFrame("Frame", nil, row)
    choice:SetHeight(24)
    choice.buttons = {}
    row.choice = choice

    -- Auswahl mit vielen Werten: ein Knopf, der weiterschaltet
    local cycle = MakeButton(row, "", "dark", 26)
    cycle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cycle:SetPoint("RIGHT", -PAD, 0)
    cycle:SetScript("OnClick", function(_, button)
        local option = row.option
        if not option or option.type ~= "choice" or not OptionEnabled(option) then return end
        local values = option.values or {}
        if #values == 0 then return end
        local current, index = SafeGet(option), 1
        for i, v in ipairs(values) do if v == current then index = i end end
        index = index + (button == "RightButton" and -1 or 1)
        if index < 1 then index = #values elseif index > #values then index = 1 end
        ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        option.set(values[index])
        Changed()
    end)
    local cycleEnter, cycleLeave = cycle:GetScript("OnEnter"), cycle:GetScript("OnLeave")
    cycle:SetScript("OnEnter", function(self) cycleEnter(self); ShowTooltip(row) end)
    cycle:SetScript("OnLeave", function(self) cycleLeave(self) end)
    row.cycle = cycle

    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Klick auf die Zeile schaltet ebenfalls um (nur bei Schaltern)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and row.option and not row.option.type then switch:Click() end
    end)
    row:EnableMouseWheel(false)
    return row
end

local function GetRow(i)
    if not rows[i] then
        rows[i] = CreateRow()
        rows[i]:SetFrameLevel(scrollChild:GetFrameLevel() + 3)
    end
    return rows[i]
end

local function ChoiceLabel(option, i)
    return option.labels and option.labels[i] or tostring(option.values[i])
end

-- Segmentknöpfe füllen; gibt die Gesamtbreite zurück
local function FillSegments(row, option, enabled)
    local choice = row.choice
    local values = option.values or {}
    local current = SafeGet(option)
    local x = 0
    for i = 1, #values do
        local b = choice.buttons[i]
        if not b then
            b = MakeButton(choice, "", "dark", 24)
            b.text:SetFont(FONT, 12, "")
            local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
            b:SetScript("OnEnter", function(self) enter(self); ShowTooltip(row) end)
            b:SetScript("OnLeave", function(self) leave(self) end)
            choice.buttons[i] = b
        end
        local value = values[i]
        local selected = current == value
        b.style = selected and "primary" or "dark"
        b.fill:SetColor(selected and C.accent or C.hover)
        b.border:SetColor(selected and C.accent or C.line)
        SetTextColor(b.text, selected and C.white or C.text)
        b.text:SetText(ChoiceLabel(option, i))
        b:SetWidth(math.max(24, math.floor(b.text:GetStringWidth() + 16)))
        b:ClearAllPoints()
        b:SetPoint("LEFT", choice, "LEFT", x, 0)
        x = x + b:GetWidth() + 4
        b:SetScript("OnClick", function()
            if not OptionEnabled(option) then return end
            ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            option.set(value)
            Changed()
        end)
        b:SetActive(enabled)
        b:Show()
    end
    for i = #values + 1, #choice.buttons do choice.buttons[i]:Hide() end
    x = math.max(0, x - 4)
    choice:SetWidth(math.max(1, x))
    return x
end

-- Zeile füllen und anordnen; gibt die Zeilenhöhe zurück
local function FillRow(row, option, width, isFirst)
    local enabled = OptionEnabled(option)
    local inner = width - 2 * PAD
    row.option = option
    row.line:SetShown(not isFirst)

    row.label:SetText(option.label)
    SetTextColor(row.label, enabled and C.text or C.grey)
    local desc
    if not enabled and option.disabledHint then
        desc = option.disabledHint
        SetTextColor(row.desc, C.red)
    else
        desc = ShortDesc(option)
        SetTextColor(row.desc, C.grey)
    end
    row.desc:SetText(desc or "")
    local hasDesc = desc ~= nil and desc ~= ""

    local kind = option.type
    local values = option.values or {}
    local isSwitch = kind == nil
    row.switch:SetShown(isSwitch)
    row.previewButton:SetShown(isSwitch and option.preview ~= nil)
    row.slider:SetShown(kind == "slider")
    row.slider.value:SetShown(kind == "slider")
    row.action:SetShown(kind == "button")
    row.choice:SetShown(false)
    row.cycle:SetShown(false)

    row.label:ClearAllPoints()
    row.desc:ClearAllPoints()
    row.slider:ClearAllPoints()
    row.slider.value:ClearAllPoints()
    row.choice:ClearAllPoints()
    row.desc:Show()

    -- Platz rechts für das Bedienelement
    local function TextLeft(controlWidth, twoLines)
        local right = -(PAD + controlWidth + 12)
        if twoLines then
            row.label:SetPoint("TOPLEFT", PAD, -9)
            row.label:SetPoint("RIGHT", row, "RIGHT", right, 0)
            row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -4)
            row.desc:SetPoint("RIGHT", row, "RIGHT", right, 0)
            return 48
        end
        row.label:SetPoint("LEFT", PAD, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", right, 0)
        row.desc:Hide()
        return 36
    end

    if kind == "slider" then
        local slider = row.slider
        slider.updating = true
        slider:SetMinMaxValues(option.min or 0, option.max or 100)
        slider:SetValueStep(option.step or 1)
        local value = SafeGet(option)
        if type(value) ~= "number" then value = option.min or 0 end
        slider:SetValue(value)
        slider.value:SetText(FormatValue(option, value))
        slider.updating = false
        slider:EnableMouse(enabled)
        slider:SetAlpha(enabled and 1 or 0.4)
        slider.value:SetAlpha(enabled and 1 or 0.4)
        row.desc:Hide()
        local labelW = row.label:GetStringWidth() or 0
        if labelW <= 118 and inner >= 250 then
            -- eine Zeile: Name · Regler · Wert
            row.label:SetPoint("LEFT", PAD, 0)
            row.label:SetWidth(120)
            slider:SetPoint("LEFT", row, "LEFT", PAD + 128, 0)
            slider:SetPoint("RIGHT", row, "RIGHT", -(PAD + 46), 0)
            slider.value:SetPoint("RIGHT", -PAD, 0)
            return 36
        end
        -- zwei Zeilen: Name und Wert oben, Regler darunter
        row.label:SetPoint("TOPLEFT", PAD, -9)
        row.label:SetPoint("RIGHT", row, "RIGHT", -(PAD + 50), 0)
        slider.value:SetPoint("TOPRIGHT", -PAD, -9)
        slider:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -28)
        slider:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
        return 52
    elseif kind == "button" then
        row.action:SetLabel(option.buttonText or option.label, 70)
        row.action:SetActive(enabled)
        return TextLeft(row.action:GetWidth(), hasDesc)
    elseif kind == "choice" then
        if #values > 0 and #values <= 6 then
            row.choice:Show()
            local w = FillSegments(row, option, enabled)
            local labelW = row.label:GetStringWidth() or 0
            row.desc:Hide()
            if labelW + w + 16 <= inner then
                row.choice:SetPoint("RIGHT", -PAD, 0)
                row.label:SetPoint("LEFT", PAD, 0)
                row.label:SetPoint("RIGHT", row, "RIGHT", -(PAD + w + 12), 0)
                return 38
            end
            row.label:SetPoint("TOPLEFT", PAD, -9)
            row.label:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
            row.choice:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -28)
            return 60
        end
        -- viele Werte: Knopf mit dem aktuellen Wert
        row.cycle:Show()
        local current, label = SafeGet(option), ""
        for i, v in ipairs(values) do
            if v == current then label = ChoiceLabel(option, i) end
        end
        row.cycle:SetLabel(label ~= "" and label or tostring(current or "–"), 70)
        row.cycle:SetActive(enabled)
        return TextLeft(row.cycle:GetWidth(), hasDesc)
    end

    -- Schalter
    row.switch:SetState(SafeGet(option) and true or false, enabled)
    local controlW = 32 + (option.preview and (row.previewButton:GetWidth() + 10) or 0)
    return TextLeft(controlW, hasDesc)
end

---------------------------------------------------------------------------
-- Karten
---------------------------------------------------------------------------

local cards = {}

local function GetCard(i)
    local card = cards[i]
    if not card then
        card = CreateFrame("Frame", nil, scrollChild)
        card:SetFrameLevel(scrollChild:GetFrameLevel() + 1)
        Panel(card, 10, C.card, C.line, "BACKGROUND")
        card.name = Text(card, 14, C.white)
        card.name:SetPoint("TOPLEFT", PAD, -12)
        card.page = Text(card, 11, C.faint)
        card.page:SetPoint("LEFT", card.name, "RIGHT", 8, 0)
        card.badge = CreateFrame("Frame", nil, card)
        card.badge:SetSize(20, 18)
        card.badge:SetPoint("TOPRIGHT", -10, -10)
        RoundRect(card.badge, 5, C.hover, "BACKGROUND")
        card.count = Text(card.badge, 11, C.accent)
        card.count:SetPoint("CENTER")
        card.headLine = Line(card, C.line)
        card.headLine:SetPoint("TOPLEFT", 1, -CARD_HEAD)
        card.headLine:SetPoint("TOPRIGHT", -1, -CARD_HEAD)
        card.headLine:SetHeight(1)
        cards[i] = card
    end
    return card
end

-- Hält die Scrollposition im gültigen Bereich (ohne die Vorschau zu schließen)
local function ClampScroll()
    local current = scroll:GetVerticalScroll() or 0
    if current > MaxScroll() then scroll:SetVerticalScroll(MaxScroll()) end
    UpdateScrollBar()
end

-- blocks: Liste von { name =, page = (nur bei der Suche), options = {…} }
local function Layout(blocks)
    local colY = { 0, 0 }
    local full = #blocks == 1
    local r = 0
    for ci, block in ipairs(blocks) do
        local card = GetCard(ci)
        local col = (full or colY[1] <= colY[2]) and 1 or 2
        local width = full and SCROLL_W or COL_W
        local x = (col - 1) * (COL_W + COL_GAP)
        local top = colY[col]
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, -top)
        card:SetWidth(width)
        -- Bereichs- und Seitennamen bleiben deutsche Schlüssel, übersetzt wird erst hier
        card.name:SetText(L[block.name])
        card.page:SetText(block.page and ("· " .. L[block.page]) or "")
        card.count:SetText(#block.options)
        card.badge:SetWidth(math.max(20, math.floor(card.count:GetStringWidth() + 12)))

        local y = CARD_HEAD
        for oi, option in ipairs(block.options) do
            r = r + 1
            local row = GetRow(r)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -y)
            local h = FillRow(row, option, width, oi == 1)
            row:SetHeight(h)
            row:Show()
            y = y + h
        end
        local height = y + CARD_PAD
        card:SetHeight(height)
        card:Show()
        if full then
            colY[1] = top + height + COL_GAP
            colY[2] = colY[1]
        else
            colY[col] = top + height + COL_GAP
        end
    end
    for i = r + 1, #rows do
        rows[i].option = nil
        rows[i]:Hide()
    end
    for i = #blocks + 1, #cards do cards[i]:Hide() end
    scrollChild:SetHeight(math.max(1, math.max(colY[1], colY[2]) - COL_GAP))
    ClampScroll()
end

---------------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------------

local searchCache = {} -- Option → { keywords = "…", label = "…", rest = "…" }

local function SearchData(option)
    local data = searchCache[option]
    if data then return data end
    local section = sectionOf[option] or ""
    local words = {}
    local function Add(list)
        if type(list) ~= "table" then return end
        for _, w in ipairs(list) do table.insert(words, Lower(w)) end
    end
    Add(option.keywords)
    Add(option.key and KEYWORDS[option.key])
    Add(SECTION_KEYWORDS[section])
    data = {
        keywords = words,
        label = Lower(option.label),
        -- Bereich und Seite deutsch und in der angezeigten Sprache, damit beides gefunden wird
        rest = Lower((option.tooltip or "") .. " " .. section .. " " .. L[section] .. " "
            .. (pageOf[section] or "") .. " " .. L[pageOf[section] or ""]),
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

-- Treffer nach Bereichen gruppiert, beste zuerst; gibt Blöcke und Anzahl zurück
local function SearchResults(query)
    local tokens = {}
    for token in Lower(query):gmatch("%S+") do table.insert(tokens, token) end
    local blocks, count, order = {}, 0, 0
    if #tokens == 0 then return blocks, 0 end
    for _, page in ipairs(pages) do
        for _, name in ipairs(page.sections) do
            local found = {}
            local best = 0
            for i, option in ipairs(sections[name]) do
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
                table.insert(blocks, { name = name, page = page.name, options = options, score = best, order = order })
            end
        end
    end
    table.sort(blocks, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    return blocks, count
end

search:SetScript("OnTextChanged", function(self)
    placeholder:SetShown(self:GetText() == "")
    SetScroll(0)
    preview:Hide()
    if Refresh then Refresh() end
end)
search:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

---------------------------------------------------------------------------
-- Navigation: Einträge in Gruppen
---------------------------------------------------------------------------

local NAV_H = 34
local selected
local navButtons = {}
local groupLabels = {}

local function SelectPage(name)
    if selected ~= name or search:GetText() ~= "" then SetScroll(0) end
    selected = name
    search:SetText("")
    search:ClearFocus()
    preview:Hide()
    ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    Refresh()
end

local function BuildNav()
    local y = -106
    local lastGroup
    for _, page in ipairs(pages) do
        if page.group ~= lastGroup then
            if lastGroup then y = y - 8 end
            local g = Text(side, 10, C.faint)
            g:SetPoint("TOPLEFT", 20, y - 6)
            g:SetText(L[page.group])
            table.insert(groupLabels, g)
            y = y - 24
            lastGroup = page.group
        end
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDE_W - 20, NAV_H)
        b:SetPoint("TOPLEFT", 10, y)
        b.page = page

        b.bg = RoundRect(b, 7, C.hover, "BACKGROUND")
        b.bg:SetShown(false)

        b.tile = CreateFrame("Frame", nil, b)
        b.tile:SetSize(24, 24)
        b.tile:SetPoint("LEFT", 8, 0)
        b.tileBg = RoundRect(b.tile, 6, C.accent, "BACKGROUND")
        b.icon = b.tile:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("CENTER")
        b.icon:SetTexture(ICONS .. (page.icon or "adjustments"))

        b.text = Text(b, 14, C.text)
        b.text:SetPoint("LEFT", b.tile, "RIGHT", 10, 0)
        b.text:SetText(L[page.name])

        b.count = Text(b, 11, C.faint)
        b.count:SetPoint("RIGHT", -10, 0)
        b.count:SetJustifyH("RIGHT")

        b:SetScript("OnClick", function(self) SelectPage(self.page.name) end)
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
        y = y - NAV_H - 2
    end
end

local function EnsureBuilt()
    if built then return end
    built = true
    CollectSections()
    selected = pages[1] and pages[1].name
    BuildNav()
end

---------------------------------------------------------------------------
-- Fußzeile und Dialog
---------------------------------------------------------------------------

local dialog -- weiter unten angelegt

local function UpdateFooter()
    local n = CountChanges()
    if n > 0 then
        footDot:SetVertexColor(C.amber[1], C.amber[2], C.amber[3], 1)
        SetTextColor(footText, C.text)
        footText:SetText(n == 1 and L["1 ungespeicherte Änderung"] or L("%d ungespeicherte Änderungen", n))
    else
        footDot:SetVertexColor(C.faint[1], C.faint[2], C.faint[3], 1)
        SetTextColor(footText, C.grey)
        footText:SetText(L["Keine ungespeicherten Änderungen"])
    end
    local combat = InCombat()
    discardButton:SetActive(n > 0)
    applyButton:SetActive(not combat)
    editButton:SetActive(not combat)
    if dialog and dialog:IsVisible() then dialog:Update(n) end
    return n
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------

-- Für Module: Fenster neu zeichnen, wenn sich ein Wert von außen geändert hat (z. B. Spalten per Ziehen)
function ns.RefreshConfig()
    if frame:IsShown() and Refresh then Refresh() end
end

function Refresh()
    if not ns.db or not built then return end
    local query = search:GetText()
    local searching = query ~= ""

    for _, b in ipairs(navButtons) do
        local isSelected = b.page.name == selected and not searching
        b.isSelected = isSelected
        b.bg:SetColor(C.hover)
        b.bg:SetShown(isSelected)
        b.tileBg:SetShown(isSelected)
        if isSelected then
            b.icon:SetVertexColor(1, 1, 1, 1)
            SetTextColor(b.text, C.white)
        else
            b.icon:SetVertexColor(C.grey[1], C.grey[2], C.grey[3], 1)
            SetTextColor(b.text, { 0.78, 0.78, 0.82, 1 })
        end
        local on, total = PageCount(b.page)
        b.count:SetText(total > 0 and (on .. "/" .. total) or "–")
        SetTextColor(b.count, isSelected and C.accent or C.faint)
    end

    local blocks = {}
    local masterOption
    if searching then
        local count
        blocks, count = SearchResults(query)
        groupLine:SetText(L["SUCHE"])
        title:SetText(L("„%s“", query))
        subtitle:SetText(count == 0 and L["Nichts gefunden."]
            or (count == 1 and L["1 Option gefunden."] or L("%d Optionen gefunden.", count)))
        emptyText:SetText(count == 0 and L["Versuch ein anderes Wort, z. B. „Taschen“, „aggro“ oder „xp“."] or "")
    else
        local page = FindPage(selected)
        groupLine:SetText(page and L[page.group] or "")
        title:SetText(L[selected or ""])
        subtitle:SetText(L[PAGE_SUBTITLES[selected] or ""])
        masterOption = MasterOption(page)
        if page then
            for _, name in ipairs(page.sections) do
                local list = {}
                for _, option in ipairs(sections[name]) do
                    if option ~= masterOption then table.insert(list, option) end
                end
                if #list > 0 then table.insert(blocks, { name = name, options = list }) end
            end
        end
        emptyText:SetText("")
    end

    -- Hauptschalter im Kopf
    master.option = masterOption
    if masterOption then
        masterSwitch:SetState(SafeGet(masterOption) and true or false, OptionEnabled(masterOption))
        master:Show()
    else
        master:Hide()
    end

    Layout(blocks)
    emptyText:SetShown(#blocks == 0)
    UpdateFooter()
end

masterSwitch:SetScript("OnClick", function()
    local option = master.option
    if not option or not OptionEnabled(option) then return end
    local value = not SafeGet(option)
    ns.Sound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    -- Immer über die set-Funktionen der Optionen, damit die Module ihr Apply ausführen
    local required = value and SwitchOption(MASTER_REQUIRES[option.key])
    if required and not SafeGet(required) then required.set(true) end
    option.set(value)
    Changed()
end)
masterSwitch:SetScript("OnEnter", function(self)
    local option = master.option
    if not option then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(option.label, 1, 1, 1)
    if option.tooltip then GameTooltip:AddLine(option.tooltip, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true) end
    if not OptionEnabled(option) and option.disabledHint then
        GameTooltip:AddLine(option.disabledHint, 1, 0.3, 0.3, true)
    end
    GameTooltip:Show()
end)
masterSwitch:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Schließen mit Nachfrage
---------------------------------------------------------------------------

-- Esc: statt des Fensters steht ein unsichtbarer Fänger in UISpecialFrames. Versteckt Esc ihn,
-- entscheidet stray selbst: ohne Änderung schließen, sonst nachfragen; im Dialog = zurück.
local escCatcher = CreateFrame("Frame", "strayFrameEsc", UIParent)
escCatcher:SetSize(1, 1)
escCatcher:SetPoint("TOPLEFT")
escCatcher:Hide()
tinsert(UISpecialFrames, "strayFrameEsc")

local quietHide = false -- Fenster wird von stray selbst versteckt (kein Esc)

local function CloseNow()
    snapshot = nil
    quietHide = true
    frame:Hide()
    quietHide = false
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
    if quietHide or self:IsShown() then return end -- selbst versteckt bzw. nur UIParent ausgeblendet
    if not frame:IsShown() then return end
    if dialog:IsVisible() then
        dialog:Hide() -- Esc im Dialog = zurück ins Fenster
    else
        RequestClose()
    end
    -- Fänger wieder scharf machen, solange das Fenster offen ist
    C_Timer.After(0, function()
        if frame:IsShown() and not escCatcher:IsShown() then escCatcher:Show() end
    end)
end)

close:SetScript("OnClick", function() RequestClose() end)

-- Dialog in stray-Optik über dem Fenster
local shade = CreateFrame("Frame", nil, frame)
shade:SetAllPoints()
shade:SetFrameLevel(frame:GetFrameLevel() + 40)
shade:EnableMouse(true)
shade:EnableMouseWheel(true)
shade:SetScript("OnMouseWheel", function() end)
RoundRect(shade, 12, { 0, 0, 0, 0.55 }, "BACKGROUND")
shade:Hide()

dialog = CreateFrame("Frame", nil, shade)
dialog:SetSize(400, 190)
dialog:SetPoint("CENTER", frame, "CENTER", 0, 20)
dialog:SetFrameLevel(shade:GetFrameLevel() + 5)
dialog:EnableMouse(true)
Panel(dialog, 12, C.card, C.line, "BACKGROUND")

local dialogTitle = Text(dialog, 16, C.white)
dialogTitle:SetPoint("TOPLEFT", 20, -20)
dialogTitle:SetText(L["Ungespeicherte Änderungen"])

local dialogText = Text(dialog, 13, C.grey)
dialogText:SetPoint("TOPLEFT", dialogTitle, "BOTTOMLEFT", 0, -10)
dialogText:SetWidth(360)
dialogText:SetWordWrap(true)
dialogText:SetJustifyV("TOP")

local dialogReload = MakeButton(dialog, L["Neu laden"], "primary")
dialogReload:SetPoint("BOTTOMRIGHT", -16, 16)
local dialogDiscard = MakeButton(dialog, L["Verwerfen"], "dark")
dialogDiscard:SetPoint("RIGHT", dialogReload, "LEFT", -8, 0)
local dialogBack = MakeButton(dialog, L["Zurück"], "dark")
dialogBack:SetPoint("RIGHT", dialogDiscard, "LEFT", -8, 0)

function dialog:Update(n)
    local text = (n == 1 and L["Du hast 1 Einstellung geändert."] or L("Du hast %d Einstellungen geändert.", n))
        .. " " .. L["„Neu laden“ übernimmt alles sicher, „Verwerfen“ stellt den Stand beim Öffnen wieder her."]
    if InCombat() then
        text = text .. "\n" .. L["Im Kampf: Leisten und Rahmen werden erst nach dem Kampf zurückgesetzt."]
    end
    dialogText:SetText(text)
    dialogReload:SetActive(not InCombat())
end

function dialog:Open()
    GameTooltip:Hide()
    preview:Hide()
    search:ClearFocus()
    shade:Show()
    self:Show()
    self:Update(CountChanges())
end

dialog:SetScript("OnHide", function() shade:Hide() end)
shade:SetScript("OnHide", function() dialog:Hide() end)

dialogBack:SetScript("OnClick", function() dialog:Hide() end)
dialogDiscard:SetScript("OnClick", function()
    Revert()
    dialog:Hide()
    CloseNow()
end)
dialogReload:SetScript("OnClick", function(self)
    if self.inactive or InCombat() then return end
    ReloadUI()
end)
ButtonTooltip(dialogReload, L["Neu laden"], function()
    return InCombat() and L["Im Kampf nicht möglich."] or L["Lädt die Oberfläche neu und übernimmt alle Änderungen."]
end)

-- Fußzeilen-Knöpfe
discardButton:SetScript("OnClick", function(self)
    if self.inactive then return end
    ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    Revert()
    Refresh()
end)
ButtonTooltip(discardButton, L["Verwerfen"], L["Setzt alle Einstellungen auf den Stand beim Öffnen des Fensters zurück und wendet sie sofort wieder an."])

applyButton:SetScript("OnClick", function(self)
    if self.inactive or InCombat() then return end
    ReloadUI()
end)
ButtonTooltip(applyButton, L["Übernehmen & neu laden"], function()
    return InCombat() and L["Im Kampf nicht möglich."]
        or L["Lädt die Oberfläche neu, damit alle Änderungen sicher übernommen werden."]
end)

editButton:SetScript("OnClick", function(self)
    if self.inactive or InCombat() then return end
    -- Fenster schließt sich für den Bearbeitungsmodus; ungespeicherte Änderungen bleiben gezählt
    if ns.EnterEditMode then ns.EnterEditMode() end
end)
ButtonTooltip(editButton, L["Bearbeitungsmodus"], L["Schließt dieses Fenster und blendet alle eingeschalteten stray-Anzeigen zum Verschieben ein. „Fertig“ oder Esc beendet den Modus. Auch per /stray edit."])

ns.On("PLAYER_REGEN_DISABLED", function() if frame:IsShown() then UpdateFooter() end end)
ns.On("PLAYER_REGEN_ENABLED", function() if frame:IsShown() then UpdateFooter() end end)

---------------------------------------------------------------------------
-- Öffnen und Schließen
---------------------------------------------------------------------------

-- Zähler regelmäßig nachziehen (z. B. Anzeige per Shift-Ziehen verschoben)
local footerTimer = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    footerTimer = footerTimer + elapsed
    if footerTimer < 0.5 then return end
    footerTimer = 0
    UpdateFooter()
end)

frame:SetScript("OnShow", function()
    EnsureBuilt()
    -- Fenster und Bearbeiten-Modus nicht gleichzeitig
    if ns.editMode and ns.ExitEditMode then ns.ExitEditMode() end
    -- Schnappschuss nur, wenn keiner mehr offen ist (z. B. nach dem Bearbeitungsmodus behalten)
    if not snapshot then TakeSnapshot() end
    ns.Sound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    shade:Hide()
    escCatcher:Show()
    Refresh()
    ns.NotifyConfig()
end)

frame:SetScript("OnHide", function()
    ns.Sound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    quietHide = true
    escCatcher:Hide()
    quietHide = false
    shade:Hide()
    search:ClearFocus()
    preview:Hide()
    GameTooltip:Hide()
    -- Nicht über stray geschlossen (z. B. Bearbeitungsmodus): Schnappschuss bleibt, damit die
    -- Änderungen beim nächsten Öffnen weiter zählen. Nur leere Schnappschüsse verwerfen.
    if snapshot and CountChanges() == 0 then snapshot = nil end
    ns.NotifyConfig()
end)

-- Falls Einstellungen woanders geändert werden (z. B. Blizzard-Optionen)
ns.On("CVAR_UPDATE", function()
    if frame:IsShown() then Refresh() end
end)

function ns.OnLoaded()
    versionText:SetText((ns.GetVersion() or ""):upper())
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
