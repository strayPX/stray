-- stray – kleines Komfort-Addon für WoW Forever
-- /stray öffnet ein Fenster mit schnellen Einstellungen.

local ADDON_NAME = ...

local defaults = {
    fastLoot = false,
    point = nil, -- gespeicherte Fensterposition
}

local db

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

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040stray|r: " .. msg)
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
frame:SetSize(260, 130)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()
tinsert(UISpecialFrames, "strayFrame") -- Esc schließt das Fenster

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
frame.title:SetText("stray")

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.point = { point, relPoint, x, y }
end)

local function CreateCheckbox(label, anchor, offsetY)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, offsetY)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label:SetText(label)
    return cb
end

local anchor = CreateFrame("Frame", nil, frame)
anchor:SetSize(1, 1)
anchor:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)

local autoLootCB = CreateCheckbox("Automatisch plündern", anchor, 0)
local fastLootCB = CreateCheckbox("Schnell plündern", anchor, -32)

local function Refresh()
    local autoOn = GetCVarOn("autoLootDefault")
    autoLootCB:SetChecked(autoOn)
    fastLootCB:SetChecked(db.fastLoot)
    fastLootCB:SetEnabled(autoOn)
    if autoOn then
        fastLootCB.label:SetTextColor(1, 0.82, 0)
    else
        fastLootCB.label:SetTextColor(0.5, 0.5, 0.5)
    end
end

autoLootCB:SetScript("OnClick", function(self)
    SetCVarValue("autoLootDefault", self:GetChecked() and "1" or "0")
    Refresh()
end)

fastLootCB:SetScript("OnClick", function(self)
    db.fastLoot = self:GetChecked() and true or false
    Refresh()
end)

frame:SetScript("OnShow", Refresh)

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
