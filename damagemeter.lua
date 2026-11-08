-- stray – DMG-Meter: eigene Fenster für Schaden und Heilung (gesamt, aktueller Kampf, einzelne Kämpfe)
--
-- Die Werte kommen aus Blizzards eingebautem Schadensmesser (C_DamageMeter), nicht aus dem Kampflog.
-- Im Kampf versiegelt WoW Forever Name, GUID, Gesamtwert und Wert pro Sekunde („secret values“).
-- Damit darf ein Addon nicht vergleichen, nicht rechnen, nicht testen und keine Tabellenschlüssel
-- bilden. Deshalb gilt hier überall: erst ns.IsSecret() prüfen; versiegelte Werte werden nur an
-- Anzeige-Funktionen (SetText, SetFormattedText, SetValue, SetMinMaxValues, AbbreviateNumbers)
-- weitergereicht – jeweils in pcall. Klassenname und „bin ich das“ sind nie versiegelt.
--
-- Es gibt bis zu fünf Fenster (seit 0.23.0-alpha) mit eigenem Modus, eigener Ansicht, Größe und
-- Position. Alle baut dieselbe Fabrik-Funktion (CreateMeter). „+“ im Kopf öffnet eine Kopie (gleiche
-- Größe, gleicher Modus), die oben an dieses Fenster andockt; „×“ schließt ein zusätzliches Fenster.
-- Jedes Fenster lässt sich an Ober- oder Unterkante eines anderen andocken; angedockte Ketten laufen
-- mit (Position und Breite folgen dem untersten nicht angedockten Fenster der Kette, der „Wurzel“).
--
-- Speicherung: Fenster 1 nutzt weiter dmMode, dmWidth, dmHeight und positions.damagemeter.
-- ns.db.dmWindows ist die Liste der Fenster: [n] = { mode =, dockTo =, dockSide = } für n = 2–5
-- (vorhanden = offen); [1] trägt nur die Andock-Angabe von Fenster 1. Breite/Höhe der Fenster 2–5
-- liegen in dmWidthN/dmHeightN (der Bearbeitungsmodus braucht einfache Schlüssel), die Position in
-- positions.damagemeterN. Angedockte Fenster haben keine gespeicherte Position.
-- Das alte zweite Fenster (dm2Show, dm2Mode, dm2Width, dm2Height, dm2Dock) wird beim Anmelden
-- Fenster 2.
--
-- Aktualisiert wird ereignisbasiert (zusammengefasst) und im Kampf zusätzlich etwa alle 0,5 s –
-- alle Fenster gemeinsam, mit höchstens einer Abfrage je Ansicht und Modus.
-- Die Ereignisse sind nur registriert, solange die passende Option an ist.

local _, ns = ...
local L = ns.L

local IsSecret = ns.IsSecret

local MAX_WINDOWS = 5

-- Liste der Fenster (siehe oben); Größen der Fenster 2–5
ns.defaults.dmWindows = {}
for n = 2, MAX_WINDOWS do
    ns.defaults["dmWidth" .. n] = 230
    ns.defaults["dmHeight" .. n] = 190
end

local DM = C_DamageMeter
local SESSION_TYPE = Enum and Enum.DamageMeterSessionType
local METER_TYPE = Enum and Enum.DamageMeterType

local HAS_API = (type(DM) == "table" and DM.GetCombatSessionFromType and type(SESSION_TYPE) == "table"
    and type(METER_TYPE) == "table") and true or false
local HAS_RESET = HAS_API and DM.ResetAllCombatSessions and true or false
local NO_API = L["Diese Spielversion hat keinen eingebauten Schadensmesser."]

local function ApiAvailable() return HAS_API end

---------------------------------------------------------------------------
-- Maße, Farben, Schrift (wie das stray-Fenster)
---------------------------------------------------------------------------

-- Design „Variante 1 – flach wie die Gruppenrahmen“ (Leon 07.11.2026)
local DEFAULT_W, DEFAULT_H = 230, 190
local MIN_W, MIN_H, MAX_W, MAX_H = 160, 80, 600, 500
local MAX_ROWS = 20 -- höchstens so viele Balken, egal wie hoch das Fenster ist
local ROW_H = 18
local ROW_GAP = 2
local HEADER_H = 20 -- Kopfzeile (Titel, S | H, Zurücksetzen); darunter 1 px Linie
local TOP_H = HEADER_H + 1 + 3 -- bis zum ersten Balken
local BOTTOM_PAD = 14 -- Platz für den Ziehgriff unten rechts, damit er keinen Wert verdeckt
local SIDE_PAD = 4
local MAX_SESSIONS = 10
local SNAP = 12 -- Andocken: so nah (in Pixeln) müssen die Kanten beim Loslassen sein

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BODY = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local RESET_ICON = "Interface\\Buttons\\UI-RefreshButton"
local GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
local GRIP_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"

-- stray-Farben (ns.Colors aus stray.lua; Ersatz mit gleichen Werten, falls die Tabelle fehlt)
local COLORS = ns.Colors or {
    bg = { 0.078, 0.078, 0.098, 0.96 }, card = { 0.094, 0.094, 0.118, 1 }, hover = { 0.122, 0.122, 0.153, 1 },
    line = { 0.149, 0.149, 0.184, 1 }, accent = { 0.545, 0.486, 0.965, 1 }, accentText = { 0.702, 0.659, 0.980, 1 },
    text = { 0.902, 0.902, 0.925, 1 }, textDim = { 0.545, 0.545, 0.600, 1 }, textFaint = { 0.369, 0.369, 0.420, 1 },
}

local C = {
    bg         = { COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.85 }, -- etwas durchsichtig, liegt im Kampf über der Welt
    barBg      = COLORS.hover,
    border     = COLORS.line,
    accent     = COLORS.accent,
    accentText = COLORS.accentText,
    text       = COLORS.text,
    textDim    = COLORS.textDim,
    textSide   = COLORS.textDim,
    menuBg     = COLORS.card,
}

-- Deutsche Schlüssel, übersetzt wird beim Anzeigen
local MODE_LABEL = { damage = "Schaden", healing = "Heilung" }

---------------------------------------------------------------------------
-- Kleine Bausteine
---------------------------------------------------------------------------

-- Stil „forever“ (Forever UI): alles hinter FX.On(); im Stil „stray“ bleibt alles wie bisher.
-- Fenster 1 entsteht beim Laden der Datei (Einstellungen noch nicht da), daher wird der Stil
-- dort nachträglich in win.StyleForever (PLAYER_LOGIN) aufgesetzt; spätere Fenster direkt.
local FX = {}

function FX.On()
    local S = ns.Style
    if not (S and S.IsForever) then return false end
    local ok, v = pcall(S.IsForever)
    return ok and v == true
end

function FX.Font()
    if FX.On() then
        local ok, f = pcall(ns.Style.Font)
        if ok and type(f) == "string" then return f end
    end
    return FONT_BODY
end

