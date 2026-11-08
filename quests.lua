-- stray – Quests: automatisch annehmen und abgeben,
-- wertvollste Wahlbelohnung mit einer Goldmünze markieren

local _, ns = ...
local L = ns.L

ns.defaults.questRewardMark = false

ns.AddOption(2, "Quests", {
    key = "questAccept",
    label = L["Automatisch annehmen"],
    tooltip = L["Nimmt neue Quests von NPCs und Gegenständen ohne Klick an. Graue Quests, von Mitspielern geteilte Quests und Begleitquests nimmst du selbst an.\n\nHalte Shift gedrückt, um das zu verhindern."],
})

ns.AddOption(2, "Quests", {
    key = "questTurnIn",
    label = L["Automatisch abgeben"],
    tooltip = L["Gibt fertige Quests ohne Klick ab. Stehen mehrere Belohnungen zur Auswahl oder kostet die Abgabe Gold, entscheidest du selbst.\n\nHalte Shift gedrückt, um das zu verhindern."],
})

-- Quests, bei denen wir bewusst angehalten haben (Auswahl/Gold) – nicht erneut automatisch öffnen
local skipped = {}

-- Questtitel können in Forever versiegelt sein; dann nicht als Schlüssel verwenden
local function IsSkipped(title)
    title = ns.Public(title)
    return title ~= nil and skipped[title] == true
end

local function MarkSkipped(title)
    title = ns.Public(title)
    if title then skipped[title] = true end
end

local function Active(key)
    return ns.db and ns.db[key] and not IsShiftKeyDown()
end

local function IsTrivialDetail()
    local questID = GetQuestID and GetQuestID()
    if questID and C_QuestLog and C_QuestLog.IsQuestTrivial then
        local ok, trivial = pcall(C_QuestLog.IsQuestTrivial, questID)
        if ok then return trivial end
    end
    return false
end

-- NPC mit Gesprächsmenü (Gossip)
ns.On("GOSSIP_SHOW", function()
    if not C_GossipInfo then return end

    if Active("questTurnIn") then
        for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if not ns.IsSecret(quest.isComplete) and quest.isComplete and not IsSkipped(quest.title) then
                C_GossipInfo.SelectActiveQuest(quest.questID)
                return
            end
        end
    end

    if Active("questAccept") then
        for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if not ns.IsSecret(quest.isTrivial) and not quest.isTrivial then
                C_GossipInfo.SelectAvailableQuest(quest.questID)
                return
            end
        end
    end
end)

-- NPC mit einfacher Questliste (ohne Gesprächsmenü)
ns.On("QUEST_GREETING", function()
    if Active("questTurnIn") then
        for i = 1, GetNumActiveQuests() do
            local title, isComplete = GetActiveTitle(i)
            if not ns.IsSecret(isComplete) and isComplete and not IsSkipped(title) then
                SelectActiveQuest(i)
                return
            end
        end
    end

    if Active("questAccept") then
        for i = 1, GetNumAvailableQuests() do
            local isTrivial = GetAvailableQuestInfo and GetAvailableQuestInfo(i)
            if not isTrivial then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end)

-- Questtext einer neuen Quest
ns.On("QUEST_DETAIL", function()
    if not Active("questAccept") then return end
    -- Von Mitspielern geteilte Quests nicht automatisch annehmen
    if UnitExists("questnpc") and UnitIsPlayer("questnpc") then return end
    if IsTrivialDetail() then return end
    AcceptQuest()
end)

-- „Weiter“-Seite einer Quest, die abgegeben wird
ns.On("QUEST_PROGRESS", function()
    if not Active("questTurnIn") then return end
    if not IsQuestCompletable() then return end
    if GetQuestMoneyToGet and GetQuestMoneyToGet() > 0 then
        MarkSkipped(GetTitleText())
        return
    end
    CompleteQuest()
end)

-- Belohnungsseite
ns.On("QUEST_COMPLETE", function()
    if not Active("questTurnIn") then return end
    local choices = GetNumQuestChoices()
    if choices > 1 then
        MarkSkipped(GetTitleText())
        return
    end
    GetQuestReward(choices)
end)
-- Einträge in „skipped“ bleiben bis zum nächsten /reload, damit dieselbe Quest
-- nicht ständig erneut automatisch geöffnet wird.

---------------------------------------------------------------------------
-- Wertvollste Wahlbelohnung: Goldmünze an der Wahl mit dem höchsten Verkaufswert
-- (Verkaufspreis × Anzahl). Blizzard ordnet die Knöpfe in QuestInfo_Display an
-- (QuestInfoRewardsFrame.RewardButtons, Typ "choice"); wir lesen sie nur und
-- legen eine eigene Textur darüber. Bei Gleichstand oder fehlenden Preisen nichts.
---------------------------------------------------------------------------

