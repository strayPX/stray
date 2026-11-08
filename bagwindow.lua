-- stray – Eigenes Taschenfenster
-- Alle normalen Taschen (0–4) in einem Fenster: Kopf mit Belegung, Suche und Schließen,
-- links Kategorien mit Anzahl, rechts das Raster, unten das Gold.
-- Die Gegenstandsknöpfe nutzen Blizzards ContainerFrameItemButtonTemplate und hängen in
-- Elternrahmen, deren ID die Taschennummer ist – so verhalten sie sich wie Blizzards
-- Taschenplätze (benutzen, verkaufen, anlegen, ziehen, verlinken, Tooltip).
-- Blizzard-Tabellen werden nicht verändert: nur hooksecurefunc und Hide() auf die Taschenrahmen.
-- Größe unten rechts ziehen: Breite rastet auf Spalten ein (bagColumns), Höhe ist frei (bagHeight).
-- Passt nicht alles hinein, wird zeilenweise geblättert (Knöpfe neu setzen statt ScrollFrame).
-- Ansicht „Alle“: oben eine Anheft-Leiste (so viele Plätze wie Spalten). Gegenstand hineinziehen
-- heftet ihn an (bagPinned.slots[Platz] = Item-ID); der echte Taschenknopf rückt dann in die
-- Leiste und fehlt unten im Raster. Shift+Rechtsklick oder Herausziehen löst ihn.

local _, ns = ...
local L = ns.L

ns.defaults.bagHeight = 0 -- 0 = Höhe automatisch nach Inhalt

local IsSecret = ns.IsSecret

---------------------------------------------------------------------------
-- Maße und Farben (lila stray-Look aus ns.Colors, Ersatzwerte falls es sie nicht gibt)
---------------------------------------------------------------------------

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BODY = "Fonts\\ARIALN.TTF"
local QUEST_BANG = TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang"
local QUEST_BORDER = TEXTURE_ITEM_QUEST_BORDER or "Interface\\ContainerFrame\\UI-Icon-QuestBorder"

local PALETTE = type(ns.Colors) == "table" and ns.Colors or {}
local function Col(key, fallback)
    local c = PALETTE[key]
    if type(c) == "table" and type(c[1]) == "number" then return c end
    return fallback
end

local C = {
    bg         = Col("bg", { 0.078, 0.078, 0.098, 0.96 }),
    side       = Col("card", { 0.094, 0.094, 0.118, 1 }),
    hover      = Col("hover", { 0.122, 0.122, 0.153, 1 }),
    border     = Col("line", { 0.149, 0.149, 0.184, 1 }),
    line       = Col("line", { 0.149, 0.149, 0.184, 1 }),
    accent     = Col("accent", { 0.545, 0.486, 0.965, 1 }),
    accentText = Col("accentText", { 0.702, 0.659, 0.980, 1 }),
    text       = Col("text", { 0.902, 0.902, 0.925, 1 }),
    textDim    = Col("textDim", { 0.545, 0.545, 0.600, 1 }),
    textFaint  = Col("textFaint", { 0.369, 0.369, 0.420, 1 }),
    field      = { 0.055, 0.055, 0.071, 1 },  -- Suchfeld/Knöpfe, etwas dunkler als das Fenster
    slot       = { 0.051, 0.051, 0.064, 1 },
    slotEdge   = { 0.149, 0.149, 0.184, 1 },
    itemEdge   = { 0.235, 0.235, 0.286, 1 },  -- Gegenstand ohne Qualitätsfarbe
    quest      = { 1, 0.82, 0, 1 },
    triage     = { 1, 0.32, 0.22, 1 },
}

local SLOT, GAP = 34, 4
local SIDE_W = 122
local PAD = 10
local HEAD = 40
local FOOT = 28
local CAT_H = 22
local MIN_W = 440
local BAR_W = 6 -- zusätzlicher Rand rechts für den Scrollbalken
local MIN_COLS, MAX_COLS = 6, 16
local MAX_H = 900
local GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
local GRIP_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"
local SORT_ATLAS = "bags-button-autosort-up"

local FIRST_BAG = 0
local LAST_BAG = (type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS) or 4

-- label = deutscher Schlüssel, übersetzt wird erst beim Anzeigen (Sprache umschaltbar)
local CATEGORIES = {
    { key = "all", label = "Alle" },
    { key = "gear", label = "Ausrüstung" },
    { key = "consumable", label = "Verbrauchbar" },
    { key = "trade", label = "Handwerk" },
    { key = "quest", label = "Quest" },
    { key = "new", label = "Neu" },
}

local ITEM_CLASS = (Enum and Enum.ItemClass) or {}
local CL_CONSUMABLE = ITEM_CLASS.Consumable or 0
local CL_WEAPON = ITEM_CLASS.Weapon or 2
local CL_ARMOR = ITEM_CLASS.Armor or 4
local CL_REAGENT = ITEM_CLASS.Reagent or 5
local CL_TRADE = ITEM_CLASS.Tradegoods or 7
local CL_QUEST = ITEM_CLASS.Questitem or 12

---------------------------------------------------------------------------
-- API-Hüllen (C_Container auf modernem Client, sonst alte Globale)
---------------------------------------------------------------------------

local Container = C_Container or {}

local function Public(v)
    if IsSecret(v) then return nil end
    return v
end

local function NumSlots(bag)
    local fn = Container.GetContainerNumSlots or GetContainerNumSlots
    if not fn then return 0 end
    local ok, n = pcall(fn, bag)
    if not ok or IsSecret(n) or type(n) ~= "number" then return 0 end
    return n
end

local function FreeSlots(bag)
    local fn = Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not fn then return nil end
    local ok, free, family = pcall(fn, bag)
    if not ok or IsSecret(free) or IsSecret(family) then return nil end
    return free, family
end

local function SlotInfo(bag, slot)
    if Container.GetContainerItemInfo then
        local ok, info = pcall(Container.GetContainerItemInfo, bag, slot)
        if not ok or type(info) ~= "table" then return nil end
        return Public(info.iconFileID), Public(info.stackCount), Public(info.isLocked),
            Public(info.quality), Public(info.hyperlink), Public(info.itemID)
    end
    if GetContainerItemInfo then
        local ok, icon, count, locked, quality, _, _, link, _, _, itemID = pcall(GetContainerItemInfo, bag, slot)
        if not ok then return nil end
        return Public(icon), Public(count), Public(locked), Public(quality), Public(link), Public(itemID)
    end
end

local function QuestInfo(bag, slot)
    local fn = Container.GetContainerItemQuestInfo or GetContainerItemQuestInfo
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, bag, slot)
    if not ok then return nil end
    if type(a) == "table" then a, b, c = a.isQuestItem, a.questID or a.questId, a.isActive end
    return Public(a), Public(b), Public(c)
end

local function SlotCooldown(bag, slot)
    local fn = Container.GetContainerItemCooldown or GetContainerItemCooldown
    if not fn then return nil end
    local ok, start, duration, enable = pcall(fn, bag, slot)
    if not ok then return nil end
    return start, duration, enable
end

local function IsNew(bag, slot)
    if not (C_NewItems and C_NewItems.IsNewItem) then return false end
    local ok, new = pcall(C_NewItems.IsNewItem, bag, slot)
    return ok and not IsSecret(new) and new == true
end

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local classCache = {}

local function ClassOf(itemID, link)
    local key = itemID or link
    if not key or not GetInstant then return nil end
    local cached = classCache[key]
    if cached ~= nil then return cached or nil end
    local ok, _, _, _, _, _, classID = pcall(GetInstant, key)
    if not ok or IsSecret(classID) or type(classID) ~= "number" then
        classCache[key] = false
        return nil
    end
    classCache[key] = classID
    return classID
end

local function QualityColor(q)
    if type(q) ~= "number" then return nil end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then return c.r, c.g, c.b end
    local fn = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if fn then
        local ok, r, g, b = pcall(fn, q)
        if ok and type(r) == "number" then return r, g, b end
    end
end

local function NameFromLink(link)
    if type(link) ~= "string" then return nil end
    return link:match("%[(.-)%]")
end

local function SafeName(f)
    if not f or not f.GetName then return nil end
    local ok, name = pcall(f.GetName, f)
    return ok and name or nil
