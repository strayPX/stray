-- stray – Interface: rote Fehlermeldungen ausblenden, Haltbarkeit anzeigen

local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Fehlermeldungen
---------------------------------------------------------------------------

-- Diese Meldungen bleiben sichtbar
local KEEP = {}
for _, name in ipairs({ "ERR_INV_FULL", "ERR_BAG_FULL", "ERR_QUEST_LOG_FULL", "ERR_LOOT_ROLL_PENDING" }) do
    if _G[name] then KEEP[_G[name]] = true end
end

local function ApplyErrors()
    if not UIErrorsFrame then return end
    if ns.db.hideErrors then
        UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    else
        UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
    end
end

-- Solange die Option an ist, empfängt nur stray die Fehler und reicht die wichtigen weiter
ns.On("UI_ERROR_MESSAGE", function(arg1, arg2)
    if not ns.db or not ns.db.hideErrors then return end
    if ns.IsSecret(arg1) or ns.IsSecret(arg2) then return end
    local message = (type(arg2) == "string") and arg2 or arg1
    if type(message) == "string" and KEEP[message] then
        UIErrorsFrame:AddMessage(message, 1, 0.1, 0.1, 1)
    end
end)

ns.AddOption(3, "Interface", {
    key = "hideErrors",
    label = L["Fehlermeldungen ausblenden"],
    tooltip = L["Rote Meldungen in der Bildschirmmitte verschwinden, z. B. „Nicht genug Mana“, „Fähigkeit noch nicht bereit“ oder „Außer Reichweite“.\n\n„Taschen voll“ und „Questlog voll“ bleiben sichtbar. Gelbe Questfortschritte sind nicht betroffen."],
    set = function(value)
        ns.db.hideErrors = value
        ApplyErrors()
    end,
})

---------------------------------------------------------------------------
-- Haltbarkeit
---------------------------------------------------------------------------

local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 } -- Ausrüstungsplätze mit Haltbarkeit

local panel = CreateFrame("Frame", "strayDurability", UIParent, ns.BACKDROP_TEMPLATE)
panel:SetSize(130, 24)
panel:SetFrameStrata("MEDIUM")
ns.ApplyBackdrop(panel)
ns.MakeMovable(panel, "durability", { "TOPRIGHT", "TOPRIGHT", -30, -200 })
ns.RegisterMovable(panel, "Haltbarkeit")
panel:Hide()

local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetPoint("CENTER")

local function PercentColor(pct)
    if pct >= 60 then return 0.25, 0.9, 0.25 end
    if pct >= 30 then return 1, 0.82, 0 end
    return 1, 0.2, 0.2
end

local function Collect()
    local items, lowest = {}, nil
    for _, slot in ipairs(SLOTS) do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            local pct = current / maximum * 100
            table.insert(items, { link = GetInventoryItemLink("player", slot), pct = pct })
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    return items, lowest
end

local function Update()
    if not ns.db or not ns.db.durability then
        panel:Hide()
        return
    end
    local _, lowest = Collect()
    if lowest then
        local r, g, b = PercentColor(lowest)
        local hex = ("%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
        text:SetText(L("Haltbarkeit |cff%s%d %%|r", hex, math.floor(lowest + 0.5)))
    else
        text:SetText(L["Haltbarkeit –"])
    end
    panel:SetWidth(text:GetStringWidth() + 20)
    panel:Show()
end

panel:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L["Haltbarkeit"], 1, 1, 1)
    local items = Collect()
    table.sort(items, function(a, b) return a.pct < b.pct end)
    for _, item in ipairs(items) do
        local r, g, b = PercentColor(item.pct)
        GameTooltip:AddDoubleLine(item.link or "?", ("%d %%"):format(math.floor(item.pct + 0.5)), 1, 1, 1, r, g, b)
    end
    if #items == 0 then
        GameTooltip:AddLine(L["Keine Ausrüstung mit Haltbarkeit angelegt."], 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(L["Shift + ziehen zum Verschieben"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
panel:SetScript("OnLeave", function() GameTooltip:Hide() end)

ns.On("UPDATE_INVENTORY_DURABILITY", Update)
ns.On("PLAYER_EQUIPMENT_CHANGED", Update)
ns.On("PLAYER_ENTERING_WORLD", Update)

ns.AddOption(3, "Interface", {
    key = "durability",
    label = L["Haltbarkeit anzeigen"],
    tooltip = L["Kleine Anzeige am Bildschirm mit der Haltbarkeit deines am stärksten beschädigten Ausrüstungsteils – grün, gelb oder rot. Der Tooltip listet alle Teile.\n\nMit Shift + linker Maustaste verschiebst du die Anzeige."],
    set = function(value)
        ns.db.durability = value
        Update()
    end,
})

ns.On("PLAYER_LOGIN", function()
    ApplyErrors()
    ns.RestorePosition(panel)
    Update()
end)
