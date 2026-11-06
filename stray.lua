-- stray – kleines Komfort-Addon für WoW Forever
-- /stray öffnet ein Fenster mit schnellen Einstellungen.

local ADDON_NAME = ...

local defaults = {
    fastLoot = false,
    point = nil, -- gespeicherte Fensterposition
}

local db

-- Farben (Blizzard-Gold)
local GOLD = { 1, 0.82, 0 }
local GOLD_DARK = { 0.79, 0.64, 0.29 }
local GREY = { 0.5, 0.5, 0.5 }

-- WoW-Einstellungen lesen/schreiben (C_CVar, falls vorhanden, sonst die alten Funktionen)
local function GetCVarOn(name)
    if C_CVar and C_CVar.GetCVarBool then
        return C_CVar.GetCVarBool(name)
    end
    return GetCVarBool(name)
end

local function SetCVarValue(name, value)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar(name, value)
    else
        SetCVar(name, value)
    end
end

local function GetVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return getMeta and getMeta(ADDON_NAME, "Version") or ""
end

local function Sound(kit)
    if SOUNDKIT and kit then PlaySound(kit) end
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100stray|r: " .. msg)
end

---------------------------------------------------------------------------
-- Schnelles Plündern
---------------------------------------------------------------------------

local lastLoot = 0

local function FastLoot()
    if not db or not db.fastLoot then return end
    -- Nur wenn WoW gerade automatisch plündern würde (Shift dreht das Verhalten um)
    if GetCVarOn("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then return end

    local now = GetTime()
    if now - lastLoot < 0.3 then return end
    lastLoot = now

    for slot = GetNumLootItems(), 1, -1 do
        local _, _, _, _, _, locked = GetLootSlotInfo(slot)
        if not locked then
            LootSlot(slot)
        end
    end
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "strayFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(270, 150)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()
tinsert(UISpecialFrames, "strayFrame") -- Esc schließt das Fenster

-- Kopfzeile: Symbol, Name, Version
local icon = frame:CreateTexture(nil, "OVERLAY")
icon:SetSize(18, 18)
icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -3)
icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
local masked = pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
if not masked then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local iconRing = frame:CreateTexture(nil, "OVERLAY", nil, 1)
iconRing:SetSize(32, 32)
iconRing:SetPoint("CENTER", icon, "CENTER", 0, 0)
iconRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
iconRing:SetTexCoord(0, 0.6, 0, 0.6)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
frame.title:SetText("stray")

local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
version:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -7)

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.point = { point, relPoint, x, y }
end)

-- Abschnittsüberschrift mit Trennlinie
local function CreateSection(text, offsetY)
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, offsetY)
    header:SetText(text)
    header:SetTextColor(unpack(GOLD_DARK))

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    line:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    line:SetColorTexture(GOLD_DARK[1], GOLD_DARK[2], GOLD_DARK[3], 0.35)

    return line
end

-- Checkbox mit Beschriftung und Tooltip
local function CreateCheckbox(label, tooltip, anchor, offsetY)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -4, offsetY)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(label)
    cb.tooltip = tooltip

    -- Die Beschriftung soll auch klickbar sein
    cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 6, 0, 0)

    if cb.SetMotionScriptsWhileDisabled then
        cb:SetMotionScriptsWhileDisabled(true)
    end
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(self.tooltip, GOLD[1], GOLD[2], GOLD[3], true)
        if not self:IsEnabled() and self.disabledHint then
            GameTooltip:AddLine(self.disabledHint, 1, 0.3, 0.3, true)
        end
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return cb
end

local lootLine = CreateSection("Beute", -36)

local autoLootCB = CreateCheckbox(
    "Automatisch plündern",
    "Ein Klick auf eine Leiche nimmt die ganze Beute. Mit gedrückter Shift-Taste plünderst du wie gewohnt manuell.",
    lootLine, -6)

local fastLootCB = CreateCheckbox(
    "Schnell plündern",
    "Nimmt die Beute sofort, ohne auf das Beutefenster zu warten. Gegenstände mit Bestätigung fragt WoW weiterhin ab.",
    lootLine, -36)
fastLootCB.disabledHint = "Erst „Automatisch plündern“ aktivieren."

local function Refresh()
    local autoOn = GetCVarOn("autoLootDefault")
    autoLootCB:SetChecked(autoOn)
    fastLootCB:SetChecked(db.fastLoot)
    fastLootCB:SetEnabled(autoOn)
    if autoOn then
        fastLootCB.label:SetTextColor(unpack(GOLD))
    else
        fastLootCB.label:SetTextColor(unpack(GREY))
    end
end

local function CheckboxSound(checked)
    Sound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

autoLootCB:SetScript("OnClick", function(self)
    CheckboxSound(self:GetChecked())
    SetCVarValue("autoLootDefault", self:GetChecked() and "1" or "0")
    Refresh()
end)

fastLootCB:SetScript("OnClick", function(self)
    CheckboxSound(self:GetChecked())
    db.fastLoot = self:GetChecked() and true or false
    Refresh()
end)

frame:SetScript("OnShow", function()
    Sound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    Refresh()
end)
frame:SetScript("OnHide", function()
    Sound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("LOOT_READY")
events:RegisterEvent("CVAR_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        strayDB = strayDB or {}
        for key, value in pairs(defaults) do
            if strayDB[key] == nil then strayDB[key] = value end
        end
        db = strayDB
        version:SetText(GetVersion())
        if db.point then
            frame:ClearAllPoints()
            frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
        end
    elseif event == "LOOT_READY" then
        FastLoot()
    elseif event == "CVAR_UPDATE" then
        -- Falls die Einstellung woanders geändert wird (z. B. Blizzard-Optionen)
        if frame:IsShown() then Refresh() end
    end
end)

---------------------------------------------------------------------------
-- Slash-Befehl
---------------------------------------------------------------------------

SLASH_STRAY1 = "/stray"
SlashCmdList["STRAY"] = function()
    if not db then
        Print("noch nicht geladen.")
        return
    end
    frame:SetShown(not frame:IsShown())
end
