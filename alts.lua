-- stray – Twink-Übersicht: speichert je Charakter Stufe, Gold, EP, erholte EP und Spielzeit
-- und zeigt alle Charaktere in einem eigenen Fenster (mit Summen für Gold und Spielzeit).
-- Erholte EP offline werden geschätzt (Classic-Regel: 5 % einer Stufe je 8 Std. im Ruhebereich,
-- außerhalb ein Viertel davon, höchstens 150 % einer Stufe).

local _, ns = ...
local L = ns.L

ns.defaults.alts = false
ns.defaults.altData = {} -- ["Name-Realm"] = { name, realm, class, level, money, xp, xpMax, rested, resting, maxLevel, time, played, playedAt }

local FONT_BODY = "Fonts\\ARIALN.TTF"
local ROW_H = 18
local MAX_ROWS = 30

local C = {
    bg      = { 0.05, 0.067, 0.09, 0.95 },
    head    = { 0.08, 0.105, 0.14, 1 },
    border  = { 0.169, 0.290, 0.451, 1 },
    accent  = { 0.353, 0.659, 1.0, 1 },
    text    = { 0.89, 0.914, 0.953, 1 },
    textDim = { 0.435, 0.525, 0.651, 1 },
}

-- Spalten: Schlüssel, Überschrift, Breite, Ausrichtung
local COLUMNS = {
    { key = "name",   label = "Name",      width = 150, justify = "LEFT" },
    { key = "level",  label = "Stufe",     width = 44,  justify = "CENTER" },
    { key = "money",  label = "Gold",      width = 118, justify = "RIGHT" },
    { key = "rested", label = "Erholt",    width = 74,  justify = "RIGHT" },
    { key = "played", label = "Spielzeit", width = 92,  justify = "RIGHT" },
}

local PAD = 10
local COL_GAP = 8

---------------------------------------------------------------------------
-- Ereignisse (eigener Rahmen: unbekannte Ereignisse werfen keinen Fehler)
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

---------------------------------------------------------------------------
-- Hilfen
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
    return realm and (name .. "-" .. realm) or name, name, realm
end

local function AtMaxLevel()
    if IsPlayerAtEffectiveMaxLevel then
        local atMax = Call(IsPlayerAtEffectiveMaxLevel)
        if not ns.IsSecret(atMax) and atMax ~= nil then return atMax and true or false end
    end
    local level = Number(Call(UnitLevel, "player"))
    local maxLevel = Number(Call(GetMaxPlayerLevel)) or Number(MAX_PLAYER_LEVEL)
    return (level and maxLevel and level >= maxLevel) and true or false
end

-- 12345 → "12.345"
local function Num(n)
    local s = tostring(math.floor(n + 0.5))
    local count
    repeat
        s, count = s:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
    until count == 0
    return s
end

-- Sekunden → „3 T 4 Std“, „1 Std 24 Min“, „22 Min“
local function FormatPlayed(sec)
    if not sec then return "–" end
    local m = math.floor(math.max(sec, 0) / 60)
    local h = math.floor(m / 60)
    if h >= 24 then
        local d = math.floor(h / 24)
        return L("%d T %d Std", d, h - d * 24)
    elseif h > 0 then
        return L("%d Std %d Min", h, m - h * 60)
    end
    return L("%d Min", m)
end

local function ClassColor(token)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = token and colors and colors[token]
    if c then return c.r or 1, c.g or 1, c.b or 1 end
    return C.text[1], C.text[2], C.text[3]
end

---------------------------------------------------------------------------
-- Daten erfassen
---------------------------------------------------------------------------

-- Zeitpunkt (time()), ab dem die Spielzeit in dieser Sitzung gültig ist
local playedValid = false

local function Data()
    if not ns.db then return nil end
    if type(ns.db.altData) ~= "table" then ns.db.altData = {} end
    return ns.db.altData
end

local function Record()
    if not ns.db or not ns.db.alts then return end
    local data = Data()
    local key, name, realm = PlayerKey()
    if not data or not key then return end
    local entry = data[key]
    if type(entry) ~= "table" then
        entry = {}
        data[key] = entry
    end
    local now = time()
    entry.name = name
    entry.realm = realm
    local _, classToken = Call(UnitClass, "player")
    entry.class = String(classToken) or entry.class
    entry.level = Number(Call(UnitLevel, "player")) or entry.level
    entry.money = Number(Call(GetMoney)) or entry.money
    entry.xp = Number(Call(UnitXP, "player")) or entry.xp
    entry.xpMax = Number(Call(UnitXPMax, "player")) or entry.xpMax
    entry.rested = Number(Call(GetXPExhaustion)) or 0
    local resting = Call(IsResting)
    if not ns.IsSecret(resting) then entry.resting = resting and true or false end
    entry.maxLevel = AtMaxLevel()
    entry.time = now
    -- Spielzeit weiterzählen, solange sie in dieser Sitzung gemessen wurde
    if playedValid and entry.played and entry.playedAt then
        entry.played = entry.played + math.max(now - entry.playedAt, 0)
        entry.playedAt = now
    end