local function Border(frame, c, layer, sub)
    local lines = {}
    local function Edge(p1, p2, horizontal)
        local t = frame:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        lines[#lines + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    return lines
end

local function Text(parent, size, c, font, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or FX.Font(), size, flags or "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Schrift mit Schatten (wie die Namen der Gruppenrahmen)
local function ShadowText(parent, size, c, font)
    local fs = Text(parent, size, c, font or FONT_BODY)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    return fs
end

-- Kompakter Buchstaben-Knopf für den Umschalter S | H; aktiv = Akzent-Lila.
-- letter ist der deutsche Schlüssel, übersetzt wird beim Anzeigen (SetActive)
local function LetterButton(parent, letter)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 16)
    b.text = Text(b, 12, C.textSide, FONT_BODY)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(L[letter])
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(C.barBg[1], C.barBg[2], C.barBg[3], 1)
    b.hover = hover
    function b:SetActive(on)
        local c = on and C.accentText or C.textSide
        self.text:SetText(L[letter])
        self.text:SetTextColor(c[1], c[2], c[3], 1)
    end
    return b
end

-- Klassenfarbe, abgedunkelt wie die Gruppenrahmen („Helligkeit der Balken“, Standard 60 %)
local function BarColor(class)
    local f = tonumber(ns.db and ns.db.partyBrightness) or 60
    f = math.max(0, math.min(100, f)) / 100
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r * f, color.g * f, color.b * f end
    return 0.5 * f, 0.5 * f, 0.5 * f
end

local function Clamp(v, lo, hi, default)
    v = tonumber(v)
    if not v then return default end
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

local function Click()
    ns.Sound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

---------------------------------------------------------------------------
-- Zahlen und Zeiten (nur für lesbare Werte!)
---------------------------------------------------------------------------

-- 12300 → „12,3K“, 1234567 → „1,2M“
local function Short(n)
    local s
    if n >= 1e6 then
        s = ("%.1fM"):format(n / 1e6)
    elseif n >= 1e5 then
        s = ("%.0fK"):format(n / 1e3)
    elseif n >= 1e3 then
        s = ("%.1fK"):format(n / 1e3)
    else
        s = ("%.0f"):format(n)
    end
    return (s:gsub("%.", ","))
end

local function FormatDuration(seconds)
    local s = math.floor(seconds + 0.5)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- Lesbare Zahl? (versiegelt → nein, ohne den Wert anzufassen)
local function PlainNumber(v)
    return not IsSecret(v) and type(v) == "number"
end

-- Ist der Wert vorhanden (lesbare Zahl oder versiegelt)?
local function HasValue(v)
    return IsSecret(v) or type(v) == "number"
end

---------------------------------------------------------------------------
-- Einmaliger Hinweis, falls die Anzeige im Kampf nicht klappt
---------------------------------------------------------------------------

local noticeShown = false

local function NoticeLocked()
    if noticeShown then return end
    noticeShown = true
    ns.Print(L["WoW Forever lässt die Werte des DMG-Meters hier gerade nicht anzeigen – stray versucht es weiter, spätestens nach dem Kampf klappt es wieder."])
end

---------------------------------------------------------------------------
-- Takt: ereignisbasiert zusammengefasst, im Kampf zusätzlich etwa alle 0,5 s
-- (gemeinsam für beide Fenster)
---------------------------------------------------------------------------

local Flush -- unten definiert

local driver = CreateFrame("Frame")
driver:Hide()
local sinceRun, pending, inCombat = 0, false, false

driver:SetScript("OnUpdate", function(self, delta)
    sinceRun = sinceRun + delta
    local showOn = ns.db and ns.db.dmShow
    if not (pending or (inCombat and showOn)) then
        self:Hide()
        return
    end
    -- Im Kampf höchstens alle 0,5 s, sonst Ereignisse 0,1 s lang sammeln
    if sinceRun < (inCombat and 0.5 or 0.1) then return end
    pending = false
    sinceRun = 0
    Flush()
end)

local function Request()
    pending = true
    driver:Show()
end

---------------------------------------------------------------------------
-- Daten: "overall", "current" oder eine sessionID (einzelner Kampf)
---------------------------------------------------------------------------

local function MeterTypeFor(mode)
    if mode == "healing" then return METER_TYPE.HealingDone end
    return METER_TYPE.DamageDone
end

-- Lesbare, nicht leere Zeichenkette aus einem der Felder, sonst nil
local function PlainString(t, ...)
    for i = 1, select("#", ...) do
        local v = t[select(i, ...)]
        if not IsSecret(v) and type(v) == "string" and v ~= "" then return v end
    end
    return nil
end

-- Einzelne Kämpfe, neueste zuerst: { id, label (mit Dauer), short (ohne Dauer) }
local function SessionList()
    local out = {}
    if not (HAS_API and DM.GetAvailableCombatSessions) then return out end
    local ok, list = pcall(DM.GetAvailableCombatSessions)
    if not ok or IsSecret(list) or type(list) ~= "table" then return out end
    for i, s in ipairs(list) do
        if type(s) == "table" then
            local id = s.sessionID
            -- Versiegelte oder fehlende ID: nicht wählbar, still überspringen
            if not IsSecret(id) and (type(id) == "number" or type(id) == "string") then
                local short = PlainString(s, "name", "sessionName") or L("Kampf %d", i)
                local label = short
                local duration = s.durationSeconds
                if PlainNumber(duration) then
                    label = label .. " – " .. FormatDuration(duration)
                end
                table.insert(out, 1, { id = id, label = label, short = short })
            end
        end
    end
    while #out > MAX_SESSIONS do table.remove(out) end
    return out
end

-- Daten einer Ansicht holen. Gibt die Sitzung (Tabelle oder nil) zurück und true, wenn der
-- gewählte einzelne Kampf nicht mehr existiert (z. B. nach dem Zurücksetzen).
local function FetchSession(view, mode)
    local meterType = MeterTypeFor(mode)
    if meterType == nil then return nil, false end
    if view ~= "overall" and view ~= "current" then
        if DM.GetCombatSessionFromID then
            local ok, session = pcall(DM.GetCombatSessionFromID, view, meterType)
            if ok and type(session) == "table" then return session, false end
        end
        return nil, true
    end
    local sessionType = (view == "current") and SESSION_TYPE.Current or SESSION_TYPE.Overall
    if sessionType == nil then return nil, false end
    local ok, session = pcall(DM.GetCombatSessionFromType, sessionType, meterType)
    if ok and type(session) == "table" then return session, false end
    return nil, false
end

-- Einträge sammeln. Gibt Einträge und Höchstwert (evtl. versiegelt) zurück.
-- Alles lesbar: nach Gesamtwert sortiert; sonst Blizzards Reihenfolge.
local function Collect(session)
    local entries = {}
    if type(session) ~= "table" then return entries, nil end
    local sources = session.combatSources
    if IsSecret(sources) or type(sources) ~= "table" then return entries, nil end

    local anySecret = false
    for _, src in ipairs(sources) do
        if type(src) == "table" then
            local total = src.totalAmount
            local secret = IsSecret(total)
            if secret or (type(total) == "number" and total > 0) then
                if secret then anySecret = true end
                local me = src.isLocalPlayer
                if IsSecret(me) then me = false end
                entries[#entries + 1] = {
                    name = src.name,
                    class = ns.Public(src.classFilename),
                    total = total,
                    perSec = src.amountPerSecond,
                    me = (me == true),
                }
            end
        end
    end

    if not anySecret then
        table.sort(entries, function(a, b) return a.total > b.total end)
        return entries, entries[1] and entries[1].total or nil
    end

    -- Versiegelt: Blizzards Höchstwert nehmen, sonst den ersten Eintrag (wird nur weitergereicht)
    local max = session.maxAmount
    if not (IsSecret(max) or (type(max) == "number" and max > 0)) then
        max = entries[1] and entries[1].total
    end
    return entries, max
end

-- Eine Abfrage je Ansicht und Modus pro Aktualisierung; beide Fenster teilen sich das Ergebnis.
-- Der Schlüssel besteht nur aus lesbaren Werten (Ansicht ist nie versiegelt, siehe SessionList).
local function Query(cache, view, mode)
    local key = tostring(view) .. "|" .. mode
    local hit = cache[key]
    if hit then return hit end
    local session, gone = FetchSession(view, mode)
    local entries, max = Collect(session)
    hit = { entries = entries, max = max, gone = gone }
    cache[key] = hit
    return hit
end

local function DemoEntries(mode)
    local me = ns.Public(UnitName("player"))
    if type(me) ~= "string" then me = L["Du"] end
    local _, myClass = UnitClass("player")
    myClass = ns.Public(myClass)
    local list = {
        { name = L["Beispiel-Magier"], class = "MAGE", total = 48200, perSec = 402 },
        { name = me, class = myClass, total = 41500, perSec = 346, me = true },
        { name = L["Beispiel-Jäger"], class = "HUNTER", total = 36800, perSec = 307 },
        { name = L["Beispiel-Krieger"], class = "WARRIOR", total = 22100, perSec = 184 },
        { name = L["Beispiel-Priester"], class = "PRIEST", total = 9400, perSec = 78 },
    }
    if mode == "healing" then
        list = {
            { name = L["Beispiel-Priester"], class = "PRIEST", total = 52300, perSec = 436 },
            { name = L["Beispiel-Druide"], class = "DRUID", total = 28900, perSec = 241 },
            { name = me, class = myClass, total = 6100, perSec = 51, me = true },
        }
    end
    return list, list[1].total
end

---------------------------------------------------------------------------
-- Anzeige-Bausteine
---------------------------------------------------------------------------

-- „Gesamt (pro Sekunde/s)“ – lesbar selbst formatiert, versiegelt nur weitergereicht
local function SetAmountText(fs, total, perSec)
    local hasPerSec = HasValue(perSec)
    if PlainNumber(total) and (not hasPerSec or PlainNumber(perSec)) then
        if hasPerSec then
            fs:SetText(("%s (%s/s)"):format(Short(total), Short(perSec)))
        else
            fs:SetText(Short(total))
        end
        return true
    end
    if not HasValue(total) then return false end

    if AbbreviateNumbers then
        local okA, a = pcall(AbbreviateNumbers, total)
        if okA then
            if hasPerSec then
                local okB, b = pcall(AbbreviateNumbers, perSec)
                if okB and pcall(fs.SetFormattedText, fs, "%s (%s/s)", a, b) then return true end
            end
            if pcall(fs.SetFormattedText, fs, "%s", a) then return true end
        end
    end
    if hasPerSec and pcall(fs.SetFormattedText, fs, "%.0f (%.0f/s)", total, perSec) then return true end
    if pcall(fs.SetFormattedText, fs, "%.0f", total) then return true end
    return pcall(function() fs:SetText(string.format("%.0f", total)) end)
end

local function SetName(fs, name)
    if IsSecret(name) then
        if not pcall(fs.SetText, fs, name) then fs:SetText("?") end
        return
    end
    if type(name) ~= "string" or name == "" then
        fs:SetText("?")
        return
    end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and type(short) == "string" then name = short end
    end
    fs:SetText(name)
end

-- Gibt false zurück, wenn der Wert nicht anzeigbar war
local function FillRow(bar, entry, max)
    SetName(bar.name, entry.name)

    -- Flach in Klassenfarbe, abgedunkelt wie die Gruppenrahmen (Klasse ist nie versiegelt)
    bar:SetStatusBarColor(BarColor(entry.class))

    if not pcall(bar.SetMinMaxValues, bar, 0, max) then bar:SetMinMaxValues(0, 1) end
    if not pcall(bar.SetValue, bar, entry.total) then bar:SetValue(0) end

    bar.mark:SetShown(entry.me and true or false)

    return SetAmountText(bar.value, entry.total, entry.perSec)
end

local function ModeTooltip(owner, label)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(L[label], C.text[1], C.text[2], C.text[3]) -- label = deutscher Schlüssel
    GameTooltip:Show()
end

local MENU_ITEM_H = 18

---------------------------------------------------------------------------
-- Fensterliste und Andock-Daten (ns.db.dmWindows, siehe Kopf der Datei)
---------------------------------------------------------------------------

local windows = {} -- [n] = Fenster (nur gebaute; ein geschlossenes bleibt gebaut, aber versteckt)
local byFrame = {} -- [Frame] = Fenster
local OpenResetPopup, ApplyDock, Decide, AddWindow, CloseWindow, PublishInstances -- unten definiert

local function List()
    local db = ns.db
    if type(db.dmWindows) ~= "table" then db.dmWindows = {} end
    return db.dmWindows
end

-- Ist Fenster n offen? Fenster 1 ist immer da (an/aus über „DMG-Meter anzeigen“).
local function IsOpen(n)
    if n == 1 then return true end
    if not ns.db or type(n) ~= "number" or n < 2 or n > MAX_WINDOWS then return false end
    return type(List()[n]) == "table"
end

local function OpenCount()
    local c = 0
    for n = 1, MAX_WINDOWS do
        if IsOpen(n) then c = c + 1 end
    end
    return c
end

-- Andock-Angabe von Fenster n: Ziel-Fenster und Seite ("top" = n sitzt oben auf dem Ziel), sonst nil
local function GetDock(n)
    if not ns.db then return nil end
    local e = List()[n]
    if type(e) ~= "table" then return nil end
    local to, side = e.dockTo, e.dockSide
    if type(to) ~= "number" or to == n or not (side == "top" or side == "bottom") then return nil end
    return to, side
end

local function SetDock(n, to, side)
    local l = List()
    local e = l[n]
    if type(e) ~= "table" then
        if not to or n ~= 1 then return end -- Fenster 2–5 nur, wenn offen
        e = {}
        l[n] = e
    end
    e.dockTo = to
    e.dockSide = to and side or nil
    -- Fenster 1 hat in der Liste nur die Andock-Angabe
    if n == 1 and not to then l[1] = nil end
end

local function ModeOf(n)
    local m
    if n == 1 then
        m = ns.db and ns.db.dmMode
    elseif ns.db then
        local e = List()[n]
        m = type(e) == "table" and e.mode or nil
    end
    if m == "damage" or m == "healing" then return m end
    return "damage"
end

local function SetModeOf(n, mode)
    if mode ~= "damage" and mode ~= "healing" then return end
    if n == 1 then
        ns.db.dmMode = mode
    elseif IsOpen(n) then
        List()[n].mode = mode
    end
end

-- Welches Fenster hängt an Seite side von t? (ignore: dieses Fenster nicht mitzählen)
local function Dependent(t, side, ignore)
    for n = 1, MAX_WINDOWS do
        if n ~= ignore and IsOpen(n) then
            local to, s = GetDock(n)
            if to == t and s == side then return n end
        end
    end
    return nil
end

-- Ist Seite side von t frei? Belegt durch ein dort angedocktes Fenster oder durch t selbst
-- (oben angedockt belegt die eigene Unterkante, unten angedockt die eigene Oberkante).
local function SideFree(t, side, ignore)
    if Dependent(t, side, ignore) then return false end
    local _, s = GetDock(t)
    return not (s and s ~= side)
end

-- Hängt x (direkt oder über andere) an n, bewegt sich also mit n mit? (x == n zählt mit)
local function MovesWith(n, x)
    local cur, guard = x, 0
    while cur and guard <= MAX_WINDOWS do
        if cur == n then return true end
        cur = GetDock(cur)
        guard = guard + 1
    end
    return false
end

-- Unterstes nicht angedocktes Fenster der Kette (bestimmt Position und Breite)
local function RootOf(n)
    local cur, guard = n, 0
    while guard < MAX_WINDOWS do
        local to = GetDock(cur)
        if not to then break end
        cur, guard = to, guard + 1
    end
    return cur
end

-- Oberstes Fenster im Stapel über n
local function TopOf(n)
    local cur = n
    for _ = 1, MAX_WINDOWS do
        local up = Dependent(cur, "top")
        if up then
            cur = up
        else
            local to, side = GetDock(cur)
            if to and side == "bottom" then cur = to else break end
        end
    end
    return cur
end

-- Gespeicherte Liste prüfen: ungültige Einträge, Ringe und doppelt belegte Kanten entfernen
local function Sanitize()
    local l = List()
    for k, e in pairs(l) do
        if type(k) ~= "number" or k < 1 or k > MAX_WINDOWS or k ~= math.floor(k) or type(e) ~= "table" then
            l[k] = nil
        end
    end
    for n = 2, MAX_WINDOWS do
        local e = l[n]
        if e and e.mode ~= "damage" and e.mode ~= "healing" then e.mode = "damage" end
    end
    for n = 1, MAX_WINDOWS do
        local to = GetDock(n)
        if IsOpen(n) and to and (not IsOpen(to) or MovesWith(n, to)) then SetDock(n, nil) end
    end
    local used = {}
    for n = 1, MAX_WINDOWS do
        local to, side = GetDock(n)
        if to then
            local mine = n .. (side == "top" and "b" or "t")
            local theirs = to .. (side == "top" and "t" or "b")
            if used[mine] or used[theirs] then
                SetDock(n, nil)
            else
                used[mine], used[theirs] = true, true
            end
        end
    end
    if l[1] and not GetDock(1) then l[1] = nil end
end

-- Altes zweites Fenster (bis 0.22.x) wird Fenster 2
local LEGACY_KEYS = { "dm2Show", "dm2Mode", "dm2Width", "dm2Height", "dm2Dock" }

local function Migrate()
    local db = ns.db
    local l = List()
    if db.dm2Show == true then
        local e = { mode = (db.dm2Mode == "damage") and "damage" or "healing" }
        if db.dm2Dock == "top" or db.dm2Dock == "bottom" then
            e.dockTo, e.dockSide = 1, db.dm2Dock
        elseif type(db.positions) == "table" and db.positions.damagemeter2 == nil then
            e.dockTo, e.dockSide = 1, "top" -- früherer Standard: oben an Fenster 1
        end
        l[2] = e
        if type(db.dm2Width) == "number" then db.dmWidth2 = db.dm2Width end
        if type(db.dm2Height) == "number" then db.dmHeight2 = db.dm2Height end
    elseif db.dm2Show == false then
        l[2] = nil
    end
    for _, key in ipairs(LEGACY_KEYS) do db[key] = nil end
end

-- Lage eines Frames in UIParent-Einheiten (nil, wenn nicht lesbar)
local function Rect(f)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    local s, u = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (PlainNumber(l) and PlainNumber(r) and PlainNumber(t) and PlainNumber(b)
            and PlainNumber(s) and PlainNumber(u) and u > 0) then
        return nil
    end
    local k = s / u
    return l * k, r * k, t * k, b * k
end

-- Breite angedockter Fenster folgt der Wurzel; für Lösen und Bearbeitungsmodus mitschreiben
local function SyncWidths()
    for n = 1, MAX_WINDOWS do
        local w = windows[n]
        if w and IsOpen(n) and GetDock(n) then
            local root = windows[RootOf(n)]
            if root and root ~= w then ns.db[w.widthKey] = Clamp(ns.db[root.widthKey], MIN_W, MAX_W, DEFAULT_W) end
        end
    end
end

-- Forever: Balken auf dunkle Fläche (ns.Style.Fill "bar") mit dünnem Bronzerand; Klassenfarbe der
-- Füllung bleibt. Gibt true zurück, wenn der Stil aufgesetzt wurde.
function FX.Row(bar)
    if bar.fxDone then return true end
    local ok = pcall(function()
        local S = ns.Style
        local fill = S.Fill(bar, "bar")
        local c = ns.Colors.bronze or ns.Colors.line
        local rim = Border(bar, { c[1], c[2], c[3], 0.85 }, "OVERLAY", 1)
        bar.fxFill, bar.fxRim = fill, rim
        bar.bg:Hide()
        bar.name:SetFont(S.Font(), 11, "")
        bar.mark:SetDrawLayer("OVERLAY", 3)
        bar.mark:SetColorTexture(ns.Colors.accent[1], ns.Colors.accent[2], ns.Colors.accent[3], 1)
    end)
    if ok then bar.fxDone = true end
    return ok
end

---------------------------------------------------------------------------
-- Fabrik: ein Meterfenster mit eigenem Zustand (n = 1–5)
---------------------------------------------------------------------------

local function CreateMeter(n)
    local win = { n = n, view = "overall", viewLabel = nil }
    win.posKey = (n == 1) and "damagemeter" or ("damagemeter" .. n)
    win.widthKey = (n == 1) and "dmWidth" or ("dmWidth" .. n)
    win.heightKey = (n == 1) and "dmHeight" or ("dmHeight" .. n)
    local moving, sizing = false, false
    local manualSizing = false

    local main = CreateFrame("Frame", (n == 1) and "strayDamageMeter" or ("strayDamageMeter" .. n), UIParent)
    win.frame = main
    main:SetSize(DEFAULT_W, DEFAULT_H)
    main:SetFrameStrata("MEDIUM")
    main:Hide()

    local mainBg = main:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints()
    mainBg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    win.lines = Border(main, C.border)
    -- 2-px-lila Kante oben (wie die Bedrohungsliste)
    local topEdge = main:CreateTexture(nil, "ARTWORK")
    topEdge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    topEdge:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
    topEdge:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, 0)
    topEdge:SetHeight(2)

    -- 1-px-Linie unter der Kopfzeile
    local headerLine = main:CreateTexture(nil, "BORDER")
    headerLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    headerLine:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -HEADER_H)
    headerLine:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -HEADER_H)
    headerLine:SetHeight(1)

    -- Größe anwenden (Bearbeitungsmodus, Anmelden). Angedockt gilt die Breite für die ganze Kette.
    function win.ApplySize()
        if not ns.db then return end
        local w = Clamp(ns.db[win.widthKey], MIN_W, MAX_W, DEFAULT_W)
        local h = Clamp(ns.db[win.heightKey], MIN_H, MAX_H, DEFAULT_H)
        ns.db[win.widthKey], ns.db[win.heightKey] = w, h
        if GetDock(n) then
            main:SetHeight(h)
            local root = windows[RootOf(n)]
            if root and root ~= win then
                ns.db[root.widthKey] = w
                root.frame:SetWidth(w)
            end
        else
            main:SetSize(w, h)
        end
        SyncWidths()
    end

    ns.MakeMovable(main, win.posKey, { "BOTTOMRIGHT", "BOTTOMRIGHT", -260, 180 + (n - 1) * 210 })
    -- Breite/Höhe auch im Fenster des Bearbeitungsmodus (ab 0.22.0)
    ns.RegisterMovable(main, "DMG-Meter " .. n, nil, {
        widthKey = win.widthKey, heightKey = win.heightKey,
        widthMin = MIN_W, widthMax = MAX_W, heightMin = MIN_H, heightMax = MAX_H,
        onSize = function()
            if InCombatLockdown() then return end
            win.ApplySize()
        end,
    })

    -- Größe ziehen (unten rechts). Grenzen: neue API SetResizeBounds, sonst SetMinResize/SetMaxResize.
    main:SetResizable(true)
    if not pcall(main.SetResizeBounds, main, MIN_W, MIN_H, MAX_W, MAX_H) then
        if main.SetMinResize then pcall(main.SetMinResize, main, MIN_W, MIN_H) end
        if main.SetMaxResize then pcall(main.SetMaxResize, main, MAX_W, MAX_H) end
    end

    function win.Mode() return ModeOf(n) end

    function win.Docked()
        local _, side = GetDock(n)
        return side
    end

    -- Verschieben (Shift + ziehen) und Größenziehen schließen sich aus: Merker um die Skripte
    -- aus ns.MakeMovable legen. ForwardDrag holt sich die Skripte per GetScript, nutzt also diese.
    do
        local baseStart = main:GetScript("OnDragStart")
        local baseStop = main:GetScript("OnDragStop")
        main:SetScript("OnDragStart", function(self, ...)
            if sizing then return end
            if IsShiftKeyDown() then moving = true end
            if baseStart then baseStart(self, ...) end
        end)
        main:SetScript("OnDragStop", function(self, ...)
            if sizing then return end
            local wasMoving = moving
            moving = false
            -- Ohne Shift wurde nichts verschoben: keine (evtl. relative) Position speichern
            if not wasMoving then return end
            if baseStop then baseStop(self, ...) end
        end)
        -- Fenster verschwindet mitten im Verschieben: Merker nicht hängen lassen
        main:HookScript("OnHide", function(self)
            if moving then
                moving = false
                if baseStop then pcall(baseStop, self) end
            end
        end)
    end

    -- Ziehen an Knöpfen und Titel an das Fenster weiterreichen (Shift + ziehen)
    local function ForwardDrag(child)
        child:RegisterForDrag("LeftButton")
        child:SetScript("OnDragStart", function()
            local fn = main:GetScript("OnDragStart")
            if fn then fn(main) end
        end)
        child:SetScript("OnDragStop", function()
            local fn = main:GetScript("OnDragStop")
            if fn then fn(main) end
        end)
    end

    local function MainTooltip(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
        local a, t, d = C.accentText, C.text, C.textDim
        GameTooltip:SetText((n == 1) and L["DMG-Meter"] or L("DMG-Meter %d", n), a[1], a[2], a[3])
        GameTooltip:AddLine(L["Klick auf den Titel: Gesamt, aktueller Kampf oder ein einzelner Kampf."], t[1], t[2], t[3], true)
        GameTooltip:AddLine(L["Werte: gesamt (pro Sekunde). Die Daten kommen aus dem eingebauten Schadensmesser des Spiels."], d[1], d[2], d[3], true)
        GameTooltip:AddLine(L["S || H oben rechts: Schaden oder Heilung."], d[1], d[2], d[3], true)
        GameTooltip:AddLine(L["„+“ im Kopf: weiteres Fenster (bis zu 5), dockt oben an."], d[1], d[2], d[3], true)
        GameTooltip:AddLine(L["Shift + ziehen zum Verschieben"], d[1], d[2], d[3])
        GameTooltip:AddLine(L["An die Ober- oder Unterkante eines anderen DMG-Meters ziehen: andocken. Wegziehen löst es wieder."], d[1], d[2], d[3], true)
        if win.Docked() then
            GameTooltip:AddLine(L["Angedockt: Ziehgriff ändert nur die Höhe"], d[1], d[2], d[3])
        else
            GameTooltip:AddLine(L["Unten rechts ziehen: Größe ändern"], d[1], d[2], d[3])
        end
        GameTooltip:Show()
    end

    main:SetScript("OnEnter", function(self) MainTooltip(self) end)
    main:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Kopfzeile rechts: Schließen (nur Fenster 2–5), Zurücksetzen (Symbol), davor S | H und „+“
    local closeButton = CreateFrame("Button", nil, main)
    closeButton:SetSize(14, 16)
    closeButton.text = Text(closeButton, 14, C.textSide, FONT_BODY)
    closeButton.text:SetPoint("CENTER", closeButton, "CENTER", 0, 0)
    closeButton.text:SetJustifyH("CENTER")
    closeButton.text:SetText("×")
    local closeHover = closeButton:CreateTexture(nil, "HIGHLIGHT")
    closeHover:SetAllPoints()
    closeHover:SetColorTexture(C.barBg[1], C.barBg[2], C.barBg[3], 1)
    closeButton:Hide()

    local resetButton = CreateFrame("Button", nil, main)
    resetButton:SetSize(14, 14)
    resetButton:SetPoint("TOPRIGHT", main, "TOPRIGHT", -4, -3)
    resetButton.icon = resetButton:CreateTexture(nil, "ARTWORK")
    resetButton.icon:SetAllPoints()
    resetButton.text = Text(resetButton, 11, C.textSide, FONT)
    resetButton.text:SetPoint("CENTER", resetButton, "CENTER", 0, 0)
    resetButton.text:SetJustifyH("CENTER")
    resetButton.text:SetText("R")
    -- Symbol, falls die Textur da ist; sonst bleibt der Buchstabe „R“
    if resetButton.icon:SetTexture(RESET_ICON) == false then
        resetButton.icon:Hide()
    else
        resetButton.text:Hide()
    end
    local resetHover = resetButton:CreateTexture(nil, "HIGHLIGHT")
    resetHover:SetAllPoints()
    resetHover:SetColorTexture(C.barBg[1], C.barBg[2], C.barBg[3], 1)

    local healingButton = LetterButton(main, "H")
    healingButton:SetPoint("RIGHT", resetButton, "LEFT", -6, 0)
    local modeSeparator = Text(main, 11, C.textDim, FONT)
    modeSeparator:SetPoint("RIGHT", healingButton, "LEFT", 0, 0)
    modeSeparator:SetText("||") -- „||“ = ein sichtbarer Strich (| ist WoWs Steuerzeichen)
    local damageButton = LetterButton(main, "S")
    damageButton:SetPoint("RIGHT", modeSeparator, "LEFT", 0, 0)

    local plusButton = CreateFrame("Button", nil, main)
    plusButton:SetSize(14, 16)
    plusButton:SetPoint("RIGHT", damageButton, "LEFT", -6, 0)
    plusButton.text = Text(plusButton, 14, C.textSide, FONT_BODY)
    plusButton.text:SetPoint("CENTER", plusButton, "CENTER", 0, 0)
    plusButton.text:SetJustifyH("CENTER")
    plusButton.text:SetText("+")
    local plusHover = plusButton:CreateTexture(nil, "HIGHLIGHT")
    plusHover:SetAllPoints()
    plusHover:SetColorTexture(C.barBg[1], C.barBg[2], C.barBg[3], 1)

    ForwardDrag(damageButton)
    ForwardDrag(healingButton)
    ForwardDrag(resetButton)
    ForwardDrag(plusButton)
    ForwardDrag(closeButton)

    damageButton:SetScript("OnEnter", function(self) ModeTooltip(self, "Schaden anzeigen") end)
    damageButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    healingButton:SetScript("OnEnter", function(self) ModeTooltip(self, "Heilung anzeigen") end)
    healingButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Titel links (klickbar: Ansicht wählen)
    local titleButton = CreateFrame("Button", nil, main)
    titleButton:SetPoint("TOPLEFT", main, "TOPLEFT", 3, -2)
    titleButton:SetPoint("TOPRIGHT", plusButton, "TOPLEFT", -4, 0)
    titleButton:SetHeight(HEADER_H - 4)
    local titleHover = titleButton:CreateTexture(nil, "HIGHLIGHT")
    titleHover:SetAllPoints()
    titleHover:SetColorTexture(C.barBg[1], C.barBg[2], C.barBg[3], 0.6)
    local title = Text(titleButton, 12, C.accentText, FONT_BODY)
    title:SetShadowOffset(1, -1)
    title:SetPoint("LEFT", titleButton, "LEFT", 3, 0)
    title:SetPoint("RIGHT", titleButton, "RIGHT", -12, 0)
    local titleArrow = Text(titleButton, 10, C.textDim)
    titleArrow:SetPoint("RIGHT", titleButton, "RIGHT", -2, 0)
    titleArrow:SetText("v")
    ForwardDrag(titleButton)
    titleButton:SetScript("OnEnter", function(self) MainTooltip(self) end)
    titleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hinweistext, wenn keine Balken da sind
    local emptyText = Text(main, 11, C.textDim)
    emptyText:SetPoint("TOPLEFT", main, "TOPLEFT", SIDE_PAD + 2, -TOP_H - 2)
    emptyText:SetPoint("TOPRIGHT", main, "TOPRIGHT", -SIDE_PAD - 2, -TOP_H - 2)
    emptyText:Hide()

    -- Balken (Pool wächst bei Bedarf bis MAX_ROWS; Breite folgt dem Fenster über TOPLEFT/TOPRIGHT)
    local rows = {}

    local function NewRow(i)
        local bar = CreateFrame("StatusBar", nil, main)
        bar:SetHeight(ROW_H)
        local y = -TOP_H - (i - 1) * (ROW_H + ROW_GAP)
        bar:SetPoint("TOPLEFT", main, "TOPLEFT", SIDE_PAD, y)
        bar:SetPoint("TOPRIGHT", main, "TOPRIGHT", -SIDE_PAD, y)
        bar:SetStatusBarTexture(WHITE)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)

        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.bg:SetColorTexture(C.barBg[1], C.barBg[2], C.barBg[3], C.barBg[4])

        -- Eigene Zeile: 2 px lila Strich am linken Rand
        bar.mark = bar:CreateTexture(nil, "OVERLAY")
        bar.mark:SetPoint("TOPLEFT")
        bar.mark:SetPoint("BOTTOMLEFT")
        bar.mark:SetWidth(2)
        bar.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        bar.mark:Hide()

        bar.value = ShadowText(bar, 11, { 1, 1, 1, 1 })
        bar.value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.value:SetJustifyH("RIGHT")
        bar.name = ShadowText(bar, 11, { 1, 1, 1, 1 }, FX.Font())
        bar.name:SetPoint("LEFT", bar, "LEFT", 5, 0)
        bar.name:SetPoint("RIGHT", bar.value, "LEFT", -4, 0)
        bar:Hide()
        if win.forever then FX.Row(bar) end
        rows[i] = bar
        return bar
    end

    -- So viele Zeilen, wie in die aktuelle Höhe passen (mindestens 1, höchstens MAX_ROWS)
    local function VisibleRows()
        local h = main:GetHeight()
        if IsSecret(h) or type(h) ~= "number" then h = DEFAULT_H end
        local count = math.floor((h - TOP_H - BOTTOM_PAD + ROW_GAP) / (ROW_H + ROW_GAP))
        count = math.max(1, math.min(MAX_ROWS, count))
        for i = #rows + 1, count do NewRow(i) end
        return count
    end

    -- Ziehgriff unten rechts (oben angedockt: oben rechts, gespiegelt)
    local grip = CreateFrame("Button", nil, main)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(main:GetFrameLevel() + 10)
    grip:SetNormalTexture(GRIP_UP)
    grip:SetPushedTexture(GRIP_DOWN)
    grip:SetHighlightTexture(GRIP_HIGHLIGHT)
    -- Leicht zurückgenommen, damit er den Wert der untersten Zeile kaum verdeckt
    grip:SetAlpha(0.5)

    -- Griff, Schließen und Zurücksetzen passend zum Andock-Zustand setzen
    function win.LayoutGrip()
        local top = win.Docked() == "top"
        grip:ClearAllPoints()
        resetButton:ClearAllPoints()
        closeButton:ClearAllPoints()
        local x = top and -20 or -4
        if top then
            -- Unterkante hängt an einem anderen Fenster: Höhe wächst nach oben, Griff sitzt oben rechts
            grip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -1, -1)
        else
            grip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -1, 1)
        end
        if n > 1 then
            closeButton:SetPoint("TOPRIGHT", main, "TOPRIGHT", x, -2)
            closeButton:Show()
            resetButton:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)
        else
            closeButton:Hide()
            resetButton:SetPoint("TOPRIGHT", main, "TOPRIGHT", x, -3)
        end
        local textures = { grip:GetNormalTexture(), grip:GetPushedTexture(), grip:GetHighlightTexture() }
        for i = 1, 3 do
            local tex = textures[i]
            if tex then
                if top then tex:SetTexCoord(0, 1, 1, 0) else tex:SetTexCoord(0, 1, 0, 1) end
            end
        end
    end

    local function SaveSizeAndPosition()
        local w, h = main:GetSize()
        if not IsSecret(w) and not IsSecret(h) then
            -- Angedockt folgt die Breite der Wurzel; beim Lösen übernimmt das Fenster diese Breite
            if not win.Docked() then ns.db[win.widthKey] = Clamp(w, MIN_W, MAX_W, DEFAULT_W) end
            ns.db[win.heightKey] = Clamp(h, MIN_H, MAX_H, DEFAULT_H)
        end
        SyncWidths()
        -- Angedockt hängt die Position an einem anderen Fenster, nichts zu speichern
        if win.Docked() then return end
        -- Wie ns.MakeMovable beim Verschieben: Ankerpunkt nach StopMovingOrSizing übernehmen
        local point, _, relPoint, x, y = main:GetPoint()
        if point then ns.db.positions[win.posKey] = { point, relPoint, x, y } end
    end

    -- Angedockt nur die Höhe ändern: Mausweg selbst verfolgen (StartSizing würde die Anker lösen)
    local startY, startH, direction = 0, 0, 1
    local function ManualSizeUpdate()
        local _, y = GetCursorPosition()
        local scale = main:GetEffectiveScale()
        if not PlainNumber(y) or not PlainNumber(scale) or scale <= 0 then return end
        local h = startH + (y / scale - startY) * direction
        main:SetHeight(Clamp(h, MIN_H, MAX_H, DEFAULT_H))
    end

    local function StopSizing()
        if not sizing then return end
        sizing = false
        if manualSizing then
            manualSizing = false
            grip:SetScript("OnUpdate", nil)
        else
            main:StopMovingOrSizing()
        end
        if ns.db then SaveSizeAndPosition() end
    end

    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or moving or sizing or not ns.db then return end
        GameTooltip:Hide()
        local dock = win.Docked()
        if dock then
            local _, y = GetCursorPosition()
            local scale = main:GetEffectiveScale()
            local h = main:GetHeight()
            if not (PlainNumber(y) and PlainNumber(scale) and PlainNumber(h)) or scale <= 0 then return end
            startY, startH = y / scale, h
            -- oben angedockt: nach oben ziehen = höher; unten angedockt: nach unten ziehen = höher
            direction = (dock == "top") and 1 or -1
            sizing, manualSizing = true, true
            grip:SetScript("OnUpdate", ManualSizeUpdate)
        elseif pcall(main.StartSizing, main, "BOTTOMRIGHT") then
            sizing = true
        end
    end)
    grip:SetScript("OnMouseUp", function() StopSizing() end)
    grip:SetScript("OnHide", function() StopSizing() end)
    grip:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if sizing then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(win.Docked() and L["Ziehen: Höhe ändern"] or L["Ziehen: Größe ändern"], C.text[1], C.text[2], C.text[3])
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self)
        self:SetAlpha(0.5)
        GameTooltip:Hide()
    end)

    -- Größe geändert: Zeilenzahl neu bestimmen und neu zeichnen (zusammengefasst über Request)
    main:SetScript("OnSizeChanged", function() Request() end)

    -----------------------------------------------------------------------
    -- Auswahlmenü (Klick auf den Titel)
    -----------------------------------------------------------------------

    local menuName = (n == 1) and "strayDamageMeterMenu" or ("strayDamageMeterMenu" .. n)
    local menu = CreateFrame("Frame", menuName, main)
    win.menu = menu
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetWidth(180)
    menu:Hide()
    local menuBg = menu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints()
    menuBg:SetColorTexture(C.menuBg[1], C.menuBg[2], C.menuBg[3], C.menuBg[4])
    win.menuLines = Border(menu, C.border)
    if UISpecialFrames then table.insert(UISpecialFrames, menuName) end

    local menuItems = {}

    local function MenuItem(i)
        if menuItems[i] then return menuItems[i] end
        local b = CreateFrame("Button", nil, menu)
        b:SetHeight(MENU_ITEM_H)
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * MENU_ITEM_H)
        b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * MENU_ITEM_H)
        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(C.barBg[1], C.barBg[2], C.barBg[3], 1)
        b.text = Text(b, 11, C.text)
        b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
        b.text:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        b:SetScript("OnClick", function(self)
            if not self.view then return end
            Click()
            win.view, win.viewLabel = self.view, self.viewLabel
            menu:Hide()
            Request()
        end)
        menuItems[i] = b
        return b
    end

    local function BuildMenu()
        local items = {
            { label = L["Gesamt"], view = "overall" },
            { label = L["Aktueller Kampf"], view = "current" },
        }
        local sessions = SessionList()
        if #sessions == 0 then
            items[#items + 1] = { label = L["Keine einzelnen Kämpfe"] }
        else
            for _, s in ipairs(sessions) do
                items[#items + 1] = { label = s.label, view = s.id, viewLabel = s.short }
            end
        end
        for i, item in ipairs(items) do
            local b = MenuItem(i)
            b.view, b.viewLabel = item.view, item.viewLabel
            b.text:SetText(item.label)
            local c = C.text
            if not item.view then
                c = C.textDim
            elseif item.view == win.view then
                c = C.accentText
            end
            b.text:SetTextColor(c[1], c[2], c[3], 1)
            b:Show()
        end
        for i = #items + 1, #menuItems do menuItems[i]:Hide() end
        menu:SetHeight(8 + #items * MENU_ITEM_H)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", titleButton, "BOTTOMLEFT", 0, -2)
    end

    titleButton:SetScript("OnClick", function()
        Click()
        if menu:IsShown() then
            menu:Hide()
            return
        end
        if pcall(BuildMenu) then menu:Show() end
    end)

    -----------------------------------------------------------------------
    -- Knöpfe der Kopfzeile
    -----------------------------------------------------------------------

    resetButton:SetScript("OnClick", function()
        Click()
        menu:Hide()
        OpenResetPopup()
    end)
    resetButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Zurücksetzen"], C.accentText[1], C.accentText[2], C.accentText[3])
        GameTooltip:AddLine(L["Löscht alle Kämpfe in allen DMG-Meter-Fenstern – auch in Blizzards eigenem Schadensmesser. Geht nur außerhalb des Kampfes."], C.text[1], C.text[2], C.text[3], true)
        GameTooltip:Show()
    end)
    resetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    plusButton:SetScript("OnClick", function()
        Click()
        menu:Hide()
        GameTooltip:Hide()
        AddWindow(n)
    end)
    plusButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Weiteres Fenster"], C.accentText[1], C.accentText[2], C.accentText[3])
        GameTooltip:AddLine(L["Öffnet eine Kopie dieses Fensters (gleiche Größe, gleicher Modus) und dockt sie oben an. Bis zu 5 Fenster."], C.text[1], C.text[2], C.text[3], true)
        GameTooltip:Show()
    end)
    plusButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    closeButton:SetScript("OnClick", function()
        Click()
        GameTooltip:Hide()
        CloseWindow(n)
    end)
    closeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Fenster schließen"], C.accentText[1], C.accentText[2], C.accentText[3])
        GameTooltip:AddLine(L["Schließt dieses DMG-Meter-Fenster. Angedockte Fenster rücken nach."], C.text[1], C.text[2], C.text[3], true)
        GameTooltip:Show()
    end)
    closeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function SetMode(mode)
        Click()
        SetModeOf(n, mode)
        Request()
    end
    damageButton:SetScript("OnClick", function() SetMode("damage") end)
    healingButton:SetScript("OnClick", function() SetMode("healing") end)

    -----------------------------------------------------------------------
    -- Stil „forever“ (Entwurf W1): Bronze-Rahmen, Schiefer, Gold-Titel, Balken mit Bronzerand.
    -- Läuft einmal je Fenster; bei einem Fehler bleibt der Aufbau im Stil „stray“ stehen.
    -----------------------------------------------------------------------

    function win.StyleForever()
        if win.forever or not FX.On() then return end
        local S = ns.Style
        local made = {}
        local ok = pcall(function()
            -- Rahmen liegt 5 px außerhalb (nur ca. 3 px innen), Eckwinkel klein; unter den Knöpfen
            local deco = CreateFrame("Frame", nil, main)
            deco:SetPoint("TOPLEFT", main, "TOPLEFT", -5, 5)
            deco:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 5, -5)
            deco:SetFrameLevel(main:GetFrameLevel())
            made.deco = deco
            made.border = S.Border(deco, { size = 8, cornerSize = 16, cornerOffset = 3 })
            made.fill = S.Fill(main, "window")
            made.fill:SetAlpha(0.92)
            -- Auswahlmenü: Schiefer-Fläche, dünner Rahmen ohne Eckwinkel
            local mdeco = CreateFrame("Frame", nil, menu)
            mdeco:SetPoint("TOPLEFT", menu, "TOPLEFT", -3, 3)
            mdeco:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 3, -3)
            mdeco:SetFrameLevel(menu:GetFrameLevel())
            made.mdeco = mdeco
            made.mborder = S.Border(mdeco, { size = 6, corners = false })
            made.mfill = S.Fill(menu, "panel")
        end)
        if not ok then
            -- Rückfall auf den Aufbau im Stil „stray“
            if made.deco then made.deco:Hide() end
            if made.fill then made.fill:Hide() end
            if made.mdeco then made.mdeco:Hide() end
            if made.mfill then made.mfill:Hide() end
            return
        end
        win.forever = true
        mainBg:Hide()
        topEdge:Hide()
        for _, t in ipairs(win.lines) do t:Hide() end
        for _, t in ipairs(win.menuLines) do t:Hide() end
        menuBg:Hide()
        local Cs = ns.Colors
        local bronze = Cs.bronze or Cs.line
        headerLine:SetColorTexture(bronze[1], bronze[2], bronze[3], 0.9)

        -- Texte und Hover mit der Forever-Palette (beim Laden von Fenster 1 noch Stil-stray-Werte)
        local dim = Cs.textDim
        for _, fs in ipairs({ closeButton.text, resetButton.text, plusButton.text, modeSeparator, titleArrow, emptyText }) do
            fs:SetTextColor(dim[1], dim[2], dim[3], 1)
        end
        local h = Cs.hover
        for _, tex in ipairs({ closeHover, resetHover, plusHover, damageButton.hover, healingButton.hover }) do
            tex:SetColorTexture(h[1], h[2], h[3], 1)
        end
        titleHover:SetColorTexture(h[1], h[2], h[3], 0.6)
        emptyText:SetFont(S.Font(), 11, "")
        pcall(function()
            title:SetFont(S.FontTitle(), 12, "")
            local g = Cs.gold or Cs.accentText
            title:SetTextColor(g[1], g[2], g[3], 1)
            local bl = Cs.bronzeLight or Cs.text
            for _, tex in ipairs({ grip:GetNormalTexture(), grip:GetPushedTexture() }) do
                tex:SetVertexColor(bl[1], bl[2], bl[3], 1)
            end
            grip:SetAlpha(0.7)
        end)
        for i = 1, #rows do FX.Row(rows[i]) end
    end
    win.StyleForever()

    -----------------------------------------------------------------------
    -- Anzeige
    -----------------------------------------------------------------------

    local function ViewLabel()
        if win.view == "current" then return L["Aktueller Kampf"] end
        if win.view == "overall" then return L["Gesamt"] end
        return win.viewLabel or L["Kampf"]
    end

    function win.ShowEmpty(message)
        for i = 1, #rows do rows[i]:Hide() end
        emptyText:SetText(message)
        emptyText:Show()
    end

    function win.Hide()
        main:Hide()
        menu:Hide()
    end

    function win.Wanted()
        return (ns.db and ns.db.dmShow and HAS_API and IsOpen(n)) and true or false
    end

    local function UpdateHeader(mode, demo)
        local text = L[MODE_LABEL[mode] or "Schaden"] .. " – " .. ViewLabel()
        if demo then text = text .. " · " .. L["Beispiel"] end
        title:SetText(text)
        damageButton:SetActive(mode == "damage")
        healingButton:SetActive(mode == "healing")
        plusButton:SetShown(OpenCount() < MAX_WINDOWS)
        if HAS_RESET then
            resetButton:Enable()
            resetButton:SetAlpha(1)
        else
            resetButton:Disable()
            resetButton:SetAlpha(0.4)
        end
    end

    -- cache: gemeinsame Abfragen dieser Aktualisierung (siehe Query)
    function win.Update(cache)
        if not win.Wanted() then
            win.Hide()
            return
        end

        local mode = win.Mode()
        local data = Query(cache, win.view, mode)
        if data.gone then
            -- Kampf gibt es nicht mehr (z. B. nach dem Zurücksetzen): zurück zu Gesamt
            win.view, win.viewLabel = "overall", nil
            data = Query(cache, "overall", mode)
        end
        local entries, max = data.entries, data.max
        local demo = false
        if #entries == 0 and ns.IsConfigOpen() then
            entries, max = DemoEntries(mode)
            demo = true
        end

        UpdateHeader(mode, demo)
        main:Show()

        if #entries == 0 then
            win.ShowEmpty(L["Noch keine Daten."])
            return
        end

        emptyText:Hide()
        local shown = math.min(#entries, VisibleRows())
        local allOk = true
        for i = 1, #rows do
            local bar = rows[i]
            if i <= shown then
                if not FillRow(bar, entries[i], max) then allOk = false end
                bar:Show()
            else
                bar:Hide()
            end
        end
        if not allOk then
            NoticeLocked()
            win.ShowEmpty(L["Werte gerade nicht anzeigbar."])
        end
    end

    -- Beim Anmelden bzw. Öffnen: gespeicherte Werte prüfen, Größe und Position setzen
    function win.Restore()
        if n == 1 then
            local m = ns.db.dmMode
            if m ~= "damage" and m ~= "healing" then ns.db.dmMode = "damage" end
        end
        ns.db[win.widthKey] = Clamp(ns.db[win.widthKey], MIN_W, MAX_W, DEFAULT_W)
        ns.db[win.heightKey] = Clamp(ns.db[win.heightKey], MIN_H, MAX_H, DEFAULT_H)
        main:SetSize(ns.db[win.widthKey], ns.db[win.heightKey])
        ns.RestorePosition(main) -- der Haken unten dockt bei Bedarf an
    end

    -----------------------------------------------------------------------
    -- Andocken: eigene Methoden auf dem eigenen Fenster umhüllen (kein Blizzard-Rahmen).
    -- Erkannt wird das Andocken in StopMovingOrSizing – das rufen sowohl ns.MakeMovable
    -- (Shift + ziehen) als auch der Bearbeiten-Modus auf.
    -----------------------------------------------------------------------

    local baseStartMoving = main.StartMoving
    local baseStopMoving = main.StopMovingOrSizing
    local dragging = false

    main.StartMoving = function(self, ...)
        -- Angedockt: erst auf einen festen Punkt am Bildschirm setzen und lösen, dann frei ziehen
        if ns.db then
            local to, side = GetDock(n)
            if to then
                local l, b, w = self:GetLeft(), self:GetBottom(), self:GetWidth()
                if PlainNumber(l) and PlainNumber(b) and PlainNumber(w) then
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
                    self:SetWidth(w)
                end
                win.lastDock = { to, side }
                SetDock(n, nil)
                win.LayoutGrip()
            end
        end
        dragging = true
        return baseStartMoving(self, ...)
    end

    main.StopMovingOrSizing = function(self, ...)
        baseStopMoving(self, ...)
        if not dragging or not ns.db then return end
        dragging = false
        -- Im Bearbeiten-Modus entscheidet der Haken strayOnDragStop (nach Einrasten und Raster)
        if ns.editMode then return end
        -- Shift + ziehen: Andocken erst im nächsten Bild, denn ns.MakeMovable speichert danach
        -- noch die Position (lesbar, weil das Fenster dann noch am Bildschirm verankert ist).
        Decide(win, true)
    end

    -- Haken des Bearbeiten-Modus: läuft nach Einrasten, Raster und Speichern der Position
    main.strayOnDragStop = function()
        if ns.db then Decide(win, false) end
    end

    windows[n] = win
    byFrame[main] = win
    return win
end

---------------------------------------------------------------------------
-- Andocken: an Ober- oder Unterkante eines beliebigen anderen Fensters
--
-- Angedockt hängt ein Fenster mit zwei Ankern an seinem Ziel (links und rechts bündig). Damit
-- laufen Position und Breite von selbst mit – auch ganze Ketten, beim Verschieben im
-- Bearbeiten-Modus ebenso. Je Kante höchstens ein Fenster, keine Ringe.
---------------------------------------------------------------------------

local function ApplyAll()
    for n = 1, MAX_WINDOWS do
        local w = windows[n]
        if w and IsOpen(n) then ApplyDock(w) end
    end
end

-- Fenster an sein Ziel hängen (1 px Überlappung, damit die Ränder zu einer Linie werden)
ApplyDock = function(win)
    if not ns.db or not win then return end
    local n, f = win.n, win.frame
    local to, side = GetDock(n)
    local target = to and windows[to]
    if target and IsOpen(to) and not MovesWith(n, to) then
        local t = target.frame
        f:ClearAllPoints()
        if side == "top" then
            f:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 0, -1)
            f:SetPoint("BOTTOMRIGHT", t, "TOPRIGHT", 0, -1)
        else
            f:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, 1)
            f:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, 1)
        end
        f:SetHeight(Clamp(ns.db[win.heightKey], MIN_H, MAX_H, DEFAULT_H))
        -- Angedockte Fenster haben keine eigene Position (Rückgängig/Zurücksetzen docken neu an)
        ns.db.positions[win.posKey] = nil
        SyncWidths()
    elseif to then
        SetDock(n, nil) -- Ziel fehlt oder würde einen Ring bilden
    end
    win.LayoutGrip()