end

---------------------------------------------------------------------------
-- Angeheftete Gegenstände: ns.db.bagPinned = { slots = { [Platz] = Item-ID }, [Item-ID] = true }
-- Die Liste [Item-ID] = true bleibt mit, weil triage.lua angeheftete Gegenstände so erkennt.
---------------------------------------------------------------------------

local HEARTHSTONE = 6948
local MAX_PINS = MAX_COLS

local function SyncPinMap(p)
    for k in pairs(p) do
        if type(k) == "number" then p[k] = nil end
    end
    for i = 1, MAX_PINS do
        local id = p.slots[i]
        if type(id) == "number" then p[id] = true end
    end
end

-- Plätze der Anheft-Leiste; stellt das alte Format ([Item-ID] = true) einmalig um:
-- Ruhestein auf Platz 1, bisher angeheftete Gegenstände dahinter.
local function PinSlots()
    if not ns.db then return {} end
    local p = ns.db.bagPinned
    if type(p) ~= "table" then
        p = {}
        ns.db.bagPinned = p
    end
    if type(p.slots) ~= "table" then
        local old = {}
        for k, v in pairs(p) do
            if type(k) == "number" and v and k ~= HEARTHSTONE then old[#old + 1] = k end
        end
        table.sort(old)
        local slots = { HEARTHSTONE }
        for _, id in ipairs(old) do
            if #slots >= MAX_PINS then break end
            slots[#slots + 1] = id
        end
        p.slots = slots
        SyncPinMap(p)
    end
    return p.slots
end

local function PinIndexOf(itemID)
    local slots = PinSlots()
    for i = 1, MAX_PINS do
        if slots[i] == itemID then return i end
    end
end

local function Columns()
    local n = ns.db and tonumber(ns.db.bagColumns) or 10
    n = math.floor(n + 0.5)
    if n < MIN_COLS then n = MIN_COLS elseif n > MAX_COLS then n = MAX_COLS end
    return n
end

---------------------------------------------------------------------------
-- Größen: Breite folgt den Spalten, Höhe automatisch oder fest (bagHeight)
---------------------------------------------------------------------------

local CAT_TOTAL = #CATEGORIES * CAT_H
local MIN_H = HEAD + PAD + CAT_TOTAL + PAD + FOOT

local function GridSize(n)
    if n < 1 then return 0 end
    return n * SLOT + (n - 1) * GAP
end

local function WidthFor(cols)
    return math.max(MIN_W, SIDE_W + PAD * 2 + BAR_W + GridSize(cols))
end

local MAX_W = WidthFor(MAX_COLS)

local function MaxHeight()
    local h = UIParent and UIParent:GetHeight()
    if type(h) ~= "number" or IsSecret(h) or h <= MIN_H then return MAX_H end
    return math.max(MIN_H, math.min(MAX_H, math.floor(h - 20)))
end

-- Wie viele ganze Spalten passen in diese Fensterbreite?
local function ColumnsForWidth(w)
    local n = math.floor((w - SIDE_W - PAD * 2 - BAR_W + GAP) / (SLOT + GAP))
    if n < MIN_COLS then n = MIN_COLS elseif n > MAX_COLS then n = MAX_COLS end
    return n
end

-- Höhe der Anheft-Leiste samt Abstand und lila Linie darunter
local PIN_H = SLOT + GAP * 2 + 1

-- Wie viele ganze Reihen passen in diese Fensterhöhe? (pinH = Höhe der Anheft-Leiste oder 0)
local function RowsForHeight(h, pinH)
    local n = math.floor((h - HEAD - PAD * 2 - FOOT - (pinH or 0) + GAP) / (SLOT + GAP))
    return math.max(1, n)
end

-- Gespeicherte feste Höhe oder nil (= automatisch)
local function FixedHeight()
    local h = ns.db and tonumber(ns.db.bagHeight)
    if not h or h <= 0 then return nil end
    return math.max(MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
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

local function Text(parent, size, c, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or FONT, size, "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "strayBagFrame", UIParent)
frame:SetSize(MIN_W, 300)
frame:SetFrameStrata("MEDIUM")
frame:SetToplevel(true)
frame:Hide()
tinsert(UISpecialFrames, "strayBagFrame") -- Esc schließt

Tex(frame, "BACKGROUND", C.bg):SetAllPoints()
Border(frame, C.border)

ns.MakeMovable(frame, "bagwindow", { "BOTTOMRIGHT", "BOTTOMRIGHT", -16, 96 })

-- Position immer als rechte untere Ecke speichern, damit das Fenster nach oben wächst
local function SavePosition(right, bottom)
    if not (right and bottom) then right, bottom = frame:GetRight(), frame:GetBottom() end
    local uiRight = UIParent:GetRight()
    if not (right and bottom and uiRight) or not ns.db then return end
    ns.db.positions.bagwindow = { "BOTTOMRIGHT", "BOTTOMRIGHT", right - uiRight, bottom }
end

local sizing = false -- Größe wird gerade gezogen (Verschieben und Ziehen schließen sich aus)

frame:SetScript("OnDragStop", function(self)
    if sizing then return end
    self:StopMovingOrSizing()
    SavePosition()
end)

local function Reanchor()
    local right, bottom = frame:GetRight(), frame:GetBottom()
    if not (right and bottom) then return end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
end

-- Kopf: ohne Shift ziehbar
local head = CreateFrame("Frame", nil, frame)
head:SetPoint("TOPLEFT", 1, -1)
head:SetPoint("TOPRIGHT", -1, -1)
head:SetHeight(HEAD - 1)
head:EnableMouse(true)
head:RegisterForDrag("LeftButton")
head:SetScript("OnDragStart", function() if not sizing then frame:StartMoving() end end)
head:SetScript("OnDragStop", function()
    if sizing then return end
    frame:StopMovingOrSizing()
    SavePosition()
end)

local headLine = Tex(frame, "BORDER", C.line)
headLine:SetPoint("TOPLEFT", 1, -HEAD); headLine:SetPoint("TOPRIGHT", -1, -HEAD); headLine:SetHeight(1)

local title = Text(head, 14, C.text)
title:SetPoint("LEFT", 12, 0)

local slotsText = Text(head, 12, C.textDim, FONT_BODY)
slotsText:SetPoint("LEFT", title, "RIGHT", 10, -1)

local close = CreateFrame("Button", nil, head)
close:SetSize(22, 22)
close:SetPoint("RIGHT", -8, 0)
Border(close, C.border)
local closeText = Text(close, 12, C.textDim, FONT_BODY)
closeText:SetPoint("CENTER", 1, 0)
closeText:SetText("X")
local closeHover = close:CreateTexture(nil, "HIGHLIGHT")
closeHover:SetAllPoints()
closeHover:SetColorTexture(1, 1, 1, 0.07)
close:SetScript("OnClick", function() frame:Hide() end)

local search = CreateFrame("EditBox", "strayBagSearch", head)
search:SetSize(170, 22)
search:SetPoint("RIGHT", close, "LEFT", -8, 0)
search:SetAutoFocus(false)
search:SetFont(FONT_BODY, 12, "")
search:SetTextColor(C.text[1], C.text[2], C.text[3])
search:SetTextInsets(8, 8, 0, 0)
search:SetMaxLetters(40)
Tex(search, "BACKGROUND", C.field):SetAllPoints()
Border(search, C.line)
local placeholder = Text(search, 12, C.textFaint, FONT_BODY)
placeholder:SetPoint("LEFT", 8, 0)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
search:SetScript("OnEditFocusLost", function(self) placeholder:SetShown(self:GetText() == "") end)

-- „Sortieren“ links neben der Suche (Besen wie bei Blizzards Taschen)
local sortButton = CreateFrame("Button", nil, head)
sortButton:SetSize(22, 22)
sortButton:SetPoint("RIGHT", search, "LEFT", -6, 0)
Tex(sortButton, "BACKGROUND", C.field):SetAllPoints()
Border(sortButton, C.border)
local sortIcon = sortButton:CreateTexture(nil, "ARTWORK")
sortIcon:SetPoint("TOPLEFT", 2, -2)
sortIcon:SetPoint("BOTTOMRIGHT", -2, 2)
local sortAtlasOk = false
if sortIcon.SetAtlas then
    local okSet, result = pcall(sortIcon.SetAtlas, sortIcon, SORT_ATLAS)
    sortAtlasOk = okSet and result ~= false
end
if sortAtlasOk and sortIcon.GetAtlas then
    local okGet, atlas = pcall(sortIcon.GetAtlas, sortIcon)
    sortAtlasOk = okGet and atlas ~= nil
end
if not sortAtlasOk then
    -- Ersatz, falls es den Atlas nicht gibt: Buchstabe statt Besen
    sortIcon:Hide()
    local sortText = Text(sortButton, 12, C.textDim, FONT_BODY)
    sortText:SetPoint("CENTER", 1, 0)
    sortText:SetText("S")
end
local sortHover = sortButton:CreateTexture(nil, "HIGHLIGHT")
sortHover:SetAllPoints()
sortHover:SetColorTexture(1, 1, 1, 0.10)
sortButton:SetScript("OnMouseDown", function() sortIcon:SetVertexColor(0.7, 0.7, 0.7) end)
sortButton:SetScript("OnMouseUp", function() sortIcon:SetVertexColor(1, 1, 1) end)
sortButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Taschen sortieren"])
    GameTooltip:Show()
end)
sortButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
sortButton:SetScript("OnClick", function()
    if InCombatLockdown() then
        ns.Print(L["Sortieren geht erst nach dem Kampf."])
        return
    end
    if not (C_Container and C_Container.SortBags) then
        ns.Print(L["Sortieren gibt es in diesem Client nicht."])
        return
    end
    if SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then pcall(PlaySound, SOUNDKIT.UI_BAG_SORTING_01) end
    local ok = pcall(C_Container.SortBags)
    if not ok then ns.Print(L["Sortieren hat nicht geklappt."]) end
    -- Neu gezeichnet wird über BAG_UPDATE_DELAYED, sobald WoW die Gegenstände verschoben hat
end)

-- Seitenleiste
local sideBg = Tex(frame, "BACKGROUND", C.side, 1)
sideBg:SetPoint("TOPLEFT", 1, -HEAD - 1)
sideBg:SetPoint("BOTTOMLEFT", 1, FOOT + 1)
sideBg:SetWidth(SIDE_W - 1)
local sideLine = Tex(frame, "BORDER", C.line)
sideLine:SetPoint("TOPLEFT", SIDE_W, -HEAD - 1)
sideLine:SetPoint("BOTTOMLEFT", SIDE_W, FOOT + 1)
sideLine:SetWidth(1)

-- Raster
local grid = CreateFrame("Frame", nil, frame)
grid:SetPoint("TOPLEFT", SIDE_W + PAD, -HEAD - PAD)
grid:SetSize(SLOT, SLOT)

local emptyText = Text(frame, 12, C.textDim, FONT_BODY)
emptyText:SetPoint("TOPLEFT", grid, "TOPLEFT", 2, -4)
emptyText:Hide()

-- Scrollbalken rechts neben dem Raster (Stil wie ui.lua). Die Klickfläche ist breiter
-- als die sichtbare Linie, damit man sie gut trifft.
local scrollTrack = CreateFrame("Button", nil, frame)
scrollTrack:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -HEAD - PAD)
scrollTrack:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, FOOT + PAD)
scrollTrack:SetWidth(10)
scrollTrack:SetFrameLevel(frame:GetFrameLevel() + 20)
scrollTrack:EnableMouseWheel(true)
local trackLine = scrollTrack:CreateTexture(nil, "ARTWORK")
trackLine:SetPoint("TOP")
trackLine:SetPoint("BOTTOM")
trackLine:SetWidth(4)
trackLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6)
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