ns.AddOption(2, "Quests", {
    key = "questRewardMark",
    label = L["Wertvollste Belohnung markieren"],
    tooltip = L["Stehen bei der Abgabe mehrere Belohnungen zur Wahl, bekommt die mit dem höchsten Verkaufswert eine kleine Goldmünze. Gezählt wird Verkaufspreis mal Anzahl.\n\nBei Gleichstand oder wenn ein Preis fehlt, wird nichts markiert. Gewählt wird nie automatisch."],
    set = function(value)
        ns.db.questRewardMark = value
        ns.UpdateRewardMark()
    end,
})

local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"

local coins = setmetatable({}, { __mode = "k" }) -- Belohnungsknopf → eigene Münz-Textur
local markedIndex = nil                          -- Index der markierten Wahl (für den Tooltip)
local waiting = false                            -- warten auf GET_ITEM_INFO_RECEIVED

local function HideCoins()
    for _, coin in pairs(coins) do coin:Hide() end
    markedIndex = nil
end

local function Coin(button)
    if coins[button] then return coins[button] end
    -- Eigener Halter als Kind des Knopfs: verschwindet mit ihm, schreibt aber nichts auf ihn
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints(button)
    holder:SetFrameLevel(button:GetFrameLevel() + 3)
    local coin = holder:CreateTexture(nil, "OVERLAY")
    coin:SetTexture(COIN_TEXTURE)
    coin:SetSize(14, 14)
    coin:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
    coin:Hide()
    coins[button] = coin
    return coin
end

-- Verkaufswert einer Wahl: Preis × Anzahl, nil wenn (noch) unbekannt
local function ChoiceValue(index)
    if not GetQuestItemLink or not C_Item or not C_Item.GetItemInfo then return nil end
    local okLink, link = pcall(GetQuestItemLink, "choice", index)
    link = okLink and ns.Public(link)
    if type(link) ~= "string" then return nil end
    local okPrice, price = pcall(function() return select(11, C_Item.GetItemInfo(link)) end)
    price = okPrice and ns.Public(price)
    if type(price) ~= "number" then return nil end
    local count = 1
    if GetQuestItemInfo then
        local okInfo, _, _, n = pcall(GetQuestItemInfo, "choice", index)
        n = okInfo and ns.Public(n)
        if type(n) == "number" and n > 0 then count = n end
    end
    return price * count
end

local waiter = CreateFrame("Frame")
waiter:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    waiting = false
    pcall(ns.UpdateRewardMark)
end)

function ns.UpdateRewardMark()
    local info = QuestInfoFrame
    -- Anzeige im Questlog (eigener Belohnungsrahmen): Münze im NPC-Fenster stehen lassen
    if info and info.questLog and ns.db and ns.db.questRewardMark then return end
    HideCoins()
    if not (ns.db and ns.db.questRewardMark) then return end
    -- Nur im Questfenster beim NPC, nicht im Questlog
    if not info or info.questLog then return end
    local rewards = info.rewardsFrame
    local buttons = rewards and rewards.RewardButtons
    if type(buttons) ~= "table" or not rewards:IsVisible() then return end
    if not GetNumQuestChoices or (GetNumQuestChoices() or 0) < 2 then return end

    local best, bestValue, tie, missing = nil, 0, false, false
    for _, button in ipairs(buttons) do
        if button:IsShown() and button.type == "choice" and button.objectType == "item" then
            local value = ChoiceValue(button:GetID())
            if value == nil then
                missing = true
            elseif value > bestValue then
                best, bestValue, tie = button, value, false
            elseif value == bestValue and value > 0 then
                tie = true
            end
        end
    end

    if missing then
        -- Gegenstand noch nicht im Cache: einmal nachladen und neu prüfen
        if not waiting then
            waiting = true
            pcall(waiter.RegisterEvent, waiter, "GET_ITEM_INFO_RECEIVED")
        end
        return
    end
    if not best or tie or bestValue <= 0 then return end
    Coin(best):Show()
    markedIndex = best:GetID()
end

if hooksecurefunc and type(QuestInfo_Display) == "function" then
    hooksecurefunc("QuestInfo_Display", function() pcall(ns.UpdateRewardMark) end)
end

-- Rückfall, falls QuestInfo_Display anders heißt: kurz nach dem Aufbau der Seite prüfen
ns.On("QUEST_COMPLETE", function()
    if ns.db and ns.db.questRewardMark then
        C_Timer.After(0, function() pcall(ns.UpdateRewardMark) end)
    end
end)

ns.On("QUEST_FINISHED", HideCoins)

-- Tooltip-Hinweis an der markierten Wahl
if hooksecurefunc and GameTooltip and GameTooltip.SetQuestItem then
    hooksecurefunc(GameTooltip, "SetQuestItem", function(tooltip, kind, index)
        if not (ns.db and ns.db.questRewardMark) or not markedIndex then return end
        if ns.IsSecret(kind) or ns.IsSecret(index) then return end
        if kind ~= "choice" or index ~= markedIndex then return end
        if QuestInfoFrame and QuestInfoFrame.questLog then return end
        tooltip:AddLine(L["stray: höchster Verkaufswert"], ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
        tooltip:Show()
    end)
end
