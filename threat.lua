-- stray – Bedrohung: Liste, Rahmen an Namensplaketten, Tank- und Aggro-Warnung
-- Nutzt die Bedrohungswerte, die der Server liefert (UnitDetailedThreatSituation / UnitThreatSituation).

local _, ns = ...

local HAS_API = (UnitDetailedThreatSituation and UnitThreatSituation) and true or false
local NO_API = "Diese Spielversion liefert keine Bedrohungswerte."

local function ApiAvailable() return HAS_API end

local function PlaySoundMaster(kit)
    if kit then PlaySound(kit, "Master") end
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
    GameTooltip:AddLine("Prozent = wie nah jemand daran ist, die Aggro zu ziehen.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    GameTooltip:AddLine("Shift + ziehen zum Verschieben", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
list:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function BarColor(entry)
    if entry.tanking then return 0.8, 0.12, 0.12 end -- hat Aggro
    if entry.pct >= 90 then return 0.85, 0.45, 0.1 end -- knapp
    if entry.pct >= 70 then return 0.8, 0.65, 0.15 end -- aufpassen
    return 0.3, 0.6, 0.18 -- sicher
end

local function NameColor(unit)
    if not unit or not UnitIsPlayer(unit) then return 1, 1, 1 end
    local _, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
            if UnitExists("raidpet" .. i) then units[#units + 1] = "raidpet" .. i end
        end
    else
        units[1] = "player"
        if UnitExists("pet") then units[#units + 1] = "pet" end
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

local function CollectThreat(mob)
    local entries = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then
            local isTanking, status, scaled = UnitDetailedThreatSituation(unit, mob)
            if status then -- nil = steht nicht auf der Bedrohungsliste
                entries[#entries + 1] = {
                    unit = unit,
                    name = UnitName(unit),
                    tanking = isTanking and true or false,
                    pct = isTanking and 100 or math.min(scaled or 0, 100),
                }
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.tanking ~= b.tanking then return a.tanking end
        return a.pct > b.pct
    end)
    return entries
end

local function DemoEntries()
    return {
        { unit = "player", name = (UnitName("player") or "Du"), tanking = true, pct = 100 },
        { name = "Beispiel-Magier", tanking = false, pct = 92 },
        { name = "Beispiel-Jäger", tanking = false, pct = 71 },
        { name = "Beispiel-Heiler", tanking = false, pct = 44 },
    }
end

local function UpdateList()
    if not ns.db or not ns.db.threatList or not HAS_API then
        list:Hide()
        return
    end

    local entries, title
    if IsEnemy("target") then
        entries = CollectThreat("target")
        title = UnitName("target")
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
    for i = 1, MAX_ROWS do
        local bar, entry = rows[i], entries[i]
        if i <= shown then
            bar:SetValue(entry.pct)
            bar:SetStatusBarColor(BarColor(entry))
            bar.name:SetText(entry.name or "?")
            bar.name:SetTextColor(NameColor(entry.unit))
            bar.pct:SetText(("%d %%"):format(math.floor(entry.pct + 0.5)))
            bar:Show()
        else
            bar:Hide()
        end
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

local function ShowWarning(f, message, sound)
    f.anim:Stop()
    f.text:SetText(message)
    f:SetAlpha(1)
    f:Show()
    f.anim:Play()
    PlaySoundMaster(sound)
end

---------------------------------------------------------------------------
-- Namensplaketten und Tank-Warnung
---------------------------------------------------------------------------

-- Status von UnitThreatSituation: 3 = du hast sicher Aggro, 2 = du hast Aggro, aber jemand
-- liegt vorn, 1 = du liegst vorn, hast aber noch keine Aggro, 0 = keine Aggro, nil = nicht auf der Liste
local PLATE_COLORS = {
    [3] = { 1, 0.15, 0.15 },
    [2] = { 1, 0.85, 0 },
    [1] = { 1, 0.85, 0 },
    [0] = { 0.25, 0.9, 0.25 },
}

local borders = setmetatable({}, { __mode = "k" }) -- Plakette → Rahmen

local function GetBorder(plate)
    if borders[plate] then return borders[plate] end
    local unitFrame = plate.UnitFrame
    local health = unitFrame and (unitFrame.healthBar or unitFrame.HealthBar)
    if not health then return end
    local border = CreateFrame("Frame", nil, health, ns.BACKDROP_TEMPLATE)
    border:SetPoint("TOPLEFT", health, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 2, -2)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    end
    border:Hide()
    borders[plate] = border
    return border
end

local function PlateUnit(plate)
    return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function UpdatePlate(plate, unit)
    if plate.IsForbidden and plate:IsForbidden() then return end
    local border = GetBorder(plate)
    if not border then return end
    local status = ns.db.threatPlates and unit and UnitCanAttack("player", unit) and UnitThreatSituation("player", unit)
    local color = status and PLATE_COLORS[status]
    if color then
        border:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        border:Show()
    else
        border:Hide()
    end
end

local function HideAllBorders()
    for _, border in pairs(borders) do border:Hide() end
end

local lastStatus, lastWarn = {}, {}

local function CheckLost(unit)
    if not IsEnemy(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local status = UnitThreatSituation("player", unit)
    local previous = lastStatus[guid]
    lastStatus[guid] = status
    if not ns.db.threatTankWarn then return end
    if previous and previous >= 2 and status and status < 2 then
        local now = GetTime()
        if (lastWarn[guid] or 0) + 3 > now then return end
        lastWarn[guid] = now
        local mob = UnitName(unit) or "?"
        local victim = UnitName(unit .. "target")
        -- Kein Pfeilzeichen: die WoW-Schrift kennt es nicht
        local message = victim and ("Aggro verloren: %s greift %s an"):format(mob, victim) or ("Aggro verloren: %s"):format(mob)
        ShowWarning(tankWarning, message, SOUNDKIT.RAID_WARNING)
    end
end

local function UpdateEnemies()
    local doPlates, doTank = ns.db.threatPlates, ns.db.threatTankWarn
    if not doPlates and not doTank then return end
    local seen = {}
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = PlateUnit(plate)
            if doPlates then UpdatePlate(plate, unit) end
            if unit and doTank then
                local guid = UnitGUID(unit)
                if guid and not seen[guid] then
                    seen[guid] = true
                    CheckLost(unit)
                end
            end
        end
    end
    -- Das aktuelle Ziel auch ohne sichtbare Plakette prüfen
    local targetGUID = UnitGUID("target")
    if doTank and targetGUID and not seen[targetGUID] then CheckLost("target") end
end

ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
    if not ns.db or not ns.db.threatPlates or not HAS_API then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then UpdatePlate(plate, unit) end
end)

ns.On("NAME_PLATE_UNIT_REMOVED", function(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate and borders[plate] then borders[plate]:Hide() end
end)

---------------------------------------------------------------------------
-- Aggro-Warnung für Schaden und Heiler
---------------------------------------------------------------------------

local armed = true

local function CheckAggro()
    if not ns.db.threatAggroWarn then return end
    if not IsEnemy("target") then
        armed = true
        return
    end
    -- Tankt das eigene Begleittier (Jäger, Hexenmeister), ist hohe Bedrohung gewollt
    if UnitExists("pet") and UnitIsUnit("targettarget", "pet") then return end
    local isTanking, _, scaled = UnitDetailedThreatSituation("player", "target")
    if isTanking or not scaled then return end
    if scaled >= 90 and armed then
        armed = false
        ShowWarning(aggroWarning, ("Gleich ziehst du Aggro! %d %%"):format(math.floor(scaled)), SOUNDKIT.RAID_WARNING)
    elseif scaled < 80 then
        armed = true
    end
end

ns.On("PLAYER_TARGET_CHANGED", function() armed = true end)

ns.On("PLAYER_REGEN_ENABLED", function()
    wipe(lastStatus)
    wipe(lastWarn)
    armed = true
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
    UpdateList()
    UpdateEnemies()
    CheckAggro()
end)

ns.OnConfig(function() UpdateList() end)

ns.On("PLAYER_LOGIN", function()
    ns.RestorePosition(list)
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(2, "Bedrohung", {
    key = "threatList",
    label = "Bedrohungsliste",
    tooltip = "Kleines Fenster mit einem Balken pro Gruppenmitglied für dein aktuelles Ziel: Wer hat Aggro, wer ist kurz davor? Außerhalb des Kampfes ist es ausgeblendet.\n\nSolange das stray-Fenster offen ist, zeigt die Liste Beispielwerte – dann kannst du sie mit Shift + linker Maustaste verschieben.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = function(value)
        ns.db.threatList = value
        UpdateList()
    end,
})

ns.AddOption(2, "Bedrohung", {
    key = "threatPlates",
    label = "Rahmen an Namensplaketten",
    tooltip = "Rahmen um den Lebensbalken gegnerischer Namensplaketten: rot = du hast Aggro, gelb = die Aggro wechselt gleich, grün = du hast keine Aggro. Kein Rahmen = du stehst nicht auf seiner Bedrohungsliste.\n\nGegnerische Namensplaketten müssen eingeschaltet sein (Taste V).",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
    set = function(value)
        ns.db.threatPlates = value
        if not value then HideAllBorders() end
    end,
})

ns.AddOption(2, "Bedrohung", {
    key = "threatTankWarn",
    label = "Tank-Warnung",
    tooltip = "Verlierst du bei einem Gegner die Aggro, steht groß in der Bildschirmmitte, wen er jetzt angreift – mit Warnton.\n\nPrüft dein Ziel und alle Gegner mit sichtbarer Namensplakette (Taste V).",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
})

ns.AddOption(2, "Bedrohung", {
    key = "threatAggroWarn",
    label = "Aggro-Warnung ab 90 %",
    tooltip = "Für Schaden und Heiler: Erreichst du 90 % der Bedrohung, die zum Aggroziehen nötig ist, erscheint „Gleich ziehst du Aggro!“ – Zeit, langsamer zu machen. Wer die Aggro schon hat, bekommt keine Warnung.",
    isEnabled = ApiAvailable,
    disabledHint = NO_API,
})
