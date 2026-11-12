-- stray – stray-Tasche: Kern (Daten, Knopf-Vorrat, Ereignisse, Ansichten, Übernahme der Blizzard-Taschen)
--
-- Öffentliche Tabelle: ns.Bag (lokal B). Die anderen bag_*.lua bauen darauf auf.
--
-- ── Konstanten ──────────────────────────────────────────────────────────────────────────────────
--   B.C.LAST_BAG        letzte normale Tasche (4); Rucksack = 0
--   B.C.REAGENT_BAG     Reagenzientasche (5); nur belegt, wenn GetContainerNumSlots(5) > 0
--   B.C.MIN_COLS/MAX_COLS (6/20), B.C.MIN_SLOT/MAX_SLOT (28/44), B.C.CL = Itemklassen
--   B.API               Hüllen: NumSlots(bag), FreeSlots(bag) → free, family, SlotInfo(bag, slot),
--                       QuestInfo(bag, slot), Cooldown(bag, slot), IsNewItem(bag, slot), BagName(bag),
--                       ItemClass(itemID, link) → classID, subClassID, equipLoc, QualityColor(q) → r, g, b
-- ── Daten ───────────────────────────────────────────────────────────────────────────────────────
--   B.Enabled()         Hauptschalter bagWindow
--   B.Scan()            liest alle Taschen neu (läuft automatisch vor jedem Refresh)
--   B.bagIDs            Array der Taschen-IDs, z. B. { 0, 1, 2, 3, 4 } (+5 mit Reagenzientasche)
--   B.bags[bag]         { bag, size, free, family, special (family ~= 0), name (roh), used }
--   B.slots[bag][slot]  Datensatz (wiederverwendet, nie festhalten – nach einem Scan neu lesen):
--       bag, slot, hasItem (bool), itemID, link, name, nameLower, count, quality, icon,
--       classID, subClassID, equipLoc, locked, isNew, bound, noValue,
--       isQuest (= questItem oder questStarter oder questNeeded), questItem, questStarter, questNeeded
--       Für Ansichten dürfen eigene Datensätze entstehen (Kopien mit demselben bag/slot, dann
--       synthetic = true setzen, sonst liest das Fenster den Platz frisch aus dem Scan); optional
--       überschreibt rec.displayCount die Stapelzahl (z. B. beim Zusammenfassen gleicher Gegenstände).
--   B.GetRecord(bag, slot), B.ForEachRecord(fn(rec)), B.BagTitle(bag) (Anzeigename, übersetzt)
--   B.used, B.total, B.free   Belegung der normalen Taschen (Spezialtaschen zählen nicht)
--   B.FillRecord(rec, bag, slot)   liest einen Platz in einen Datensatz (auch für die Bank nutzbar)
-- ── Aktualisierung ──────────────────────────────────────────────────────────────────────────────
--   B.OnRefresh(fn)     fn(reasons) nach jedem gebündelten Refresh; reasons = Menge { bag=true, lock=true,
--                       cooldown=true, quest=true, config=true, open=true, … } (nur Lesen, wird wiederverwendet)
--   B.RequestRefresh(delay, reason)   fordert einen Refresh an (gebündelt, höchstens einer je Verzögerung)
--   B.Refresh(reason)   sofort scannen und Callbacks rufen (nur wenn Hauptschalter an)
-- ── Ansichten / Abschnitte ──────────────────────────────────────────────────────────────────────
--   B.RegisterView(key, { label = "deutscher Schlüssel", build = function() return sections end })
--   B.GetView(key) → Ansicht oder multibag; B.viewOrder = Array der Schlüssel (für die Auswahl)
--   B.BuildSections() → Liste von Abschnitten der aktiven Ansicht (Option bagView):
--       { key, title, counter ("(3 / 16)" oder nil), items = {Datensätze mit Gegenstand},
--         empties = {Datensätze leerer Plätze} (echte Plätze, werden als Knöpfe gezeigt) oder nil,
--         emptySlots = n (zusätzliche gedimmte Felder ohne Funktion), plus = bool, onPlus = fn(section, button),
--         noHeader = bool, hidden = bool, collapsible = bool, collapsed = bool, onToggle = fn(section),
--         headerButton = { text, onClick = fn(section), tooltip }, bag (nur Taschen-Ansicht), special = bool }
--       multibag = je Tasche ein Abschnitt (Standard), onebag = alle normalen Taschen in einem Raster.
--       Kommt derselbe Platz (bag, slot) mehrfach vor, nutzt das Fenster Zusatzknöpfe (siehe unten).
-- ── Knopf-Vorrat (echte Blizzard-Itemknöpfe, nie im Kampf erzeugt) ─────────────────────────────
--   B.host                      gemeinsamer Elternrahmen aller Taschen-Container (hängt im Fenster)
--   B.WarmPool()                legt fehlende Knöpfe an (nur außerhalb des Kampfes); true, wenn alles da ist
--   B.AcquireButton(bag, slot, extra)   Knopf für diesen Platz oder nil (im Kampf: nur Vorhandenes).
--                               extra = 2, 3, … liefert Zusatzknöpfe, die auf (bag, slot) umgesetzt werden
--   B.ReleaseButton(btn)        versteckt den Knopf (nur außerhalb des Kampfes)
--   B.ButtonState(btn)          Zustandstabelle des Knopfes (schwach gehalten): { bag, slot, extra, … }
--   B.OnButtonCreated(fn)       fn(btn, state) für jeden neuen und jeden schon vorhandenen Knopf
--   B.ForEachButton(fn)         fn(btn, state) für alle angelegten Knöpfe
-- ── Fenster (bag_window.lua) ────────────────────────────────────────────────────────────────────
--   B.Open() B.Close() B.Toggle() B.IsOpen() B.frame
--   B.AddHeaderIcon{ key, icon (Textur), atlas, tooltip, onClick } → Knopf; B.header.icons = Container
--   B.sidebarHost, B.SetSidebarWidth(w), B.footerLeft, B.RequestLayout(), B.RequestPaint()
--   B.SetSearch(text), B.GetSearch(), B.MatchesSearch(rec)
--   B.SetTriage(bag, slot)    Löschkandidat markieren (triage.lua)
-- ── Übernahme von Blizzards Taschen (hier unten) ────────────────────────────────────────────────
--   B.ApplyTakeover()           parkt Blizzards Taschenrahmen (Schlüsselring bleibt) bzw. gibt sie frei
--   B.GamepadActive()           true bei aktiver Gamepad-Oberfläche (InputUtil.IsGamepadUIEnabled): dann bleiben Blizzards Taschen
--   B.openerName                Name des Rahmens, der das Fenster automatisch geöffnet hat (nil = von Hand)
--   B.AutoAllowed(name)         (bag_auto.lua) darf der Rahmen `name` das Fenster öffnen? Fragt openBy ab