end

local function OnTimePlayed(total)
    total = Number(total)
    if not total or not ns.db or not ns.db.alts then return end
    local data = Data()
    local key = PlayerKey()
    if not data or not key then return end
    if type(data[key]) ~= "table" then Record() end
    local entry = data[key]
    if type(entry) ~= "table" then return end
    entry.played = total
    entry.playedAt = time()
    playedValid = true
    if ns.RefreshAlts then ns.RefreshAlts() end
end

local timePlayedRequested = false

local function RequestPlayed()
    if timePlayedRequested or not RequestTimePlayed then return end
    timePlayedRequested = true
    -- Die Antwort steht als zwei Zeilen im Chat; sauber unterdrücken lässt sie sich ohne Eingriff
    -- in Blizzards Chatrahmen nicht, deshalb nur einmal je Anmeldung fragen.
    C_Timer.After(4, function() pcall(RequestTimePlayed) end)
end

local pendingRecord = false

-- Häufige Ereignisse (Geld, EP) bündeln
local function RecordSoon()
    if pendingRecord then return end
    pendingRecord = true
    C_Timer.After(1, function()
        pendingRecord = false
        Record()
        if ns.RefreshAlts then ns.RefreshAlts() end
    end)
end

SafeOn("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
    if not ns.db or not ns.db.alts then return end
    local data = Data()
    local key = PlayerKey()
    local entry = data and key and data[key]
    if isReloadingUi and type(entry) == "table" and entry.played and entry.playedAt then
        -- Nach /reload war der Charakter die ganze Zeit eingeloggt: Spielzeit läuft weiter
        playedValid = true
    else
        -- Neue Anmeldung: alter Messzeitpunkt gilt nicht mehr (sonst zählte die Offline-Zeit mit)
        if isInitialLogin and type(entry) == "table" then entry.playedAt = nil end
        if isInitialLogin or isReloadingUi then RequestPlayed() end
    end
    Record()
end)

SafeOn("PLAYER_LOGOUT", Record)
SafeOn("PLAYER_MONEY", RecordSoon)
SafeOn("PLAYER_XP_UPDATE", RecordSoon)
SafeOn("PLAYER_LEVEL_UP", RecordSoon)
SafeOn("UPDATE_EXHAUSTION", RecordSoon)
SafeOn("PLAYER_UPDATE_RESTING", RecordSoon)
SafeOn("TIME_PLAYED_MSG", OnTimePlayed)

---------------------------------------------------------------------------
-- Erholte EP (mit Schätzung seit dem Logout)
---------------------------------------------------------------------------

local REST_PER_HOUR = 0.05 / 8 -- Anteil einer Stufe je Stunde im Ruhebereich
local REST_MAX = 1.5

-- Gibt Prozent und „geschätzt“ zurück (nil bei Höchststufe oder fehlenden Daten)
local function RestedPercent(entry, isCurrent)
    if entry.maxLevel then return nil end
    local xpMax = Number(entry.xpMax)
    if not xpMax or xpMax <= 0 then return nil end
    local part = (Number(entry.rested) or 0) / xpMax
    local estimated = false
    if not isCurrent and Number(entry.time) then
        local hours = math.max(time() - entry.time, 0) / 3600
        local rate = entry.resting and REST_PER_HOUR or (REST_PER_HOUR / 4)
        local gain = hours * rate
        if gain > 0.001 then
            estimated = true
            part = part + gain
        end
    end
    part = math.min(part, REST_MAX)
    return part * 100, estimated
end

