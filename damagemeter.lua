-- stray – DMG-Meter: eigenes Fenster für Schaden und Heilung (gesamt, aktueller Kampf, einzelne Kämpfe)
--
-- Die Werte kommen aus Blizzards eingebautem Schadensmesser (C_DamageMeter), nicht aus dem Kampflog.
-- Im Kampf versiegelt WoW Forever Name, GUID, Gesamtwert und Wert pro Sekunde („secret values“).
-- Damit darf ein Addon nicht vergleichen, nicht rechnen, nicht testen und keine Tabellenschlüssel
-- bilden. Deshalb gilt hier überall: erst ns.IsSecret() prüfen; versiegelte Werte werden nur an
-- Anzeige-Funktionen (SetText, SetFormattedText, SetValue, SetMinMaxValues, AbbreviateNumbers)
-- weitergereicht – jeweils in pcall. Klassenname und „bin ich das“ sind nie versiegelt.
--
-- Aktualisiert wird ereignisbasiert (zusammengefasst) und im Kampf zusätzlich etwa alle 0,5 s.
-- Die Ereignisse sind nur registriert, solange die passende Option an ist.

local _, ns = ...

local IsSecret = ns.IsSecret

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
-- Fenster
---------------------------------------------------------------------------

local main = CreateFrame("Frame", "strayDamageMeter", UIParent)
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

ns.MakeMovable(main, "damagemeter", { "BOTTOMRIGHT", "BOTTOMRIGHT", -260, 180 })
ns.RegisterMovable(main, "DMG-Meter")

-- Größe ziehen (unten rechts). Grenzen: neue API SetResizeBounds, sonst SetMinResize/SetMaxResize.
main:SetResizable(true)
if not pcall(main.SetResizeBounds, main, MIN_W, MIN_H, MAX_W, MAX_H) then
    if main.SetMinResize then pcall(main.SetMinResize, main, MIN_W, MIN_H) end
    if main.SetMaxResize then pcall(main.SetMaxResize, main, MAX_W, MAX_H) end
end

-- Verschieben (Shift + ziehen) und Größenziehen schließen sich aus: Merker um die Skripte
-- aus ns.MakeMovable legen. ForwardDrag holt sich die Skripte per GetScript, nutzt also diese.
local moving, sizing = false, false
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
        moving = false
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
    GameTooltip:SetText("DMG-Meter", 1, 1, 1)
    GameTooltip:AddLine("Klick auf den Titel: Gesamt, aktueller Kampf oder ein einzelner Kampf.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    GameTooltip:AddLine("Werte: gesamt (pro Sekunde). Die Daten kommen aus dem eingebauten Schadensmesser des Spiels.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("S || H oben rechts: Schaden oder Heilung.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Shift + ziehen zum Verschieben", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Unten rechts ziehen: Größe ändern", 0.5, 0.5, 0.5)
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

local function ModeTooltip(owner, label)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(label, 1, 1, 1)
    GameTooltip:Show()
end
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

-- Ziehgriff unten rechts
local grip = CreateFrame("Button", nil, main)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -1, 1)
grip:SetFrameLevel(main:GetFrameLevel() + 10)
grip:SetNormalTexture(GRIP_UP)
grip:SetPushedTexture(GRIP_DOWN)
grip:SetHighlightTexture(GRIP_HIGHLIGHT)
-- Leicht zurückgenommen, damit er den Wert der untersten Zeile kaum verdeckt
grip:SetAlpha(0.5)

local function SaveSizeAndPosition()
    local w, h = main:GetSize()
    if not IsSecret(w) and not IsSecret(h) then
        ns.db.dmWidth = Clamp(w, MIN_W, MAX_W, DEFAULT_W)
        ns.db.dmHeight = Clamp(h, MIN_H, MAX_H, DEFAULT_H)
    end
    -- Wie ns.MakeMovable beim Verschieben: Ankerpunkt nach StopMovingOrSizing übernehmen
    local point, _, relPoint, x, y = main:GetPoint()
    if point then ns.db.positions.damagemeter = { point, relPoint, x, y } end
end

local function StopSizing()
    if not sizing then return end
    sizing = false
    main:StopMovingOrSizing()
    if ns.db then SaveSizeAndPosition() end
end

grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or moving or sizing or not ns.db then return end
    GameTooltip:Hide()
    if pcall(main.StartSizing, main, "BOTTOMRIGHT") then sizing = true end
end)
grip:SetScript("OnMouseUp", function() StopSizing() end)
grip:SetScript("OnHide", function() StopSizing() end)
grip:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    if sizing then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Ziehen: Größe ändern", 1, 1, 1)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", function(self)
    self:SetAlpha(0.5)
    GameTooltip:Hide()
