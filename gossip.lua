-- stray – Gesprächsmenü überspringen
-- Hat ein NPC genau eine Gesprächsoption und keine Quests (Flugmeister, Gastwirt, Bankier,
-- Händler …), wählt stray sie automatisch. Shift verhindert das.

local _, ns = ...
local L = ns.L

local IsSecret = ns.IsSecret

ns.AddOption(1, "Quests", {
    key = "gossipSkip",
    label = L["Gesprächsmenü überspringen"],
    tooltip = L["Hat ein NPC nur eine Gesprächsoption und keine Quests – etwa Flugmeister, Gastwirt, Bankier oder Händler –, wählt stray sie automatisch. Halte Shift gedrückt, um das Menü zu sehen.\n\nOptionen mit Bestätigung (z. B. Gold bezahlen) fragt WoW weiterhin ab."],
})

local lastNpc, lastTime = nil, 0

local function Count(list)
    if type(list) ~= "table" then return 0 end
    return #list
end

ns.On("GOSSIP_SHOW", function()
    if not ns.db or not ns.db.gossipSkip or IsShiftKeyDown() then return end
    if not C_GossipInfo or not C_GossipInfo.GetOptions then return end

    -- Quests haben Vorrang (die erledigt ggf. die Quest-Automatik)
    if Count(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()) > 0 then return end
    if Count(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests()) > 0 then return end

    local options = C_GossipInfo.GetOptions()
    if Count(options) ~= 1 then return end
    local option = options[1]
    if type(option) ~= "table" then return end

    -- Schutz gegen Schleifen: denselben NPC nicht sofort wieder automatisch bedienen
    local npc = UnitGUID("npc")
    if IsSecret(npc) then npc = nil end
    local now = GetTime()
    if npc and npc == lastNpc and now - lastTime < 3 then return end
    lastNpc, lastTime = npc, now

    local id, index = option.gossipOptionID, option.orderIndex
    if IsSecret(id) then id = nil end
    if IsSecret(index) then index = nil end
    if id and C_GossipInfo.SelectOption then
        C_GossipInfo.SelectOption(id)
    elseif index and C_GossipInfo.SelectOptionByIndex then
        C_GossipInfo.SelectOptionByIndex(index)
    end
end)