-- Ziehgriff unten rechts (wie beim DMG-Meter)
local grip = CreateFrame("Button", nil, frame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
grip:SetFrameLevel(frame:GetFrameLevel() + 30)
grip:SetNormalTexture(GRIP_UP)
grip:SetPushedTexture(GRIP_DOWN)
grip:SetHighlightTexture(GRIP_HIGHLIGHT)
grip:SetAlpha(0.5)

frame:SetResizable(true)
if not pcall(frame.SetResizeBounds, frame, MIN_W, MIN_H, MAX_W, MAX_H) then
    if frame.SetMinResize then pcall(frame.SetMinResize, frame, MIN_W, MIN_H) end
    if frame.SetMaxResize then pcall(frame.SetMaxResize, frame, MAX_W, MAX_H) end
end

-- Fuß
local footLine = Tex(frame, "BORDER", C.line)
footLine:SetPoint("BOTTOMLEFT", 1, FOOT); footLine:SetPoint("BOTTOMRIGHT", -1, FOOT); footLine:SetHeight(1)

local moneyText = Text(frame, 12, C.text, FONT_BODY)
moneyText:SetPoint("BOTTOMLEFT", 12, 8)

local hintText = Text(frame, 11, C.textDim, FONT_BODY)
hintText:SetPoint("BOTTOMRIGHT", -22, 9) -- rechts daneben sitzt der Ziehgriff
hintText:SetJustifyH("RIGHT")

-- „Löschkandidat aufnehmen“ (nur sichtbar, wenn triage.lua einen Kandidaten meldet)
local triageButton = CreateFrame("Button", nil, frame)
triageButton:SetHeight(18)
triageButton:SetPoint("RIGHT", hintText, "LEFT", -12, 0)
Border(triageButton, { C.triage[1], C.triage[2], C.triage[3], 0.8 })
local triageHover = triageButton:CreateTexture(nil, "HIGHLIGHT")
triageHover:SetAllPoints()
triageHover:SetColorTexture(1, 1, 1, 0.07)
local triageLabel = Text(triageButton, 11, C.text, FONT_BODY)
triageLabel:SetPoint("CENTER", 0, 0)
triageButton:SetWidth(150)
triageButton:SetScript("OnClick", function()
    if ns.TriagePickup then ns.TriagePickup() end
end)
triageButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Löschkandidat aufnehmen"])
    GameTooltip:AddLine(L["Legt den rot markierten, billigsten Gegenstand auf den Mauszeiger. stray löscht nichts selbst – das Zerstören bestätigst du bei WoW."], 1, 1, 1, true)
    GameTooltip:Show()
end)
triageButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
triageButton:Hide()

---------------------------------------------------------------------------
-- Kategorien
---------------------------------------------------------------------------

local selected = "all"
local catButtons = {}
local RequestUpdate
-- Blättern: erste sichtbare Reihe, größtmöglicher Wert, sichtbare und gesamte Reihen
local scrollRow, scrollMax, viewRows, totalRows = 0, 0, 1, 1

for i, cat in ipairs(CATEGORIES) do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(SIDE_W - 12, CAT_H)
    b:SetPoint("TOPLEFT", 6, -HEAD - PAD - (i - 1) * CAT_H)
    b.bar = Tex(b, "ARTWORK", C.accent)
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(2)
    b.sel = Tex(b, "BACKGROUND", { C.accent[1], C.accent[2], C.accent[3], 0.10 })
    b.sel:SetAllPoints()
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.05)
    b.label = Text(b, 12, C.text, FONT_BODY)
    b.label:SetPoint("LEFT", 8, 0)
    b.labelKey = cat.label
    b.count = Text(b, 11, C.textDim, FONT_BODY)
    b.count:SetPoint("RIGHT", -4, 0)
    b.count:SetJustifyH("RIGHT")
    b.key = cat.key
    b:SetScript("OnClick", function(self)
        if selected ~= self.key then scrollRow = 0 end
        selected = self.key
        RequestUpdate(0)
    end)
    catButtons[i] = b
end

local function PaintCategories(counts)
    for _, b in ipairs(catButtons) do
        local on = b.key == selected
        b.bar:SetShown(on)
        b.sel:SetShown(on)
        local c = on and C.accentText or C.text
        b.label:SetTextColor(c[1], c[2], c[3])
        b.count:SetText(counts[b.key] or 0)
    end
end