end)

---------------------------------------------------------------------------
-- Ansicht: "overall", "current" oder eine sessionID (einzelner Kampf)
---------------------------------------------------------------------------

local view = "overall"
local viewLabel = nil -- Beschriftung des gewählten einzelnen Kampfs

local function Mode()
    return (ns.db and ns.db.dmMode == "healing") and "healing" or "damage"
end

local function ViewLabel()
    if view == "current" then return "Aktueller Kampf" end
    if view == "overall" then return "Gesamt" end
    return viewLabel or "Kampf"
end

local function MeterType()
    if Mode() == "healing" then return METER_TYPE.HealingDone end
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

-- Daten der aktuellen Ansicht holen (Tabelle oder nil)
local function GetSession()
    local meterType = MeterType()
    if meterType == nil then return nil end
    if view ~= "overall" and view ~= "current" then
        if DM.GetCombatSessionFromID then
            local ok, session = pcall(DM.GetCombatSessionFromID, view, meterType)
            if ok and type(session) == "table" then return session end
        end
        -- Kampf gibt es nicht mehr (z. B. nach dem Zurücksetzen): zurück zu Gesamt
        view, viewLabel = "overall", nil
    end
    local sessionType = (view == "current") and SESSION_TYPE.Current or SESSION_TYPE.Overall
    if sessionType == nil then return nil end
    local ok, session = pcall(DM.GetCombatSessionFromType, sessionType, meterType)
    if ok and type(session) == "table" then return session end
    return nil
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

local function DemoEntries()
    local me = ns.Public(UnitName("player"))
    if type(me) ~= "string" then me = "Du" end
    local _, myClass = UnitClass("player")
    myClass = ns.Public(myClass)
    local healing = Mode() == "healing"
    local list = {
        { name = "Beispiel-Magier", class = "MAGE", total = 48200, perSec = 402 },
        { name = me, class = myClass, total = 41500, perSec = 346, me = true },
        { name = "Beispiel-Jäger", class = "HUNTER", total = 36800, perSec = 307 },
        { name = "Beispiel-Krieger", class = "WARRIOR", total = 22100, perSec = 184 },
        { name = "Beispiel-Priester", class = "PRIEST", total = 9400, perSec = 78 },
    }
    if healing then
        list = {
            { name = "Beispiel-Priester", class = "PRIEST", total = 52300, perSec = 436 },
            { name = "Beispiel-Druide", class = "DRUID", total = 28900, perSec = 241 },
            { name = me, class = myClass, total = 6100, perSec = 51, me = true },
        }
    end
    return list, list[1].total
end

---------------------------------------------------------------------------
-- Anzeige
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

local function ShowEmpty(message)
    for i = 1, #rows do rows[i]:Hide() end
    emptyText:SetText(message)
    emptyText:Show()
end

local function UpdateHeader(demo)
    local text = MODE_LABEL[Mode()] .. " – " .. ViewLabel()
    if demo then text = text .. " · Beispiel" end
    title:SetText(text)
    damageButton:SetActive(Mode() == "damage")
    healingButton:SetActive(Mode() == "healing")
    if HAS_RESET then
        resetButton:Enable()
        resetButton:SetAlpha(1)
    else
        resetButton:Disable()
        resetButton:SetAlpha(0.4)
    end
