-- stray – Sozial: Duelle ablehnen, Wiederbelebung und Beschwörung annehmen

local _, ns = ...

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
