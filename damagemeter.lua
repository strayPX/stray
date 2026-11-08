-- stray – DMG-Meter: eigene Fenster für Schaden und Heilung (gesamt, aktueller Kampf, einzelne Kämpfe)
--
-- Die Werte kommen aus Blizzards eingebautem Schadensmesser (C_DamageMeter), nicht aus dem Kampflog.
-- Im Kampf versiegelt WoW Forever Name, GUID, Gesamtwert und Wert pro Sekunde („secret values“).
-- Damit darf ein Addon nicht vergleichen, nicht rechnen, nicht testen und keine Tabellenschlüssel
-- bilden. Deshalb gilt hier überall: erst ns.IsSecret() prüfen; versiegelte Werte werden nur an
-- Anzeige-Funktionen (SetText, SetFormattedText, SetValue, SetMinMaxValues, AbbreviateNumbers)
-- weitergereicht – jeweils in pcall. Klassenname und „bin ich das“ sind nie versiegelt.
--
-- Es gibt bis zu zwei Fenster mit eigenem Modus, eigener Ansicht, Größe und Position. Beide baut
-- dieselbe Fabrik-Funktion (CreateMeter). Fenster 2 lässt sich an Ober- oder Unterkante von
-- Fenster 1 andocken und läuft dann mit (Position und Breite).
--
-- Aktualisiert wird ereignisbasiert (zusammengefasst) und im Kampf zusätzlich etwa alle 0,5 s –
-- beide Fenster gemeinsam, mit höchstens einer Abfrage je Ansicht und Modus.
-- Die Ereignisse sind nur registriert, solange die passende Option an ist.

local _, ns = ...

local IsSecret = ns.IsSecret

-- Zweites Fenster (Fenster 1 nutzt weiter dmMode, dmWidth, dmHeight und positions.damagemeter)
ns.defaults.dm2Show = false
ns.defaults.dm2Mode = "healing"
ns.defaults.dm2Width = 230
ns.defaults.dm2Height = 190
-- dm2Dock ("top", "bottom" oder nil) hat bewusst keinen Standardwert: nil heißt „nicht angedockt“.

local DM = C_DamageMeter
local SESSION_TYPE = Enum and Enum.DamageMeterSessionType
local METER_TYPE = Enum and Enum.DamageMeterType

local HAS_API = (type(DM) == "table" and DM.GetCombatSessionFromType and type(SESSION_TYPE) == "table"
    and type(METER_TYPE) == "table") and true or false
local HAS_RESET = HAS_API and DM.ResetAllCombatSessions and true or false
local NO_API = "Diese Spielversion hat keinen eingebauten Schadensmesser."

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

local C = {
    bg       = { 0.051, 0.067, 0.090, 0.75 }, -- wie die Kacheln der Gruppenrahmen
    barBg    = { 0.110, 0.122, 0.149, 0.8 },  -- wie der Lebensbalken-Hintergrund
    border   = { 0.169, 0.290, 0.451, 1 },
    accent   = { 0.353, 0.659, 1.000, 1 },
    text     = { 0.890, 0.914, 0.953, 1 },
    textDim  = { 0.435, 0.525, 0.651, 1 },
    textSide = { 0.682, 0.733, 0.816, 1 },
    menuBg   = { 0.067, 0.102, 0.157, 0.97 },
}

local MODE_LABEL = { damage = "Schaden", healing = "Heilung" }

---------------------------------------------------------------------------
-- Kleine Bausteine
---------------------------------------------------------------------------