local _, ns = ...
local L = ns.L
local IsSecret = ns.IsSecret

local B = {}
ns.Bag = B

---------------------------------------------------------------------------
-- Standardwerte
---------------------------------------------------------------------------

ns.defaults.bagWindow = false   -- Hauptschalter: stray-Tasche statt Blizzards Taschen
ns.defaults.bagView = "multibag" -- "multibag" (Pro Tasche) | "onebag" (Eine Tasche) | "categories" (Kategorien)
ns.defaults.bagColumns = 12
ns.defaults.bagHeight = 0       -- 0 = Höhe automatisch nach Inhalt
ns.defaults.bagSlotSize = 36
ns.defaults.bagLocked = false   -- Fenster nicht verschieben, Größe nicht ändern
ns.defaults.bagMerge = false    -- gleiche Gegenstände zusammenfassen (nur Ansicht „Kategorien“)
ns.defaults.bagCollapsed = {}   -- [Abschnitts-Schlüssel] = true: eingeklappt

---------------------------------------------------------------------------
-- Konstanten
---------------------------------------------------------------------------

local C = {}
B.C = C
do
    local inv = Constants and Constants.InventoryConstants
    C.FIRST_BAG = 0
    C.LAST_BAG = (inv and tonumber(inv.NumBagSlots)) or (type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS) or 4
    C.REAGENT_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or (C.LAST_BAG + 1)
    C.KEYRING = (Enum and Enum.BagIndex and Enum.BagIndex.Keyring) or KEYRING_CONTAINER
    C.MIN_COLS, C.MAX_COLS = 6, 20
    C.MIN_SLOT, C.MAX_SLOT = 28, 44
    local IC = (Enum and Enum.ItemClass) or {}
    C.CL = {
        consumable = IC.Consumable or 0, container = IC.Container or 1, weapon = IC.Weapon or 2,
        armor = IC.Armor or 4, reagent = IC.Reagent or 5, trade = IC.Tradegoods or 7,
        quiver = IC.Quiver or 11, quest = IC.Questitem or 12,
    }
end

---------------------------------------------------------------------------
-- API-Hüllen (C_Container auf dem modernen Client, sonst alte Globale)
---------------------------------------------------------------------------

local API = {}
B.API = API
local Container = C_Container or {}

local function Public(v)
    if IsSecret(v) then return nil end
    return v
end

function API.NumSlots(bag)
    local fn = Container.GetContainerNumSlots or GetContainerNumSlots
    if not fn then return 0 end
    local ok, n = pcall(fn, bag)
    if not ok or IsSecret(n) or type(n) ~= "number" then return 0 end
    return n
end

-- freie Plätze, Taschenfamilie (0 = normale Tasche, sonst Spezialtasche)
function API.FreeSlots(bag)
    local fn = Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not fn then return nil end
    local ok, free, family = pcall(fn, bag)
    if not ok or IsSecret(free) or IsSecret(family) then return nil end
    return free, family
end

