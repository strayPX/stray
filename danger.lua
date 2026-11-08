-- stray – Warnung vor gefährlichen Gegnern: Totenkopf an der Namensplakette von Elite-Gegnern
-- und Gegnern ab „eigene Stufe + X“ (auch „??“), dazu ein kurzer Hinweis oben am Bildschirm.
-- Ausgewertet wird nur außerhalb des Kampfes; im Kampf bleibt das Symbol, wie es war.
-- In Instanzen nur das Symbol, kein Hinweis. Kein Richtungspfeil (Gegnerpositionen sind gesperrt).
-- Platz: oben rechts über dem Lebensbalken (Bedrohung: Rahmen um den Balken und Prozent rechts daneben,
-- Quest-Gegner: links daneben). Eigene Rahmen aus einem Pool, nichts wird auf die Plakette geschrieben.

local _, ns = ...
local L = ns.L

ns.defaults.dangerWarn = false
ns.defaults.dangerLevels = 3

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local REPEAT_DELAY = 10 -- Sekunden bis zum nächsten Hinweis für denselben Namen

local CLASS_LABELS = {
    elite = L["Elite"],
    rareelite = L["Seltene Elite"],
    worldboss = L["Weltboss"],
}

local pool = {}    -- freie Symbole
local active = {}  -- [Unit-Token] = Symbol
local lastWarn = {} -- [Name] = GetTime() des letzten Hinweises

---------------------------------------------------------------------------
-- Hinweis oben am Bildschirm (verschiebbar)
---------------------------------------------------------------------------

local notice = CreateFrame("Frame", nil, UIParent)
notice:SetSize(520, 30)
notice:SetPoint("TOP", UIParent, "TOP", 0, -115)
notice:SetFrameStrata("HIGH")
notice:Hide()
notice.text = notice:CreateFontString(nil, "OVERLAY")
notice.text:SetFont(STANDARD_TEXT_FONT, 17, "OUTLINE")
notice.text:SetTextColor(1, 0.33, 0.28)
notice.text:SetPoint("CENTER")

notice.anim = notice:CreateAnimationGroup()
local fade = notice.anim:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0)
fade:SetStartDelay(2.5)
fade:SetDuration(0.6)
notice.anim:SetScript("OnFinished", function() notice:Hide() end)

ns.MakeMovable(notice, "dangerwarn", { "TOP", "TOP", 0, -115 })
notice:EnableMouse(false) -- fängt sonst Mausklicks in der Spielwelt ab

local SAMPLE = L["Gefährlich: Murloc-Orakel (Elite, Stufe 32)"]
local sampleShown = false

local function ShowSample(on)
    if on and ns.db and ns.db.dangerWarn then
        sampleShown = true
        notice.anim:Stop()
        notice.text:SetText(SAMPLE)
        notice:SetAlpha(1)
        notice:Show()
        -- Bei offenem stray-Fenster mit Shift + Ziehen verschiebbar
        notice:EnableMouse(true)
    elseif sampleShown then
        sampleShown = false
        notice.anim:Stop()
        notice:EnableMouse(false)
        notice:Hide()
    end
end

ns.RegisterMovable(notice, "Gefahr-Hinweis", ShowSample)
ns.OnConfig(ShowSample)

local function PlayNoticeSound()
    local kit = SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081
    pcall(PlaySound, kit)
end

local function ShowNotice(message)
    if ns.IsConfigOpen() then return end -- Beispieltext nicht überschreiben
    notice.anim:Stop()
    notice.text:SetText(message)
    notice:SetAlpha(1)
    notice:Show()
    notice.anim:Play()
    PlayNoticeSound()
end

---------------------------------------------------------------------------
-- Symbole an Namensplaketten (Pool)
---------------------------------------------------------------------------

local function NewSkull()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(14, 14)
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetAllPoints()
    f.icon:SetTexture(SKULL)
    f:Hide()
    return f
end

local function Release(unit)
    local skull = active[unit]
    if not skull then return end
    active[unit] = nil
    skull:Hide()
    skull:ClearAllPoints()
    skull:SetParent(UIParent)
    table.insert(pool, skull)
end

local function ReleaseAll()
    for unit in pairs(active) do Release(unit) end
end

local function Attach(unit, plate)
    local skull = active[unit]
    if not skull then
        skull = table.remove(pool) or NewSkull()
        active[unit] = skull
    end
    skull:SetParent(plate)
    skull:SetFrameLevel(plate:GetFrameLevel() + 10)
    skull:ClearAllPoints()
    local unitFrame = plate.UnitFrame
    local health = unitFrame and (unitFrame.healthBar or unitFrame.HealthBar)
    if health then
        skull:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 3)
    else
        skull:SetPoint("BOTTOM", plate, "TOP", 0, 0)
    end
    skull:Show()
end

---------------------------------------------------------------------------
-- Auswertung
---------------------------------------------------------------------------

local function InInstance()
    if not IsInInstance then return false end
    local ok, inside = pcall(IsInInstance)
    if not ok or ns.IsSecret(inside) then return true end -- im Zweifel wie in einer Instanz
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

