-- stray – Hilfe bei vollen Taschen
-- Ab höchstens einem freien Platz sucht stray den billigsten Gegenstand in den Taschen
-- (Verkaufspreis × Anzahl) und markiert ihn als Löschkandidat: an Blizzards Taschenknöpfen
-- (eigene Texturen, keine Felder auf Blizzard-Frames) und im Tooltip.
-- Beim Plündern bekommt Beute, die mehr wert ist als der Löschkandidat, eine kleine Goldmünze.
-- stray löscht nie etwas selbst.

local _, ns = ...
local L = ns.L

ns.defaults.bagTriage = false

local IsSecret = ns.IsSecret
local Container = C_Container or {}

local FIRST_BAG = 0
local LAST_BAG = (type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS) or 4
local MAX_FREE = 1 -- ab so wenigen freien Plätzen hilft stray
local MIN_KEEP_QUALITY = 3 -- „selten“ und besser gilt nie als Löschkandidat
local CL_QUEST = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local RED = { 1, 0.32, 0.22 }

local function Public(v)
    if IsSecret(v) then return nil end
    return v
end

local function Enabled()
    return ns.db and ns.db.bagTriage and true or false
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local function SellPrice(item)
    if ns.VendorSellPrice then return ns.VendorSellPrice(item) end
    if not GetInfo then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(GetInfo, item)
    if not ok or IsSecret(price) or type(price) ~= "number" then return nil end
    return price
end

local function ItemIDFromLink(link)
    if type(link) ~= "string" or IsSecret(link) then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id)
end

---------------------------------------------------------------------------
-- Billigsten Gegenstand bestimmen
---------------------------------------------------------------------------

local candidate     -- { bag, slot, itemID, link, value } oder nil
local missingPrice = false

local function NumSlots(bag)
    if not Container.GetContainerNumSlots then return 0 end
    local ok, n = pcall(Container.GetContainerNumSlots, bag)
    if not ok or IsSecret(n) or type(n) ~= "number" then return 0 end
    return n
end

