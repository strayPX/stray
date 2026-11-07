-- stray – Bedrohung: Liste, Rahmen und Prozent an Namensplaketten, Tank- und Aggro-Warnung
--
-- WoW Forever versiegelt manche Bedrohungswerte („geheime Werte“, secret values). Damit darf
-- ein Addon nicht vergleichen, nicht rechnen und nicht testen – auch „== nil“ ist verboten,
-- nur type() und ns.IsSecret() sind erlaubt. Deshalb gilt hier überall: erst ns.IsSecret()
-- prüfen, dann auswerten. Versiegelte Einzelwerte werden still übersprungen oder nur an
-- Anzeige-Funktionen (Text, Balken, Farbkurven von C_CurveUtil) weitergereicht.
--
-- Lesbar sind nach bisherigen Erkenntnissen:
--   UnitThreatSituation("player", Gegner)         → Status 0–3 / nil (Rahmen, Tank-Warnung)
--   UnitDetailedThreatSituation(Gruppe, "target") → Werte der Liste (dann sortiert)
-- Versiegelt sein kann vor allem UnitDetailedThreatSituation("player", Plakette) (nur Anzeige).
--
-- Aktualisiert wird ereignisbasiert (zusammengefasst, höchstens 10×/s) und im Kampf zusätzlich
-- etwa einmal pro Sekunde. Die Ereignisse sind nur registriert, solange eine Option an ist.
-- Alles Auswertende läuft in pcall, damit nie eine Fehlerflut entsteht.

local _, ns = ...

local HAS_API = (UnitDetailedThreatSituation and UnitThreatSituation) and true or false
local NO_API = "Diese Spielversion liefert keine Bedrohungswerte."

local function ApiAvailable() return HAS_API end

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

-- Lesbares UnitIsUnit: true/false, versiegelt → nil
local function SameUnit(a, b)
    local same = UnitIsUnit(a, b)
    if IsSecret(same) then return nil end
    return same and true or false
end

local function IsEnemy(unit)
    return UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit)
end

local function PlaySoundMaster(kit)
    if kit then PlaySound(kit, "Master") end
end

---------------------------------------------------------------------------
-- Farben: Tabellen für lesbare Werte, Farbkurven für versiegelte
---------------------------------------------------------------------------

local GREEN, YELLOW, ORANGE, RED = { 0.25, 0.9, 0.25 }, { 1, 0.85, 0 }, { 1, 0.55, 0.1 }, { 1, 0.15, 0.15 }

-- Status von UnitThreatSituation: 3 = du hast sicher Aggro, 2 = du hast Aggro, aber jemand
-- liegt vorn, 1 = du liegst vorn, hast aber noch keine Aggro, 0 = keine Aggro, nil = nicht auf der Liste
local STATUS_COLORS = { [0] = GREEN, [1] = YELLOW, [2] = YELLOW, [3] = RED }
local STATUS_POINTS = { { 0, GREEN }, { 1, YELLOW }, { 3, RED } }
-- Prozent bis zur Aggro (Liste und Plaketten-Zahl)
local PERCENT_POINTS = { { 0, GREEN }, { 70, YELLOW }, { 90, ORANGE }, { 100, RED } }

-- Lesbarer Status als Zahl, sonst nil (versiegelt, nil oder unerwarteter Typ)
local function PlainStatus(status)
    if IsSecret(status) or type(status) ~= "number" then return nil end
    return status
