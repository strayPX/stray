-- stray – Eigenes Taschenfenster
-- Alle normalen Taschen (0–4) in einem Fenster: Kopf mit Belegung, Suche und Schließen,
-- links Kategorien mit Anzahl, rechts das Raster, unten das Gold.
-- Die Gegenstandsknöpfe nutzen Blizzards ContainerFrameItemButtonTemplate und hängen in
-- Elternrahmen, deren ID die Taschennummer ist – so verhalten sie sich wie Blizzards
-- Taschenplätze (benutzen, verkaufen, anlegen, ziehen, verlinken, Tooltip).
-- Blizzard-Tabellen werden nicht verändert: nur hooksecurefunc und Hide() auf die Taschenrahmen.

local _, ns = ...

local IsSecret = ns.IsSecret

---------------------------------------------------------------------------
-- Maße und Farben (Stil wie ui.lua)
---------------------------------------------------------------------------

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BODY = "Fonts\\ARIALN.TTF"
local QUEST_BANG = TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang"
local QUEST_BORDER = TEXTURE_ITEM_QUEST_BORDER or "Interface\\ContainerFrame\\UI-Icon-QuestBorder"

local C = {
    bg      = { 0.051, 0.067, 0.090, 0.95 },
    side    = { 0.043, 0.067, 0.106, 1 },
    border  = { 0.169, 0.290, 0.451, 1 },
    line    = { 0.122, 0.200, 0.322, 1 },
    accent  = { 0.353, 0.659, 1.000, 1 },
    text    = { 0.890, 0.914, 0.953, 1 },
    textDim = { 0.435, 0.525, 0.651, 1 },
    slot    = { 0.035, 0.047, 0.067, 1 },
    slotEdge = { 0.110, 0.165, 0.247, 1 },
    quest   = { 1, 0.82, 0, 1 },
    triage  = { 1, 0.32, 0.22, 1 },
}

local SLOT, GAP = 34, 4
local SIDE_W = 122
local PAD = 10
local HEAD = 40
local FOOT = 28
local CAT_H = 22
local MIN_W = 440

local FIRST_BAG = 0
local LAST_BAG = (type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS) or 4

