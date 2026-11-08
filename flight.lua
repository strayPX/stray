-- stray – Flugzeit-Balken (nach dem Vorbild InFlight: Zeiten werden gemessen)
--
-- WoW liefert keine Flugdauer. stray misst deshalb selbst: Beim Flugmeister merkt es sich
-- Start (TaxiNodeName des aktuellen Knotens) und Ziel (hooksecurefunc auf TakeTaxiNode).
-- Abflug ist PLAYER_CONTROL_LOST (oder UnitOnTaxi wird wahr), Landung PLAYER_CONTROL_GAINED
-- (oder UnitOnTaxi wird falsch). Die gemessene Dauer landet in ns.db.flightRouteTimes unter
-- „Start → Ziel“. Eine vorzeitige Landung (TaxiRequestEarlyLanding) wird nicht gespeichert.
--
--   Bekannte Strecke:   Balken mit Restzeit und Ziel.
--   Unbekannte Strecke: Balken „wird gemessen“ mit laufender Zeit.
--
-- Im Tooltip der Flugmeister-Karte steht die bekannte Dauer der Ziele (hooksecurefunc auf
-- TaxiNodeOnButtonEnter bzw. die Kartenpunkte der Flugkarte; nur eine Zeile im GameTooltip).
-- Nach /reload mitten im Flug fehlt der Balken bis zum nächsten Flug: Das Spiel nennt für
-- einen laufenden Flug weder Ziel noch Fortschritt.

local _, ns = ...
local L = ns.L

ns.defaults.flightBar = false
ns.defaults.flightRouteTimes = {} -- ["Start → Ziel"] = Sekunden

local FONT = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local C = {
    bg     = { 0.051, 0.067, 0.090, 0.95 },
    border = { 0.169, 0.290, 0.451, 1 },
    accent = { 0.353, 0.659, 1.000, 1 },
    text   = { 0.890, 0.914, 0.953, 1 },
    dim    = { 0.435, 0.525, 0.651, 1 },
}

local WIDTH, HEIGHT = 260, 20
local ARROW = " → "

local pending -- { from, to, clicked }: Ziel gewählt, Abflug steht aus
local flight  -- { from, to, key, start, known, early }

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function Plain(v)
    if ns.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

local function Times()
    if not ns.db then return nil end
    if type(ns.db.flightRouteTimes) ~= "table" then ns.db.flightRouteTimes = {} end
    return ns.db.flightRouteTimes
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function NodeName(slot)
    if not TaxiNodeName then return nil end
    local ok, name = pcall(TaxiNodeName, slot)
    if ok then return Plain(name) end
end

local function CurrentNode()
    if not (NumTaxiNodes and TaxiNodeGetType) then return nil end
    local ok, num = pcall(NumTaxiNodes)
    if not ok or type(num) ~= "number" then return nil end
    for i = 1, num do
        local okType, kind = pcall(TaxiNodeGetType, i)
        if okType and kind == "CURRENT" then return NodeName(i) end
    end
end

local function OnTaxi()
    if not UnitOnTaxi then return false end
    local on = UnitOnTaxi("player")
    if ns.IsSecret(on) then return false end
    return on and true or false
end

---------------------------------------------------------------------------
-- Balken
---------------------------------------------------------------------------

local bar = CreateFrame("Frame", "strayFlightBar", UIParent)
bar:SetSize(WIDTH, HEIGHT)
bar:SetFrameStrata("MEDIUM")
ns.MakeMovable(bar, "flightbar", { "TOP", "TOP", 0, -30 })
bar:Hide()

do
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = bar:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
    end
end

local fill = CreateFrame("StatusBar", nil, bar)
fill:SetPoint("TOPLEFT", 1, -1)
fill:SetPoint("BOTTOMRIGHT", -1, 1)
fill:SetStatusBarTexture(WHITE)
fill:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3], 0.55)
fill:SetMinMaxValues(0, 1)
fill:SetValue(0)

local dest = fill:CreateFontString(nil, "OVERLAY")
dest:SetFont(FONT, 12, "OUTLINE")
dest:SetTextColor(C.text[1], C.text[2], C.text[3])
dest:SetPoint("LEFT", 6, 0)
dest:SetJustifyH("LEFT")
dest:SetWordWrap(false)

