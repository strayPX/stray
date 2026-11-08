-- stray – Sozial: Duelle ablehnen, Wiederbelebung und Beschwörung annehmen,
-- Gruppeneinladungen von Freunden/Gilde annehmen oder von Fremden ablehnen

local _, ns = ...
local L = ns.L

ns.defaults.inviteAcceptFriends = false
ns.defaults.inviteDeclineStrangers = false
ns.defaults.declineFriendRequests = false
ns.defaults.declinePetDuels = false
ns.defaults.declineSharedQuests = false
ns.defaults.declineSharedQuestsStrangers = false
ns.defaults.whisperInvite = false
ns.defaults.whisperInviteWord = "inv"

ns.AddOption(3, "Sozial", {
    key = "declineDuels",
    label = L["Duelle ablehnen"],
    tooltip = L["Duellanfragen werden sofort abgelehnt. Im Chat steht, wer dich herausgefordert hat."],
})

ns.AddOption(3, "Sozial", {
    key = "acceptRes",
    label = L["Wiederbelebung annehmen"],
    tooltip = L["Nimmt Wiederbelebungen von Mitspielern automatisch an – aber nicht, solange der Wiederbelebende noch im Kampf ist."],
})

ns.AddOption(3, "Sozial", {
    key = "acceptSummon",
    label = L["Beschwörung annehmen"],
    tooltip = L["Nimmt Beschwörungen (z. B. vom Hexenmeister) automatisch an – nicht, wenn du gerade im Kampf bist."],
})

ns.AddOption(3, "Sozial", {
    key = "inviteAcceptFriends",
    label = L["Einladungen von Freunden und Gilde annehmen"],
    tooltip = L["Gruppeneinladungen von Freunden, Battle.net-Freunden und Gildenmitgliedern werden automatisch angenommen.\nNicht, solange du in einer Warteschlange bist, und nicht bei Einladungen über die Gruppensuche."],
})

ns.AddOption(3, "Sozial", {
    key = "inviteDeclineStrangers",
    label = L["Einladungen von Fremden ablehnen"],
    tooltip = L["Gruppeneinladungen von Spielern, die weder Freund noch in deiner Gilde sind, werden sofort abgelehnt. Im Chat steht, wer dich eingeladen hat.\nEinladungen über die Gruppensuche bleiben unberührt."],
})

local function HidePopups(...)
    for i = 1, select("#", ...) do
        StaticPopup_Hide((select(i, ...)))
    end
end

---------------------------------------------------------------------------
-- Duelle
---------------------------------------------------------------------------

ns.On("DUEL_REQUESTED", function(name)
    if not ns.db or not ns.db.declineDuels then return end
    name = ns.Public(name)
    CancelDuel()
    HidePopups("DUEL_REQUESTED")
    C_Timer.After(0, function() HidePopups("DUEL_REQUESTED") end)
    ns.Print(L("Duell von %s abgelehnt.", name or "?"))
end)

---------------------------------------------------------------------------
-- Wiederbelebung
---------------------------------------------------------------------------

local function InCombat(name)
    if not name then return true end -- Name unbekannt (z. B. versiegelt) = nicht automatisch annehmen
    local ok, combat = pcall(UnitAffectingCombat, name)
    -- Unklar (Fehler oder versiegelt) = sicherheitshalber „im Kampf“
    if not ok or ns.IsSecret(combat) then return true end
    return combat and true or false
end

local function AcceptRes(name)
    if not UnitIsDeadOrGhost("player") then return end
    if InCombat(name) then
        ns.Print(L("Wiederbelebung von %s nicht automatisch angenommen – noch im Kampf.", name or "?"))
        return
    end
    AcceptResurrect()
    HidePopups("RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER")
    ns.Print(L("Wiederbelebung von %s angenommen.", name or "?"))
end

ns.On("RESURRECT_REQUEST", function(name)
    if not ns.db or not ns.db.acceptRes then return end
    name = ns.Public(name)
    -- Gibt es noch eine Wartezeit, erst danach annehmen
    local delay = GetCorpseRecoveryDelay and GetCorpseRecoveryDelay() or 0
    C_Timer.After(math.max(delay, 0) + 0.5, function() AcceptRes(name) end)
end)

---------------------------------------------------------------------------
-- Beschwörung
---------------------------------------------------------------------------

local function ConfirmSummonNow()
    if C_SummonInfo and C_SummonInfo.ConfirmSummon then
        C_SummonInfo.ConfirmSummon()
    elseif ConfirmSummon then
        ConfirmSummon()
    end
