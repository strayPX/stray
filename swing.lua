-- stray – Swing-Timer: je Waffe eine schmale Leiste bis zum nächsten automatischen Schlag
-- Haupthand immer, Nebenhand nur bei Beidhändigkeit, Fernkampf (Jäger, Zauberstab) auf Wunsch.
--
-- WoW Forever hat kein Kampflog für Addons mehr; dafür meldet der Client jeden Schlag selbst:
--   PLAYER_SWING(swingDuration, swingType)               – ein Schlag, Dauer bis zum nächsten
--   C_SwingTimer.EnableRangeCheck(swingType, an)          – Reichweitenmeldungen bestellen
--   PLAYER_SWING_RANGE_UPDATE(swingType, inRange, checks) – Ziel in/außer Reichweite
--   C_SwingTimer.IsTargetWithinSwingRange(swingType)      – nil = keine Prüfung möglich
-- Die Füllung läuft, wenn der Client es kann, ohne Lua pro Bild (StatusBar:SetTimerDuration mit
-- einem Dauerobjekt). Restzeit und Reichweite zieht ein kleiner 0,1-s-Takt nach, der nur läuft,
-- solange die Anzeige sichtbar ist. Ohne Dauerobjekte füllt ein schlankes OnUpdate die Leiste,
-- ebenfalls nur während ein Schlag läuft. Alles ist aus, solange die Option aus ist.

local _, ns = ...

ns.defaults.swingTimer = false
ns.defaults.swingWidth = 200
ns.defaults.swingRanged = false

local IsSecret = ns.IsSecret

local SWING = Enum and Enum.PlayerSwingType
local HAS_API = (type(C_SwingTimer) == "table" and type(SWING) == "table" and SWING.MainHand ~= nil
    and SWING.OffHand ~= nil and SWING.Ranged ~= nil) and true or false
local NO_API = "Diese Spielversion meldet keine automatischen Schläge."

-- Füllung über Dauerobjekte (Midnight-Engine)
local DIR = Enum and Enum.StatusBarTimerDirection
local INTERP = Enum and Enum.StatusBarInterpolation
local HAS_TIMER = (C_DurationUtil and C_DurationUtil.CreateDuration and type(DIR) == "table"
    and type(INTERP) == "table" and DIR.ElapsedTime ~= nil and DIR.RemainingTime ~= nil
    and INTERP.Immediate ~= nil) and true or false

local MIN_W, MAX_W = 100, 400
local ROW_H = 12
local ROW_GAP = 3
local FONT = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local C = {
    bg      = { 0.05, 0.067, 0.09, 0.95 },
    border  = { 0.169, 0.290, 0.451, 1 },
    fill    = { 0.353, 0.659, 1.0, 1 },
    fillOH  = { 0.255, 0.510, 0.820, 1 },
    fillR   = { 0.420, 0.780, 0.450, 1 },
    range   = { 0.85, 0.15, 0.15, 1 },
    text    = { 0.89, 0.914, 0.953, 1 },
    textOut = { 1, 0.35, 0.35, 1 },
}

local function Clamp(v, lo, hi, default)
    v = tonumber(v)
    if not v then return default end
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

local function Enabled()
    return HAS_API and ns.db and ns.db.swingTimer and true or false
end

-- Lesbare Zahl oder nil
local function Num(v)
    if IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- 1.45 → „1,4“
local function Seconds(s)
    return (("%.1f"):format(s):gsub("%.", ","))
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local holder = CreateFrame("Frame", "straySwingTimer", UIParent)
holder:SetSize(200, ROW_H)
holder:SetFrameStrata("MEDIUM")
holder:Hide()
ns.MakeMovable(holder, "swing", { "CENTER", "CENTER", 0, -170 })
-- Klicks in die Welt nicht abfangen; Shift + ziehen nur bei offenem stray-Fenster
holder:EnableMouse(false)
ns.RegisterMovable(holder, "Swing-Timer")