-- icon, count, locked, quality, link, itemID, isBound, hasNoValue
function API.SlotInfo(bag, slot)
    if Container.GetContainerItemInfo then
        local ok, info = pcall(Container.GetContainerItemInfo, bag, slot)
        if not ok or type(info) ~= "table" then return nil end
        return Public(info.iconFileID), Public(info.stackCount), Public(info.isLocked),
            Public(info.quality), Public(info.hyperlink), Public(info.itemID),
            Public(info.isBound), Public(info.hasNoValue)
    end
    if GetContainerItemInfo then
        local ok, icon, count, locked, quality, _, _, link, _, noValue, itemID = pcall(GetContainerItemInfo, bag, slot)
        if not ok then return nil end
        return Public(icon), Public(count), Public(locked), Public(quality), Public(link), Public(itemID),
            nil, Public(noValue)
    end
end

-- isQuestItem, questID, isActive
function API.QuestInfo(bag, slot)
    local fn = Container.GetContainerItemQuestInfo or GetContainerItemQuestInfo
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, bag, slot)
    if not ok then return nil end
    if type(a) == "table" then a, b, c = a.isQuestItem, a.questID or a.questId, a.isActive end
    return Public(a), Public(b), Public(c)
end

function API.Cooldown(bag, slot)
    local fn = Container.GetContainerItemCooldown or GetContainerItemCooldown
    if not fn then return nil end
    local ok, start, duration, enable = pcall(fn, bag, slot)
    if not ok then return nil end
    return start, duration, enable
end

function API.IsNewItem(bag, slot)
    if not (C_NewItems and C_NewItems.IsNewItem) then return false end
    local ok, new = pcall(C_NewItems.IsNewItem, bag, slot)
    return ok and not IsSecret(new) and new == true
end

-- Name der Tasche (Rucksack hat keinen eigenen), roh oder nil
function API.BagName(bag)
    local fn = Container.GetBagName or GetBagName
    if not fn then return nil end
    local ok, name = pcall(fn, bag)
    if not ok or IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

do
    local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local cache = {}

    -- classID, subClassID, equipLoc (gecacht je Item-ID)
    function API.ItemClass(itemID, link)
        local key = itemID or link
        if not key or not GetInstant then return nil end
        local c = cache[key]
        if c == nil then
            local ok, _, _, _, equipLoc, _, classID, subClassID = pcall(GetInstant, key)
            if ok and not IsSecret(classID) and type(classID) == "number" then
                c = { classID, (not IsSecret(subClassID) and subClassID) or nil,
                    (not IsSecret(equipLoc) and equipLoc ~= "" and equipLoc) or nil }
            else
                c = false
            end
            cache[key] = c
        end
        if not c then return nil end
        return c[1], c[2], c[3]
    end
end

function API.QualityColor(q)
    if type(q) ~= "number" then return nil end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then return c.r, c.g, c.b end
    local fn = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if fn then
        local ok, r, g, b = pcall(fn, q)
        if ok and type(r) == "number" then return r, g, b end
    end
end

---------------------------------------------------------------------------
-- Hauptschalter
---------------------------------------------------------------------------

function B.Enabled()
    return ns.db ~= nil and ns.db.bagWindow == true
end

-- Gamepad-Oberfläche aktiv? Dann bedient Blizzard die Taschen selbst (stray hält sich raus).
function B.GamepadActive()
    local util = InputUtil
    if type(util) ~= "table" or type(util.IsGamepadUIEnabled) ~= "function" then return false end
    local ok, on = pcall(util.IsGamepadUIEnabled)
    return ok and not IsSecret(on) and on == true
end

---------------------------------------------------------------------------
-- Daten lesen
---------------------------------------------------------------------------

B.bags = {}
B.slots = {}
B.bagIDs = {}
B.used, B.total, B.free = 0, 0, 0
B.rev = 0 -- zählt jeden Scan

local function NameFromLink(link)
    if type(link) ~= "string" then return nil end
    return link:match("%[(.-)%]")
end

-- liest einen Platz in den Datensatz d (alle Felder werden gesetzt oder gelöscht)
function B.FillRecord(d, bag, slot)
    d.bag, d.slot = bag, slot
    local icon, count, locked, quality, link, itemID, bound, noValue = API.SlotInfo(bag, slot)
    d.icon, d.count, d.locked, d.quality, d.link, d.itemID, d.bound, d.noValue =
        icon, count, locked and true or false, quality, link, itemID, bound, noValue
    d.hasItem = (icon or link or itemID) and true or false
    d.displayCount = nil
    if not d.hasItem then
        d.name, d.nameLower, d.classID, d.subClassID, d.equipLoc = nil, nil, nil, nil, nil
        d.isNew, d.isQuest, d.questItem, d.questStarter, d.questNeeded = false, false, false, false, false
        d.linkKey = nil
        return d
    end
    if not itemID and link then
        local id = link:match("item:(%d+)")
        d.itemID = id and tonumber(id) or nil
        itemID = d.itemID
    end
    if d.linkKey ~= link or not d.name then
        d.linkKey = link
        d.name = NameFromLink(link)
        d.nameLower = d.name and d.name:lower() or nil
    end
    d.classID, d.subClassID, d.equipLoc = API.ItemClass(itemID, link)

    local isQuestItem, questID, isActive = API.QuestInfo(bag, slot)
    d.questStarter = (questID and not isActive) and true or false
    d.questItem = (d.classID == C.CL.quest or isQuestItem) and true or false
    d.questNeeded = false
    if ns.QuestForItemLink and link then
        local ok, quest = pcall(ns.QuestForItemLink, link)
        if ok and quest then d.questNeeded = true end
    end
    d.isQuest = d.questStarter or d.questItem or d.questNeeded
    d.isNew = API.IsNewItem(bag, slot)
    return d