end

-- Liegt das Fenster gerade nah genug an einem anderen? Ergebnis Ziel und Seite oder nil.
-- Die eigene Andock-Angabe ist vorher gelöscht; mitlaufende Fenster zählen nicht als Ziel.
local function FindDock(win)
    local n = win.n
    local l2, r2, t2, b2 = Rect(win.frame)
    if not l2 then return nil end
    local bottomFree = not Dependent(n, "bottom")
    local topFree = not Dependent(n, "top")
    local best, bestSide, bestDist
    for m = 1, MAX_WINDOWS do
        local other = windows[m]
        if m ~= n and other and IsOpen(m) and other.frame:IsShown() and not MovesWith(n, m) then
            local l1, r1, t1, b1 = Rect(other.frame)
            -- Nur wenn sich die Fenster waagerecht überlappen
            if l1 and not (r2 < l1 or l2 > r1) then
                if bottomFree and SideFree(m, "top", n) then
                    local d = math.abs(b2 - t1)
                    if d < SNAP and (not bestDist or d < bestDist) then best, bestSide, bestDist = m, "top", d end
                end
                if topFree and SideFree(m, "bottom", n) then
                    local d = math.abs(t2 - b1)
                    if d < SNAP and (not bestDist or d < bestDist) then best, bestSide, bestDist = m, "bottom", d end
                end
            end
        end
    end
    return best, bestSide
