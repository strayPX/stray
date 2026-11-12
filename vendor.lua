-- stray – Händlerpreis im Tooltip und Bekanntes beim Händler einfärben
-- 1. Jeder Gegenstands-Tooltip zeigt den Verkaufspreis beim Händler, bei Stapeln auch den
--    Stapelwert – außer Blizzard zeigt den Preis selbst schon (Zeile „SellPrice“ in den Tooltipdaten).
-- 2. Rezepte, Begleiter, Reittiere und Bücher, die der Charakter schon kennt („Bereits bekannt“),
--    werden in der Händlerliste grün eingefärbt. Nachbearbeitung per hooksecurefunc auf
--    MerchantFrame_UpdateMerchantInfo; eigene Overlay-Texturen in einer lokalen Tabelle.

local _, ns = ...
local L = ns.L

ns.defaults.vendorPrice = false
ns.defaults.knownColor = false

local IsSecret = ns.IsSecret

local function Public(v)
    if IsSecret(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- Gemeinsame Hilfen
---------------------------------------------------------------------------

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Verkaufspreis je Stück (nil, wenn unbekannt oder noch nicht geladen)
local function SellPrice(item)
    if not GetInfo or item == nil then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(GetInfo, item)
    if not ok or IsSecret(price) or type(price) ~= "number" then return nil end
    return price
end
ns.VendorSellPrice = SellPrice -- für triage.lua

local function ItemIDFromLink(link)
    if type(link) ~= "string" or IsSecret(link) then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id)
end

-- Anzahl des Gegenstands am Tooltip-Besitzer, falls bekannt (Taschenplatz, Beute, Händler)
local function OwnerCount(tooltip, itemID)
    if not tooltip.GetOwner then return nil end
    local ok, owner = pcall(tooltip.GetOwner, tooltip)
    if not ok or type(owner) ~= "table" then return nil end

    -- Taschenplatz (Blizzard-Taschen, Bank, stray-Taschenfenster: dessen Knöpfe kennen ihren Platz aus dem Kernzustand)
    local B = ns.Bag
    local st = B and B.ButtonState and B.ButtonState(owner)
    if st and type(st.bag) == "number" and type(st.slot) == "number" and C_Container and C_Container.GetContainerItemInfo then
        local okInfo, info = pcall(C_Container.GetContainerItemInfo, st.bag, st.slot)
        if okInfo and type(info) == "table" and Public(info.itemID) == itemID then
            return Public(info.stackCount)
        end
        return nil
    end
    if owner.GetBagID and owner.GetID and C_Container and C_Container.GetContainerItemInfo then
        local okBag, bag = pcall(owner.GetBagID, owner)
        local okSlot, slot = pcall(owner.GetID, owner)
        if okBag and okSlot and not IsSecret(bag) and not IsSecret(slot)
            and type(bag) == "number" and type(slot) == "number" then
            local okInfo, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if okInfo and type(info) == "table" and Public(info.itemID) == itemID then
                return Public(info.stackCount)
            end
            return nil
        end
    end

    -- Beutefenster: Element mit GetSlotIndex
    if owner.GetSlotIndex and GetLootSlotInfo then
        local okIdx, index = pcall(owner.GetSlotIndex, owner)
        if okIdx and type(index) == "number" and not IsSecret(index) then
            local okLink, link = pcall(GetLootSlotLink, index)
            if okLink and ItemIDFromLink(link) == itemID then
                local okLoot, _, _, quantity = pcall(GetLootSlotInfo, index)
                if okLoot then return Public(quantity) end
            end
        end
        return nil
    end

    -- Händler (Kaufliste oder Rückkauf)
    local okName, name = pcall(owner.GetName, owner)
    if okName and type(name) == "string" and name:match("^MerchantItem%d+ItemButton$") then
        local index = owner:GetID()
        if type(index) ~= "number" or IsSecret(index) then return nil end
        if MerchantFrame and MerchantFrame.selectedTab == 2 then
            if GetBuybackItemInfo then
                local okBuy, _, _, _, quantity = pcall(GetBuybackItemInfo, index)
                if okBuy then return Public(quantity) end
            end
        elseif C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local okMer, info = pcall(C_MerchantFrame.GetItemInfo, index)
            if okMer and type(info) == "table" then return Public(info.stackCount) end
        end
    end
    return nil
end

-- Zeigt Blizzard den Verkaufspreis schon? (Tooltipzeile vom Typ SellPrice)
local SELL_PRICE_LINE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice) or 11

local function BlizzardShowsPrice(data)
    local lines = data.lines
    if type(lines) ~= "table" then return false end
    for _, line in ipairs(lines) do
        if type(line) == "table" then
            local kind = line.type
            if not IsSecret(kind) and kind == SELL_PRICE_LINE then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- 1. Verkaufspreis im Tooltip
---------------------------------------------------------------------------

local function OnItemTooltip(tooltip, data)
    if not ns.db or not ns.db.vendorPrice then return end
    if type(tooltip) ~= "table" or type(data) ~= "table" or IsSecret(data) then return end
    if not tooltip.AddLine or tooltip.isShopping then return end
    local okName, tipName = pcall(tooltip.GetName, tooltip)
    if okName and tipName == "ItemSocketingDescription" then return end

    local itemID = data.id
    if IsSecret(itemID) or type(itemID) ~= "number" then return end
    local link = data.hyperlink
    if IsSecret(link) or type(link) ~= "string" then link = nil end

    if BlizzardShowsPrice(data) then return end
    local price = SellPrice(link or itemID)
    if not price or price <= 0 then return end

    tooltip:AddLine(L("Verkaufspreis: %s", ns.FormatMoney(price)), 1, 1, 1)
    local count = OwnerCount(tooltip, itemID)
    if type(count) == "number" and count >= 2 then
        tooltip:AddLine(L("Stapel (%d): %s", count, ns.FormatMoney(price * count)), 1, 1, 1)
    end
    pcall(tooltip.Show, tooltip)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        local ok, err = pcall(OnItemTooltip, tooltip, data)
        if not ok and ns.debug then geterrorhandler()(err) end
    end)
