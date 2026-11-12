-- stray – Händler: graue Gegenstände verkaufen, Ausrüstung reparieren

local _, ns = ...
local L = ns.L

ns.AddOption(1, "Händler", {
    key = "autoSell",
    label = L["Automatisch verkaufen"],
    tooltip = L["Verkauft beim Händler alle grauen Gegenstände aus deinen Taschen. Gegenstände, die eine Quest im Questlog noch braucht, verkauft stray dabei nie. Halte Shift gedrückt, um das zu verhindern.\n\nDer Händler kann nur die letzten 12 verkauften Gegenstände zurückkaufen."],
})

ns.AddOption(1, "Händler", {
    key = "autoRepair",
    label = L["Automatisch reparieren"],
    tooltip = L["Repariert deine Ausrüstung mit deinem Gold, wenn der Händler reparieren kann. Halte Shift gedrückt, um das zu verhindern."],
})

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local UseItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
-- Forever hat das alte globale GetItemInfo nicht mehr, nur C_Item.GetItemInfo
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Standard-Filter: graue Gegenstände; mit stray-Tasche zusätzlich markierter Schrott, ohne per
-- bagJunkMarks[itemID] == false geschützte graue Gegenstände
local function AutoFilter(rec)
    local B = ns.Bag
    if ns.db and ns.db.bagWindow and B and B.IsJunk then
        return B.IsJunk(rec)
    end
    return rec.quality == 0
end

-- Liefert Verkaufswert und Sperrstatus, falls der Platz einen verkaufbaren Gegenstand enthält, den der Filter will
local function GetJunk(bag, slot, filter)
    local link, count, noValue, quality, locked, itemID
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return end
        link, count, noValue, quality, locked, itemID =
            info.hyperlink, info.stackCount, info.hasNoValue, info.quality, info.isLocked, info.itemID
    else
        local _, c, l, q, _, _, h, _, nv, id = GetContainerItemInfo(bag, slot)
        link, count, noValue, quality, locked, itemID = h, c, nv, q, l, id
    end
    if not link or noValue then return end
    -- Nie verkaufen, was eine Quest im Questlog noch braucht
    if ns.QuestForItemLink and ns.QuestForItemLink(link) then return end

    local _, _, itemQuality, _, _, _, _, _, _, _, price = GetItemInfo(link)
    quality = quality or itemQuality
    if not itemID then
        local id = type(link) == "string" and link:match("item:(%d+)")
        itemID = id and tonumber(id) or nil
    end
    if not price or price <= 0 then return end
    local rec = { bag = bag, slot = slot, hasItem = true, itemID = itemID, link = link, quality = quality, count = count }
    local ok, want = pcall(filter or AutoFilter, rec)
    if not ok or not want then return end

    return price * (count or 1), locked
end

local merchantOpen = false
local ticker
local soldCount, soldValue = 0, 0
local repairPending = false
local steps = 0
local activeFilter -- Filter eines manuellen Verkaufs (ns.SellJunk), sonst nil

local function TryRepair()
    if not CanMerchantRepair() then return true end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return true end
    if GetMoney() < cost then return false end
    RepairAllItems()
    ns.Print(L("Ausrüstung für %s repariert.", ns.FormatMoney(cost)))
    return true
end

local function FinishSelling()
    activeFilter = nil
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if soldCount > 0 then
        if soldCount == 1 then
            ns.Print(L("1 Gegenstand für %s verkauft.", ns.FormatMoney(soldValue)))
        else
            ns.Print(L("%d Gegenstände für %s verkauft.", soldCount, ns.FormatMoney(soldValue)))
        end
    end
    -- Nach dem Verkauf nochmal versuchen, falls das Gold vorher nicht gereicht hat
    if repairPending and merchantOpen then
        if not TryRepair() then
            ns.Print(L["Nicht genug Gold zum Reparieren."])
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
            local value, locked = GetJunk(bag, slot, activeFilter)
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

    activeFilter = nil
    if ns.db.autoSell then
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(0.2, SellStep)
    elseif repairPending then
        ns.Print(L["Nicht genug Gold zum Reparieren."])
        repairPending = false
    end
end)

ns.On("MERCHANT_CLOSED", function()
    merchantOpen = false
    if ticker then FinishSelling() end
end)

-- Öffentlich (Schrott-Knopf der stray-Tasche): verkauft alle Gegenstände, die filterFn(rec) will
-- (rec = { bag, slot, itemID, link, quality, count }), schrittweise wie der Automatik-Verkauf.
-- Questgegenstände bleiben geschützt. Gibt true zurück, wenn der Verkauf gestartet wurde.
function ns.SellJunk(filterFn)
    if not merchantOpen or type(filterFn) ~= "function" then return false end
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    soldCount, soldValue, steps = 0, 0, 0
    repairPending = false
    activeFilter = filterFn
    ticker = C_Timer.NewTicker(0.2, SellStep)
    return true
end

function ns.MerchantOpen()
    return merchantOpen
end