local function CurrentPlayed(entry, isCurrent)
    local played = Number(entry.played)
    if not played then return nil end
    if isCurrent and playedValid and Number(entry.playedAt) then
        played = played + math.max(time() - entry.playedAt, 0)
    end
    return played
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local function Color(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function Border(frame, c)
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER")
        Color(t, c)
        if i == 1 then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
        elseif i == 2 then t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(1)
        elseif i == 3 then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(1)
        else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(1) end
    end
end

local function Text(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontHighlightSmall)
    pcall(fs.SetFont, fs, FONT_BODY, size, "")
    c = c or C.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetWordWrap(false)
    return fs
end

local tableWidth = 0
for i, col in ipairs(COLUMNS) do
    tableWidth = tableWidth + col.width + (i > 1 and COL_GAP or 0)
end

local frame = CreateFrame("Frame", "strayAltsFrame", UIParent)
frame:SetSize(tableWidth + PAD * 2, 200)
frame:SetFrameStrata("MEDIUM")
frame:SetToplevel(true)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()
if UISpecialFrames then table.insert(UISpecialFrames, "strayAltsFrame") end -- Esc schließt

frame.strayKey = "altsWindow"
frame.strayDefault = { "CENTER", "CENTER", 0, 60 }
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    if ns.db and type(ns.db.positions) == "table" then
        ns.db.positions[self.strayKey] = { point, relPoint, x, y }
    end
end)

do
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Color(bg, C.bg)
    Border(frame, C.border)
end

local title = Text(frame, 14, C.accent)
title:SetPoint("TOPLEFT", PAD, -9)
title:SetText(L["Twink-Übersicht"])

local subtitle = Text(frame, 11, C.textDim)
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
subtitle:SetText(L["Rechtsklick auf eine Zeile entfernt den Eintrag. Ziehen verschiebt das Fenster."])

local close = CreateFrame("Button", nil, frame)
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -5, -5)
close.text = Text(close, 16, C.textDim)
close.text:SetPoint("CENTER")
close.text:SetText("×")
close:SetScript("OnClick", function() frame:Hide() end)
close:SetScript("OnEnter", function(self) self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
close:SetScript("OnLeave", function(self) self.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3]) end)

local TABLE_TOP = -46

local header = CreateFrame("Frame", nil, frame)
header:SetPoint("TOPLEFT", PAD, TABLE_TOP)
header:SetSize(tableWidth, ROW_H + 2)
do
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Color(bg, C.head)
end

-- Spalten-Textfelder in einer Zeile anlegen
local function MakeCells(parent, size, color)
    local cells = {}
    local x = 0
    for i, col in ipairs(COLUMNS) do
        local fs = Text(parent, size, color)
        fs:SetPoint("LEFT", parent, "LEFT", x + 4, 0)
        fs:SetWidth(col.width - 8)
        fs:SetJustifyH(col.justify)
        cells[col.key] = fs
        x = x + col.width + COL_GAP
    end
    return cells
end

local headerCells = MakeCells(header, 12, C.accent)
for _, col in ipairs(COLUMNS) do headerCells[col.key]:SetText(L[col.label]) end

local rows = {}
local emptyText = Text(frame, 12, C.textDim)
emptyText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -8)
emptyText:SetText(L["Noch keine Twinks erfasst. Schalte „Twinks erfassen“ ein und logge deine Charaktere einmal ein."])
emptyText:SetWidth(tableWidth - 8)
emptyText:SetWordWrap(true)
emptyText:SetJustifyH("LEFT")

local moreText = Text(frame, 11, C.textDim)

local footer = CreateFrame("Frame", nil, frame)
footer:SetSize(tableWidth, ROW_H + 4)
do
    local line = footer:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    Color(line, C.border)
end
local footerCells = MakeCells(footer, 12, C.text)