end

-- Nach dem Loslassen entscheiden: andocken oder gelöst. later = Andocken erst im nächsten Bild.
Decide = function(win, later)
    local n, f = win.n, win.frame
    local old, oldSide = GetDock(n)
    if old then win.lastDock = { old, oldSide } end
    SetDock(n, nil)
    local to, side = FindDock(win)
    if not to then
        -- Gelöst: die aktuelle Breite wird die eigene Breite
        local w = f:GetWidth()
        if PlainNumber(w) then ns.db[win.widthKey] = Clamp(w, MIN_W, MAX_W, DEFAULT_W) end
        win.LayoutGrip()
        return
    end
    SetDock(n, to, side)
    if later and C_Timer and C_Timer.After then
        C_Timer.After(0, function() ApplyDock(win) end)
    else
        ApplyDock(win)
    end
end

-- Andocken versuchen, wenn die Kanten frei sind
local function TryDock(win, to, side)
    local n = win.n
    if type(to) ~= "number" or to == n or not IsOpen(to) or not windows[to] or MovesWith(n, to) then return false end
    if Dependent(n, (side == "top") and "bottom" or "top") or not SideFree(to, side, n) then return false end
    SetDock(n, to, side)
    ApplyDock(win)
    return true
end

-- Keine Position und nicht angedockt (Zurücksetzen, Rückgängig): an die letzte Andockstelle,
-- sonst oben auf den Stapel von Fenster 1 (früherer Standard des zweiten Fensters)
local function DefaultDock(win)
    local last = win.lastDock
    if last and TryDock(win, last[1], last[2]) then return end
    TryDock(win, TopOf(1), "top")
