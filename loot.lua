-- stray – Beute: automatisch und schnell plündern

local _, ns = ...
local L = ns.L

ns.AddOption(1, "Beute", {
    key = "autoLoot",
    label = L["Automatisch plündern"],
    tooltip = L["Ein Klick auf eine Leiche nimmt die ganze Beute. Mit gedrückter Shift-Taste plünderst du wie gewohnt manuell."],
    get = function() return ns.GetCVarOn("autoLootDefault") end,
    set = function(value) ns.SetCVarValue("autoLootDefault", value and "1" or "0") end,
})

ns.AddOption(1, "Beute", {
    key = "fastLoot",
    label = L["Schnell plündern"],
    tooltip = L["Nimmt die Beute sofort, ohne auf das Beutefenster zu warten. Gegenstände mit Bestätigung fragt WoW weiterhin ab."],
    isEnabled = function() return ns.GetCVarOn("autoLootDefault") end,
    disabledHint = L["Erst „Automatisch plündern“ einschalten (direkt darüber)."],
})

local lastLoot = 0

ns.On("LOOT_READY", function()
    if not ns.db or not ns.db.fastLoot then return end
    -- Nur wenn WoW gerade automatisch plündern würde (Shift dreht das Verhalten um)
    if ns.GetCVarOn("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then return end

    local now = GetTime()
    if now - lastLoot < 0.3 then return end
    lastLoot = now

    for slot = GetNumLootItems(), 1, -1 do
        local _, _, _, _, _, locked = GetLootSlotInfo(slot)
        if not locked then
            LootSlot(slot)
        end
    end
end)