---------------------------------------------------------------------------
-- Anheft-Leiste (nur in „Alle“): eigene Plätze als Unterlage und Ablagefläche.
-- Liegt der Gegenstand in den Taschen, rückt sein echter (sicherer) Taschenknopf auf den
-- Platz – Benutzen, Tooltip, Abklingzeit und Anzahl wie überall im Fenster. Fehlt er,
-- zeigt der Platz das Symbol ausgegraut.
---------------------------------------------------------------------------

local pinOf = {}       -- [Taschenknopf] = Platz in der Anheft-Leiste (aus dem letzten Layout)
local pinSlots = {}    -- [Platz] = Unterlage
local UpdateCatchers

local pinBar = CreateFrame("Frame", nil, frame)
pinBar:SetPoint("TOPLEFT", SIDE_W + PAD, -HEAD - PAD)
pinBar:SetSize(SLOT, PIN_H)
pinBar:Hide()

local pinLine = Tex(pinBar, "ARTWORK", { C.accent[1], C.accent[2], C.accent[3], 0.45 })
pinLine:SetPoint("TOPLEFT", 0, -(SLOT + GAP))
pinLine:SetHeight(1)
pinLine:SetWidth(SLOT)

local function CursorItemID()
    if not GetCursorInfo then return nil end
    local ok, kind, id = pcall(GetCursorInfo)
    if not ok or IsSecret(kind) or IsSecret(id) then return nil end
    if kind ~= "item" or type(id) ~= "number" then return nil end
    return id
end

local function ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and not IsSecret(icon) and icon then return icon end
    end
    if GetInstant then
        local ok, _, _, _, _, icon = pcall(GetInstant, itemID)
        if ok and not IsSecret(icon) and icon then return icon end
    end
end

-- Platz belegen (itemID) oder leeren (nil). Steht der Gegenstand schon woanders, zieht er um.
local function SetPin(index, itemID)
    if not ns.db or not index then return end
    local slots = PinSlots()
    if itemID then
        for i = 1, MAX_PINS do
            if slots[i] == itemID then slots[i] = nil end
        end
    end
    slots[index] = itemID
    SyncPinMap(ns.db.bagPinned)
    RequestUpdate(0)
    if ns.TriageRefresh then pcall(ns.TriageRefresh) end
end

local function DropOnPin(self)
    local id = CursorItemID()
    if not id then return end
    SetPin(self.index, id)
    -- Gegenstand geht zurück an seinen Platz in der Tasche; angeheftet wird nur die Item-ID
    if ClearCursor then pcall(ClearCursor) end
end

for i = 1, MAX_PINS do
    local s = CreateFrame("Button", nil, pinBar)
    s:SetSize(SLOT, SLOT)
    s:SetPoint("TOPLEFT", (i - 1) * (SLOT + GAP), 0)
    s:SetFrameLevel(frame:GetFrameLevel() + 1) -- unter den Taschenknöpfen
    s.index = i
    Tex(s, "BACKGROUND", C.slot):SetAllPoints()
    Border(s, C.slotEdge)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.icon:SetDesaturated(true)
    s.icon:SetVertexColor(0.6, 0.6, 0.6)
    s.icon:SetAlpha(0.6)
    s.icon:Hide()
    s:RegisterForClicks("RightButtonUp")
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            local ok = pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
            if not ok then GameTooltip:SetText(L["Angeheftet"]) end
            GameTooltip:AddLine(L["Nicht in deinen Taschen."], C.textDim[1], C.textDim[2], C.textDim[3], true)
            GameTooltip:AddLine(L["Shift+Rechtsklick oder herausziehen: lösen"], C.accentText[1], C.accentText[2], C.accentText[3], true)
        else
            GameTooltip:SetText(L["Anheft-Platz"], 1, 1, 1)
            GameTooltip:AddLine(L["Gegenstand hierher ziehen, um ihn anzuheften."], C.textDim[1], C.textDim[2], C.textDim[3], true)
        end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and IsShiftKeyDown() and self.itemID then
            GameTooltip:Hide()
            SetPin(self.index, nil)
        end
    end)
    s:SetScript("OnDragStart", function(self)
        if self.itemID then
            GameTooltip:Hide()
            SetPin(self.index, nil)
        end
    end)

    -- Ablagefläche obenauf: fängt die Maus nur, solange ein Gegenstand am Mauszeiger hängt
    local c = CreateFrame("Button", nil, pinBar)
    c:SetAllPoints(s)
    c:SetFrameLevel(frame:GetFrameLevel() + 40)
    c.index = i
    c:EnableMouse(false)
    local hl = c:CreateTexture(nil, "OVERLAY")
    hl:SetAllPoints()
    hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.30)
    hl:Hide()
    c:SetScript("OnEnter", function() hl:Show() end)
    c:SetScript("OnLeave", function() hl:Hide() end)
    c:SetScript("OnHide", function() hl:Hide() end)
    c:SetScript("OnReceiveDrag", DropOnPin)
    c:SetScript("OnMouseUp", DropOnPin)
    s.catcher = c
    pinSlots[i] = s
end

function UpdateCatchers()
    local on = pinBar:IsVisible() and CursorItemID() ~= nil
    for _, s in ipairs(pinSlots) do
        pcall(s.catcher.EnableMouse, s.catcher, (on and s:IsShown()) and true or false)
    end
end

local function PaintPinSlot(s, itemID, present)
    s.itemID = itemID
    if itemID and not present then
        s.icon:SetTexture(ItemIcon(itemID) or 134400) -- 134400 = Fragezeichen
        s.icon:Show()
    else
        s.icon:Hide()
    end
end

-- Cursor-Wechsel: Ablageflächen an/aus (Ereignisse gibt es nicht in jedem Client)
local cursorWatch = CreateFrame("Frame")
for _, event in ipairs({ "CURSOR_CHANGED", "CURSOR_UPDATE" }) do
    pcall(cursorWatch.RegisterEvent, cursorWatch, event)
end
cursorWatch:SetScript("OnEvent", function() if frame:IsShown() then UpdateCatchers() end end)

---------------------------------------------------------------------------
-- Gegenstandsknöpfe
---------------------------------------------------------------------------

local containers = {}  -- [bag] = Elternrahmen mit ID = Tasche
local buttons = {}     -- [bag][slot] = Knopf
local builtSize = {}   -- [bag] = Anzahl Plätze beim Aufbau
local data = {}        -- [Knopf] = gelesene Platzdaten
local built, broken = false, false
local pendingBuild, pendingLayout = false, false
local searchText = ""

local function GetContainerFrame(bag)
    local c = containers[bag]
    if c then return c end
    c = CreateFrame("Frame", "strayBagContainer" .. bag, grid)
    c:SetAllPoints(grid)
    c:SetID(bag)
    -- Neuere Templates fragen den Elternrahmen; eigene Rahmen, keine Blizzard-Tabellen
    c.GetBagID = function(self) return self:GetID() end
    c.IsCombinedBagContainer = function() return false end
    containers[bag] = c
    return c
end

local function Region(b, key, suffix)
    return b[key] or (b:GetName() and _G[b:GetName() .. suffix])
end

