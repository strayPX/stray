-- stray – Fenster: Spalten, Abschnitte und Checkboxen aus dem Optionsregister

local _, ns = ...

local PAD = 18          -- Innenabstand links/rechts
local COL_WIDTH = 230   -- Breite einer Spalte
local TOP = -34         -- erste Zeile unter der Titelleiste
local ROW = 26          -- Höhe einer Checkbox-Zeile
local SECTION_GAP = 10  -- Abstand zwischen Abschnitten
local BOTTOM_PAD = 8    -- Abstand unter der letzten Zeile

local GOLD, GOLD_DARK, GREY = ns.GOLD, ns.GOLD_DARK, ns.GREY

---------------------------------------------------------------------------
-- Grundgerüst
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "strayFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetWidth(PAD * 2 + COL_WIDTH * #ns.columns)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()
tinsert(UISpecialFrames, "strayFrame") -- Esc schließt das Fenster

-- Kopfzeile: Symbol (innerhalb der Titelleiste), Name, Version
local icon = frame:CreateTexture(nil, "OVERLAY")
icon:SetSize(14, 14)
icon:SetPoint("CENTER", frame, "TOPLEFT", 17, -13)
icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
local masked = pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
if not masked then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local iconRing = frame:CreateTexture(nil, "OVERLAY", nil, 1)
iconRing:SetSize(22, 22)
iconRing:SetPoint("CENTER", icon, "CENTER", 0, 0)
iconRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
iconRing:SetTexCoord(0, 0.6, 0, 0.6)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", frame, "TOP", 0, -5)
title:SetText("stray")

local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
version:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -7)

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.point = { point, relPoint, x, y }
end)

---------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------

local checkboxes = {}
local Refresh

local function CreateSection(x, y, name)
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    header:SetText(name)
    header:SetTextColor(GOLD_DARK[1], GOLD_DARK[2], GOLD_DARK[3])

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetSize(COL_WIDTH - 20, 1)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - 15)
    line:SetColorTexture(GOLD_DARK[1], GOLD_DARK[2], GOLD_DARK[3], 0.35)

    return y - 20
end

local function CreateCheckbox(x, y, option)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", frame, "TOPLEFT", x - 4, y)
    cb.option = option

    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(option.label)

    -- Auch die Beschriftung ist klickbar
    cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 6, 0, 0)

    if cb.SetMotionScriptsWhileDisabled then
        cb:SetMotionScriptsWhileDisabled(true)
    end

    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(option.label, 1, 1, 1)
        GameTooltip:AddLine(option.tooltip, GOLD[1], GOLD[2], GOLD[3], true)
        if not self:IsEnabled() and option.disabledHint then
            GameTooltip:AddLine(option.disabledHint, 1, 0.3, 0.3, true)
        end
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        ns.Sound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        option.set(checked)
        Refresh()
    end)

    table.insert(checkboxes, cb)
    return y - ROW
end

---------------------------------------------------------------------------
-- Aufbau aus dem Optionsregister; Höhe wächst mit der längsten Spalte
---------------------------------------------------------------------------

local lowest = TOP
for col, sections in ipairs(ns.columns) do
    local x = PAD + (col - 1) * COL_WIDTH
    local y = TOP
    for i, section in ipairs(sections) do
        if i > 1 then y = y - SECTION_GAP end
        y = CreateSection(x, y, section.name)
        for _, option in ipairs(section.options) do
            y = CreateCheckbox(x, y, option)
        end
    end
    lowest = math.min(lowest, y)
end
frame:SetHeight(-lowest + BOTTOM_PAD)

function Refresh()
    if not ns.db then return end
    for _, cb in ipairs(checkboxes) do
        local option = cb.option
        local enabled = not option.isEnabled or option.isEnabled()
        cb:SetChecked(option.get() and true or false)
        cb:SetEnabled(enabled)
        local color = enabled and GOLD or GREY
        cb.label:SetTextColor(color[1], color[2], color[3])
    end
end

-- Module können reagieren, wenn das Fenster auf- oder zugeht (z. B. Beispielanzeigen)
ns.configCallbacks = ns.configCallbacks or {}

local function NotifyConfig(open)
    for _, fn in ipairs(ns.configCallbacks) do fn(open) end
end

frame:SetScript("OnShow", function()
    ns.Sound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    Refresh()
    NotifyConfig(true)
end)
frame:SetScript("OnHide", function()
    ns.Sound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    NotifyConfig(false)
end)

-- Falls Einstellungen woanders geändert werden (z. B. Blizzard-Optionen)
ns.On("CVAR_UPDATE", function()
    if frame:IsShown() then Refresh() end
end)

function ns.OnLoaded()
    version:SetText(ns.GetVersion())
    if ns.db.point then
        frame:ClearAllPoints()
        frame:SetPoint(ns.db.point[1], UIParent, ns.db.point[2], ns.db.point[3], ns.db.point[4])
    end
end

---------------------------------------------------------------------------
-- Slash-Befehl
---------------------------------------------------------------------------

SLASH_STRAY1 = "/stray"
SlashCmdList["STRAY"] = function()
    if not ns.db then
        ns.Print("noch nicht geladen.")
        return
    end
    frame:SetShown(not frame:IsShown())
end
