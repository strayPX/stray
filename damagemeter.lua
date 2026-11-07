-- stray – Schadensmesser: eigenes Fenster für Schaden und Heilung (gesamt, aktueller Kampf, einzelne Kämpfe)
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

local WIDTH = 230
local MAX_ROWS = 8
local ROW_H = 16
local ROW_GAP = 2
local TOP_H = 46 -- Kopfzeile (Titel + Knöpfe) bis zum ersten Balken
local MAX_SESSIONS = 10

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BODY = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local C = {
    bg       = { 0.051, 0.067, 0.090, 0.9 },
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

local function ColorLines(lines, c)
    for _, t in ipairs(lines) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

local function Text(parent, size, c, font, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or FONT_BODY, size, flags or "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Kleiner flacher Knopf; SetActive hebt ihn blau hervor
local function SmallButton(parent, label, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 16)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.03)
    b.lines = Border(b, C.border)
    b.text = Text(b, 11, C.textSide)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.07)
    function b:SetActive(on)
        if on then
            self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18)
            ColorLines(self.lines, C.accent)
            self.text:SetTextColor(1, 1, 1, 1)
        else
            self.bg:SetColorTexture(1, 1, 1, 0.03)
            ColorLines(self.lines, C.border)
            self.text:SetTextColor(C.textSide[1], C.textSide[2], C.textSide[3], 1)
        end
    end
    return b
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
    ns.Print("WoW Forever lässt die Werte des Schadensmessers hier gerade nicht anzeigen – stray versucht es weiter, spätestens nach dem Kampf klappt es wieder.")
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local main = CreateFrame("Frame", "strayDamageMeter", UIParent)
main:SetSize(WIDTH, TOP_H + 26)
main:SetFrameStrata("MEDIUM")
main:Hide()

local mainBg = main:CreateTexture(nil, "BACKGROUND")
mainBg:SetAllPoints()
mainBg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
Border(main, C.border)