local function StyleButton(b)
    b:SetSize(SLOT, SLOT)
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    local iconBorder = b.IconBorder
    if iconBorder then iconBorder:SetAlpha(0) end
    local questTex = Region(b, "IconQuestTexture", "IconQuestTexture")
    if questTex then questTex:SetAlpha(0) end
    local newTex = b.NewItemTexture
    if newTex then newTex:SetAlpha(0) end
    local battle = b.BattlepayItemTexture
    if battle then battle:SetAlpha(0) end

    b.strayBg = Tex(b, "BACKGROUND", C.slot, -8)
    b.strayBg:SetAllPoints()

    local icon = Region(b, "icon", "IconTexture") or b.Icon
    b.strayIcon = icon
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
    b.strayCooldown = cd

    -- Rand im stray-Stil (Farbe nach Qualität)
    local holder = CreateFrame("Frame", nil, b)
    holder:SetAllPoints()
    holder:SetFrameLevel(b:GetFrameLevel() + 2)
    b.strayEdges = Border(holder, C.slotEdge, "OVERLAY")

    b.strayQuest = holder:CreateTexture(nil, "OVERLAY", nil, 2)
    b.strayQuest:SetPoint("TOPLEFT", 1, -1)
    b.strayQuest:SetPoint("BOTTOMRIGHT", -1, 1)
    b.strayQuest:Hide()

    b.strayNew = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    b.strayNew:SetPoint("TOPLEFT", 1, -1)
    b.strayNew:SetPoint("BOTTOMRIGHT", -1, 1)
    b.strayNew:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18)
    b.strayNew:Hide()

    -- Löschkandidat (triage.lua): rötliche Fläche, Rand wird in Paint rot
    b.strayTriage = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    b.strayTriage:SetPoint("TOPLEFT", 1, -1)
    b.strayTriage:SetPoint("BOTTOMRIGHT", -1, 1)
    b.strayTriage:SetColorTexture(C.triage[1], C.triage[2], C.triage[3], 0.22)
    b.strayTriage:Hide()

    b.strayPin = holder:CreateTexture(nil, "OVERLAY", nil, 3)
    b.strayPin:SetSize(6, 6)
    b.strayPin:SetPoint("TOPLEFT", 2, -2)
    b.strayPin:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    b.strayPin:Hide()

    b.strayDim = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    b.strayDim:SetAllPoints()
    b.strayDim:SetColorTexture(0, 0, 0, 0.7)
    b.strayDim:Hide()

    -- Anzahl über unserem Rand halten
    local count = Region(b, "Count", "Count")
    if count and count.SetParent then
        pcall(count.SetParent, count, holder)
        count:SetDrawLayer("OVERLAY", 6)
    end
end

-- Alt+Rechtsklick: anheften (erster freier Platz der sichtbaren Leiste) oder lösen
local function TogglePin(b)
    local d = data[b]
    if not d or not d.itemID then return end
    local index = PinIndexOf(d.itemID)
    if index then
        SetPin(index, nil)
        ns.Print(L("%s gelöst.", d.link or L["Gegenstand"]))
        return
    end
    local slots = PinSlots()
    for i = 1, Columns() do
        if not slots[i] then
            SetPin(i, d.itemID)
            ns.Print(L("%s angeheftet.", d.link or L["Gegenstand"]))
            return
        end
    end
    ns.Print(L["Die Anheft-Leiste ist voll. Zieh einen Gegenstand auf einen belegten Platz, um ihn zu ersetzen."])
end

local function CreateItemButton(bag, slot)
    local parent = GetContainerFrame(bag)
    local name = "strayBagItem" .. bag .. "_" .. slot
    local b
    for _, kind in ipairs({ "ItemButton", "Button" }) do
        local ok, result = pcall(CreateFrame, kind, name, parent, "ContainerFrameItemButtonTemplate")
        if ok and result then b = result break end
    end
    if not b then return nil end
    b:SetID(slot)
    if b.SetBagID then pcall(b.SetBagID, b, bag) end
    b.strayBag, b.straySlot = bag, slot
    pcall(StyleButton, b)
    -- Nach Blizzards Klick: Alt+Rechtsklick heftet an/ab; in der Anheft-Leiste löst
    -- Shift+Rechtsklick (beides sind „modifizierte“ Klicks, Blizzard benutzt dabei nichts)
    b:HookScript("OnClick", function(self, mouse)
        if mouse ~= "RightButton" then return end
        if IsAltKeyDown() then
            TogglePin(self)
        elseif IsShiftKeyDown() and pinOf[self] then
            SetPin(pinOf[self], nil)
        end
    end)
    -- Aus der Anheft-Leiste herausziehen löst den Gegenstand (er hängt dann am Mauszeiger)
    b:HookScript("OnDragStart", function(self)
        if pinOf[self] then SetPin(pinOf[self], nil) end
    end)
    -- „Neu“-Markierung beim Verlassen entfernen (wie Blizzard nach dem Ansehen)
    b:HookScript("OnLeave", function(self)
        local d = data[self]
        if d and d.isNew and C_NewItems and C_NewItems.RemoveNewItem then
            pcall(C_NewItems.RemoveNewItem, self.strayBag, self.straySlot)
            RequestUpdate(0.1)
        end
    end)
    b:Hide()
    return b
end

local function AnyProtected()
    local ok, protected = pcall(frame.IsProtected, frame)
    return ok and protected and true or false
end

-- Darf das Fenster gerade Knöpfe zeigen/verstecken/verschieben?
local function CanLayout()
    return not InCombatLockdown() or not AnyProtected()
end

local function Build()
    if broken then return false end
    if InCombatLockdown() then
        pendingBuild = true
        return false
    end
    pendingBuild = false
    for bag = FIRST_BAG, LAST_BAG do
        local n = NumSlots(bag)
        buttons[bag] = buttons[bag] or {}
        for slot = 1, n do
            if not buttons[bag][slot] then
                local b = CreateItemButton(bag, slot)
                if not b then
                    broken = true
                    ns.Print(L["Taschenfenster: Blizzards Taschenknopf-Vorlage fehlt – es bleiben Blizzards Taschen."])
                    return false
                end
                buttons[bag][slot] = b
            end
        end
        builtSize[bag] = n
    end
    built = true
    return true
end

---------------------------------------------------------------------------
-- Daten lesen
---------------------------------------------------------------------------

local function ScanButton(b, counts)
    local bag, slot = b.strayBag, b.straySlot
    local d = data[b] or { cats = {} }
    data[b] = d
    wipe(d.cats)
    local icon, count, locked, quality, link, itemID = SlotInfo(bag, slot)
    if not itemID and link then
        local id = link:match("item:(%d+)")
        itemID = id and tonumber(id)
    end
    d.icon, d.count, d.locked, d.quality, d.link, d.itemID = icon, count, locked, quality, link, itemID
    d.name = NameFromLink(link)
    d.isNew, d.questStarter, d.questItem, d.questNeeded = false, false, false, false
    if not (icon or link or itemID) then return d end

    local classID = ClassOf(itemID, link)
    local isQuestItem, questID, isActive = QuestInfo(bag, slot)
    if questID and not isActive then d.questStarter = true end
    if classID == CL_QUEST or isQuestItem then d.questItem = true end
    if ns.QuestForItemLink and link then
        local ok, quest = pcall(ns.QuestForItemLink, link)
        if ok and quest then d.questNeeded = true end
    end

    -- Was eine Quest braucht, steht nur unter „Quest“ (dazu Alle/Neu).
    -- Ist die Quest abgegeben, fällt das Flag beim nächsten Lesen weg und die
    -- normale Kategorie gilt wieder.
    if d.questStarter or d.questItem or d.questNeeded then
        d.cats.quest = true
    else
        if classID == CL_WEAPON or classID == CL_ARMOR then d.cats.gear = true end
        if classID == CL_CONSUMABLE then d.cats.consumable = true end
        if classID == CL_TRADE or classID == CL_REAGENT then d.cats.trade = true end
    end

    d.isNew = IsNew(bag, slot)
    if d.isNew then d.cats.new = true end

    counts.all = counts.all + 1
    for key in pairs(d.cats) do counts[key] = (counts[key] or 0) + 1 end
    return d
end

local function Matches(d, key)
    if key == "all" then return true end
    return d and d.cats[key] == true
end

