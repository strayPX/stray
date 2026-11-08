-- stray – Händler: graue Gegenstände verkaufen, Ausrüstung reparieren

local _, ns = ...

ns.AddOption(1, "Händler", {
    key = "autoSell",
    label = "Automatisch verkaufen",
    tooltip = "Verkauft beim Händler alle grauen Gegenstände aus deinen Taschen. Gegenstände, die eine Quest im Questlog noch braucht, verkauft stray dabei nie. Halte Shift gedrückt, um das zu verhindern.\n\nDer Händler kann nur die letzten 12 verkauften Gegenstände zurückkaufen.",
})

ns.AddOption(1, "Händler", {
    key = "autoRepair",
    label = "Automatisch reparieren",
    tooltip = "Repariert deine Ausrüstung mit deinem Gold, wenn der Händler reparieren kann. Halte Shift gedrückt, um das zu verhindern.",
})

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local UseItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
-- Forever hat das alte globale GetItemInfo nicht mehr, nur C_Item.GetItemInfo
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Liefert Verkaufswert und Sperrstatus, falls der Platz einen grauen, verkaufbaren Gegenstand enthält
local function GetJunk(bag, slot)
    local link, count, noValue, quality, locked
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return end
        link, count, noValue, quality, locked = info.hyperlink, info.stackCount, info.hasNoValue, info.quality, info.isLocked
    else
        local _, c, l, q, _, _, h, _, nv = GetContainerItemInfo(bag, slot)
        link, count, noValue, quality, locked = h, c, nv, q, l
    end
    if not link or noValue then return end
    -- Nie verkaufen, was eine Quest im Questlog noch braucht
    if ns.QuestForItemLink and ns.QuestForItemLink(link) then return end

    local _, _, itemQuality, _, _, _, _, _, _, _, price = GetItemInfo(link)
    quality = quality or itemQuality
    if quality ~= 0 or not price or price <= 0 then return end

    return price * (count or 1), locked
end

local merchantOpen = false
local ticker
local soldCount, soldValue = 0, 0
local repairPending = false
local steps = 0

local function TryRepair()
    if not CanMerchantRepair() then return true end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return true end
    if GetMoney() < cost then return false end
    RepairAllItems()
    ns.Print("Ausrüstung für " .. ns.FormatMoney(cost) .. " repariert.")
    return true
end

local function FinishSelling()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if soldCount > 0 then
        ns.Print(("%d %s für %s verkauft."):format(
            soldCount, soldCount == 1 and "Gegenstand" or "Gegenstände", ns.FormatMoney(soldValue)))
    end
    -- Nach dem Verkauf nochmal versuchen, falls das Gold vorher nicht gereicht hat
    if repairPending and merchantOpen then
        if not TryRepair() then
            ns.Print("Nicht genug Gold zum Reparieren.")
        end
    end
    repairPending = false
end

local function SellStep()
    steps = steps + 1
    if not merchantOpen or steps > 300 then
        FinishSelling()
        return
    end

    local soldNow, waiting = 0, false
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetNumSlots(bag) or 0 do
            local value, locked = GetJunk(bag, slot)
            if value then
                if locked then
                    waiting = true -- wird gerade verkauft, Bestätigung abwarten
                elseif soldNow < 3 then
                    UseItem(bag, slot)
                    soldCount = soldCount + 1
                    soldValue = soldValue + value
                    soldNow = soldNow + 1
                else
                    waiting = true
                end
            end
        end
    end

    if soldNow == 0 and not waiting then
        FinishSelling()
    end
end

ns.On("MERCHANT_SHOW", function()
    merchantOpen = true
    if not ns.db or IsShiftKeyDown() then return end

    soldCount, soldValue, steps = 0, 0, 0
    repairPending = false

    if ns.db.autoRepair then
        repairPending = not TryRepair()
    end

    if ns.db.autoSell then
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(0.2, SellStep)
    elseif repairPending then
        ns.Print("Nicht genug Gold zum Reparieren.")
        repairPending = false
    end
end)

ns.On("MERCHANT_CLOSED", function()
    merchantOpen = false
    if ticker then FinishSelling() end
end)
