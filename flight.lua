-- stray – Reisen: Flugzeit-Anzeige oben mittig
-- WoW liefert keine Flugdauer. stray misst jede Strecke (Start > Ziel) und speichert sie.

local _, ns = ...

ns.AddOption(2, "Reisen", {
    key = "flightTimer",
    label = "Flugzeit anzeigen",
    tooltip = "Zeigt während eines Flugs oben mittig Ziel, Restzeit und Fortschritt.\n\nBeim ersten Flug einer Strecke wird die Dauer gemessen, ab dem zweiten gibt es einen Countdown.",
})

---------------------------------------------------------------------------
-- Leiste
---------------------------------------------------------------------------

local bar = CreateFrame("StatusBar", "strayFlightBar", UIParent)
bar:SetSize(220, 12)
bar:SetPoint("TOP", UIParent, "TOP", 0, -110)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
bar:SetMinMaxValues(0, 1)
bar:SetValue(0)
bar:Hide()

local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

local border = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate" or nil)
border:SetPoint("TOPLEFT", -4, 4)
border:SetPoint("BOTTOMRIGHT", 4, -4)
if border.SetBackdrop then
    border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    border:SetBackdropBorderColor(ns.GOLD_DARK[1], ns.GOLD_DARK[2], ns.GOLD_DARK[3])
end

local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("BOTTOM", bar, "TOP", 0, 6)

---------------------------------------------------------------------------
-- Messung
---------------------------------------------------------------------------

local pending   -- Flug gebucht, noch nicht abgehoben
local flight    -- laufender Flug
local interrupted = false

hooksecurefunc("TakeTaxiNode", function(index)
    local source
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then
            source = TaxiNodeName(i)
            break
        end
    end
    pending = { source = source, dest = TaxiNodeName(index), booked = GetTime() }
end)

ns.On("PLAYER_LEAVING_WORLD", function()
    if flight then interrupted = true end
end)

local function UpdateBar()
    if not ns.db.flightTimer then
        bar:Hide()
        return
    end
    local elapsed = GetTime() - flight.start
    local known = flight.key and ns.db.flightTimes[flight.key]
    if known and known > 0 then
        bar:SetValue(math.min(elapsed / known, 1))
        text:SetText(flight.dest .. "  ·  noch " .. ns.FormatTime(known - elapsed))
    else
        bar:SetValue(0)
        text:SetText(flight.dest .. "  ·  " .. ns.FormatTime(elapsed) .. " (wird gemessen)")
    end
    bar:Show()
end

local watcher = CreateFrame("Frame")
local acc = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then return end
    acc = 0
    if not ns.db then return end

    local onTaxi = UnitOnTaxi("player")

    if pending and not flight then
        if onTaxi then
            flight = {
                dest = pending.dest or "Flug",
                key = pending.source and pending.dest and (pending.source .. " > " .. pending.dest),
                start = GetTime(),
            }
            interrupted = false
            pending = nil
        elseif GetTime() - pending.booked > 5 then
            pending = nil -- nicht abgehoben
        end
    end

    if flight then
        if onTaxi then
            UpdateBar()
        else
            local duration = GetTime() - flight.start
            if flight.key and not interrupted and duration > 5 then
                ns.db.flightTimes[flight.key] = math.floor(duration + 0.5)
            end
            flight = nil
            bar:Hide()
        end
    end
end)
