-- stray – stray-Tasche: Offline-Bestand (ns.Bag.Offline = O)
--
-- Speichert je Charakter, was in Taschen und Bank liegt (nur Lesen, nichts wird bewegt), und zeigt es später an:
--   * Kopf-Symbol im Taschenfenster → Menü: Gold aller Charaktere, Bestand ansehen, Charakter löschen
--   * Ansicht im Bankfenster (K.SetSource), mit Suche
--   * Tooltip-Zeilen „Name: Taschen N · Bank M“ an Gegenständen
-- Wirkt unabhängig vom Schalter bagWindow (Blizzard-Taschen genügen); alles hinter dem Schalter bagOffline.
--
-- ── Datenformat (ns.db.bagOfflineData, charakterübergreifend wie altData; nie in Profilen) ─────────
--   [ "Name-Realm" ] = {
--       name, realm, class (Klassen-Token), money (Kupfer), time (time()),
--       bags = { [bag] = { size = n, [slot] = "itemID:anzahl" | { itemID, anzahl, "item:…-Link" } } },
--       bank = dito (nur wenn die Bank offen war), bankTime = time() der letzten Bank-Erfassung,
--   }
--   Ein Link wird nur gespeichert, wenn er vom Standard-Link der ID abweicht (Verzauberung, Edelsteine,
--   Zufallseigenschaft, Bonus-IDs).
--
-- ── Öffentliche API (ns.Bag.Offline) ─────────────────────────────────────────────────────────────
--   O.Enabled()               Schalter bagOffline an?
--   O.Save()                  erfasst den eigenen Charakter sofort (Taschen; Bank nur bei offener Bank-Interaktion)
--   O.Characters()            sortierte Liste { key, name, class, money, time, bankTime, hasBags, hasBank, self }
--   O.GoldList()              sortierte Liste { key, name, class, money } (absteigend) und Summe; nutzt auch altData
--   O.Counts(itemID)          flaches Array { key, taschen, bank, key, taschen, bank, … } aller gespeicherten Charaktere
--   O.View(key) / O.StopView() / O.Viewing()   Ansicht im Bankfenster
--   O.Delete(key) / O.Clear() Daten löschen (ohne Rückfrage; die Rückfragen stehen in den Menüs/Optionen)
--   O.ShowMenu(owner)         öffnet das Charakter-Menü; O.UpdateIcon() prüft die Sichtbarkeit des Kopf-Symbols

local _, ns = ...
local L = ns.L
local B = ns.Bag
local IsSecret = ns.IsSecret
local API = B.API

local O = {}
B.Offline = O

ns.defaults.bagOffline = false        -- Bestand aller Charaktere speichern
ns.defaults.bagOfflineTooltip = true  -- Tooltip-Zeilen (wirkt nur mit bagOffline)
ns.defaults.bagIconOffline = true     -- Kopf-Symbol (wirkt nur mit bagOffline)
ns.defaults.bagOfflineData = {}       -- siehe Datenformat oben

local SAVE_DELAY = 1.5

local S = {
    pending = false, idx = nil, info = {}, want = {},
    view = nil,       -- { key, src, built, isSelf }
    collapsed = {},   -- [Abschnitt] = true, nur für die Ansicht
    infoTimer = false,
}

local function On()
    return ns.db ~= nil and ns.db.bagOffline == true
end
function O.Enabled() return On() end

local function Data()
    if not ns.db then return nil end
    local d = ns.db.bagOfflineData
    if type(d) ~= "table" then
        d = {}
        ns.db.bagOfflineData = d
    end
    return d
end

local function Num(v)
    if IsSecret(v) or type(v) ~= "number" or v ~= v then return nil end
    return v
end

local function Str(v)
    if IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

---------------------------------------------------------------------------
-- Charakter-Schlüssel (wie alts.lua: „Name-Realm“)
---------------------------------------------------------------------------