end

local menu -- unten definiert

local function Update()
    if not ns.db or not ns.db.dmShow or not HAS_API then
        main:Hide()
        if menu then menu:Hide() end
        return
    end

    local entries, max = Collect(GetSession())
    local demo = false
    if #entries == 0 and ns.IsConfigOpen() then
        entries, max = DemoEntries()
        demo = true
    end

    UpdateHeader(demo)
    main:Show()

    if #entries == 0 then
        ShowEmpty("Noch keine Daten.")
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
        ShowEmpty("Werte gerade nicht anzeigbar.")
        return
    end
end

local function Flush()
    if pcall(Update) then return end
    NoticeLocked()
    pcall(ShowEmpty, "Werte gerade nicht anzeigbar.")
end

---------------------------------------------------------------------------
-- Takt: ereignisbasiert zusammengefasst, im Kampf zusätzlich etwa alle 0,5 s
---------------------------------------------------------------------------

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

-- Größe geändert: Zeilenzahl neu bestimmen und neu zeichnen (zusammengefasst über Request)
main:SetScript("OnSizeChanged", function() Request() end)

---------------------------------------------------------------------------
-- Auswahlmenü (Klick auf den Titel)
---------------------------------------------------------------------------

menu = CreateFrame("Frame", "strayDamageMeterMenu", main)
menu:SetFrameStrata("DIALOG")
menu:SetClampedToScreen(true)
menu:EnableMouse(true)
menu:SetWidth(180)
menu:Hide()
local menuBg = menu:CreateTexture(nil, "BACKGROUND")
menuBg:SetAllPoints()
menuBg:SetColorTexture(C.menuBg[1], C.menuBg[2], C.menuBg[3], C.menuBg[4])
Border(menu, C.border)
if UISpecialFrames then table.insert(UISpecialFrames, "strayDamageMeterMenu") end

local MENU_ITEM_H = 18
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
        view, viewLabel = self.view, self.viewLabel
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
        elseif item.view == view then
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

---------------------------------------------------------------------------
-- Zurücksetzen
---------------------------------------------------------------------------

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
    view, viewLabel = "overall", nil
    menu:Hide()
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

resetButton:SetScript("OnClick", function()
    Click()
    menu:Hide()
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs["STRAY_DAMAGEMETER_RESET"] then
        StaticPopup_Show("STRAY_DAMAGEMETER_RESET")
    else
        DoReset(false)
    end
end)
resetButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Zurücksetzen", 1, 1, 1)
    GameTooltip:AddLine("Löscht alle Kämpfe – auch in Blizzards eigenem Schadensmesser. Geht nur außerhalb des Kampfes.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    GameTooltip:Show()
end)
resetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function SetMode(mode)
    Click()
    ns.db.dmMode = mode
    Request()
end
damageButton:SetScript("OnClick", function() SetMode("damage") end)
healingButton:SetScript("OnClick", function() SetMode("healing") end)

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
        if view ~= "overall" and view ~= "current" then view, viewLabel = "overall", nil end
        if menu then menu:Hide() end
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
    if ns.db.dmMode ~= "damage" and ns.db.dmMode ~= "healing" then ns.db.dmMode = "damage" end
    ns.db.dmWidth = Clamp(ns.db.dmWidth, MIN_W, MAX_W, DEFAULT_W)
    ns.db.dmHeight = Clamp(ns.db.dmHeight, MIN_H, MAX_H, DEFAULT_H)
    main:SetSize(ns.db.dmWidth, ns.db.dmHeight)
    ns.RestorePosition(main)
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
            main:Hide()
            menu:Hide()
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
    key = "dmAutoReset",
    label = "Nach Instanz zurücksetzen",
    tooltip = "Setzt den DMG-Meter zurück, sobald du einen Dungeon oder Schlachtzug verlässt. Im Chat erscheint dann eine kurze Meldung. Das betrifft auch Blizzards eigenen Schadensmesser, weil beide dieselben Daten nutzen.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("dmAutoReset"),
})
