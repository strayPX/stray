-- stray – stray-Tasche: Kategorien (Ansicht „Kategorien“, Anheften, Zuletzt erhalten, eigene Kategorien)
--
-- Öffentliche Tabelle: B.Categories (B = ns.Bag). Die Ansicht „categories“ liefert diese Abschnitte
-- (Reihenfolge einstellbar): Angeheftet, Zuletzt erhalten, Rüstkammer, Abenteuer-Vorrat, Handwerkswaren,
-- Verschiedenes, Quest-Items, Schrott und eigene Kategorien; danach immer Spezialtaschen, Freie Plätze
-- und „Kategorie hinzufügen“.
--
--   B.Categories.List()          geordnete Liste der sichtbaren Kategorien { key, title, icon, count, custom }
--                                (Tabellen werden wiederverwendet; count stammt vom letzten Aufbau der Ansicht,
--                                 für aktuelle Zahlen nach B.OnRefresh lesen)
--   B.Categories.SetFilter(key)  nur diesen Abschnitt zeigen (nil = „Alle“); B.Categories.GetFilter()
--   B.Categories.CategoryOf(rec) Schlüssel der festen/eigenen Kategorie eines Datensatzes (ohne Angeheftet/Spezial)
--   B.Categories.OnChanged(fn)   fn() bei jeder Änderung der Struktur (Reihenfolge, Anheften, Zuweisung, Filter …)
--   B.Categories.Title(key)      Anzeigename einer Kategorie
--   B.IsJunk(rec)                Schrott: graue Gegenstände oder per ns.db.bagJunkMarks[itemID] = true markiert
--                                (= false schützt einen grauen Gegenstand); nur definiert, wenn noch nicht vorhanden
-- Gespeichert: ns.db.bagPins = { [itemID] = Reihenfolge },
--   ns.db.bagCats = { order = { Schlüssel … }, custom = { [id] = { name, icon, items = {[itemID]=true}, hideInAll } },
--   hidden = { [Schlüssel] = true } }

local _, ns = ...
local L = ns.L
local B = ns.Bag
local IsSecret = ns.IsSecret

local Cat = {}
B.Categories = Cat

ns.defaults.bagPins = {}
ns.defaults.bagCats = {}
ns.defaults.bagJunkMarks = {}
ns.defaults.bagShowPinned = true
ns.defaults.bagHidePinnedInCategories = true
ns.defaults.bagShowRecent = false
ns.defaults.bagArmoryBySlot = false
ns.defaults.bagShowAllEmpty = false
ns.defaults.bagHideAddCategory = false

---------------------------------------------------------------------------
-- Konstanten
---------------------------------------------------------------------------

local ICON = "Interface\\Icons\\"
local MAX_RECENT = 15

-- feste Abschnitte in Standardreihenfolge (Spezialtaschen, Freie Plätze und „hinzufügen“ stehen immer am Ende)
local FIXED_ORDER = { "pinned", "recent", "armory", "prep", "trade", "misc", "quest", "junk" }
local FIXED = {}
for _, k in ipairs(FIXED_ORDER) do FIXED[k] = true end

local TITLES = {
    pinned = "Angeheftet", recent = "Zuletzt erhalten", armory = "Rüstkammer", prep = "Abenteuer-Vorrat",
    trade = "Handwerkswaren", misc = "Verschiedenes", quest = "Quest-Items", junk = "Schrott",
    special = "Spezialtaschen", free = "Freie Plätze", addcat = "Kategorie hinzufügen",
}
local ICONS = {
    pinned = "INV_Misc_Note_01", recent = "INV_Misc_Bag_08", armory = "INV_Chest_Chain", prep = "INV_Potion_54",
    trade = "INV_Fabric_Linen_01", misc = "INV_Misc_Bag_08", quest = "INV_Misc_QuestionMark",
    junk = "INV_Misc_Coin_02", special = "INV_Misc_Bag_08", free = "INV_Misc_Bag_08",
}
local DEFAULT_CUSTOM_ICON = "INV_Misc_QuestionMark"

