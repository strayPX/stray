-- stray – Questtracker: eigene Questliste am rechten Bildschirmrand
-- Daten nur aus Blizzards Questlog (C_QuestLog.*), keine Fremd-Datenbank.
-- Fest am rechten Rand verankert (wächst nach links und unten), Inhalt rechtsbündig.
-- Kopf „Quests  20 / 40“ (Klick klappt alles ein), Gebiete einzeln einklappbar,
-- Stufe + Name in Schwierigkeitsfarbe, Ziele mit Zählern rechts, „Bereit zur Abgabe“,
-- „+ n weitere Quests“, Größen-Griff unten links.
--
-- Questgegenstände: sichere Gegenstandsknöpfe (SecureActionButtonTemplate, type item).
-- Sie hängen direkt an UIParent (nie an der Liste, sonst würde die Liste geschützt) und werden
-- nur außerhalb des Kampfes angelegt, gesetzt oder versteckt; im Kampf vorgemerkt.
--
-- Blizzards Questverfolgung (ObjectiveTrackerFrame) wird bei Bedarf nur per Hide() außerhalb
-- des Kampfes ausgeblendet; im Kampf nur Alpha 0, Hide() danach. Kein Feld auf Blizzard-Frames,
-- nur HookScript. Questie: nur lesen (Frame sichtbar?) und die offizielle Questie.API nutzen.

local _, ns = ...
local L = ns.L

ns.defaults.questTracker = false
ns.defaults.questTrackerHideBlizzard = true
ns.defaults.questTrackerGroup = true
ns.defaults.questTrackerSort = "zone"     -- "zone" | "level" | "progress"
ns.defaults.questTrackerAlpha = 28        -- Deckkraft des Hintergrunds in %
ns.defaults.questTrackerWidth = 250
ns.defaults.questTrackerHeight = 420      -- größte Höhe (Griff unten links)
ns.defaults.questTrackerTop = 240         -- Abstand vom oberen Rand
ns.defaults.questTrackerCollapsed = false
ns.defaults.questTrackerShowAll = false
ns.defaults.questTrackerRecipes = true    -- Abschnitt „Berufsreagenzien“ unter den Quests
ns.defaults.questTrackerRecipesCollapsed = false
ns.defaults.questTrackerZones = {}        -- [Gebietsname] = true (eingeklappt)

local SECTION = "Questtracker"
local KEY = "questTracker"
local FONT = "Fonts\\ARIALN.TTF"
local COLORS = ns.Colors

-- Maße (in Einheiten der Liste)
local S = {
    pad = 10, header = 26, radius = 6, item = 22, gap = 6, counterGap = 8,
    zoneH = 16, moreH = 16, bottom = 8,
    minW = 180, maxW = 420, minH = 120, maxH = 1000,
}

local GREEN = { 0.40, 0.85, 0.40 }
local RED = { 1, 0.32, 0.32 }
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local U = {}

local function Pack(ok, ...)
    if ok then return ... end
end

-- Sicherer Aufruf: nil bei fehlender Funktion oder Fehler
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return Pack(pcall(fn, ...))
end

function U.Num(v)
    if ns.IsSecret(v) or type(v) ~= "number" or v ~= v then return nil end
    return v
end

function U.Str(v)
    if ns.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

function U.Bool(v)
    if ns.IsSecret(v) then return nil end
    return v and true or false
end

function U.Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Großbuchstaben inkl. Umlaute (UTF-8, Latin-1-Zusatz à–þ → À–Þ, ß bleibt)
function U.Upper(s)
    s = string.upper(s)
    return (s:gsub("\195([\160-\190])", function(c)
        local b = c:byte()
        if b == 183 then return "\195" .. c end
        return "\195" .. string.char(b - 32)
    end))
end

function U.Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Enabled()
    return ns.db and ns.db.questTracker and true or false
end

---------------------------------------------------------------------------
-- Questie: nur erkennen und lesen, nie etwas ändern
---------------------------------------------------------------------------

function U.QuestieLoaded()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return Call(isLoaded, "Questie") and true or false
end

-- Ist Questies eigene Questliste gerade sichtbar? nil = nicht feststellbar
function U.QuestieTrackerShown()
    local f = _G.Questie_BaseFrame
    if type(f) ~= "table" or type(f.IsShown) ~= "function" then return nil end
    return U.Bool(Call(f.IsShown, f))
end

-- Konflikt-Eintrag (Vertrag mit conflicts.lua): Texte sind L-Schlüssel, übersetzt wird dort
do
    ns.Conflicts = ns.Conflicts or {}
    local list = ns.Conflicts[KEY]
    if type(list) ~= "table" then
        list = {}
        ns.Conflicts[KEY] = list
    end
    local have = false
    for _, e in ipairs(list) do
        if type(e) == "table" and e.addon == "Questie" then have = true end
    end
    if not have then
        table.insert(list, {
            addon = "Questie",
            feature = "Questliste (Tracker)",
            hint = "Questie hat eine eigene Questliste. Schalte sie in Questie unter „Tracker“ aus – Karte und Minimap von Questie bleiben.",
            check = function()
                if not U.QuestieLoaded() then return false end
                return U.QuestieTrackerShown()
            end,
        })
    end
end

---------------------------------------------------------------------------
-- Questlog lesen
---------------------------------------------------------------------------

-- Merkt sich Gebiet und Reihenfolge je Quest. Quests unter zugeklappten Überschriften liefert
-- das Questlog nicht – sie bleiben aus dem Speicher sichtbar, bis sie weg sind.
local cache = {} -- [questID] = { zone = "…", order = n, zoneOrder = n }

function U.StillOnQuest(questID)
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local on = Call(C_QuestLog.IsOnQuest, questID)
        if not ns.IsSecret(on) and on ~= nil then return on and true or false end
    end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        return U.Num(Call(C_QuestLog.GetLogIndexForQuestID, questID)) ~= nil
    end
    return true
end

function U.LogEntry(i)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = Call(C_QuestLog.GetInfo, i)
        if type(info) ~= "table" then return end
        return U.Str(info.title), U.Bool(info.isHeader), U.Num(info.questID), U.Bool(info.isHidden)
    end
    if GetQuestLogTitle then
        local title, _, _, isHeader, _, _, _, questID = Call(GetQuestLogTitle, i)
        return U.Str(title), U.Bool(isHeader), U.Num(questID), false
    end
end

function U.ScanLog()
    local entries, quests = 0, nil
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        entries, quests = Call(C_QuestLog.GetNumQuestLogEntries)
    elseif GetNumQuestLogEntries then
        entries, quests = Call(GetNumQuestLogEntries)
    end
    entries = U.Num(entries) or 0
    local zone, zoneOrder, seen = "", 0, {}
    for i = 1, entries do
        local title, isHeader, questID, isHidden = U.LogEntry(i)
        if isHeader then
            zone = title or ""
            zoneOrder = zoneOrder + 1
        elseif questID and not isHidden then
            cache[questID] = { zone = zone, order = i, zoneOrder = zoneOrder }
            seen[questID] = true
        end
    end
    for questID in pairs(cache) do
        if not seen[questID] and not U.StillOnQuest(questID) then cache[questID] = nil end
    end
    return U.Num(quests)
end

-- Ziel zerlegen: Name, Zähler („4 / 12“) oder nil, erfüllt?
function U.Objective(o)
    local text = U.Str(o.text) or ""
    local have, need = U.Num(o.numFulfilled), U.Num(o.numRequired)
    local name, a, b = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
    if not name then a, b, name = text:match("^(%d+)%s*/%s*(%d+)%s+(.+)$") end
    local counter
    if name then
        name = U.Trim(name)
        counter = (have or tonumber(a) or 0) .. " / " .. (need or tonumber(b) or 0)
    else
        name = text
        if need and need > 1 then counter = (have or 0) .. " / " .. need end
    end
    local done = U.Bool(o.finished) or false
    local frac = done and 1 or ((have and need and need > 0) and math.min(1, have / need) or 0)
    return { text = name, counter = counter, done = done, frac = frac }
