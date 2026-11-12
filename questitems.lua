-- stray – Questgegenstände schützen
-- Erkennt Gegenstände in den Taschen, die für Quests im Questlog gebraucht werden
-- („Leinenstoff: 3/10“), markiert sie wie Blizzard-Questgegenstände (goldener Rahmen + „!“)
-- und warnt beim Händler, wenn so ein Gegenstand doch verkauft wurde – mit Rückkauf-Knopf.

local _, ns = ...
local L = ns.L

local IsSecret = ns.IsSecret
local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local QUEST_BANG = TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang"

---------------------------------------------------------------------------
-- Questlog lesen: Gegenstandsname → Questtitel
---------------------------------------------------------------------------

local questItems = {} -- ["Leinenstoff"] = "Die Wollrolle"

local function ItemNameFromObjective(text)
    if type(text) ~= "string" or IsSecret(text) then return nil end
    -- „Leinenstoff: 3/10“; manche Clients schreiben „3/10 Leinenstoff“
    local name = text:match("^(.-):%s*%d+%s*/%s*%d+")
        or text:match("^%d+%s*/%s*%d+%s+(.+)$")
        or text:match("^(.-):")
    if name then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
    if name == "" then return nil end
    return name
end

local function QuestEntry(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if type(info) ~= "table" then return end
        if IsSecret(info.isHeader) or IsSecret(info.title) or IsSecret(info.questID) then return end
        return info.title, info.isHeader, info.questID
    end
    local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
    if IsSecret(title) or IsSecret(isHeader) or IsSecret(questID) then return end
    return title, isHeader, questID
end

local function Objectives(index, questID)
    local list = {}
    if questID and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and type(objectives) == "table" then
            for _, o in ipairs(objectives) do
                if type(o) == "table" and not IsSecret(o.type) and not IsSecret(o.text) then
                    list[#list + 1] = { type = o.type, text = o.text }
                end
            end
            return list
        end
    end
    if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local count = GetNumQuestLeaderBoards(index)
        if IsSecret(count) or type(count) ~= "number" then return list end
        for j = 1, count do
            local text, kind = GetQuestLogLeaderBoard(j, index)
            if not IsSecret(text) and not IsSecret(kind) then
                list[#list + 1] = { type = kind, text = text }
            end
        end
    end
    return list
end

-- Merkt sich je Quest die Gegenstände. Quests unter zugeklappten Überschriften liefert das
-- Questlog nicht mit – sie bleiben deshalb aus dem Speicher erhalten, bis sie abgegeben
-- oder abgebrochen sind (statt die Überschriften für den Spieler aufzuklappen).
local questCache = {} -- [questID] = { title = "…", names = { "Leinenstoff", … } }

local function StillOnQuest(questID)
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, on = pcall(C_QuestLog.IsOnQuest, questID)
        if ok and not IsSecret(on) then return on and true or false end
    end
    return true -- ohne diese Abfrage: erst bei Abgabe/Abbruch entfernen
end

local function RebuildQuestItems()
    local count = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    if IsSecret(count) or type(count) ~= "number" then return end
    for index = 1, count do
        local title, isHeader, questID = QuestEntry(index)
        if title and not isHeader and questID then
            local names = {}
            for _, objective in ipairs(Objectives(index, questID)) do
                if objective.type == "item" then
                    local name = ItemNameFromObjective(objective.text)
                    if name then names[#names + 1] = name end
                end
            end
            questCache[questID] = { title = title, names = names }
        end
    end
    -- Neu zusammensetzen (erst am Ende ersetzen, damit nie eine halbe Liste gilt)
    local fresh = {}
    for questID, entry in pairs(questCache) do
        if StillOnQuest(questID) then
            for _, name in ipairs(entry.names) do
                if not fresh[name] then fresh[name] = entry.title end
            end
        else
            questCache[questID] = nil
        end
    end
    questItems = fresh
end

local function ForgetQuest(questID)
    if questID and not IsSecret(questID) then questCache[questID] = nil end
end

local function NameFromLink(link)
    if type(link) ~= "string" or IsSecret(link) then return nil end
    return link:match("%[(.-)%]")
end

-- Für andere Module (z. B. Automatisch verkaufen): gehört dieser Gegenstand zu einer Quest?
function ns.QuestForItemLink(link)
    local name = NameFromLink(link)
    return name and questItems[name]
end

local function SlotLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    return GetContainerItemLink and GetContainerItemLink(bag, slot)
end

---------------------------------------------------------------------------
-- Markierung an den Blizzard-Taschen
---------------------------------------------------------------------------

local marks = setmetatable({}, { __mode = "k" }) -- Taschenknopf → Markierung

local function GetMark(button)
    local mark = marks[button]
    if mark then return mark end
    mark = button:CreateTexture(nil, "OVERLAY", nil, 6)
    mark:SetAllPoints(button.icon or button.Icon or button)
    mark:SetTexture(QUEST_BANG)
    mark:Hide()
    marks[button] = mark
    return mark
end

local function ButtonBagSlot(button)
    local bag = (button.GetBagID and button:GetBagID()) or (button:GetParent() and button:GetParent():GetID())
    local slot = button:GetID()
    return bag, slot
end

local function ForEachBagButton(fn)
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            local name = frame:GetName()
            for j = 1, (frame.size or 36) do
                local button = _G[name .. "Item" .. j]
                if button and button:IsShown() then fn(button) end
            end
        end
    end
    local combined = ContainerFrameCombinedBags
    if combined and combined:IsShown() and combined.EnumerateValidItems then
        for _, button in combined:EnumerateValidItems() do fn(button) end
    end
end

local function UpdateButton(button)
    local mark = GetMark(button)
    if not ns.db or not ns.db.questItemMarks then
        mark:Hide()
        return
    end
    local bag, slot = ButtonBagSlot(button)
    local quest = bag and slot and ns.QuestForItemLink(SlotLink(bag, slot))
    mark:SetShown(quest ~= nil)
end

local function UpdateBags()
    ForEachBagButton(function(button) pcall(UpdateButton, button) end)
end

local function HideAllMarks()
    for _, mark in pairs(marks) do mark:Hide() end
end

-- Taschen werden beim Öffnen neu befüllt: kurz danach markieren
local function HookBagFrames()
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:HookScript("OnShow", function() C_Timer.After(0, UpdateBags) end)
        end
    end
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function() C_Timer.After(0, UpdateBags) end)
    end
end

---------------------------------------------------------------------------
-- Verkauf beim Händler erkennen und Rückkauf anbieten
---------------------------------------------------------------------------

local merchantOpen = false
local buybackBefore = {} -- Link → Anzahl in der Rückkaufliste

local function NumBuyback()
    local n = GetNumBuybackItems and GetNumBuybackItems() or 0
    if IsSecret(n) or type(n) ~= "number" then return 0 end
    return n
end

local function BuybackCounts()
    local counts = {}
    for i = 1, NumBuyback() do
        local link = GetBuybackItemLink(i)
        if link and not IsSecret(link) then counts[link] = (counts[link] or 0) + 1 end
    end
    return counts
end

local function FindBuyback(link)
    for i = NumBuyback(), 1, -1 do
        local l = GetBuybackItemLink(i)
        if l and not IsSecret(l) and l == link then return i end
    end
end

-- Mehrere Verkäufe auf einmal: nacheinander nachfragen
local soldQueue = {}
local ShowNextSold

StaticPopupDialogs["STRAY_QUESTITEM_SOLD"] = {
    text = L["%s gehört zur Quest „%s“.\nZurückkaufen?"],
    button1 = L["Zurückkaufen"],
    button2 = L["Nein"],
    OnAccept = function(self, data)
        local link = data or self.data
        local index = merchantOpen and link and FindBuyback(link)
        if index then
            BuybackItem(index)
            ns.Print(L("Rückkauf von %s angefordert.", link))
        else
            ns.Print(L["Zurückkaufen nicht möglich – ist der Händler noch offen?"])
        end
    end,
    OnHide = function() C_Timer.After(0, function() ShowNextSold() end) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ShowNextSold()
    if not merchantOpen then
        wipe(soldQueue)
        return
    end
    if StaticPopup_Visible and StaticPopup_Visible("STRAY_QUESTITEM_SOLD") then return end
    local entry = table.remove(soldQueue, 1)
    if not entry then return end
    -- Texte beim Anzeigen holen, damit sie der gewählten Sprache folgen
    local dialog = StaticPopupDialogs["STRAY_QUESTITEM_SOLD"]
    if dialog then
        dialog.text = L["%s gehört zur Quest „%s“.\nZurückkaufen?"]
        dialog.button1 = L["Zurückkaufen"]
        dialog.button2 = L["Nein"]
    end
    StaticPopup_Show("STRAY_QUESTITEM_SOLD", entry.link, entry.quest, entry.link)
    ns.Sound(SOUNDKIT.RAID_WARNING)
end

local function CheckSold()
    if not merchantOpen then return end
    local now = BuybackCounts()
    for link, count in pairs(now) do
        local added = count - (buybackBefore[link] or 0)
        if added > 0 and ns.db and ns.db.questItemSellWarn then
            local quest = ns.QuestForItemLink(link)
            if quest then
                for _ = 1, added do
                    soldQueue[#soldQueue + 1] = { link = link, quest = quest }
                end
            end
        end
    end
    buybackBefore = now
    ShowNextSold()
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

local pending = false

-- Das stray-Taschenfenster zeichnet die Quest-Markierung selbst (Rahmen + „!“, Option questItemMarks);
-- es braucht nur den Anstoß, wenn sich die Liste der Questgegenstände geändert hat.
local function RefreshBagWindow()
    local B = ns.Bag
    if B and B.RequestRefresh then B.RequestRefresh(0.05, "quest") end
end

local function Refresh()
    pending = false
    pcall(RebuildQuestItems)
    UpdateBags()
    pcall(RefreshBagWindow)
end

local function RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.2, Refresh)
end

ns.On("QUEST_LOG_UPDATE", RequestRefresh)
ns.On("BAG_UPDATE_DELAYED", function()
    UpdateBags()
    pcall(CheckSold)
end)

ns.On("MERCHANT_SHOW", function()
    merchantOpen = true
    buybackBefore = BuybackCounts()
    RequestRefresh()
end)
ns.On("MERCHANT_UPDATE", function() pcall(CheckSold) end)
ns.On("MERCHANT_CLOSED", function()
    merchantOpen = false
    wipe(soldQueue)
    StaticPopup_Hide("STRAY_QUESTITEM_SOLD")
end)

ns.On("QUEST_TURNED_IN", function(questID) ForgetQuest(questID); RequestRefresh() end)
ns.On("QUEST_REMOVED", function(questID) ForgetQuest(questID); RequestRefresh() end)

ns.On("PLAYER_LOGIN", function()
    HookBagFrames()
    RequestRefresh()
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(1, "Taschen", {
    key = "questItemMarks",
    label = L["Questgegenstände markieren"],
    tooltip = L["Gegenstände, die du für eine Quest in deinem Questlog brauchst, bekommen in den Taschen einen goldenen Rahmen mit „!“. So verkaufst du sie nicht aus Versehen.\n\nErkannt werden Questziele wie „Leinenstoff: 3/10“ – auch schon erfüllte, weil du sie bei der Abgabe noch brauchst."],
    set = function(value)
        ns.db.questItemMarks = value
        if value then Refresh() else HideAllMarks() end
        pcall(RefreshBagWindow)
    end,
})

ns.AddOption(1, "Händler", {
    key = "questItemSellWarn",
    label = L["Warnung beim Verkauf"],
    tooltip = L["Verkaufst du beim Händler einen Gegenstand, den du für eine Quest brauchst, fragt stray sofort nach: „Zurückkaufen?“ – ein Klick holt ihn zum gleichen Preis zurück.\n\nFunktioniert, solange der Händler offen ist."],
    set = function(value)
        ns.db.questItemSellWarn = value
        if value then RequestRefresh() end
    end,
})