-- Gefährlich? Dann Klassifizierungstext (oder nil) und Stufentext zurück, sonst nil
local function Assess(unit)
    if Public(UnitIsPlayer(unit), "boolean") ~= false then return nil end
    if Public(UnitCanAttack("player", unit), "boolean") ~= true then return nil end
    if Public(UnitIsDead(unit), "boolean") == true then return nil end

    local classification = Public(UnitClassification(unit), "string")
    local classLabel = classification and CLASS_LABELS[classification]
    local level = Public(UnitLevel(unit), "number")
    local myLevel = Public(UnitLevel("player"), "number")
    local margin = tonumber(ns.db.dangerLevels) or 3

    local high = false
    if level then
        if level < 0 then
            high = true -- Stufe „??“
        elseif myLevel and level >= myLevel + margin then
            high = true
        end
    end
    if not (classLabel or high) then return nil end

    local levelText = (level and level >= 0) and tostring(level) or "??"
    return classLabel, levelText
end

local function Evaluate(unit, fresh)
    if type(unit) ~= "string" or ns.IsSecret(unit) then return end
    if not (ns.db and ns.db.dangerWarn) then Release(unit) return end
    -- Im Kampf nicht neu auswerten: Symbol bleibt, wie es war
    if InCombat() then return end

    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then
        Release(unit)
        return
    end

    local classLabel, levelText = Assess(unit)
    if not levelText then
        Release(unit)
        return
    end
    Attach(unit, plate)

    -- Hinweis nur beim ersten Auftauchen, außerhalb von Instanzen, höchstens alle 10 s je Name
    if not fresh or InInstance() then return end
    local name = Public(UnitName(unit), "string")
    if not name or name == "" then return end
    local now = GetTime()
    if lastWarn[name] and now - lastWarn[name] < REPEAT_DELAY then return end
    lastWarn[name] = now
    if classLabel then
        ShowNotice(L("Gefährlich: %s (%s, Stufe %s)", name, classLabel, levelText))
    else
        ShowNotice(L("Gefährlich: %s (Stufe %s)", name, levelText))
    end
end

local function RefreshAll()
    if not (ns.db and ns.db.dangerWarn) then
        ReleaseAll()
        return
    end
    if InCombat() then return end
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for unit in pairs(active) do
        if not C_NamePlate.GetNamePlateForUnit(unit) then Release(unit) end
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then pcall(Evaluate, unit, false) end
    end
end

-- Alte Einträge der Hinweis-Sperre gelegentlich aufräumen
local function PruneWarnings()
    local now = GetTime()
    for name, t in pairs(lastWarn) do
        if now - t >= REPEAT_DELAY then lastWarn[name] = nil end
    end
end

---------------------------------------------------------------------------
-- Ereignisse (eigener Rahmen, Registrierung abgesichert)
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_ENABLED",
    "PLAYER_LEVEL_UP", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, unit)
    if not ns.db then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" and not ns.IsSecret(unit) then Release(unit) end
        return
    end
    if not ns.db.dangerWarn then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        pcall(Evaluate, unit, true)
    elseif event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
        if type(unit) == "string" and not ns.IsSecret(unit) and unit:find("^nameplate") then
            pcall(Evaluate, unit, false)
        elseif unit == "player" then
            pcall(RefreshAll)
        end
    else
        if event == "PLAYER_REGEN_ENABLED" then PruneWarnings() end
        pcall(RefreshAll)
    end
end)

ns.On("PLAYER_LOGIN", function()
    ns.RestorePosition(notice)
end)

---------------------------------------------------------------------------
-- Optionen (Bereich „Kampfhilfen“, höchstens 2 Optionen aus dieser Datei)
---------------------------------------------------------------------------

ns.AddOption(2, "Kampfhilfen", {
    key = "dangerWarn",
    label = L["Gefährliche Gegner warnen"],
    tooltip = L["Elite-Gegner und Gegner, deren Stufe deutlich über deiner liegt (auch „??“), bekommen einen Totenkopf an der Namensplakette. Taucht so ein Gegner zum ersten Mal auf, erscheint oben kurz ein Hinweis mit leisem Ton, für denselben Namen höchstens alle 10 Sekunden.\n\nAusgewertet wird außerhalb des Kampfes. In Instanzen gibt es nur den Totenkopf. Gegnerische Namensplaketten müssen eingeschaltet sein (Taste V). Den Hinweis verschiebst du bei offenem stray-Fenster mit Shift + Ziehen."],
    set = function(value)
        ns.db.dangerWarn = value
        if value then
            pcall(RefreshAll)
        else
            ReleaseAll()
        end
        ShowSample(value and ns.IsConfigOpen())
    end,
})

ns.AddOption(2, "Kampfhilfen", {
    key = "dangerLevels",
    type = "slider",
    min = 2,
    max = 10,
    step = 1,
    label = L["Warnen ab Stufen darüber"],
    tooltip = L["Ab wie vielen Stufen über deiner eigenen ein Gegner als gefährlich gilt. Elite-Gegner und „??“ zählen immer."],
    isEnabled = function() return ns.db and ns.db.dangerWarn and true or false end,
    disabledHint = L["Erst „Gefährliche Gegner warnen“ einschalten (direkt darüber)."],
    set = function(value)
        ns.db.dangerLevels = value
        pcall(RefreshAll)
    end,
})