end

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
    GameTooltip:AddLine("Sortiert: wer die Aggro hat zuerst, dann nach Bedrohung. Liefert WoW Forever versiegelte Werte, bleibt die Reihenfolge fest (du zuerst).", 0.7, 0.7, 0.7, true)
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
    -- Du (und dein Begleiter) immer zuerst – im Raid nur einmal
    units[1] = "player"
    if UnitExists("pet") then units[#units + 1] = "pet" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit, pet = "raid" .. i, "raidpet" .. i
            -- Versiegeltes UnitIsUnit: lieber aufnehmen als jemanden verlieren
            if SameUnit(unit, "player") ~= true then
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

-- Gibt die Einträge zurück und ob sie sortiert werden konnten.
-- Sind alle Werte lesbar: sortiert (wer tankt zuerst, dann Prozent absteigend).
-- Ist irgendein Wert versiegelt: feste Reihenfolge, Werte nur zur Anzeige.
local function CollectThreat(mob)
    local raw, anySecret = {}, false
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then
            local isTanking, status, scaled = UnitDetailedThreatSituation(unit, mob)
            if IsSecret(isTanking) or IsSecret(status) or IsSecret(scaled) then
                anySecret = true
            end
            if OnThreatList(status) then
                raw[#raw + 1] = { unit = unit, isTanking = isTanking, scaled = scaled }
            end
        end
    end

    local entries = {}
    if anySecret then
        -- Rückfall: unsortiert, Werte werden nur weitergereicht
        for _, r in ipairs(raw) do
            entries[#entries + 1] = { unit = r.unit, name = ns.Public(UnitName(r.unit)), pct = r.scaled }
        end
        return entries, false
    end

    -- Alles lesbar: rechnen und sortieren erlaubt
    for _, r in ipairs(raw) do
        local tanking = r.isTanking and true or false
        local pct = 0
        if tanking then
            pct = 100
        elseif type(r.scaled) == "number" then
            pct = math.min(r.scaled, 100)
        end
        entries[#entries + 1] = { unit = r.unit, name = ns.Public(UnitName(r.unit)), tanking = tanking, pct = pct }
    end
    table.sort(entries, function(a, b)
        if a.tanking ~= b.tanking then return a.tanking end
        return a.pct > b.pct
    end)
    return entries, true
end

local function DemoEntries()
    return {
        { unit = "player", name = ns.Public(UnitName("player")) or "Du", pct = 100 },
        { name = "Beispiel-Magier", pct = 92 },
        { name = "Beispiel-Jäger", pct = 71 },
        { name = "Beispiel-Heiler", pct = 44 },
    }
end

-- Für lesbare und versiegelte Prozentwerte: Balken, Text und Farbe nur über Anzeige-Funktionen
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
-- Warnungen in der Bildschirmmitte
---------------------------------------------------------------------------

local function CreateWarning(y, r, g, b, size)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(900, 40)
    f:SetPoint("TOP", UIParent, "TOP", 0, y)
    f:SetFrameStrata("HIGH")
    f:Hide()

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    f.text:SetTextColor(r, g, b)
    f.text:SetPoint("CENTER")

    f.anim = f:CreateAnimationGroup()
    local fade = f.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(2)
    fade:SetDuration(0.6)
    f.anim:SetScript("OnFinished", function() f:Hide() end)
    return f
end

local tankWarning = CreateWarning(-150, 1, 0.23, 0.23, 24)
local aggroWarning = CreateWarning(-190, 1, 0.69, 0.13, 19)

local function ShowWarning(f, message)
    f.anim:Stop()
    f.text:SetText(message)
    f:SetAlpha(1)
    f:Show()
    f.anim:Play()
    PlaySoundMaster(SOUNDKIT and SOUNDKIT.RAID_WARNING)
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
    if not ((showBorder or showText) and unit and UnitCanAttack("player", unit)) then
        deco.border:Hide()
        deco.text:Hide()
        return
    end

    -- Lesbarer Status (wie bei EllesmereUI): bestimmt den Rahmen und bevorzugt die Textfarbe
    local rawStatus = UnitThreatSituation("player", unit)
    local statusSecret = IsSecret(rawStatus)
    local status = PlainStatus(rawStatus)
    local statusColor = status and STATUS_COLORS[status]

    -- Rahmen nur mit lesbarem Status; versiegelt oder nil → kein Rahmen
    if showBorder and statusColor and ColorBorder(deco.border, statusColor[1], statusColor[2], statusColor[3]) then
        deco.border:Show()
    else
        deco.border:Hide()
    end

    -- Prozent: reine Anzeige, der Wert kann versiegelt sein
    if not showText then
        deco.text:Hide()
        return
    end
    local _, detailStatus, scaled = UnitDetailedThreatSituation("player", unit)
    local onList
    if statusSecret then
        onList = OnThreatList(detailStatus)
    else
        onList = status ~= nil
    end
    if not onList then
        deco.text:Hide()
        return
    end
    if SetPercentText(deco.text, scaled) then
        local okColor, r, g, b
        if statusColor then
            okColor, r, g, b = true, statusColor[1], statusColor[2], statusColor[3]
        else
            okColor, r, g, b = ColorFor(STATUS_POINTS, statusCurve, detailStatus)
        end
        if not (okColor and pcall(deco.text.SetTextColor, deco.text, r, g, b)) then
            deco.text:SetTextColor(1, 1, 1)
        end
        deco.text:Show()
    else
        deco.text:Hide()
        NoticeLocked("Prozent an Namensplaketten")
    end
end

-- part = "border" oder "text"; ohne part beides
local function HideDecorations(part)
    for _, deco in pairs(decorations) do
        if part then
            deco[part]:Hide()
        else
            deco.border:Hide()
            deco.text:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Tank-Warnung: Status je Gegner merken, Abfall von ≥ 2 auf < 2 melden
---------------------------------------------------------------------------

local lastStatus = {} -- [GUID] = letzter lesbarer Status
local lastWarn = {}   -- [GUID] = Zeit der letzten Warnung (3 s Sperre)

-- Lesbare GUID oder nil (versiegelt → überspringen)
local function PlainGUID(unit)
    local guid = UnitGUID(unit)
    if IsSecret(guid) or type(guid) ~= "string" then return nil end
    return guid
end

local function CheckLost(unit, guid)
    if not IsEnemy(unit) then return end
    local rawStatus = UnitThreatSituation("player", unit)
    -- Versiegelt: still überspringen, den alten Stand behalten
    if IsSecret(rawStatus) then return end
    local status = PlainStatus(rawStatus)
    local previous = lastStatus[guid]
    lastStatus[guid] = status
    if previous and previous >= 2 and status and status < 2 then
        -- Übernimmt das eigene Begleittier den Gegner, ist das gewollt – keine Warnung
        if UnitExists("pet") and SameUnit(unit .. "target", "pet") == true then return end
        local now = GetTime()
        if (lastWarn[guid] or 0) + 3 > now then return end
        lastWarn[guid] = now
        local mob = ns.Public(UnitName(unit)) or "?"
        local victim = ns.Public(UnitName(unit .. "target"))
        -- Kein Pfeilzeichen: die WoW-Schrift kennt es nicht
        local message
        if type(victim) == "string" then
            message = ("Aggro verloren: %s greift %s an"):format(mob, victim)
        else
            message = ("Aggro verloren: %s"):format(mob)
        end
        ShowWarning(tankWarning, message)
    end
end

-- Plaketten aktualisieren und (falls an) die Tank-Warnung je Gegner prüfen
local function UpdateEnemies()
    local doPlates = ns.db.threatPlates or ns.db.threatPercent
    local doTank = ns.db.threatTankWarn
    if not doPlates and not doTank then return end
    local seen = {}
    local tankFailed = false
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = PlateUnit(plate)
            if doPlates then pcall(UpdatePlate, plate, unit) end
            if unit and doTank then
                local guid = PlainGUID(unit)
                if guid and not seen[guid] then
                    seen[guid] = true
                    if not pcall(CheckLost, unit, guid) then tankFailed = true end
                end
            end
        end
    end
    -- Das aktuelle Ziel auch ohne sichtbare Plakette prüfen
    if doTank then
        local guid = PlainGUID("target")
        if guid and not seen[guid] then
            if not pcall(CheckLost, "target", guid) then tankFailed = true end
        end
    end
    if tankFailed then NoticeLocked("Tank-Warnung") end
end

---------------------------------------------------------------------------
-- Aggro-Warnung ab 90 %
---------------------------------------------------------------------------

local armed = true

local function CheckAggro()
    if not ns.db.threatAggroWarn then return end
    if not IsEnemy("target") then
        armed = true
        return
    end
    -- Tankt das eigene Begleittier (Jäger, Hexenmeister), ist hohe Bedrohung gewollt.
    -- Versiegeltes Ergebnis (nil): lieber nicht warnen.
    if UnitExists("pet") and SameUnit("targettarget", "pet") ~= false then return end
    local isTanking, _, scaled = UnitDetailedThreatSituation("player", "target")
    if IsSecret(isTanking) or IsSecret(scaled) then return end
    -- Wer die Aggro schon hat, bekommt keine Warnung
    if isTanking or type(scaled) ~= "number" then return end
    if scaled >= 90 and armed then
        armed = false
        ShowWarning(aggroWarning, ("Gleich ziehst du Aggro! %d %%"):format(math.floor(scaled)))
    elseif scaled < 80 then
        armed = true
    end
end

---------------------------------------------------------------------------
-- Takt: ereignisbasiert zusammengefasst, im Kampf zusätzlich etwa 1×/s
---------------------------------------------------------------------------

local function Flush()
    if not HAS_API or not ns.db then return end
    pcall(UpdateList)
    pcall(UpdateEnemies)
    if not pcall(CheckAggro) then NoticeLocked("Aggro-Warnung") end
end

local driver = CreateFrame("Frame")
driver:Hide()
local sinceRun, pending, inCombat = 0, false, false

-- Läuft nur, solange etwas ansteht oder Kampf ist
driver:SetScript("OnUpdate", function(self, delta)
    sinceRun = sinceRun + delta
    if pending then
        if sinceRun < 0.1 then return end
    elseif inCombat then
        if sinceRun < 1 then return end
    else
        self:Hide()
        return
    end
    pending = false
    sinceRun = 0
    Flush()
end)

-- Aktualisierung anmelden; mehrere Ereignisse kurz hintereinander ergeben einen Durchlauf
local function Request()
    pending = true
    driver:Show()
end

local EVENTS = {
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_THREAT_LIST_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
    "GROUP_ROSTER_UPDATE",
    "UNIT_PET",
}

local events = CreateFrame("Frame")
local registered = false

events:SetScript("OnEvent", function(_, event, unit)
    if not ns.db then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        -- Neue Plakette sofort schmücken, damit nichts flackert
        if ns.db.threatPlates or ns.db.threatPercent then
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
            if plate then pcall(UpdatePlate, plate, unit) end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
        local deco = plate and decorations[plate]
        if deco then
            deco.border:Hide()
            deco.text:Hide()
        end
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        armed = true
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        wipe(lastStatus)
        wipe(lastWarn)
        armed = true
    end
    Request()
end)

local function AnyEnabled()
    local db = ns.db
    return db and (db.threatList or db.threatPlates or db.threatPercent or db.threatTankWarn or db.threatAggroWarn) and true or false
end

-- Ereignisse nur registrieren, solange mindestens eine Bedrohungsoption an ist
local function RefreshEvents()
    local want = HAS_API and AnyEnabled()
    if want == registered then return end
    registered = want
    for _, event in ipairs(EVENTS) do
        if want then
            pcall(events.RegisterEvent, events, event)
        else
            pcall(events.UnregisterEvent, events, event)
        end
    end
    if want then
        inCombat = InCombatLockdown() and true or false
        Request()
    else
        inCombat, pending = false, false
        driver:Hide()
        wipe(lastStatus)
        wipe(lastWarn)
        armed = true
        list:Hide()
        HideDecorations()
    end
end

ns.OnConfig(function() pcall(UpdateList) end)

ns.On("PLAYER_LOGIN", function()
    ns.RestorePosition(list)
    RefreshEvents()
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

-- Wert speichern, Ereignisse neu bewerten, Anzeigen aktualisieren bzw. ausblenden
local function Setter(key, after)
    return function(value)
        ns.db[key] = value
        RefreshEvents()
        if after then after(value) end
        Request()
    end
end

ns.AddOption(2, "Bedrohung", {
    key = "threatList",
    preview = "threat_list",
    label = "Bedrohungsliste",
    tooltip = "Zeigt die Bedrohung deiner Gruppe für dein aktuelles Ziel. Ein Balken pro Gruppenmitglied und Begleiter: 100 % = hat die Aggro, je näher an 100 %, desto knapper. Sortiert wird nach Bedrohung (wer die Aggro hat, steht oben); liefert WoW Forever versiegelte Werte, bleibt die Reihenfolge fest (du zuerst). Funktioniert auch solo; außerhalb des Kampfes ist die Liste ausgeblendet.\n\nSolange das stray-Fenster offen ist, zeigt die Liste Beispielwerte – dann kannst du sie mit Shift + linker Maustaste verschieben.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("threatList", function() pcall(UpdateList) end),
})

ns.AddOption(2, "Bedrohung", {
    key = "threatPlates",
    preview = "threat_plates",
    label = "Rahmen an Namensplaketten",
    tooltip = "Farbiger Rahmen an gegnerischen Namensplaketten zeigt deinen Aggro-Status. Rot = du hast Aggro, gelb = die Aggro wechselt gleich, grün = du hast keine Aggro. Kein Rahmen = du stehst nicht auf seiner Bedrohungsliste.\n\nGegnerische Namensplaketten müssen eingeschaltet sein (Taste V).",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("threatPlates", function(value)
        if not value then HideDecorations("border") end
    end),
})

ns.AddOption(2, "Bedrohung", {
    key = "threatPercent",
    preview = "threat_percent",
    label = "Prozent an Namensplaketten",
    tooltip = "Zeigt deine Bedrohung in Prozent neben gegnerischen Namensplaketten. 0 % = keine, 100 % = du hast die Aggro. Die Farbe passt zum Rahmen.\n\nGegnerische Namensplaketten müssen eingeschaltet sein (Taste V).",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("threatPercent", function(value)
        if not value then HideDecorations("text") end
    end),
})

ns.AddOption(2, "Bedrohung", {
    key = "threatTankWarn",
    preview = "threat_tankwarn",
    label = "Tank-Warnung",
    tooltip = "Warnt mit Ton und großem Text, wenn du bei einem Gegner die Aggro verlierst. In der Bildschirmmitte steht dann, wen er jetzt angreift. Geprüft werden dein Ziel und alle Gegner mit sichtbarer Namensplakette; auch solo aktiv.\n\nDamit mehr als dein Ziel geprüft wird, müssen gegnerische Namensplaketten eingeschaltet sein (Taste V).",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("threatTankWarn"),
})

ns.AddOption(2, "Bedrohung", {
    key = "threatAggroWarn",
    preview = "threat_aggrowarn",
    label = "Aggro-Warnung ab 90 %",
    tooltip = "Warnt, kurz bevor du deinem Ziel die Aggro abnimmst. Erreichst du 90 % der Bedrohung, die zum Aggroziehen nötig ist, erscheint „Gleich ziehst du Aggro!“ – Zeit, langsamer zu machen. Wer die Aggro schon hat oder wessen Begleiter tankt, bekommt keine Warnung; unter 80 % oder nach einem Zielwechsel ist sie wieder bereit.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = Setter("threatAggroWarn"),
})