local function Edge(parent, p1, p2, horizontal)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4])
    t:SetPoint(p1)
    t:SetPoint(p2)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
end

-- Reihenfolge von oben nach unten
local ROW_DEFS = {}
if HAS_API then
    ROW_DEFS = {
        { type = SWING.MainHand, tag = "Haupthand", fill = C.fill },
        { type = SWING.OffHand, tag = "Nebenhand", fill = C.fillOH },
        { type = SWING.Ranged, tag = "Fernkampf", fill = C.fillR },
    }
end

local rows = {}    -- in Anzeigereihenfolge
local byType = {}  -- [swingType] = Zeile

local function NewRow(def)
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(ROW_H)
    row.def = def

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    Edge(row, "TOPLEFT", "TOPRIGHT", true)
    Edge(row, "BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge(row, "TOPLEFT", "BOTTOMLEFT", false)
    Edge(row, "TOPRIGHT", "BOTTOMRIGHT", false)

    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar

    -- Texte über der Füllung
    local textFrame = CreateFrame("Frame", nil, row)
    textFrame:SetAllPoints(row)
    textFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    row.tag = textFrame:CreateFontString(nil, "OVERLAY")
    row.tag:SetFont(FONT, 10, "OUTLINE")
    row.tag:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.tag:SetJustifyH("LEFT")
    row.tag:SetWordWrap(false)
    row.tag:SetText(def.tag)
    row.time = textFrame:CreateFontString(nil, "OVERLAY")
    row.time:SetFont(FONT, 10, "OUTLINE")
    row.time:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.time:SetJustifyH("RIGHT")
    row.time:SetWordWrap(false)
    row.time:SetText("")

    -- Dauerobjekt je Zeile, wird bei jedem Schlag neu gesetzt
    if HAS_TIMER and type(bar.SetTimerDuration) == "function" then
        local ok, obj = pcall(C_DurationUtil.CreateDuration)
        if ok and obj then row.durObj = obj end
    end

    row.canSwing = (def.type == SWING.MainHand)
    row.outOfRange = false
    row:Hide()
    rows[#rows + 1] = row
    byType[def.type] = row
    return row
end

for _, def in ipairs(ROW_DEFS) do NewRow(def) end

local function ApplyLook(row)
    local fill = row.outOfRange and C.range or row.def.fill
    row.bar:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4])
    row.bar:SetAlpha(row.outOfRange and 0.55 or 1)
    local t = row.outOfRange and C.textOut or C.text
    row.tag:SetTextColor(t[1], t[2], t[3], 1)
    row.time:SetTextColor(t[1], t[2], t[3], 1)
end

-- Leere Leiste ohne laufenden Schlag
local function IdleRow(row)
    row.endTime, row.duration = nil, nil
    if row.durObj then
        -- Abgelaufene Dauer mit „Restzeit“-Richtung zeichnet eine leere Leiste
        pcall(row.durObj.SetTimeFromStart, row.durObj, GetTime() - 1, 1)
        pcall(row.bar.SetTimerDuration, row.bar, row.durObj, INTERP.Immediate, DIR.RemainingTime)
    end
    row.bar:SetValue(0)
    row.time:SetText("")
end

local function Running(row)
    return row.endTime ~= nil
end

local function AnyRunning()
    for _, row in ipairs(rows) do
        if row:IsShown() and Running(row) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Welche Waffen schlagen zu?
---------------------------------------------------------------------------

-- Nebenhand/Fernkampf nur, wenn der Client eine Angriffsgeschwindigkeit meldet.
-- Versiegelt (z. B. eingeschränkte Werte im Kampf): letzten bekannten Stand behalten.
local function RefreshWeapons()
    if not HAS_API then return end
    local ok, _, oh, ranged = pcall(UnitAttackSpeed, "player")
    if not ok then return end
    local ohRow, rRow = byType[SWING.OffHand], byType[SWING.Ranged]
    if ohRow and not IsSecret(oh) then
        ohRow.canSwing = type(oh) == "number" and oh > 0
    end
    if rRow and not IsSecret(ranged) then
        rRow.canSwing = type(ranged) == "number" and ranged > 0
    end