local timeText = fill:CreateFontString(nil, "OVERLAY")
timeText:SetFont(FONT, 12, "OUTLINE")
timeText:SetTextColor(C.text[1], C.text[2], C.text[3])
timeText:SetPoint("RIGHT", -6, 0)
timeText:SetJustifyH("RIGHT")
dest:SetPoint("RIGHT", timeText, "LEFT", -6, 0)

bar:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L["Flugzeit"], 1, 1, 1)
    if flight then
        GameTooltip:AddLine(flight.from .. ARROW .. flight.to, C.text[1], C.text[2], C.text[3], true)
        if flight.known then
            GameTooltip:AddLine(L("Gemessene Dauer: %s", FormatTime(flight.known)), C.accent[1], C.accent[2], C.accent[3])
        else
            GameTooltip:AddLine(L["Diese Strecke wird gerade zum ersten Mal gemessen."], C.dim[1], C.dim[2], C.dim[3], true)
        end
    else
        GameTooltip:AddLine(L["Zeigt Ziel und Restzeit, solange du fliegst. Unbekannte Strecken misst stray beim ersten Flug."], C.text[1], C.text[2], C.text[3], true)
    end
    GameTooltip:AddLine(L["Shift + ziehen zum Verschieben"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

local Land

local throttle = 0
local function OnUpdate(_, elapsed)
    throttle = throttle + elapsed
    if throttle < 0.1 then return end
    throttle = 0
    if not flight then return end
    local now = GetTime() - flight.start
    -- Landung verpasst? (PLAYER_CONTROL_GAINED ist der genaue Zeitpunkt)
    if now > 3 and not OnTaxi() then
        Land()
        return
    end
    if flight.known and not flight.early then
        local left = flight.known - now
        fill:SetValue(math.min(1, now / flight.known))
        timeText:SetText(left > 0 and FormatTime(left) or L["gleich"])
    else
        fill:SetValue(1)
        timeText:SetText(FormatTime(now))
    end
end

local function ShowFlight()
    if not flight then return end
    fill:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3], flight.known and 0.55 or 0.2)
    if flight.known and not flight.early then
        dest:SetText(flight.to)
    elseif flight.early then
        dest:SetText(L("%s (vorzeitige Landung)", flight.to))
    else
        dest:SetText(L("%s – wird gemessen", flight.to))
    end
    throttle = 1
    bar:SetScript("OnUpdate", OnUpdate)
    bar:Show()
end


local function ShowPreview()
    bar:SetScript("OnUpdate", nil)
    fill:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3], 0.55)
    fill:SetValue(0.4)
    dest:SetText(L["Beispiel: Sturmwind"])
    timeText:SetText("1:23")
    bar:Show()
end

local function UpdateBar()
    if not (ns.db and ns.db.flightBar) then
        bar:SetScript("OnUpdate", nil)
        bar:Hide()
        return
    end
    if flight then
        ShowFlight()
    elseif ns.IsConfigOpen() then
        ShowPreview()
    else
        bar:SetScript("OnUpdate", nil)
        bar:Hide()
    end
end

---------------------------------------------------------------------------
-- Messung
---------------------------------------------------------------------------

local function StartFlight()
    if not pending then return end
    local times = Times()
    local key = pending.from .. ARROW .. pending.to
    flight = {
        from = pending.from, to = pending.to, key = key,
        start = GetTime(),
        known = times and tonumber(times[key]) or nil,
    }
    pending = nil
    UpdateBar()
end

Land = function()
    if not flight then return end
    local duration = GetTime() - flight.start
    -- Nur vollständige Flüge speichern; sehr kurze Werte sind Fehlmessungen
    if not flight.early and duration > 5 then
        local times = Times()
        if times then times[flight.key] = math.floor(duration * 10 + 0.5) / 10 end
        if not flight.known then
            ns.Print(L("Flugzeit gemessen: %s – %s", flight.key, FormatTime(duration)))
        end
    end
    flight = nil
    UpdateBar()
end

-- Kurz nach dem Klick auf UnitOnTaxi achten, falls PLAYER_CONTROL_LOST ausbleibt
local watch
local function WatchTakeoff()
    if watch then watch:Cancel() end
    local tries = 0
    watch = C_Timer.NewTicker(0.25, function(self)
        tries = tries + 1
        if not pending or flight then
            self:Cancel(); watch = nil
            return
        end
        if OnTaxi() then
            self:Cancel(); watch = nil
            StartFlight()
        elseif tries > 40 then -- 10 Sekunden: Flug kam nicht zustande
            self:Cancel(); watch = nil
            pending = nil
        end
    end)