end

-- Schwierigkeitsfarbe wie Blizzard auf Forever (GetDifficultyColor + Inhaltsschwierigkeit),
-- sonst GetQuestDifficultyColor, sonst nach Stufenabstand
function U.LevelColor(questID, level)
    if questID and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
        local d = Call(C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID)
        if not ns.IsSecret(d) and d ~= nil then
            local c = Call(GetDifficultyColor, d)
            if type(c) == "table" and U.Num(c.r) then return c.r, c.g, c.b end
        end
    end
    if level and GetQuestDifficultyColor then
        local c = Call(GetQuestDifficultyColor, level)
        if type(c) == "table" and U.Num(c.r) then return c.r, c.g, c.b end
    end
    local diff = (level or 0) - (U.Num(UnitLevel("player")) or 1)
    if diff >= 5 then return 1, 0.1, 0.1 end
    if diff >= 3 then return 1, 0.5, 0.25 end
    if diff >= -2 then return 1, 0.82, 0 end
    if diff >= -8 then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end

---------------------------------------------------------------------------
-- Questgegenstände: Blizzards Sondergegenstand, sonst Ersatz aus den Taschen
---------------------------------------------------------------------------

local bagItems, bagDirty = {}, true -- benutzbare Gegenstände: { itemID, name, bag, slot, questID }

function U.ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return U.Num(Call(C_Item.GetItemCount, itemID, false, true)) or 0 end
    return U.Num(Call(GetItemCount, itemID, false, true)) or 0
end

function U.ScanBags()
    bagDirty = false
    wipe(bagItems)
    if not C_Container or not C_Container.GetContainerNumSlots then return end
    local numBags = (Constants and Constants.InventoryConstants and U.Num(Constants.InventoryConstants.NumBagSlots))
        or NUM_BAG_SLOTS or 4
    local getSpell = C_Item and C_Item.GetItemSpell
    for bag = 0, numBags do
        local slots = U.Num(Call(C_Container.GetContainerNumSlots, bag)) or 0
        for slot = 1, slots do
            local info = Call(C_Container.GetContainerItemInfo, bag, slot)
            local itemID = type(info) == "table" and U.Num(info.itemID)
            if itemID and Call(getSpell, itemID) then
                local name = U.Str(info.itemName) or (C_Item and U.Str(Call(C_Item.GetItemNameByID, itemID)))
                local qi = Call(C_Container.GetContainerItemQuestInfo, bag, slot)
                bagItems[#bagItems + 1] = {
                    itemID = itemID, bag = bag, slot = slot,
                    name = name and name:lower(),
                    questID = type(qi) == "table" and U.Num(qi.questID) or nil,
                }
            end
        end
    end
end

-- Gegenstand für eine Quest: { itemID, logIndex (Sondergegenstand) oder bag/slot, tex }
function U.QuestItem(q)
    local logIndex = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
        and U.Num(Call(C_QuestLog.GetLogIndexForQuestID, q.id))
    if logIndex and GetQuestLogSpecialItemInfo then
        local link, tex, _, showDone = Call(GetQuestLogSpecialItemInfo, logIndex)
        link = U.Str(link)
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if itemID and (not q.complete or U.Bool(showDone)) and U.ItemCount(itemID) > 0 then
            return { itemID = itemID, logIndex = logIndex, tex = tex }
        end
    end
    if q.complete then return nil end
    if bagDirty then U.ScanBags() end
    for _, it in ipairs(bagItems) do
        if it.questID == q.id then return { itemID = it.itemID, bag = it.bag, slot = it.slot } end
    end
    local title = q.title:lower()
    for _, it in ipairs(bagItems) do
        local name = it.name
        if name and #name >= 4 then
            if title:find(name, 1, true) then return { itemID = it.itemID, bag = it.bag, slot = it.slot } end
            for _, o in ipairs(q.objectives) do
                if o.text:lower():find(name, 1, true) then
                    return { itemID = it.itemID, bag = it.bag, slot = it.slot }
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Daten zusammenstellen und sortieren
---------------------------------------------------------------------------