local CATEGORIES = {
    { key = "all", label = "Alle" },
    { key = "gear", label = "Ausrüstung" },
    { key = "consumable", label = "Verbrauchbar" },
    { key = "trade", label = "Handwerk" },
    { key = "quest", label = "Quest" },
    { key = "new", label = "Neu" },
    { key = "pinned", label = "Angeheftet" },
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

local function Pinned()
    if not ns.db then return {} end
    if type(ns.db.bagPinned) ~= "table" then ns.db.bagPinned = {} end
    return ns.db.bagPinned
end

local function Columns()
    local n = ns.db and tonumber(ns.db.bagColumns) or 10
    n = math.floor(n + 0.5)
    if n < 6 then n = 6 elseif n > 16 then n = 16 end
    return n
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
local function SavePosition()
    local right, bottom = frame:GetRight(), frame:GetBottom()
    local uiRight = UIParent:GetRight()
    if not (right and bottom and uiRight) or not ns.db then return end
    ns.db.positions.bagwindow = { "BOTTOMRIGHT", "BOTTOMRIGHT", right - uiRight, bottom }
end

frame:SetScript("OnDragStop", function(self)
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
head:SetScript("OnDragStart", function() frame:StartMoving() end)
head:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SavePosition()
end)

local headLine = Tex(frame, "BORDER", C.line)
headLine:SetPoint("TOPLEFT", 1, -HEAD); headLine:SetPoint("TOPRIGHT", -1, -HEAD); headLine:SetHeight(1)

local title = Text(head, 14, C.text)
title:SetPoint("LEFT", 12, 0)
title:SetText("Taschen")

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
Tex(search, "BACKGROUND", { 0.039, 0.059, 0.090, 1 }):SetAllPoints()
Border(search, { 0.133, 0.220, 0.353, 1 })
local placeholder = Text(search, 12, { 0.365, 0.451, 0.576, 1 }, FONT_BODY)
placeholder:SetPoint("LEFT", 8, 0)
placeholder:SetText("Suchen …")
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
search:SetScript("OnEditFocusLost", function(self) placeholder:SetShown(self:GetText() == "") end)

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
emptyText:SetText("Keine Gegenstände.")
emptyText:Hide()

-- Fuß
local footLine = Tex(frame, "BORDER", C.line)
footLine:SetPoint("BOTTOMLEFT", 1, FOOT); footLine:SetPoint("BOTTOMRIGHT", -1, FOOT); footLine:SetHeight(1)

local moneyText = Text(frame, 12, C.text, FONT_BODY)
moneyText:SetPoint("BOTTOMLEFT", 12, 8)

local hintText = Text(frame, 11, C.textDim, FONT_BODY)
hintText:SetPoint("BOTTOMRIGHT", -12, 9)
hintText:SetJustifyH("RIGHT")
hintText:SetText("Alt+Rechtsklick: anheften")

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
triageLabel:SetText("Löschkandidat aufnehmen")
triageButton:SetWidth(150)
triageButton:SetScript("OnClick", function()
    if ns.TriagePickup then ns.TriagePickup() end
end)
triageButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Löschkandidat aufnehmen")
    GameTooltip:AddLine("Legt den rot markierten, billigsten Gegenstand auf den Mauszeiger. stray löscht nichts selbst – das Zerstören bestätigst du bei WoW.", 1, 1, 1, true)
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
    b.label:SetText(cat.label)
    b.count = Text(b, 11, C.textDim, FONT_BODY)
    b.count:SetPoint("RIGHT", -4, 0)
    b.count:SetJustifyH("RIGHT")
    b.key = cat.key
    b:SetScript("OnClick", function(self)
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
        local c = on and C.accent or C.text
        b.label:SetTextColor(c[1], c[2], c[3])
        b.count:SetText(counts[b.key] or 0)
    end
end

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

local function TogglePin(b)
    local d = data[b]
    if not d or not d.itemID then return end
    local pinned = Pinned()
    if pinned[d.itemID] then
        pinned[d.itemID] = nil
        ns.Print((d.link or "Gegenstand") .. " gelöst.")
    else
        pinned[d.itemID] = true
        ns.Print((d.link or "Gegenstand") .. " angeheftet.")
    end
    RequestUpdate(0)
    if ns.TriageRefresh then pcall(ns.TriageRefresh) end
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
    -- Nach Blizzards Klick: Alt+Rechtsklick heftet an/ab
    b:HookScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and IsAltKeyDown() then TogglePin(self) end
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
                    ns.Print("Taschenfenster: Blizzards Taschenknopf-Vorlage fehlt – es bleiben Blizzards Taschen.")
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
    d.isNew, d.questStarter, d.questItem, d.questNeeded, d.pinned = false, false, false, false, false
    if not (icon or link or itemID) then return d end

    local classID = ClassOf(itemID, link)
    if classID == CL_WEAPON or classID == CL_ARMOR then d.cats.gear = true end
    if classID == CL_CONSUMABLE then d.cats.consumable = true end
    if classID == CL_TRADE or classID == CL_REAGENT then d.cats.trade = true end

    local isQuestItem, questID, isActive = QuestInfo(bag, slot)
    if questID and not isActive then d.questStarter = true end
    if classID == CL_QUEST or isQuestItem then d.questItem = true end
    if ns.QuestForItemLink and link then
        local ok, quest = pcall(ns.QuestForItemLink, link)
        if ok and quest then d.questNeeded = true end
    end
    if d.questStarter or d.questItem or d.questNeeded then d.cats.quest = true end

    d.isNew = IsNew(bag, slot)
    if d.isNew then d.cats.new = true end
    if itemID and Pinned()[itemID] then
        d.pinned = true
        d.cats.pinned = true
    end

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
        SetEdges(b, C.border[1], C.border[2], C.border[3], 1)
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
    if b.strayPin then b.strayPin:SetShown(d.pinned) end

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
    slotsText:SetText((total - free) .. " / " .. total .. " Plätze")
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

local function Layout()
    local cols = Columns()
    local shown = {}
    ActiveButtons(function(b)
        if Matches(data[b], selected) then shown[#shown + 1] = b end
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
    local visible = {}
    for i, b in ipairs(shown) do
        visible[b] = true
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (SLOT + GAP), -row * (SLOT + GAP))
        b:Show()
    end
    ActiveButtons(function(b) if not visible[b] then b:Hide() end end)
    emptyText:SetShown(#shown == 0)

    local rows = math.max(1, math.ceil(#shown / cols))
    local gridW = cols * SLOT + (cols - 1) * GAP
    local gridH = rows * SLOT + (rows - 1) * GAP
    grid:SetSize(gridW, gridH)
    local catH = #CATEGORIES * CAT_H
    local width = math.max(MIN_W, SIDE_W + PAD * 2 + gridW)
    local height = HEAD + PAD + math.max(gridH, catH) + PAD + FOOT
    Reanchor()
    frame:SetSize(width, height)
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
        Layout()
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
-- Öffnen und Schließen
---------------------------------------------------------------------------

local openerName -- Rahmen, der das Fenster geöffnet hat (z. B. MerchantFrame)
local previewOpened = false
local combatNoted = false

frame:SetScript("OnShow", function()
    updatePending = false
    Update()
end)
frame:SetScript("OnHide", function()
    openerName = nil
    previewOpened = false
    search:ClearFocus()
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
                ns.Print("Taschenfenster wird nach dem Kampf aufgebaut – bis dahin Blizzards Taschen.")
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

ns.RegisterMovable(frame, "Taschenfenster", function(on)
    if on then
        if Enabled() and not frame:IsShown() and not InCombatLockdown() and ShowWindow() then
            previewOpened = true
        end
    elseif previewOpened then
        frame:Hide()
    end
end)

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
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
    label = "Eigenes Taschenfenster",
    tooltip = "Zeigt alle Taschen in einem Fenster mit Suche und Kategorien (Ausrüstung, Verbrauchbar, Handwerk, Quest, Neu, Angeheftet). B-Taste, Rucksack-Knopf und Händler öffnen dann dieses Fenster statt Blizzards Taschen.\n\nAlt+Rechtsklick auf einen Gegenstand heftet ihn an oder löst ihn. Kopfzeile ziehen verschiebt das Fenster.\n\nAusschalten wirkt sofort; ganz sauber wird es nach Neuladen (/reload).",
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
    label = "Spalten im Taschenfenster",
    min = 6, max = 16, step = 1,
    tooltip = "Wie viele Plätze nebeneinander im stray-Taschenfenster stehen.",
    isEnabled = function() return ns.db and ns.db.bagWindow and true or false end,
    disabledHint = "Erst „Eigenes Taschenfenster“ einschalten.",
    set = function(value)
        ns.db.bagColumns = value
        RequestUpdate(0)
    end,
})