end

local function SummonInfo()
    if C_SummonInfo then
        return C_SummonInfo.GetSummonConfirmSummoner and C_SummonInfo.GetSummonConfirmSummoner(),
            C_SummonInfo.GetSummonConfirmAreaName and C_SummonInfo.GetSummonConfirmAreaName()
    end
    return GetSummonConfirmSummoner and GetSummonConfirmSummoner(),
        GetSummonConfirmAreaName and GetSummonConfirmAreaName()
end

ns.On("CONFIRM_SUMMON", function()
    if not ns.db or not ns.db.acceptSummon then return end
    if UnitAffectingCombat("player") then
        ns.Print(L["Beschwörung nicht automatisch angenommen – du bist im Kampf."])
        return
    end
    C_Timer.After(0.5, function()
        if UnitAffectingCombat("player") then return end
        local summoner, area = SummonInfo()
        summoner, area = ns.Public(summoner), ns.Public(area)
        ConfirmSummonNow()
        HidePopups("CONFIRM_SUMMON", "CONFIRM_SUMMON_SCENARIO", "CONFIRM_SUMMON_STARTING_AREA")
        ns.Print(L("Beschwörung von %s nach %s angenommen.", summoner or "?", area or "?"))
    end)
end)

---------------------------------------------------------------------------
-- Gruppeneinladungen
---------------------------------------------------------------------------

-- Nur öffentliche Werte weiterreichen; versiegelte Argumente dürfen nicht an die APIs
local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then return nil end
    end
    local ok, result = pcall(fn, ...)
    if not ok or ns.IsSecret(result) then return nil end
    return result
end

local function IsFriendOrGuild(name, guid)
    if guid then
        if C_FriendList and SafeCall(C_FriendList.IsFriend, guid) then return true end
        if C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
            local info = SafeCall(C_BattleNet.GetAccountInfoByGUID, guid)
            if type(info) == "table" and not ns.IsSecret(info.isFriend) and info.isFriend then return true end
        end
        if SafeCall(IsGuildMember, guid) then return true end
    end
    if name then
        if C_GuildInfo and SafeCall(C_GuildInfo.MemberExistsByName, name) then return true end
        if C_FriendList and C_FriendList.GetFriendInfo and SafeCall(C_FriendList.GetFriendInfo, name) then return true end
    end
    return false
end

-- Einladung annehmen und das Fenster erst schließen, wenn wir wirklich in der Gruppe sind
-- (das Blizzard-Fenster lehnt beim Schließen sonst selbst ab)
local function AcceptAndClose(name)
    AcceptGroup()
    local tries = 0
    local function Check()
        tries = tries + 1
        if IsInGroup and IsInGroup() then
            HidePopups("PARTY_INVITE")
            return
        end
        if tries < 10 then C_Timer.After(0.3, Check) end
    end
    C_Timer.After(0.2, Check)
    ns.Print(L("Einladung von %s angenommen.", name or "?"))
end

local function Decline(name)
    DeclineGroup()
    HidePopups("PARTY_INVITE")
    C_Timer.After(0, function() HidePopups("PARTY_INVITE") end)
    ns.Print(L("Einladung von %s abgelehnt.", name or "?"))
end

ns.On("PARTY_INVITE_REQUEST", function(name, isTank, isHealer, isDamage, _, _, inviterGUID, questSessionActive)
    if not ns.db or not (ns.db.inviteAcceptFriends or ns.db.inviteDeclineStrangers) then return end
    -- Gruppensuche (Rollenabfrage) und Questsitzungen nicht anfassen
    if ns.Public(isTank) or ns.Public(isHealer) or ns.Public(isDamage) or ns.Public(questSessionActive) then return end
    -- In einer Warteschlange: Annehmen würde sie verlassen, also selbst entscheiden lassen
    if WillAcceptInviteRemoveQueues then
        local ok, removes = pcall(WillAcceptInviteRemoveQueues)
        if not ok or ns.IsSecret(removes) or removes then return end
    end

    name = ns.Public(name)
    local guid = ns.Public(inviterGUID)
    if type(name) ~= "string" then name = nil end
    if type(guid) ~= "string" or guid == "" then guid = nil end
    -- Ohne Namen und GUID nicht entscheiden
    if not name and not guid then return end

    if IsFriendOrGuild(name, guid) then
        if ns.db.inviteAcceptFriends then AcceptAndClose(name) end
    elseif ns.db.inviteDeclineStrangers then
        -- Bist du in der Gruppensuche gelistet, laden Fremde dich ganz normal ein – dann nicht ablehnen
        if C_LFGList and C_LFGList.HasActiveEntryInfo then
            local ok, listed = pcall(C_LFGList.HasActiveEntryInfo)
            if not ok or ns.IsSecret(listed) or listed then return end
        end
        Decline(name)
    end
end)