ns.MakeMovable(main, "damagemeter", { "BOTTOMRIGHT", "BOTTOMRIGHT", -260, 180 })

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
    GameTooltip:SetText("Schadensmesser", 1, 1, 1)
    GameTooltip:AddLine("Klick auf den Titel: Gesamt, aktueller Kampf oder ein einzelner Kampf.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    GameTooltip:AddLine("Werte: gesamt (pro Sekunde). Die Daten kommen aus dem eingebauten Schadensmesser des Spiels.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Shift + ziehen zum Verschieben", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

main:SetScript("OnEnter", function(self) MainTooltip(self) end)
main:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Titel (klickbar: Ansicht wählen)
local titleButton = CreateFrame("Button", nil, main)
titleButton:SetPoint("TOPLEFT", main, "TOPLEFT", 6, -5)
titleButton:SetPoint("TOPRIGHT", main, "TOPRIGHT", -6, -5)
titleButton:SetHeight(18)
local titleHover = titleButton:CreateTexture(nil, "HIGHLIGHT")
titleHover:SetAllPoints()
titleHover:SetColorTexture(1, 1, 1, 0.06)
local title = Text(titleButton, 12, C.text, FONT)
title:SetPoint("LEFT", titleButton, "LEFT", 2, 0)
title:SetPoint("RIGHT", titleButton, "RIGHT", -14, 0)
local titleArrow = Text(titleButton, 11, C.accent)
titleArrow:SetPoint("RIGHT", titleButton, "RIGHT", -2, 0)
titleArrow:SetText("v")
ForwardDrag(titleButton)
titleButton:SetScript("OnEnter", function(self) MainTooltip(self) end)
titleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Umschalter Schaden | Heilung, Zurücksetzen
local damageButton = SmallButton(main, "Schaden", 58)
damageButton:SetPoint("TOPLEFT", main, "TOPLEFT", 6, -25)
local healingButton = SmallButton(main, "Heilung", 58)
healingButton:SetPoint("LEFT", damageButton, "RIGHT", 4, 0)
local resetButton = SmallButton(main, "Zurücksetzen", 78)
resetButton:SetPoint("TOPRIGHT", main, "TOPRIGHT", -6, -25)
ForwardDrag(damageButton)
ForwardDrag(healingButton)
ForwardDrag(resetButton)

-- Hinweistext, wenn keine Balken da sind
local emptyText = Text(main, 11, C.textDim)
emptyText:SetPoint("TOPLEFT", main, "TOPLEFT", 8, -TOP_H - 2)
emptyText:SetPoint("TOPRIGHT", main, "TOPRIGHT", -8, -TOP_H - 2)
emptyText:Hide()

-- Balken
local rows = {}
for i = 1, MAX_ROWS do
    local bar = CreateFrame("StatusBar", nil, main)
    bar:SetSize(WIDTH - 12, ROW_H)
    bar:SetPoint("TOPLEFT", main, "TOPLEFT", 6, -TOP_H - (i - 1) * (ROW_H + ROW_GAP))
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(1, 1, 1, 0.06)

    -- Markierung für den eigenen Balken
    bar.mark = bar:CreateTexture(nil, "OVERLAY")
    bar.mark:SetPoint("TOPLEFT")
    bar.mark:SetPoint("BOTTOMLEFT")
    bar.mark:SetWidth(2)
    bar.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    bar.mark:Hide()

    bar.value = Text(bar, 11, C.text, FONT_BODY, "OUTLINE")
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bar.value:SetJustifyH("RIGHT")
    bar.name = Text(bar, 11, C.text, FONT_BODY, "OUTLINE")
    bar.name:SetPoint("LEFT", bar, "LEFT", 5, 0)
    bar.name:SetPoint("RIGHT", bar.value, "LEFT", -4, 0)
    bar:Hide()
    rows[i] = bar
end

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

    local color = entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
    if color then
        bar:SetStatusBarColor(color.r, color.g, color.b, 0.75)
    else
        bar:SetStatusBarColor(0.5, 0.5, 0.5, 0.75)
    end

    if not pcall(bar.SetMinMaxValues, bar, 0, max) then bar:SetMinMaxValues(0, 1) end
    if not pcall(bar.SetValue, bar, entry.total) then bar:SetValue(0) end

    if entry.me then
        bar.bg:SetColorTexture(1, 1, 1, 0.16)
        bar.mark:Show()
    else
        bar.bg:SetColorTexture(1, 1, 1, 0.06)
        bar.mark:Hide()
    end

    return SetAmountText(bar.value, entry.total, entry.perSec)
end

local function ShowEmpty(message)
    for i = 1, MAX_ROWS do rows[i]:Hide() end
    emptyText:SetText(message)
    emptyText:Show()
    main:SetHeight(TOP_H + 20)
end

local function UpdateHeader(demo)
    local text = MODE_LABEL[Mode()] .. " – " .. ViewLabel()
    if demo then text = text .. " · Beispiel" end
    title:SetText(text)
    damageButton:SetActive(Mode() == "damage")
    healingButton:SetActive(Mode() == "healing")
    if HAS_RESET then
        resetButton:Enable()
        resetButton.text:SetAlpha(1)
    else
        resetButton:Disable()
        resetButton.text:SetAlpha(0.4)
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
    local shown = math.min(#entries, MAX_ROWS)
    local allOk = true
    for i = 1, MAX_ROWS do
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
    main:SetHeight(TOP_H + shown * (ROW_H + ROW_GAP) + 4)
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
        ns.Print("Der Schadensmesser ließ sich nicht zurücksetzen.")
        return false
    end
    view, viewLabel = "overall", nil
    menu:Hide()
    if auto then
        ns.Print("Schadensmesser zurückgesetzt (Instanz verlassen).")
    else
        ns.Print("Schadensmesser zurückgesetzt.")
    end
    Request()
    return true
end

if StaticPopupDialogs then
    StaticPopupDialogs["STRAY_DAMAGEMETER_RESET"] = {
        text = "Alle Kämpfe im Schadensmesser zurücksetzen?\n\nDas betrifft auch Blizzards eigenen Schadensmesser.",
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

ns.AddOption(2, "Schadensmesser", {
    key = "dmShow",
    label = "Schadensmesser anzeigen",
    tooltip = "Zeigt Schaden oder Heilung deiner Gruppe in einem eigenen Fenster. Bis zu 8 Balken mit Gesamtwert und Wert pro Sekunde, dein eigener Balken ist hervorgehoben. Oben schaltest du zwischen Schaden und Heilung um; ein Klick auf den Titel wählt Gesamt, den aktuellen Kampf oder einen einzelnen Kampf. Die Werte kommen aus dem eingebauten Schadensmesser des Spiels.\n\nSolange das stray-Fenster offen ist und noch keine Daten da sind, zeigt das Fenster Beispielwerte – dann kannst du es mit Shift + linker Maustaste verschieben.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("dmShow"),
})

ns.AddOption(2, "Schadensmesser", {
    key = "dmAutoReset",
    label = "Nach Instanz zurücksetzen",
    tooltip = "Setzt den Schadensmesser zurück, sobald du einen Dungeon oder Schlachtzug verlässt. Im Chat erscheint dann eine kurze Meldung. Das betrifft auch Blizzards eigenen Schadensmesser, weil beide dieselben Daten nutzen.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("dmAutoReset"),
})
