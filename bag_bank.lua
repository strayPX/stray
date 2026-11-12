-- stray – stray-Tasche: Bankfenster (ns.Bag.Bank = K)
--
-- Eigenes Bankfenster im Aufbau der stray-Tasche: Kopf (Titel, Belegung, Sortieren, Einlagern, Banktaschen,
-- Suche, X), Abschnitte je Bank-Tab bzw. Banktasche (einklappbar), Raster aus echten Blizzard-Itemknöpfen
-- (ContainerFrameItemButtonTemplate, Elternrahmen mit SetID(Taschen-ID)), Scrollen, Größe ziehen, Schloss.
--
-- Bank-Modell (laut Blizzard-Quelltext, Zweig forever = „Camelot“): Retail-artige Bank mit C_Bank-Tabs
--   Enum.BankType.Character; Tab-IDs = Enum.BagIndex.CharacterBankTab_1.. (6..14); Taschenplätze liegen im
--   Behälter Enum.BagIndex.Characterbanktab (-2), Platz 1 ist das gratis Grundfach. Rückfall ohne C_Bank-Tabs:
--   klassische Bank (BANK_CONTAINER = -1 und Banktaschen NUM_BAG_SLOTS+1 …).
-- Blizzards BankFrame bleibt GEÖFFNET (ContainerFrameItemButton fragt BankFrame:GetActiveBankType() – nur dann
--   lagert ein Rechtsklick ein) und wird nur unsichtbar „geparkt“: SetParent auf einen sichtbaren, unsichtbaren
--   Rahmen (Alpha 0, Maßstab ~0). Kein Hide(), kein SetParent auf einen versteckten Rahmen (das würde OnHide
--   auslösen → C_Bank.CloseBankFrame).
--
-- ── Öffentliche API (ns.Bag.Bank) ───────────────────────────────────────────────────────────────
--   K.IsOpen()              Fenster sichtbar? (live, Offline-Quelle oder Vorschau)
--   K.IsInteractionOpen()   Bank-Interaktion (Bankier) ist offen – unabhängig vom Schalter
--   K.IsLive()              Fenster zeigt gerade die echte Bank
--   K.bagIDs()              Array der aktuellen Bank-Taschen-IDs (nur Taschen mit Plätzen); nur bei offener Bank
--   K.ForEachRecord(fn)     fn(rec) für alle Plätze der Bank (Datensätze wie B.slots, siehe B.FillRecord);
--                           nur bei offener Bank (liest frisch). rec nie festhalten.
--   K.OnRefresh(fn)         fn(reasons) nach jedem gebündelten Bank-Refresh (auch bei ausgeschaltetem bagBank,
--                           solange die Bank-Interaktion offen ist); reasons = Menge { bag=true, open=true, … }
--   K.OnState(fn)           fn(event) mit event = "open" | "close" (Interaktion), "shown" | "hidden" (Fenster),
--                           "source" (Quelle gesetzt/gelöscht)
--   K.frame                 das Fenster
--   K.Open() K.Close() K.Toggle()   Fenster zeigen/verbergen (Live nur bei offener Bank; mit Quelle immer)
--   K.SetSource(nil | { title, used, total, sections = function() … end })
--       Zeigt statt der Live-Bank einen gespeicherten Bestand. sections() liefert Abschnitte wie B.BuildSections:
--       { key, title, counter, items = { Datensätze mit icon, count, link, itemID, quality, name, hasItem },
--         emptySlots = n (gedimmte Felder), collapsible, collapsed, onToggle = fn(section), noHeader }
--       Gezeigt werden einfache Icons (kein Knopf, nur Tooltip per Item-Link/ID). Öffnet die Bank live, wird
--       die Quelle automatisch gelöscht (K.source = nil). Danach K.Open() bzw. K.RequestRefresh(0, "source").
--   K.RequestRefresh(delay, reason)  gebündelter Refresh; K.Refresh(reason) sofort
--   K.Wanted()              Schalter bagBank und bagWindow an?

local _, ns = ...
local L = ns.L
local B = ns.Bag
local IsSecret = ns.IsSecret
local API = B.API

local K = {}
B.Bank = K

ns.defaults.bagBank = false          -- stray-Bank statt Blizzards Bank (wirkt nur mit bagWindow)
ns.defaults.bagBankColumns = 14
ns.defaults.bagBankHeight = 0        -- 0 = Höhe automatisch
ns.defaults.bagBankCollapsed = {}    -- [Abschnitts-Schlüssel] = true: eingeklappt

---------------------------------------------------------------------------
-- Stil „forever“ (wie bag_window.lua): alles hinter FX.On()
---------------------------------------------------------------------------

local FX = { stray = {}, lines = {}, btns = {} }

function FX.On()
    local S = ns.Style
    if not (S and S.IsForever) then return false end
    local ok, v = pcall(S.IsForever)
    return ok and v == true
end

