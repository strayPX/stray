-- stray – Quest-Gegner: gelbes Ausrufezeichen und Fortschritt („3/8“) an der Namensplakette
-- von Gegnern, die man für eine offene Quest töten oder plündern muss.
-- Erkennung über die Tooltipdaten der Einheit (Questziel-Zeilen). Nur außerhalb von Instanzen
-- und nur außerhalb des Kampfes neu ausgewertet; im Kampf bleibt die Markierung, wie sie war.
-- Eigene Rahmen aus einem Pool, verwaltet nach Unit-Token – auf die Plakette wird nichts geschrieben.
-- Platz: links neben dem Lebensbalken (Bedrohung sitzt rechts und als Rahmen um den Balken).

local _, ns = ...

ns.defaults.questMobMarks = false

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local FONT_BODY = "Fonts\\ARIALN.TTF"

local pool = {}   -- freie Markierungen
local active = {} -- [Unit-Token] = Markierung

---------------------------------------------------------------------------
-- Markierungen (Pool)
---------------------------------------------------------------------------

local function NewMarker()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(14, 14)
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetAllPoints()
    f.icon:SetTexture(QUEST_ICON)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFontObject(GameFontHighlightSmall)
    pcall(f.text.SetFont, f.text, FONT_BODY, 10, "OUTLINE")
    f.text:SetTextColor(1, 0.82, 0)
    f.text:SetPoint("RIGHT", f, "LEFT", -1, 0)
    f:Hide()
    return f
end

local function Release(unit)
    local marker = active[unit]
    if not marker then return end
    active[unit] = nil
    marker:Hide()
    marker:ClearAllPoints()
    marker:SetParent(UIParent)
    table.insert(pool, marker)
end

local function ReleaseAll()
    for unit in pairs(active) do Release(unit) end
end

local function HealthBar(plate)
    local unitFrame = plate.UnitFrame
    return unitFrame and (unitFrame.healthBar or unitFrame.HealthBar) or nil
end

local function Attach(unit, plate, text)
    local marker = active[unit]
    if not marker then
        marker = table.remove(pool) or NewMarker()
        active[unit] = marker
    end
    marker:SetParent(plate)
    marker:SetFrameLevel(plate:GetFrameLevel() + 10)
    marker:ClearAllPoints()
    local health = HealthBar(plate)
    if health then
        marker:SetPoint("RIGHT", health, "LEFT", -3, 0)
    else
        marker:SetPoint("RIGHT", plate, "LEFT", 0, 0)
    end
    marker.text:SetText(text or "")
    marker:Show()
end

---------------------------------------------------------------------------
-- Auswertung
---------------------------------------------------------------------------

local function InInstance()
    if not IsInInstance then return false end
    local ok, inside = pcall(IsInInstance)
    if not ok or ns.IsSecret(inside) then return true end -- im Zweifel: still bleiben
    return inside and true or false
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function Public(value, kind)
    value = ns.Public(value)
    if type(value) == kind then return value end
    return nil
end

-- Offenes Questziel aus den Tooltipdaten: Text „3/8“ (oder „40 %“), "" wenn ohne Zahl, nil wenn keins
local function QuestObjective(unit)
    if not C_TooltipInfo or not C_TooltipInfo.GetUnit or not Enum or not Enum.TooltipDataLineType then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or ns.IsSecret(data) or type(data) ~= "table" then return nil end
    local lines = ns.Public(data.lines)
    if type(lines) ~= "table" then return nil end

    local LT = Enum.TooltipDataLineType
    local myName = Public(UnitName("player"), "string")
    local mine = true     -- Ziele unter dem Namen eines Mitspielers gehören nicht uns
    local questID = nil

    for _, line in ipairs(lines) do
        if type(line) == "table" then
            local kind = Public(line.type, "number")
            if kind == LT.QuestTitle then
                mine = true
                questID = Public(line.id, "number")
            elseif kind == LT.QuestPlayer then
                local name = Public(line.leftText, "string")
                mine = (name ~= nil and myName ~= nil and name == myName)
            elseif kind == LT.QuestObjective and mine then
                local completed = ns.Public(line.completed)
                local onQuest = true
                if questID and C_QuestLog and C_QuestLog.IsOnQuest then
                    local okOn, on = pcall(C_QuestLog.IsOnQuest, questID)
                    on = okOn and ns.Public(on)
                    if on == false then onQuest = false end
                end
                if completed == false and onQuest then
                    local have = Public(line.numFulfilled, "number")
                    local need = Public(line.numRequired, "number")
                    local text = Public(line.leftText, "string")
                    -- Prozentziele haben nur 0/1 in den Zahlenfeldern, der Wert steht im Text
                    local pct = text and text:match("(%d+)%s*%%")
                    if pct then return pct .. " %" end
                    if have and need and need > 0 then return have .. "/" .. need end
                    if text then
                        local a, b = text:match("(%d+)%s*/%s*(%d+)")
                        if a then return a .. "/" .. b end
                    end
                    return ""
                end
            end
        end
    end
    return nil
end

local function Evaluate(unit)
    if type(unit) ~= "string" or ns.IsSecret(unit) then return end
    if not (ns.db and ns.db.questMobMarks) or InInstance() then
        Release(unit)
        return
    end
    -- Im Kampf nicht neu auswerten: Markierung bleibt, wie sie war
    if InCombat() then return end

    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then
        Release(unit)
        return
    end
    local isPlayer = ns.Public(UnitIsPlayer(unit))
    if isPlayer ~= false then
        Release(unit)
        return
    end

    local text = QuestObjective(unit)
    if text then
        Attach(unit, plate, text)
    else
        Release(unit)
    end
end

local function RefreshAll()
    if not (ns.db and ns.db.questMobMarks) or InInstance() then
        ReleaseAll()
        return
    end
    if InCombat() then return end
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    -- Erst Verwaistes aufräumen, dann alle sichtbaren Plaketten prüfen
    for unit in pairs(active) do
        if not C_NamePlate.GetNamePlateForUnit(unit) then Release(unit) end
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then pcall(Evaluate, unit) end
    end
end

-- Questlog-Änderungen kommen oft in Schüben: gedrosselt neu auswerten
local refreshTimer = false
local function ScheduleRefresh()
    if refreshTimer or not (ns.db and ns.db.questMobMarks) then return end
    refreshTimer = true
    C_Timer.After(0.3, function()
        refreshTimer = false
        pcall(RefreshAll)
    end)
end

---------------------------------------------------------------------------
-- Ereignisse (eigener Rahmen, Registrierung abgesichert)
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE",
    "UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, unit)
    if not ns.db then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" and not ns.IsSecret(unit) then Release(unit) end
        return
    end
    if not ns.db.questMobMarks then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        pcall(Evaluate, unit)
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if unit == "player" then ScheduleRefresh() end
    else
        ScheduleRefresh()
    end
end)

---------------------------------------------------------------------------
-- Option
---------------------------------------------------------------------------

ns.AddOption(2, "Quests", {
    key = "questMobMarks",
    label = "Quest-Gegner markieren",
    tooltip = "Gegner, die du für eine offene Quest töten oder plündern musst, bekommen links an der Namensplakette ein gelbes Ausrufezeichen und deinen Fortschritt, z. B. „3/8“.\n\nNur außerhalb von Instanzen. Im Kampf bleibt die Markierung stehen und wird danach aktualisiert. Gegnerische Namensplaketten müssen eingeschaltet sein (Taste V).",
    set = function(value)
        ns.db.questMobMarks = value
        if value then pcall(RefreshAll) else ReleaseAll() end
    end,
})
