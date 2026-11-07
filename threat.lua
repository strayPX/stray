-- stray – Bedrohung: Liste und Anzeige an Namensplaketten
--
-- WoW Forever liefert Bedrohungswerte im Kampf als „geheime Werte“ (secret values).
-- Addons dürfen sie nicht vergleichen, nicht damit rechnen und nicht als Bedingung testen.
-- Erlaubt ist nur, sie an Anzeige-Funktionen weiterzureichen (Text, Balken) oder über
-- Blizzards Farbkurven (C_CurveUtil) in eine Farbe zu verwandeln. Genau das macht dieses Modul:
-- Es zeigt die Werte an, ohne sie je selbst auszuwerten. Jeder Anzeige-Schritt läuft in pcall;
-- klappt einer nicht, bleibt die Anzeige leer statt Fehler zu werfen.

local _, ns = ...

local HAS_API = UnitDetailedThreatSituation and true or false
local NO_API = "Diese Spielversion liefert keine Bedrohungswerte."
local NO_WARNINGS = "In WoW Forever nicht möglich: Das Spiel gibt Bedrohungswerte im Kampf nur versiegelt an Addons weiter, und diese Warnung müsste sie vergleichen."

local function ApiAvailable() return HAS_API end
local function NeverAvailable() return false end

local IsSecret = ns.IsSecret

local noticeShown = {}

-- Einmaliger Hinweis je Teil, falls die Anzeige versiegelter Werte im Client nicht klappt
local function NoticeLocked(part)
    if noticeShown[part] then return end
    noticeShown[part] = true
    ns.Print(("WoW Forever lässt die Bedrohungswerte im Kampf hier nicht anzeigen – „%s“ pausiert deshalb."):format(part))
end

-- Steht die Einheit auf der Bedrohungsliste? Ein versiegelter Status heißt „ja“;
-- ein unversiegeltes nil heißt „nein“. Der Wert selbst wird dabei nie ausgewertet.
local function OnThreatList(status)
    return IsSecret(status) or status ~= nil
end

---------------------------------------------------------------------------
-- Farben: Tabellen für normale Werte, Farbkurven für versiegelte
---------------------------------------------------------------------------

local GREEN, YELLOW, ORANGE, RED = { 0.25, 0.9, 0.25 }, { 1, 0.85, 0 }, { 1, 0.55, 0.1 }, { 1, 0.15, 0.15 }

-- Status 3 = du hast sicher Aggro, 2 = du hast Aggro, jemand liegt vorn,
-- 1 = du liegst vorn, hast aber noch keine Aggro, 0 = keine Aggro
local STATUS_POINTS = { { 0, GREEN }, { 1, YELLOW }, { 3, RED } }
-- Prozent bis zur Aggro (Liste und Plaketten-Zahl)
local PERCENT_POINTS = { { 0, GREEN }, { 70, YELLOW }, { 90, ORANGE }, { 100, RED } }

local function PlainColor(points, value)
    local color = points[1][2]
    for _, point in ipairs(points) do
        if value >= point[1] then color = point[2] end
    end
    return color
end

local function NewStepCurve(points)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or type(curve) ~= "table" and type(curve) ~= "userdata" then return nil end
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step and curve.SetType then
        pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    end
    for _, point in ipairs(points) do
        local c = point[2]
        if not pcall(curve.AddPoint, curve, point[1], CreateColor(c[1], c[2], c[3], 1)) then
            return nil
        end
    end
    return curve
end

local statusCurve = NewStepCurve(STATUS_POINTS)
local percentCurve = NewStepCurve(PERCENT_POINTS)

-- Gibt ok, r, g, b zurück; r, g, b können versiegelt sein und werden nur weitergereicht
local function CurveColor(curve, value)
    if not curve then return false end
    if curve.EvaluateUnpacked then
        local ok, r, g, b = pcall(curve.EvaluateUnpacked, curve, value)
        if ok then return true, r, g, b end
    end
    local ok, color = pcall(curve.Evaluate, curve, value)
    if not ok or type(color) ~= "table" then return false end
    local okRGB, r, g, b = pcall(function() return color:GetRGB() end)
    if not okRGB then return false end
    return true, r, g, b