end

local function OnTakeTaxiNode(slot)
    if not (ns.db and ns.db.flightBar) or flight then return end
    if ns.IsSecret(slot) then return end
    local from, to = CurrentNode(), NodeName(slot)
    if not (from and to) or from == to then return end
    pending = { from = from, to = to, clicked = GetTime() }
    WatchTakeoff()
end

local function OnEarlyLanding()
    if not flight then return end
    flight.early = true
    ShowFlight()
end

---------------------------------------------------------------------------
-- Tooltip am Flugmeister
---------------------------------------------------------------------------

local function AddTimeLine(slot)
    if not (ns.db and ns.db.flightBar) or ns.IsSecret(slot) or type(slot) ~= "number" then return end
    local from, to = CurrentNode(), NodeName(slot)
    if not (from and to) or from == to then return end
    local times = Times()
    local seconds = times and tonumber(times[from .. ARROW .. to])
    if seconds then
        GameTooltip:AddLine(L("Flugzeit: %s", FormatTime(seconds)), C.accent[1], C.accent[2], C.accent[3])
    else
        GameTooltip:AddLine(L["Flugzeit: noch nicht gemessen"], C.dim[1], C.dim[2], C.dim[3])
    end
    GameTooltip:Show()
end

local taxiHooked, mapHooked = false, false

local function HookFlightMap()
    if mapHooked then return end
    local mixin = FlightMap_FlightPointPinMixin
    if type(mixin) ~= "table" or type(mixin.OnMouseEnter) ~= "function" then return end
    mapHooked = true
    hooksecurefunc(mixin, "OnMouseEnter", function(pin)
        local data = type(pin) == "table" and pin.taxiNodeData
        if type(data) ~= "table" then return end
        -- Nur erreichbare Ziele (nicht der eigene Standort)
        if Enum and Enum.FlightPathState and data.state ~= Enum.FlightPathState.Reachable then return end
        pcall(AddTimeLine, data.slotIndex)
    end)
end

---------------------------------------------------------------------------
-- Einrichten
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_CONTROL_LOST" then
        if pending and not flight and GetTime() - pending.clicked < 10 then StartFlight() end
    elseif event == "PLAYER_CONTROL_GAINED" then
        if flight and not OnTaxi() then Land() end
    end
end)

local hooked = false

local function Apply()
    if ns.db.flightBar then
        if not hooked then
            hooked = true
            if type(TakeTaxiNode) == "function" then hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode) end
            if type(TaxiRequestEarlyLanding) == "function" then hooksecurefunc("TaxiRequestEarlyLanding", OnEarlyLanding) end
        end
        if not taxiHooked and type(TaxiNodeOnButtonEnter) == "function" then
            taxiHooked = true
            hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
                if type(button) ~= "table" or not button.GetID then return end
                local okType, kind = pcall(TaxiNodeGetType, button:GetID())
                if okType and kind == "REACHABLE" then pcall(AddTimeLine, button:GetID()) end
            end)
        end
        HookFlightMap()
        pcall(events.RegisterEvent, events, "PLAYER_CONTROL_LOST")
        pcall(events.RegisterEvent, events, "PLAYER_CONTROL_GAINED")
    else
        events:UnregisterAllEvents()
        pending = nil
        flight = nil
    end
    UpdateBar()
end

ns.RegisterMovable(bar, "Flugzeit", function() UpdateBar() end)
ns.OnConfig(function() UpdateBar() end)

ns.AddOption(3, "Kamera & Karte", {
    key = "flightBar",
    label = L["Flugzeit-Balken"],
    tooltip = L["Beim Flug mit dem Flugmeister zeigt ein Balken oben mittig Ziel und Restzeit. WoW nennt keine Flugdauer, deshalb misst stray jede Strecke beim ersten Flug selbst („wird gemessen“) und weiß sie ab dann. Am Flugmeister steht die bekannte Dauer im Tooltip der Ziele.\n\nMit Shift + linker Maustaste verschiebst du den Balken."],
    set = function(value)
        ns.db.flightBar = value
        Apply()
    end,
})

ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_FlightMap" and ns.db and ns.db.flightBar then HookFlightMap() end
end)

ns.On("PLAYER_LOGIN", function()
    ns.RestorePosition(bar)
    Apply()
end)