end

local function BuildBagIDs()
    local ids = {}
    for bag = C.FIRST_BAG, C.LAST_BAG do ids[#ids + 1] = bag end
    if API.NumSlots(C.REAGENT_BAG) > 0 then ids[#ids + 1] = C.REAGENT_BAG end
    return ids
end

function B.Scan()
    local ids = BuildBagIDs()
    B.bagIDs = ids
    local used, total = 0, 0
    for _, bag in ipairs(ids) do
        local info = B.bags[bag]
        if not info then
            info = { bag = bag }
            B.bags[bag] = info
        end
        local n = API.NumSlots(bag)
        local free, family = API.FreeSlots(bag)
        info.size = n
        info.family = family or 0
        info.special = info.family ~= 0
        info.name = (bag ~= 0) and API.BagName(bag) or nil
        local list = B.slots[bag]
        if not list then
            list = {}
            B.slots[bag] = list
        end
        local usedHere = 0
        for slot = 1, n do
            local d = list[slot]
            if not d then
                d = {}
                list[slot] = d
            end
            B.FillRecord(d, bag, slot)
            if d.hasItem then usedHere = usedHere + 1 end
        end
        for slot = n + 1, #list do list[slot] = nil end
        info.used = usedHere
        info.free = n - usedHere
        if type(free) == "number" and free <= n then info.free = free end
        if not info.special then
            total = total + n
            used = used + usedHere
        end
    end
    -- Taschen, die es nicht mehr gibt
    for bag in pairs(B.bags) do
        local found = false
        for _, id in ipairs(ids) do if id == bag then found = true break end end
        if not found then B.bags[bag], B.slots[bag] = nil, nil end
    end
    B.used, B.total, B.free = used, total, total - used
    B.rev = B.rev + 1
end

function B.GetRecord(bag, slot)
    local list = B.slots[bag]
    return list and list[slot] or nil
end

function B.ForEachRecord(fn)
    for _, bag in ipairs(B.bagIDs) do
        local list = B.slots[bag]
        if list then
            for slot = 1, #list do fn(list[slot]) end
        end
    end
end

function B.BagTitle(bag)
    if bag == 0 then return L["Rucksack"] end
    local info = B.bags[bag]
    local name = info and info.name
    if name then return name end
    return L["Tasche"] .. " " .. bag
end

---------------------------------------------------------------------------
-- Ansichten und Abschnitte
---------------------------------------------------------------------------

B.views = {}
B.viewOrder = {}

function B.RegisterView(key, def)
    if type(key) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return end
    def.key = key
    if not B.views[key] then B.viewOrder[#B.viewOrder + 1] = key end
    B.views[key] = def
end

function B.GetView(key)
    return B.views[key] or B.views.multibag
end

local function Collapsed(key)
    local t = ns.db and ns.db.bagCollapsed
    return type(t) == "table" and t[key] == true
end

local function ToggleCollapsed(section)
    if not (ns.db and type(ns.db.bagCollapsed) == "table") then return end
    local key = section.key
    ns.db.bagCollapsed[key] = (not ns.db.bagCollapsed[key]) or nil
end

-- Datensätze einer Tasche in belegt/leer trennen
local function SplitBag(bag, items, empties)
    local list = B.slots[bag]
    if not list then return end
    for slot = 1, #list do
        local d = list[slot]
        if d.hasItem then items[#items + 1] = d else empties[#empties + 1] = d end
    end
end

local function BagSection(bag)
    local info = B.bags[bag]
    local items, empties = {}, {}
    SplitBag(bag, items, empties)
    local size = info and info.size or (#items + #empties)
    return {
        key = "bag" .. bag, bag = bag, special = info and info.special or false,
        title = B.BagTitle(bag), counter = string.format("(%d / %d)", #items, size),
        items = items, empties = empties, emptySlots = 0,
        collapsible = true, collapsed = Collapsed("bag" .. bag), onToggle = ToggleCollapsed,
    }
end

B.RegisterView("multibag", {
    label = "Pro Tasche",
    build = function()
        local sections = {}
        for _, bag in ipairs(B.bagIDs) do
            local info = B.bags[bag]
            if info and info.size > 0 then sections[#sections + 1] = BagSection(bag) end
        end
        return sections
    end,
})

B.RegisterView("onebag", {
    label = "Eine Tasche",
    build = function()
        local sections = {}
        local items, empties, size = {}, {}, 0
        for _, bag in ipairs(B.bagIDs) do
            local info = B.bags[bag]
            if info and info.size > 0 then
                if info.special then
                    sections[#sections + 1] = BagSection(bag)
                else
                    SplitBag(bag, items, empties)
                    size = size + info.size
                end
            end
        end
        table.insert(sections, 1, {
            key = "all", title = L["Inventar"], counter = string.format("(%d / %d)", #items, size),
            items = items, empties = empties, emptySlots = 0, noHeader = true,
        })
        return sections
    end,
})

function B.BuildSections()
    local view = B.GetView(ns.db and ns.db.bagView)
    local ok, sections = pcall(view.build)
    if not ok or type(sections) ~= "table" then
        if not ok then geterrorhandler()(sections) end
        sections = B.views.multibag.build()
    end
    return sections
end

---------------------------------------------------------------------------
-- Aktualisierung (gebündelt)
---------------------------------------------------------------------------

local callbacks = {}
local reasons = {}
local pending = false

function B.OnRefresh(fn)
    callbacks[#callbacks + 1] = fn
end

function B.Refresh(reason)
    if not B.Enabled() then return end
    if reason then reasons[reason] = true end
    local ok, err = pcall(B.Scan)
    if not ok then geterrorhandler()(err) end
    for _, fn in ipairs(callbacks) do
        local ok2, err2 = pcall(fn, reasons)
        if not ok2 then geterrorhandler()(err2) end
    end
    wipe(reasons)
end

function B.RequestRefresh(delay, reason)
    if not B.Enabled() then return end
    if reason then reasons[reason] = true end
    if pending then return end
    pending = true
    C_Timer.After(delay or 0.03, function()
        pending = false
        B.Refresh()
    end)
end

---------------------------------------------------------------------------
-- Knopf-Vorrat: echte Blizzard-Itemknöpfe, Eltern-ID = Tasche, Knopf-ID = Platz.
-- Fremde Daten stehen nicht auf den Knöpfen, sondern in schwachen Tabellen.
---------------------------------------------------------------------------

B.host = CreateFrame("Frame", "strayBagHost", UIParent) -- das Fenster hängt ihn später um
B.host:SetSize(10, 10)

local state = setmetatable({}, { __mode = "k" }) -- [Knopf] = { bag, slot, extra }
local buttons = {}      -- [bag][slot] = Knopf
local extras = {}       -- [Nummer] = Zusatzknopf
local containers = {}   -- [bag] = Elternrahmen
local createdFns = {}
local broken, needWarm = false, false

local function Container(bag)
    local c = containers[bag]
    if c then return c end
    c = CreateFrame("Frame", "strayBagContainer" .. bag, B.host)
    c:SetAllPoints(B.host)
    c:SetID(bag)
    -- Neuere Vorlagen fragen den Elternrahmen; eigene Rahmen, keine Blizzard-Tabellen
    c.GetBagID = function(self) return self:GetID() end
    c.IsCombinedBagContainer = function() return false end
    containers[bag] = c
    return c
end

local function CreateButton(bag, slot, name, parent)
    local b
    for _, kind in ipairs({ "ItemButton", "Button" }) do
        local ok, result = pcall(CreateFrame, kind, name, parent, "ContainerFrameItemButtonTemplate")
        if ok and result then b = result break end
    end
    if not b then
        if not broken then
            broken = true
            ns.Print(L["Taschenfenster: Blizzards Taschenknopf-Vorlage fehlt – es bleiben Blizzards Taschen."])
        end
        return nil
    end
    -- Die Taschen-ID kommt aus dem Elternrahmen (GetBagID fällt darauf zurück). Bewusst kein SetBagID:
    -- das schreibt über ein Attribut einen Wert, der von unserem Code stammt, in Blizzards Knopf und
    -- würde jede Gegenstands-Aktion (Benutzen, Verkaufen) als „tainted“ markieren.
    b:SetID(slot)
    local st = { bag = bag, slot = slot }
    state[b] = st
    -- „Neu“-Markierung: Blizzard entfernt sie beim Daraufzeigen, danach neu zeichnen
    b:HookScript("OnLeave", function(self)
        local s = state[self]
        local rec = s and B.GetRecord(s.bag, s.slot)
        if rec and rec.isNew and B.Enabled() then B.RequestRefresh(0.1, "new") end
    end)
    b:Hide()
    for _, fn in ipairs(createdFns) do
        local ok, err = pcall(fn, b, st)
        if not ok then geterrorhandler()(err) end
    end
    return b
end

function B.OnButtonCreated(fn)
    createdFns[#createdFns + 1] = fn
    for b, st in pairs(state) do pcall(fn, b, st) end
end

function B.ForEachButton(fn)
    for b, st in pairs(state) do fn(b, st) end
end

function B.ButtonState(btn)
    return state[btn]
end

function B.AcquireButton(bag, slot, extra)
    if broken then return nil end
    if extra and extra > 1 then
        local b = extras[extra - 1]
        if not b then
            if InCombatLockdown() then needWarm = true return nil end
            b = CreateButton(bag, slot, "strayBagExtra" .. (extra - 1), Container(bag))
            if not b then return nil end
            state[b].extra = extra - 1
            extras[extra - 1] = b
        end
        local st = state[b]
        if st.bag ~= bag or st.slot ~= slot then
            if InCombatLockdown() then return nil end
            -- Taschen-ID = ID des Elternrahmens (kein SetBagID, siehe CreateButton)
            local cont = Container(bag)
            if b:GetParent() ~= cont then pcall(b.SetParent, b, cont) end
            b:SetID(slot)
            st.bag, st.slot = bag, slot
        end
        return b
    end
    local list = buttons[bag]
    if not list then
        list = {}
        buttons[bag] = list
    end
    local b = list[slot]
    if b then return b end
    if InCombatLockdown() then needWarm = true return nil end
    b = CreateButton(bag, slot, "strayBagItem" .. bag .. "_" .. slot, Container(bag))
    list[slot] = b
    return b
end

function B.ReleaseButton(btn)
    if not btn or InCombatLockdown() then return false end
    if btn:IsShown() then pcall(btn.Hide, btn) end
    return true
end

-- Alle Knöpfe für die aktuell vorhandenen Plätze anlegen (nicht im Kampf)
function B.WarmPool()
    if broken then return false end
    if InCombatLockdown() then
        needWarm = true
        return false
    end
    needWarm = false
    for _, bag in ipairs(BuildBagIDs()) do
        for slot = 1, API.NumSlots(bag) do
            if not B.AcquireButton(bag, slot) then return false end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Übernahme von Blizzards Taschen
-- Blizzards Rahmen werden per SetParent unter einen versteckten Rahmen gehängt (keine Blizzard-
-- Funktionen werden ersetzt, nur hooksecurefunc/HookScript). Schlüsselring bleibt Blizzards Fenster.
-- Im Kampf kann das Fenster nicht aufgehen (geschützte Knöpfe): dann bekommt Blizzard seine Rahmen
-- beim Kampfbeginn zurück (PLAYER_REGEN_DISABLED kommt noch vor der Sperre) und nach dem Kampf wieder weg.
---------------------------------------------------------------------------

local park = CreateFrame("Frame", nil, UIParent)
park:SetAllPoints(UIParent)
park:Hide()

local origParent = setmetatable({}, { __mode = "k" })
local takeover = false -- Übernahme aktiv (Hauptschalter an und Hooks installiert)
local suppress = false

local function ForEachBlizzard(fn)
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then fn(f) end
    end
    if ContainerFrameCombinedBags then fn(ContainerFrameCombinedBags) end
end

local function IsKeyring(f)
    local ok, id = pcall(function() return f.GetBagID and f:GetBagID() or f:GetID() end)
    if not ok or IsSecret(id) or type(id) ~= "number" then return false end
    return C.KEYRING ~= nil and id == C.KEYRING
end

local function ParkFrame(f)
    if InCombatLockdown() then return end
    local ok, parent = pcall(f.GetParent, f)
    if not ok or parent == park then return end
    origParent[f] = origParent[f] or parent or UIParent
    pcall(f.SetParent, f, park)
end

local function UnparkFrame(f)
    if InCombatLockdown() then return end
    local ok, parent = pcall(f.GetParent, f)
    if not ok or parent ~= park then return end
    pcall(f.SetParent, f, origParent[f] or ContainerFrameContainer or UIParent)
end

-- Schlüsselring bleibt sichtbar, alles andere hängt am versteckten Rahmen. Bewusst kein Hide() auf
-- Blizzards Rahmen (deren OnHide würde im Taint-Kontext laufen): Blizzards Öffnen/Schließen-Zustand
-- läuft unsichtbar weiter, das Umschalten entscheidet allein der Zustand des stray-Fensters.
local function ParkBlizzardBags()
    if InCombatLockdown() or B.GamepadActive() then return end
    suppress = true
    ForEachBlizzard(function(f)
        if IsKeyring(f) then UnparkFrame(f) else ParkFrame(f) end
    end)
    suppress = false
end

function B.ApplyTakeover()
    if InCombatLockdown() then return end
    if B.Enabled() and takeover and not B.GamepadActive() then
        ParkBlizzardBags()
    else
        ForEachBlizzard(UnparkFrame)
    end
end

-- Kann das stray-Fenster jetzt übernehmen? (Fenster stellt B.CanShow bereit)
local function Usable()
    return B.Enabled() and takeover and not B.GamepadActive() and B.CanShow ~= nil and B.CanShow() and true or false
end

-- Verschachtelte Aufrufe (ToggleAllBags ruft OpenBackpack …): der äußere Hook kommt zuletzt und
-- gewinnt; ausgewertet wird im nächsten Frame – so schaltet ein Tastendruck genau einmal um.
local intent, intentName

local function SafeName(f)
    if not f or not f.GetName then return nil end
    local ok, name = pcall(f.GetName, f)
    return ok and name or nil
end

local function Resolve()
    local action, name = intent, intentName
    intent, intentName = nil, nil
    if not action or not B.Enabled() then return end
    local shown = B.IsOpen()
    if action == "toggle" then
        action = shown and "hide" or "show"
    elseif action == "openBy" then
        -- bag_auto.lua: je Fenster abschaltbar; „Taschen nicht automatisch öffnen“ hat Vorrang
        local allowed = true
        if B.AutoAllowed then
            local ok, result = pcall(B.AutoAllowed, name)
            allowed = not ok or result ~= false
        end
        if not shown and allowed and B.Open() then B.openerName = name end
        return
    elseif action == "closeBy" then
        if shown and name and name == B.openerName then B.Close() end
        return
    end
    if action == "show" then
        if not shown then B.Open() end
    elseif action == "hide" then
        if shown then B.Close() end
    end
end

local function Request(action, name)
    if suppress or not Usable() then return end
    ParkBlizzardBags()
    if not intent then C_Timer.After(0, Resolve) end
    intent, intentName = action, name
end

local function InstallHooks()
    local function Hook(fnName, handler)
        if type(_G[fnName]) == "function" then
            hooksecurefunc(fnName, function(...) pcall(handler, ...) end)
        end
    end
    local function InRange(id)
        if IsSecret(id) or type(id) ~= "number" then return false end
        return id >= C.FIRST_BAG and id <= C.REAGENT_BAG
    end
    Hook("ToggleAllBags", function() Request("toggle") end)
    Hook("OpenAllBags", function(opener)
        local name = type(opener) == "table" and SafeName(opener) or nil
        if name then Request("openBy", name) else Request("show") end
    end)
    Hook("CloseAllBags", function(opener)
        if type(opener) == "table" then
            -- Wie Blizzard: nur schließen, wenn dieser Rahmen die Taschen geöffnet hat
            Request("closeBy", SafeName(opener))
        else
            Request("hide")
        end
    end)
    Hook("ToggleBackpack", function() Request("toggle") end)
    Hook("OpenBackpack", function() Request("show") end)
    Hook("CloseBackpack", function() Request("hide") end)
    Hook("ToggleBag", function(id) if InRange(id) then Request("toggle") end end)

    -- Auffangnetz: Taschen, die ohne diese Funktionen aufgehen (z. B. OpenBag direkt)
    local function OnBlizzardShow(self)
        if suppress or not Usable() or IsKeyring(self) then return end
        if not intent then Request("show") end
        C_Timer.After(0, function() if Usable() then ParkBlizzardBags() end end)
    end
    ForEachBlizzard(function(f)
        if f.HookScript then f:HookScript("OnShow", OnBlizzardShow) end
    end)
    takeover = true
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    local ok, err = pcall(InstallHooks)
    if not ok then geterrorhandler()(err) end
    if B.Enabled() then
        B.WarmPool()
        B.ApplyTakeover()
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    -- Knöpfe vorab außerhalb des Kampfes anlegen, damit das Fenster auch im Kampf aufgeht
    C_Timer.After(2, function()
        if B.Enabled() and not InCombatLockdown() then
            B.WarmPool()
            B.ApplyTakeover()
        end
    end)
end)

ns.On("PLAYER_REGEN_DISABLED", function()
    -- Fenster zu: Blizzard bekommt seine Taschen für den Kampf zurück (noch vor der Sperre)
    if not (B.Enabled() and takeover) or B.IsOpen() then return end
    pcall(function()
        ForEachBlizzard(function(f)
            if not IsKeyring(f) then
                -- noch unsichtbar „offene“ Rahmen schließen, damit sie nicht plötzlich im Kampf erscheinen
                if f:IsShown() then pcall(f.Hide, f) end
                UnparkFrame(f)
            end
        end)
    end)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if not B.Enabled() then return end
    if needWarm then B.WarmPool() end
    B.ApplyTakeover()
    B.RequestRefresh(0, "combat")
end)

-- Gamepad-Oberfläche an/aus: Blizzards Taschen zurückgeben bzw. wieder übernehmen
do
    local pad = CreateFrame("Frame")
    for _, event in ipairs({ "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED" }) do
        pcall(pad.RegisterEvent, pad, event)
    end
    pad:SetScript("OnEvent", function()
        C_Timer.After(0.2, function()
            if not B.Enabled() then return end
            if B.GamepadActive() and B.IsOpen() then B.Close() end
            B.ApplyTakeover()
        end)
    end)
end

ns.On("BAG_UPDATE", function() B.RequestRefresh(0.05, "bag") end)
ns.On("BAG_UPDATE_DELAYED", function() B.RequestRefresh(0.02, "bag") end)
ns.On("ITEM_LOCK_CHANGED", function() B.RequestRefresh(0.02, "lock") end)
ns.On("BAG_UPDATE_COOLDOWN", function() B.RequestRefresh(0.1, "cooldown") end)
ns.On("QUEST_LOG_UPDATE", function() B.RequestRefresh(0.5, "quest") end)
do
    -- Quest abgegeben/abgebrochen: questitems.lua baut seine Liste nach 0,2 s neu, danach einordnen
    local function AfterQuestGone() C_Timer.After(0.6, function() B.RequestRefresh(0, "quest") end) end
    ns.On("QUEST_TURNED_IN", AfterQuestGone)
    ns.On("QUEST_REMOVED", AfterQuestGone)
end
-- Ereignisse, die es nicht in jedem Client gibt
do
    local optional = CreateFrame("Frame")
    for _, event in ipairs({ "BAG_NEW_ITEMS_UPDATED", "BAG_CONTAINER_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }) do
        pcall(optional.RegisterEvent, optional, event)
    end
    optional:SetScript("OnEvent", function(_, event)
        B.RequestRefresh(0.1, event == "PLAYER_EQUIPMENT_CHANGED" and "bag" or "new")
    end)
end
-- Optionen wie „Questgegenstände markieren“ wirken sofort
ns.OnConfig(function() B.RequestRefresh(0, "config") end)

---------------------------------------------------------------------------
-- Optionen (Bereich „Tasche“)
---------------------------------------------------------------------------

local function On()
    return ns.db and ns.db.bagWindow and true or false
end

local DISABLED_HINT = L["Erst „stray-Tasche“ einschalten (weiter oben)."]

ns.AddOption(1, "Tasche", {
    key = "bagWindow",
    label = L["stray-Tasche"],
    tooltip = L["Ersetzt Blizzards Taschen durch ein eigenes Fenster: alle Taschen mit Suche, Abschnitten und Platz-Anzeige. B-Taste, Rucksack-Knopf und Händler öffnen dann dieses Fenster. Der Schlüsselring bleibt bei Blizzard.\n\nKopfzeile ziehen verschiebt das Fenster, der Griff unten rechts ändert die Größe (Breite in Spalten). Im Kampf kann das Fenster nicht aufgehen – dann zeigt WoW seine eigenen Taschen.\n\nAusschalten wirkt sofort; ganz sauber wird es nach Neuladen (/reload)."],
    keywords = { "tasche", "taschen", "inventar", "rucksack", "bags", "bag", "inventory", "backpack", "stray-tasche" },
    set = function(value)
        ns.db.bagWindow = value
        if value then
            B.WarmPool()
            B.ApplyTakeover()
            B.RequestRefresh(0, "config")
        else
            if B.IsOpen() then B.Close() end
            B.ApplyTakeover()
        end
    end,
})

ns.AddOption(1, "Tasche", {
    key = "bagView",
    type = "choice",
    label = L["Ansicht"],
    values = { "multibag", "onebag", "categories" },
    labels = { L["Pro Tasche"], L["Eine Tasche"], L["Kategorien"] },
    tooltip = L["„Pro Tasche“: je Tasche ein Abschnitt. „Eine Tasche“: alle normalen Taschen in einem Raster. „Kategorien“: nach Art der Gegenstände gruppiert."],
    keywords = { "ansicht", "kategorien", "view", "categories", "one bag", "multibag" },
    isEnabled = On,
    disabledHint = DISABLED_HINT,
    set = function(value)
        ns.db.bagView = value
        if B.RequestLayout then B.RequestLayout() end
    end,
})

ns.AddOption(1, "Tasche", {
    key = "bagColumns",
    type = "slider",
    label = L["Spalten"],
    min = C.MIN_COLS, max = C.MAX_COLS, step = 1,
    tooltip = L["Wie viele Plätze nebeneinander stehen. Ziehst du das Fenster unten rechts breiter oder schmaler, ändert sich dieser Wert mit."],
    keywords = { "spalten", "breite", "columns", "width" },
    isEnabled = On,
    disabledHint = DISABLED_HINT,
    set = function(value)
        ns.db.bagColumns = value
        if B.RequestLayout then B.RequestLayout() end
    end,
})

ns.AddOption(1, "Tasche", {
    key = "bagSlotSize",
    type = "slider",
    label = L["Feldgröße"],
    min = C.MIN_SLOT, max = C.MAX_SLOT, step = 1, unit = " px",
    tooltip = L["Größe der einzelnen Gegenstandsfelder in Pixeln. Standard: 36."],
    keywords = { "größe", "felder", "slot", "size", "icons" },
    isEnabled = On,
    disabledHint = DISABLED_HINT,
    set = function(value)
        ns.db.bagSlotSize = value
        if B.RequestLayout then B.RequestLayout() end
    end,
})

ns.AddOption(1, "Tasche", {
    key = "bagLocked",
    label = L["Fenster sperren"],
    tooltip = L["Das Taschenfenster lässt sich dann nicht verschieben und seine Größe nicht ändern. Das Schloss unten im Fenster schaltet dasselbe."],
    keywords = { "sperren", "schloss", "fixieren", "lock", "locked" },
    isEnabled = On,
    disabledHint = DISABLED_HINT,
    set = function(value)
        ns.db.bagLocked = value
        if B.RequestPaint then B.RequestPaint() end
    end,
})

ns.AddOption(1, "Tasche", {
    key = "bagMerge",
    label = L["Gleiche Gegenstände zusammenfassen"],
    tooltip = L["Fasst in der Ansicht „Kategorien“ gleiche Gegenstände auf einem Feld zusammen und zeigt die Gesamtzahl."],
    keywords = { "zusammenfassen", "stapel", "merge", "stack", "gleiche" },
    isEnabled = On,
    disabledHint = DISABLED_HINT,
    set = function(value)
        ns.db.bagMerge = value
        if B.RequestLayout then B.RequestLayout() end
    end,
})