end

local function ColorFor(points, curve, value)
    if not IsSecret(value) then
        if type(value) ~= "number" then return false end
        local c = PlainColor(points, value)
        return true, c[1], c[2], c[3]
    end
    return CurveColor(curve, value)
end

-- Prozentzahl in einen Text schreiben (versiegelt: nur formatieren, nie rechnen)
local function SetPercentText(fontString, value)
    if not IsSecret(value) then
        if type(value) ~= "number" then return false end
        fontString:SetText(("%.0f %%"):format(value))
        return true
    end
    if pcall(fontString.SetFormattedText, fontString, "%.0f %%", value) then return true end
    return pcall(function() fontString:SetText(string.format("%.0f %%", value)) end)
end

---------------------------------------------------------------------------
-- Bedrohungsliste
---------------------------------------------------------------------------

local MAX_ROWS = 8
local ROW_H = 16
local ROW_GAP = 2
local WIDTH = 210

local list = CreateFrame("Frame", "strayThreat", UIParent, ns.BACKDROP_TEMPLATE)
list:SetSize(WIDTH, 40)
list:SetFrameStrata("MEDIUM")
ns.ApplyBackdrop(list)
ns.MakeMovable(list, "threat", { "RIGHT", "RIGHT", -60, -60 })
list:Hide()

local header = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -7)
header:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -7)
header:SetJustifyH("LEFT")

local rows = {}
for i = 1, MAX_ROWS do
    local bar = CreateFrame("StatusBar", nil, list)
    bar:SetSize(WIDTH - 12, ROW_H)
    bar:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -22 - (i - 1) * (ROW_H + ROW_GAP))
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 100)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.08)

    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.name:SetPoint("LEFT", bar, "LEFT", 4, 0)
    bar.pct = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.pct:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bar:Hide()
    rows[i] = bar
end

list:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Bedrohung", 1, 1, 1)
    GameTooltip:AddLine("Prozent = wie nah jemand daran ist, die Aggro zu ziehen. 100 % = hat die Aggro.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    GameTooltip:AddLine("Reihenfolge fest (du zuerst), weil WoW Forever das Sortieren nach Bedrohung nicht erlaubt.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Shift + ziehen zum Verschieben", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
list:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function NameColor(unit)
    if not unit or not UnitIsPlayer(unit) then return 1, 1, 1 end
    local _, class = UnitClass(unit)
    class = ns.Public(class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

local function GroupUnits()
    local units = {}
    -- Du (und dein Begleiter) immer zuerst
    units[1] = "player"
    if UnitExists("pet") then units[#units + 1] = "pet" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit, pet = "raid" .. i, "raidpet" .. i
            if not UnitIsUnit(unit, "player") then
                units[#units + 1] = unit
                if UnitExists(pet) then units[#units + 1] = pet end
            end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
            if UnitExists("partypet" .. i) then units[#units + 1] = "partypet" .. i end
        end
    end
    return units
end

local function IsEnemy(unit)
    return UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit)
end

-- Feste Reihenfolge: Sortieren hieße vergleichen, und das ist bei versiegelten Werten verboten
local function CollectThreat(mob)
    local entries = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then
            local _, status, scaled = UnitDetailedThreatSituation(unit, mob)
            if OnThreatList(status) then
                entries[#entries + 1] = { unit = unit, name = ns.Public(UnitName(unit)), pct = scaled }
            end
        end
    end
    return entries
end

local function DemoEntries()
    return {
        { unit = "player", name = ns.Public(UnitName("player")) or "Du", pct = 100 },
        { name = "Beispiel-Magier", pct = 92 },
        { name = "Beispiel-Jäger", pct = 71 },
        { name = "Beispiel-Heiler", pct = 44 },
    }
end

local function FillRow(bar, entry)
    bar.name:SetText(entry.name or "?")
    bar.name:SetTextColor(NameColor(entry.unit))
    -- Klappt der Balken nicht, bleibt er leer; die Prozentzahl reicht dann
    if not pcall(bar.SetValue, bar, entry.pct) then bar:SetValue(0) end
    local okText = SetPercentText(bar.pct, entry.pct)
    local okColor, r, g, b = ColorFor(PERCENT_POINTS, percentCurve, entry.pct)
    if not (okColor and pcall(bar.SetStatusBarColor, bar, r, g, b)) then
        bar:SetStatusBarColor(0.5, 0.5, 0.5)
    end
    return okText
end

local function UpdateList()
    if not ns.db or not ns.db.threatList or not HAS_API then
        list:Hide()
        return
    end

    local entries, title
    if IsEnemy("target") then
        entries = CollectThreat("target")
        title = ns.Public(UnitName("target"))
    end
    if not entries or #entries == 0 then
        if not ns.IsConfigOpen() then
            list:Hide()
            return
        end
        entries, title = DemoEntries(), "Beispiel – Shift + ziehen"
    end

    header:SetText("Bedrohung · " .. (title or "?"))
    local shown = math.min(#entries, MAX_ROWS)
    local allOk = true
    for i = 1, MAX_ROWS do
        local bar = rows[i]
        if i <= shown then
            if not FillRow(bar, entries[i]) then allOk = false end
            bar:Show()
        else
            bar:Hide()
        end
    end
    if not allOk then
        NoticeLocked("Bedrohungsliste")
        list:Hide()
        return
    end
    list:SetHeight(28 + shown * (ROW_H + ROW_GAP))
    list:Show()
end

---------------------------------------------------------------------------
-- Namensplaketten: Rahmen und Prozent
---------------------------------------------------------------------------

-- Plakette → { border = { Rahmen, Kanten }, text = Prozentzahl }
local decorations = setmetatable({}, { __mode = "k" })

local function CreateBorder(health)
    local frame = CreateFrame("Frame", nil, health)
    frame:SetPoint("TOPLEFT", health, "TOPLEFT", -2, 2)
    frame:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 2, -2)
    local edges = {}
    local function Edge(p1, p2, horizontal)
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint(p1, frame, p1)
        t:SetPoint(p2, frame, p2)
        if horizontal then t:SetHeight(2) else t:SetWidth(2) end
        edges[#edges + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    frame.edges = edges
    frame:Hide()
    return frame
end

local function ColorBorder(border, r, g, b)
    for _, edge in ipairs(border.edges) do
        if not pcall(edge.SetVertexColor, edge, r, g, b) then return false end
    end
    return true
end

local function GetDecoration(plate)
    if decorations[plate] then return decorations[plate] end
    local unitFrame = plate.UnitFrame
    local health = unitFrame and (unitFrame.healthBar or unitFrame.HealthBar)
    if not health then return end

    local border = CreateBorder(health)

    local holder = CreateFrame("Frame", nil, health)
    holder:SetAllPoints(health)
    local text = holder:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    text:SetPoint("LEFT", health, "RIGHT", 5, 0)
    text:Hide()

    local deco = { border = border, text = text }
    decorations[plate] = deco
    return deco
end

local function PlateUnit(plate)
    return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function UpdatePlate(plate, unit)
    if plate.IsForbidden and plate:IsForbidden() then return end
    local deco = GetDecoration(plate)
    if not deco then return end

    local showBorder, showText = ns.db.threatPlates, ns.db.threatPercent
    local status, scaled
    if (showBorder or showText) and unit and UnitCanAttack("player", unit) then
        local _
        _, status, scaled = UnitDetailedThreatSituation("player", unit)
    end
    if not OnThreatList(status) then
        deco.border:Hide()
        deco.text:Hide()
        return
    end

    local okColor, r, g, b = ColorFor(STATUS_POINTS, statusCurve, status)

    if showBorder and okColor and ColorBorder(deco.border, r, g, b) then
        deco.border:Show()
    else
        deco.border:Hide()
        if showBorder then NoticeLocked("Rahmen an Namensplaketten") end
    end

    if showText and SetPercentText(deco.text, scaled) then
        if not (okColor and pcall(deco.text.SetTextColor, deco.text, r, g, b)) then
            deco.text:SetTextColor(1, 1, 1)
        end
        deco.text:Show()
    else
        deco.text:Hide()
        if showText then NoticeLocked("Prozent an Namensplaketten") end
    end
end

local function HideDecorations(part)
    for _, deco in pairs(decorations) do deco[part]:Hide() end
end

local function UpdatePlates()
    if not (ns.db.threatPlates or ns.db.threatPercent) then return end
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        pcall(UpdatePlate, plate, PlateUnit(plate))
    end
end

ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
    if not ns.db or not HAS_API or not (ns.db.threatPlates or ns.db.threatPercent) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then pcall(UpdatePlate, plate, unit) end
end)

ns.On("NAME_PLATE_UNIT_REMOVED", function(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local deco = plate and decorations[plate]
    if deco then
        deco.border:Hide()
        deco.text:Hide()
    end
end)

---------------------------------------------------------------------------
-- Takt: fünfmal pro Sekunde aktualisieren
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.2 then return end
    elapsed = 0
    if not HAS_API or not ns.db then return end
    pcall(UpdateList)
    pcall(UpdatePlates)
end)

ns.OnConfig(function() pcall(UpdateList) end)

ns.On("PLAYER_LOGIN", function()
    ns.RestorePosition(list)
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(2, "Bedrohung", {
    key = "threatList",
    preview = "threat_list",
    label = "Bedrohungsliste",
    tooltip = "Kleines Fenster mit einem Balken pro Gruppenmitglied für dein aktuelles Ziel: 100 % = hat die Aggro, je näher an 100 %, desto knapper. Die Reihenfolge ist fest (du zuerst), weil WoW Forever das Sortieren nach Bedrohung nicht erlaubt. Außerhalb des Kampfes ist es ausgeblendet.\n\nSolange das stray-Fenster offen ist, zeigt die Liste Beispielwerte – dann kannst du sie mit Shift + linker Maustaste verschieben.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = function(value)
        ns.db.threatList = value
        pcall(UpdateList)
    end,
})

ns.AddOption(2, "Bedrohung", {
    key = "threatPlates",
    preview = "threat_plates",
    label = "Rahmen an Namensplaketten",
    tooltip = "Rahmen um den Lebensbalken gegnerischer Namensplaketten: rot = du hast Aggro, gelb = die Aggro wechselt gleich, grün = du hast keine Aggro. Kein Rahmen = du stehst nicht auf seiner Bedrohungsliste.\n\nGegnerische Namensplaketten müssen eingeschaltet sein (Taste V).",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = function(value)
        ns.db.threatPlates = value
        if not value then HideDecorations("border") end
    end,
})

ns.AddOption(2, "Bedrohung", {
    key = "threatPercent",
    preview = "threat_percent",
    label = "Prozent an Namensplaketten",
    tooltip = "Zeigt rechts neben dem Lebensbalken gegnerischer Namensplaketten deine Bedrohung: 0 % = keine, 100 % = du hast die Aggro. Die Farbe passt zum Rahmen.\n\nGegnerische Namensplaketten müssen eingeschaltet sein (Taste V).",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = function(value)
        ns.db.threatPercent = value
        if not value then HideDecorations("text") end
    end,
})

ns.AddOption(2, "Bedrohung", {
    key = "threatTankWarn",
    preview = "threat_tankwarn",
    label = "Tank-Warnung",
    tooltip = "Verlierst du bei einem Gegner die Aggro, steht groß in der Bildschirmmitte, wen er jetzt angreift – mit Warnton.",
    isEnabled = NeverAvailable,
    disabledHint = NO_WARNINGS,
})

ns.AddOption(2, "Bedrohung", {
    key = "threatAggroWarn",
    preview = "threat_aggrowarn",
    label = "Aggro-Warnung ab 90 %",
    tooltip = "Für Schaden und Heiler: Erreichst du 90 % der Bedrohung, die zum Aggroziehen nötig ist, erscheint „Gleich ziehst du Aggro!“.",
    isEnabled = NeverAvailable,
    disabledHint = NO_WARNINGS,
})
