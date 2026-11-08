-- stray – EP-Tracker: EP pro Stunde (Sitzung und letzte 10 Minuten), Zeit bis zum Levelaufstieg,
-- Zeit auf der aktuellen Stufe, Gesamtspielzeit und Verlauf je Stufe (je Charakter gespeichert).
--
-- Die Anzeige an der Erfahrungsleiste baut hud.lua; dieses Modul liefert nur die Daten:
--   ns.XPTracker.GetLine()        → kurzer Text („bis Level 1h 42m · EP/h 92k“) oder nil
--   ns.XPTracker.AddTooltip(tt)   → hängt die Einzelwerte an einen GameTooltip an
--   ns.XPTracker.OnChange(fn)     → fn() läuft, wenn sich die Zeile ändert (höchstens alle 5 s)
-- Dazu gibt es optional eine kleine verschiebbare Tabelle.
--
-- Spielzeit: Quelle ist TIME_PLAYED_MSG (Gesamt + aktuelle Stufe). stray fragt sie einmal je
-- Anmeldung ab (RequestTimePlayed). Damit die Antwort nicht als Chatzeile erscheint, wird das
-- Ereignis an den Chatfenstern kurz abgemeldet und gleich danach wieder angemeldet – nur ein
-- Methodenaufruf, keine Felder oder Funktionen von Blizzard werden verändert. Hat die Twink-
-- Übersicht (alts.lua) schon gefragt, nutzt der Tracker deren Antwort mit und fragt nicht erneut.
-- Nach /reload läuft die gespeicherte Spielzeit einfach weiter (man war ja eingeloggt).

local _, ns = ...
local L = ns.L

ns.defaults.xpTracker = false
ns.defaults.xpTrackerTable = false
-- ["Name-Realm"] = { level, played, playedAt, levelStart, levels = { [Stufe] = { played, duration, at } }, session = { start, xp, samples } }
ns.defaults.xpHistory = {}

local SECTION = "Erfahrung"
local FONT_BODY = "Fonts\\ARIALN.TTF"
local RECENT_WINDOW = 600   -- „letzte 10 min“ in Sekunden
local MIN_RATE_TIME = 60    -- erst ab einer Minute Messzeit eine Rate angeben
local TICK = 5              -- Takt für Zeile, Tabelle und OnChange
local HISTORY_TOOLTIP = 5   -- so viele letzte Stufen im Tooltip
local REQUEST_DELAY = 6     -- Sekunden nach dem Login (alts.lua fragt nach 4 s)

-- stray-Farben (ns.Colors aus stray.lua; Ersatz mit gleichen Werten, falls die Tabelle fehlt)
local COLORS = ns.Colors or {
    bg = { 0.078, 0.078, 0.098, 0.96 }, card = { 0.094, 0.094, 0.118, 1 }, hover = { 0.122, 0.122, 0.153, 1 },
    line = { 0.149, 0.149, 0.184, 1 }, accent = { 0.545, 0.486, 0.965, 1 }, accentText = { 0.702, 0.659, 0.980, 1 },
    text = { 0.902, 0.902, 0.925, 1 }, textDim = { 0.545, 0.545, 0.600, 1 }, textFaint = { 0.369, 0.369, 0.420, 1 },
}

local C = {
    bg         = COLORS.bg,
    border     = COLORS.line,
    accent     = COLORS.accent,
    accentText = COLORS.accentText,
    text       = COLORS.text,
    textDim    = COLORS.textDim,
}

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function Number(v)
    if ns.IsSecret(v) or type(v) ~= "number" or v ~= v then return nil end
    return v
end

local function String(v)
    if ns.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

local function Enabled()
    return ns.db and ns.db.xpTracker and true or false
end

local function OwnRealm()
    local realm = String(Call(GetNormalizedRealmName))
    if not realm then
        realm = String(Call(GetRealmName))
        if realm then realm = realm:gsub("[%s%-]", "") end
    end
    return (realm and realm ~= "") and realm or nil
end

local function PlayerKey()
    local name = String(Call(UnitName, "player"))
    if not name then return nil end
    local realm = OwnRealm()
    return realm and (name .. "-" .. realm) or name
end