-- Ausrüstungsplätze für „Rüstkammer nach Platz“: { Gruppe, Name, equipLocs … }
local SLOTS = {
    { "head", "Kopf", "INVTYPE_HEAD" },
    { "neck", "Hals", "INVTYPE_NECK" },
    { "shoulder", "Schulter", "INVTYPE_SHOULDER" },
    { "back", "Rücken", "INVTYPE_CLOAK" },
    { "chest", "Brust", "INVTYPE_CHEST", "INVTYPE_ROBE" },
    { "shirt", "Hemd", "INVTYPE_BODY" },
    { "tabard", "Wappenrock", "INVTYPE_TABARD" },
    { "wrist", "Handgelenke", "INVTYPE_WRIST" },
    { "hands", "Hände", "INVTYPE_HAND" },
    { "waist", "Taille", "INVTYPE_WAIST" },
    { "legs", "Beine", "INVTYPE_LEGS" },
    { "feet", "Füße", "INVTYPE_FEET" },
    { "finger", "Finger", "INVTYPE_FINGER" },
    { "trinket", "Schmuck", "INVTYPE_TRINKET" },
    { "main", "Haupthand", "INVTYPE_WEAPONMAINHAND" },
    { "one", "Einhand", "INVTYPE_WEAPON" },
    { "two", "Zweihand", "INVTYPE_2HWEAPON" },
    { "off", "Nebenhand", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" },
    { "ranged", "Distanz", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" },
    { "other", "Sonstiges" },
}
local SLOT_OF = {}
for _, s in ipairs(SLOTS) do
    for i = 3, #s do SLOT_OF[s[i]] = s[1] end
end

local CLS = {}
do
    local IC = (Enum and Enum.ItemClass) or {}
    CLS.gem, CLS.projectile, CLS.recipe = IC.Gem or 3, IC.Projectile or 6, IC.Recipe or 9
end

-- Zustand (wiederverwendete Tabellen, damit pro Refresh kein Müll entsteht)
local S = {
    buck = {},              -- [Schlüssel] = Datensätze des Abschnitts
    secs = {},              -- [Schlüssel] = Abschnittstabelle
    out = {}, ord = {}, inord = {}, ids = {}, shown = {}, cnt = {},
    pool = {}, poolN = 0,   -- Kopien von Datensätzen (zusammengefasst, Zuletzt, Freie Plätze)
    seen = {}, first = {}, total = {},
    spEmpty = {}, free = {}, oneFree = {}, none = {}, listOut = {},
    ctr = {},               -- Zähler-Texte je Zahl
    have = {}, tmp = {},    -- Bestand je Item-ID (letzter / aktueller Scan)
    recent = {},            -- zuletzt erhaltene Item-IDs, neueste zuerst
    assign = {}, assignDirty = true,
    changed = {},
    filter = nil,
}

local function Opt(key, default)
    local v = ns.db and ns.db[key]
    if v == nil then return default end
    return v and true or false
end

local function Counter(n)
    local c = S.ctr[n]
    if not c then
        c = string.format("(%d)", n)
        S.ctr[n] = c
    end
    return c
end

local function Cats()
    local db = ns.db
    local c = db.bagCats
    if type(c) ~= "table" then
        c = {}
        db.bagCats = c
    end
    if type(c.order) ~= "table" then c.order = {} end
    if type(c.custom) ~= "table" then c.custom = {} end
    if type(c.hidden) ~= "table" then c.hidden = {} end
    if type(db.bagPins) ~= "table" then db.bagPins = {} end
    if type(db.bagCollapsed) ~= "table" then db.bagCollapsed = {} end
    return c
end

---------------------------------------------------------------------------
-- Schrott
---------------------------------------------------------------------------

if not B.IsJunk then
    function B.IsJunk(rec)
        if not rec or not rec.hasItem then return false end
        local id = rec.itemID
        local marks = ns.db and ns.db.bagJunkMarks
        if id and type(marks) == "table" then
            if marks[id] == true then return true end
            if marks[id] == false then return false end
        end
        return rec.quality == 0
    end
end

---------------------------------------------------------------------------
-- Änderungen melden
---------------------------------------------------------------------------

function Cat.OnChanged(fn)
    if type(fn) == "function" then S.changed[#S.changed + 1] = fn end
end

local function Changed()
    S.assignDirty = true
    for _, fn in ipairs(S.changed) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
    if B.RequestLayout then B.RequestLayout() end
    if ns.RefreshConfig then pcall(ns.RefreshConfig) end
end

---------------------------------------------------------------------------
-- Reihenfolge und Sichtbarkeit
---------------------------------------------------------------------------

-- Vollständige Reihenfolge (gespeicherte zuerst, Fehlendes ergänzt); Ergebnis wird wiederverwendet
local function OrderedKeys(c)
    local out, inord = S.ord, S.inord
    wipe(out)
    wipe(inord)
    for _, k in ipairs(c.order) do
        if not inord[k] and (FIXED[k] or c.custom[k]) then
            out[#out + 1] = k
            inord[k] = true
        end
    end
    for _, k in ipairs(FIXED_ORDER) do
        if not inord[k] then
            out[#out + 1] = k
            inord[k] = true
        end
    end
    local ids = S.ids
    wipe(ids)
    for id in pairs(c.custom) do
        if not inord[id] then ids[#ids + 1] = id end
    end
    if #ids > 0 then
        table.sort(ids)
        for _, id in ipairs(ids) do
            out[#out + 1] = id
            inord[id] = true
        end
    end
    return out
end

local function IsHidden(key)
    if key == "pinned" then return not Opt("bagShowPinned", true) end
    if key == "recent" then return not Opt("bagShowRecent", false) end
    return Cats().hidden[key] == true
end

local function Hide(key)
    if key == "pinned" then
        ns.db.bagShowPinned = false
    elseif key == "recent" then
        ns.db.bagShowRecent = false
    elseif key ~= "misc" then
        Cats().hidden[key] = true
    end
    if S.filter == key then S.filter = nil end
    Changed()
end

local function Unhide(key)
    if key == "pinned" then
        ns.db.bagShowPinned = true
    elseif key == "recent" then
        ns.db.bagShowRecent = true
    else
        Cats().hidden[key] = nil
    end
    Changed()
end

-- Nachbar in Richtung dir, der im letzten Aufbau sichtbar war
local function Neighbor(ord, idx, dir)
    local j = idx + dir
    while ord[j] and not S.shown[ord[j]] do j = j + dir end
    return ord[j] and j or nil
end

local function CanMove(key, dir)
    local ord = OrderedKeys(Cats())
    for i, k in ipairs(ord) do
        if k == key then return Neighbor(ord, i, dir) ~= nil end
    end
    return false
end

local function Move(key, dir)
    local c = Cats()
    local ord = OrderedKeys(c)
    for i, k in ipairs(ord) do
        if k == key then
            local j = Neighbor(ord, i, dir)
            if not j then return end
            ord[i], ord[j] = ord[j], ord[i]
            wipe(c.order)
            for n, name in ipairs(ord) do c.order[n] = name end
            Changed()
            return
        end
    end
end

---------------------------------------------------------------------------
-- Titel und Symbole
---------------------------------------------------------------------------

local function TitleOf(key)
    local custom = ns.db and ns.db.bagCats and ns.db.bagCats.custom and ns.db.bagCats.custom[key]
    if custom then return custom.name or L["Kategorie"] end
    local t = TITLES[key]
    return t and L[t] or tostring(key)
end
Cat.Title = TitleOf

local function IconOf(key)
    local custom = ns.db and ns.db.bagCats and ns.db.bagCats.custom and ns.db.bagCats.custom[key]
    if custom then return custom.icon or (ICON .. DEFAULT_CUSTOM_ICON) end
    return ICON .. (ICONS[key] or "INV_Misc_Bag_08")
end

---------------------------------------------------------------------------
-- Anheften und Zuweisen
---------------------------------------------------------------------------

local function Pin(id)
    Cats()
    local pins = ns.db.bagPins
    if pins[id] then return end
    local top = 0
    for _, v in pairs(pins) do
        if type(v) == "number" and v > top then top = v end
    end
    pins[id] = top + 1
    Changed()
end

local function Unpin(id)
    local pins = ns.db.bagPins
    if type(pins) == "table" and pins[id] then
        pins[id] = nil
        Changed()
    end
end

local function RebuildAssign(c)
    wipe(S.assign)
    for catId, def in pairs(c.custom) do
        if type(def.items) == "table" then
            for id in pairs(def.items) do S.assign[id] = catId end
        end
    end
    S.assignDirty = false
end

local function Assign(catId, id)
    local c = Cats()
    local def = c.custom[catId]
    if not def then return end
    for _, other in pairs(c.custom) do
        if type(other.items) == "table" then other.items[id] = nil end
    end
    if type(def.items) ~= "table" then def.items = {} end
    def.items[id] = true
    Changed()
end

local function Unassign(id)
    local c = Cats()
    local any = false
    for _, def in pairs(c.custom) do
        if type(def.items) == "table" and def.items[id] then
            def.items[id] = nil
            any = true
        end
    end
    if any then Changed() end
end

local function CursorItemID()
    if not GetCursorInfo then return nil end
    local ok, kind, id = pcall(GetCursorInfo)
    if ok and kind == "item" and not IsSecret(id) and type(id) == "number" then return id end
    return nil
end

local function ItemLabel(id)
    local rec
    for _, bag in ipairs(B.bagIDs) do
        local list = B.slots[bag]
        for i = 1, list and #list or 0 do
            if list[i].itemID == id then
                rec = list[i]
                break
            end
        end
        if rec then break end
    end
    return (rec and (rec.link or rec.name)) or L["Gegenstand"]
end

local function PlusPin()
    local id = CursorItemID()
    if not id then
        ns.Print(L["Nimm zuerst einen Gegenstand mit der Maus auf, dann drück +."])
        return
    end
    Pin(id)
    ClearCursor()
    ns.Print(L("%s angeheftet.", ItemLabel(id)))
end

local function PlusAssign(section)
    local id = CursorItemID()
    if not id then
        ns.Print(L["Nimm zuerst einen Gegenstand mit der Maus auf, dann drück +."])
        return
    end
    Assign(section.catKey, id)
    ClearCursor()
    ns.Print(L("%s zugewiesen.", ItemLabel(id)))
end

---------------------------------------------------------------------------
-- Kategorie-Bestimmung
---------------------------------------------------------------------------

local function ClassKey(rec)
    local cl = rec.classID
    if not cl then return "misc" end
    local CL = B.C.CL
    if cl == CL.weapon or cl == CL.armor then return "armory" end
    if cl == CL.consumable or cl == CLS.projectile then return "prep" end
    if cl == CL.trade or cl == CL.reagent or cl == CLS.recipe or cl == CLS.gem then return "trade" end
    return "misc"
end

function Cat.CategoryOf(rec)
    if not rec or not rec.hasItem then return nil end
    local c = Cats()
    if S.assignDirty then RebuildAssign(c) end
    local id = rec.itemID
    local custom = id and S.assign[id]
    if custom and c.custom[custom] then return custom end
    if (rec.isQuest or rec.classID == B.C.CL.quest) and not c.hidden.quest then return "quest" end
    if not c.hidden.junk and B.IsJunk(rec) then return "junk" end
    local key = ClassKey(rec)
    if key ~= "misc" and c.hidden[key] then key = "misc" end
    return key
end

---------------------------------------------------------------------------
-- Zuletzt erhalten (nur Speicher; Zuwachs der Gesamtzahl je Item-ID zwischen Scans)
---------------------------------------------------------------------------

local function PushRecent(id)
    local r = S.recent
    for i = #r, 1, -1 do
        if r[i] == id then table.remove(r, i) end
    end
    table.insert(r, 1, id)
    for i = #r, MAX_RECENT + 1, -1 do r[i] = nil end
end

local recentReady, haveBase = false, false

B.OnRefresh(function()
    local cur = S.tmp
    wipe(cur)
    for _, bag in ipairs(B.bagIDs) do
        local list = B.slots[bag]
        for i = 1, list and #list or 0 do
            local rec = list[i]
            local id = rec.itemID
            if rec.hasItem and id then
                local n = rec.count
                cur[id] = (cur[id] or 0) + ((type(n) == "number" and n > 0) and n or 1)
            end
        end
    end
    if recentReady and haveBase then
        for id, n in pairs(cur) do
            if n > (S.have[id] or 0) then PushRecent(id) end
        end
    end
    haveBase = true
    S.have, S.tmp = cur, S.have
end)

-- Der erste Scan nach dem Login (Taschen laden noch) zählt nicht
ns.On("PLAYER_ENTERING_WORLD", function()
    recentReady = false
    C_Timer.After(3, function() recentReady = true end)
end)

---------------------------------------------------------------------------
-- Datensatz-Kopien und Zusammenfassen
---------------------------------------------------------------------------

local function Synth(src)
    local n = S.poolN + 1
    S.poolN = n
    local t = S.pool[n]
    if not t then
        t = {}
        S.pool[n] = t
    else
        wipe(t)
    end
    for k, v in pairs(src) do t[k] = v end
    t.synthetic = true
    return t
end

local function Merge(items)
    if not Opt("bagMerge", false) then return end
    local seen = S.seen
    wipe(seen)
    local total, n = #items, 0
    for i = 1, total do
        local rec = items[i]
        local id = rec.itemID
        local at = id and seen[id]
        if at then
            local first = items[at]
            if not first.synthetic then
                first = Synth(first)
                items[at] = first
                first.displayCount = type(first.count) == "number" and first.count or 1
            end
            first.displayCount = (first.displayCount or 1) + ((type(rec.count) == "number") and rec.count or 1)
        else
            n = n + 1
            items[n] = rec
            if id then seen[id] = n end
        end
    end
    for i = n + 1, total do items[i] = nil end
end

local function Bucket(key)
    local t = S.buck[key]
    if not t then
        t = {}
        S.buck[key] = t
    end
    return t
end

local function PinSort(a, b)
    local pins = ns.db.bagPins
    local pa, pb = pins[a.itemID] or 0, pins[b.itemID] or 0
    if pa ~= pb then return pa < pb end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

---------------------------------------------------------------------------
-- Kontextmenüs und Eingabefenster
---------------------------------------------------------------------------

local MENU_FRAME

-- Menüdefinition: Liste von { text, func, sub = {…}, title = true, divider = true }
local function ShowMenu(owner, def)
    if MenuUtil and MenuUtil.CreateContextMenu then
        local function Fill(parent, list)
            for _, e in ipairs(list) do
                if e.divider then
                    if parent.CreateDivider then parent:CreateDivider() end
                elseif e.title then
                    if parent.CreateTitle then parent:CreateTitle(e.text) end
                elseif e.sub then
                    Fill(parent:CreateButton(e.text), e.sub)
                else
                    local fn = e.func
                    parent:CreateButton(e.text, function() pcall(fn) end)
                end
            end
        end
        local ok, err = pcall(MenuUtil.CreateContextMenu, owner, function(_, root) Fill(root, def) end)
        if not ok then geterrorhandler()(err) end
        return
    end
    if not EasyMenu then return end
    local function Convert(list)
        local out = {}
        for _, e in ipairs(list) do
            if e.divider then
                out[#out + 1] = { text = "", disabled = true, notCheckable = true }
            elseif e.title then
                out[#out + 1] = { text = e.text, isTitle = true, notCheckable = true }
            elseif e.sub then
                out[#out + 1] = { text = e.text, hasArrow = true, notCheckable = true, menuList = Convert(e.sub) }
            else
                local fn = e.func
                out[#out + 1] = { text = e.text, notCheckable = true, func = function() pcall(fn) end }
            end
        end
        return out
    end
    if not MENU_FRAME then
        MENU_FRAME = CreateFrame("Frame", "strayBagCategoryMenu", UIParent, "UIDropDownMenuTemplate")
    end
    pcall(EasyMenu, Convert(def), MENU_FRAME, "cursor", 0, 0, "MENU")
end

Cat.ShowMenu = ShowMenu -- auch für bag_sidebar.lua

local input -- laufende Eingabe: { mode, key, default, itemID }

local function GetEditBox(popup)
    return popup.editBox or popup.EditBox or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "EditBox"])
end

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NextCustomID(c)
    local n = tonumber(c.seq) or 0
    repeat n = n + 1 until not c.custom["c" .. n]
    c.seq = n
    return "c" .. n
end

local function CreateCategory(name, itemID)
    local c = Cats()
    local id = NextCustomID(c)
    c.custom[id] = { name = name, items = {}, hideInAll = false }
    local ord = OrderedKeys(c)
    local list = {}
    local placed = false
    for _, k in ipairs(ord) do
        if k == "quest" and not placed then
            list[#list + 1] = id
            placed = true
        end
        if k ~= id then list[#list + 1] = k end
    end
    if not placed then list[#list + 1] = id end
    wipe(c.order)
    for i, k in ipairs(list) do c.order[i] = k end
    if itemID then Assign(id, itemID) else Changed() end
end

local function Submit(text)
    local job = input
    input = nil
    if not job then return end
    text = Trim(text)
    local c = Cats()
    if job.mode == "new" then
        if text ~= "" then CreateCategory(text:sub(1, 40), job.itemID) end
    elseif job.mode == "rename" then
        local def = c.custom[job.key]
        if def and text ~= "" then
            def.name = text:sub(1, 40)
            Changed()
        end
    elseif job.mode == "icon" then
        local def = c.custom[job.key]
        if def then
            local n = tonumber(text)
            if n then
                def.icon = n
            elseif text == "" then
                def.icon = nil
            elseif text:find("\\", 1, true) or text:find("/", 1, true) then
                def.icon = text
            else
                def.icon = ICON .. text
            end
            Changed()
        end
    end
end

StaticPopupDialogs["STRAY_BAGCAT_INPUT"] = {
    text = "",
    button1 = ACCEPT or "OK",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 60,
    OnShow = function(self)
        local box = GetEditBox(self)
        if not box then return end
        box:SetText(input and input.default or "")
        box:HighlightText()
        box:SetFocus()
    end,
    OnAccept = function(self)
        local box = GetEditBox(self)
        Submit(box and box:GetText() or "")
    end,
    OnCancel = function() input = nil end,
    EditBoxOnEnterPressed = function(box)
        Submit(box:GetText())
        box:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(box)
        input = nil
        box:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local pendingDelete
StaticPopupDialogs["STRAY_BAGCAT_DELETE"] = {
    text = "",
    button1 = ACCEPT or "OK",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        local key = pendingDelete
        pendingDelete = nil
        local c = Cats()
        if not key or not c.custom[key] then return end
        c.custom[key] = nil
        for i = #c.order, 1, -1 do
            if c.order[i] == key then table.remove(c.order, i) end
        end
        ns.db.bagCollapsed[key] = nil
        if S.filter == key then S.filter = nil end
        Changed()
    end,
    OnCancel = function() pendingDelete = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function AskInput(mode, key, label, default, itemID)
    input = { mode = mode, key = key, default = default, itemID = itemID }
    local d = StaticPopupDialogs["STRAY_BAGCAT_INPUT"]
    d.text = label
    StaticPopup_Show("STRAY_BAGCAT_INPUT")
end

local function AskNewCategory(itemID)
    AskInput("new", nil, L["Name der neuen Kategorie:"], "", itemID)
end

local function AskDelete(key)
    local def = Cats().custom[key]
    if not def then return end
    pendingDelete = key
    local d = StaticPopupDialogs["STRAY_BAGCAT_DELETE"]
    d.text = L["Kategorie „%s“ wirklich löschen? Die Gegenstände kommen zurück in ihre normale Kategorie."]
    StaticPopup_Show("STRAY_BAGCAT_DELETE", def.name or "")
end

-- Menü einer Abschnitts-Überschrift (Rechtsklick)
local function SectionMenu(section, header)
    local key = section and section.catKey
    local c = Cats()
    if not key or not (FIXED[key] or c.custom[key]) then return end
    local def = c.custom[key]
    local menu = { { title = true, text = TitleOf(key) } }
    if def then
        menu[#menu + 1] = { text = L["Umbenennen"], func = function() AskInput("rename", key, L["Neuer Name:"], def.name or "") end }
        menu[#menu + 1] = { text = L["Symbol wählen"], func = function()
            AskInput("icon", key, L["Symbol (Icon-ID oder Name aus Interface\\Icons, leer = Standard):"], def.icon and tostring(def.icon) or "")
        end }
    end
    if CanMove(key, -1) then menu[#menu + 1] = { text = L["Nach oben"], func = function() Move(key, -1) end } end
    if CanMove(key, 1) then menu[#menu + 1] = { text = L["Nach unten"], func = function() Move(key, 1) end } end
    if def then
        menu[#menu + 1] = {
            text = def.hideInAll and L["In „Alle“ zeigen"] or L["In „Alle“ verstecken"],
            func = function()
                def.hideInAll = (not def.hideInAll) or nil
                Changed()
            end,
        }
        menu[#menu + 1] = { text = L["Löschen"], func = function() AskDelete(key) end }
    elseif key ~= "misc" then
        local label = (key == "pinned" or key == "recent") and L["Ausblenden"] or L["Ausblenden (Gegenstände unter Verschiedenes)"]
        menu[#menu + 1] = { text = label, func = function() Hide(key) end }
    end
    -- Ausgeblendete Abschnitte wieder zeigen
    local sub
    for _, k in ipairs(FIXED_ORDER) do
        if k ~= "misc" and IsHidden(k) then
            sub = sub or {}
            sub[#sub + 1] = { text = TitleOf(k), func = function() Unhide(k) end }
        end
    end
    if sub then
        menu[#menu + 1] = { divider = true }
        menu[#menu + 1] = { text = L["Ausgeblendete Abschnitte anzeigen"], sub = sub }
    end
    ShowMenu(header, menu)
end

-- Menü für einen Gegenstand (Shift- oder Alt-Rechtsklick auf einen Gegenstand ohne Anheften/Zuweisung)
local function ItemMenu(owner, id)
    local c = Cats()
    local menu = { { title = true, text = ItemLabel(id) } }
    menu[#menu + 1] = { text = L["Anheften"], func = function() Pin(id) end }
    local sub = {}
    for _, k in ipairs(OrderedKeys(c)) do
        if c.custom[k] then
            local key = k
            sub[#sub + 1] = { text = TitleOf(key), func = function() Assign(key, id) end }
        end
    end
    sub[#sub + 1] = { text = L["Neue Kategorie …"], func = function() AskNewCategory(id) end }
    menu[#menu + 1] = { text = L["Kategorie zuweisen"], sub = sub }
    ShowMenu(owner, menu)
end

-- Shift- oder Alt-Rechtsklick auf einen Gegenstandsknopf (nur HookScript, Blizzards Klick bleibt unberührt)
B.OnButtonCreated(function(btn)
    btn:HookScript("OnClick", function(self, mouse)
        if mouse ~= "RightButton" or not (IsShiftKeyDown() or IsAltKeyDown()) then return end
        if not B.Enabled() or not ns.db or ns.db.bagView ~= "categories" then return end
        local st = B.ButtonState(self)
        local rec = st and B.GetRecord(st.bag, st.slot)
        local id = rec and rec.hasItem and rec.itemID
        if not id then return end
        local name = rec.link or rec.name or L["Gegenstand"]
        if type(ns.db.bagPins) == "table" and ns.db.bagPins[id] then
            Unpin(id)
            ns.Print(L("%s gelöst.", name))
            return
        end
        if S.assignDirty then RebuildAssign(Cats()) end
        if S.assign[id] then
            Unassign(id)
            ns.Print(L("%s: Zuweisung entfernt.", name))
            return
        end
        ItemMenu(self, id)
    end)
end)

---------------------------------------------------------------------------
-- Abschnitte bauen
---------------------------------------------------------------------------

local function NewSection(key, catKey)
    local sec = S.secs[key]
    if not sec then
        sec = {}
        S.secs[key] = sec
    else
        wipe(sec)
    end
    sec.key, sec.catKey = key, catKey or key
    return sec
end

local function ToggleCollapsed(section)
    local t = ns.db and ns.db.bagCollapsed
    if type(t) ~= "table" then return end
    t[section.key] = (not t[section.key]) or nil
end

local function Finish(sec, title, items, count)
    sec.title = title
    sec.items = items
    sec.counter = Counter(count)
    sec.collapsible = true
    sec.collapsed = ns.db.bagCollapsed[sec.key] == true
    sec.onToggle = ToggleCollapsed
    sec.onContext = SectionMenu
    S.cnt[sec.catKey] = (S.cnt[sec.catKey] or 0) + count
    return sec
end

local PINNED_BUTTON = {
    text = "Ausblenden",
    tooltip = "Blendet den Abschnitt aus. Wieder einblenden: Rechtsklick auf eine Überschrift, „Ausgeblendete Abschnitte anzeigen“ (oder in den Optionen).",
    onClick = function() Hide("pinned") end,
}
local RECENT_BUTTON = {
    text = "Ausblenden",
    tooltip = "Blendet den Abschnitt aus. Wieder einblenden: Rechtsklick auf eine Überschrift, „Ausgeblendete Abschnitte anzeigen“ (oder in den Optionen).",
    onClick = function() Hide("recent") end,
}

local function Show(out, sec)
    out[#out + 1] = sec
    S.shown[sec.catKey] = true
end

local function Classify()
    for _, t in pairs(S.buck) do wipe(t) end
    wipe(S.spEmpty)
    wipe(S.free)
    wipe(S.first)
    wipe(S.total)
    local pins = ns.db.bagPins
    local showPinned = Opt("bagShowPinned", true)
    local hidePinned = Opt("bagHidePinnedInCategories", true)
    local bySlot = Opt("bagArmoryBySlot", false)
    local pinned, special = Bucket("pinned"), Bucket("special")
    for _, bag in ipairs(B.bagIDs) do
        local info, list = B.bags[bag], B.slots[bag]
        if info and list then
            for slot = 1, #list do
                local rec = list[slot]
                if info.special then
                    if rec.hasItem then special[#special + 1] = rec else S.spEmpty[#S.spEmpty + 1] = rec end
                elseif not rec.hasItem then
                    S.free[#S.free + 1] = rec
                else
                    local id = rec.itemID
                    if id then
                        if not S.first[id] then S.first[id] = rec end
                        S.total[id] = (S.total[id] or 0) + ((type(rec.count) == "number") and rec.count or 1)
                    end
                    local isPinned = showPinned and id and pins[id] ~= nil
                    if isPinned then pinned[#pinned + 1] = rec end
                    if not (isPinned and hidePinned) then
                        local key = Cat.CategoryOf(rec)
                        if key == "armory" and bySlot then
                            key = "armory_" .. (SLOT_OF[rec.equipLoc or ""] or "other")
                        end
                        local t = Bucket(key)
                        t[#t + 1] = rec
                    end
                end
            end
        end
    end
    table.sort(pinned, PinSort)
end

local function AddCustom(out, key, def, filtered)
    local items = Bucket(key)
    Merge(items)
    local sec = NewSection(key)
    Finish(sec, def.name or L["Kategorie"], items, #items)
    if def.hideInAll and not filtered then return end
    sec.plus = true
    sec.onPlus = PlusAssign
    sec.plusTooltip = "Gegenstand aufnehmen, dann + drücken, um ihn dieser Kategorie zuzuweisen"
    Show(out, sec)
end

local function AddArmory(out)
    if not Opt("bagArmoryBySlot", false) then
        local items = Bucket("armory")
        if #items == 0 then return end
        Merge(items)
        Show(out, Finish(NewSection("armory"), TitleOf("armory"), items, #items))
        return
    end
    for _, s in ipairs(SLOTS) do
        local items = Bucket("armory_" .. s[1])
        if #items > 0 then
            Merge(items)
            local sec = NewSection("armory_" .. s[1], "armory")
            Show(out, Finish(sec, TitleOf("armory") .. " – " .. L[s[2]], items, #items))
        end
    end
end

local function AddRecent(out)
    local list = Bucket("recent")
    wipe(list)
    for _, id in ipairs(S.recent) do
        local first = S.first[id]
        if first then
            local rec = Synth(first)
            rec.displayCount = S.total[id]
            list[#list + 1] = rec
        end
    end
    if #list == 0 then return end
    local sec = NewSection("recent")
    sec.headerButton = RECENT_BUTTON
    Show(out, Finish(sec, TitleOf("recent"), list, #list))
end

local function AddSpecial(out)
    local items = Bucket("special")
    local nEmpty = #S.spEmpty
    if #items == 0 and nEmpty == 0 then return end
    Merge(items)
    local sec = NewSection("special")
    Finish(sec, TitleOf("special"), items, #items)
    sec.empties = S.spEmpty
    sec.counter = string.format("(%d / %d)", #items, #items + nEmpty)
    Show(out, sec)
end

local function AddFree(out)
    local n = #S.free
    if n == 0 then return end
    local sec = NewSection("free")
    Finish(sec, TitleOf("free"), S.none, n)
    if Opt("bagShowAllEmpty", false) then
        sec.empties = S.free
    else
        -- ein Feld mit der Zahl der freien Plätze (echter leerer Platz, Zähler als Text)
        local one = Synth(S.free[1])
        one.displayCount = n
        wipe(S.oneFree)
        S.oneFree[1] = one
        sec.empties = S.oneFree
    end
    Show(out, sec)
end

local function Build()
    local c = Cats()
    if S.assignDirty then RebuildAssign(c) end
    S.poolN = 0
    wipe(S.cnt)
    wipe(S.shown)
    local out = S.out
    wipe(out)
    Classify()
    local filter = S.filter

    for _, key in ipairs(OrderedKeys(c)) do
        if key == "pinned" then
            if Opt("bagShowPinned", true) then
                local items = Bucket("pinned")
                Merge(items)
                local sec = NewSection("pinned")
                sec.plus = true
                sec.onPlus = PlusPin
                sec.plusTooltip = "Gegenstand aufnehmen, dann + drücken, um ihn anzuheften"
                sec.headerButton = PINNED_BUTTON
                Show(out, Finish(sec, TitleOf("pinned"), items, #items))
            end
        elseif key == "recent" then
            if Opt("bagShowRecent", false) then AddRecent(out) end
        elseif key == "armory" then
            if not c.hidden.armory then AddArmory(out) end
        elseif FIXED[key] then
            if not c.hidden[key] then
                local items = Bucket(key)
                if #items > 0 then
                    Merge(items)
                    Show(out, Finish(NewSection(key), TitleOf(key), items, #items))
                end
            end
        elseif c.custom[key] then
            AddCustom(out, key, c.custom[key], filter ~= nil)
        end
    end
    AddSpecial(out)
    AddFree(out)

    if filter then
        local n = 0
        for i = 1, #out do
            local sec = out[i]
            if sec.catKey == filter then
                n = n + 1
                out[n] = sec
            end
        end
        for i = n + 1, #out do out[i] = nil end
    elseif not Opt("bagHideAddCategory", false) then
        local sec = NewSection("addcat")
        sec.title = L[TITLES.addcat]
        sec.items = S.none
        sec.plus = true
        sec.onPlus = function() AskNewCategory() end
        sec.plusTooltip = "Neue eigene Kategorie anlegen"
        out[#out + 1] = sec
    end
    return out
end

B.RegisterView("categories", { label = "Kategorien", build = Build })

---------------------------------------------------------------------------
-- Schnittstelle für die Seitenleiste
---------------------------------------------------------------------------

function Cat.SetFilter(key)
    if key ~= nil and type(key) ~= "string" then key = nil end
    if key == S.filter then return end
    S.filter = key
    Changed()
end

function Cat.GetFilter() return S.filter end

local listPool = {}
function Cat.List()
    local c = Cats()
    local out = S.listOut
    wipe(out)
    local function Add(key, isCustom)
        local n = #out + 1
        local e = listPool[n]
        if not e then
            e = {}
            listPool[n] = e
        end
        e.key, e.title, e.icon, e.count, e.custom = key, TitleOf(key), IconOf(key), S.cnt[key] or 0, isCustom and true or false
        out[n] = e
    end
    for _, key in ipairs(OrderedKeys(c)) do
        if c.custom[key] then
            Add(key, true)
        elseif not IsHidden(key) then
            Add(key, false)
        end
    end
    if S.shown.special then Add("special", false) end
    if S.shown.free then Add("free", false) end
    return out
end

---------------------------------------------------------------------------
-- Optionen (Bereich „Tasche“)
---------------------------------------------------------------------------

do
    local function On() return ns.db and ns.db.bagWindow and true or false end
    local HINT = L["Erst „stray-Tasche“ einschalten (weiter oben)."]
    local function Switch(key, label, tooltip, keywords)
        ns.AddOption(1, "Tasche", {
            key = key, label = label, tooltip = tooltip, keywords = keywords,
            isEnabled = On, disabledHint = HINT,
            set = function(value)
                ns.db[key] = value
                if S.filter and IsHidden(S.filter) then S.filter = nil end
                Changed()
            end,
        })
    end
    Switch("bagShowPinned", L["Abschnitt „Angeheftet“ zeigen"],
        L["Zeigt in der Ansicht „Kategorien“ oben den Abschnitt „Angeheftet“. Gegenstand mit der Maus aufnehmen und das + drücken heftet ihn an; Shift- oder Alt-Rechtsklick auf einen angehefteten Gegenstand löst ihn."],
        { "angeheftet", "anheften", "pin", "pinned", "kategorien" })
    Switch("bagHidePinnedInCategories", L["Angeheftetes nicht doppelt zeigen"],
        L["Angeheftete Gegenstände erscheinen nur im Abschnitt „Angeheftet“ und nicht zusätzlich in ihrer Kategorie."],
        { "angeheftet", "doppelt", "pin", "duplicate" })
    Switch("bagShowRecent", L["Abschnitt „Zuletzt erhalten“ zeigen"],
        L["Zeigt in der Ansicht „Kategorien“ die bis zu 15 Gegenstände, die du in dieser Sitzung zuletzt neu erhalten hast (neueste zuerst)."],
        { "zuletzt", "erhalten", "neu", "recent", "new" })
    Switch("bagArmoryBySlot", L["Rüstkammer nach Platz gliedern"],
        L["Teilt den Abschnitt „Rüstkammer“ nach Ausrüstungsplatz auf (Kopf, Schulter, Haupthand, …)."],
        { "rüstkammer", "ausrüstung", "platz", "armory", "equipment", "slot" })
    Switch("bagShowAllEmpty", L["Alle freien Plätze einzeln zeigen"],
        L["Zeigt im Abschnitt „Freie Plätze“ jeden leeren Platz einzeln statt eines Feldes mit der Anzahl."],
        { "frei", "leer", "plätze", "empty", "free", "slots" })
    Switch("bagHideAddCategory", L["„Kategorie hinzufügen“ verbergen"],
        L["Blendet das Feld „Kategorie hinzufügen“ am Ende der Ansicht „Kategorien“ aus. Neue Kategorien legst du dann nicht mehr dort an; vorhandene lassen sich weiter bearbeiten."],
        { "kategorie", "hinzufügen", "category", "add", "custom" })
end