end

local function RowWanted(row)
    if row.def.type == SWING.Ranged and not (ns.db and ns.db.swingRanged) then return false end
    return row.canSwing and true or false
end

---------------------------------------------------------------------------
-- Aufbau und Sichtbarkeit
---------------------------------------------------------------------------

local inCombat = false
local preview = false

local function Layout()
    local width = Clamp(ns.db and ns.db.swingWidth, MIN_W, MAX_W, 200)
    local y, shown = 0, 0
    for _, row in ipairs(rows) do
        local want = RowWanted(row) or (preview and row.def.type == SWING.MainHand)
        if want then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -y)
            row:Show()
            y = y + ROW_H + ROW_GAP
            shown = shown + 1
        else
            if Running(row) then IdleRow(row) end
            row:Hide()
        end
    end
    holder:SetSize(width, math.max(ROW_H, y - ROW_GAP))
end

local ticker -- unten definiert
local StartTicker, StopTicker

local function UpdateShown()
    local show = Enabled() and (preview or inCombat or AnyRunning())
    holder:SetShown(show and true or false)
    if show then StartTicker() else StopTicker() end
end

-- Beispielinhalt bei offenem stray-Fenster/Bearbeiten-Modus
local function ApplyPreview()
    for _, row in ipairs(rows) do
        if row:IsShown() and not Running(row) then
            if preview then
                local share = (row.def.type == SWING.MainHand) and 0.6 or 0.3
                row.bar:SetValue(share)
                row.time:SetText(row.def.type == SWING.MainHand and "1,4" or "0,9")
            else
                IdleRow(row)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Reichweite
---------------------------------------------------------------------------

local rangeEnabled = {} -- [swingType] = true, solange wir die Prüfung bestellt haben

local function SetRangeCheck(row, on)
    if not (C_SwingTimer.EnableRangeCheck) then return end
    local t = row.def.type
    if (rangeEnabled[t] or false) == on then return end
    if pcall(C_SwingTimer.EnableRangeCheck, t, on) then
        rangeEnabled[t] = on or nil
    end
end

local function SetOutOfRange(row, out)
    out = out and true or false
    if row.outOfRange == out then return end
    row.outOfRange = out
    ApplyLook(row)
end

-- Selbst nachfragen (falls die Meldungen fehlen oder Blizzards Swing-Timer sie abbestellt hat)
local function PollRange(row)
    if not C_SwingTimer.IsTargetWithinSwingRange then return end
    local ok, inRange = pcall(C_SwingTimer.IsTargetWithinSwingRange, row.def.type)
    if not ok or IsSecret(inRange) then return end
    -- nil = keine Prüfung möglich (kein Ziel o. Ä.), nicht als „außer Reichweite“ werten
    SetOutOfRange(row, inRange == false)
end

local function RefreshRange()
    for _, row in ipairs(rows) do
        local want = Enabled() and row:IsShown() and not preview
        SetRangeCheck(row, want and true or false)
        if want then PollRange(row) else SetOutOfRange(row, false) end
    end
end

---------------------------------------------------------------------------
-- Schläge
---------------------------------------------------------------------------

local function UpdateText(row, now)
    local remaining = row.endTime - now
    if remaining <= 0 then
        IdleRow(row)
        return false
    end
    row.time:SetText(Seconds(remaining))
    return true
end

local function StartRow(row, duration)
    local now = GetTime()
    row.duration = duration
    row.endTime = now + duration
    local armed = false
    if row.durObj then
        armed = pcall(row.durObj.SetTimeFromStart, row.durObj, now, duration)
            and pcall(row.bar.SetTimerDuration, row.bar, row.durObj, INTERP.Immediate, DIR.ElapsedTime)
    end
    if not armed then
        row.durObj = nil -- Dauerobjekt klappt nicht: ab jetzt OnUpdate-Füllung
        row.bar:SetValue(0)
    end
    UpdateText(row, now)