local function AskRemove(key)
    StaticPopup_Show("STRAY_ALT_REMOVE", key, nil, key)
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(tableWidth, ROW_H)
    row:RegisterForClicks("RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
    if i % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.025)
    end
    row.cells = MakeCells(row, 12, C.text)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.key then AskRemove(self.key) end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.key then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.key)
        if self.updated then
            GameTooltip:AddLine(L("Stand: %s", date(L["%d.%m.%Y %H:%M"], self.updated)), C.textDim[1], C.textDim[2], C.textDim[3])
        end
        if self.estimated then
            GameTooltip:AddLine(L("Erholte EP seit dem Logout geschätzt (%s).", self.resting and L["im Ruhebereich"] or L["außerhalb eines Ruhebereichs"]), C.textDim[1], C.textDim[2], C.textDim[3], true)
        end
        GameTooltip:AddLine(L["Rechtsklick: Eintrag entfernen"], ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

local function SortedEntries()
    local list = {}
    local data = Data()
    if not data then return list end
    for key, entry in pairs(data) do
        if type(key) == "string" and type(entry) == "table" then
            table.insert(list, { key = key, entry = entry })
        end
    end
    table.sort(list, function(a, b)
        local la, lb = Number(a.entry.level) or 0, Number(b.entry.level) or 0
        if la ~= lb then return la > lb end
        return a.key < b.key
    end)
    return list
end

local function Refresh()
    if not frame:IsShown() or not ns.db then return end
    if ns.db.alts then Record() end
    local currentKey = PlayerKey()
    local list = SortedEntries()
    local shown = math.min(#list, MAX_ROWS)
    local totalMoney, totalPlayed = 0, 0
    local anyPlayed = false

    for _, item in ipairs(list) do
        local entry = item.entry
        totalMoney = totalMoney + (Number(entry.money) or 0)
        local played = CurrentPlayed(entry, item.key == currentKey)
        if played then
            totalPlayed = totalPlayed + played
            anyPlayed = true
        end
    end

    for i = 1, math.max(shown, #rows) do
        local row = rows[i]
        if i <= shown then
            row = row or CreateRow(i)
            local item = list[i]
            local entry = item.entry
            local isCurrent = item.key == currentKey
            row.key = item.key
            row.updated = Number(entry.time)
            row.resting = entry.resting
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -(i - 1) * ROW_H - 2)

            local cells = row.cells
            cells.name:SetText((entry.name or item.key) .. (isCurrent and " *" or ""))
            cells.name:SetTextColor(ClassColor(entry.class))
            cells.level:SetText(Number(entry.level) and tostring(entry.level) or "–")
            cells.money:SetText(Number(entry.money) and ns.FormatMoney(entry.money) or "–")
            local pct, estimated = RestedPercent(entry, isCurrent)
            row.estimated = estimated
            if pct then
                cells.rested:SetText((estimated and L["ca. "] or "") .. Num(pct) .. " %")
            else
                cells.rested:SetText("–")
            end
            cells.played:SetText(FormatPlayed(CurrentPlayed(entry, isCurrent)))
            row:Show()
        elseif row then
            row.key = nil
            row:Hide()
        end
    end

    emptyText:SetShown(#list == 0)
    local bodyH = (#list == 0) and 36 or (shown * ROW_H + 4)
    if #list > shown then
        moreText:ClearAllPoints()
        moreText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -bodyH)
        moreText:SetText(L("… und %d weitere", #list - shown))
        moreText:Show()
        bodyH = bodyH + ROW_H
    else
        moreText:Hide()
    end

    footer:ClearAllPoints()
    footer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -bodyH - 4)
    footerCells.name:SetText(L("Summe (%d)", #list))
    footerCells.level:SetText("")
    footerCells.money:SetText(ns.FormatMoney(totalMoney))
    footerCells.rested:SetText("")
    footerCells.played:SetText(anyPlayed and FormatPlayed(totalPlayed) or "–")

    frame:SetHeight(-TABLE_TOP + (ROW_H + 2) + bodyH + 4 + (ROW_H + 4) + PAD)
end

ns.RefreshAlts = function()
    if frame:IsShown() then pcall(Refresh) end
end

frame:SetScript("OnShow", function(self)
    ns.RestorePosition(self)
    local ok, err = pcall(Refresh)
    if not ok then geterrorhandler()(err) end
end)

function ns.ToggleAlts()
    if not ns.db then return end
    frame:SetShown(not frame:IsShown())
end

StaticPopupDialogs["STRAY_ALT_REMOVE"] = {
    text = L["Twink „%s“ aus der Übersicht entfernen?"],
    button1 = L["Entfernen"],
    button2 = CANCEL or L["Abbrechen"],
    OnAccept = function(self, data)
        local key = data or self.data
        local altData = Data()
        if type(key) ~= "string" or not altData then return end
        if key == PlayerKey() then
            ns.Print(L["Der eingeloggte Charakter wird gleich wieder erfasst – bitte von einem anderen Charakter aus entfernen."])
        end
        altData[key] = nil
        ns.RefreshAlts()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(3, "Charaktere", {
    key = "alts",
    label = L["Twinks erfassen"],
    tooltip = L["Speichert für jeden Charakter Stufe, Gold, erholte EP und Spielzeit, damit du alle in der Twink-Übersicht siehst.\nBeim Einloggen fragt stray einmal die Spielzeit ab, dabei erscheinen die zwei üblichen Zeilen im Chat."],
    set = function(value)
        ns.db.alts = value
        if value then
            Record()
            RequestPlayed()
        end
        ns.RefreshAlts()
    end,
})

ns.AddOption(3, "Charaktere", {
    key = "altsOpen",
    type = "button",
    label = L["Twink-Übersicht öffnen"],
    buttonText = L["Öffnen"],
    tooltip = L["Zeigt alle erfassten Charaktere mit Stufe, Gold, erholten EP und Spielzeit, darunter die Summen.\nErholte EP von ausgeloggten Charakteren werden geschätzt („ca.“)."],
    onClick = function() ns.ToggleAlts() end,
})