end

-- Nach jedem ns.RestorePosition (Anmelden, Zurücksetzen, Rückgängig, Verwerfen) neu andocken
hooksecurefunc(ns, "RestorePosition", function(frame)
    local win = byFrame[frame]
    if not win or not ns.db or not IsOpen(win.n) then return end
    local n = win.n
    if GetDock(n) then
        if ns.editMode and ns.db.positions[win.posKey] ~= nil then
            -- Rückgängig im Bearbeitungsmodus: an der gespeicherten Stelle lassen, danach entscheidet
            -- strayOnDragStop nach der Lage. Breite der bisherigen Kette übernehmen.
            local root = windows[RootOf(n)]
            local w = root and root.frame:GetWidth()
            if PlainNumber(w) then frame:SetWidth(w) end
            return
        end
        ApplyDock(win)
        return
    end
    if n > 1 and ns.db.positions[win.posKey] == nil then DefaultDock(win) end
    win.LayoutGrip()
end)

-- Fenster x vom Ziel lösen und an seiner jetzigen Stelle festhalten
local function MakeRoot(x)
    local w = windows[x]
    if not w then
        SetDock(x, nil)
        return
    end
    local f = w.frame
    local l, b, wd = f:GetLeft(), f:GetBottom(), f:GetWidth()
    SetDock(x, nil)
    if PlainNumber(l) and PlainNumber(b) then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
        if PlainNumber(wd) then
            f:SetWidth(wd)
            ns.db[w.widthKey] = Clamp(wd, MIN_W, MAX_W, DEFAULT_W)
        end
        ns.db.positions[w.posKey] = { "BOTTOMLEFT", "BOTTOMLEFT", l, b }
    end
    w.LayoutGrip()