function U.ReadQuest(questID, c)
    local title = C_QuestLog.GetTitleForQuestID and U.Str(Call(C_QuestLog.GetTitleForQuestID, questID))
    if not title then return nil end
    local level = (C_QuestLog.GetQuestDifficultyLevel and U.Num(Call(C_QuestLog.GetQuestDifficultyLevel, questID))) or 0
    local q = {
        id = questID, title = title, level = level, zone = c.zone, order = c.order, zoneOrder = c.zoneOrder,
        elite = C_QuestLog.IsEliteQuest and U.Bool(Call(C_QuestLog.IsEliteQuest, questID)) or false,
        complete = (C_QuestLog.IsComplete and U.Bool(Call(C_QuestLog.IsComplete, questID)))
            or (C_QuestLog.ReadyForTurnIn and U.Bool(Call(C_QuestLog.ReadyForTurnIn, questID))) or false,
        failed = C_QuestLog.IsFailed and U.Bool(Call(C_QuestLog.IsFailed, questID)) or false,
        objectives = {},
    }
    local list = C_QuestLog.GetQuestObjectives and Call(C_QuestLog.GetQuestObjectives, questID)
    local sum = 0
    if type(list) == "table" then
        for _, o in ipairs(list) do
            if type(o) == "table" then
                local obj = U.Objective(o)
                q.objectives[#q.objectives + 1] = obj
                sum = sum + obj.frac
            end
        end
    end
    q.progress = q.complete and 1 or (#q.objectives > 0 and sum / #q.objectives or 0)
    q.r, q.g, q.b = U.LevelColor(questID, level)
    q.item = U.QuestItem(q)
    return q
end

-- Beispielinhalt (bei offenem stray-Fenster ohne Quests), deutsche Schlüssel, übersetzt beim Anzeigen
local SAMPLE = {
    { "Loch Modan", 10, "Eingeschneit", { { "Krug mit Schnee", 0, 1 } } },
    { "Loch Modan", 11, "Rattenfang", { { "Tunnelrattenohren", 4, 12 } } },
    { "Loch Modan", 11, "Thelsamar-Blutwurst", { { "Ebergedärme", 3, 3 }, { "Bärenfleisch", 1, 3 }, { "Spinnensekret", 0, 3 } } },
    { "Loch Modan", 12, "Verteidigung der Länder des Königs", { { "Splittersteintroggs", 6, 10 } } },
    { "Loch Modan", 15, "Gebirgsjäger Sturmlanzes Aufgabe", {}, true },
    { "Rotkammgebirge", 18, "Rotkammgulasch", { { "Große Geiferzahnschnauze", 1, 5 } } },
}

function U.SampleData()
    local list = {}
    for i, s in ipairs(SAMPLE) do
        local q = { id = nil, sample = true, title = L[s[3]], level = s[2], zone = L[s[1]], order = i,
            zoneOrder = (i < 6) and 1 or 2, complete = s[5] or false, failed = false, objectives = {} }
        local sum = 0
        for _, o in ipairs(s[4]) do
            local done = o[2] >= o[3]
            q.objectives[#q.objectives + 1] = { text = L[o[1]], counter = o[2] .. " / " .. o[3], done = done, frac = o[2] / o[3] }
            sum = sum + o[2] / o[3]
        end
        q.progress = q.complete and 1 or (#s[4] > 0 and sum / #s[4] or 0)
        q.r, q.g, q.b = U.LevelColor(nil, s[2])
        list[#list + 1] = q
    end
    return list, #list
end

-- Liefert Elemente zum Zeichnen: { kind = "zone", zone, count, collapsed } / { kind = "quest", q }
function U.BuildData()
    local quests, numQuests = {}, nil
    if C_QuestLog then
        numQuests = U.ScanLog()
        for questID, c in pairs(cache) do
            local q = U.ReadQuest(questID, c)
            if q then quests[#quests + 1] = q end
        end
    end
    local sample = false
    if #quests == 0 and ns.IsConfigOpen() then
        quests, numQuests = U.SampleData()
        sample = true
    end
    numQuests = numQuests or #quests

    local mode = ns.db.questTrackerSort
    local here = U.Str(GetRealZoneText and GetRealZoneText())
    local function Before(a, b)
        if mode == "level" and a.level ~= b.level then return a.level < b.level end
        if mode == "progress" and a.progress ~= b.progress then return a.progress > b.progress end
        if mode == "zone" and not ns.db.questTrackerGroup then
            local ah, bh = a.zone == here, b.zone == here
            if ah ~= bh then return ah end
        end
        return a.order < b.order
    end
    table.sort(quests, Before)

    local elements = {}
    if not ns.db.questTrackerGroup then
        for _, q in ipairs(quests) do elements[#elements + 1] = { kind = "quest", q = q } end
        return elements, numQuests, #quests, sample
    end
    -- Gebiete in Questlog-Reihenfolge; bei „Gebiet“ das aktuelle zuerst
    local zones, byZone = {}, {}
    for _, q in ipairs(quests) do
        local z = byZone[q.zone]
        if not z then
            z = { name = q.zone, order = q.zoneOrder, quests = {} }
            byZone[q.zone] = z
            zones[#zones + 1] = z
        end
        z.quests[#z.quests + 1] = q
    end
    table.sort(zones, function(a, b)
        if mode == "zone" then
            local ah, bh = a.name == here, b.name == here
            if ah ~= bh then return ah end
        end
        return a.order < b.order
    end)
    local collapsed = ns.db.questTrackerZones
    for _, z in ipairs(zones) do
        local shut = type(collapsed) == "table" and collapsed[z.name] == true
        elements[#elements + 1] = { kind = "zone", zone = z.name, count = #z.quests, collapsed = shut }
        if not shut then
            for _, q in ipairs(z.quests) do elements[#elements + 1] = { kind = "quest", q = q } end
        end
    end
    return elements, numQuests, #quests, sample
end

---------------------------------------------------------------------------
-- Rahmen
---------------------------------------------------------------------------

local tracker = CreateFrame("Frame", "strayQuestTracker", UIParent)
tracker:SetSize(ns.defaults.questTrackerWidth, 200)
tracker:SetFrameStrata("LOW")
tracker:SetClampedToScreen(true)
tracker:Hide()

local W = {} -- Bauteile der Liste

-- Hintergrund: schwarz, durchsichtig, mit runden Ecken (vier Viertelkreise + drei Flächen)
do
    local r = S.radius
    local bg = {}
    local function Tex()
        local t = tracker:CreateTexture(nil, "BACKGROUND")
        bg[#bg + 1] = t
        return t
    end
    local corners = {
        { "TOPLEFT", 0, 0.5, 0, 0.5 }, { "TOPRIGHT", 0.5, 1, 0, 0.5 },
        { "BOTTOMLEFT", 0, 0.5, 0.5, 1 }, { "BOTTOMRIGHT", 0.5, 1, 0.5, 1 },
    }
    for _, c in ipairs(corners) do
        local t = Tex()
        t:SetTexture(CIRCLE)
        t:SetTexCoord(c[2], c[3], c[4], c[5])
        t:SetSize(r, r)
        t:SetPoint(c[1])
    end
    local top = Tex()
    top:SetColorTexture(1, 1, 1, 1)
    top:SetPoint("TOPLEFT", r, 0)
    top:SetPoint("BOTTOMRIGHT", tracker, "TOPRIGHT", -r, -r)
    local mid = Tex()
    mid:SetColorTexture(1, 1, 1, 1)
    mid:SetPoint("TOPLEFT", 0, -r)
    mid:SetPoint("BOTTOMRIGHT", 0, r)
    local bottom = Tex()
    bottom:SetColorTexture(1, 1, 1, 1)
    bottom:SetPoint("TOPLEFT", tracker, "BOTTOMLEFT", r, r)
    bottom:SetPoint("BOTTOMRIGHT", -r, 0)
    W.bg = bg
end

function U.ApplyAlpha()
    local a = U.Clamp(ns.db and ns.db.questTrackerAlpha or 28, 0, 100) / 100
    for _, t in ipairs(W.bg) do t:SetVertexColor(0, 0, 0, a) end
end

-- Kopf: „Quests“ links, „20 / 40“ rechts, lila Linie darunter; Klick klappt ein/aus
do
    local head = CreateFrame("Button", nil, tracker)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(S.header)
    head:RegisterForClicks("LeftButtonUp")
    local title = head:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 15, "")
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 0.9)
    title:SetPoint("LEFT", S.pad, 1)
    title:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    local count = head:CreateFontString(nil, "OVERLAY")
    count:SetFont(FONT, 13, "")
    count:SetShadowOffset(1, -1)
    count:SetShadowColor(0, 0, 0, 0.9)
    count:SetPoint("RIGHT", -S.pad, 1)
    count:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    local line = head:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", S.pad, 0)
    line:SetPoint("BOTTOMRIGHT", -S.pad, 0)
    head:SetScript("OnEnter", function(self)
        title:SetTextColor(COLORS.accentText[1], COLORS.accentText[2], COLORS.accentText[3])
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Klick: Liste ein- oder ausklappen"], 1, 1, 1)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function()
        title:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
        GameTooltip:Hide()
    end)
    head:SetScript("OnClick", function()
        ns.db.questTrackerCollapsed = not ns.db.questTrackerCollapsed
        U.Refresh()
    end)
    W.head, W.title, W.count = head, title, count
end

-- Ebenen: Klickflächen unter dem Text, Text darüber (fängt keine Maus)
W.text = CreateFrame("Frame", nil, tracker)
W.text:SetAllPoints()
W.text:SetFrameLevel(tracker:GetFrameLevel() + 10)

-- Größen-Griff unten links (die Liste hängt rechts, also zieht man links/unten)
do
    local grip = CreateFrame("Button", nil, tracker)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMLEFT", 2, 2)
    grip:SetFrameLevel(tracker:GetFrameLevel() + 12)
    for _, kind in ipairs({ "Normal", "Highlight", "Pushed" }) do
        local suffix = (kind == "Normal" and "Up") or (kind == "Highlight" and "Highlight") or "Down"
        grip["Set" .. kind .. "Texture"](grip, GRIP .. suffix)
        local t = grip["Get" .. kind .. "Texture"](grip)
        if t then t:SetTexCoord(1, 0, 0, 1) end -- gespiegelt: Griff zeigt nach links unten
    end
    local function OnUpdate(self)
        local st = self.start
        if not st then return end
        local cx, cy = GetCursorPosition()
        local w = math.floor(U.Clamp(st.w + (st.x - cx) / st.scale, S.minW, S.maxW) + 0.5)
        local h = math.floor(U.Clamp(st.h + (st.y - cy) / st.scale, S.minH, S.maxH) + 0.5)
        if w ~= ns.db.questTrackerWidth or h ~= ns.db.questTrackerHeight then
            ns.db.questTrackerWidth, ns.db.questTrackerHeight = w, h
            U.Layout()
        end
    end
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local x, y = GetCursorPosition()
        self.start = { x = x, y = y, w = ns.db.questTrackerWidth, h = ns.db.questTrackerHeight,
            scale = tracker:GetEffectiveScale() }
        ns.db.questTrackerShowAll = false
        W.sizing = true
        self:SetScript("OnUpdate", OnUpdate)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self.start = nil
        W.sizing = false
        U.Refresh()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Ziehen: Größe ändern"], 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    W.grip = grip
end

---------------------------------------------------------------------------
-- Berufsreagenzien: verfolgte Rezepte (C_TradeSkillUI) mit Bestand / Bedarf je Reagenz
---------------------------------------------------------------------------

-- Bestand: Gegenstand (Taschen, Bank, Reagenzienbank, Kontobank) oder Währung
function U.ReagentCount(r)
    if type(r) ~= "table" then return 0 end
    local id = U.Num(r.itemID)
    if id and id ~= 0 then
        if C_Item and C_Item.GetItemCount then
            return U.Num(Call(C_Item.GetItemCount, id, true, false, true, true)) or 0
        end
        return U.Num(Call(GetItemCount, id, true)) or 0
    end
    local cur = U.Num(r.currencyID)
    if cur and cur ~= 0 and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = Call(C_CurrencyInfo.GetCurrencyInfo, cur)
        return type(info) == "table" and U.Num(info.quantity) or 0
    end
    return 0
end

function U.ReagentName(slot, r)
    local id = U.Num(r.itemID)
    if id and id ~= 0 then
        local name = C_Item and C_Item.GetItemNameByID and U.Str(Call(C_Item.GetItemNameByID, id))
        if not name then
            if C_Item and C_Item.RequestLoadItemDataByID then Call(C_Item.RequestLoadItemDataByID, id) end
            W.needItemInfo = true
            return "…"
        end
        return name
    end
    local cur = U.Num(r.currencyID)
    if cur and cur ~= 0 and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = Call(C_CurrencyInfo.GetCurrencyInfo, cur)
        return type(info) == "table" and U.Str(info.name) or nil
    end
    if type(slot.slotInfo) == "table" then return U.Str(slot.slotInfo.slotText) end
end

-- Ein Rezept lesen: { id, recraft, name, lines = { { text, counter, done } }, done }
function U.ReadRecipe(recipeID, recraft)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return nil end
    local schematic = Call(C_TradeSkillUI.GetRecipeSchematic, recipeID, recraft)
    if type(schematic) ~= "table" then return nil end
    local name = U.Str(schematic.name) or "?"
    if recraft then name = L("Neu herstellen: %s", name) end
    local rec = { id = recipeID, recraft = recraft, name = name, lines = {}, done = true }
    local slots = {}
    local list = type(schematic.reagentSlotSchematics) == "table" and schematic.reagentSlotSchematics or {}
    for _, slot in ipairs(list) do
        if type(slot) == "table" and slot.required == true and type(slot.reagents) == "table" then
            -- Pflichtplätze zum Verändern (Modifying) zuerst, wie bei Blizzard
            local modifying = Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Modifying
            table.insert(slots, modifying and 1 or (#slots + 1), slot)
        end
    end
    for _, slot in ipairs(slots) do
        local first = slot.reagents[1]
        local text = type(first) == "table" and U.ReagentName(slot, first)
        if text then
            local need = U.Num(slot.quantityRequired) or 1
            local ranged
            if type(slot.variableQuantities) == "table" and #slot.variableQuantities > 0 then
                local lo, hi = math.huge, 0
                for _, v in ipairs(slot.variableQuantities) do
                    local n = type(v) == "table" and U.Num(v.quantity)
                    if n then lo, hi = math.min(lo, n), math.max(hi, n) end
                end
                if hi > 0 then ranged = (lo == hi) and tostring(hi) or (lo .. "–" .. hi) end
            end
            if ranged then
                -- Menge wählbar (Blizzard merkt sie sich nicht): nur den Bereich zeigen
                rec.lines[#rec.lines + 1] = { text = text, counter = ranged, done = false }
                rec.done = false
            else
                -- Qualitätsstufen und Ersatzgegenstände eines Platzes zählen zusammen
                local have = 0
                for _, r in ipairs(slot.reagents) do have = have + U.ReagentCount(r) end
                local done = have >= need
                rec.lines[#rec.lines + 1] = { text = text, counter = have .. " / " .. need, done = done }
                if not done then rec.done = false end
            end
        end
    end
    return rec
end

-- Alle verfolgten Rezepte (normal, dann Wiederherstellen); leer, wenn die Option aus ist
function U.BuildRecipes(sample)
    local out = {}
    W.needItemInfo = false
    if not ns.db.questTrackerRecipes then return out end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked then
        for _, recraft in ipairs({ false, true }) do
            local ids = Call(C_TradeSkillUI.GetRecipesTracked, recraft)
            if type(ids) == "table" then
                for _, id in ipairs(ids) do
                    id = U.Num(id)
                    local rec = id and U.ReadRecipe(id, recraft)
                    if rec then out[#out + 1] = rec end
                end
            end
        end
    end
    if #out == 0 and sample then
        local rec = { sample = true, name = L["Beispiel: Verzauberung"], lines = {}, done = false }
        for _, s in ipairs({ { "Magischer Staub", 3, 25 }, { "Seelensplitter", 8, 8 } }) do
            rec.lines[#rec.lines + 1] = { text = L[s[1]], counter = s[2] .. " / " .. s[3], done = s[2] >= s[3] }
        end
        out[1] = rec
    end
    return out
end

---------------------------------------------------------------------------
-- Pools (Text, Pfeile, Klickflächen) mit Zurücksetzen für „passt nicht mehr“
---------------------------------------------------------------------------

local P = { fs = {}, tex = {}, btn = {}, nfs = 0, ntex = 0, nbtn = 0 }

function P.FS(size, c, justify)
    P.nfs = P.nfs + 1
    local fs = P.fs[P.nfs]
    if not fs then
        fs = W.text:CreateFontString(nil, "OVERLAY")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:SetJustifyV("TOP")
        P.fs[P.nfs] = fs
    end
    fs:SetFont(FONT, size, "")
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetJustifyH(justify or "RIGHT")
    fs:ClearAllPoints()
    fs:SetWidth(0)
    fs:SetWordWrap(false)
    fs:SetText("")
    fs:Show()
    return fs
end

function P.Arrow(down)
    P.ntex = P.ntex + 1
    local t = P.tex[P.ntex]
    if not t then
        t = W.text:CreateTexture(nil, "OVERLAY")
        t:SetTexture(ARROW)
        t:SetSize(10, 10)
        P.tex[P.ntex] = t
    end
    t:SetRotation(down and -math.pi / 2 or 0)
    t:SetVertexColor(COLORS.textDim[1], COLORS.textDim[2], COLORS.textDim[3], 1)
    t:ClearAllPoints()
    t:Show()
    return t
end

function P.Button(kind, top, height)
    P.nbtn = P.nbtn + 1
    local b = P.btn[P.nbtn]
    if not b then
        b = CreateFrame("Button", nil, tracker)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.10)
        b:SetScript("OnClick", function(self, button) U.OnRowClick(self, button) end)
        b:SetScript("OnEnter", function(self) U.OnRowEnter(self) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        P.btn[P.nbtn] = b
    end
    b:SetFrameLevel(tracker:GetFrameLevel() + 2)
    b.kind, b.q, b.zone, b.recipe = kind, nil, nil, nil
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", tracker, "TOPLEFT", S.pad / 2, -top)
    b:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad / 2, -top)
    b:SetHeight(math.max(1, height))
    b:Show()
    return b
end

function P.Mark()
    return { P.nfs, P.ntex, P.nbtn, #W.wanted }
end

function P.Rollback(m)
    for i = m[1] + 1, P.nfs do P.fs[i]:Hide() end
    for i = m[2] + 1, P.ntex do P.tex[i]:Hide() end
    for i = m[3] + 1, P.nbtn do P.btn[i]:Hide() end
    for i = #W.wanted, m[4] + 1, -1 do W.wanted[i] = nil end
    P.nfs, P.ntex, P.nbtn = m[1], m[2], m[3]
end

---------------------------------------------------------------------------
-- Zeichnen
---------------------------------------------------------------------------

W.wanted = {} -- Questgegenstände der gezeichneten Quests: { item, fs, questID }

-- Gebietszeile: „▾ LOCH MODAN“ rechtsbündig, eingeklappt mit Anzahl ganz rechts
function U.DrawZone(e, y, innerW)
    local right = S.pad
    if e.collapsed then
        local n = P.FS(12, COLORS.textDim)
        n:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y - 1)
        n:SetText(e.count)
        right = right + n:GetStringWidth() + 8
    end
    local fs = P.FS(12, COLORS.text)
    fs:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -right, -y - 1)
    fs:SetText(U.Upper(e.zone ~= "" and e.zone or L["Sonstige"]))
    local maxW = innerW - (right - S.pad) - 16
    if fs:GetStringWidth() > maxW then fs:SetWidth(maxW) end
    local arrow = P.Arrow(not e.collapsed)
    arrow:SetPoint("RIGHT", fs, "LEFT", -4, 0)
    local b = P.Button("zone", y, S.zoneH)
    b.zone = e.zone
    return y + S.zoneH + 4
end

-- Questblock: Titel (Schwierigkeitsfarbe, umbrechend), darunter Ziele oder „Bereit zur Abgabe“
function U.DrawQuest(q, y, innerW)
    local top = y
    local reserve = q.item and (S.item + 6) or 0
    local title = P.FS(13, { q.r, q.g, q.b })
    title:SetWordWrap(true)
    title:SetWidth(innerW - reserve)
    title:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y)
    title:SetText("[" .. q.level .. (q.elite and "+" or "") .. "] " .. q.title)
    y = y + math.ceil(title:GetStringHeight()) + 3

    if q.complete then
        local fs = P.FS(12, GREEN)
        fs:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y)
        fs:SetText(CHECK .. L["Bereit zur Abgabe"])
        y = y + 15
    elseif q.failed then
        local fs = P.FS(12, RED)
        fs:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y)
        fs:SetText(L["Fehlgeschlagen"])
        y = y + 15
    else
        for _, o in ipairs(q.objectives) do
            local cw = 0
            if o.counter then
                local c = P.FS(12, o.done and GREEN or COLORS.text)
                c:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y)
                c:SetText(o.counter)
                cw = c:GetStringWidth() + S.counterGap
            end
            local fs = P.FS(12, o.done and GREEN or { 0.82, 0.82, 0.86 })
            fs:SetWordWrap(true)
            fs:SetWidth(math.max(40, innerW - cw - 10))
            fs:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad - cw, -y)
            fs:SetText((o.done and CHECK or "") .. o.text)
            y = y + math.max(13, math.ceil(fs:GetStringHeight())) + 2
        end
    end
    if q.item then
        y = math.max(y, top + S.item + 2)
        W.wanted[#W.wanted + 1] = { item = q.item, fs = title, questID = q.id }
    end
    local b = P.Button("quest", top - 2, y - top + 2)
    b.q = q
    return y + S.gap
end

-- Überschrift „▾ BERUFSREAGENZIEN“ (wie eine Gebietszeile), eingeklappt mit Anzahl ganz rechts
function U.DrawRecipesHead(count, collapsed, y, innerW)
    local right = S.pad
    if collapsed then
        local n = P.FS(12, COLORS.textDim)
        n:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y - 1)
        n:SetText(count)
        right = right + n:GetStringWidth() + 8
    end
    local fs = P.FS(12, COLORS.text)
    fs:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -right, -y - 1)
    fs:SetText(U.Upper(L["Berufsreagenzien"]))
    local maxW = innerW - (right - S.pad) - 16
    if fs:GetStringWidth() > maxW then fs:SetWidth(maxW) end
    local arrow = P.Arrow(not collapsed)
    arrow:SetPoint("RIGHT", fs, "LEFT", -4, 0)
    P.Button("recipes", y, S.zoneH)
    return y + S.zoneH + 4
end

-- Rezeptblock: Rezeptname, darunter die Reagenzien mit „vorhanden / benötigt“ rechts
function U.DrawRecipe(r, y, innerW)
    local top = y
    local title = P.FS(13, r.done and GREEN or COLORS.text)
    title:SetWordWrap(true)
    title:SetWidth(innerW)
    title:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y)
    title:SetText(r.name)
    y = y + math.ceil(title:GetStringHeight()) + 3
    for _, o in ipairs(r.lines) do
        local cw = 0
        local c = P.FS(12, o.done and GREEN or COLORS.text)
        c:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y)
        c:SetText(o.counter)
        cw = c:GetStringWidth() + S.counterGap
        local fs = P.FS(12, o.done and GREEN or { 0.82, 0.82, 0.86 })
        fs:SetWordWrap(true)
        fs:SetWidth(math.max(40, innerW - cw - 10))
        fs:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad - cw, -y)
        fs:SetText((o.done and CHECK or "") .. o.text)
        y = y + math.max(13, math.ceil(fs:GetStringHeight())) + 2
    end
    local b = P.Button("recipe", top - 2, y - top + 2)
    b.recipe = r
    return y + S.gap
end

-- Zeile unten rechts: „+ n weitere Quests ▾“ bzw. „Weniger anzeigen ▴“
function U.DrawMore(y, text, down)
    local arrow = P.Arrow(down)
    arrow:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y - 2)
    arrow:SetRotation(down and -math.pi / 2 or math.pi / 2)
    local fs = P.FS(12, COLORS.textDim)
    fs:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad - 14, -y)
    fs:SetText(text)
    P.Button("more", y - 2, S.moreH + 2)
    return y + S.moreH
end

function U.Layout()
    if not ns.db then return end
    P.Rollback({ 0, 0, 0, 0 })
    local width = U.Clamp(ns.db.questTrackerWidth, S.minW, S.maxW)
    tracker:SetWidth(width)
    U.ApplyAlpha()
    local data = W.data or {}
    local maxQuests = C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept
        and U.Num(Call(C_QuestLog.GetMaxNumQuestsCanAccept))
    W.title:SetText(L["Quests"])
    W.count:SetText(maxQuests and L("%d / %d", data.numQuests or 0, maxQuests) or tostring(data.numQuests or 0))

    if ns.db.questTrackerCollapsed then
        W.grip:Hide()
        tracker:SetHeight(S.header + 2)
        return
    end
    W.grip:Show()

    local innerW = width - 2 * S.pad
    local normalMax = U.Clamp(ns.db.questTrackerHeight, S.minH, S.maxH)
    local full = W.sizing or ns.editMode
    local maxH = normalMax
    if ns.db.questTrackerShowAll and not full then
        local topY = tracker:GetTop()
        maxH = U.Num(topY) and math.max(normalMax, topY - 20) or 2000
    end

    local elements = data.elements or {}
    local y = S.header + 8
    local drawn, hiddenByZone, stopped = 0, 0, false
    if #elements == 0 then
        local fs = P.FS(12, COLORS.textDim)
        fs:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -S.pad, -y)
        fs:SetText(L["Keine Quests im Questlog"])
        y = y + 16
    end
    -- Platz für die Berufsreagenzien-Kopfzeile (und die „weitere Quests“-Zeile) fest reservieren
    local recipes = data.recipes
    local hasRecipes = type(recipes) == "table" and #recipes > 0
    local reserve = hasRecipes and (S.zoneH + 6 + S.moreH + 2) or 0
    local zoneMark, zoneFresh
    for i, e in ipairs(elements) do
        local last = (i == #elements)
        local limit = maxH - S.bottom - reserve - (last and 0 or (S.moreH + 2))
        local mark = P.Mark()
        local ny
        if e.kind == "zone" then
            ny = U.DrawZone(e, y, innerW)
        else
            ny = U.DrawQuest(e.q, y, innerW)
        end
        if ny > limit and drawn + hiddenByZone > 0 then
            -- passt nicht: zurücknehmen; eine leere Gebietsüberschrift gleich mit
            if e.kind == "quest" and zoneFresh and zoneMark then
                P.Rollback(zoneMark)
                y = zoneMark.y
            else
                P.Rollback(mark)
            end
            stopped = true
            break
        end
        if e.kind == "zone" then
            zoneMark = mark
            zoneMark.y = y
            zoneFresh = not e.collapsed
            if e.collapsed then hiddenByZone = hiddenByZone + e.count end
        else
            drawn = drawn + 1
            zoneFresh = false
        end
        y = ny
    end
    -- „weitere Quests“ direkt unter den Quests, danach die Berufsreagenzien (Kopfzeile ist reserviert)
    local rest = (data.total or 0) - drawn - hiddenByZone
    if stopped and rest > 0 then
        y = U.DrawMore(y + 2, L("+ %d weitere Quests", rest), true)
    end
    local recipeRest = 0
    if hasRecipes then
        local shut = ns.db.questTrackerRecipesCollapsed and true or false
        y = U.DrawRecipesHead(#recipes, shut, y + 4, innerW)
        if not shut then
            for i, r in ipairs(recipes) do
                local rmark = P.Mark()
                local ry = U.DrawRecipe(r, y, innerW)
                local rlimit = maxH - S.bottom - (i == #recipes and 0 or (S.moreH + 2))
                if ry > rlimit and i > 1 then
                    P.Rollback(rmark)
                    recipeRest = #recipes - i + 1
                    break
                end
                y = ry
            end
        end
    end
    if recipeRest > 0 then
        y = U.DrawMore(y + 2, L("+ %d weitere Rezepte", recipeRest), true)
    elseif not (stopped and rest > 0) and ns.db.questTrackerShowAll and y > normalMax then
        y = U.DrawMore(y + 2, L["Weniger anzeigen"], false)
    end
    local h = y + S.bottom
    if full then h = math.max(h, normalMax) end
    tracker:SetHeight(math.max(S.header + 20, h))
end

---------------------------------------------------------------------------
-- Klicks und Tooltips
---------------------------------------------------------------------------

function U.OpenQuest(questID, details)
    if details and QuestUtil and QuestUtil.OpenQuestDetails then
        Call(QuestUtil.OpenQuestDetails, questID)
    elseif QuestMapFrame_OpenToQuestDetails then
        Call(QuestMapFrame_OpenToQuestDetails, questID)
    elseif ToggleQuestLog then
        Call(ToggleQuestLog)
    end
end

function U.QuestLink(questID)
    if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID then
        return Call(ChatFrameUtil.TryInsertQuestLinkForQuestID, questID)
    end
    local link = GetQuestLink and U.Str(Call(GetQuestLink, questID))
    if link and ChatEdit_InsertLink then return Call(ChatEdit_InsertLink, link) end
end

function U.OnRowClick(self, button)
    if self.kind == "zone" then
        if type(ns.db.questTrackerZones) ~= "table" then ns.db.questTrackerZones = {} end
        local z = self.zone or ""
        ns.db.questTrackerZones[z] = (not ns.db.questTrackerZones[z]) or nil
        U.Refresh()
    elseif self.kind == "more" then
        ns.db.questTrackerShowAll = not ns.db.questTrackerShowAll
        U.Refresh()
    elseif self.kind == "recipes" then
        ns.db.questTrackerRecipesCollapsed = not ns.db.questTrackerRecipesCollapsed
        U.Refresh()
    elseif self.kind == "recipe" then
        local r = self.recipe
        if not r or not r.id then return end
        if button == "RightButton" then
            -- Rezept nicht mehr verfolgen (Blizzard schickt danach TRACKED_RECIPE_UPDATE)
            if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
                Call(C_TradeSkillUI.SetRecipeTracked, r.id, false, r.recraft)
            end
        elseif IsModifiedClick and IsModifiedClick("CHATLINK") then
            local link = C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink and U.Str(Call(C_TradeSkillUI.GetRecipeLink, r.id))
            if link and ChatFrameUtil and ChatFrameUtil.InsertLink then
                Call(ChatFrameUtil.InsertLink, link)
            elseif link and ChatEdit_InsertLink then
                Call(ChatEdit_InsertLink, link)
            end
        elseif r.recraft then
            return
        elseif InCombatLockdown() then
            ns.Print(L["Im Kampf lässt sich das Rezept nicht öffnen."])
        elseif C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
            Call(C_TradeSkillUI.OpenRecipe, r.id)
        end
    elseif self.kind == "quest" then
        local q = self.q
        if not q or not q.id then return end
        if button == "LeftButton" and IsModifiedClick and IsModifiedClick("CHATLINK") then
            U.QuestLink(q.id)
        elseif InCombatLockdown() then
            ns.Print(L["Im Kampf lässt sich das Questlog nicht öffnen."])
        else
            U.OpenQuest(q.id, button == "RightButton")
        end
    end
end

function U.OnRowEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self.kind == "zone" then
        GameTooltip:AddLine(L["Klick: Gebiet ein- oder ausklappen"], 1, 1, 1)
    elseif self.kind == "recipes" then
        GameTooltip:AddLine(L["Klick: Berufsreagenzien ein- oder ausklappen"], 1, 1, 1)
    elseif self.kind == "recipe" then
        if not self.recipe then return end
        GameTooltip:AddLine(self.recipe.name, 1, 1, 1, true)
        if self.recipe.id then
            if not self.recipe.recraft then GameTooltip:AddLine(L["Klick: Rezept öffnen"], 0.8, 0.8, 0.8) end
            GameTooltip:AddLine(L["Rechtsklick: nicht mehr verfolgen"], 0.8, 0.8, 0.8)
            GameTooltip:AddLine(L["Shift-Klick: Rezeptlink in den Chat"], 0.8, 0.8, 0.8)
        end
    elseif self.kind == "more" then
        GameTooltip:AddLine(ns.db.questTrackerShowAll and L["Klick: weniger Quests anzeigen"]
            or L["Klick: alle Quests anzeigen"], 1, 1, 1)
    elseif self.q then
        GameTooltip:AddLine(self.q.title, self.q.r, self.q.g, self.q.b, true)
        GameTooltip:AddLine(L["Klick: Quest auf der Karte öffnen"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Rechtsklick: Questdetails"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Shift-Klick: Questlink in den Chat"], 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Sichere Questgegenstand-Knöpfe (an UIParent, nur außerhalb des Kampfes ändern)
---------------------------------------------------------------------------

local itemButtons = {}

function U.ItemCooldown(b)
    local start, dur, enable
    if b.logIndex and GetQuestLogSpecialItemCooldown then
        start, dur, enable = Call(GetQuestLogSpecialItemCooldown, b.logIndex)
    end
    if not U.Num(start) then
        local fn = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
        start, dur, enable = Call(fn, b.itemID)
    end
    start, dur = U.Num(start), U.Num(dur)
    if start and dur then
        if CooldownFrame_Set then
            Call(CooldownFrame_Set, b.cd, start, dur, (enable == true or enable == 1) and 1 or 0)
        else
            Call(b.cd.SetCooldown, b.cd, start, dur)
        end
    end
end

function U.ItemVisual(b)
    if not b.itemID then return end
    local count = U.ItemCount(b.itemID)
    b.count:SetText(count > 1 and count or "")
    b.icon:SetDesaturated(count <= 0)
    U.ItemCooldown(b)
end

function U.ItemRange(b, elapsed)
    b.tick = (b.tick or 0) - elapsed
    if b.tick > 0 then return end
    b.tick = 0.25
    local inRange
    if UnitExists("target") then
        if b.logIndex and IsQuestLogSpecialItemInRange then
            local v = U.Num(Call(IsQuestLogSpecialItemInRange, b.logIndex))
            if v ~= nil then inRange = (v == 1) end
        elseif C_Item and C_Item.IsItemInRange then
            local v = Call(C_Item.IsItemInRange, b.itemID, "target")
            if not ns.IsSecret(v) and v ~= nil then inRange = v and true or false end
        end
    end
    if inRange == false then
        b.icon:SetVertexColor(1, 0.25, 0.25)
    else
        b.icon:SetVertexColor(1, 1, 1)
    end
end

function U.ItemButton(i)
    local b = itemButtons[i]
    if b then return b end
    b = CreateFrame("Button", "strayQuestItem" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("MEDIUM")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    b:SetAttribute("useOnKeyDown", false)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(COLORS.line[1], COLORS.line[2], COLORS.line[3], 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self.logIndex and GameTooltip.SetQuestLogSpecialItem then
            GameTooltip:SetQuestLogSpecialItem(self.logIndex)
        elseif self.bag and self.slot then
            GameTooltip:SetBagItem(self.bag, self.slot)
        elseif self.itemID then
            GameTooltip:SetItemByID(self.itemID)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnUpdate", U.ItemRange)
    b:Hide()
    itemButtons[i] = b
    return b
end

function U.SyncItems()
    if InCombatLockdown() then
        W.itemsPending = true
        return
    end
    W.itemsPending = false
    local n = 0
    if Enabled() and tracker:IsShown() and not ns.db.questTrackerCollapsed then
        local uiScale = UIParent:GetEffectiveScale()
        for _, w in ipairs(W.wanted) do
            local fs = w.fs
            local right, top = fs:IsShown() and U.Num(fs:GetRight()), U.Num(fs:GetTop())
            if right and top then
                n = n + 1
                local b = U.ItemButton(n)
                local s = fs:GetEffectiveScale() / uiScale
                local textW = math.min(fs:GetStringWidth() or 0, fs:GetWidth() or 0)
                local size = S.item * tracker:GetEffectiveScale() / uiScale
                b:SetSize(size, size)
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (right - textW - 6) * s, (top + 3) * s)
                local it = w.item
                if b.itemID ~= it.itemID then b:SetAttribute("item", "item:" .. it.itemID) end
                b.itemID, b.logIndex, b.bag, b.slot = it.itemID, it.logIndex, it.bag, it.slot
                local tex = it.tex or (C_Item and C_Item.GetItemIconByID and Call(C_Item.GetItemIconByID, it.itemID))
                b.icon:SetTexture(tex or 134400)
                U.ItemVisual(b)
                b:Show()
            end
        end
    end
    for i = n + 1, #itemButtons do itemButtons[i]:Hide() end
end

---------------------------------------------------------------------------
-- Blizzards Questverfolgung ausblenden (nur Hide außerhalb des Kampfes, im Kampf Alpha)
---------------------------------------------------------------------------

local B = { hidden = false, hooked = false, pending = false }

function B.Want()
    return Enabled() and ns.db.questTrackerHideBlizzard and true or false
end

function B.EditModeActive()
    local em = _G.EditModeManagerFrame
    return em and em.IsEditModeActive and Call(em.IsEditModeActive, em) and true or false
end

function B.HideNow(otf)
    if B.EditModeActive() then return end
    if InCombatLockdown() then
        Call(otf.SetAlpha, otf, 0)
        B.pending = true
    else
        Call(otf.SetAlpha, otf, 1)
        Call(otf.Hide, otf)
        B.pending = false
    end
    B.hidden = true
end

function B.Apply()
    local otf = _G.ObjectiveTrackerFrame
    if not otf or type(otf.HookScript) ~= "function" then return end
    if not B.hooked then
        B.hooked = true
        otf:HookScript("OnShow", function(self)
            if B.Want() then B.HideNow(self) end
        end)
        local em = _G.EditModeManagerFrame
        if em and type(em.ExitEditMode) == "function" then
            hooksecurefunc(em, "ExitEditMode", function() C_Timer.After(0, B.Apply) end)
        end
    end
    if B.Want() then
        if otf:IsShown() or B.pending then B.HideNow(otf) end
    elseif B.hidden then
        if InCombatLockdown() then
            Call(otf.SetAlpha, otf, 1)
            B.pending = true
        else
            Call(otf.SetAlpha, otf, 1)
            Call(otf.Show, otf)
            B.hidden, B.pending = false, false
        end
    end
end

---------------------------------------------------------------------------
-- Position: immer am rechten Rand, nur die Höhe (Abstand von oben) ist frei
---------------------------------------------------------------------------

ns.MakeMovable(tracker, KEY, { "TOPRIGHT", "TOPRIGHT", 0, -ns.defaults.questTrackerTop })

function U.Place()
    ns.ApplyScale(tracker)
    local pos = ns.db.positions[KEY]
    local y = -(tonumber(ns.db.questTrackerTop) or ns.defaults.questTrackerTop)
    if type(pos) == "table" and pos[1] == "TOPRIGHT" and U.Num(pos[4]) then y = pos[4] end
    tracker:ClearAllPoints()
    tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, y)
end

-- Nach dem Ziehen (Shift+Ziehen oder Bearbeitungsmodus): zurück an den rechten Rand, Höhe behalten
function U.SnapRight()
    local top = U.Num(tracker:GetTop())
    local uiTop = U.Num(UIParent:GetTop())
    if not top or not uiTop then return end
    local k = UIParent:GetEffectiveScale() / tracker:GetEffectiveScale()
    local y = math.floor(top - uiTop * k + 0.5)
    ns.db.positions[KEY] = { "TOPRIGHT", "TOPRIGHT", 0, y }
    ns.db.questTrackerTop = -y
    U.Place()
    U.SyncItems()
end

tracker:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    U.SnapRight()
end)
tracker.strayOnDragStop = function() U.SnapRight() end

---------------------------------------------------------------------------
-- Aktualisieren und Events
---------------------------------------------------------------------------

function U.Refresh()
    if not ns.db then return end
    if not Enabled() then
        U.SyncItems()
        return
    end
    local elements, numQuests, total, sample = U.BuildData()
    W.data = { elements = elements, numQuests = numQuests, total = total,
        recipes = U.BuildRecipes(sample or (#elements == 0 and ns.IsConfigOpen())) }
    U.Layout()
    U.SyncItems()
end

local scheduled = false
function U.Schedule()
    if scheduled or not Enabled() then return end
    scheduled = true
    C_Timer.After(0.15, function()
        scheduled = false
        local ok, err = pcall(U.Refresh)
        if not ok then geterrorhandler()(err) end
    end)
end

local ev = CreateFrame("Frame")
local EVENTS = {
    "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED",
    "BAG_UPDATE_COOLDOWN", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
    "TRACKED_RECIPE_UPDATE", "CURRENCY_DISPLAY_UPDATE", "GET_ITEM_INFO_RECEIVED",
}

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        local id = U.Num(arg1)
        if id then cache[id] = nil end
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if arg1 ~= "player" then return end
    elseif event == "BAG_UPDATE_DELAYED" then
        bagDirty = true
    elseif event == "CURRENCY_DISPLAY_UPDATE" or event == "TRACKED_RECIPE_UPDATE" then
        if not ns.db.questTrackerRecipes then return end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- nur, wenn ein Reagenzname noch fehlt (sonst feuert das Ereignis ständig)
        if not (W.needItemInfo and ns.db.questTrackerRecipes) then return end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        for _, b in ipairs(itemButtons) do
            if b:IsShown() then pcall(U.ItemVisual, b) end
        end
        return
    end
    U.Schedule()
end)

function U.SetEvents(on)
    for _, e in ipairs(EVENTS) do
        if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
end

function U.Apply()
    if not ns.db then return end
    if Enabled() then
        U.Place()
        tracker:Show()
        U.SetEvents(true)
        bagDirty = true
        U.Refresh()
    else
        U.SetEvents(false)
        tracker:Hide()
        U.SyncItems()
    end
    B.Apply()
end

ns.On("PLAYER_LOGIN", function()
    U.Apply()
    -- Questie: über die offizielle API sofort mit aktualisieren (nur Rückrufe, nichts ändern)
    local api = U.QuestieLoaded() and type(_G.Questie) == "table" and _G.Questie.API
    if type(api) == "table" then
        if type(api.RegisterOnReady) == "function" then pcall(api.RegisterOnReady, U.Schedule) end
        if type(api.RegisterForQuestUpdates) == "function" then
            pcall(api.RegisterForQuestUpdates, function() U.Schedule() end)
        end
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function() U.Schedule() end)

ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_ObjectiveTracker" and ns.db then B.Apply() end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if B.pending then B.Apply() end
    if W.itemsPending then U.SyncItems() end
end)

-- Bei offenem stray-Fenster Beispielinhalt zeigen (nur wenn das Log leer ist)
ns.OnConfig(function() if Enabled() then U.Schedule() end end)

ns.RegisterMovable(tracker, "Questtracker", function() if Enabled() then U.Schedule() end end, {
    widthKey = "questTrackerWidth", heightKey = "questTrackerHeight",
    widthMin = S.minW, widthMax = S.maxW, heightMin = S.minH, heightMax = S.maxH,
    onSize = function() U.Refresh() end,
})

---------------------------------------------------------------------------
-- Optionen (Bereich „Questtracker“)
---------------------------------------------------------------------------

ns.AddOption(2, SECTION, {
    key = "questTracker",
    label = L["Questtracker anzeigen"],
    tooltip = L["Eigene Questliste am rechten Bildschirmrand mit allen Quests aus deinem Questlog. Klick auf „Quests“ klappt die Liste ein, Klick auf ein Gebiet nur dieses Gebiet. Die Größe ziehst du unten links.\n\nKlick auf eine Quest öffnet sie auf der Karte, Rechtsklick die Questdetails, Shift-Klick schreibt den Questlink in den Chat."],
    keywords = { "questtracker", "quest tracker", "questliste", "quest list", "ziele", "objectives", "questie" },
    set = function(v) ns.db.questTracker = v; U.Apply() end,
})

ns.AddOption(2, SECTION, {
    key = "questTrackerHideBlizzard",
    label = L["Blizzard-Questverfolgung ausblenden"],
    tooltip = L["Blendet Blizzards eigene Questverfolgung aus, solange der stray-Questtracker an ist. Im Kampf wird sie nur durchsichtig und erst danach ganz ausgeblendet. Dabei verschwindet auch Blizzards Liste „Berufsreagenzien“; stray zeigt sie selbst unter den Quests."],
    keywords = { "blizzard", "objective tracker", "questverfolgung", "verstecken", "hide" },
    isEnabled = function() return ns.db.questTracker end,
    set = function(v) ns.db.questTrackerHideBlizzard = v; B.Apply() end,
})

ns.AddOption(2, SECTION, {
    key = "questTrackerRecipes",
    label = L["Berufsreagenzien anzeigen"],
    tooltip = L["Zeigt unter den Quests deine verfolgten Berufsrezepte mit den benötigten Reagenzien (vorhanden / benötigt, Taschen und Bank). Erledigte Reagenzien werden grün. Klick auf ein Rezept öffnet es, Rechtsklick beendet die Verfolgung, Shift-Klick schreibt den Link in den Chat."],
    keywords = { "berufe", "reagenzien", "rezepte", "professions", "reagents", "recipes", "crafting", "tracker" },
    isEnabled = function() return ns.db.questTracker end,
    set = function(v) ns.db.questTrackerRecipes = v; U.Refresh() end,
})

ns.AddOption(2, SECTION, {
    key = "questTrackerGroup",
    label = L["Nach Gebiet gruppieren"],
    tooltip = L["Fasst die Quests unter dem Gebietsnamen zusammen wie im Questlog. Gebiete lassen sich einzeln einklappen."],
    keywords = { "gebiet", "zone", "gruppieren", "group" },
    isEnabled = function() return ns.db.questTracker end,
    set = function(v) ns.db.questTrackerGroup = v; U.Refresh() end,
})

ns.AddOption(2, SECTION, {
    key = "questTrackerSort",
    type = "choice",
    label = L["Sortierung"],
    values = { "zone", "level", "progress" },
    labels = { L["Gebiet"], L["Stufe"], L["Fortschritt"] },
    tooltip = L["Gebiet: aktuelles Gebiet zuerst, sonst Reihenfolge des Questlogs.\nStufe: niedrigste Stufe zuerst.\nFortschritt: fast fertige Quests zuerst."],
    keywords = { "sortierung", "sort", "stufe", "level", "fortschritt", "progress" },
    isEnabled = function() return ns.db.questTracker end,
    set = function(v) ns.db.questTrackerSort = v; U.Refresh() end,
})

ns.AddOption(2, SECTION, {
    key = "questTrackerAlpha",
    type = "slider",
    label = L["Deckkraft des Hintergrunds"],
    min = 0, max = 100, step = 2,
    format = function(v) return v .. " %" end,
    tooltip = L["0 = ganz durchsichtig, 100 = schwarz."],
    keywords = { "deckkraft", "opacity", "alpha", "hintergrund", "background" },
    isEnabled = function() return ns.db.questTracker end,
    set = function(v) ns.db.questTrackerAlpha = v; U.ApplyAlpha() end,
})

ns.AddOption(2, SECTION, {
    key = "questTrackerWidth",
    type = "slider",
    label = L["Breite"],
    min = S.minW, max = S.maxW, step = 1,
    tooltip = L["Breite der Questliste in Pixeln. Die Höhe ziehst du unten links am Griff."],
    keywords = { "breite", "width", "größe", "size" },
    isEnabled = function() return ns.db.questTracker end,
    set = function(v) ns.db.questTrackerWidth = v; U.Refresh() end,
})

ns.AddOption(2, SECTION, {
    key = "questTrackerTop",
    type = "slider",
    label = L["Abstand von oben"],
    min = 0, max = 900, step = 1,
    tooltip = L["Abstand der Questliste vom oberen Bildschirmrand in Pixeln. Im Bearbeitungsmodus kannst du sie auch hoch und runter ziehen; sie bleibt immer am rechten Rand."],
    keywords = { "position", "höhe", "oben", "top", "offset" },
    isEnabled = function() return ns.db.questTracker end,
    get = function()
        local pos = ns.db.positions and ns.db.positions[KEY]
        if type(pos) == "table" and pos[1] == "TOPRIGHT" and U.Num(pos[4]) then return math.floor(-pos[4] + 0.5) end
        return ns.db.questTrackerTop
    end,
    set = function(v)
        ns.db.questTrackerTop = v
        ns.db.positions[KEY] = { "TOPRIGHT", "TOPRIGHT", 0, -v }
        if Enabled() then
            U.Place()
            U.SyncItems()
        end
    end,
})

ns.AddOption(2, SECTION, {
    key = "questTrackerQuestie",
    type = "button",
    label = L["Questie-Einstellungen"],
    buttonText = L["Öffnen"],
    noExport = true,
    tooltip = L["Öffnet das Einstellungsfenster von Questie. Dort unter „Tracker“ die Questliste ausschalten, damit nicht zwei Listen erscheinen; Karte und Minimap von Questie bleiben. stray ändert an Questie nichts."],
    disabledHint = L["Questie ist nicht geladen."],
    keywords = { "questie", "tracker" },
    isEnabled = function() return U.QuestieLoaded() end,
    onClick = function()
        local fn = SlashCmdList and SlashCmdList["ACECONSOLE_QUESTIE"]
        if type(fn) == "function" and not InCombatLockdown() then
            pcall(fn, "")
        else
            ns.Print(L["Questie-Einstellungen: /questie eingeben."])
        end
    end,
})