-- Eintrag des eingeloggten Charakters (wird bei Bedarf angelegt)
local function Entry()
    if not ns.db then return nil end
    if type(ns.db.xpHistory) ~= "table" then ns.db.xpHistory = {} end
    local key = PlayerKey()
    if not key then return nil end
    local entry = ns.db.xpHistory[key]
    if type(entry) ~= "table" then
        entry = {}
        ns.db.xpHistory[key] = entry
    end
    if type(entry.levels) ~= "table" then entry.levels = {} end
    return entry
end

local function AtMaxLevel()
    if IsXPUserDisabled then
        local disabled = Call(IsXPUserDisabled)
        if not ns.IsSecret(disabled) and disabled then return true end
    end
    if IsPlayerAtEffectiveMaxLevel then
        local atMax = Call(IsPlayerAtEffectiveMaxLevel)
        if not ns.IsSecret(atMax) and atMax ~= nil then return atMax and true or false end
    end
    local level = Number(Call(UnitLevel, "player"))
    local maxLevel = Number(Call(GetMaxPlayerLevel)) or Number(MAX_PLAYER_LEVEL)
    if level and maxLevel then return level >= maxLevel end
    return false
end

local function Comma(s)
    return (s:gsub("%.", ","))
end

-- 92k, 9,2k, 1,2M
local function ShortNumber(n)
    if not n then return "–" end
    if n >= 1e6 then return Comma(("%.1fM"):format(n / 1e6)) end
    if n >= 1e4 then return ("%dk"):format(math.floor(n / 1000 + 0.5)) end
    if n >= 1000 then return Comma(("%.1fk"):format(n / 1000)) end
    return ("%d"):format(math.floor(n + 0.5))
end

-- 2T 3h, 1h 42m, 42m, <1m
local function Duration(sec)
    if not sec or sec < 0 then return "–" end
    sec = math.floor(sec)
    local days = math.floor(sec / 86400)
    local hours = math.floor((sec % 86400) / 3600)
    local mins = math.floor((sec % 3600) / 60)
    if days > 0 then return L("%dT %dh", days, hours) end
    if hours > 0 then return ("%dh %02dm"):format(hours, mins) end
    if mins > 0 then return ("%dm"):format(mins) end
    return "<1m"
end

---------------------------------------------------------------------------
-- Spielzeit
---------------------------------------------------------------------------

local playedValid = false      -- gespeicherte Spielzeit gilt für diese Sitzung
local playedRequested = false  -- RequestTimePlayed in dieser Sitzung schon gestellt
local playedReceived = false   -- TIME_PLAYED_MSG in dieser Sitzung schon gekommen

local function CurrentPlayed(entry)
    entry = entry or Entry()
    if not playedValid or not entry then return nil end
    local played, at = Number(entry.played), Number(entry.playedAt)
    if not played or not at then return nil end
    return played + math.max(time() - at, 0)
end

local function TimeOnLevel(entry)
    entry = entry or Entry()
    local played = CurrentPlayed(entry)
    local start = entry and Number(entry.levelStart)
    if not played or not start then return nil end
    return math.max(played - start, 0)
end

-- Chatzeile der Antwort vermeiden: Ereignis an den Chatfenstern kurz abmelden
local muted = {}

local function UnmuteChat()
    for i = #muted, 1, -1 do
        local frame = muted[i]
        pcall(frame.RegisterEvent, frame, "TIME_PLAYED_MSG")
        muted[i] = nil
    end
end