end

-- „+“ an Fenster m: Kopie (Größe, Modus) im ersten freien Platz, oben an m angedockt.
-- Ist die Oberkante von m schon belegt, schiebt sich das neue Fenster dazwischen.
AddWindow = function(m)
    if not ns.db or not windows[m] or OpenCount() >= MAX_WINDOWS then return end
    local n
    for i = 2, MAX_WINDOWS do
        if not IsOpen(i) then n = i break end
    end
    if not n then return end
    local src = windows[m]
    List()[n] = { mode = src.Mode() }
    local win = windows[n] or CreateMeter(n)
    win.lastDock, win.view, win.viewLabel = nil, "overall", nil
    ns.db.positions[win.posKey] = nil
    if type(ns.db.scales) == "table" then ns.db.scales[win.posKey] = ns.db.scales[src.posKey] end
    local w, h = src.frame:GetWidth(), src.frame:GetHeight()
    ns.db[win.widthKey] = Clamp(PlainNumber(w) and w or ns.db[src.widthKey], MIN_W, MAX_W, DEFAULT_W)
    ns.db[win.heightKey] = Clamp(PlainNumber(h) and h or ns.db[src.heightKey], MIN_H, MAX_H, DEFAULT_H)

    local up = Dependent(m, "top")
    local to, side = GetDock(m)
    if up then
        SetDock(up, n, "top")
        SetDock(n, m, "top")
    elseif to and side == "bottom" then
        SetDock(n, to, "bottom")
        SetDock(m, n, "bottom")
    else
        SetDock(n, m, "top")
    end
    win.Restore()
    ApplyAll()
    PublishInstances()
    Request()