local function Border(frame, c)
    local lines = {}
    local function Edge(p1, p2, horizontal)
        local t = frame:CreateTexture(nil, "BORDER")
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
    fs:SetFont(font or FONT_BODY, size, flags or "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Schrift mit Schatten (wie die Namen der Gruppenrahmen)
local function ShadowText(parent, size, c)
    local fs = Text(parent, size, c, FONT_BODY)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    return fs
end

-- Kompakter Buchstaben-Knopf für den Umschalter S | H; aktiv = Akzentblau
local function LetterButton(parent, letter)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 16)
    b.text = Text(b, 12, C.textSide, FONT)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(letter)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)
    function b:SetActive(on)
        local c = on and C.accent or C.textSide
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
    ns.Print("WoW Forever lässt die Werte des DMG-Meters hier gerade nicht anzeigen – stray versucht es weiter, spätestens nach dem Kampf klappt es wieder.")
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
                local short = PlainString(s, "name", "sessionName") or ("Kampf %d"):format(i)
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
    if type(me) ~= "string" then me = "Du" end
    local _, myClass = UnitClass("player")
    myClass = ns.Public(myClass)
    local list = {
        { name = "Beispiel-Magier", class = "MAGE", total = 48200, perSec = 402 },
        { name = me, class = myClass, total = 41500, perSec = 346, me = true },
        { name = "Beispiel-Jäger", class = "HUNTER", total = 36800, perSec = 307 },
        { name = "Beispiel-Krieger", class = "WARRIOR", total = 22100, perSec = 184 },
        { name = "Beispiel-Priester", class = "PRIEST", total = 9400, perSec = 78 },
    }
    if mode == "healing" then
        list = {
            { name = "Beispiel-Priester", class = "PRIEST", total = 52300, perSec = 436 },
            { name = "Beispiel-Druide", class = "DRUID", total = 28900, perSec = 241 },
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
    GameTooltip:SetText(label, 1, 1, 1)
    GameTooltip:Show()
end

local MENU_ITEM_H = 18

-- Andock-Zustand von Fenster 2: "top", "bottom" oder nil
local function DockState()
    local d = ns.db and ns.db.dm2Dock
    if d == "top" or d == "bottom" then return d end
    return nil
end

local windows = {}
local OpenResetPopup -- unten definiert

---------------------------------------------------------------------------
-- Fabrik: ein Meterfenster mit eigenem Zustand
--
-- cfg: name, menuName, posKey, label, defaultPoint, modeKey, defaultMode, widthKey, heightKey,
--      showKey (zusätzlicher Schalter, nur Fenster 2), dockable (nur Fenster 2)
---------------------------------------------------------------------------

local function CreateMeter(cfg)
    local win = { cfg = cfg, view = "overall", viewLabel = nil }
    local moving, sizing = false, false
    local manualSizing = false

    local main = CreateFrame("Frame", cfg.name, UIParent)
    win.frame = main
    main:SetSize(DEFAULT_W, DEFAULT_H)
    main:SetFrameStrata("MEDIUM")
    main:Hide()

    local mainBg = main:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints()
    mainBg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    Border(main, C.border)

    -- 1-px-Linie unter der Kopfzeile
    local headerLine = main:CreateTexture(nil, "BORDER")
    headerLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    headerLine:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -HEADER_H)
    headerLine:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -HEADER_H)
    headerLine:SetHeight(1)

    ns.MakeMovable(main, cfg.posKey, cfg.defaultPoint)
    -- Breite/Höhe auch im Fenster des Bearbeitungsmodus (ab 0.22.0)
    ns.RegisterMovable(main, cfg.label, nil, {
        widthKey = cfg.widthKey, heightKey = cfg.heightKey,
        widthMin = MIN_W, widthMax = MAX_W, heightMin = MIN_H, heightMax = MAX_H,
        onSize = function()
            if InCombatLockdown() then return end
            main:SetSize(ns.db[cfg.widthKey] or DEFAULT_W, ns.db[cfg.heightKey] or DEFAULT_H)
        end,
    })

    -- Größe ziehen (unten rechts). Grenzen: neue API SetResizeBounds, sonst SetMinResize/SetMaxResize.
    main:SetResizable(true)
    if not pcall(main.SetResizeBounds, main, MIN_W, MIN_H, MAX_W, MAX_H) then
        if main.SetMinResize then pcall(main.SetMinResize, main, MIN_W, MIN_H) end
        if main.SetMaxResize then pcall(main.SetMaxResize, main, MAX_W, MAX_H) end
    end

    function win.Mode()
        local m = ns.db and ns.db[cfg.modeKey]
        if m == "damage" or m == "healing" then return m end
        return cfg.defaultMode
    end

    function win.Docked()
        if not cfg.dockable then return nil end
        return DockState()
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
        GameTooltip:SetText(cfg.label, 1, 1, 1)
        GameTooltip:AddLine("Klick auf den Titel: Gesamt, aktueller Kampf oder ein einzelner Kampf.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
        GameTooltip:AddLine("Werte: gesamt (pro Sekunde). Die Daten kommen aus dem eingebauten Schadensmesser des Spiels.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("S || H oben rechts: Schaden oder Heilung.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Shift + ziehen zum Verschieben", 0.5, 0.5, 0.5)
        if cfg.dockable then
            GameTooltip:AddLine("An die Ober- oder Unterkante des ersten DMG-Meters ziehen: andocken. Wegziehen löst es wieder.", 0.5, 0.5, 0.5, true)
            if win.Docked() then
                GameTooltip:AddLine("Angedockt: Ziehgriff ändert nur die Höhe", 0.5, 0.5, 0.5)
            else
                GameTooltip:AddLine("Unten rechts ziehen: Größe ändern", 0.5, 0.5, 0.5)
            end
        else
            GameTooltip:AddLine("Unten rechts ziehen: Größe ändern", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end

    main:SetScript("OnEnter", function(self) MainTooltip(self) end)
    main:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Kopfzeile rechts: Zurücksetzen (Symbol), davor der Umschalter S | H
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
    resetHover:SetColorTexture(1, 1, 1, 0.12)

    local healingButton = LetterButton(main, "H")
    healingButton:SetPoint("RIGHT", resetButton, "LEFT", -6, 0)
    local modeSeparator = Text(main, 11, C.textDim, FONT)
    modeSeparator:SetPoint("RIGHT", healingButton, "LEFT", 0, 0)
    modeSeparator:SetText("||") -- „||“ = ein sichtbarer Strich (| ist WoWs Steuerzeichen)
    local damageButton = LetterButton(main, "S")
    damageButton:SetPoint("RIGHT", modeSeparator, "LEFT", 0, 0)
    ForwardDrag(damageButton)
    ForwardDrag(healingButton)
    ForwardDrag(resetButton)

    damageButton:SetScript("OnEnter", function(self) ModeTooltip(self, "Schaden anzeigen") end)
    damageButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    healingButton:SetScript("OnEnter", function(self) ModeTooltip(self, "Heilung anzeigen") end)
    healingButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Titel links (klickbar: Ansicht wählen)
    local titleButton = CreateFrame("Button", nil, main)
    titleButton:SetPoint("TOPLEFT", main, "TOPLEFT", 3, -2)
    titleButton:SetPoint("TOPRIGHT", damageButton, "TOPLEFT", -4, 0)
    titleButton:SetHeight(HEADER_H - 4)
    local titleHover = titleButton:CreateTexture(nil, "HIGHLIGHT")
    titleHover:SetAllPoints()
    titleHover:SetColorTexture(1, 1, 1, 0.06)
    local title = Text(titleButton, 12, C.text, FONT)
    title:SetPoint("LEFT", titleButton, "LEFT", 3, 0)
    title:SetPoint("RIGHT", titleButton, "RIGHT", -12, 0)
    local titleArrow = Text(titleButton, 10, C.accent)
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

        -- Eigene Zeile: 2 px blauer Strich am linken Rand
        bar.mark = bar:CreateTexture(nil, "OVERLAY")
        bar.mark:SetPoint("TOPLEFT")
        bar.mark:SetPoint("BOTTOMLEFT")
        bar.mark:SetWidth(2)
        bar.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        bar.mark:Hide()

        bar.value = ShadowText(bar, 11, { 1, 1, 1, 1 })
        bar.value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.value:SetJustifyH("RIGHT")
        bar.name = ShadowText(bar, 11, { 1, 1, 1, 1 })
        bar.name:SetPoint("LEFT", bar, "LEFT", 5, 0)
        bar.name:SetPoint("RIGHT", bar.value, "LEFT", -4, 0)
        bar:Hide()
        rows[i] = bar
        return bar
    end

    -- So viele Zeilen, wie in die aktuelle Höhe passen (mindestens 1, höchstens MAX_ROWS)
    local function VisibleRows()
        local h = main:GetHeight()
        if IsSecret(h) or type(h) ~= "number" then h = DEFAULT_H end
        local n = math.floor((h - TOP_H - BOTTOM_PAD + ROW_GAP) / (ROW_H + ROW_GAP))
        n = math.max(1, math.min(MAX_ROWS, n))
        for i = #rows + 1, n do NewRow(i) end
        return n
    end

    -- Ziehgriff unten rechts (angedockt oben: oben rechts, gespiegelt)
    local grip = CreateFrame("Button", nil, main)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(main:GetFrameLevel() + 10)
    grip:SetNormalTexture(GRIP_UP)
    grip:SetPushedTexture(GRIP_DOWN)
    grip:SetHighlightTexture(GRIP_HIGHLIGHT)
    -- Leicht zurückgenommen, damit er den Wert der untersten Zeile kaum verdeckt
    grip:SetAlpha(0.5)

    -- Griff und Zurücksetzen-Knopf passend zum Andock-Zustand setzen
    function win.LayoutGrip()
        local top = win.Docked() == "top"
        grip:ClearAllPoints()
        resetButton:ClearAllPoints()
        if top then
            -- Unterkante hängt an Fenster 1: Höhe wächst nach oben, Griff sitzt oben rechts
            grip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -1, -1)
            resetButton:SetPoint("TOPRIGHT", main, "TOPRIGHT", -20, -3)
        else
            grip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -1, 1)
            resetButton:SetPoint("TOPRIGHT", main, "TOPRIGHT", -4, -3)
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
            -- Angedockt folgt die Breite Fenster 1; beim Lösen übernimmt Fenster 2 diese Breite
            if not win.Docked() then ns.db[cfg.widthKey] = Clamp(w, MIN_W, MAX_W, DEFAULT_W) end
            ns.db[cfg.heightKey] = Clamp(h, MIN_H, MAX_H, DEFAULT_H)
        end
        -- Angedockt hängt die Position an Fenster 1, nichts zu speichern
        if win.Docked() then return end
        -- Wie ns.MakeMovable beim Verschieben: Ankerpunkt nach StopMovingOrSizing übernehmen
        local point, _, relPoint, x, y = main:GetPoint()
        if point then ns.db.positions[cfg.posKey] = { point, relPoint, x, y } end
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
        GameTooltip:SetText(win.Docked() and "Ziehen: Höhe ändern" or "Ziehen: Größe ändern", 1, 1, 1)
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

    local menu = CreateFrame("Frame", cfg.menuName, main)
    win.menu = menu
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetWidth(180)
    menu:Hide()
    local menuBg = menu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints()
    menuBg:SetColorTexture(C.menuBg[1], C.menuBg[2], C.menuBg[3], C.menuBg[4])
    Border(menu, C.border)
    if UISpecialFrames then table.insert(UISpecialFrames, cfg.menuName) end

    local menuItems = {}

    local function MenuItem(i)
        if menuItems[i] then return menuItems[i] end
        local b = CreateFrame("Button", nil, menu)
        b:SetHeight(MENU_ITEM_H)
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * MENU_ITEM_H)
        b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * MENU_ITEM_H)
        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
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
            { label = "Gesamt", view = "overall" },
            { label = "Aktueller Kampf", view = "current" },
        }
        local sessions = SessionList()
        if #sessions == 0 then
            items[#items + 1] = { label = "Keine einzelnen Kämpfe" }
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
                c = C.accent
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
        GameTooltip:SetText("Zurücksetzen", 1, 1, 1)
        GameTooltip:AddLine("Löscht alle Kämpfe in beiden DMG-Meter-Fenstern – auch in Blizzards eigenem Schadensmesser. Geht nur außerhalb des Kampfes.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
        GameTooltip:Show()
    end)
    resetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function SetMode(mode)
        Click()
        ns.db[cfg.modeKey] = mode
        Request()
    end
    damageButton:SetScript("OnClick", function() SetMode("damage") end)
    healingButton:SetScript("OnClick", function() SetMode("healing") end)

    -----------------------------------------------------------------------
    -- Anzeige
    -----------------------------------------------------------------------

    local function ViewLabel()
        if win.view == "current" then return "Aktueller Kampf" end
        if win.view == "overall" then return "Gesamt" end
        return win.viewLabel or "Kampf"
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
        if not (ns.db and ns.db.dmShow and HAS_API) then return false end
        if cfg.showKey and not ns.db[cfg.showKey] then return false end
        return true
    end

    local function UpdateHeader(mode, demo)
        local text = MODE_LABEL[mode] .. " – " .. ViewLabel()
        if demo then text = text .. " · Beispiel" end
        title:SetText(text)
        damageButton:SetActive(mode == "damage")
        healingButton:SetActive(mode == "healing")
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
            win.ShowEmpty("Noch keine Daten.")
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
            win.ShowEmpty("Werte gerade nicht anzeigbar.")
        end
    end

    -- Beim Anmelden: gespeicherte Werte prüfen, Größe und Position setzen
    function win.Restore()
        local m = ns.db[cfg.modeKey]
        if m ~= "damage" and m ~= "healing" then ns.db[cfg.modeKey] = cfg.defaultMode end
        ns.db[cfg.widthKey] = Clamp(ns.db[cfg.widthKey], MIN_W, MAX_W, DEFAULT_W)
        ns.db[cfg.heightKey] = Clamp(ns.db[cfg.heightKey], MIN_H, MAX_H, DEFAULT_H)
        main:SetSize(ns.db[cfg.widthKey], ns.db[cfg.heightKey])
        ns.RestorePosition(main)
    end

    windows[#windows + 1] = win
    return win
end

---------------------------------------------------------------------------
-- Die beiden Fenster (Fenster 1 behält die bisherigen Schlüssel und Namen)
---------------------------------------------------------------------------

local win1 = CreateMeter({
    name = "strayDamageMeter",
    menuName = "strayDamageMeterMenu",
    posKey = "damagemeter",
    label = "DMG-Meter",
    defaultPoint = { "BOTTOMRIGHT", "BOTTOMRIGHT", -260, 180 },
    modeKey = "dmMode",
    defaultMode = "damage",
    widthKey = "dmWidth",
    heightKey = "dmHeight",
})

local win2 = CreateMeter({
    name = "strayDamageMeter2",
    menuName = "strayDamageMeterMenu2",
    posKey = "damagemeter2",
    label = "DMG-Meter 2",
    defaultPoint = { "BOTTOMRIGHT", "BOTTOMRIGHT", -260, 390 },
    modeKey = "dm2Mode",
    defaultMode = "healing",
    widthKey = "dm2Width",
    heightKey = "dm2Height",
    showKey = "dm2Show",
    dockable = true,
})

Flush = function()
    local cache = {}
    for _, win in ipairs(windows) do
        if not pcall(win.Update, cache) then
            NoticeLocked()
            pcall(win.ShowEmpty, "Werte gerade nicht anzeigbar.")
        end
    end
end

---------------------------------------------------------------------------
-- Andocken: Fenster 2 an Ober- oder Unterkante von Fenster 1
--
-- Angedockt hängt Fenster 2 mit zwei Ankern an Fenster 1 (links und rechts bündig). Damit
-- laufen Position und Breite von selbst mit, auch beim Verschieben im Bearbeiten-Modus.
-- Erkannt wird das Andocken in StopMovingOrSizing von Fenster 2 – das rufen sowohl
-- ns.MakeMovable (Shift + ziehen) als auch der Bearbeiten-Modus auf.
---------------------------------------------------------------------------

local f1, f2 = win1.frame, win2.frame

-- Fenster 2 an Fenster 1 hängen (1 px Überlappung, damit die Ränder zu einer Linie werden)
local function ApplyDock()
    if not ns.db then return end
    local dock = DockState()
    if dock then
        f2:ClearAllPoints()
        if dock == "top" then
            f2:SetPoint("BOTTOMLEFT", f1, "TOPLEFT", 0, -1)
            f2:SetPoint("BOTTOMRIGHT", f1, "TOPRIGHT", 0, -1)
        else
            f2:SetPoint("TOPLEFT", f1, "BOTTOMLEFT", 0, 1)
            f2:SetPoint("TOPRIGHT", f1, "BOTTOMRIGHT", 0, 1)
        end
        f2:SetHeight(Clamp(ns.db.dm2Height, MIN_H, MAX_H, DEFAULT_H))
    end
    win2.LayoutGrip()
end

-- Liegt Fenster 2 gerade nah genug an Fenster 1? Ergebnis "top", "bottom" oder nil
local function FindDock()
    if not f1:IsShown() then return nil end
    local l1, r1, t1, b1 = f1:GetLeft(), f1:GetRight(), f1:GetTop(), f1:GetBottom()
    local l2, r2, t2, b2 = f2:GetLeft(), f2:GetRight(), f2:GetTop(), f2:GetBottom()
    for _, v in ipairs({ l1, r1, t1, b1, l2, r2, t2, b2 }) do
        if not PlainNumber(v) then return nil end
    end
    -- Nur wenn sich die Fenster waagerecht überlappen
    if r2 < l1 or l2 > r1 then return nil end
    if math.abs(b2 - t1) < SNAP then return "top" end
    if math.abs(t2 - b1) < SNAP then return "bottom" end
    return nil
end

do
    -- Eigene Methoden auf dem eigenen Fenster umhüllen (kein Blizzard-Rahmen)
    local baseStartMoving = f2.StartMoving
    local baseStopMoving = f2.StopMovingOrSizing
    local dragging = false

    f2.StartMoving = function(self, ...)
        -- Angedockt: erst auf einen festen Punkt am Bildschirm setzen, dann frei ziehen
        if DockState() then
            local l, b, w = self:GetLeft(), self:GetBottom(), self:GetWidth()
            if PlainNumber(l) and PlainNumber(b) and PlainNumber(w) then
                self:ClearAllPoints()
                self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
                self:SetWidth(w)
            end
        end
        dragging = true
        return baseStartMoving(self, ...)
    end

    -- Nach dem Loslassen entscheiden: andocken oder gelöst. later = Andocken erst im nächsten Bild.
    local function Decide(later)
        local was = DockState()
        local dock = FindDock()
        ns.db.dm2Dock = dock
        if not dock then
            -- Gelöst: die aktuelle Breite wird die eigene Breite
            local w = f2:GetWidth()
            if PlainNumber(w) then ns.db.dm2Width = Clamp(w, MIN_W, MAX_W, DEFAULT_W) end
            if was then win2.LayoutGrip() end
            return
        end
        if later and C_Timer and C_Timer.After then
            C_Timer.After(0, ApplyDock)
        else
            ApplyDock()
        end
    end

    f2.StopMovingOrSizing = function(self, ...)
        baseStopMoving(self, ...)
        if not dragging or not ns.db then return end
        dragging = false
        -- Im Bearbeiten-Modus entscheidet der Haken strayOnDragStop (nach Einrasten und Raster)
        if ns.editMode then return end
        -- Shift + ziehen: Andocken erst im nächsten Bild, denn ns.MakeMovable speichert danach
        -- noch die Position (lesbar, weil das Fenster dann noch am Bildschirm verankert ist).
        Decide(true)
    end

    -- Haken des Bearbeiten-Modus: läuft nach Einrasten, Raster und Speichern der Position
    f2.strayOnDragStop = function()
        if ns.db then Decide(false) end
    end
end

-- Position von Fenster 2 zurückgesetzt (Anmelden, Rechtsklick oder „Alles zurücksetzen“ im
-- Bearbeiten-Modus): Ohne gespeicherte Position gilt der Standard „oben angedockt“.
hooksecurefunc(ns, "RestorePosition", function(frame)
    if frame ~= f2 or not ns.db then return end
    if ns.db.positions[f2.strayKey] == nil then ns.db.dm2Dock = "top" end
    ApplyDock()
end)

---------------------------------------------------------------------------
-- Zurücksetzen (betrifft beide Fenster, die Daten sind dieselben)
---------------------------------------------------------------------------

local function ResetViews()
    for _, win in ipairs(windows) do
        win.view, win.viewLabel = "overall", nil
        win.menu:Hide()
    end
end

-- auto = true: nach Verlassen einer Instanz (andere Chatzeile, keine Kampfmeldung)
local function DoReset(auto)
    if not HAS_RESET then return false end
    if InCombatLockdown() then
        if not auto then ns.Print("Zurücksetzen geht erst nach dem Kampf.") end
        return false
    end
    if not pcall(DM.ResetAllCombatSessions) then
        ns.Print("Der DMG-Meter ließ sich nicht zurücksetzen.")
        return false
    end
    ResetViews()
    if auto then
        ns.Print("DMG-Meter zurückgesetzt (Instanz verlassen).")
    else
        ns.Print("DMG-Meter zurückgesetzt.")
    end
    Request()
    return true
end

if StaticPopupDialogs then
    StaticPopupDialogs["STRAY_DAMAGEMETER_RESET"] = {
        text = "Alle Kämpfe im DMG-Meter zurücksetzen?\n\nDas betrifft auch Blizzards eigenen Schadensmesser.",
        button1 = YES or "Ja",
        button2 = NO or "Nein",
        OnAccept = function() DoReset(false) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

OpenResetPopup = function()
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs["STRAY_DAMAGEMETER_RESET"] then
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
        for _, win in ipairs(windows) do
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
    -- Erst Fenster 1, dann Fenster 2 (dessen Andocken braucht die Lage von Fenster 1)
    win1.Restore()
    win2.Restore()
    RefreshEvents()
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

local function Setter(key)
    return function(value)
        ns.db[key] = value
        RefreshEvents()
        if not value and key == "dmShow" then
            for _, win in ipairs(windows) do win.Hide() end
        end
        Request()
    end
end

ns.AddOption(2, "DMG-Meter", {
    key = "dmShow",
    label = "DMG-Meter anzeigen",
    tooltip = "Zeigt Schaden oder Heilung deiner Gruppe in einem eigenen Fenster. Balken mit Gesamtwert und Wert pro Sekunde in Klassenfarbe (so hell wie die Gruppenrahmen), dein eigener Balken hat links einen blauen Strich. Wie viele Balken zu sehen sind, ergibt sich aus der Fenstergröße – unten rechts ziehen zum Ändern. Oben rechts schaltest du mit S || H zwischen Schaden und Heilung um; ein Klick auf den Titel wählt Gesamt, den aktuellen Kampf oder einen einzelnen Kampf. Die Werte kommen aus dem eingebauten Schadensmesser des Spiels.\n\nSolange das stray-Fenster offen ist und noch keine Daten da sind, zeigt das Fenster Beispielwerte – dann kannst du es mit Shift + linker Maustaste verschieben.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("dmShow"),
})

ns.AddOption(2, "DMG-Meter", {
    key = "dm2Show",
    label = "Zweites Fenster",
    tooltip = "Zeigt ein zweites DMG-Meter-Fenster mit eigenem Modus (Standard: Heilung), eigener Ansicht und eigener Größe – zum Beispiel oben Heilung und unten Schaden.\n\nZiehst du es mit Shift an die Ober- oder Unterkante des ersten Fensters, dockt es an: gleiche Breite, links bündig, und es wandert mit dem ersten Fenster mit. Angedockt änderst du nur seine Höhe. Wegziehen löst es wieder. Beim ersten Einschalten sitzt es angedockt über dem ersten Fenster. Zurücksetzen gilt für beide Fenster.",
    isEnabled = function() return HAS_API and ns.db and ns.db.dmShow and true or false end,
    disabledHint = "Erst „DMG-Meter anzeigen“ einschalten (direkt darüber).",
    set = function(value)
        ns.db.dm2Show = value
        -- Erstes Einschalten (noch nie verschoben): oben angedockt
        if value and DockState() == nil and ns.db.positions[f2.strayKey] == nil then
            ns.db.dm2Dock = "top"
        end
        ApplyDock()
        if not value then win2.Hide() end
        Request()
    end,
})

ns.AddOption(2, "DMG-Meter", {
    key = "dmAutoReset",
    label = "Nach Instanz zurücksetzen",
    tooltip = "Setzt den DMG-Meter zurück, sobald du einen Dungeon oder Schlachtzug verlässt. Im Chat erscheint dann eine kurze Meldung. Das betrifft auch Blizzards eigenen Schadensmesser, weil beide dieselben Daten nutzen.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("dmAutoReset"),
})