local function MatchesSearch(d)
    if searchText == "" then return true end
    if not d or not d.name then return false end
    return d.name:lower():find(searchText, 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Darstellung
---------------------------------------------------------------------------

local function SetEdges(b, r, g, bl, a)
    if not b.strayEdges then return end
    for _, t in ipairs(b.strayEdges) do t:SetColorTexture(r, g, bl, a or 1) end
end

local function SetCooldown(b, bag, slot, hasItem)
    local cd = b.strayCooldown
    if not cd then return end
    if not hasItem then
        if cd.Clear then pcall(cd.Clear, cd) else cd:Hide() end
        return
    end
    local start, duration, enable = SlotCooldown(bag, slot)
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

-- Löschkandidat aus triage.lua (Tasche, Platz) oder nil
local triageBag, triageSlot

local function QuestMarksOn()
    return ns.db and ns.db.questItemMarks and true or false
end

local function Paint(b, d, dimByCategory)
    local hasItem = d.icon or d.link or d.itemID
    -- Questziele aus dem Questlog nur mit „Questgegenstände markieren“; Blizzards eigene
    -- Questgegenstände und Questanfänge markiert WoW immer
    local questNeeded = d.questNeeded and QuestMarksOn()
    local isTriage = hasItem and b.strayBag == triageBag and b.straySlot == triageSlot
    if SetItemButtonTexture then
        pcall(SetItemButtonTexture, b, d.icon)
    elseif b.strayIcon then
        b.strayIcon:SetTexture(d.icon)
    end
    if b.strayIcon then b.strayIcon:SetShown(d.icon ~= nil) end
    local count = (type(d.count) == "number") and d.count or 0
    if SetItemButtonCount then
        pcall(SetItemButtonCount, b, count)
    else
        local fs = Region(b, "Count", "Count")
        if fs then
            fs:SetText(count > 1 and count or "")
            fs:SetShown(count > 1)
        end
    end
    local locked = d.locked and true or false
    if SetItemButtonDesaturated then
        pcall(SetItemButtonDesaturated, b, locked)
    elseif b.strayIcon then
        b.strayIcon:SetDesaturated(locked)
    end
    if b.strayIcon then
        local v = locked and 0.5 or 1
        b.strayIcon:SetVertexColor(v, v, v)
    end

    -- Rand: Löschkandidat rot, Quest gold, sonst Qualität (ab „selten“ farbig, Schrott grau)
    if isTriage then
        SetEdges(b, C.triage[1], C.triage[2], C.triage[3], 1)
    elseif d.questItem or questNeeded or d.questStarter then
        SetEdges(b, C.quest[1], C.quest[2], C.quest[3], 1)
    elseif hasItem and type(d.quality) == "number" and d.quality >= 2 and QualityColor(d.quality) then
        local r, g, bl = QualityColor(d.quality)
        SetEdges(b, r, g, bl, 1)
    elseif hasItem and d.quality == 0 then
        SetEdges(b, 0.40, 0.40, 0.40, 1)
    elseif hasItem then
        SetEdges(b, C.itemEdge[1], C.itemEdge[2], C.itemEdge[3], 1)
    else
        SetEdges(b, C.slotEdge[1], C.slotEdge[2], C.slotEdge[3], 1)
    end

    if b.strayQuest then
        if d.questStarter or questNeeded then
            b.strayQuest:SetTexture(QUEST_BANG)
            b.strayQuest:Show()
        elseif d.questItem then
            b.strayQuest:SetTexture(QUEST_BORDER)
            b.strayQuest:Show()
        else
            b.strayQuest:Hide()
        end
    end
    if b.strayTriage then b.strayTriage:SetShown(isTriage and true or false) end
    if b.strayNew then b.strayNew:SetShown(d.isNew) end
    if b.strayPin then b.strayPin:SetShown(pinOf[b] ~= nil) end

    local dim = not MatchesSearch(d) or (dimByCategory and not Matches(d, selected))
    if b.strayDim then b.strayDim:SetShown(dim and true or false) end

    SetCooldown(b, b.strayBag, b.straySlot, hasItem)
end

local function UpdateHeader()
    local total, free = 0, 0
    for bag = FIRST_BAG, LAST_BAG do
        local n = NumSlots(bag)
        local f, family = FreeSlots(bag)
        -- Nur normale Taschen (keine Köcher, Kräuter- oder Seelentaschen)
        if family == 0 or family == nil then
            total = total + n
            free = free + (type(f) == "number" and f or 0)
        end
    end
    slotsText:SetText(L("%d / %d Plätze", total - free, total))
    local money = GetMoney and Public(GetMoney())
    moneyText:SetText(type(money) == "number" and ns.FormatMoney(money) or "")
end

local function ActiveButtons(fn)
    for bag = FIRST_BAG, LAST_BAG do
        local list = buttons[bag]
        if list then
            for slot = 1, (builtSize[bag] or 0) do
                local b = list[slot]
                if b then fn(b) end
            end
        end
    end
end

local function UpdateScrollBar()
    if totalRows <= viewRows then
        scrollTrack:Hide()
        return
    end
    local trackH = scrollTrack:GetHeight() or 0
    if trackH <= 0 then
        scrollTrack:Hide()
        return
    end
    local thumbH = math.max(16, math.floor(trackH * viewRows / totalRows))
    local offset = (scrollMax > 0) and (scrollRow / scrollMax * (trackH - thumbH)) or 0
    scrollThumb:ClearAllPoints()
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -offset)
    scrollThumb:SetHeight(thumbH)
    scrollTrack:Show()
end

local liveCols -- Spalten während des Ziehens