end

-- „ד an Fenster k (nicht Fenster 1): angedockte Fenster rücken nach
CloseWindow = function(k)
    if k == 1 or not IsOpen(k) or not ns.db then return end
    local to, side = GetDock(k)
    local up, down = Dependent(k, "top"), Dependent(k, "bottom")
    if to then
        -- An der freien Seite hängendes Fenster übernimmt den Platz am Ziel
        local j = (side == "top") and up or down
        if j then SetDock(j, to, side) end
    elseif up then
        MakeRoot(up)
        if down then SetDock(down, up, "bottom") end
    elseif down then
        MakeRoot(down)
    end
    List()[k] = nil
    local win = windows[k]
    if win then
        ns.db.positions[win.posKey] = nil
        if type(ns.db.scales) == "table" then ns.db.scales[win.posKey] = nil end
        win.lastDock = nil
        win.Hide()
    end
    ApplyAll()
    PublishInstances()
    Request()
end

---------------------------------------------------------------------------
-- Auswahl je Fenster (Auswahlliste im stray-Fenster, falls ui.lua sie anbietet)
---------------------------------------------------------------------------

local selectedWin = 1

local function GetSelected()
    if not IsOpen(selectedWin) then selectedWin = 1 end
    return selectedWin
end

local function SetSelected(id)
    id = tonumber(id)
    if id and IsOpen(id) then selectedWin = id end
end