-- Freie Plätze in normalen Taschen und welche Taschen normal sind
local function NormalBags()
    local free, bags = 0, {}
    if not Container.GetContainerNumFreeSlots then return nil, bags end
    for bag = FIRST_BAG, LAST_BAG do
        local ok, f, family = pcall(Container.GetContainerNumFreeSlots, bag)
        if ok and not IsSecret(f) and not IsSecret(family) and type(f) == "number" then
            if family == 0 or family == nil then
                free = free + f
                bags[#bags + 1] = bag
            end
        end
    end
    return free, bags
end

local function IsQuestThing(bag, slot, itemID, link)
    if ns.QuestForItemLink and link then
        local ok, quest = pcall(ns.QuestForItemLink, link)
        if ok and quest then return true end
    end
    if Container.GetContainerItemQuestInfo then
        local ok, info = pcall(Container.GetContainerItemQuestInfo, bag, slot)
        if ok and type(info) == "table" then
            if Public(info.isQuestItem) or Public(info.questID) then return true end
        end
    end
    if GetInstant then
        local ok, _, _, _, _, _, classID = pcall(GetInstant, itemID)
        if ok and not IsSecret(classID) and classID == CL_QUEST then return true end
    end
    return false
end

local function Scan()
    missingPrice = false
    if not Enabled() or not Container.GetContainerItemInfo then return nil end
    local free, bags = NormalBags()
    if not free or free > MAX_FREE then return nil end

    local best
    for _, bag in ipairs(bags) do
        for slot = 1, NumSlots(bag) do
            local ok, info = pcall(Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" then
                local itemID = Public(info.itemID)
                local link = Public(info.hyperlink)
                local count = Public(info.stackCount)
                local quality = Public(info.quality)
                local noValue = Public(info.hasNoValue)
                local locked = Public(info.isLocked)
                if type(itemID) ~= "number" then itemID = ItemIDFromLink(link) end
                if type(itemID) == "number" and not noValue and not locked
                    and not (type(quality) == "number" and quality >= MIN_KEEP_QUALITY)
                    and not IsQuestThing(bag, slot, itemID, link) then
                    local price = SellPrice(link or itemID)
                    if price == nil then
                        missingPrice = true
                    elseif price > 0 then
                        local value = price * ((type(count) == "number" and count > 0) and count or 1)
                        if not best or value < best.value then
                            best = { bag = bag, slot = slot, itemID = itemID, link = link, value = value }
                        end
                    end
                end
            end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Markierung an Blizzards Taschen (eigene Texturen, lokale Tabelle)
---------------------------------------------------------------------------

local marks = setmetatable({}, { __mode = "k" }) -- Taschenknopf → { Texturen }

local function GetMark(button)
    local m = marks[button]
    if m then return m end
    local icon = button.icon or button.Icon or button
    m = {}
    local fill = button:CreateTexture(nil, "OVERLAY", nil, 6)
    fill:SetAllPoints(icon)
    fill:SetColorTexture(RED[1], RED[2], RED[3], 0.22)
    m[1] = fill
    for i = 1, 4 do
        local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(RED[1], RED[2], RED[3], 1)
        m[#m + 1] = t
    end
    m[2]:SetPoint("TOPLEFT", icon); m[2]:SetPoint("TOPRIGHT", icon); m[2]:SetHeight(2)
    m[3]:SetPoint("BOTTOMLEFT", icon); m[3]:SetPoint("BOTTOMRIGHT", icon); m[3]:SetHeight(2)
    m[4]:SetPoint("TOPLEFT", icon); m[4]:SetPoint("BOTTOMLEFT", icon); m[4]:SetWidth(2)
    m[5]:SetPoint("TOPRIGHT", icon); m[5]:SetPoint("BOTTOMRIGHT", icon); m[5]:SetWidth(2)
    for _, t in ipairs(m) do t:Hide() end
    marks[button] = m
    return m
end

local function ShowMark(button, on)
    if not on and not marks[button] then return end
    for _, t in ipairs(GetMark(button)) do t:SetShown(on) end
end

local function ButtonBagSlot(button)
    if not button.GetBagID or not button.GetID then return nil end
    local okBag, bag = pcall(button.GetBagID, button)
    local okSlot, slot = pcall(button.GetID, button)
    if not okBag or not okSlot or IsSecret(bag) or IsSecret(slot) then return nil end
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return bag, slot
end

local function ForEachBlizzardButton(fn)
    local frames = {}
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then frames[#frames + 1] = f end
    end
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    for _, f in ipairs(frames) do
        if f:IsShown() and f.EnumerateValidItems then
            pcall(function()
                for _, button in f:EnumerateValidItems() do
                    if button then fn(button) end
                end
            end)
        end
    end
end

local function PaintBlizzard()
    for button in pairs(marks) do ShowMark(button, false) end
    if not candidate then return end
    ForEachBlizzardButton(function(button)
        local bag, slot = ButtonBagSlot(button)
        if bag == candidate.bag and slot == candidate.slot then ShowMark(button, true) end
    end)
end

---------------------------------------------------------------------------
-- Goldmünze an wertvoller Beute
---------------------------------------------------------------------------

local coins = setmetatable({}, { __mode = "k" }) -- Beuteknopf → Textur

local function HideCoins()
    for _, tex in pairs(coins) do tex:Hide() end
end

local function GetCoin(itemButton)
    local tex = coins[itemButton]
    if tex then return tex end
    tex = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetSize(13, 13)
    tex:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT", 2, 2)
    tex:SetTexture(COIN)
    tex:Hide()
    coins[itemButton] = tex
    return tex
end

local function LootValue(index)
    if not GetLootSlotLink or not GetLootSlotInfo then return nil end
    local okLink, link = pcall(GetLootSlotLink, index)
    if not okLink or type(link) ~= "string" or IsSecret(link) then return nil end
    local okInfo, _, _, quantity = pcall(GetLootSlotInfo, index)
    if not okInfo or IsSecret(quantity) then return nil end
    local price = SellPrice(link)
    if not price or price <= 0 then return nil end
    return price * ((type(quantity) == "number" and quantity > 0) and quantity or 1)
end

local function PaintLoot()
    HideCoins()
    if not Enabled() or not candidate then return end
    local box = LootFrame and LootFrame:IsShown() and LootFrame.ScrollBox
    if not box or not box.ForEachFrame then return end
    box:ForEachFrame(function(element)
        local itemButton = element.Item
        if itemButton and element.GetSlotIndex then
            local ok, index = pcall(element.GetSlotIndex, element)
            if ok and type(index) == "number" and not IsSecret(index) then
                local value = LootValue(index)
                if value and value > candidate.value then GetCoin(itemButton):Show() end
            end
        end
    end)
end

local function SafePaintLoot()
    pcall(PaintLoot)
end

---------------------------------------------------------------------------
-- Neu berechnen (gedrosselt)
---------------------------------------------------------------------------

local function Apply()
    local ok, result = pcall(Scan)
    candidate = ok and result or nil
    pcall(PaintBlizzard)
    if LootFrame and LootFrame:IsShown() then SafePaintLoot() end
end

local pending = false

local function RequestScan(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 0.3, function()
        pending = false
        Apply()
    end)
end

-- Tooltipzeile am Löschkandidaten
local function OnItemTooltip(tooltip, data)
    if not candidate or not Enabled() then return end
    if type(tooltip) ~= "table" or type(data) ~= "table" or IsSecret(data) then return end
    if not tooltip.AddLine or not tooltip.GetOwner then return end
    local itemID = data.id
    if IsSecret(itemID) or itemID ~= candidate.itemID then return end
    local ok, owner = pcall(tooltip.GetOwner, tooltip)
    if not ok or type(owner) ~= "table" then return end
    local bag, slot = ButtonBagSlot(owner)
    if bag ~= candidate.bag or slot ~= candidate.slot then return end
    tooltip:AddLine(L["stray: billigster Gegenstand – Löschkandidat"], RED[1], RED[2], RED[3])
    pcall(tooltip.Show, tooltip)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        pcall(OnItemTooltip, tooltip, data)
    end)
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    -- Blizzards Taschen werden beim Öffnen neu belegt: danach markieren
    local function OnShow() if candidate then C_Timer.After(0, function() pcall(PaintBlizzard) end) end end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f and f.HookScript then f:HookScript("OnShow", OnShow) end
    end
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags.HookScript then
        ContainerFrameCombinedBags:HookScript("OnShow", OnShow)
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function() if Enabled() then RequestScan(2) end end)
ns.On("BAG_UPDATE_DELAYED", function() if Enabled() then RequestScan(0.3) end end)
ns.On("QUEST_LOG_UPDATE", function() if Enabled() and candidate then RequestScan(1) end end)

ns.On("LOOT_OPENED", function() if Enabled() then C_Timer.After(0, SafePaintLoot) end end)
ns.On("LOOT_SLOT_CLEARED", function() if Enabled() then C_Timer.After(0, SafePaintLoot) end end)
ns.On("LOOT_CLOSED", function() pcall(HideCoins) end)

-- Preise, die noch nicht im Cache waren, kommen nach
local itemEvents = CreateFrame("Frame")
pcall(itemEvents.RegisterEvent, itemEvents, "GET_ITEM_INFO_RECEIVED")
itemEvents:SetScript("OnEvent", function()
    if Enabled() and missingPrice then RequestScan(1) end
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(1, "Taschen", {
    key = "bagTriage",
    label = L["Hilfe bei vollen Taschen"],
    tooltip = L["Ist höchstens noch ein Platz frei, markiert stray den billigsten Gegenstand (Verkaufspreis × Anzahl) rot als Löschkandidat – in Blizzards Taschen und im Tooltip. Beute, die mehr wert ist, bekommt beim Plündern eine Goldmünze.\n\nNie vorgeschlagen werden Questgegenstände, Gegenstände ohne Verkaufswert und alles ab „selten“ (blau).\n\nstray löscht nichts selbst."],
    set = function(value)
        ns.db.bagTriage = value
        Apply()
        if not value then pcall(HideCoins) end
    end,
})
