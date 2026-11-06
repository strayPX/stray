-- stray – Quests: automatisch annehmen und abgeben

local _, ns = ...

ns.AddOption(2, "Quests", {
    key = "questAccept",
    label = "Automatisch annehmen",
    tooltip = "Nimmt neue Quests von NPCs und Gegenständen ohne Klick an. Graue Quests, von Mitspielern geteilte Quests und Begleitquests nimmst du selbst an.\n\nHalte Shift gedrückt, um das zu verhindern.",
})

ns.AddOption(2, "Quests", {
    key = "questTurnIn",
    label = "Automatisch abgeben",
    tooltip = "Gibt fertige Quests ohne Klick ab. Stehen mehrere Belohnungen zur Auswahl oder kostet die Abgabe Gold, entscheidest du selbst.\n\nHalte Shift gedrückt, um das zu verhindern.",
})

-- Quests, bei denen wir bewusst angehalten haben (Auswahl/Gold) – nicht erneut automatisch öffnen
local skipped = {}

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
            if quest.isComplete and not skipped[quest.title] then
                C_GossipInfo.SelectActiveQuest(quest.questID)
                return
            end
        end
    end

    if Active("questAccept") then
        for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if not quest.isTrivial then
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
            if isComplete and not skipped[title] then
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
        skipped[GetTitleText()] = true
        return
    end
    CompleteQuest()
end)

-- Belohnungsseite
ns.On("QUEST_COMPLETE", function()
    if not Active("questTurnIn") then return end
    local choices = GetNumQuestChoices()
    if choices > 1 then
        skipped[GetTitleText()] = true
        return
    end
    GetQuestReward(choices)
end)
-- Einträge in „skipped“ bleiben bis zum nächsten /reload, damit dieselbe Quest
-- nicht ständig erneut automatisch geöffnet wird.
