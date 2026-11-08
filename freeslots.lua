-- stray – Freie Taschenplätze auf dem Rucksack-Knopf anzeigen
-- Nutzt Blizzards eigene Anzeige, falls der Client sie hat (CVar displayFreeBagSlots);
-- sonst schreibt stray die Zahl selbst auf den Rucksack-Knopf.

local _, ns = ...
local L = ns.L

local CVAR = "displayFreeBagSlots"
local GetFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots

local function HasBlizzardOption()
    local getDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if not getDefault then return false end
    local ok, value = pcall(getDefault, CVAR)
    return ok and value ~= nil
end

local useBlizzard = HasBlizzardOption()
local text

local function CountFree()
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local n, bagType = GetFree(bag)
        -- Nur normale Taschen zählen (keine Köcher, Kräuter- oder Seelentaschen)
        if type(n) == "number" and (bagType == 0 or bagType == nil) then
            free = free + n
        end
    end
    return free
end

local function Update()
    if useBlizzard or not text then return end
    if not ns.db or not ns.db.freeSlots then
        text:Hide()
        return
    end
    local free = CountFree()
    text:SetText(free)
    if free == 0 then
        text:SetTextColor(1, 0.25, 0.25)
    else
        text:SetTextColor(1, 1, 1)
    end
    text:Show()
end

local function CreateText()
    local button = MainMenuBarBackpackButton
    if not button or text then return end
    text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    text:Hide()
end

ns.AddOption(1, "Taschen", {
    key = "freeSlots",
    label = L["Freie Taschenplätze"],
    tooltip = L["Zeigt auf dem Rucksack-Knopf unten an der Leiste, wie viele Plätze in deinen Taschen noch frei sind – rot, wenn alles voll ist. Spezialtaschen wie Köcher zählen nicht mit."],
    get = function()
        if useBlizzard then return ns.GetCVarOn(CVAR) end
        return ns.db.freeSlots
    end,
    set = function(value)
        if useBlizzard then
            ns.SetCVarValue(CVAR, value and "1" or "0")
        else
            ns.db.freeSlots = value
            Update()
        end
    end,
})

ns.On("PLAYER_LOGIN", function()
    if not useBlizzard then
        CreateText()
        Update()
    end
end)
ns.On("BAG_UPDATE_DELAYED", Update)
ns.On("PLAYER_ENTERING_WORLD", Update)