local function PlayerKey()
    if S.selfKey then return S.selfKey, S.selfName, S.selfRealm end
    local ok, name = pcall(UnitName, "player")
    name = ok and Str(name) or nil
    if not name then return nil end
    local realm
    if GetNormalizedRealmName then
        ok, realm = pcall(GetNormalizedRealmName)
        realm = ok and Str(realm) or nil
    end
    if not realm and GetRealmName then
        ok, realm = pcall(GetRealmName)
        realm = ok and Str(realm) or nil
        if realm then realm = realm:gsub("[%s%-]", "") end
    end
    local key = realm and (name .. "-" .. realm) or name
    if realm then S.selfKey, S.selfName, S.selfRealm = key, name, realm end
    return key, name, realm
end

---------------------------------------------------------------------------
-- Erfassen
---------------------------------------------------------------------------

-- Weicht der Link vom Standard-Link ab? (Verzauberung, Edelsteine, Zufallseigenschaft, Bonus-IDs)
-- Gibt dann die reine Verknüpfung „item:…“ zurück.
local function ExtraPayload(link)
    if type(link) ~= "string" then return nil end
    local payload = link:match("|H(item:[^|]*)|h") or link:match("^(item:[%d:%-]*)$")
    if not payload then return nil end
    local i, extra = 0, false
    for v in (payload .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if ((i >= 3 and i <= 8) or i == 14) and v ~= "" and v ~= "0" then
            extra = true
            break
        end
    end
    return extra and payload or nil
end

local function Encode(id, count, link)
    count = Num(count) or 1
    local payload = ExtraPayload(link)
    if payload then return { id, count, payload } end
    return id .. ":" .. count
end

local function Decode(v)
    if type(v) == "table" then return Num(v[1]), Num(v[2]) or 1, v[3] end
    if type(v) ~= "string" then return nil end
    local id, count = v:match("^(%d+):(%d+)")
    return tonumber(id), tonumber(count) or 1
end

-- liest eine Tasche in dst[bag]; gibt Größe zurück
local function ReadBag(dst, bag)
    local size = API.NumSlots(bag)
    if size <= 0 then
        dst[bag] = nil
        return 0
    end
    local t = dst[bag]
    if type(t) ~= "table" then
        t = {}
        dst[bag] = t
    else
        wipe(t)
    end
    t.size = size
    for slot = 1, size do
        local _, count, _, _, link, id = API.SlotInfo(bag, slot)
        if not id and type(link) == "string" then id = tonumber(link:match("item:(%d+)")) end
        if type(id) == "number" then t[slot] = Encode(id, count, link) end
    end
    return size
end

local function ReadSet(dst, ids)
    local total, keep = 0, {}
    for _, bag in ipairs(ids) do
        keep[bag] = true
        total = total + ReadBag(dst, bag)
    end
    for bag in pairs(dst) do
        if not keep[bag] then dst[bag] = nil end
    end
    return total
end

local function BagIDs()
    local ids = {}
    for bag = B.C.FIRST_BAG or 0, B.C.LAST_BAG do ids[#ids + 1] = bag end
    local rb = B.C.REAGENT_BAG
    if rb and rb > B.C.LAST_BAG and API.NumSlots(rb) > 0 then ids[#ids + 1] = rb end
    return ids
end

local function BankOpen()
    local K = B.Bank
    return K ~= nil and K.IsInteractionOpen ~= nil and K.IsInteractionOpen() == true
end

function O.Save()
    if not On() then return end
    local data = Data()
    local key, name, realm = PlayerKey()
    if not data or not key then return end
    local e = data[key]
    if type(e) ~= "table" then
        e = {}
        data[key] = e
    end
    e.name, e.realm = name, realm
    local ok, _, token = pcall(UnitClass, "player")
    e.class = (ok and Str(token)) or e.class
    local okM, money = pcall(GetMoney)
    e.money = (okM and Num(money)) or e.money
    e.time = time()
    if type(e.bags) ~= "table" then e.bags = {} end
    ReadSet(e.bags, BagIDs())
    if BankOpen() then
        local ok2, ids = pcall(B.Bank.bagIDs)
        if ok2 and type(ids) == "table" and #ids > 0 then
            local bank = type(e.bank) == "table" and e.bank or {}
            -- nur übernehmen, wenn Plätze gelesen wurden (Bankdaten können kurz nach dem Öffnen fehlen)
            if ReadSet(bank, ids) > 0 then
                e.bank = bank
                e.bankTime = e.time
            end
        end
    end
    O.UpdateIcon()
end

local function RequestSave(delay)
    if S.pending or not On() then return end
    S.pending = true
    C_Timer.After(delay or SAVE_DELAY, function()
        S.pending = false
        local ok, err = pcall(O.Save)
        if not ok then geterrorhandler()(err) end
    end)
end

---------------------------------------------------------------------------
-- Auswertung: Charaktere, Gold, Zählindex
---------------------------------------------------------------------------

function O.Characters()
    local list = {}
    local data = Data()
    if not data then return list end
    local own = PlayerKey()
    for key, e in pairs(data) do
        if type(e) == "table" then
            list[#list + 1] = {
                key = key, name = e.name or key, class = e.class, money = Num(e.money) or 0,
                time = e.time, bankTime = e.bankTime, hasBags = type(e.bags) == "table",
                hasBank = type(e.bank) == "table", self = (key == own),
            }
        end
    end
    table.sort(list, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    return list
end

-- alle bekannten Charaktere mit Gold: eigene Daten, ergänzt um altData (Twink-Übersicht), jeweils der frischere Stand
function O.GoldList()
    local out, sum = {}, 0
    local seen = {}
    local data = Data() or {}
    local alts = ns.db and type(ns.db.altData) == "table" and ns.db.altData or {}
    for key, e in pairs(data) do
        if type(e) == "table" and Num(e.money) then
            local a = alts[key]
            local money = e.money
            if type(a) == "table" and Num(a.money) and (Num(a.time) or 0) > (Num(e.time) or 0) then
                money = a.money
            end
            seen[key] = true
            out[#out + 1] = { key = key, name = e.name or key, class = e.class, money = money }
        end
    end
    for key, a in pairs(alts) do
        if not seen[key] and type(a) == "table" and Num(a.money) then
            out[#out + 1] = { key = key, name = a.name or key, class = a.class, money = a.money }
        end
    end
    table.sort(out, function(a, b)
        if a.money ~= b.money then return a.money > b.money end
        return tostring(a.name) < tostring(b.name)
    end)
    for _, g in ipairs(out) do sum = sum + g.money end
    return out, sum
end

local function AddIndex(idx, key, set, slotIndex)
    if type(set) ~= "table" then return end
    local count = {}
    for _, t in pairs(set) do
        if type(t) == "table" then
            for slot = 1, (t.size or 0) do
                local id, n = Decode(t[slot])
                if id then count[id] = (count[id] or 0) + n end
            end
        end
    end
    for id, n in pairs(count) do
        local list = idx[id]
        if not list then
            list = {}
            idx[id] = list
        end
        local at
        for i = 1, #list, 3 do
            if list[i] == key then
                at = i
                break
            end
        end
        if not at then
            at = #list + 1
            list[at], list[at + 1], list[at + 2] = key, 0, 0
        end
        list[at + slotIndex] = n
    end
end

-- Zählindex je Gegenstand-ID, lazy; wird bei Löschen/Schalter neu gebaut. Der eigene Charakter steht
-- mit dem Stand des Aufbaus darin und wird beim Anzeigen ohnehin übersprungen.
local function Index()
    if S.idx then return S.idx end
    local idx = {}
    local data = Data() or {}
    local keys = {}
    for key, e in pairs(data) do
        if type(e) == "table" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        return tostring(data[a].name or a):lower() < tostring(data[b].name or b):lower()
    end)
    for _, key in ipairs(keys) do
        AddIndex(idx, key, data[key].bags, 1)
        AddIndex(idx, key, data[key].bank, 2)
    end
    S.idx = idx
    return idx
end

function O.Counts(itemID)
    return Index()[itemID]
end

---------------------------------------------------------------------------
-- Löschen
---------------------------------------------------------------------------

function O.StopView()
    local v = S.view
    S.view = nil
    local K = B.Bank
    if v and K and K.SetSource and K.source == v.src then K.SetSource(nil) end
end

function O.Viewing()
    return S.view and S.view.key or nil
end

function O.Delete(key)
    local data = Data()
    if not data or not data[key] then return end
    if S.view and S.view.key == key then O.StopView() end
    data[key] = nil
    S.idx = nil
    O.UpdateIcon()
end

function O.Clear()
    local data = Data()
    if not data then return end
    O.StopView()
    for key in pairs(data) do data[key] = nil end
    S.idx = nil
    if On() then O.Save() end
    O.UpdateIcon()
end

---------------------------------------------------------------------------
-- Ansicht im Bankfenster
---------------------------------------------------------------------------

local function ItemInfo(id)
    local c = S.info[id]
    if c then return c end
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name, _, quality, _, _, _, _, _, _, icon = pcall(fn, id)
    if ok and type(name) == "string" and not IsSecret(name) then
        c = { name = name, lower = name:lower(), quality = Num(quality), icon = icon }
        S.info[id] = c
        return c
    end
    if not S.want[id] then
        S.want[id] = true
        local req = C_Item and C_Item.RequestLoadItemDataByID
        if req then pcall(req, id) end
    end
    return nil
end

local function SortedBags(set)
    local ids = {}
    for bag, t in pairs(set) do
        if type(t) == "table" and type(bag) == "number" then ids[#ids + 1] = bag end
    end
    table.sort(ids)
    return ids
end

-- Abschnitt aus einer Taschenmenge
local function BuildGroup(key, title, set)
    local items, total = {}, 0
    for _, bag in ipairs(SortedBags(set)) do
        local t = set[bag]
        total = total + (t.size or 0)
        for slot = 1, (t.size or 0) do
            local id, count, link = Decode(t[slot])
            if id then
                local info = ItemInfo(id)
                items[#items + 1] = {
                    hasItem = true, itemID = id, count = count, link = link,
                    name = info and info.name, nameLower = info and info.lower,
                    quality = info and info.quality, icon = info and info.icon,
                }
            end
        end
    end
    return {
        key = key, title = title, counter = string.format("(%d / %d)", #items, total),
        items = items, emptySlots = 0, collapsible = true, collapsed = S.collapsed[key] == true,
        onToggle = function(sec)
            sec.collapsed = not sec.collapsed
            S.collapsed[sec.key] = sec.collapsed or nil
        end,
        used = #items, size = total,
    }
end

local function BuildSections(v)
    local data = Data()
    local e = data and data[v.key]
    local out = {}
    if type(e) ~= "table" then return out end
    if not v.isSelf and type(e.bags) == "table" then
        out[#out + 1] = BuildGroup("bags", L["Taschen"], e.bags)
    end
    if type(e.bank) == "table" then
        local stamp = e.bankTime and date(L["%d.%m.%Y %H:%M"], e.bankTime) or "?"
        out[#out + 1] = BuildGroup("bank", L("Bank (Stand: %s)", stamp), e.bank)
    else
        out[#out + 1] = {
            key = "bank", title = L["Bank (noch nicht besucht)"], counter = "", items = {}, emptySlots = 0,
        }
    end
    return out
end

local function Sections(v)
    if not v.built then v.built = BuildSections(v) end
    return v.built
end

local function Rebuild()
    local v = S.view
    if not v then return end
    v.built = nil
    local K = B.Bank
    if K and K.RequestRefresh then K.RequestRefresh(0, "source") end
end

function O.View(key)
    local K = B.Bank
    local data = Data()
    if not (K and K.SetSource and data and type(data[key]) == "table") then return false end
    if S.view and S.view.key == key then
        O.StopView()
        return true
    end
    local e = data[key]
    local v = { key = key, isSelf = (key == PlayerKey()) }
    local name = e.name or key
    v.src = {
        title = v.isSelf and L("%s – Bank (zuletzt gesehen)", name) or L("%s – Bestand", name),
        sections = function() return Sections(v) end,
    }
    local used, size = 0, 0
    for _, sec in ipairs(Sections(v)) do
        used = used + (sec.used or 0)
        size = size + (sec.size or 0)
    end
    v.src.used, v.src.total = used, size
    S.view = v
    K.SetSource(v.src)
    if K.Open then K.Open() end
    return true
end

---------------------------------------------------------------------------
-- Menü
---------------------------------------------------------------------------

local function ClassHex(token)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = token and colors and colors[token]
    if c then
        return string.format("|cff%02x%02x%02x", math.floor((c.r or 1) * 255 + 0.5),
            math.floor((c.g or 1) * 255 + 0.5), math.floor((c.b or 1) * 255 + 0.5))
    end
    return "|cffffffff"
end

local function Colored(name, class)
    return ClassHex(class) .. tostring(name) .. "|r"
end

local function Money(n)
    return ns.FormatMoney and ns.FormatMoney(n) or tostring(n)
end

local function MenuDef()
    local def = {}
    local gold, sum = O.GoldList()
    if #gold > 0 then
        def[#def + 1] = { title = true, text = L["Gold aller Charaktere"] }
        for _, g in ipairs(gold) do
            def[#def + 1] = { title = true, text = Colored(g.name, g.class) .. "  " .. Money(g.money) }
        end
        if #gold > 1 then def[#def + 1] = { title = true, text = L("Summe: %s", Money(sum)) } end
        def[#def + 1] = { divider = true }
    end
    local chars = O.Characters()
    local own = PlayerKey()
    def[#def + 1] = { title = true, text = L["Bestand ansehen"] }
    local n = 0
    local viewing = O.Viewing()
    for _, c in ipairs(chars) do
        if (c.hasBags and not c.self) or c.hasBank then
            n = n + 1
            local label = Colored(c.name, c.class)
            if c.self then label = label .. " – " .. L["Bank (zuletzt gesehen)"] end
            if viewing == c.key then label = "> " .. label end
            local key = c.key
            def[#def + 1] = { text = label, func = function() O.View(key) end }
        end
    end
    if n == 0 then def[#def + 1] = { title = true, text = L["Noch kein Bestand gespeichert."] } end
    if viewing then
        def[#def + 1] = { text = L["Ansicht schließen"], func = function() O.StopView() end }
    end
    local sub = {}
    for _, c in ipairs(chars) do
        if c.key ~= own then
            local key = c.key
            sub[#sub + 1] = { text = Colored(c.name, c.class), func = function() O.AskDelete(key) end }
        end
    end
    if #sub > 0 then
        def[#def + 1] = { divider = true }
        def[#def + 1] = { text = L["Charakter löschen"], sub = sub }
    end
    return def
end

function O.ShowMenu(owner)
    local Cat = B.Categories
    if not (Cat and Cat.ShowMenu) then return end
    Cat.ShowMenu(owner, MenuDef())
end

StaticPopupDialogs["STRAY_BAGOFFLINE_DELETE"] = {
    text = "%s",
    button1 = "",
    button2 = CANCEL,
    OnAccept = function(self, data)
        local key = data or self.data
        if type(key) == "string" then O.Delete(key) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["STRAY_BAGOFFLINE_CLEAR"] = {
    text = "%s",
    button1 = "",
    button2 = CANCEL,
    OnAccept = function() O.Clear() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function O.AskDelete(key)
    local d = StaticPopupDialogs["STRAY_BAGOFFLINE_DELETE"]
    local data = Data()
    local e = data and data[key]
    d.text = L["Gespeicherten Bestand von „%s“ löschen?"]
    d.button1 = L["Löschen"]
    d.button2 = L["Abbrechen"]
    StaticPopup_Show("STRAY_BAGOFFLINE_DELETE", e and e.name or key, nil, key)
end

local function AskClear()
    local d = StaticPopupDialogs["STRAY_BAGOFFLINE_CLEAR"]
    d.text = L["Den gespeicherten Bestand aller Charaktere löschen?"]
    d.button1 = L["Löschen"]
    d.button2 = L["Abbrechen"]
    StaticPopup_Show("STRAY_BAGOFFLINE_CLEAR")
end

---------------------------------------------------------------------------
-- Kopf-Symbol (früh angelegt; Sichtbarkeit nach Schalter und Daten)
---------------------------------------------------------------------------

local iconBtn
if B.AddHeaderIcon then
    local ok, btn = pcall(B.AddHeaderIcon, {
        key = "offline", icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
        tooltip = "Bestand anderer Charaktere",
        onClick = function(self, mouse)
            if mouse == "RightButton" and S.view then
                O.StopView()
            else
                O.ShowMenu(self)
            end
        end,
    })
    if ok then iconBtn = btn end
end
if iconBtn then iconBtn:Hide() end

function O.UpdateIcon()
    if not iconBtn then return end
    local show = false
    if On() and ns.db.bagIconOffline ~= false then
        local own = PlayerKey()
        for _, c in ipairs(O.Characters()) do
            if c.key ~= own and (c.hasBags or c.hasBank) then
                show = true
                break
            end
        end
    end
    iconBtn:SetShown(show)
end

---------------------------------------------------------------------------
-- Tooltip-Zeilen
---------------------------------------------------------------------------

local function AddTooltipLines(tooltip, id)
    if not On() or not ns.db.bagOfflineTooltip then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    id = Num(id)
    if not id then return end
    local list = Index()[id]
    if not list then return end
    local data = Data()
    local own = PlayerKey()
    local n, sumBags, sumBank = 0, 0, 0
    for i = 1, #list, 3 do
        local key, nb, nk = list[i], list[i + 1], list[i + 2]
        local e = data and data[key]
        if key ~= own and type(e) == "table" then
            local text
            if nb > 0 and nk > 0 then
                text = L("Taschen %d · Bank %d", nb, nk)
            elseif nb > 0 then
                text = L("Taschen %d", nb)
            else
                text = L("Bank %d", nk)
            end
            n = n + 1
            sumBags, sumBank = sumBags + nb, sumBank + nk
            tooltip:AddLine(Colored(e.name or key, e.class) .. ": " .. text, 0.8, 0.8, 0.8)
        end
    end
    if n > 1 then
        tooltip:AddLine(L("Summe (andere Charaktere): %d", sumBags + sumBank), 0.6, 0.6, 0.6)
    end
end

do
    local registered = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.Item then
        registered = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip, data)
            if not On() then return end
            local id = type(data) == "table" and data.id or nil
            pcall(AddTooltipLines, tooltip, id)
        end)
    end
    if not registered then
        local function Hook(tt)
            if tt and tt.HookScript then
                pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                    if not On() then return end
                    local ok, _, link = pcall(self.GetItem, self)
                    if ok and type(link) == "string" and not IsSecret(link) then
                        pcall(AddTooltipLines, self, tonumber(link:match("item:(%d+)")))
                    end
                end)
            end
        end
        Hook(GameTooltip)
        Hook(ItemRefTooltip)
    end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

do
    local ev = CreateFrame("Frame")
    local handlers = {
        BAG_UPDATE_DELAYED = function() RequestSave() end,
        PLAYER_MONEY = function()
            if not On() then return end
            local data, key = Data(), PlayerKey()
            local e = data and key and data[key]
            local ok, money = pcall(GetMoney)
            if type(e) == "table" and ok and Num(money) then e.money = money end
        end,
        PLAYER_LOGOUT = function() O.Save() end,
        PLAYER_LOGIN = function()
            O.UpdateIcon()
            RequestSave(3)
        end,
        GET_ITEM_INFO_RECEIVED = function(id)
            if not S.view or not S.want[id] then return end
            S.want[id] = nil
            if S.infoTimer then return end
            S.infoTimer = true
            C_Timer.After(0.3, function()
                S.infoTimer = false
                Rebuild()
            end)
        end,
    }
    for event in pairs(handlers) do pcall(ev.RegisterEvent, ev, event) end
    ev:SetScript("OnEvent", function(_, event, ...)
        local ok, err = pcall(handlers[event], ...)
        if not ok then geterrorhandler()(err) end
    end)
end

-- Bankfenster: Erfassung bei Bank-Refresh, Ansicht nachführen
do
    local K = B.Bank
    if K then
        if K.OnRefresh then
            K.OnRefresh(function() RequestSave(SAVE_DELAY) end)
        end
        if K.OnState then
            K.OnState(function(event)
                if event == "open" then
                    RequestSave(SAVE_DELAY)
                    S.view = nil   -- das Bankfenster löscht die Quelle selbst
                elseif event == "source" or event == "hidden" then
                    local v = S.view
                    if v and K.source ~= v.src then
                        S.view = nil
                    elseif v and event == "hidden" then
                        O.StopView()
                    end
                end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

do
    local function OffOn() return On() end
    local HINT = L["Erst „Bestand aller Charaktere speichern“ einschalten (weiter oben)."]

    ns.AddOption(1, "Tasche", {
        key = "bagOffline",
        label = L["Bestand aller Charaktere speichern"],
        tooltip = L["Speichert für jeden Charakter, was in Taschen und Bank liegt, und zeigt es später an: Kopf-Symbol im Taschenfenster (Bestand im Bankfenster ansehen, Gold aller Charaktere) und Zeilen im Gegenstands-Tooltip.\n\nDie Bank wird erfasst, wenn du sie besuchst. Wirkt auch ohne „stray-Tasche“ (mit Blizzards Taschen), das Kopf-Symbol gibt es aber nur im stray-Taschenfenster."],
        keywords = { "bestand", "offline", "twink", "charaktere", "inventar", "bank", "tasche", "alts", "inventory", "stock" },
        set = function(value)
            ns.db.bagOffline = value
            S.idx = nil
            if value then
                O.Save()
            elseif S.view then
                O.StopView()
            end
            O.UpdateIcon()
        end,
    })
    ns.AddOption(1, "Tasche", {
        key = "bagOfflineTooltip",
        label = L["Bestand anderer Charaktere im Tooltip"],
        tooltip = L["Hängt an Gegenstands-Tooltips Zeilen „Name: Taschen N · Bank M“ für jeden anderen gespeicherten Charakter an, der den Gegenstand hat (bei mehreren mit Summe)."],
        keywords = { "tooltip", "bestand", "offline", "twink", "charaktere", "anzahl", "count" },
        isEnabled = OffOn, disabledHint = HINT,
    })
    ns.AddOption(1, "Tasche", {
        key = "bagIconOffline",
        label = L["Symbol „Bestand“ im Taschenfenster"],
        tooltip = L["Zeigt im Kopf des Taschenfensters ein Symbol mit dem Charakter-Menü (Bestand ansehen, Gold, löschen). Es erscheint, sobald ein anderer Charakter gespeichert ist."],
        keywords = { "symbol", "icon", "bestand", "offline", "kopf", "twink" },
        isEnabled = OffOn, disabledHint = HINT,
        set = function(value)
            ns.db.bagIconOffline = value
            O.UpdateIcon()
        end,
    })
    ns.AddOption(1, "Tasche", {
        key = "bagOfflineClear",
        type = "button",
        label = L["Gespeicherten Bestand löschen"],
        buttonText = L["Löschen"],
        tooltip = L["Löscht den gespeicherten Bestand aller Charaktere (mit Rückfrage). Gold und Twink-Übersicht bleiben unberührt; der eingeloggte Charakter wird sofort neu erfasst."],
        keywords = { "löschen", "bestand", "offline", "zurücksetzen", "clear", "delete", "reset" },
        onClick = AskClear,
    })
end