PublishInstances = function()
    if type(ns.RegisterInstances) ~= "function" or not ns.db then return end
    local list = {}
    for n = 1, MAX_WINDOWS do
        if IsOpen(n) then list[#list + 1] = { id = n, label = L("DMG-Meter %d", n) } end
    end
    local ok, err = pcall(ns.RegisterInstances, "DMG-Meter", list, GetSelected, SetSelected)
    if not ok then geterrorhandler()(err) end
end

-- Im Bearbeitungsmodus angeklicktes Fenster wird das gewählte
local function OnEditSelect(arg)
    local key = ns.EditSelected
    if type(key) ~= "string" then key = arg end
    if type(key) ~= "string" then return end
    if key == "damagemeter" then
        SetSelected(1)
    else
        SetSelected(key:match("^damagemeter(%d)$"))
    end
end

Flush = function()
    local cache = {}
    for n = 1, MAX_WINDOWS do
        local win = windows[n]
        if win and not pcall(win.Update, cache) then
            NoticeLocked()
            pcall(win.ShowEmpty, L["Werte gerade nicht anzeigbar."])
        end
    end
end

-- Fenster 1 gleich beim Laden bauen (Name strayDamageMeter wie bisher), die übrigen beim Anmelden
CreateMeter(1)

---------------------------------------------------------------------------
-- Zurücksetzen (betrifft alle Fenster, die Daten sind dieselben)
---------------------------------------------------------------------------

local function ResetViews()
    for n = 1, MAX_WINDOWS do
        local win = windows[n]
        if win then
            win.view, win.viewLabel = "overall", nil
            win.menu:Hide()
        end
    end
end

-- auto = true: nach Verlassen einer Instanz (andere Chatzeile, keine Kampfmeldung)
local function DoReset(auto)
    if not HAS_RESET then return false end
    if InCombatLockdown() then
        if not auto then ns.Print(L["Zurücksetzen geht erst nach dem Kampf."]) end
        return false
    end
    if not pcall(DM.ResetAllCombatSessions) then
        ns.Print(L["Der DMG-Meter ließ sich nicht zurücksetzen."])
        return false
    end
    ResetViews()
    if auto then
        ns.Print(L["DMG-Meter zurückgesetzt (Instanz verlassen)."])
    else
        ns.Print(L["DMG-Meter zurückgesetzt."])
    end
    Request()
    return true
end

local RESET_TEXT = "Alle Kämpfe im DMG-Meter zurücksetzen?\n\nDas betrifft auch Blizzards eigenen Schadensmesser."

if StaticPopupDialogs then
    StaticPopupDialogs["STRAY_DAMAGEMETER_RESET"] = {
        text = L[RESET_TEXT],
        button1 = YES or L["Ja"],
        button2 = NO or L["Nein"],
        OnAccept = function() DoReset(false) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

OpenResetPopup = function()
    local dialog = StaticPopupDialogs and StaticPopupDialogs["STRAY_DAMAGEMETER_RESET"]
    if StaticPopup_Show and dialog then
        -- Text beim Anzeigen übersetzen (eigene Tabelle, gewählte Sprache)
        dialog.text = L[RESET_TEXT]
        if not YES then dialog.button1 = L["Ja"] end
        if not NO then dialog.button2 = L["Nein"] end
        StaticPopup_Show("STRAY_DAMAGEMETER_RESET")
    else
        DoReset(false)
    end
end

---------------------------------------------------------------------------
-- Nach Instanz zurücksetzen
---------------------------------------------------------------------------

local lastInstance = nil -- "party", "raid", "other" oder "none"

local function CurrentInstance()
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then return nil end
    inInstance, instanceType = ns.Public(inInstance), ns.Public(instanceType)
    if instanceType == "party" or instanceType == "raid" then return instanceType end
    if inInstance then return "other" end
    return "none"
end

local pendingAutoReset = false

local function CheckInstance()
    local now = CurrentInstance()
    if now == nil then return end
    local previous = lastInstance
    lastInstance = now
    if not (ns.db and ns.db.dmAutoReset) then return end
    if (previous == "party" or previous == "raid") and now == "none" then
        if InCombatLockdown() then
            -- Im Kampf gesperrt: nach dem Kampf nachholen
            pendingAutoReset = true
        elseif C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                -- Beginnt in dieser Sekunde ein Kampf: nach dem Kampf nachholen
                if not DoReset(true) then pendingAutoReset = true end
            end)
        else
            DoReset(true)
        end
    end
end

---------------------------------------------------------------------------
-- Ereignisse: nur registriert, solange die passende Option an ist
---------------------------------------------------------------------------

local SHOW_EVENTS = {
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
}
local RESET_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
}

local events = CreateFrame("Frame")
local registered = {} -- [Ereignis] = true

events:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_ENTERING_WORLD" then
        pcall(CheckInstance)
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if pendingAutoReset then
            pendingAutoReset = false
            if ns.db.dmAutoReset then pcall(DoReset, true) end
        end
    elseif event == "DAMAGE_METER_RESET" then
        for _, win in pairs(windows) do
            if win.view ~= "overall" and win.view ~= "current" then win.view, win.viewLabel = "overall", nil end
            win.menu:Hide()
        end
    end
    Request()
end)

local function RefreshEvents()
    local want = {}
    if HAS_API and ns.db then
        if ns.db.dmShow then
            for _, e in ipairs(SHOW_EVENTS) do want[e] = true end
        end
        if ns.db.dmAutoReset and HAS_RESET then
            for _, e in ipairs(RESET_EVENTS) do want[e] = true end
        end
    end
    local all = {}
    for _, e in ipairs(SHOW_EVENTS) do all[e] = true end
    for _, e in ipairs(RESET_EVENTS) do all[e] = true end
    for e in pairs(all) do
        local w = want[e] or false
        if w ~= (registered[e] or false) then
            if w then
                -- Unbekannte Ereignisse (andere Spielversion) dürfen nicht stören
                if pcall(events.RegisterEvent, events, e) then registered[e] = true end
            else
                pcall(events.UnregisterEvent, events, e)
                registered[e] = nil
            end
        end
    end
    if want.PLAYER_ENTERING_WORLD then
        -- Beim Einschalten den aktuellen Ort merken, damit „verlassen“ erkannt wird
        if lastInstance == nil then lastInstance = CurrentInstance() end
    else
        lastInstance, pendingAutoReset = nil, false
    end
    inCombat = InCombatLockdown() and true or false
    Request()
end


ns.OnConfig(function() Request() end)

ns.On("PLAYER_LOGIN", function()
    Migrate()
    Sanitize()
    -- Erst alle offenen Fenster bauen, dann Größe/Position setzen (Andocken braucht die Ziele)
    for n = 2, MAX_WINDOWS do
        if IsOpen(n) and not windows[n] then CreateMeter(n) end
    end
    for n = 1, MAX_WINDOWS do
        local win = windows[n]
        if win and IsOpen(n) then win.Restore() end
    end
    -- Fenster 1 entstand beim Laden der Datei: Stil „forever“ nachträglich aufsetzen
    for n = 1, MAX_WINDOWS do
        local win = windows[n]
        if win and win.StyleForever then win.StyleForever() end
    end
    ApplyAll()
    RefreshEvents()
    PublishInstances()
    if type(ns.OnEditSelect) == "function" then pcall(ns.OnEditSelect, OnEditSelect) end
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

local function Setter(key)
    return function(value)
        ns.db[key] = value
        RefreshEvents()
        if not value and key == "dmShow" then
            for _, win in pairs(windows) do win.Hide() end
        end
        Request()
    end
end

local function ShowEnabled()
    return HAS_API and ns.db and ns.db.dmShow and true or false
end

ns.AddOption(2, "DMG-Meter", {
    key = "dmShow",
    label = L["DMG-Meter anzeigen"],
    tooltip = L["Zeigt Schaden oder Heilung deiner Gruppe in einem eigenen Fenster. Balken mit Gesamtwert und Wert pro Sekunde in Klassenfarbe (so hell wie die Gruppenrahmen), dein eigener Balken hat links einen lila Strich. Wie viele Balken zu sehen sind, ergibt sich aus der Fenstergröße – unten rechts ziehen zum Ändern. Oben rechts schaltest du mit S || H zwischen Schaden und Heilung um; ein Klick auf den Titel wählt Gesamt, den aktuellen Kampf oder einen einzelnen Kampf. Die Werte kommen aus dem eingebauten Schadensmesser des Spiels.\n\nSolange das stray-Fenster offen ist und noch keine Daten da sind, zeigt das Fenster Beispielwerte – dann kannst du es mit Shift + linker Maustaste verschieben."],
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("dmShow"),
})

-- Ersetzt „Zweites Fenster“ (bis 0.22.x). Nicht im Profil: dort steht die Fensterliste selbst.
ns.AddOption(2, "DMG-Meter", {
    key = "dmWindowCount",
    type = "slider",
    min = 1, max = MAX_WINDOWS, step = 1,
    label = L["Anzahl Fenster"],
    tooltip = L["Wie viele DMG-Meter-Fenster offen sind (1–5). Weitere Fenster öffnest du auch mit „+“ im Kopf eines Fensters, schließen mit „ד. Ein neues Fenster ist eine Kopie (gleiche Größe, gleicher Modus) und dockt oben an. Mit Shift + ziehen oder im Bearbeitungsmodus löst du ein Fenster; an Ober- oder Unterkante eines anderen Fensters gezogen, dockt es wieder an. Angedockte Fenster wandern mit, angedockt änderst du nur die Höhe. Zurücksetzen gilt für alle Fenster."],
    keywords = { "fenster", "window", "windows", "anzahl", "count", "zweites", "second", "andocken", "dock", "damage", "meter" },
    noExport = true,
    isEnabled = ShowEnabled,
    disabledHint = L["Erst „DMG-Meter anzeigen“ einschalten (direkt darüber)."],
    get = function() return ns.db and OpenCount() or 1 end,
    set = function(value)
        if not ns.db then return end
        value = Clamp(value, 1, MAX_WINDOWS, 1)
        for _ = 1, MAX_WINDOWS do
            if OpenCount() >= value then break end
            AddWindow(TopOf(1))
        end
        for n = MAX_WINDOWS, 2, -1 do
            if OpenCount() <= value then break end
            if IsOpen(n) then CloseWindow(n) end
        end
        -- „Rückgängig“ schreibt die Fensterliste direkt zurück: fehlende Fenster bauen, Lage neu setzen
        for n = 2, MAX_WINDOWS do
            if IsOpen(n) and not windows[n] then CreateMeter(n).Restore() end
        end
        ApplyAll()
        PublishInstances()
        Request()
    end,
})

-- Modus des gewählten Fensters (Auswahlliste oben auf der Seite; ohne Auswahl Fenster 1)
ns.AddOption(2, "DMG-Meter", {
    key = "dmSelMode",
    type = "choice",
    values = { "damage", "healing" },
    labels = { L["Schaden"], L["Heilung"] },
    label = L["Modus"],
    tooltip = L["Schaden oder Heilung im gewählten DMG-Meter-Fenster – dasselbe wie S || H im Fenster selbst."],
    keywords = { "modus", "mode", "schaden", "damage", "heilung", "healing" },
    noExport = true,
    isEnabled = ShowEnabled,
    disabledHint = L["Erst „DMG-Meter anzeigen“ einschalten (direkt darüber)."],
    get = function() return ns.db and ModeOf(GetSelected()) or "damage" end,
    set = function(value)
        if not ns.db then return end
        SetModeOf(GetSelected(), value)
        Request()
    end,
})

ns.AddOption(2, "DMG-Meter", {
    key = "dmAutoReset",
    label = L["Nach Instanz zurücksetzen"],
    tooltip = L["Setzt den DMG-Meter zurück, sobald du einen Dungeon oder Schlachtzug verlässt. Im Chat erscheint dann eine kurze Meldung. Das betrifft auch Blizzards eigenen Schadensmesser, weil beide dieselben Daten nutzen."],
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("dmAutoReset"),
})
