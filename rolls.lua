-- stray – Würfelfenster (Bedarf/Gier) verschiebbar
--
-- Auf Forever stehen die Würfelfenster GroupLootFrame1–4 in Blizzards GroupLootContainer.
-- Der ist kein Edit-Mode-System (das gibt es nur für das normale Beutefenster), sondern ein
-- „BottomManagedFrame“: BottomManagedFrameContainer stapelt ihn über den Aktionsleisten.
--
-- stray legt einen verschiebbaren Platzhalter „Würfelfenster“ an und richtet den Container
-- nach jedem Blizzard-Layout daran aus (hooksecurefunc auf GroupLootContainer_Update und
-- BottomManagedFrameContainer:Layout). Die Würfelfenster hängen an der Unterkante des
-- Containers und wachsen nach oben. stray schreibt keine Felder auf Blizzards Rahmen.
-- Falls der Container geschützt ist, wird er im Kampf nicht umgesetzt, sondern danach.

local _, ns = ...

ns.defaults.rollsMove = false

local FONT = "Fonts\\ARIALN.TTF"
local C = {
    bg     = { 0.051, 0.067, 0.090, 0.95 },
    border = { 0.169, 0.290, 0.451, 1 },
    accent = { 0.353, 0.659, 1.000, 1 },
    text   = { 0.890, 0.914, 0.953, 1 },
    dim    = { 0.435, 0.525, 0.651, 1 },
}

local holder = CreateFrame("Frame", "strayRolls", UIParent)
holder:SetSize(280, 70)
holder:SetFrameStrata("MEDIUM")
ns.MakeMovable(holder, "rolls", { "BOTTOM", "BOTTOM", 0, 230 })

-- Beispielrahmen, nur bei offenem stray-Fenster sichtbar
local sample = CreateFrame("Frame", nil, holder)
sample:SetAllPoints()
do
    local bg = sample:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = sample:CreateTexture(nil, "BORDER")
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
    end
    local title = sample:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 13, "")
    title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    title:SetPoint("TOP", 0, -14)
    title:SetText("Würfelfenster")
    local hint = sample:CreateFontString(nil, "OVERLAY")
    hint:SetFont(FONT, 11, "")
    hint:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetText("Bedarf / Gier erscheint hier, weitere darüber")
end
sample:Hide()
holder:SetScript("OnEnter", function(self)
    if not sample:IsShown() then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Würfelfenster", 1, 1, 1)
    GameTooltip:AddLine("Hier erscheinen die Bedarf-/Gier-Fenster.", C.text[1], C.text[2], C.text[3], true)
    GameTooltip:AddLine("Shift + ziehen zum Verschieben", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
holder:SetScript("OnLeave", function() GameTooltip:Hide() end)

local hooked = false
local deferred = false

local function Container()
    local c = GroupLootContainer
    if type(c) == "table" and c.ClearAllPoints and c.SetPoint then return c end
end

local function IsProtected(frame)
    if not frame.IsProtected then return false end
    local ok, protected = pcall(frame.IsProtected, frame)
    return ok and protected and true or false
end

local function Reanchor()
    if not (ns.db and ns.db.rollsMove) then return end
    local c = Container()
    if not c then return end
    if InCombatLockdown() and IsProtected(c) then
        deferred = true
        return
    end
    pcall(function()
        c:ClearAllPoints()
        c:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)
    end)
end

local function InstallHooks()
    if hooked then return end
    if type(GroupLootContainer_Update) == "function" then
        hooksecurefunc("GroupLootContainer_Update", Reanchor)
        hooked = true
    end
    local managed = BottomManagedFrameContainer
    if type(managed) == "table" and type(managed.Layout) == "function" then
        hooksecurefunc(managed, "Layout", Reanchor)
        hooked = true
    end
end

local function UpdateHolder()
    local on = ns.db and ns.db.rollsMove
    -- Der Platzhalter ist immer da (Anker), sichtbar nur mit Beispiel bei offenem stray-Fenster
    if on then
        holder:Show()
        holder:EnableMouse(ns.IsConfigOpen())
        sample:SetShown(ns.IsConfigOpen())
    else
        holder:Hide()
        sample:Hide()
    end
end

local function Apply()
    UpdateHolder()
    if ns.db.rollsMove then
        InstallHooks()
        Reanchor()
    end
end

ns.RegisterMovable(holder, "Würfelfenster", function() UpdateHolder() end)
ns.OnConfig(function() UpdateHolder() end)

ns.AddOption(3, "Interface", {
    key = "rollsMove",
    label = "Würfelfenster verschiebbar",
    tooltip = "Die Bedarf-/Gier-Fenster erscheinen an einer Stelle deiner Wahl statt über den Aktionsleisten. Bei offenem stray-Fenster siehst du einen Platzhalter „Würfelfenster“, den du mit Shift + linker Maustaste oder im Bearbeiten-Modus verschiebst.\n\nAusschalten wirkt ganz nach /reload.",
    set = function(value)
        ns.db.rollsMove = value
        Apply()
        if not value then ns.Print("Blizzards Würfelfenster-Position kommt spätestens nach /reload zurück.") end
    end,
})

ns.On("PLAYER_LOGIN", function()
    ns.RestorePosition(holder)
    Apply()
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if deferred then
        deferred = false
        Reanchor()
    end
end)