end

-- Fallback ohne Dauerobjekte: Füllung je Bild, nur solange ein Schlag läuft
local filler = CreateFrame("Frame")
filler:Hide()
filler:SetScript("OnUpdate", function(self)
    local now, any = GetTime(), false
    for _, row in ipairs(rows) do
        if Running(row) and not row.durObj and row.duration and row.duration > 0 then
            local p = 1 - (row.endTime - now) / row.duration
            if p >= 1 then p = 1 else any = true end
            row.bar:SetValue(p)
        end
    end
    if not any then self:Hide() end
end)

local tickCount = 0

local function Tick()
    local now = GetTime()
    tickCount = tickCount + 1
    for _, row in ipairs(rows) do
        if Running(row) then UpdateText(row, now) end
        -- Etwa alle 0,5 s die Reichweite selbst nachfragen
        if tickCount % 5 == 0 and row:IsShown() and not preview then PollRange(row) end
    end
    if not (preview or inCombat or AnyRunning()) then UpdateShown() end
end

StartTicker = function()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(0.1, function()
        local ok, err = pcall(Tick)
        if not ok then
            -- Ein Fehler soll nicht zehnmal pro Sekunde kommen: Takt anhalten und einmal melden
            if ticker then ticker:Cancel(); ticker = nil end
            geterrorhandler()(err)
        end
    end)
end

StopTicker = function()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function OnSwing(duration, swingType)
    duration, swingType = Num(duration), Num(swingType)
    if not duration or not swingType or duration <= 0 then return end
    local row = byType[swingType]
    if not row then return end
    if swingType == SWING.Ranged and not ns.db.swingRanged then return end
    -- Ein Schlag beweist, dass die Waffe zuschlagen kann (z. B. nach versiegeltem Tempo)
    if not row.canSwing then
        row.canSwing = true
        Layout()
        RefreshRange()
    end
    if not row:IsShown() then return end
    StartRow(row, duration)
    if not row.durObj then filler:Show() end
    UpdateShown()
end

---------------------------------------------------------------------------
-- Ereignisse: nur registriert, solange die Option an ist
---------------------------------------------------------------------------

local EVENTS = {
    "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "WEAPON_SLOT_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
}
local UNIT_EVENTS = { "UNIT_ATTACK_SPEED", "UNIT_INVENTORY_CHANGED" }

local events = CreateFrame("Frame")
local registered = false

local function WeaponsChanged()
    RefreshWeapons()
    Layout()
    ApplyPreview()
    RefreshRange()
    UpdateShown()
end

events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not Enabled() then return end
    if event == "PLAYER_SWING" then
        OnSwing(a1, a2)
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local swingType = Num(a1)
        local row = swingType and byType[swingType]
        if row and not preview and not IsSecret(a2) and not IsSecret(a3) then
            -- checksRange false: keine Prüfung möglich → nicht rot färben
            SetOutOfRange(row, a3 and not a2)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        -- Blizzards eigener Swing-Timer kann die Prüfung abbestellt haben: neu bestellen
        wipe(rangeEnabled)
        RefreshRange()
        UpdateShown()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateShown()
    elseif event == "PLAYER_TARGET_CHANGED" then
        for _, row in ipairs(rows) do
            if row:IsShown() and not preview then PollRange(row) end
        end
    else
        -- PLAYER_ENTERING_WORLD, Waffenwechsel, Angriffstempo
        if (event == "UNIT_ATTACK_SPEED" or event == "UNIT_INVENTORY_CHANGED")
            and (IsSecret(a1) or a1 ~= "player") then
            return
        end
        WeaponsChanged()
    end
end)

