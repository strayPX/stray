-- stray – Automation (Phase 2, Leatrix-Funktionen nachgebaut)
-- Bereich „Automatisch“: Geist im Schlachtfeld freigeben, bei Sitzen/Reiten aufstehen/absteigen,
-- Beute-Rückfragen bestätigen, Taschen nicht automatisch öffnen
local _, ns = ...
local L = ns.L

ns.defaults.autoReleasePvP = false
ns.defaults.autoStandDismount = false
ns.defaults.autoConfirmLoot = false
ns.defaults.noAutoBags = false

local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok or ns.IsSecret(a) then return nil end
    return a
end

---------------------------------------------------------------------------
-- 1. Im Schlachtfeld automatisch Geist freigeben
---------------------------------------------------------------------------

local resOffered = false

local function InBattleground()
    local ok, inInstance, kind = pcall(IsInInstance)
    if not ok or ns.IsSecret(kind) then return false end
    return inInstance and kind == "pvp"
end

local function TryRelease()
    local db = ns.db
    if not db or not db.autoReleasePvP then return end
    if not UnitIsDead("player") or UnitIsGhost("player") then return end
    if not InBattleground() then return end
    if resOffered then return end
    -- Seelenstein/Selbstwiederbelebung vorhanden: selbst entscheiden lassen
    if C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions then
        local options = Safe(C_DeathInfo.GetSelfResurrectOptions)
        if type(options) == "table" and #options > 0 then return end
    end
    -- Freigeben gesperrt (Aura, Bosskampf) oder Wiederbelebungsangebot sichtbar: nichts tun
    if HasNoReleaseAura and Safe(HasNoReleaseAura) then return end
    if C_InstanceEncounter and C_InstanceEncounter.IsEncounterSuppressingRelease
        and Safe(C_InstanceEncounter.IsEncounterSuppressingRelease) then return end
    if StaticPopup_Visible then
        for _, which in ipairs({ "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }) do
            if Safe(StaticPopup_Visible, which) then return end
        end
    end
    if IsFalling and Safe(IsFalling) and not (IsOutOfBounds and Safe(IsOutOfBounds)) then
        C_Timer.After(1, TryRelease)
        return
    end
    pcall(RepopMe)
end

ns.On("PLAYER_DEAD", function()
    resOffered = false
    if not ns.db or not ns.db.autoReleasePvP then return end
    C_Timer.After(0.6, TryRelease)
end)

ns.On("RESURRECT_REQUEST", function() resOffered = true end)
ns.On("PLAYER_ALIVE", function() resOffered = false end)
ns.On("PLAYER_UNGHOST", function() resOffered = false end)

ns.AddOption(3, "Automatisch", {
    key = "autoReleasePvP",
    label = L["Im Schlachtfeld Geist automatisch freigeben"],
    tooltip = L["Stirbst du in einem Schlachtfeld, wird dein Geist automatisch freigegeben.\nNicht in Arenen, nicht mit Seelenstein oder Selbstwiederbelebung, nicht bei gesperrter Freigabe und nicht, solange dir jemand eine Wiederbelebung anbietet."],
    keywords = { "geist", "freigeben", "schlachtfeld", "pvp", "tod", "release", "spirit", "battleground", "death", "ghost" },
})

---------------------------------------------------------------------------
-- 2. Automatisch aufstehen / absteigen
---------------------------------------------------------------------------

local MOUNT_ERRORS = { "ERR_NOT_WHILE_MOUNTED", "ERR_ATTACK_MOUNTED", "ERR_TAXIPLAYERALREADYMOUNTED" }
local STAND_ERRORS = { "SPELL_FAILED_NOT_STANDING", "ERR_CANTATTACK_NOTSTANDING", "ERR_LOOT_NOTSTANDING", "ERR_TAXINOTSTANDING" }

local mountSet, standSet

local function BuildSet(names)
    local set = {}
    for _, name in ipairs(names) do
        local text = _G[name]
        if type(text) == "string" and text ~= "" and not text:find("%%") then set[text] = true end
    end
    return set
end

local lastAction = 0

ns.On("UI_ERROR_MESSAGE", function(arg1, arg2)
    if not ns.db or not ns.db.autoStandDismount then return end
    if ns.IsSecret(arg1) or ns.IsSecret(arg2) then return end
    local message = (type(arg2) == "string") and arg2 or arg1
    if type(message) ~= "string" then return end
    if InCombatLockdown() then return end
    if not mountSet then
        mountSet, standSet = BuildSet(MOUNT_ERRORS), BuildSet(STAND_ERRORS)
    end
    local now = GetTime()
    if now - lastAction < 1 then return end
    if mountSet[message] then
        -- Nicht in der Luft, nicht auf Flugrouten
        if Safe(IsFlying) then return end
        if Safe(UnitOnTaxi, "player") then return end
        if Safe(IsMounted) then
            lastAction = now
            pcall(Dismount)
        end
    elseif standSet[message] then
        lastAction = now
        if C_ChatInfo and C_ChatInfo.PerformEmote then
            pcall(C_ChatInfo.PerformEmote, "STAND", nil, true)
        elseif DoEmote then
            pcall(DoEmote, "STAND", nil, true)
        end
    end
end)

ns.AddOption(3, "Automatisch", {
    key = "autoStandDismount",
    label = L["Automatisch aufstehen und absteigen"],
    tooltip = L["Verhindert Sitzen oder Reiten eine Aktion („Du musst dafür stehen“, „Das geht nicht beim Reiten“), stehst du auf bzw. steigst ab. Wiederhole die Aktion dann einfach.\nNur außerhalb des Kampfes, nicht im Flug und nicht auf Flugrouten. Gestaltwandlerformen bleiben unberührt."],
    keywords = { "aufstehen", "absteigen", "sitzen", "reiten", "reittier", "stand", "dismount", "mount", "sit", "seated" },
})

---------------------------------------------------------------------------
-- 3. Beute-Rückfragen (Bindung beim Aufheben) automatisch bestätigen
---------------------------------------------------------------------------

-- Nur „Bindet beim Aufheben“ bei Beute und beim Würfeln; „Gegenstand zerstören“ und
-- Entzauberungswürfe werden nie automatisch bestätigt.
ns.On("LOOT_BIND_CONFIRM", function(slot)
    if not ns.db or not ns.db.autoConfirmLoot then return end
    slot = ns.Public(slot)
    if type(slot) ~= "number" then return end
    pcall(ConfirmLootSlot, slot)
    C_Timer.After(0, function() pcall(StaticPopup_Hide, "LOOT_BIND") end)
end)

ns.On("CONFIRM_LOOT_ROLL", function(rollID, rollType)
    if not ns.db or not ns.db.autoConfirmLoot then return end
    rollID, rollType = ns.Public(rollID), ns.Public(rollType)
    if type(rollID) ~= "number" or type(rollType) ~= "number" then return end
    pcall(ConfirmLootRoll, rollID, rollType)
    C_Timer.After(0, function() pcall(StaticPopup_Hide, "CONFIRM_LOOT_ROLL") end)
end)

ns.AddOption(3, "Automatisch", {
    key = "autoConfirmLoot",
    label = L["Beute-Warnungen automatisch bestätigen"],
    tooltip = L["Bestätigt die Rückfrage „Dieser Gegenstand wird beim Aufheben gebunden“ bei Beute und beim Würfeln (Bedarf/Gier).\n„Gegenstand zerstören“ und Entzauberungs-Rückfragen bestätigt stray nie automatisch."],
    keywords = { "beute", "bindung", "binden", "aufheben", "würfeln", "warnung", "bestätigen", "loot", "bind", "pickup", "roll", "confirm", "warning" },
})

---------------------------------------------------------------------------
-- 4. Taschen nicht automatisch öffnen (Händler, Bank, Post)
---------------------------------------------------------------------------

-- Blizzards OpenAllBags(frame) merkt sich intern, welches Fenster die Taschen geöffnet hat;
-- CloseAllBags(frame) schließt sie nur, wenn es dasselbe Fenster ist. Taschen, die du vorher
-- selbst geöffnet hast, bleiben also offen. Keine eigenen Felder auf Blizzard-Frames.
local BAG_FRAMES = { MerchantFrame = true, BankFrame = true, MailFrame = true }

if type(OpenAllBags) == "function" and type(CloseAllBags) == "function" then
    hooksecurefunc("OpenAllBags", function(frame)
        if not ns.db or not ns.db.noAutoBags then return end
        if type(frame) ~= "table" or not frame.GetName then return end
        local ok, name = pcall(frame.GetName, frame)
        if not ok or type(name) ~= "string" or not BAG_FRAMES[name] then return end
        if InCombatLockdown() then return end
        pcall(CloseAllBags, frame)
    end)
end

ns.AddOption(3, "Automatisch", {
    key = "noAutoBags",
    label = L["Taschen nicht automatisch öffnen"],
    tooltip = L["Beim Händler, in der Bank und am Briefkasten öffnen sich deine Taschen nicht von selbst. Mit der Taschentaste öffnest du sie jederzeit selbst.\nWirkt nur auf Taschen, die diese Fenster geöffnet hätten."],
    keywords = { "taschen", "öffnen", "schließen", "händler", "bank", "post", "briefkasten", "bags", "open", "close", "vendor", "merchant", "mail" },
})