end

---------------------------------------------------------------------------
-- 2. Bekanntes beim Händler einfärben
---------------------------------------------------------------------------

local KNOWN_TEXT = ITEM_SPELL_KNOWN or "Bereits bekannt"
local GREEN = { 0.35, 1, 0.35 }

local overlays = {} -- [Händlerknopf] = eigene grüne Textur

local function IsKnownMerchantItem(index)
    if not (C_TooltipInfo and C_TooltipInfo.GetMerchantItem) then return false end
    local ok, data = pcall(C_TooltipInfo.GetMerchantItem, index)
    if not ok or type(data) ~= "table" or IsSecret(data) then return false end
    local lines = data.lines
    if type(lines) ~= "table" then return false end
    for _, line in ipairs(lines) do
        if type(line) == "table" then
            local text = line.leftText
            if not IsSecret(text) and text == KNOWN_TEXT then return true end
        end
    end
    return false
end

local function GetOverlay(button)
    local tex = overlays[button]
    if tex then return tex end
    tex = button:CreateTexture(nil, "OVERLAY", nil, 5)
    local icon = button.icon or button.Icon
    tex:SetAllPoints(icon or button)
    tex:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.28)
    tex:Hide()
    overlays[button] = tex
    return tex
end

local function HideOverlays()
    for _, tex in pairs(overlays) do tex:Hide() end
end

local function PaintMerchant()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    if not ns.db or not ns.db.knownColor or MerchantFrame.selectedTab ~= 1 then
        HideOverlays()
        return
    end
    local perPage = MERCHANT_ITEMS_PER_PAGE or 10
    local page = MerchantFrame.page
    if type(page) ~= "number" then return end
    local numItems = GetMerchantNumItems and GetMerchantNumItems() or 0
    if IsSecret(numItems) or type(numItems) ~= "number" then return end

    for i = 1, perPage do
        local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
        local merchantButton = _G["MerchantItem" .. i]
        if itemButton then
            local index = (page - 1) * perPage + i
            local known = index <= numItems and IsKnownMerchantItem(index)
            local tex = GetOverlay(itemButton)
            tex:SetShown(known and true or false)
            if known then
                if SetItemButtonTextureVertexColor then
                    pcall(SetItemButtonTextureVertexColor, itemButton, GREEN[1], GREEN[2], GREEN[3])
                end
                if SetItemButtonNameFrameVertexColor and merchantButton then
                    pcall(SetItemButtonNameFrameVertexColor, merchantButton, 0.2, 0.6, 0.2)
                end
            end
        end
    end
end

local function SafePaint()
    local ok, err = pcall(PaintMerchant)
    if not ok and ns.debug then geterrorhandler()(err) end
end

-- Daten nachgeladen (z. B. Rezept noch nicht im Cache): gedrosselt neu färben
local paintPending = false
local function RequestPaint()
    if paintPending then return end
    paintPending = true
    C_Timer.After(0.2, function()
        paintPending = false
        SafePaint()
    end)
end

ns.On("PLAYER_LOGIN", function()
    if type(MerchantFrame_UpdateMerchantInfo) == "function" then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", SafePaint)
    end
    -- Rückkauf nutzt dieselben Knöpfe: dort keine Färbung
    if type(MerchantFrame_UpdateBuybackInfo) == "function" then
        hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function() pcall(HideOverlays) end)
    end
end)

ns.On("MERCHANT_CLOSED", function() pcall(HideOverlays) end)

local itemEvents = CreateFrame("Frame")
pcall(itemEvents.RegisterEvent, itemEvents, "GET_ITEM_INFO_RECEIVED")
itemEvents:SetScript("OnEvent", function()
    if ns.db and ns.db.knownColor and MerchantFrame and MerchantFrame:IsShown() then RequestPaint() end
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(1, "Händler", {
    key = "vendorPrice",
    label = L["Verkaufspreis im Tooltip"],
    tooltip = L["Zeigt in jedem Gegenstands-Tooltip, was der Händler dafür zahlt. Bei Stapeln steht zusätzlich der Wert des ganzen Stapels dabei (in den Taschen, beim Händler und in der Beute).\n\nZeigt WoW den Preis schon selbst, fügt stray nichts hinzu."],
})

ns.AddOption(1, "Händler", {
    key = "knownColor",
    label = L["Bekanntes grün färben"],
    tooltip = L("Rezepte, Begleiter, Reittiere und Bücher, die du schon kennst („%s“), werden beim Händler grün eingefärbt. So kaufst du nichts doppelt.", KNOWN_TEXT),
    set = function(value)
        ns.db.knownColor = value
        if value then
            SafePaint()
        else
            pcall(HideOverlays)
            -- Blizzards eigene Färbung wiederherstellen
            if MerchantFrame and MerchantFrame:IsShown() and type(MerchantFrame_Update) == "function" then
                pcall(MerchantFrame_Update)
            end
        end
    end,
})