local function MuteChat()
    local count = Number(NUM_CHAT_WINDOWS) or 10
    for i = 1, count do
        local frame = _G["ChatFrame" .. i]
        if type(frame) == "table" and frame.IsEventRegistered and frame.UnregisterEvent then
            local ok, registered = pcall(frame.IsEventRegistered, frame, "TIME_PLAYED_MSG")
            if ok and registered == true and pcall(frame.UnregisterEvent, frame, "TIME_PLAYED_MSG") then
                muted[#muted + 1] = frame
            end
        end
    end
    -- Sicherheitsnetz, falls keine Antwort kommt: spätestens nach 10 s wieder normal
    C_Timer.After(10, UnmuteChat)
end

local function RequestPlayed()
    if playedRequested or playedReceived or not RequestTimePlayed then return end
    playedRequested = true
    MuteChat()
    if not pcall(RequestTimePlayed) then UnmuteChat() end
end

local function RequestPlayedSoon()
    if playedRequested or playedReceived then return end
    C_Timer.After(REQUEST_DELAY, function()
        if Enabled() then RequestPlayed() end
    end)
end

---------------------------------------------------------------------------
-- EP messen
---------------------------------------------------------------------------

local last = { xp = nil, max = nil, level = nil }

local function Session(entry)
    if type(entry.session) ~= "table" then
        entry.session = { start = time(), xp = 0, samples = {} }
    end
    local s = entry.session
    if not Number(s.start) then s.start = time() end
    if not Number(s.xp) then s.xp = 0 end
    if type(s.samples) ~= "table" then s.samples = {} end
    return s
end

local function NewSession(entry)
    entry.session = { start = time(), xp = 0, samples = {} }
end

local function PruneSamples(s, now)
    local samples = s.samples
    local keep = 1
    for i = 1, #samples do
        local sample = samples[i]
        if type(sample) == "table" and Number(sample[1]) and now - sample[1] <= RECENT_WINDOW then
            samples[keep] = sample
            keep = keep + 1
        end
    end
    for i = #samples, keep, -1 do samples[i] = nil end
end

local function ReadXP()
    local cur = Number(Call(UnitXP, "player"))
    local max = Number(Call(UnitXPMax, "player"))
    local level = Number(Call(UnitLevel, "player"))
    return cur, max, level
end

local function RememberXP()
    last.xp, last.max, last.level = ReadXP()
end

local function OnXPUpdate()
    if not Enabled() then return end
    local entry = Entry()
    if not entry then return end
    local cur, max, level = ReadXP()
    if not cur or not max or not level then return end
    local gain = 0
    if last.xp and last.max and last.level then
        if level > last.level or (level == last.level and cur < last.xp) then
            -- Levelaufstieg (UnitLevel kann einen Moment hinterherhinken)
            gain = (last.max - last.xp) + cur
            if level == last.level then level = level + 1 end
        elseif level == last.level then
            gain = cur - last.xp
        end
        -- Unplausible Sprünge (z. B. Stufe zurückgesetzt) nicht zählen
        if gain < 0 or gain > last.max * 2 then gain = 0 end
    end
    last.xp, last.max, last.level = cur, max, level
    if gain > 0 then
        local s = Session(entry)
        local now = time()
        s.xp = s.xp + gain
        s.samples[#s.samples + 1] = { now, gain }
        PruneSamples(s, now)
    end
end

-- EP/h der Sitzung und der letzten 10 Minuten (nil, solange zu wenig gemessen ist)
local function Rates(entry)
    if not entry or type(entry.session) ~= "table" then return nil, nil end
    local s = Session(entry)
    local now = time()
    local elapsed = now - s.start
    if elapsed < MIN_RATE_TIME then return nil, nil end
    local sessionRate = s.xp / elapsed * 3600
    PruneSamples(s, now)
    local recentXP = 0
    for _, sample in ipairs(s.samples) do recentXP = recentXP + (Number(sample[2]) or 0) end
    local window = math.min(RECENT_WINDOW, elapsed)
    local recentRate = recentXP / window * 3600
    return sessionRate, recentRate
end

local function TimeToLevel(entry)
    local sessionRate, recentRate = Rates(entry)
    local rate = (recentRate and recentRate > 0) and recentRate or sessionRate
    if not rate or rate <= 0 then return nil, rate end
    local cur, max = ReadXP()
    if not cur or not max or max <= 0 then return nil, rate end
    return math.max(max - cur, 0) / rate * 3600, rate
end

---------------------------------------------------------------------------
-- Stufen-Verlauf
---------------------------------------------------------------------------

local function OnLevelUp(newLevel)
    if not Enabled() then return end
    local entry = Entry()
    if not entry then return end
    newLevel = Number(newLevel) or ((Number(entry.level) or 0) + 1)
    local played = CurrentPlayed(entry)
    local record = { at = time(), played = played }
    -- Dauer nur, wenn der Beginn der vorigen Stufe bekannt ist (sonst lieber leer lassen)
    if played and Number(entry.levelStart) and Number(entry.level) == newLevel - 1 then
        record.duration = math.max(played - entry.levelStart, 0)
    end
    entry.levels[newLevel] = record
    entry.level = newLevel
    entry.levelStart = played -- nil, solange die Spielzeit unbekannt ist
end

local function OnTimePlayed(total, thisLevel)
    total, thisLevel = Number(total), Number(thisLevel)
    C_Timer.After(0, UnmuteChat)
    if not total or not Enabled() then return end
    playedReceived = true
    local entry = Entry()
    if not entry then return end
    entry.played = total
    entry.playedAt = time()
    if thisLevel then entry.levelStart = total - thisLevel end
    entry.level = Number(Call(UnitLevel, "player")) or entry.level
    playedValid = true
end

---------------------------------------------------------------------------
-- Zeile und Benachrichtigung
---------------------------------------------------------------------------

local callbacks = {}
local lastLine = nil

local function BuildLine()
    if not Enabled() or AtMaxLevel() then return nil end
    local entry = Entry()
    if not entry then return nil end
    local seconds, rate = TimeToLevel(entry)
    if not rate or rate <= 0 then return nil end
    return L("bis Level %s · EP/h %s", Duration(seconds), ShortNumber(rate))
end

local function Notify(force)
    local ok, line = pcall(BuildLine)
    if not ok then line = nil end
    if not force and line == lastLine then return end
    lastLine = line
    for _, fn in ipairs(callbacks) do
        local okCall, err = pcall(fn, line)
        if not okCall then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Öffentliche Schnittstelle
---------------------------------------------------------------------------

ns.XPTracker = {}

function ns.XPTracker.GetLine()
    local ok, line = pcall(BuildLine)
    return ok and line or nil
end

function ns.XPTracker.OnChange(fn)
    if type(fn) == "function" then callbacks[#callbacks + 1] = fn end
end

local function SortedLevels(entry)
    local list = {}
    for level, record in pairs(entry.levels or {}) do
        if Number(level) and type(record) == "table" then list[#list + 1] = level end
    end
    table.sort(list, function(a, b) return a > b end)
    return list
end

local function FillTooltip(tt)
    local entry = Entry()
    if not entry then return end
    local acc, txt, dim = C.accentText, C.text, C.textDim
    local function Row(label, value)
        tt:AddDoubleLine(label, value, dim[1], dim[2], dim[3], txt[1], txt[2], txt[3])
    end
    tt:AddLine(" ")
    tt:AddLine(L["EP-Tracker"], acc[1], acc[2], acc[3])
    if not AtMaxLevel() then
        local sessionRate, recentRate = Rates(entry)
        local seconds = TimeToLevel(entry)
        Row(L["EP/h (Sitzung)"], sessionRate and ShortNumber(sessionRate) or "–")
        Row(L["EP/h (letzte 10 min)"], recentRate and ShortNumber(recentRate) or "–")
        Row(L["Bis Levelaufstieg"], seconds and Duration(seconds) or "–")
    end
    Row(L["Zeit auf dieser Stufe"], Duration(TimeOnLevel(entry)))
    Row(L["Spielzeit gesamt"], Duration(CurrentPlayed(entry)))
    local levels = SortedLevels(entry)
    if #levels > 0 then
        tt:AddLine(L["Letzte Stufen"], acc[1], acc[2], acc[3])
        for i = 1, math.min(#levels, HISTORY_TOOLTIP) do
            local level = levels[i]
            local record = entry.levels[level]
            local value = Duration(Number(record.duration))
            if Number(record.played) then value = value .. L("  (gesamt %s)", Duration(record.played)) end
            Row(L("Stufe %d", level), value)
        end
    end
end

function ns.XPTracker.AddTooltip(tt)
    if not Enabled() or type(tt) ~= "table" or not tt.AddLine then return end
    local ok, err = pcall(FillTooltip, tt)
    if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Kleine Tabelle
---------------------------------------------------------------------------

-- label = deutscher Schlüssel, übersetzt wird beim Anzeigen
local ROWS = {
    { key = "session", label = "EP/h Sitzung" },
    { key = "recent",  label = "EP/h 10 min" },
    { key = "toLevel", label = "Bis Level" },
    { key = "onLevel", label = "Auf Stufe" },
    { key = "played",  label = "Spielzeit" },
}
local ROW_H = 15
local WIDTH = 170

local panel = CreateFrame("Frame", "strayXPTracker", UIParent)
panel:SetSize(WIDTH, 22 + #ROWS * ROW_H)
panel:SetFrameStrata("MEDIUM")
panel:Hide()

do
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    local lines = {}
    for i = 1, 4 do
        local t = panel:CreateTexture(nil, "BORDER")
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4])
        lines[i] = t
    end
    lines[1]:SetPoint("TOPLEFT"); lines[1]:SetPoint("TOPRIGHT"); lines[1]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT"); lines[2]:SetHeight(1)
    lines[3]:SetPoint("TOPLEFT"); lines[3]:SetPoint("BOTTOMLEFT"); lines[3]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT"); lines[4]:SetPoint("BOTTOMRIGHT"); lines[4]:SetWidth(1)
    -- 2-px-lila Kante oben (wie die Bedrohungsliste)
    local top = panel:CreateTexture(nil, "ARTWORK")
    top:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
end

local function MakeText(size, r, g, b)
    local fs = panel:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontHighlightSmall)
    pcall(fs.SetFont, fs, FONT_BODY, size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetTextColor(r, g, b)
    return fs
end

local title = MakeText(12, C.accentText[1], C.accentText[2], C.accentText[3])
title:SetPoint("TOPLEFT", 6, -5)
title:SetText(L["EP-Tracker"])

local cells = {}
local labels = {}
for i, row in ipairs(ROWS) do
    local y = -20 - (i - 1) * ROW_H
    local label = MakeText(11, C.textDim[1], C.textDim[2], C.textDim[3])
    label:SetPoint("TOPLEFT", 6, y)
    label:SetText(L[row.label])
    labels[row.key] = label
    local value = MakeText(11, C.text[1], C.text[2], C.text[3])
    value:SetPoint("TOPRIGHT", -6, y)
    value:SetJustifyH("RIGHT")
    cells[row.key] = value
end

ns.MakeMovable(panel, "xptracker", { "TOP", "TOP", 0, -60 })

panel:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["EP-Tracker"], C.accentText[1], C.accentText[2], C.accentText[3])
    GameTooltip:AddLine(L["Shift + Ziehen verschiebt die Tabelle."], C.textDim[1], C.textDim[2], C.textDim[3])
    ns.XPTracker.AddTooltip(GameTooltip)
    GameTooltip:Show()
end)
panel:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

-- „2T 7h“ ist ein deutscher Schlüssel, übersetzt wird beim Anzeigen
local SAMPLE = { session = "84k", recent = "92k", toLevel = "1h 42m", onLevel = "38m", played = "2T 7h" }

local function UpdatePanel()
    if not Enabled() or not ns.db.xpTrackerTable then panel:Hide() return end
    title:SetText(L["EP-Tracker"]) -- zur Anzeigezeit, damit die gewählte Sprache greift
    local entry = Entry()
    local values = {}
    local maxed = AtMaxLevel()
    if entry then
        local sessionRate, recentRate = Rates(entry)
        values.session = sessionRate and ShortNumber(sessionRate) or nil
        values.recent = recentRate and ShortNumber(recentRate) or nil
        local seconds = TimeToLevel(entry)
        values.toLevel = seconds and Duration(seconds) or nil
        values.onLevel = TimeOnLevel(entry) and Duration(TimeOnLevel(entry)) or nil
        values.played = CurrentPlayed(entry) and Duration(CurrentPlayed(entry)) or nil
    end
    if maxed then values.session, values.recent, values.toLevel = L["Höchststufe"], "–", "–" end
    -- Bei offenem stray-Fenster fehlende Werte mit Beispielen füllen, damit man die Größe sieht
    local preview = ns.IsConfigOpen()
    for key, cell in pairs(cells) do
        local v = values[key]
        if not v and preview then v = SAMPLE[key] and L[SAMPLE[key]] end
        cell:SetText(v or "–")
    end
    for _, row in ipairs(ROWS) do labels[row.key]:SetText(L[row.label]) end
    title:SetText(preview and L["EP-Tracker · Beispiel"] or L["EP-Tracker"])
    panel:Show()
end

ns.RegisterMovable(panel, "EP-Tracker", function() pcall(UpdatePanel) end)
ns.OnConfig(function() pcall(UpdatePanel) end)

---------------------------------------------------------------------------
-- Ereignisse und Takt
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

local function SafeOn(event, fn)
    if not eventHandlers[event] then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return end
        eventHandlers[event] = {}
    end
    table.insert(eventHandlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(eventHandlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

local ticker
local sessionFresh = false -- Sitzung gehört zu dieser Anmeldung (oder lief über /reload weiter)

local function Tick()
    pcall(UpdatePanel)
    Notify(false)
end

local function Apply()
    if not ns.db then return end
    if Enabled() then
        local entry = Entry()
        if entry and (not sessionFresh or type(entry.session) ~= "table") then NewSession(entry) end
        sessionFresh = true
        RememberXP()
        if not playedValid then RequestPlayedSoon() end
        if not ticker then ticker = C_Timer.NewTicker(TICK, Tick) end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
    pcall(UpdatePanel)
    Notify(true)
end

local loggedIn = false

SafeOn("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
    if loggedIn then return end -- nur das erste Mal (Ladebildschirme ignorieren)
    loggedIn = true
    ns.RestorePosition(panel)
    local entry = Enabled() and Entry()
    if entry then
        if isReloadingUi and Number(entry.played) and Number(entry.playedAt) then
            -- /reload: man war die ganze Zeit eingeloggt, Spielzeit und Sitzung laufen weiter
            playedValid = true
            if type(entry.session) == "table" then sessionFresh = true end
        else
            -- Neue Anmeldung: alte Messwerte und Sitzung gelten nicht mehr
            entry.playedAt = nil
            NewSession(entry)
            sessionFresh = true
        end
        local level = Number(Call(UnitLevel, "player"))
        if level and Number(entry.level) and level ~= entry.level then entry.levelStart = nil end
        if level then entry.level = level end
    end
    Apply()
end)

SafeOn("TIME_PLAYED_MSG", OnTimePlayed)
SafeOn("PLAYER_XP_UPDATE", function()
    OnXPUpdate()
end)
SafeOn("PLAYER_LEVEL_UP", function(newLevel)
    OnLevelUp(newLevel)
    C_Timer.After(1, function() if Enabled() then Tick() end end)
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(3, SECTION, {
    key = "xpTracker",
    label = L["EP-Tracker"],
    tooltip = L["Zeigt an der Erfahrungsleiste, wie lange es noch bis zum Levelaufstieg dauert und "
        .. "wie viele EP pro Stunde du bekommst.\n\n"
        .. "Im Tooltip der Leiste: EP/h der Sitzung und der letzten 10 Minuten, Zeit auf der Stufe, "
        .. "Gesamtspielzeit und die letzten Stufen mit ihrer Dauer. Der Verlauf wird je Charakter gespeichert.\n\n"
        .. "Beim Einloggen fragt stray einmal die Spielzeit ab (wie /played), ohne Chatzeile. "
        .. "Auf Höchststufe bleibt die Zeile an der Leiste leer."],
    keywords = { "xp", "ep", "exp", "experience", "erfahrung", "level", "stufe", "levelup",
        "xp/h", "ep/h", "tracker", "playtime", "played", "spielzeit" },
    set = function(value)
        ns.db.xpTracker = value
        Apply()
    end,
})

ns.AddOption(3, SECTION, {
    key = "xpTrackerTable",
    label = L["EP-Tracker als Tabelle"],
    tooltip = L["Kleine Tabelle mit EP/h, Zeit bis zum Levelaufstieg, Zeit auf der Stufe und Spielzeit.\n\n"
        .. "Shift + Ziehen verschiebt sie, ebenso der Bearbeitungsmodus. Braucht den EP-Tracker."],
    keywords = { "xp", "ep", "exp", "level", "stufe", "playtime", "spielzeit", "tabelle", "table", "tracker" },
    isEnabled = function() return ns.db and ns.db.xpTracker and true or false end,
    set = function(value)
        ns.db.xpTrackerTable = value
        pcall(UpdatePanel)
    end,
})