-- live = true: während des Ziehens, Fenstergröße nicht anfassen.
-- keepTopLeft = true: Größe setzen, ohne vorher an die rechte untere Ecke zu hängen.
local function Layout(live, keepTopLeft)
    local cols = (live and liveCols) or Columns()

    -- Anheft-Leiste nur in „Alle“: so viele Plätze wie Spalten; je Platz der erste
    -- Taschenknopf mit dieser Item-ID (weitere Stapel bleiben unten im Raster)
    local showPins = selected == "all"
    local pinCount = showPins and math.min(cols, MAX_PINS) or 0
    local pinH = showPins and PIN_H or 0
    local slots = PinSlots()
    local pinButton = {}
    wipe(pinOf)
    if showPins then
        local firstByID = {}
        ActiveButtons(function(b)
            local id = data[b] and data[b].itemID
            if id and not firstByID[id] then firstByID[id] = b end
        end)
        for i = 1, pinCount do
            local id = slots[i]
            local b = id and firstByID[id]
            if b then
                pinButton[i] = b
                pinOf[b] = i
            end
        end
    end

    local shown = {}
    ActiveButtons(function(b)
        if not pinOf[b] and Matches(data[b], selected) then shown[#shown + 1] = b end
    end)
    -- Plätze kleiner gewordener Taschen ausblenden
    for bag = FIRST_BAG, LAST_BAG do
        local list = buttons[bag]
        if list then
            for slot = (builtSize[bag] or 0) + 1, #list do
                if list[slot] then list[slot]:Hide() end
            end
        end
    end
    -- Höhe: beim Ziehen die aktuelle, sonst fest gespeichert oder nach Inhalt (gedeckelt)
    local rows = math.max(1, math.ceil(#shown / cols))
    local height
    if live then
        height = frame:GetHeight() or MIN_H
    else
        height = FixedHeight()
        if not height then
            local auto = HEAD + PAD + math.max(pinH + GridSize(rows), CAT_TOTAL) + PAD + FOOT
            height = math.max(MIN_H, math.min(MaxHeight(), auto))
        end
    end
    totalRows = rows
    viewRows = math.min(rows, RowsForHeight(height, pinH))
    scrollMax = math.max(0, rows - viewRows)
    if scrollRow > scrollMax then scrollRow = scrollMax end
    if scrollRow < 0 then scrollRow = 0 end

    -- Anheft-Leiste setzen; das Raster rutscht darunter
    grid:ClearAllPoints()
    grid:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_W + PAD, -HEAD - PAD - pinH)
    local visible = {}
    pinBar:SetShown(showPins)
    if showPins then
        local w = math.max(1, GridSize(pinCount))
        pinBar:SetSize(w, PIN_H)
        pinLine:SetWidth(w)
        for i, s in ipairs(pinSlots) do
            local on = i <= pinCount
            s:SetShown(on)
            if on then
                local b = pinButton[i]
                if b then
                    visible[b] = true
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
                    b:Show()
                end
                PaintPinSlot(s, slots[i], b ~= nil)
            end
        end
    end
    UpdateCatchers()

    -- Nur die sichtbaren Reihen setzen und zeigen, der Rest wird ausgeblendet
    for i, b in ipairs(shown) do
        local row = math.floor((i - 1) / cols) - scrollRow
        if row >= 0 and row < viewRows then
            visible[b] = true
            local col = (i - 1) % cols
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (SLOT + GAP), -row * (SLOT + GAP))
            b:Show()
        end
    end
    ActiveButtons(function(b) if not visible[b] then b:Hide() end end)
    emptyText:SetShown(#shown == 0 and next(pinButton) == nil)

    grid:SetSize(math.max(1, GridSize(cols)), math.max(1, GridSize(viewRows)))
    if not live then
        if not keepTopLeft then Reanchor() end
        frame:SetSize(WidthFor(cols), height)
    end
    UpdateScrollBar()
end

local updatePending = false

local function Update()
    updatePending = false
    if not frame:IsShown() or not built then return end
    -- Tasche getauscht? Dann neu aufbauen (nur außerhalb des Kampfes)
    for bag = FIRST_BAG, LAST_BAG do
        if NumSlots(bag) ~= (builtSize[bag] or 0) then
            if InCombatLockdown() then pendingBuild = true else Build() end
            break
        end
    end
    local counts = { all = 0 }
    ActiveButtons(function(b) ScanButton(b, counts) end)
    PaintCategories(counts)
    local canLayout = CanLayout()
    if canLayout then
        pendingLayout = false
        Layout(sizing)
    else
        pendingLayout = true
    end
    -- Im Kampf mit geschützten Knöpfen: Kategorie nur über Abdunkeln
    ActiveButtons(function(b)
        local d = data[b]
        if d then pcall(Paint, b, d, not canLayout) end
    end)
    UpdateHeader()
end

function RequestUpdate(delay)
    if updatePending or not frame:IsShown() then return end
    updatePending = true
    C_Timer.After(delay or 0.05, Update)
end

-- Schnittstelle für triage.lua: Löschkandidat markieren (bag, slot) oder aufheben (nil)
function ns.BagWindowSetTriage(bag, slot)
    if IsSecret(bag) or IsSecret(slot) or type(bag) ~= "number" or type(slot) ~= "number" then
        bag, slot = nil, nil
    end
    if bag == triageBag and slot == triageSlot then return end
    triageBag, triageSlot = bag, slot
    triageButton:SetShown(bag ~= nil)
    RequestUpdate(0)
end

search:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    placeholder:SetShown(text == "" and not self:HasFocus())
    searchText = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    RequestUpdate(0)
end)

---------------------------------------------------------------------------
-- Blättern: Mausrad, Scrollbalken ziehen oder in die Spur klicken
---------------------------------------------------------------------------

local function SetScrollRow(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    if n > scrollMax then n = scrollMax end
    if n < 0 then n = 0 end
    if n == scrollRow or not CanLayout() then return end
    scrollRow = n
    Layout(sizing)
end

local function OnWheel(_, delta)
    if type(delta) ~= "number" then return end
    SetScrollRow(scrollRow - delta)
end

frame:EnableMouseWheel(true)
frame:SetScript("OnMouseWheel", OnWheel)
scrollTrack:SetScript("OnMouseWheel", OnWheel)

-- Cursor-Höhe in Fensterkoordinaten
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
    self.startRow = scrollRow
    thumbLine:SetWidth(6)
    self:SetScript("OnUpdate", function(thumb)
        local free = TrackFree()
        if free <= 0 or scrollMax <= 0 then return end
        local moved = thumb.startY - CursorY()
        SetScrollRow(thumb.startRow + moved / free * scrollMax)
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

-- Klick in die Spur: Daumen springt dorthin
scrollTrack:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local top = self:GetTop()
    local free = TrackFree()
    if not top or free <= 0 then return end
    local pos = top - CursorY() - (scrollThumb:GetHeight() or 0) / 2
    SetScrollRow(math.max(0, math.min(free, pos)) / free * scrollMax)
end)

---------------------------------------------------------------------------
-- Größe ziehen: Breite rastet auf Spalten ein, Höhe frei
---------------------------------------------------------------------------

local startW, startH, startCols

-- Fenster an die linke obere Ecke hängen, damit nur die rechte untere Ecke wandert
local function AnchorTopLeft()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return nil end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return left, top
end

local function OnSizing()
    local w = frame:GetWidth()
    if type(w) ~= "number" then return end
    -- Erst beim Loslassen speichern; kleine Wackler (unter 8 px) ändern die Spalten nicht
    if math.abs(w - startW) >= 8 then
        liveCols = ColumnsForWidth(w)
    else
        liveCols = startCols
    end
    Layout(true)
end

frame:SetScript("OnSizeChanged", function()
    if sizing then pcall(OnSizing) end
end)

local function StopSizing()
    if not sizing then return end
    sizing = false
    frame:StopMovingOrSizing()
    local w, h = frame:GetSize()
    if ns.db and type(w) == "number" and type(h) == "number" then
        if math.abs(w - startW) >= 8 then
            ns.db.bagColumns = ColumnsForWidth(w)
            if ns.RefreshConfig then pcall(ns.RefreshConfig) end
        end
        -- Nur wer die Höhe wirklich verändert, legt eine feste Höhe fest
        if math.abs(h - startH) >= 19 then -- etwa eine halbe Reihe; schräges Ziehen an der Breite ändert die Höhe nicht
            ns.db.bagHeight = math.max(MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
        end
    end
    liveCols = nil
    -- Breite auf ganze Spalten einrasten, linke obere Ecke bleibt stehen
    local left, top = AnchorTopLeft()
    Layout(false, true)
    if left and top then
        local width, height = frame:GetSize()
        local right, bottom = left + width, top - height
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
        SavePosition(right, bottom)
    else
        SavePosition()
    end
end

grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or sizing or not ns.db or not built then return end
    if not CanLayout() then
        ns.Print(L["Größe ändern geht erst nach dem Kampf."])
        return
    end
    GameTooltip:Hide()
    startW, startH = frame:GetSize()
    if type(startW) ~= "number" or type(startH) ~= "number" then return end
    startCols = Columns()
    liveCols = startCols
    AnchorTopLeft()
    if pcall(frame.StartSizing, frame, "BOTTOMRIGHT") then
        sizing = true
    else
        liveCols = nil
        Reanchor()
    end
end)
grip:SetScript("OnMouseUp", function() StopSizing() end)
grip:SetScript("OnHide", function() StopSizing() end)
grip:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    if sizing then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Ziehen: Größe ändern"], 1, 1, 1)
    GameTooltip:AddLine(L["Breite in ganzen Spalten, Höhe frei. Passt nicht alles hinein, blätterst du mit dem Mausrad."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(L["Höhe wieder automatisch: im Bearbeitungsmodus Shift+Rechtsklick auf das Taschenfenster."], C.textDim[1], C.textDim[2], C.textDim[3], true)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", function(self)
    self:SetAlpha(0.5)
    GameTooltip:Hide()
end)

---------------------------------------------------------------------------
-- Öffnen und Schließen
---------------------------------------------------------------------------

local openerName -- Rahmen, der das Fenster geöffnet hat (z. B. MerchantFrame)
local previewOpened = false
local combatNoted = false

-- Sichtbare Texte erst beim Anzeigen übersetzen (Sprache ist umschaltbar)
local function RefreshTexts()
    title:SetText(L["Taschen"])
    placeholder:SetText(L["Suchen …"])
    emptyText:SetText(L["Keine Gegenstände."])
    hintText:SetText(L["In die obere Reihe ziehen: anheften"])
    triageLabel:SetText(L["Löschkandidat aufnehmen"])
    for _, b in ipairs(catButtons) do b.label:SetText(L[b.labelKey]) end
end

frame:SetScript("OnShow", function()
    updatePending = false
    pcall(RefreshTexts)
    Update()
end)
frame:SetScript("OnHide", function()
    openerName = nil
    previewOpened = false
    search:ClearFocus()
    UpdateCatchers()
end)

local function Enabled()
    return ns.db and ns.db.bagWindow and true or false
end

-- Kann das stray-Fenster jetzt übernehmen? Sonst bleiben Blizzards Taschen offen.
local function Usable()
    if broken or not Enabled() then return false end
    if InCombatLockdown() then
        if not built then
            if not combatNoted then
                combatNoted = true
                ns.Print(L["Taschenfenster wird nach dem Kampf aufgebaut – bis dahin Blizzards Taschen."])
            end
            pendingBuild = true
            return false
        end
        if AnyProtected() then return false end
    end
    return true
end

local function ShowWindow()
    if not built and not Build() then return false end
    if InCombatLockdown() and AnyProtected() then return false end
    frame:Show()
    return true
end

local suppress = false

local function HideBlizzardBags()
    suppress = true
    pcall(function()
        for i = 1, (NUM_CONTAINER_FRAMES or 13) do
            local f = _G["ContainerFrame" .. i]
            if f and f:IsShown() then
                local id = f:GetID()
                if not IsSecret(id) and type(id) == "number" and id >= FIRST_BAG and id <= LAST_BAG then
                    f:Hide()
                end
            end
        end
        local combined = ContainerFrameCombinedBags
        if combined and combined:IsShown() then combined:Hide() end
    end)
    suppress = false
end

-- Verschachtelte Aufrufe (ToggleAllBags ruft OpenBackpack …): der äußere Hook kommt zuletzt
-- und gewinnt; ausgewertet wird im nächsten Frame.
local intent, intentName

local function Resolve()
    local action, name = intent, intentName
    intent, intentName = nil, nil
    if not action or not Enabled() then return end
    local shown = frame:IsShown()
    if action == "toggle" then
        action = shown and "hide" or "show"
    elseif action == "openBy" then
        if shown then return end
        if ShowWindow() then openerName = name end
        return
    elseif action == "closeBy" then
        if shown and name and name == openerName then frame:Hide() end
        return
    end
    if action == "show" then
        if not shown then ShowWindow() end
    elseif action == "hide" then
        if shown and not (InCombatLockdown() and AnyProtected()) then frame:Hide() end
    end
end

local function Request(action, name)
    if suppress or not Usable() then return end
    HideBlizzardBags()
    if not intent then C_Timer.After(0, Resolve) end
    intent, intentName = action, name
end

local function InstallHooks()
    local function Hook(fnName, handler)
        if type(_G[fnName]) == "function" then
            hooksecurefunc(fnName, function(...)
                local ok = pcall(handler, ...)
                return ok
            end)
        end
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
    Hook("ToggleBag", function(id)
        if IsSecret(id) or type(id) ~= "number" then return end
        if id >= FIRST_BAG and id <= LAST_BAG then Request("toggle") end
    end)

    -- Auffangnetz: Taschen, die ohne diese Funktionen aufgehen (z. B. OpenBag direkt)
    local function OnBlizzardShow(self)
        if suppress or not Usable() then return end
        local id = self.GetID and self:GetID()
        if self ~= ContainerFrameCombinedBags then
            if IsSecret(id) or type(id) ~= "number" or id < FIRST_BAG or id > LAST_BAG then return end
        end
        if not intent then Request("show") end
        C_Timer.After(0, function() if Usable() then HideBlizzardBags() end end)
    end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f and f.HookScript then f:HookScript("OnShow", OnBlizzardShow) end
    end
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags.HookScript then
        ContainerFrameCombinedBags:HookScript("OnShow", OnBlizzardShow)
    end
end

-- Höhe im Bearbeitungsmodus: bagHeight 0 = automatisch (nach Inhalt). Untergrenze 0, damit
-- „Zurücksetzen“ (Standard 0) nicht auf die kleinste feste Höhe geklemmt wird.
local function NormalizeHeight()
    if not ns.db then return end
    local h = tonumber(ns.db.bagHeight)
    if not h or IsSecret(h) or h <= 0 then
        ns.db.bagHeight = 0
    else
        ns.db.bagHeight = math.max(MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
    end
end

ns.RegisterMovable(frame, "Taschenfenster", function(on)
    if on then
        if Enabled() and not frame:IsShown() and not InCombatLockdown() and ShowWindow() then
            previewOpened = true
        end
    elseif previewOpened then
        frame:Hide()
    end
end, {
    heightKey = "bagHeight",
    heightMin = 0,
    heightMax = MAX_H,
    onSize = function(which)
        if which ~= "height" then return end
        NormalizeHeight()
        RequestUpdate(0)
    end,
})

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    local h = tonumber(ns.db.bagHeight)
    ns.db.bagHeight = (h and h > 0) and math.max(MIN_H, math.min(MAX_H, math.floor(h + 0.5))) or 0
    PinSlots() -- altes Anheft-Format umstellen, Ruhestein auf Platz 1
    ns.RestorePosition(frame)
    pcall(InstallHooks)
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    -- Knöpfe vorab außerhalb des Kampfes anlegen, damit das Fenster auch im Kampf aufgeht
    C_Timer.After(2, function()
        if Enabled() and not built and not InCombatLockdown() then Build() end
    end)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    combatNoted = false
    if pendingBuild and Enabled() then Build() end
    if pendingLayout or pendingBuild then RequestUpdate(0) end
end)

ns.On("BAG_UPDATE_DELAYED", function() RequestUpdate(0.05) end)
ns.On("ITEM_LOCK_CHANGED", function() RequestUpdate(0.05) end)
ns.On("BAG_UPDATE_COOLDOWN", function() RequestUpdate(0.1) end)
ns.On("PLAYER_MONEY", function() if frame:IsShown() then UpdateHeader() end end)
ns.On("QUEST_LOG_UPDATE", function() RequestUpdate(0.5) end)
-- Quest abgegeben/abgebrochen: questitems.lua baut seine Liste nach 0,2 s neu, danach einordnen
local function AfterQuestGone() C_Timer.After(0.6, function() RequestUpdate(0) end) end
ns.On("QUEST_TURNED_IN", AfterQuestGone)
ns.On("QUEST_REMOVED", AfterQuestGone)
-- Optionen wie „Questgegenstände markieren“ wirken sofort, wenn das stray-Fenster auf/zu geht
ns.OnConfig(function() RequestUpdate(0) end)

-- Backstop zu den Hooks: Händler öffnet/schließt das Fenster
ns.On("MERCHANT_SHOW", function() Request("openBy", "MerchantFrame") end)
ns.On("MERCHANT_CLOSED", function() Request("closeBy", "MerchantFrame") end)

-- Ereignisse, die es nicht in jedem Client gibt
local optional = CreateFrame("Frame")
for _, event in ipairs({ "BAG_NEW_ITEMS_UPDATED", "INVENTORY_SEARCH_UPDATE" }) do
    pcall(optional.RegisterEvent, optional, event)
end
optional:SetScript("OnEvent", function() RequestUpdate(0.1) end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(1, "Taschen", {
    key = "bagWindow",
    label = L["Eigenes Taschenfenster"],
    tooltip = L["Zeigt alle Taschen in einem Fenster mit Suche und Kategorien (Ausrüstung, Verbrauchbar, Handwerk, Quest, Neu). B-Taste, Rucksack-Knopf und Händler öffnen dann dieses Fenster statt Blizzards Taschen.\n\nQuestgegenstände stehen nur unter „Quest“, bis die Quest abgegeben ist.\n\nIn „Alle“ steht oben eine Anheft-Leiste (der Ruhestein sitzt anfangs auf Platz 1): Gegenstand hineinziehen heftet ihn an, Shift+Rechtsklick oder Herausziehen löst ihn. Angeheftetes benutzt du dort wie in der Tasche. Auch Alt+Rechtsklick auf einen Gegenstand heftet ihn an oder löst ihn. Kopfzeile ziehen verschiebt das Fenster, der Griff unten rechts ändert die Größe. Passt nicht alles hinein, blätterst du mit dem Mausrad. Der Besen neben der Suche sortiert die Taschen.\n\nAusschalten wirkt sofort; ganz sauber wird es nach Neuladen (/reload)."],
    set = function(value)
        ns.db.bagWindow = value
        if value then
            if not InCombatLockdown() then Build() end
        else
            if not (InCombatLockdown() and AnyProtected()) then frame:Hide() end
        end
    end,
})

ns.AddOption(1, "Taschen", {
    key = "bagColumns",
    type = "slider",
    label = L["Spalten im Taschenfenster"],
    min = 6, max = 16, step = 1,
    tooltip = L["Wie viele Plätze nebeneinander im stray-Taschenfenster stehen. Ziehst du das Fenster unten rechts breiter oder schmaler, ändert sich dieser Wert mit."],
    isEnabled = function() return ns.db and ns.db.bagWindow and true or false end,
    disabledHint = L["Erst „Eigenes Taschenfenster“ einschalten (weiter oben)."],
    set = function(value)
        ns.db.bagColumns = value
        RequestUpdate(0)
    end,
})

