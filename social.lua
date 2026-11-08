-- stray – Sozial: Duelle ablehnen, Wiederbelebung und Beschwörung annehmen,
-- Gruppeneinladungen von Freunden/Gilde annehmen oder von Fremden ablehnen

local _, ns = ...

ns.defaults.inviteAcceptFriends = false
ns.defaults.inviteDeclineStrangers = false

ns.AddOption(3, "Sozial", {
    key = "declineDuels",
    label = "Duelle ablehnen",
    tooltip = "Duellanfragen werden sofort abgelehnt. Im Chat steht, wer dich herausgefordert hat.",
})

ns.AddOption(3, "Sozial", {
    key = "acceptRes",
    label = "Wiederbelebung annehmen",
    tooltip = "Nimmt Wiederbelebungen von Mitspielern automatisch an – aber nicht, solange der Wiederbelebende noch im Kampf ist.",
})

ns.AddOption(3, "Sozial", {
    key = "acceptSummon",
    label = "Beschwörung annehmen",
    tooltip = "Nimmt Beschwörungen (z. B. vom Hexenmeister) automatisch an – nicht, wenn du gerade im Kampf bist.",
})

ns.AddOption(3, "Sozial", {
    key = "inviteAcceptFriends",
    label = "Einladungen von Freunden und Gilde annehmen",
    tooltip = "Gruppeneinladungen von Freunden, Battle.net-Freunden und Gildenmitgliedern werden automatisch angenommen.\nNicht, solange du in einer Warteschlange bist, und nicht bei Einladungen über die Gruppensuche.",
})

ns.AddOption(3, "Sozial", {
    key = "inviteDeclineStrangers",
    label = "Einladungen von Fremden ablehnen",
    tooltip = "Gruppeneinladungen von Spielern, die weder Freund noch in deiner Gilde sind, werden sofort abgelehnt. Im Chat steht, wer dich eingeladen hat.\nEinladungen über die Gruppensuche bleiben unberührt.",
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
    ns.Print(("Duell von %s abgelehnt."):format(name or "?"))
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
        ns.Print(("Wiederbelebung von %s nicht automatisch angenommen – noch im Kampf."):format(name or "?"))
        return
    end
    AcceptResurrect()
    HidePopups("RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER")
    ns.Print(("Wiederbelebung von %s angenommen."):format(name or "?"))
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
        ns.Print("Beschwörung nicht automatisch angenommen – du bist im Kampf.")
        return
    end
    C_Timer.After(0.5, function()
        if UnitAffectingCombat("player") then return end
        local summoner, area = SummonInfo()
        summoner, area = ns.Public(summoner), ns.Public(area)
        ConfirmSummonNow()
        HidePopups("CONFIRM_SUMMON", "CONFIRM_SUMMON_SCENARIO", "CONFIRM_SUMMON_STARTING_AREA")
        ns.Print(("Beschwörung von %s nach %s angenommen."):format(summoner or "?", area or "?"))
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
    ns.Print(("Einladung von %s angenommen."):format(name or "?"))
end

local function Decline(name)
    DeclineGroup()
    HidePopups("PARTY_INVITE")
    C_Timer.After(0, function() HidePopups("PARTY_INVITE") end)
    ns.Print(("Einladung von %s abgelehnt."):format(name or "?"))
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