local function SetEventsRegistered(want)
    if want == registered then return end
    registered = want
    for _, e in ipairs(EVENTS) do
        if want then
            -- Unbekannte Ereignisse (andere Spielversion) dürfen nicht stören
            pcall(events.RegisterEvent, events, e)
        else
            pcall(events.UnregisterEvent, events, e)
        end
    end
    for _, e in ipairs(UNIT_EVENTS) do
        if want then
            if not pcall(events.RegisterUnitEvent, events, e, "player") then
                pcall(events.RegisterEvent, events, e)
            end
        else
            pcall(events.UnregisterEvent, events, e)
        end
    end
end

---------------------------------------------------------------------------
-- Ein-/Ausschalten
---------------------------------------------------------------------------

local function Apply()
    if not ns.db then return end
    local on = Enabled()
    SetEventsRegistered(on)
    preview = on and ns.IsConfigOpen() or false
    holder:EnableMouse(preview)
    if on then
        inCombat = InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
        if IsSecret(inCombat) then inCombat = InCombatLockdown() end
        inCombat = inCombat and true or false
        for _, row in ipairs(rows) do ApplyLook(row) end
        RefreshWeapons()
        Layout()
        ApplyPreview()
        RefreshRange()
        UpdateShown()
    else
        for _, row in ipairs(rows) do
            SetRangeCheck(row, false)
            SetOutOfRange(row, false)
            if Running(row) then IdleRow(row) end
        end
        filler:Hide()
        StopTicker()
        holder:Hide()
    end
end

ns.On("PLAYER_LOGIN", function()
    ns.db.swingWidth = Clamp(ns.db.swingWidth, MIN_W, MAX_W, 200)
    ns.RestorePosition(holder)
    Apply()
end)

ns.OnConfig(function() Apply() end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

local function IsOn() return Enabled() end

ns.AddOption(2, "Kampfhilfen", {
    key = "swingTimer",
    label = "Swing-Timer",
    tooltip = "Zeigt unter der Bildschirmmitte eine schmale Leiste je Waffe, die bis zu deinem nächsten automatischen Schlag von links nach rechts läuft, mit der Restzeit rechts. Haupthand immer, Nebenhand nur, wenn du mit zwei Waffen kämpfst.\n\nIst dein Ziel außer Reichweite, wird die Leiste rot und dunkler. Außerhalb des Kampfes und ohne laufenden Schlag ist sie unsichtbar.\n\nDie Zeiten meldet das Spiel selbst. Verschieben über „Anzeigen verschieben“ oder bei offenem stray-Fenster mit Shift + linker Maustaste.",
    isEnabled = function() return HAS_API end,
    disabledHint = NO_API,
    set = function(value)
        ns.db.swingTimer = value
        Apply()
    end,
})

ns.AddOption(2, "Kampfhilfen", {
    key = "swingWidth",
    type = "slider",
    label = "Breite Swing-Timer",
    min = MIN_W, max = MAX_W, step = 10,
    tooltip = "Breite der Swing-Timer-Leisten in Pixeln.",
    isEnabled = IsOn,
    disabledHint = HAS_API and "Erst „Swing-Timer“ einschalten (weiter oben)." or NO_API,
    set = function(v)
        ns.db.swingWidth = Clamp(v, MIN_W, MAX_W, 200)
        if Enabled() then Layout() end
    end,
})

ns.AddOption(2, "Kampfhilfen", {
    key = "swingRanged",
    label = "Fernkampf-Leiste",
    tooltip = "Zeigt zusätzlich eine Leiste für Fernkampfschüsse (Automatischer Schuss der Jäger, Zauberstab), sobald eine Fernkampfwaffe angelegt ist.",
    isEnabled = IsOn,
    disabledHint = HAS_API and "Erst „Swing-Timer“ einschalten (weiter oben)." or NO_API,
    set = function(value)
        ns.db.swingRanged = value
        if Enabled() then WeaponsChanged() end
    end,
})