---------------------------------------------------------------------------
-- Weitere Sozial-Optionen (Phase 2): Freundschaftsanfragen, Haustierkampf-Duelle,
-- geteilte Quests, Einladung per Flüstern
---------------------------------------------------------------------------

ns.AddOption(3, "Sozial", {
    key = "declineFriendRequests",
    label = L["Freundschaftsanfragen ablehnen"],
    tooltip = L["Neue Battle.net-Freundschaftsanfragen (BattleTag und Real-ID) werden automatisch abgelehnt. Im Chat steht, dass eine Anfrage abgelehnt wurde.\nBereits offene Anfragen vom Login bleiben unberührt."],
    keywords = { "freundschaft", "freundschaftsanfrage", "battletag", "real-id", "realid", "freund", "ablehnen", "blockieren", "friend", "request", "decline", "block", "battle.net" },
})

ns.AddOption(3, "Sozial", {
    key = "declinePetDuels",
    label = L["Haustierkampf-Duelle ablehnen"],
    tooltip = L["Herausforderungen zu einem Haustierkampf (PvP-Duell) werden sofort abgelehnt. Im Chat steht, wer dich herausgefordert hat."],
    keywords = { "haustier", "haustierkampf", "duell", "pvp", "ablehnen", "blockieren", "pet", "battle", "duel", "decline", "block" },
})

ns.AddOption(3, "Sozial", {
    key = "declineSharedQuests",
    label = L["Geteilte Quests ablehnen"],
    tooltip = L["Quests, die dir jemand aus seinem Questlog teilt, werden nicht angeboten. Im Chat steht, wer und welche Quest.\nDas gilt für alle, auch für Freunde und Gildenmitglieder."],
    keywords = { "quest", "geteilt", "teilen", "weitergabe", "ablehnen", "share", "shared", "sharing", "decline", "push" },
})

ns.AddOption(3, "Sozial", {
    key = "declineSharedQuestsStrangers",
    label = L["Geteilte Quests von Fremden ablehnen"],
    tooltip = L["Wie „Geteilte Quests ablehnen“, aber nur für Spieler, die weder Freund noch in deiner Gilde sind. Quests von Freunden und Gildenmitgliedern werden weiter angeboten."],
    keywords = { "quest", "geteilt", "teilen", "fremde", "ablehnen", "share", "shared", "stranger", "decline", "push" },
    isEnabled = function() return not (ns.db and ns.db.declineSharedQuests) end,
    disabledHint = L["Schon durch „Geteilte Quests ablehnen“ (direkt darüber) abgedeckt."],
})

ns.AddOption(3, "Sozial", {
    key = "whisperInvite",
    label = L["Per Flüstern einladen"],
    tooltip = L["Wer dir das Schlüsselwort flüstert (ganze Nachricht, Groß-/Kleinschreibung egal), wird in deine Gruppe eingeladen.\nNur, wenn du einladen darfst, nicht in Instanzen, nicht in Warteschlangen oder der Gruppensuche und nicht öfter als einmal alle 10 Sekunden pro Spieler."],
    keywords = { "flüstern", "einladen", "einladung", "inv", "invite", "whisper", "keyword", "schlüsselwort", "gruppe", "group" },
})

ns.AddOption(3, "Sozial", {
    key = "whisperInviteWord",
    type = "choice",
    values = { "inv", "invite", "einladen" },
    labels = { "inv", "invite", "einladen" },
    label = L["Schlüsselwort zum Einladen"],
    tooltip = L["Dieses Wort, geflüstert, lädt den Absender ein."],
    keywords = { "schlüsselwort", "flüstern", "einladen", "inv", "keyword", "whisper", "invite" },
    isEnabled = function() return ns.db and ns.db.whisperInvite end,
    disabledHint = L["Erst „Per Flüstern einladen“ einschalten (direkt darüber)."],
})