function FX.Stray(x)
    FX.stray[#FX.stray + 1] = x
    return x
end

local function FXHide(o)
    if type(o) ~= "table" then return end
    if o.Hide then
        pcall(o.Hide, o)
    else
        for _, v in pairs(o) do FXHide(v) end
    end
end

---------------------------------------------------------------------------
-- Maße und Farben
---------------------------------------------------------------------------

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BODY = "Fonts\\ARIALN.TTF"

local C
do
    local PALETTE = type(ns.Colors) == "table" and ns.Colors or {}
    local function Col(key, fallback)
        local c = PALETTE[key]
        if type(c) == "table" and type(c[1]) == "number" then return c end
        return fallback
    end
    C = {
        bg         = Col("bg", { 0.078, 0.078, 0.098, 0.96 }),
        line       = Col("line", { 0.149, 0.149, 0.184, 1 }),
        accent     = Col("accent", { 0.545, 0.486, 0.965, 1 }),
        accentText = Col("accentText", { 0.702, 0.659, 0.980, 1 }),
        text       = Col("text", { 0.902, 0.902, 0.925, 1 }),
        textDim    = Col("textDim", { 0.545, 0.545, 0.600, 1 }),
        textFaint  = Col("textFaint", { 0.369, 0.369, 0.420, 1 }),
        field      = { 0.055, 0.055, 0.071, 1 },
        slot       = { 0.051, 0.051, 0.064, 1 },
        slotEdge   = { 0.149, 0.149, 0.184, 1 },
        itemEdge   = { 0.235, 0.235, 0.286, 1 },
        quest      = { 1, 0.82, 0, 1 },
    }
end

local M = {
    GAP = 4, PAD = 10, HEAD = 40, FOOT = 28, HDR_H = 22, HDR_GAP = 6, SEC_GAP = 12,
    MIN_W = 600, BAR_W = 8, MAX_H = 900, MIN_H = 200,
}

-- Zustand des Fensters (gebündelt, um lokale Namen zu sparen)
local W = {
    scrollY = 0, scrollMax = 0, viewH = 0, contentH = 0,
    items = {},          -- platzierte Knöpfe: { btn, rec, y }
    placed = {},         -- [Knopf] = true (letzter Layout-Durchlauf)
    deco = setmetatable({}, { __mode = "k" }),   -- [Knopf] = eigene Texturen
    pos = setmetatable({}, { __mode = "k" }),    -- [Knopf] = { x, y, size }
    headers = {}, virt = {}, statics = {},
    search = "", sizing = false, pendingLayout = false, pendingHide = false,
    hc = {},             -- Farben der Überschriften (Forever setzt sie um)
}

-- Zustand der Bank (Interaktion, Übernahme)
local D = {
    reasons = {}, callbacks = {}, stateFns = {}, pending = false,
    forceBlizzard = false, openedBags = false, scanned = false,
}
K.interaction = false
K.source = nil

local function SlotSize()
    local n = ns.db and tonumber(ns.db.bagSlotSize) or 36
    n = math.floor(n + 0.5)
    return math.max(B.C.MIN_SLOT, math.min(B.C.MAX_SLOT, n))
end

local function Columns()
    local n = ns.db and tonumber(ns.db.bagBankColumns) or 14
    n = math.floor(n + 0.5)
    return math.max(B.C.MIN_COLS, math.min(B.C.MAX_COLS, n))
end

local function GridSize(n)
    if n < 1 then return 0 end
    local s = SlotSize()
    return n * s + (n - 1) * M.GAP
end

local function WidthFor(cols)
    return math.max(M.MIN_W, M.PAD * 2 + M.BAR_W + GridSize(cols))
end

local function ColumnsForWidth(w)
    local n = math.floor((w - M.PAD * 2 - M.BAR_W + M.GAP) / (SlotSize() + M.GAP))
    return math.max(B.C.MIN_COLS, math.min(B.C.MAX_COLS, n))
end

local function MaxHeight()
    local h = UIParent and UIParent:GetHeight()
    if type(h) ~= "number" or IsSecret(h) or h <= M.MIN_H then return M.MAX_H end
    return math.max(M.MIN_H, math.min(M.MAX_H, math.floor(h - 20)))
end

local function FixedHeight()
    local h = ns.db and tonumber(ns.db.bagBankHeight)
    if not h or h <= 0 then return nil end
    return math.max(M.MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
end

local function Locked()
    return ns.db and ns.db.bagLocked and true or false
end

---------------------------------------------------------------------------
-- Kleine Bausteine
---------------------------------------------------------------------------

local function Tex(parent, layer, c, sub)
    local t = parent:CreateTexture(nil, layer or "BORDER", nil, sub)
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

local function Border(frame, c, layer)
    local edges = {}
    for i = 1, 4 do edges[i] = Tex(frame, layer or "BORDER", c) end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    return edges
end

local function SetEdges(edges, r, g, b, a)
    if not edges then return end
    for _, t in ipairs(edges) do t:SetColorTexture(r, g, b, a or 1) end
end

local function Text(parent, size, c, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or FONT, size, "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Tip(owner, title, body, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 1, 1)
    if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

local function AnyProtected(f)
    local ok, protected = pcall(f.IsProtected, f)
    return ok and protected and true or false
end

local function Public(v)
    if IsSecret(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- Bank-API (Hüllen): C_Bank-Tabs (Forever) oder klassische Bank
---------------------------------------------------------------------------

local BK = {}
BK.CB = C_Bank
BK.CHAR = Enum and Enum.BankType and Enum.BankType.Character
BK.CONT = (Enum and Enum.BagIndex and Enum.BagIndex.Characterbanktab) or -2
BK.FIRSTTAB = (Enum and Enum.BagIndex and Enum.BagIndex.CharacterBankTab_1) or 6

function BK.HasTabs()
    local cb = BK.CB
    return type(cb) == "table" and type(BK.CHAR) == "number" and type(cb.FetchPurchasedBankTabData) == "function"
end

-- "tabs" (C_Bank), "classic" oder nil (keine Bank-API)
function BK.Model()
    if BK.HasTabs() then return "tabs" end
    if type(GetNumBankSlots) == "function" or BANK_CONTAINER ~= nil then return "classic" end
    return nil
end

local function BoolCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then return nil end
    return v
end

-- Kann diese Interaktion die Charakter-Bank zeigen? (Kriegsmeute-Banker allein: nein → Blizzards Bank bleibt)
function BK.CanView()
    if BK.Model() ~= "tabs" then return true end
    local v = BoolCall(BK.CB.CanViewBank, BK.CHAR)
    if v == nil then return true end
    return v and true or false
end

-- Liegen Taschen in den Banktabs (Camelot) oder sind es feste Tabs?
function BK.BagsInBank()
    return BoolCall(BK.CB and BK.CB.ShouldUsePlayerBagsInBank) == true
end

function BK.MaxTabs()
    local n = BoolCall(BK.CB and BK.CB.FetchMaxNumBankTabs, BK.CHAR)
    if type(n) == "number" then return n end
    return nil
end

function BK.CloseInteraction()
    if BK.CB and type(BK.CB.CloseBankFrame) == "function" then
        pcall(BK.CB.CloseBankFrame)
    elseif type(CloseBankFrame) == "function" then
        pcall(CloseBankFrame)
    end
end

function BK.Sort()
    if BK.Model() == "tabs" and C_Container and C_Container.SortBank then
        return pcall(C_Container.SortBank, BK.CHAR)
    end
    local fn = (C_Container and C_Container.SortBankBags) or SortBankBags
    if type(fn) == "function" then return pcall(fn) end
    return false
end

function BK.HasSort()
    if BK.Model() == "tabs" then return C_Container ~= nil and C_Container.SortBank ~= nil end
    return ((C_Container and C_Container.SortBankBags) or SortBankBags) ~= nil
end

function BK.HasDeposit()
    if BK.Model() ~= "tabs" or type(BK.CB.AutoDepositItemsIntoBank) ~= "function" then return false end
    local sup = BoolCall(BK.CB.DoesBankTypeSupportAutoDeposit, BK.CHAR)
    return sup ~= false
end

function BK.Deposit()
    if not BK.HasDeposit() then return false end
    return pcall(BK.CB.AutoDepositItemsIntoBank, BK.CHAR)
end

-- Nächster kaufbarer Tab/Platz: Kosten (Kupfer), kannBezahlen – oder nil
function BK.NextCost()
    if BK.Model() == "tabs" then
        local can = BoolCall(BK.CB.CanPurchaseBankTab, BK.CHAR)
        if can == false then return nil end
        if type(BK.CB.FetchNextPurchasableBankTabData) ~= "function" then return nil end
        local ok, data = pcall(BK.CB.FetchNextPurchasableBankTabData, BK.CHAR)
        if ok and type(data) == "table" and not IsSecret(data.tabCost) and type(data.tabCost) == "number" then
            return data.tabCost, data.canAfford ~= false
        end
        return nil
    end
    if type(GetBankSlotCost) == "function" and type(GetNumBankSlots) == "function" then
        local ok, n = pcall(GetNumBankSlots)
        if ok and type(n) == "number" and not IsSecret(n) and n < (NUM_BANKBAGSLOTS or 7) then
            local ok2, cost = pcall(GetBankSlotCost, n)
            if ok2 and type(cost) == "number" and not IsSecret(cost) then return cost, true end
        end
    end
    return nil
end

-- Kauf nur über Blizzards eigenen Bestätigungsdialog; false, wenn es ihn nicht gibt
function BK.Buy()
    local name = (BK.Model() == "tabs") and "CONFIRM_BUY_BANK_TAB" or "CONFIRM_BUY_BANK_SLOT"
    if not (StaticPopupDialogs and StaticPopupDialogs[name] and StaticPopup_Show) then return false end
    local data = (BK.Model() == "tabs") and { bankType = BK.CHAR } or nil
    local ok = pcall(StaticPopup_Show, name, nil, nil, data)
    return ok
end

---------------------------------------------------------------------------
-- Daten: Tabs/Taschen und Plätze lesen
---------------------------------------------------------------------------

K.tabs = {}       -- geordnet: { id, key, title, icon, size, free, used, index }
K.slots = {}      -- [bag][slot] = Datensatz (wiederverwendet)
K.used, K.total = 0, 0
K.rev = 0

local function ReadTabs()
    local list = {}
    local model = BK.Model()
    if model == "tabs" then
        local ok, data = pcall(BK.CB.FetchPurchasedBankTabData, BK.CHAR)
        if ok and type(data) == "table" and not IsSecret(data) then
            for i, t in ipairs(data) do
                if type(t) == "table" then
                    local id = Public(t.ID)
                    if type(id) ~= "number" then id = BK.FIRSTTAB + i - 1 end
                    local name = Public(t.name)
                    if type(name) ~= "string" or name == "" then name = nil end
                    list[#list + 1] = { id = id, name = name, icon = Public(t.icon), index = i }
                end
            end
        end
    elseif model == "classic" then
        local main = BANK_CONTAINER or -1
        list[1] = { id = main, name = L["Bank"], index = 1, main = true }
        local ok, n = pcall(GetNumBankSlots or function() return 0 end)
        n = (ok and not IsSecret(n) and type(n) == "number") and n or 0
        for i = 1, n do
            list[#list + 1] = { id = (NUM_BAG_SLOTS or 4) + i, index = i + 1 }
        end
    end
    return list
end

local function TabTitle(t)
    if t.name then return t.name end
    local n = API.BagName(t.id)
    if n then return n end
    if BK.Model() == "classic" then return L("Banktasche %d", math.max(1, (t.index or 2) - 1)) end
    return L("Bankfach %d", t.index or 1)
end

function K.Scan()
    local list = ReadTabs()
    local used, total = 0, 0
    local seen = {}
    for _, t in ipairs(list) do
        local id = t.id
        seen[id] = true
        local size = API.NumSlots(id)
        local slots = K.slots[id]
        if not slots then
            slots = {}
            K.slots[id] = slots
        end
        local usedHere = 0
        for slot = 1, size do
            local d = slots[slot]
            if not d then
                d = {}
                slots[slot] = d
            end
            B.FillRecord(d, id, slot)
            if d.hasItem then usedHere = usedHere + 1 end
        end
        for slot = size + 1, #slots do slots[slot] = nil end
        t.size, t.used, t.free = size, usedHere, size - usedHere
        t.key = "bank" .. id
        t.title = TabTitle(t)
        used = used + usedHere
        total = total + size
    end
    for id in pairs(K.slots) do
        if not seen[id] then K.slots[id] = nil end
    end
    K.tabs = list
    K.used, K.total = used, total
    K.rev = K.rev + 1
    D.scanned = true
end

function K.bagIDs()
    if K.interaction then pcall(K.Scan) end
    local ids = {}
    for _, t in ipairs(K.tabs) do
        if (t.size or 0) > 0 then ids[#ids + 1] = t.id end
    end
    return ids
end

function K.ForEachRecord(fn)
    if not K.interaction then return end
    pcall(K.Scan)
    for _, t in ipairs(K.tabs) do
        local slots = K.slots[t.id]
        if slots then
            for slot = 1, #slots do fn(slots[slot]) end
        end
    end
end

function K.OnRefresh(fn)
    D.callbacks[#D.callbacks + 1] = fn
end

function K.OnState(fn)
    D.stateFns[#D.stateFns + 1] = fn
end

local function Fire(event)
    for _, fn in ipairs(D.stateFns) do
        local ok, err = pcall(fn, event)
        if not ok then geterrorhandler()(err) end
    end
end

function K.Wanted()
    return ns.db ~= nil and ns.db.bagBank == true and B.Enabled()
end

function K.IsInteractionOpen() return K.interaction end

---------------------------------------------------------------------------
-- Knopf-Vorrat: echte Blizzard-Itemknöpfe (Elternrahmen = Tasche, Knopf-ID = Platz), nie im Kampf erzeugt.
-- Eigener Vorrat (der des Kerns hängt im Taschenfenster). Fremde Daten stehen in schwachen Tabellen.
---------------------------------------------------------------------------

local P = { containers = {}, buttons = {}, broken = false, state = setmetatable({}, { __mode = "k" }) }
P.host = CreateFrame("Frame", "strayBankHost", UIParent)
P.host:SetSize(10, 10)

local function Container(bag)
    local c = P.containers[bag]
    if c then return c end
    local name = "strayBankContainer" .. (tostring(bag):gsub("%-", "m"))
    c = CreateFrame("Frame", name, P.host)
    c:SetAllPoints(P.host)
    c:SetID(bag)
    c.GetBagID = function(self) return self:GetID() end
    c.IsCombinedBagContainer = function() return false end
    P.containers[bag] = c
    return c
end

local function Region(b, key, suffix)
    return b[key] or (b:GetName() and _G[b:GetName() .. suffix])
end

-- Blizzards Zeichnung dämpfen, eigene Texturen darunter/darüber (wie bag_window.lua)
local function StyleButton(b)
    local Dc = {}
    W.deco[b] = Dc
    local size = SlotSize()
    b:SetSize(size, size)
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    for _, key in ipairs({ "IconBorder", "NewItemTexture", "BattlepayItemTexture", "JunkIcon", "UpgradeIcon" }) do
        local r = b[key]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
    local questTex = Region(b, "IconQuestTexture", "IconQuestTexture")
    if questTex then questTex:SetAlpha(0) end

    Dc.bg = Tex(b, "BACKGROUND", C.slot, -8)
    Dc.bg:SetAllPoints()

    local icon = Region(b, "icon", "IconTexture") or b.Icon
    Dc.icon = icon
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local cd = Region(b, "Cooldown", "Cooldown")
    if cd then
        cd:ClearAllPoints()
        cd:SetPoint("TOPLEFT", 1, -1)
        cd:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    Dc.cooldown = cd

    local holder = CreateFrame("Frame", nil, b)
    holder:SetAllPoints()
    holder:SetFrameLevel(b:GetFrameLevel() + 2)
    Dc.edges = Border(holder, C.slotEdge, "OVERLAY")

    Dc.quest = holder:CreateTexture(nil, "OVERLAY", nil, 2)
    Dc.quest:SetPoint("TOPLEFT", 1, -1)
    Dc.quest:SetPoint("BOTTOMRIGHT", -1, 1)
    Dc.quest:Hide()

    Dc.new = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    Dc.new:SetPoint("TOPLEFT", 1, -1)
    Dc.new:SetPoint("BOTTOMRIGHT", -1, 1)
    Dc.new:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.22)
    Dc.new:Hide()

    Dc.dim = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    Dc.dim:SetAllPoints()
    Dc.dim:SetColorTexture(0, 0, 0, 0.7)
    Dc.dim:Hide()

    local count = Region(b, "Count", "Count")
    if count and count.SetParent then
        pcall(count.SetParent, count, holder)
        count:SetDrawLayer("OVERLAY", 6)
    end
    Dc.count = count
    Dc.holder = holder
end

local function CreateButton(bag, slot, parent)
    local b
    local name = "strayBankItem" .. (tostring(bag):gsub("%-", "m")) .. "_" .. slot
    for _, kind in ipairs({ "ItemButton", "Button" }) do
        local ok, result = pcall(CreateFrame, kind, name, parent, "ContainerFrameItemButtonTemplate")
        if ok and result then b = result break end
    end
    if not b then
        if not P.broken then
            P.broken = true
            ns.Print(L["Bankfenster: Blizzards Taschenknopf-Vorlage fehlt – es bleibt Blizzards Bank."])
        end
        return nil
    end
    -- Die Taschen-ID kommt aus dem Elternrahmen (kein SetBagID: taint, siehe bag_core.lua)
    b:SetID(slot)
    P.state[b] = { bag = bag, slot = slot }
    b:Hide()
    pcall(StyleButton, b)
    return b
end

function P.Acquire(bag, slot)
    if P.broken then return nil end
    local list = P.buttons[bag]
    if not list then
        list = {}
        P.buttons[bag] = list
    end
    local b = list[slot]
    if b then return b end
    if InCombatLockdown() then P.needWarm = true return nil end
    b = CreateButton(bag, slot, Container(bag))
    list[slot] = b
    return b
end

function P.Release(btn)
    if not btn or InCombatLockdown() then return false end
    if btn:IsShown() then pcall(btn.Hide, btn) end
    return true
end

-- Knöpfe für alle aktuellen Plätze anlegen (nur außerhalb des Kampfes); true, wenn alle da sind
function P.Warm()
    if P.broken then return false end
    if InCombatLockdown() then
        P.needWarm = true
        return false
    end
    P.needWarm = false
    for _, t in ipairs(K.tabs) do
        for slot = 1, (t.size or 0) do
            if not P.Acquire(t.id, slot) then return false end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "strayBankFrame", UIParent)
K.frame = frame
frame:SetSize(M.MIN_W, 300)
frame:SetFrameStrata("MEDIUM")
frame:SetToplevel(true)
frame:Hide()
tinsert(UISpecialFrames, "strayBankFrame") -- Esc schließt (und beendet die Bank-Interaktion)

do
    local winBg = Tex(frame, "BACKGROUND", C.bg)
    winBg:SetAllPoints()
    FX.Stray(winBg)
end
FX.Stray(Border(frame, C.line))

ns.MakeMovable(frame, "bagbank", { "TOPLEFT", "TOPLEFT", 60, -120 })

local function SavePosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) or not ns.db then return end
    ns.db.positions.bagbank = { "TOPLEFT", "BOTTOMLEFT", left, top }
end

frame:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not W.sizing and not Locked() then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    if W.sizing then return end
    self:StopMovingOrSizing()
    SavePosition()
end)

local head = CreateFrame("Frame", nil, frame)
head:SetPoint("TOPLEFT", 1, -1)
head:SetPoint("TOPRIGHT", -1, -1)
head:SetHeight(M.HEAD - 1)
head:EnableMouse(true)
head:RegisterForDrag("LeftButton")
head:SetScript("OnDragStart", function()
    if not W.sizing and not Locked() then frame:StartMoving() end
end)
head:SetScript("OnDragStop", function()
    if W.sizing then return end
    frame:StopMovingOrSizing()
    SavePosition()
end)

do
    local headLine = Tex(frame, "BORDER", C.line)
    headLine:SetPoint("TOPLEFT", 1, -M.HEAD); headLine:SetPoint("TOPRIGHT", -1, -M.HEAD); headLine:SetHeight(1)
    FX.lines[#FX.lines + 1] = headLine
end

local title = Text(head, 14, C.text)
title:SetPoint("LEFT", 12, 0)

local slotsText = Text(head, 12, C.textDim, FONT_BODY)
slotsText:SetPoint("LEFT", title, "RIGHT", 10, -1)

local close = CreateFrame("Button", nil, head)
close:SetSize(22, 22)
close:SetPoint("RIGHT", -8, 0)
FX.Stray(Border(close, C.line))
do
    local closeText = Text(close, 12, C.textDim, FONT_BODY)
    closeText:SetPoint("CENTER", 1, 0)
    closeText:SetText("X")
    local closeHover = close:CreateTexture(nil, "HIGHLIGHT")
    closeHover:SetAllPoints()
    closeHover:SetColorTexture(1, 1, 1, 0.07)
    FX.Stray(closeHover)
    FX.btns[#FX.btns + 1] = { btn = close, text = closeText }
end

local search = CreateFrame("EditBox", "strayBankSearch", head)
search:SetSize(120, 22)
search:SetPoint("RIGHT", close, "LEFT", -8, 0)
search:SetAutoFocus(false)
search:SetFont(FONT_BODY, 12, "")
search:SetTextColor(C.text[1], C.text[2], C.text[3])
search:SetTextInsets(8, 8, 0, 0)
search:SetMaxLetters(40)
do
    local searchBg = Tex(search, "BACKGROUND", C.field)
    searchBg:SetAllPoints()
    FX.Stray(searchBg)
end
FX.Stray(Border(search, C.line))
local placeholder = Text(search, 12, C.textFaint, FONT_BODY)
placeholder:SetPoint("LEFT", 8, 0)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
search:SetScript("OnEditFocusLost", function(self) placeholder:SetShown(self:GetText() == "") end)

-- Textknöpfe im Kopf (von rechts nach links vor dem Suchfeld)
local function HeadButton(anchor)
    local btn = CreateFrame("Button", nil, head)
    btn:SetHeight(22)
    FX.Stray(Tex(btn, "BACKGROUND", C.field)):SetAllPoints()
    FX.Stray(Border(btn, C.line))
    btn.label = Text(btn, 11, C.text, FONT_BODY)
    btn.label:SetPoint("CENTER", 0, 0)
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.10)
    FX.Stray(hover)
    FX.btns[#FX.btns + 1] = { btn = btn, text = btn.label }
    btn:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

local bagsBtn = HeadButton(search)
local depositBtn = HeadButton(bagsBtn)
local sortBtn = HeadButton(depositBtn)

-- Beschriftung und Größe der Kopfknöpfe (sichtbare Texte erst beim Anzeigen übersetzen)
local function LabelHeadButton(btn, text)
    btn.label:SetText(text)
    btn:SetWidth(math.max(40, math.floor((btn.label:GetStringWidth() or 40) + 16)))
end

---------------------------------------------------------------------------
-- Inhalt: ScrollFrame mit den Abschnitten
---------------------------------------------------------------------------

local scroll = CreateFrame("ScrollFrame", nil, frame)
local child = CreateFrame("Frame", nil, scroll)
child:SetSize(10, 10)
scroll:SetScrollChild(child)
P.host:SetParent(child)
P.host:ClearAllPoints()
P.host:SetAllPoints(child)

scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -M.HEAD - 1)
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -M.BAR_W, M.FOOT + 1)

local emptyText = Text(child, 12, C.textDim, FONT_BODY)
emptyText:SetPoint("TOPLEFT", M.PAD, -M.PAD)
emptyText:Hide()

local scrollTrack = CreateFrame("Button", nil, frame)
scrollTrack:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -M.HEAD - 4)
scrollTrack:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, M.FOOT + 4)
scrollTrack:SetWidth(10)
scrollTrack:SetFrameLevel(frame:GetFrameLevel() + 20)
scrollTrack:EnableMouseWheel(true)
do
    local trackLine = scrollTrack:CreateTexture(nil, "ARTWORK")
    trackLine:SetPoint("TOP")
    trackLine:SetPoint("BOTTOM")
    trackLine:SetWidth(4)
    trackLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6)
    FX.track = trackLine
end
scrollTrack:Hide()

local scrollThumb = CreateFrame("Button", nil, scrollTrack)
scrollThumb:SetWidth(10)
scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 2)
local thumbLine = scrollThumb:CreateTexture(nil, "OVERLAY")
thumbLine:SetPoint("TOP")
thumbLine:SetPoint("BOTTOM")
thumbLine:SetWidth(4)
thumbLine:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
scrollThumb:SetScript("OnEnter", function() thumbLine:SetWidth(6) end)
scrollThumb:SetScript("OnLeave", function(self) if not self.dragging then thumbLine:SetWidth(4) end end)

local grip = CreateFrame("Button", nil, frame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
grip:SetFrameLevel(frame:GetFrameLevel() + 30)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetAlpha(0.5)

frame:SetResizable(true)
local function UpdateResizeBounds()
    local maxW = WidthFor(B.C.MAX_COLS)
    if not pcall(frame.SetResizeBounds, frame, M.MIN_W, M.MIN_H, maxW, M.MAX_H) then
        if frame.SetMinResize then pcall(frame.SetMinResize, frame, M.MIN_W, M.MIN_H) end
        if frame.SetMaxResize then pcall(frame.SetMaxResize, frame, maxW, M.MAX_H) end
    end
end
UpdateResizeBounds()

---------------------------------------------------------------------------
-- Fuß: links „Blizzard-Bank“, rechts Gold und Schloss
---------------------------------------------------------------------------

do
    local footLine = Tex(frame, "BORDER", C.line)
    footLine:SetPoint("BOTTOMLEFT", 1, M.FOOT); footLine:SetPoint("BOTTOMRIGHT", -1, M.FOOT); footLine:SetHeight(1)
    FX.lines[#FX.lines + 1] = footLine
end

local blizzBtn = CreateFrame("Button", nil, frame)
blizzBtn:SetHeight(18)
blizzBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 5)
FX.Stray(Tex(blizzBtn, "BACKGROUND", C.field)):SetAllPoints()
FX.Stray(Border(blizzBtn, C.line))
blizzBtn.label = Text(blizzBtn, 11, C.textDim, FONT_BODY)
blizzBtn.label:SetPoint("CENTER", 0, 0)
do
    local hover = blizzBtn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.10)
    FX.Stray(hover)
    FX.btns[#FX.btns + 1] = { btn = blizzBtn, text = blizzBtn.label }
end

local lockBtn = CreateFrame("Button", nil, frame)
lockBtn:SetSize(18, 18)
lockBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 5)
local lockParts = {}
do
    local function Part(w, h, p, x, y)
        local t = lockBtn:CreateTexture(nil, "ARTWORK")
        t:SetSize(w, h)
        t:SetPoint(p, lockBtn, p, x, y)
        t:SetColorTexture(1, 1, 1, 1)
        lockParts[#lockParts + 1] = t
        return t
    end
    lockBtn.body = Part(12, 8, "BOTTOM", 0, 2)
    lockBtn.shackleL = Part(2, 6, "BOTTOMLEFT", 3, 9)
    lockBtn.shackleR = Part(2, 6, "BOTTOMRIGHT", -3, 9)
    lockBtn.shackleT = Part(8, 2, "TOP", 0, -1)
    lockBtn.shackleOpenR = Part(2, 3, "BOTTOMRIGHT", -3, 12)
end
local function PaintLock()
    local locked = Locked()
    local c = locked and (W.hc.gold or C.accentText) or C.textDim
    for _, t in ipairs(lockParts) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    lockBtn.shackleR:SetShown(locked)
    lockBtn.shackleOpenR:SetShown(not locked)
    lockBtn.shackleT:SetWidth(locked and 8 or 5)
    lockBtn.shackleT:ClearAllPoints()
    lockBtn.shackleT:SetPoint("TOP", lockBtn, "TOP", locked and 0 or -1.5, -1)
end
lockBtn:SetScript("OnClick", function()
    if not ns.db then return end
    ns.db.bagLocked = not ns.db.bagLocked
    PaintLock()
    grip:SetShown(not Locked())
    if B.RequestPaint then B.RequestPaint() end
    if ns.RefreshConfig then pcall(ns.RefreshConfig) end
end)
lockBtn:SetScript("OnEnter", function(self)
    Tip(self, Locked() and L["Fenster ist gesperrt"] or L["Fenster sperren"],
        L["Gesperrt: das Fenster lässt sich nicht verschieben und seine Größe nicht ändern."])
end)
lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local moneyText = Text(frame, 12, C.text, FONT_BODY)
moneyText:SetPoint("RIGHT", lockBtn, "LEFT", -8, 0)
moneyText:SetJustifyH("RIGHT")

---------------------------------------------------------------------------
-- Zeichnen: Suche, Gegenstandsknöpfe, einfache Icons (Offline-Quelle)
---------------------------------------------------------------------------

local function RecName(rec)
    if rec.nameLower then return rec.nameLower end
    local n = rec.name
    if type(n) ~= "string" and type(rec.link) == "string" then n = rec.link:match("%[(.-)%]") end
    return type(n) == "string" and n:lower() or nil
end

-- leer = alles passt; sonst Name enthält den Text (leere Plätze passen nie)
function K.Matches(rec)
    if W.search == "" then return true end
    if not rec or not rec.hasItem then return false end
    local n = RecName(rec)
    return n ~= nil and n:find(W.search, 1, true) ~= nil
end

function K.SetSearch(text)
    text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    W.search = text
    if search:GetText():lower() ~= text then search:SetText(text) end
end

function K.GetSearch() return W.search end

local function QuestMarksOn()
    return ns.db and ns.db.questItemMarks and true or false
end

local function SetCooldown(Dc, bag, slot, hasItem)
    local cd = Dc.cooldown
    if not cd then return end
    if not hasItem then
        if cd.Clear then pcall(cd.Clear, cd) else cd:Hide() end
        return
    end
    local start, duration, enable = API.Cooldown(bag, slot)
    if start == nil then return end
    if IsSecret(start) or IsSecret(duration) or IsSecret(enable) then
        pcall(cd.SetCooldown, cd, start, duration)
        return
    end
    if CooldownFrame_Set then
        pcall(CooldownFrame_Set, cd, start, duration, enable)
    elseif enable and enable ~= 0 and duration and duration > 0 then
        cd:SetCooldown(start, duration)
        cd:Show()
    else
        cd:Hide()
    end
end

local function QualityEdge(Dc, rec)
    local q, hasItem = rec.quality, rec.hasItem
    if rec.questItem or rec.questStarter or (rec.questNeeded and QuestMarksOn()) then
        SetEdges(Dc.edges, C.quest[1], C.quest[2], C.quest[3], 1)
    elseif hasItem and type(q) == "number" and q >= 2 and API.QualityColor(q) then
        local r, g, bl = API.QualityColor(q)
        SetEdges(Dc.edges, r, g, bl, 1)
    elseif hasItem and q == 0 then
        SetEdges(Dc.edges, 0.40, 0.40, 0.40, 1)
    elseif hasItem then
        SetEdges(Dc.edges, C.itemEdge[1], C.itemEdge[2], C.itemEdge[3], 1)
    else
        SetEdges(Dc.edges, C.slotEdge[1], C.slotEdge[2], C.slotEdge[3], 0.7)
    end
end

-- Zeichnet einen echten Knopf nach seinem Datensatz (nur Texturen und Texte, nie geschützt)
local function Paint(b, rec)
    local Dc = W.deco[b]
    if not Dc or not rec then return end
    local hasItem = rec.hasItem
    -- Direkt an Symbol und Zahl (siehe bag_window.lua): kein SetItemButtonTexture/-Count
    if Dc.icon then
        Dc.icon:SetTexture(rec.icon)
        Dc.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Dc.icon:SetShown(rec.icon ~= nil)
    end
    local count = rec.displayCount or rec.count
    count = (type(count) == "number") and count or 0
    if Dc.count then
        Dc.count:SetText(count > 1 and count or "")
        Dc.count:SetShown(count > 1)
    end
    local locked = rec.locked and true or false
    if Dc.icon then Dc.icon:SetDesaturated(locked) end
    if Dc.icon then
        local v = locked and 0.5 or 1
        Dc.icon:SetVertexColor(v, v, v)
    end
    QualityEdge(Dc, rec)
    Dc.bg:SetColorTexture(C.slot[1], C.slot[2], C.slot[3], hasItem and 1 or 0.7)
    if rec.questStarter or (rec.questNeeded and QuestMarksOn()) then
        Dc.quest:SetTexture(TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang")
        Dc.quest:Show()
    elseif rec.questItem then
        Dc.quest:SetTexture(TEXTURE_ITEM_QUEST_BORDER or "Interface\\ContainerFrame\\UI-Icon-QuestBorder")
        Dc.quest:Show()
    else
        Dc.quest:Hide()
    end
    Dc.new:SetShown(rec.isNew and true or false)
    Dc.dim:SetShown(not K.Matches(rec))
    SetCooldown(Dc, rec.bag, rec.slot, hasItem)
end

-- Einfache Icons für die Offline-Quelle: Frame mit Icon, Zahl, Rand und Tooltip (keine Knopf-Funktion)
local function MakeStatic()
    local s = CreateFrame("Frame", nil, child)
    s:EnableMouse(true)
    s.bg = Tex(s, "BACKGROUND", C.slot)
    s.bg:SetAllPoints()
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.edges = Border(s, C.slotEdge, "OVERLAY")
    s.count = Text(s, 11, C.text, FONT_BODY)
    s.count:SetPoint("BOTTOMRIGHT", -3, 3)
    s.count:SetJustifyH("RIGHT")
    s.dim = Tex(s, "OVERLAY", { 0, 0, 0, 0.7 }, 7)
    s.dim:SetAllPoints()
    s.dim:Hide()
    s:SetScript("OnEnter", function(self)
        local rec = self.rec
        if not rec or not rec.hasItem then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = rec.link or (rec.itemID and ("item:" .. rec.itemID))
        if link and pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return s
end

local function StaticIcon(rec)
    if rec.icon then return rec.icon end
    local id = rec.itemID or (type(rec.link) == "string" and tonumber(rec.link:match("item:(%d+)")))
    if not id then return nil end
    local fn = C_Item and C_Item.GetItemIconByID
    if fn then
        local ok, icon = pcall(fn, id)
        if ok and icon then return icon end
    end
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if inst then
        local ok, _, _, _, _, icon = pcall(inst, id)
        if ok and icon then return icon end
    end
    return nil
end

local function PaintStatic(s, rec)
    s.rec = rec
    local icon = StaticIcon(rec)
    s.icon:SetTexture(icon)
    s.icon:SetShown(icon ~= nil)
    local count = rec.displayCount or rec.count
    s.count:SetText((type(count) == "number" and count > 1) and count or "")
    QualityEdge(s, rec)
    s.bg:SetColorTexture(C.slot[1], C.slot[2], C.slot[3], rec.hasItem and 1 or 0.7)
    s.dim:SetShown(not K.Matches(rec))
end

local function PaintAll()
    for _, it in ipairs(W.items) do
        local rec = it.rec
        if not rec.synthetic then
            local list = K.slots[rec.bag]
            rec = (list and list[rec.slot]) or rec
        end
        pcall(Paint, it.btn, rec)
    end
    for _, s in ipairs(W.statics) do
        if s.shown and s.rec then pcall(PaintStatic, s, s.rec) end
    end
    for _, v in ipairs(W.virt) do
        if v.shown then v.dim:SetShown(W.search ~= "") end
    end
end

---------------------------------------------------------------------------
-- Überschriften und gedimmte Felder
---------------------------------------------------------------------------

local function HeaderColors()
    local hc = W.hc
    return hc.text or C.text, hc.dim or C.textDim, hc.line or C.line
end

local function MakeHeader()
    local h = CreateFrame("Button", nil, child)
    h:SetHeight(M.HDR_H)
    h.arrow = h:CreateTexture(nil, "ARTWORK")
    h.arrow:SetSize(12, 12)
    h.arrow:SetPoint("LEFT", 0, 0)
    h.label = Text(h, 13, C.text)
    h.count = Text(h, 11, C.textDim, FONT_BODY)
    h.line = h:CreateTexture(nil, "BORDER")
    h.line:SetHeight(1)
    h:SetScript("OnClick", function(self)
        local s = self.section
        if s and s.collapsible then
            if s.onToggle then pcall(s.onToggle, s) end
            K.RequestRefresh(0, "layout")
        end
    end)
    return h
end

local function StyleHeader(h, sec)
    local tc, dc, lc = HeaderColors()
    h.section = sec
    h.label:SetTextColor(tc[1], tc[2], tc[3])
    h.count:SetTextColor(dc[1], dc[2], dc[3])
    h.line:SetColorTexture(lc[1], lc[2], lc[3], lc[4] or 1)
    h.label:SetText(sec.title or "")
    h.count:SetText(sec.counter or "")
    h.arrow:SetShown(sec.collapsible and true or false)
    h.label:ClearAllPoints()
    if sec.collapsible then
        h.arrow:SetTexture(sec.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        h.label:SetPoint("LEFT", h.arrow, "RIGHT", 4, 0)
    else
        h.label:SetPoint("LEFT", 0, 0)
    end
    h.count:ClearAllPoints()
    h.count:SetPoint("LEFT", h.label, "RIGHT", 8, -1)
    h.line:ClearAllPoints()
    h.line:SetPoint("LEFT", h.count, "RIGHT", 10, 0)
    h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
end

local function MakeVirt()
    local v = CreateFrame("Frame", nil, child)
    v.bg = Tex(v, "BACKGROUND", C.slot)
    v.bg:SetAllPoints()
    v.edges = Border(v, C.slotEdge)
    v.dim = Tex(v, "OVERLAY", { 0, 0, 0, 0.5 })
    v.dim:SetAllPoints()
    v.dim:Hide()
    return v
end

---------------------------------------------------------------------------
-- Abschnitte: live (je Tab/Tasche), Offline-Quelle oder Vorschau
---------------------------------------------------------------------------

local function Collapsed(key)
    local t = ns.db and ns.db.bagBankCollapsed
    return type(t) == "table" and t[key] == true
end

local function ToggleCollapsed(section)
    if not (ns.db and type(ns.db.bagBankCollapsed) == "table") then return end
    local key = section.key
    ns.db.bagBankCollapsed[key] = (not ns.db.bagBankCollapsed[key]) or nil
end

-- "preview" (Bearbeitungsmodus), "source" (Offline-Bestand) oder "live"
local function Mode()
    if W.preview then return "preview" end
    if K.source then return "source" end
    return "live"
end

local function BuildSections()
    local mode = Mode()
    if mode == "preview" then
        return {
            { key = "p1", title = L["Bank"], counter = "(0 / 28)", items = {}, emptySlots = 28 },
            { key = "p2", title = L("Bankfach %d", 2), counter = "(0 / 28)", items = {}, emptySlots = 28 },
        }
    end
    if mode == "source" then
        local ok, sections = pcall(K.source.sections)
        if not ok then geterrorhandler()(sections) end
        return (ok and type(sections) == "table") and sections or {}
    end
    local sections = {}
    for _, t in ipairs(K.tabs) do
        if (t.size or 0) > 0 then
            local items = {}
            local slots = K.slots[t.id] or {}
            for slot = 1, t.size do items[#items + 1] = slots[slot] end
            sections[#sections + 1] = {
                key = t.key, title = t.title, counter = string.format("(%d / %d)", t.used or 0, t.size),
                items = items, emptySlots = 0,
                collapsible = true, collapsed = Collapsed(t.key), onToggle = ToggleCollapsed,
            }
        end
    end
    return sections
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function CanLayout()
    return not InCombatLockdown() or not AnyProtected(frame)
end

local function UpdateScrollBar()
    if W.scrollMax <= 0 then
        scrollTrack:Hide()
        return
    end
    local trackH = scrollTrack:GetHeight() or 0
    if trackH <= 0 then
        scrollTrack:Hide()
        return
    end
    local thumbH = math.max(16, math.floor(trackH * W.viewH / math.max(1, W.contentH)))
    local offset = (W.scrollY / W.scrollMax) * (trackH - thumbH)
    scrollThumb:ClearAllPoints()
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -offset)
    scrollThumb:SetHeight(thumbH)
    scrollTrack:Show()
end

local function Cull()
    if not CanLayout() then return end
    local size = SlotSize()
    local top, bottom = W.scrollY - size * 2, W.scrollY + W.viewH + size * 2
    for _, it in ipairs(W.items) do
        local vis = it.y + size >= top and it.y <= bottom
        if vis ~= it.shown then
            it.shown = vis
            if vis then it.btn:Show() else it.btn:Hide() end
        end
    end
end

local function SetScroll(y, noCull)
    y = math.max(0, math.min(W.scrollMax, tonumber(y) or 0))
    W.scrollY = y
    pcall(scroll.SetVerticalScroll, scroll, y)
    UpdateScrollBar()
    if not noCull then Cull() end
end

local function PlaceButton(b, x, y, size)
    local p = W.pos[b]
    if not p then
        p = {}
        W.pos[b] = p
    end
    if p.size ~= size then
        b:SetSize(size, size)
        p.size = size
    end
    if p.x ~= x or p.y ~= y then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", P.host, "TOPLEFT", x, -y)
        p.x, p.y = x, y
    end
end

local function Layout(live)
    local size, gap, pad = SlotSize(), M.GAP, M.PAD
    local cols = (live and W.liveCols) or Columns()
    local sections = BuildSections()
    local isStatic = Mode() ~= "live"
    local nowPlaced = {}
    wipe(W.items)
    local hdrN, virtN, statN = 0, 0, 0
    local y = pad
    local first = true

    for _, sec in ipairs(sections) do
        if not sec.hidden then
            if not first then y = y + M.SEC_GAP end
            first = false
            if not sec.noHeader then
                hdrN = hdrN + 1
                local h = W.headers[hdrN]
                if not h then
                    h = MakeHeader()
                    W.headers[hdrN] = h
                end
                StyleHeader(h, sec)
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", child, "TOPLEFT", pad, -y)
                h:SetPoint("TOPRIGHT", child, "TOPRIGHT", -pad, -y)
                h:Show()
                y = y + M.HDR_H + M.HDR_GAP
            end
            if not sec.collapsed then
                local cell = 0
                local function Next()
                    cell = cell + 1
                    return ((cell - 1) % cols) * (size + gap), y + math.floor((cell - 1) / cols) * (size + gap)
                end
                for _, rec in ipairs(sec.items or {}) do
                    local x, cy = Next()
                    if isStatic then
                        statN = statN + 1
                        local s = W.statics[statN]
                        if not s then
                            s = MakeStatic()
                            W.statics[statN] = s
                        end
                        s:ClearAllPoints()
                        s:SetPoint("TOPLEFT", child, "TOPLEFT", x, -cy)
                        s:SetSize(size, size)
                        s:Show()
                        s.shown = true
                        pcall(PaintStatic, s, rec)
                    else
                        local b = P.Acquire(rec.bag, rec.slot)
                        if b then
                            PlaceButton(b, x, cy, size)
                            nowPlaced[b] = true
                            W.items[#W.items + 1] = { btn = b, rec = rec, y = cy, shown = b:IsShown() }
                        end
                    end
                end
                for _ = 1, (sec.emptySlots or 0) do
                    local x, cy = Next()
                    virtN = virtN + 1
                    local v = W.virt[virtN]
                    if not v then
                        v = MakeVirt()
                        W.virt[virtN] = v
                    end
                    v:ClearAllPoints()
                    v:SetPoint("TOPLEFT", child, "TOPLEFT", x, -cy)
                    v:SetSize(size, size)
                    v:Show()
                    v.shown = true
                end
                local rows = math.ceil(cell / cols)
                if rows > 0 then y = y + rows * (size + gap) - gap end
            else
                y = y - M.HDR_GAP
            end
        end
    end
    for i = hdrN + 1, #W.headers do W.headers[i]:Hide() end
    for i = virtN + 1, #W.virt do W.virt[i]:Hide(); W.virt[i].shown = false end
    for i = statN + 1, #W.statics do W.statics[i]:Hide(); W.statics[i].shown = false; W.statics[i].rec = nil end
    emptyText:SetShown(#sections == 0)

    for b in pairs(W.placed) do
        if not nowPlaced[b] then P.Release(b) end
    end
    W.placed = nowPlaced

    local contentH = y + pad
    local width = WidthFor(cols)
    child:SetSize(math.max(1, width - 1 - M.BAR_W), math.max(1, contentH))
    W.contentH = contentH
    local height
    if live then
        height = frame:GetHeight() or M.MIN_H
    else
        height = FixedHeight() or math.max(M.MIN_H, math.min(MaxHeight(), M.HEAD + 1 + contentH + M.FOOT + 1))
    end
    W.viewH = math.max(1, height - M.HEAD - M.FOOT - 2)
    W.scrollMax = math.max(0, contentH - W.viewH)
    if not live then
        frame:SetSize(width, height)
        UpdateResizeBounds()
    end
    SetScroll(W.scrollY, true)
    local top, bottom = W.scrollY - size * 2, W.scrollY + W.viewH + size * 2
    for _, it in ipairs(W.items) do
        local vis = it.y + size >= top and it.y <= bottom
        it.shown = vis
        if vis then it.btn:Show() else it.btn:Hide() end
    end
end

---------------------------------------------------------------------------
-- Banktaschen-Leiste (Taschenplätze der Bank, Kauf über Blizzards Dialog)
---------------------------------------------------------------------------

local Bar = { slots = {}, shown = false }

Bar.frame = CreateFrame("Frame", nil, frame)
Bar.frame:SetFrameLevel(frame:GetFrameLevel() + 40)
Bar.frame:EnableMouse(true)
Bar.frame:Hide()
FX.Stray(Tex(Bar.frame, "BACKGROUND", C.bg)):SetAllPoints()
FX.Stray(Border(Bar.frame, C.line))
Bar.title = Text(Bar.frame, 12, C.text)
Bar.title:SetPoint("TOPLEFT", 10, -8)
Bar.hint = Text(Bar.frame, 11, C.textDim, FONT_BODY)
Bar.hint:SetJustifyH("LEFT")
Bar.hint:SetWordWrap(true)

local BAR_SLOT = 36

local function BarSlot(i)
    local s = Bar.slots[i]
    if s then return s end
    s = CreateFrame("Button", nil, Bar.frame)
    s:SetSize(BAR_SLOT, BAR_SLOT)
    s.bg = Tex(s, "BACKGROUND", C.slot)
    s.bg:SetAllPoints()
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.edges = Border(s, C.slotEdge, "OVERLAY")
    s.mark = Text(s, 18, C.textDim, FONT_BODY)
    s.mark:SetPoint("CENTER", 0, 1)
    s.mark:SetJustifyH("CENTER")
    local hl = s:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)
    s:RegisterForClicks("LeftButtonUp")
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s:SetScript("OnEnter", function(self) Bar.Tooltip(self) end)
    s:SetScript("OnClick", function(self) Bar.Click(self) end)
    s:SetScript("OnReceiveDrag", function(self) Bar.Click(self) end)
    s:SetScript("OnDragStart", function(self) Bar.Click(self) end)
    Bar.slots[i] = s
    return s
end

-- Zustände der Leiste: "bag" (Tasche drin), "empty" (Platz leer), "tab" (fester Tab), "buy" (nächster
-- kaufbarer Platz), "locked" (noch nicht freigeschaltet)
local function BarData()
    local list = {}
    local model = BK.Model()
    if model == "tabs" then
        local bags = BK.BagsInBank()
        local max = BK.MaxTabs() or #K.tabs
        local cost, afford = BK.NextCost()
        for i = bags and 2 or 1, max do
            local tab = K.tabs[i]
            local e = { index = i, tab = tab }
            if tab then
                if bags then
                    local icon, _, _, quality = API.SlotInfo(BK.CONT, i)
                    e.icon, e.quality = icon, quality
                    e.state = icon and "bag" or "empty"
                else
                    e.state, e.icon = "tab", tab.icon
                end
            elseif i == #K.tabs + 1 and cost then
                e.state, e.cost, e.afford = "buy", cost, afford
            else
                e.state = "locked"
            end
            list[#list + 1] = e
        end
    elseif model == "classic" then
        local ok, n = pcall(GetNumBankSlots or function() return 0 end)
        n = (ok and not IsSecret(n) and type(n) == "number") and n or 0
        local cost, afford = BK.NextCost()
        for i = 1, (NUM_BANKBAGSLOTS or 7) do
            local e = { index = i, tab = K.tabs[i + 1] }
            local inv
            if type(BankButtonIDToInvSlotID) == "function" then
                local ok2, v = pcall(BankButtonIDToInvSlotID, i, 1)
                inv = (ok2 and not IsSecret(v)) and v or nil
            end
            e.inv = inv
            if i <= n then
                local icon
                if inv and GetInventoryItemTexture then icon = Public(GetInventoryItemTexture("player", inv)) end
                e.icon = icon
                e.state = icon and "bag" or "empty"
            elseif i == n + 1 and cost then
                e.state, e.cost, e.afford = "buy", cost, afford
            else
                e.state = "locked"
            end
            list[#list + 1] = e
        end
    end
    return list
end

function Bar.Update()
    local data = BarData()
    local n = #data
    local pad, gap = 10, 6
    for i = 1, math.max(n, #Bar.slots) do
        local s = Bar.slots[i]
        local e = data[i]
        if e then
            s = BarSlot(i)
            s.entry = e
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", Bar.frame, "TOPLEFT", pad + (i - 1) * (BAR_SLOT + gap), -30)
            s.icon:SetTexture(e.icon)
            s.icon:SetShown(e.icon ~= nil)
            s.icon:SetDesaturated(e.state == "locked")
            local q = e.quality
            if e.state == "bag" and type(q) == "number" and q >= 2 and API.QualityColor(q) then
                local r, g, b = API.QualityColor(q)
                SetEdges(s.edges, r, g, b, 1)
            else
                SetEdges(s.edges, C.slotEdge[1], C.slotEdge[2], C.slotEdge[3], e.state == "locked" and 0.4 or 1)
            end
            if e.state == "buy" then
                s.mark:SetText("+")
                s.mark:SetTextColor(C.accentText[1], C.accentText[2], C.accentText[3])
            elseif e.state == "locked" then
                s.mark:SetText("x")
                s.mark:SetTextColor(C.textFaint[1], C.textFaint[2], C.textFaint[3])
            else
                s.mark:SetText("")
            end
            s:Show()
        elseif s then
            s:Hide()
            s.entry = nil
        end
    end
    local width = math.max(pad * 2 + n * BAR_SLOT + math.max(0, n - 1) * gap, 300)
    Bar.frame:SetWidth(width)
    Bar.hint:ClearAllPoints()
    Bar.hint:SetPoint("TOPLEFT", Bar.frame, "TOPLEFT", pad, -30 - BAR_SLOT - 8)
    Bar.hint:SetWidth(width - pad * 2)
    local hintH = math.ceil(Bar.hint:GetStringHeight() or 24)
    Bar.frame:SetHeight(30 + BAR_SLOT + 8 + hintH + 10)
end

function Bar.Tooltip(s)
    local e = s.entry
    if not e then return end
    local tab = e.tab
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    if e.state == "bag" and BK.Model() == "tabs" and GameTooltip.SetBagItem
        and pcall(GameTooltip.SetBagItem, GameTooltip, BK.CONT, e.index) then
        if tab then GameTooltip:AddLine(L("%d von %d Plätzen frei", tab.free or 0, tab.size or 0), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(L["Klick: Tasche aufnehmen. Mit einer Tasche am Cursor: tauschen."], 0.6, 0.6, 0.6, true)
    elseif e.state == "bag" and e.inv and GameTooltip.SetInventoryItem
        and pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", e.inv) then
        if tab then GameTooltip:AddLine(L("%d von %d Plätzen frei", tab.free or 0, tab.size or 0), 0.8, 0.8, 0.8) end
    elseif e.state == "tab" then
        GameTooltip:SetText(tab and tab.title or L("Bankfach %d", e.index), 1, 1, 1)
        if tab then GameTooltip:AddLine(L("%d von %d Plätzen frei", tab.free or 0, tab.size or 0), 0.8, 0.8, 0.8) end
    elseif e.state == "empty" then
        GameTooltip:SetText(L["Leerer Taschenplatz"], 1, 1, 1)
        GameTooltip:AddLine(L["Zieh eine Tasche aus deinem Rucksack hierher, um sie einzusetzen."], 0.8, 0.8, 0.8, true)
    elseif e.state == "buy" then
        GameTooltip:SetText(L["Taschenplatz kaufen"], 1, 1, 1)
        local r, g, b = 0.8, 0.8, 0.8
        if e.afford == false then r, g, b = 1, 0.3, 0.3 end
        GameTooltip:AddLine(L("Kostet %s. Es öffnet sich Blizzards Bestätigungsdialog – gekauft wird erst nach deinem Ja.",
            ns.FormatMoney(e.cost or 0)), r, g, b, true)
    else
        GameTooltip:SetText(L["Noch nicht freigeschaltet"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Kaufe zuerst den Platz davor."], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function Pickup(container, slot)
    local fn = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
    if fn then return (pcall(fn, container, slot)) end
    return false
end

function Bar.Click(s)
    local e = s.entry
    if not e then return end
    if e.state == "buy" then
        if not BK.Buy() then
            ns.Print(L["Kaufen geht hier nicht – nutze „Blizzard-Bank“ unten links im Fenster."])
        end
    elseif e.state == "bag" or e.state == "empty" then
        if BK.Model() == "tabs" then
            Pickup(BK.CONT, e.index)
        elseif e.inv then
            if CursorHasItem and CursorHasItem() then
                if PutItemInBag then pcall(PutItemInBag, e.inv) end
            elseif PickupBagFromSlot then
                pcall(PickupBagFromSlot, e.inv)
            end
        end
        K.RequestRefresh(0.1, "bag")
    end
end

function Bar.Apply()
    local show = Bar.shown and frame:IsShown() and Mode() == "live"
    if show then
        Bar.title:SetText(L["Banktaschen"])
        Bar.hint:SetText((BK.Model() == "tabs" and BK.BagsInBank())
            and L["Setze Taschen in die Plätze, um die Bank zu vergrößern. Ein Platz mit + lässt sich kaufen (mit Bestätigung)."]
            or L["Hier siehst du die Plätze der Bank. Ein Platz mit + lässt sich kaufen (mit Bestätigung)."])
        Bar.Update()
        Bar.frame:ClearAllPoints()
        Bar.frame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -M.HEAD - 4)
        Bar.frame:Show()
    else
        Bar.frame:Hide()
    end
end

function Bar.Toggle()
    Bar.shown = not Bar.shown
    Bar.Apply()
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------

local function UpdateHeader()
    local mode = Mode()
    local src = K.source
    if mode == "source" then
        title:SetText(L[tostring(src.title or "Bank")])
    else
        title:SetText(L["Bank"])
    end
    local used, total = K.used, K.total
    if mode == "source" then
        if type(src.used) == "number" and type(src.total) == "number" then
            used, total = src.used, src.total
        else
            used, total = 0, 0
            local ok, sections = pcall(src.sections)
            if ok and type(sections) == "table" then
                for _, sec in ipairs(sections) do
                    local n = #(sec.items or {})
                    used = used + n
                    total = total + n + (sec.emptySlots or 0)
                end
            end
        end
    elseif mode == "preview" then
        used, total = 0, 56
    end
    slotsText:SetText(L("%d / %d Plätze", used, total))
    local money = GetMoney and ns.Public(GetMoney())
    moneyText:SetText((mode == "live" and type(money) == "number") and ns.FormatMoney(money) or "")
    local live = mode == "live"
    sortBtn:SetShown(live and BK.HasSort() and true or false)
    depositBtn:SetShown(live and BK.HasDeposit() and true or false)
    bagsBtn:SetShown(live and BK.Model() ~= nil)
    blizzBtn:SetShown(live and K.interaction and _G.BankFrame ~= nil)
    if not live then Bar.frame:Hide() end
end

local function Update()
    if not frame:IsShown() then return end
    if Mode() == "live" and not InCombatLockdown() then P.Warm() end
    if CanLayout() then
        W.pendingLayout = false
        Layout(W.sizing)
    else
        W.pendingLayout = true
    end
    PaintAll()
    UpdateHeader()
    if Bar.frame:IsShown() then Bar.Update() end
end

function K.Refresh(reason)
    if reason then D.reasons[reason] = true end
    if K.interaction and Mode() ~= "source" then
        local ok, err = pcall(K.Scan)
        if not ok then geterrorhandler()(err) end
    end
    for _, fn in ipairs(D.callbacks) do
        local ok, err = pcall(fn, D.reasons)
        if not ok then geterrorhandler()(err) end
    end
    wipe(D.reasons)
    if frame:IsShown() then
        local ok, err = pcall(Update)
        if not ok then geterrorhandler()(err) end
    end
end

function K.RequestRefresh(delay, reason)
    if reason then D.reasons[reason] = true end
    if D.pending then return end
    D.pending = true
    C_Timer.After(delay or 0.03, function()
        D.pending = false
        if K.interaction or frame:IsShown() then K.Refresh() end
    end)
end

local paintPending = false
local function RequestPaint()
    if paintPending or not frame:IsShown() then return end
    paintPending = true
    C_Timer.After(0, function()
        paintPending = false
        if frame:IsShown() then
            PaintAll()
            PaintLock()
            grip:SetShown(not Locked())
        end
    end)
end

search:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    placeholder:SetShown(text == "" and not self:HasFocus())
    W.search = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    RequestPaint()
end)

---------------------------------------------------------------------------
-- Blättern und Größe ziehen
---------------------------------------------------------------------------

do
local function OnWheel(_, delta)
    if type(delta) ~= "number" or W.scrollMax <= 0 then return end
    SetScroll(W.scrollY - delta * (SlotSize() + M.GAP) * 1.5)
end

frame:EnableMouseWheel(true)
frame:SetScript("OnMouseWheel", OnWheel)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", OnWheel)
scrollTrack:SetScript("OnMouseWheel", OnWheel)

local function CursorY()
    local _, y = GetCursorPosition()
    return (y or 0) / (scrollTrack:GetEffectiveScale() or 1)
end

local function TrackFree()
    return (scrollTrack:GetHeight() or 0) - (scrollThumb:GetHeight() or 0)
end

scrollThumb:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    self.dragging = true
    self.startY = CursorY()
    self.startScroll = W.scrollY
    thumbLine:SetWidth(6)
    self:SetScript("OnUpdate", function(thumb)
        local free = TrackFree()
        if free <= 0 or W.scrollMax <= 0 then return end
        SetScroll(thumb.startScroll + (thumb.startY - CursorY()) / free * W.scrollMax)
    end)
end)
scrollThumb:SetScript("OnMouseUp", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    if not self:IsMouseOver() then thumbLine:SetWidth(4) end
end)
scrollThumb:SetScript("OnHide", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    thumbLine:SetWidth(4)
end)
scrollTrack:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local top = self:GetTop()
    local free = TrackFree()
    if not top or free <= 0 then return end
    local pos = top - CursorY() - (scrollThumb:GetHeight() or 0) / 2
    SetScroll(math.max(0, math.min(free, pos)) / free * W.scrollMax)
end)
end

do
local startW, startH, startCols

local function AnchorTopLeft()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return nil end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return left, top
end

frame:SetScript("OnSizeChanged", function()
    if not W.sizing then return end
    local w = frame:GetWidth()
    if type(w) ~= "number" then return end
    if math.abs(w - startW) >= 8 then
        W.liveCols = ColumnsForWidth(w)
    else
        W.liveCols = startCols
    end
    pcall(Layout, true)
end)

local function StopSizing()
    if not W.sizing then return end
    W.sizing = false
    frame:StopMovingOrSizing()
    local w, h = frame:GetSize()
    if ns.db and type(w) == "number" and type(h) == "number" then
        if math.abs(w - startW) >= 8 then
            ns.db.bagBankColumns = ColumnsForWidth(w)
            if ns.RefreshConfig then pcall(ns.RefreshConfig) end
        end
        if math.abs(h - startH) >= 19 then
            ns.db.bagBankHeight = math.max(M.MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
        end
    end
    W.liveCols = nil
    AnchorTopLeft()
    Layout(false)
    SavePosition()
    PaintAll()
end

grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or W.sizing or not ns.db or Locked() then return end
    if not CanLayout() then
        ns.Print(L["Größe ändern geht erst nach dem Kampf."])
        return
    end
    GameTooltip:Hide()
    startW, startH = frame:GetSize()
    if type(startW) ~= "number" or type(startH) ~= "number" then return end
    startCols = Columns()
    W.liveCols = startCols
    AnchorTopLeft()
    if pcall(frame.StartSizing, frame, "BOTTOMRIGHT") then
        W.sizing = true
    else
        W.liveCols = nil
    end
end)
grip:SetScript("OnMouseUp", function() StopSizing() end)
grip:SetScript("OnHide", function() StopSizing() end)
grip:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    if W.sizing then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Ziehen: Größe ändern"], 1, 1, 1)
    GameTooltip:AddLine(L["Breite in ganzen Spalten, Höhe frei. Passt nicht alles hinein, blätterst du mit dem Mausrad."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(L["Höhe wieder automatisch: im Bearbeitungsmodus Shift+Rechtsklick auf das Bankfenster."], C.textDim[1], C.textDim[2], C.textDim[3], true)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", function(self)
    self:SetAlpha(0.5)
    GameTooltip:Hide()
end)
end

---------------------------------------------------------------------------
-- Stil „forever“
---------------------------------------------------------------------------

function FX.Apply()
    if FX.done or FX.failed or not FX.On() then return end
    if InCombatLockdown() and AnyProtected(frame) then
        FX.retry = true
        return
    end
    FX.retry = false
    local S = ns.Style
    local made = {}
    local ok = pcall(function()
        local deco = CreateFrame("Frame", nil, frame)
        made[#made + 1] = deco
        deco:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, 5)
        deco:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
        deco:SetFrameLevel(frame:GetFrameLevel() + 1)
        S.Border(deco, { size = 8, cornerSize = 16, cornerOffset = 3 })
        made[#made + 1] = S.Fill(frame, "window")
        for _, item in ipairs(FX.btns) do
            local obj = S.Button(item.btn, item.kind or "secondary")
            made[#made + 1] = obj
            item.obj = obj
        end
        made[#made + 1] = S.EditBox(search)
        made[#made + 1] = S.Fill(Bar.frame, "window")
    end)
    if not ok then
        for _, o in ipairs(made) do FXHide(o) end
        FX.failed = true
        return
    end
    FX.done = true
    for _, o in ipairs(FX.stray) do FXHide(o) end

    local Pl = ns.Colors
    local function Set(t, c, a)
        t[1], t[2], t[3], t[4] = c[1], c[2], c[3], a or 1
    end
    Set(C.field, { 0.043, 0.043, 0.051 })
    Set(C.slot, { 0.043, 0.043, 0.051 })
    Set(C.slotEdge, { 0.33, 0.255, 0.125 })
    Set(C.itemEdge, { 0.46, 0.36, 0.18 })

    local function Tint(fs, c)
        if fs and c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    end
    local br = Pl.bronze or Pl.line
    for _, t in ipairs(FX.lines) do t:SetColorTexture(br[1], br[2], br[3], 0.85) end
    if FX.track then FX.track:SetColorTexture(br[1], br[2], br[3], 0.5) end
    W.hc.gold, W.hc.text, W.hc.dim = Pl.gold, Pl.gold or Pl.text, Pl.textDim
    W.hc.line = { br[1], br[2], br[3], 0.85 }

    pcall(title.SetFont, title, S.FontTitle(), 15, "")
    pcall(Bar.title.SetFont, Bar.title, S.FontTitle(), 13, "")
    Tint(title, Pl.gold)
    Tint(Bar.title, Pl.gold)
    Tint(slotsText, Pl.textDim)
    Tint(placeholder, Pl.textFaint)
    Tint(emptyText, Pl.textDim)
    Tint(moneyText, Pl.text)
    Tint(Bar.hint, Pl.textDim)
    search:SetTextColor(Pl.text[1], Pl.text[2], Pl.text[3])
    for _, item in ipairs(FX.btns) do
        if item.text and item.obj and item.obj.textColor then Tint(item.text, item.obj.textColor) end
    end
    for _, h in ipairs(W.headers) do pcall(h.label.SetFont, h.label, S.FontTitle(), 13, "") end

    grip:ClearAllPoints()
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    local nt = grip.GetNormalTexture and grip:GetNormalTexture()
    local bl = Pl.bronzeLight or br
    if nt then pcall(nt.SetVertexColor, nt, bl[1], bl[2], bl[3]) end

    PaintLock()
    if frame:IsShown() then K.RequestRefresh(0, "layout") end
end

---------------------------------------------------------------------------
-- Kopf- und Fußknöpfe
---------------------------------------------------------------------------

close:SetScript("OnClick", function() K.Close() end)

local function CombatBlocked()
    if InCombatLockdown() then
        ns.Print(L["Sortieren geht erst nach dem Kampf."])
        return true
    end
    return false
end

sortBtn:SetScript("OnClick", function()
    if CombatBlocked() then return end
    if not BK.Sort() then ns.Print(L["Sortieren hat nicht geklappt."]) end
    K.RequestRefresh(0.3, "bag")
end)
sortBtn:SetScript("OnEnter", function(self)
    Tip(self, L["Bank sortieren"], L["Sortiert die Plätze der Bank nach Blizzards Regeln. Geht nicht im Kampf."])
end)

depositBtn:SetScript("OnClick", function()
    if CombatBlocked() then return end
    BK.Deposit()
    K.RequestRefresh(0.3, "bag")
end)
depositBtn:SetScript("OnEnter", function(self)
    Tip(self, L["Alles einlagern"], L["Lagert passende Gegenstände aus deinen Taschen in die Bank ein (Blizzards „Alles einlagern“)."])
end)

bagsBtn:SetScript("OnClick", function() Bar.Toggle() end)
bagsBtn:SetScript("OnEnter", function(self)
    Tip(self, L["Banktaschen"], L["Zeigt die Taschenplätze der Bank: Taschen einsetzen oder herausnehmen und weitere Plätze kaufen."])
end)

blizzBtn:SetScript("OnClick", function() K.HandBack() end)
blizzBtn:SetScript("OnEnter", function(self)
    Tip(self, L["Blizzards Bankfenster zeigen"],
        L["Blendet Blizzards eigene Bank statt dieses Fensters ein (z. B. für die Kriegsmeute-Bank oder Tab-Einstellungen). Beim nächsten Besuch beim Bankier übernimmt stray wieder."],
        "ANCHOR_TOPLEFT")
end)
blizzBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function RefreshTexts()
    placeholder:SetText(L["Suchen …"])
    emptyText:SetText(Mode() == "live" and L["Diese Bank hat noch keine Plätze."] or L["Keine Gegenstände."])
    LabelHeadButton(sortBtn, L["Sortieren"])
    LabelHeadButton(depositBtn, L["Einlagern"])
    LabelHeadButton(bagsBtn, L["Banktaschen"])
    blizzBtn.label:SetText(L["Blizzard-Bank"])
    blizzBtn:SetWidth(math.max(40, math.floor((blizzBtn.label:GetStringWidth() or 60) + 14)))
end

---------------------------------------------------------------------------
-- Blizzards BankFrame parken / zurückgeben
---------------------------------------------------------------------------

-- Sichtbarer, aber unsichtbarer und winziger Rahmen (Alpha 0, Maßstab ~0): Blizzards BankFrame bleibt
-- „offen“ (IsShown, BankPanel aktiv), ohne zu stören oder Mausklicks zu fangen.
local park = CreateFrame("Frame", "strayBankPark", UIParent)
park:SetSize(1, 1)
park:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
park:SetScale(0.001)
park:SetAlpha(0)
park:EnableMouse(false)
local origParent

function K.IsParked()
    local bf = _G.BankFrame
    if not bf then return false end
    local ok, parent = pcall(bf.GetParent, bf)
    return ok and parent == park
end

function K.Park()
    local bf = _G.BankFrame
    if not bf or InCombatLockdown() then return false end
    local ok, parent = pcall(bf.GetParent, bf)
    if not ok then return false end
    if parent == park then return true end
    origParent = parent or UIParent
    return (pcall(bf.SetParent, bf, park))
end

function K.Unpark()
    local bf = _G.BankFrame
    if not bf or not K.IsParked() then return true end
    if InCombatLockdown() then D.needUnpark = true return false end
    D.needUnpark = false
    return (pcall(bf.SetParent, bf, origParent or UIParent))
end

---------------------------------------------------------------------------
-- Öffnen und Schließen
---------------------------------------------------------------------------

local function PlayOpenSound(open)
    local kit = SOUNDKIT and (open and SOUNDKIT.IG_BACKPACK_OPEN or SOUNDKIT.IG_BACKPACK_CLOSE)
    if kit then pcall(PlaySound, kit) end
end

frame:SetScript("OnShow", function()
    pcall(FX.Apply)
    pcall(RefreshTexts)
    pcall(PaintLock)
    grip:SetShown(not Locked())
    PlayOpenSound(true)
    K.Refresh("open")
    Bar.Apply()
    Fire("shown")
end)

frame:SetScript("OnHide", function()
    search:ClearFocus()
    Bar.shown = false
    Bar.frame:Hide()
    PlayOpenSound(false)
    W.preview = false
    if K.interaction and not D.suppressClose then
        BK.CloseInteraction()
    end
    if D.openedBags then
        D.openedBags = false
        if B.IsOpen and B.IsOpen() then pcall(B.Close) end
    end
    Fire("hidden")
end)

-- Fenster verbergen (im Kampf mit geschützten Knöpfen erst danach)
local function SafeHide()
    if not frame:IsShown() then return true end
    if InCombatLockdown() and AnyProtected(frame) then
        W.pendingHide = true
        return false
    end
    frame:Hide()
    return true
end

function K.IsOpen() return frame:IsShown() end
function K.IsLive() return frame:IsShown() and Mode() == "live" and K.interaction end

-- Übernahme: eigenes Fenster zeigen, Blizzards BankFrame unsichtbar parken
function K.Takeover()
    if not K.interaction then return false end
    if not K.Wanted() then
        K.Unpark()
        return false
    end
    if D.forceBlizzard then return false end
    if frame:IsShown() and Mode() == "live" then
        K.Park()
        return true
    end
    if InCombatLockdown() then return false end
    if not BK.Model() or not BK.CanView() or P.broken then return false end
    K.source = nil
    W.preview = false
    pcall(K.Scan)
    if not P.Warm() then return false end
    frame:Show()
    if not frame:IsShown() then return false end
    K.Park()
    -- Taschenfenster mit öffnen (und beim Schließen der Bank wieder zu, falls wir es geöffnet haben);
    -- nur, wenn die Bank es öffnen darf (Schalter „Bei der Bank öffnen“, „Taschen nicht automatisch öffnen“)
    if B.Enabled() and B.Open and B.IsOpen and not B.IsOpen()
        and (not B.AutoAllowed or B.AutoAllowed("BankFrame")) then
        if B.Open() then
            D.openedBags = true
            B.openerName = "BankFrame"
        end
    end
    return true
end

function K.Open()
    if frame:IsShown() then return true end
    if K.source then
        frame:Show()
        return frame:IsShown()
    end
    if K.interaction then return K.Takeover() end
    return false
end

function K.Close()
    D.suppressClose = false
    return SafeHide()
end

function K.Toggle()
    if frame:IsShown() then return K.Close() end
    return K.Open()
end

function K.SetSource(src)
    if src ~= nil and not (type(src) == "table" and type(src.sections) == "function") then src = nil end
    K.source = src
    W.preview = false
    if frame:IsShown() then
        if src == nil and not (K.interaction and K.Wanted() and not D.forceBlizzard) then
            D.suppressClose = true
            SafeHide()
            D.suppressClose = false
        else
            Bar.Apply()
            K.RequestRefresh(0, "source")
        end
    end
    Fire("source")
end

-- „Blizzard-Bank zeigen“ und Rückgabe bei ausgeschaltetem Schalter
function K.HandBack()
    D.forceBlizzard = true
    D.suppressClose = true
    SafeHide()
    D.suppressClose = false
    K.Unpark()
end

local function InteractionOpened()
    local first = not K.interaction
    K.interaction = true
    if first then
        D.forceBlizzard = false
        D.scanned = false
    end
    K.Takeover()
    if first then
        K.RequestRefresh(0, "open")
        Fire("open")
    end
end

local function InteractionClosed()
    if not K.interaction then return end
    K.interaction = false
    D.forceBlizzard = false
    D.scanned = false
    if Mode() == "live" and frame:IsShown() then
        D.suppressClose = true
        SafeHide()
        D.suppressClose = false
    end
    C_Timer.After(0, function() K.Unpark() end)
    K.Refresh("close")
    Fire("close")
end

-- Option geändert: sofort übernehmen bzw. zurückgeben
function K.Sync()
    if not K.interaction then return end
    if K.Wanted() then
        if not frame:IsShown() and not D.forceBlizzard then K.Takeover() end
    elseif frame:IsShown() and Mode() == "live" then
        K.HandBack()
    else
        K.Unpark()
    end
end

-- Auffangnetz: Schalter wurde ausgeschaltet, während das Fenster offen ist
do
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.5 then return end
        acc = 0
        if Mode() == "live" and K.interaction and not K.Wanted() then K.HandBack() end
    end)
end

---------------------------------------------------------------------------
-- Bearbeitungsmodus (Position, Höhe)
---------------------------------------------------------------------------

do
local function NormalizeHeight()
    if not ns.db then return end
    local h = tonumber(ns.db.bagBankHeight)
    if not h or IsSecret(h) or h <= 0 then
        ns.db.bagBankHeight = 0
    else
        ns.db.bagBankHeight = math.max(M.MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
    end
end

ns.RegisterMovable(frame, "Bankfenster", function(on)
    if on then
        if K.Wanted() and not frame:IsShown() and not K.interaction and not K.source then
            W.preview = true
            frame:Show()
        end
    elseif W.preview then
        W.preview = false
        SafeHide()
    end
end, {
    heightKey = "bagBankHeight",
    heightMin = 0,
    heightMax = M.MAX_H,
    onSize = function(which)
        if which ~= "height" then return end
        NormalizeHeight()
        K.RequestRefresh(0, "layout")
    end,
})
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    local h = tonumber(ns.db.bagBankHeight)
    ns.db.bagBankHeight = (h and h > 0) and math.max(M.MIN_H, math.min(M.MAX_H, math.floor(h + 0.5))) or 0
    pcall(FX.Apply)
    UpdateResizeBounds()
    ns.RestorePosition(frame)
    PaintLock()
    grip:SetShown(not Locked())
    -- Blizzards BankFrame: Auf-/Zugehen verfolgen (HookScript, keine Funktion wird ersetzt)
    local bf = _G.BankFrame
    if bf and bf.HookScript then
        pcall(bf.HookScript, bf, "OnShow", function() InteractionOpened() end)
        pcall(bf.HookScript, bf, "OnHide", function() InteractionClosed() end)
        if bf:IsShown() then InteractionOpened() end
    end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if FX.retry then pcall(FX.Apply) end
    if W.pendingHide then
        W.pendingHide = false
        if not (K.interaction and Mode() == "live") then SafeHide() end
    end
    if D.needUnpark then K.Unpark() end
    if P.needWarm and (K.interaction or frame:IsShown()) then P.Warm() end
    if W.pendingLayout and frame:IsShown() then K.RequestRefresh(0, "layout") end
    if K.interaction and K.Wanted() and not frame:IsShown() and not D.forceBlizzard then K.Takeover() end
end)

do
    local ev = CreateFrame("Frame")
    local list = {
        "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
        "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "BAG_CONTAINER_UPDATE",
        "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "PLAYER_MONEY",
    }
    for _, event in ipairs(list) do pcall(ev.RegisterEvent, ev, event) end
    ev:SetScript("OnEvent", function(_, event)
        if event == "BANKFRAME_OPENED" then
            C_Timer.After(0, InteractionOpened)
        elseif event == "BANKFRAME_CLOSED" then
            InteractionClosed()
        elseif event == "PLAYER_MONEY" then
            if frame:IsShown() then UpdateHeader() end
        elseif K.interaction or frame:IsShown() then
            local reason = (event == "ITEM_LOCK_CHANGED") and "lock"
                or (event == "BAG_UPDATE_COOLDOWN") and "cooldown" or "bag"
            K.RequestRefresh(event == "BAG_UPDATE_COOLDOWN" and 0.1 or 0.03, reason)
        end
    end)
end

---------------------------------------------------------------------------
-- Optionen (Bereich „Bank“)
---------------------------------------------------------------------------

local function BagWindowOn()
    return ns.db and ns.db.bagWindow and true or false
end

local function BankOn()
    return ns.db and ns.db.bagWindow and ns.db.bagBank and true or false
end

ns.AddOption(1, "Bank", {
    key = "bagBank",
    label = L["stray-Bank"],
    tooltip = L["Ersetzt Blizzards Bankfenster durch ein eigenes Fenster im Stil der stray-Tasche: ein Abschnitt je Banktab bzw. Banktasche, Suche, Sortieren, „Alles einlagern“ und eine Leiste für die Banktaschen (einsetzen, herausnehmen, Plätze kaufen). Rechtsklick auf einen Gegenstand lagert ihn ein oder aus, wie gewohnt.\n\nWirkt nur, wenn auch „stray-Tasche“ eingeschaltet ist. Blizzards Bank bleibt unsichtbar im Hintergrund geöffnet; „Blizzard-Bank“ unten links im Fenster zeigt sie wieder (z. B. für die Kriegsmeute-Bank). Im Kampf oder bei Fehlern bleibt Blizzards Bank."],
    keywords = { "bank", "bankier", "lager", "banktasche", "banktaschen", "bankfach", "bank tab", "bank bags", "stray-bank" },
    isEnabled = BagWindowOn,
    disabledHint = L["Erst „stray-Tasche“ einschalten (weiter oben)."],
    set = function(value)
        ns.db.bagBank = value
        K.Sync()
    end,
})

ns.AddOption(1, "Bank", {
    key = "bagBankColumns",
    type = "slider",
    label = L["Spalten (Bank)"],
    min = B.C.MIN_COLS, max = B.C.MAX_COLS, step = 1,
    tooltip = L["Wie viele Plätze im Bankfenster nebeneinander stehen. Ziehst du das Fenster unten rechts breiter oder schmaler, ändert sich dieser Wert mit."],
    keywords = { "spalten", "breite", "bank", "columns", "width" },
    isEnabled = BankOn,
    disabledHint = L["Erst „stray-Bank“ einschalten (direkt darüber)."],
    set = function(value)
        ns.db.bagBankColumns = value
        K.RequestRefresh(0, "layout")
    end,
})