-- Freundschaftsanfragen (Battle.net)
ns.On("BN_FRIEND_INVITE_ADDED", function()
    if not ns.db or not ns.db.declineFriendRequests then return end
    C_Timer.After(0.2, function()
        if not ns.db or not ns.db.declineFriendRequests then return end
        if not BNGetNumFriendInvites or not BNDeclineFriendInvite then return end
        local ok, count = pcall(BNGetNumFriendInvites)
        if not ok or ns.IsSecret(count) or type(count) ~= "number" then return end
        local declined = 0
        for i = count, 1, -1 do
            local info = SafeCall(C_BattleNet and C_BattleNet.GetFriendInviteInfo, i)
            local id = type(info) == "table" and ns.Public(info.inviteID) or nil
            if type(id) == "number" and pcall(BNDeclineFriendInvite, id) then declined = declined + 1 end
        end
        if declined > 0 then ns.Print(L("Freundschaftsanfragen abgelehnt: %d", declined)) end
    end)
end)

-- Haustierkampf-Duelle
ns.On("PET_BATTLE_PVP_DUEL_REQUESTED", function(name)
    if not ns.db or not ns.db.declinePetDuels then return end
    name = ns.Public(name)
    if C_PetBattles and C_PetBattles.CancelPVPDuel then pcall(C_PetBattles.CancelPVPDuel) end
    HidePopups("PET_BATTLE_PVP_DUEL_REQUESTED")
    C_Timer.After(0, function() HidePopups("PET_BATTLE_PVP_DUEL_REQUESTED") end)
    ns.Print(L("Haustierkampf-Duell von %s abgelehnt.", type(name) == "string" and name or "?"))
end)

-- Geteilte Quests (nur das Angebot wegklicken; der Teilende bekommt keine Zusage)
ns.On("QUEST_ACCEPT_CONFIRM", function(name, questTitle)
    if not ns.db or not (ns.db.declineSharedQuests or ns.db.declineSharedQuestsStrangers) then return end
    name, questTitle = ns.Public(name), ns.Public(questTitle)
    if type(name) ~= "string" then name = nil end
    if not ns.db.declineSharedQuests then
        -- Nur Fremde: ohne bekannten Namen oder bei Freund/Gilde nichts tun
        if not name or IsFriendOrGuild(name, nil) then return end
    end
    HidePopups("QUEST_ACCEPT", "QUEST_ACCEPT_LOG_FULL")
    C_Timer.After(0, function() HidePopups("QUEST_ACCEPT", "QUEST_ACCEPT_LOG_FULL") end)
    ns.Print(L("Geteilte Quest „%s“ von %s abgelehnt.", type(questTitle) == "string" and questTitle or "?", name or "?"))
end)

-- Einladung per Flüstern
local WHISPER_WORDS = { inv = true, invite = true, einladen = true }
local lastWhisperInvite = {}

local function QueuedOrListed()
    -- Gruppensuche, Dungeon-/Raid-Warteschlange, Schlachtfeld-Warteschlange
    if C_LFGList and C_LFGList.HasActiveEntryInfo then
        local ok, listed = pcall(C_LFGList.HasActiveEntryInfo)
        if not ok or ns.IsSecret(listed) or listed then return true end
    end
    if GetLFGMode and LE_LFG_CATEGORY_LFD then
        for category = 1, 6 do
            local ok, mode = pcall(GetLFGMode, category)
            if ok and not ns.IsSecret(mode) and mode then return true end
        end
    end
    if GetBattlefieldStatus then
        for i = 1, 6 do
            local ok, status = pcall(GetBattlefieldStatus, i)
            if ok and not ns.IsSecret(status) and (status == "queued" or status == "confirm") then return true end
        end
    end
    return false
end

ns.On("CHAT_MSG_WHISPER", function(text, sender)
    if not ns.db or not ns.db.whisperInvite then return end
    text, sender = ns.Public(text), ns.Public(sender)
    if type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
    local word = ns.db.whisperInviteWord
    if not WHISPER_WORDS[word] then word = "inv" end
    local msg = text:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if msg ~= word then return end
    local ok, inInstance = pcall(IsInInstance)
    if not ok or ns.IsSecret(inInstance) or inInstance then return end
    if UnitAffectingCombat("player") then return end
    if C_PartyInfo and C_PartyInfo.CanInvite then
        local can = SafeCall(C_PartyInfo.CanInvite)
        if not can then return end
    end
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return end
    if QueuedOrListed() then return end
    local now = GetTime()
    if lastWhisperInvite[sender] and now - lastWhisperInvite[sender] < 10 then return end
    lastWhisperInvite[sender] = now
    local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
    if type(invite) ~= "function" then return end
    if pcall(invite, sender) then
        ns.Print(L("%s per Flüstern eingeladen.", sender))
    end
end)
