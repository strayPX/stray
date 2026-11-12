-- stray – stray-Tasche: Fenster
-- Kopf (Titel, Belegung, Kopf-Symbole, Suche, Schließen), links Platz für die Seitenleiste, in der Mitte
-- die Abschnitte (Überschrift + Raster aus echten Blizzard-Itemknöpfen), unten Gold, Schloss, Größen-Griff.
-- Die Abschnitte liefert die aktive Ansicht (B.BuildSections, siehe bag_core.lua). Gegenstandsknöpfe
-- kommen aus dem Vorrat des Kerns (B.AcquireButton); dieses Fenster setzt sie nur um.
-- Layout (SetPoint/Show/Hide an Knöpfen) nur außerhalb des Kampfes; im Kampf wird nur neu gezeichnet.

local _, ns = ...
local L = ns.L
local B = ns.Bag
local IsSecret = ns.IsSecret
local API = B.API

---------------------------------------------------------------------------
-- Stil „forever“ (Forever UI): alles hinter FX.On(); im Stil „stray“ bleibt alles wie bisher.
-- Das Fenster entsteht beim Laden der Datei (Einstellungen noch nicht da), der Stil wird deshalb
-- bei PLAYER_LOGIN aufgesetzt (FX.Apply). Hier werden die stray-Teile nur gemerkt.
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
        side       = Col("card", { 0.094, 0.094, 0.118, 1 }),
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
        triage     = { 1, 0.32, 0.22, 1 },
    }
end

local K = {
    GAP = 4, PAD = 10, HEAD = 40, FOOT = 28, HDR_H = 22, HDR_GAP = 6, SEC_GAP = 12,
    MIN_W = 480, BAR_W = 8, MAX_H = 900, MIN_H = 160,
}

-- Zustand des Fensters (gebündelt, um lokale Namen zu sparen)
local W = {
    sideW = 0,           -- Breite der Seitenleiste
    scrollY = 0, scrollMax = 0, viewH = 0, contentH = 0,
    items = {},          -- platzierte Knöpfe: { btn, rec, y }
    placed = {},         -- [Knopf] = true (letzter Layout-Durchlauf)
    bound = setmetatable({}, { __mode = "k" }),  -- [Knopf] = Datensatz
    deco = setmetatable({}, { __mode = "k" }),   -- [Knopf] = eigene Texturen
    pos = setmetatable({}, { __mode = "k" }),    -- [Knopf] = { x, y, size } (letzte Position)
    headers = {}, virt = {}, plus = {},
    search = "", pendingLayout = false, sizing = false,
    sizeSig = "",
    hc = {},             -- Farben der Überschriften (Forever setzt sie um)
}

local function SlotSize()
    local n = ns.db and tonumber(ns.db.bagSlotSize) or 36
    n = math.floor(n + 0.5)
    return math.max(B.C.MIN_SLOT, math.min(B.C.MAX_SLOT, n))
end

local function Columns()
    local n = ns.db and tonumber(ns.db.bagColumns) or 12
    n = math.floor(n + 0.5)
    return math.max(B.C.MIN_COLS, math.min(B.C.MAX_COLS, n))
end

local function GridSize(n)
    if n < 1 then return 0 end
    local s = SlotSize()
    return n * s + (n - 1) * K.GAP
end

local function WidthFor(cols)
    return math.max(K.MIN_W, W.sideW + K.PAD * 2 + K.BAR_W + GridSize(cols))
end

local function ColumnsForWidth(w)
    local n = math.floor((w - W.sideW - K.PAD * 2 - K.BAR_W + K.GAP) / (SlotSize() + K.GAP))
    return math.max(B.C.MIN_COLS, math.min(B.C.MAX_COLS, n))
end

local function MaxHeight()
    local h = UIParent and UIParent:GetHeight()
    if type(h) ~= "number" or IsSecret(h) or h <= K.MIN_H then return K.MAX_H end
    return math.max(K.MIN_H, math.min(K.MAX_H, math.floor(h - 20)))
end

local function FixedHeight()
    local h = ns.db and tonumber(ns.db.bagHeight)
    if not h or h <= 0 then return nil end
    return math.max(K.MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
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

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "strayBagFrame", UIParent)
B.frame = frame
frame:SetSize(K.MIN_W, 300)
frame:SetFrameStrata("MEDIUM")
frame:SetToplevel(true)
frame:Hide()
tinsert(UISpecialFrames, "strayBagFrame") -- Esc schließt

do
    local winBg = Tex(frame, "BACKGROUND", C.bg)
    winBg:SetAllPoints()
    FX.Stray(winBg)
end
FX.Stray(Border(frame, C.line))

ns.MakeMovable(frame, "bagwindow", { "BOTTOMRIGHT", "BOTTOMRIGHT", -16, 96 })

-- Position immer als rechte untere Ecke speichern, damit das Fenster nach oben wächst
local function SavePosition(right, bottom)
    if not (right and bottom) then right, bottom = frame:GetRight(), frame:GetBottom() end
    local uiRight = UIParent:GetRight()
    if not (right and bottom and uiRight) or not ns.db then return end
    uiRight = uiRight * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    ns.db.positions.bagwindow = { "BOTTOMRIGHT", "BOTTOMRIGHT", right - uiRight, bottom }
end

local function Reanchor()
    if ns.editMode then return end
    local right, bottom = frame:GetRight(), frame:GetBottom()
    if not (right and bottom) then return end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
end

frame:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not W.sizing and not Locked() then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    if W.sizing then return end
    self:StopMovingOrSizing()
    SavePosition()
end)

-- Kopf: ohne Shift ziehbar (außer gesperrt)
local head = CreateFrame("Frame", nil, frame)
head:SetPoint("TOPLEFT", 1, -1)
head:SetPoint("TOPRIGHT", -1, -1)
head:SetHeight(K.HEAD - 1)
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
    headLine:SetPoint("TOPLEFT", 1, -K.HEAD); headLine:SetPoint("TOPRIGHT", -1, -K.HEAD); headLine:SetHeight(1)
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
close:SetScript("OnClick", function() B.Close() end)

local search = CreateFrame("EditBox", "strayBagSearch", head)
search:SetSize(140, 22)
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

-- Kopf-Symbole (von rechts nach links vor dem Suchfeld); B.header.icons nimmt Knöpfe der Seitenleiste auf
B.header = { frame = head, search = search, close = close, title = title, slotsText = slotsText }
local icons = CreateFrame("Frame", nil, head)
icons:SetHeight(22)
icons:SetPoint("RIGHT", search, "LEFT", -6, 0)
icons:SetWidth(1)
B.header.icons = icons
local iconList, iconByKey = {}, {}

local function PlaceIcons()
    for i, btn in ipairs(iconList) do
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", icons, "RIGHT", -(i - 1) * 28, 0)
    end
    icons:SetWidth(math.max(1, #iconList * 28 - 6))
end

-- def = { key, icon (Textur), atlas, tooltip (deutscher Schlüssel), onClick = fn(btn, mouse) }
function B.AddHeaderIcon(def)
    if type(def) ~= "table" or not def.key then return nil end
    local btn = iconByKey[def.key]
    if not btn then
        btn = CreateFrame("Button", nil, icons)
        btn:SetSize(22, 22)
        FX.Stray(Tex(btn, "BACKGROUND", C.field)):SetAllPoints()
        FX.Stray(Border(btn, C.line))
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetPoint("TOPLEFT", 3, -3)
        btn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        FX.Stray(hover)
        FX.btns[#FX.btns + 1] = { btn = btn }
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnMouseDown", function(self) self.icon:SetVertexColor(0.7, 0.7, 0.7) end)
        btn:SetScript("OnMouseUp", function(self) self.icon:SetVertexColor(1, 1, 1) end)
        btn:SetScript("OnEnter", function(self)
            local d = self.def
            if d and d.tooltip then
                local tip = type(d.tooltip) == "function" and d.tooltip() or d.tooltip
                Tip(self, L[tip])
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self, mouse)
            local d = self.def
            if d and d.onClick then
                local ok, err = pcall(d.onClick, self, mouse)
                if not ok then geterrorhandler()(err) end
            end
        end)
        iconByKey[def.key] = btn
        iconList[#iconList + 1] = btn
        PlaceIcons()
    end
    btn.def = def
    if def.atlas and btn.icon.SetAtlas then
        pcall(btn.icon.SetAtlas, btn.icon, def.atlas)
    elseif def.icon then
        btn.icon:SetTexture(def.icon)
    end
    return btn
end

function B.GetHeaderIcon(key)
    return iconByKey[key]
end

---------------------------------------------------------------------------
-- Seitenleiste (Platz; T3 hängt Inhalt in B.sidebarHost)
---------------------------------------------------------------------------

local sideBg = Tex(frame, "BACKGROUND", C.side, 1)
sideBg:SetPoint("TOPLEFT", 1, -K.HEAD - 1)
sideBg:SetPoint("BOTTOMLEFT", 1, K.FOOT + 1)
sideBg:SetWidth(1)
FX.Stray(sideBg)
local sideLine = Tex(frame, "BORDER", C.line)
sideLine:SetWidth(1)
FX.lines[#FX.lines + 1] = sideLine

local sideHost = CreateFrame("Frame", nil, frame)
sideHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -K.HEAD - 1)
sideHost:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, K.FOOT + 1)
sideHost:SetWidth(1)
sideHost:Hide()
B.sidebarHost = sideHost

---------------------------------------------------------------------------
-- Inhalt: ScrollFrame mit den Abschnitten. Gegenstandsknöpfe hängen über B.host im Scrollkind.
---------------------------------------------------------------------------

local scroll = CreateFrame("ScrollFrame", nil, frame)
local child = CreateFrame("Frame", nil, scroll)
child:SetSize(10, 10)
scroll:SetScrollChild(child)
B.host:SetParent(child)
B.host:ClearAllPoints()
B.host:SetAllPoints(child)

local function PositionScroll()
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", W.sideW + 1, -K.HEAD - 1)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -K.BAR_W, K.FOOT + 1)
    sideBg:SetWidth(math.max(1, W.sideW))
    sideBg:SetShown(W.sideW > 0)
    sideLine:ClearAllPoints()
    sideLine:SetPoint("TOPLEFT", W.sideW + 1, -K.HEAD - 1)
    sideLine:SetPoint("BOTTOMLEFT", W.sideW + 1, K.FOOT + 1)
    sideLine:SetShown(W.sideW > 0)
    sideHost:SetWidth(math.max(1, W.sideW))
    sideHost:SetShown(W.sideW > 0)
    if FX.side then FX.side:SetShown(W.sideW > 0) end
end
PositionScroll()

local emptyText = Text(child, 12, C.textDim, FONT_BODY)
emptyText:SetPoint("TOPLEFT", K.PAD, -K.PAD)
emptyText:Hide()

-- Scrollbalken rechts (Stil wie ui.lua); die Klickfläche ist breiter als die sichtbare Linie
local scrollTrack = CreateFrame("Button", nil, frame)
scrollTrack:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -K.HEAD - 4)
scrollTrack:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, K.FOOT + 4)
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

-- Größen-Griff unten rechts
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
    if not pcall(frame.SetResizeBounds, frame, K.MIN_W, K.MIN_H, maxW, K.MAX_H) then
        if frame.SetMinResize then pcall(frame.SetMinResize, frame, K.MIN_W, K.MIN_H) end
        if frame.SetMaxResize then pcall(frame.SetMaxResize, frame, maxW, K.MAX_H) end
    end
end
UpdateResizeBounds()

---------------------------------------------------------------------------
-- Fuß: links Platz (B.footerLeft), rechts Gold und Schloss
---------------------------------------------------------------------------

do
    local footLine = Tex(frame, "BORDER", C.line)
    footLine:SetPoint("BOTTOMLEFT", 1, K.FOOT); footLine:SetPoint("BOTTOMRIGHT", -1, K.FOOT); footLine:SetHeight(1)
    FX.lines[#FX.lines + 1] = footLine
end

local footerLeft = CreateFrame("Frame", nil, frame)
footerLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 4)
footerLeft:SetSize(200, K.FOOT - 8)
B.footerLeft = footerLeft

-- Schloss: aus Farbflächen gebaut (Körper + Bügel), damit keine Textur fehlen kann
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
    local body = Part(12, 8, "BOTTOM", 0, 2)
    lockBtn.shackleL = Part(2, 6, "BOTTOMLEFT", 3, 9)
    lockBtn.shackleR = Part(2, 6, "BOTTOMRIGHT", -3, 9)
    lockBtn.shackleT = Part(8, 2, "TOP", 0, -1)
    lockBtn.shackleOpenR = Part(2, 3, "BOTTOMRIGHT", -3, 12)
    lockBtn.body = body
end
local function PaintLock()
    local locked = Locked()
    local c = locked and (W.hc.gold or C.accentText) or C.textDim
    for _, t in ipairs(lockParts) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    -- offen: rechter Bügel höher, oberer Balken kürzer
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

local hintText = Text(frame, 11, C.textDim, FONT_BODY) -- Platz für Statusmeldungen (z. B. Umpacken)
hintText:SetPoint("BOTTOMLEFT", footerLeft, "BOTTOMRIGHT", 6, 1)
B.hintText = hintText

---------------------------------------------------------------------------
-- Gegenstandsknöpfe: Stil und Zeichnen
---------------------------------------------------------------------------

local function Region(b, key, suffix)
    return b[key] or (b:GetName() and _G[b:GetName() .. suffix])
end

-- Beim Anlegen eines Knopfes (Kern): Blizzards Zeichnung dämpfen, eigene Texturen darunter/darüber
local function StyleButton(b)
    local D = {}
    W.deco[b] = D
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

    D.bg = Tex(b, "BACKGROUND", C.slot, -8)
    D.bg:SetAllPoints()

    local icon = Region(b, "icon", "IconTexture") or b.Icon
    D.icon = icon
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
    D.cooldown = cd

    -- Rand im stray-Stil (Farbe nach Qualität) und Marken
    local holder = CreateFrame("Frame", nil, b)
    holder:SetAllPoints()
    holder:SetFrameLevel(b:GetFrameLevel() + 2)
    D.edges = Border(holder, C.slotEdge, "OVERLAY")

    D.quest = holder:CreateTexture(nil, "OVERLAY", nil, 2)
    D.quest:SetPoint("TOPLEFT", 1, -1)
    D.quest:SetPoint("BOTTOMRIGHT", -1, 1)
    D.quest:Hide()

    D.new = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    D.new:SetPoint("TOPLEFT", 1, -1)
    D.new:SetPoint("BOTTOMRIGHT", -1, 1)
    D.new:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.22)
    D.new:Hide()

    D.triage = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    D.triage:SetPoint("TOPLEFT", 1, -1)
    D.triage:SetPoint("BOTTOMRIGHT", -1, 1)
    D.triage:SetColorTexture(C.triage[1], C.triage[2], C.triage[3], 0.22)
    D.triage:Hide()

    D.mark = holder:CreateTexture(nil, "OVERLAY", nil, 3) -- kleines Quadrat oben links (z. B. angeheftet)
    D.mark:SetSize(6, 6)
    D.mark:SetPoint("TOPLEFT", 2, -2)
    D.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    D.mark:Hide()

    D.hover = holder:CreateTexture(nil, "OVERLAY", nil, 4) -- Hervorhebung von außen (z. B. Taschen-Slots)
    D.hover:SetAllPoints()
    D.hover:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.28)
    D.hover:Hide()

    D.dim = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    D.dim:SetAllPoints()
    D.dim:SetColorTexture(0, 0, 0, 0.7)
    D.dim:Hide()

    -- Anzahl über unserem Rand halten
    local count = Region(b, "Count", "Count")
    if count and count.SetParent then
        pcall(count.SetParent, count, holder)
        count:SetDrawLayer("OVERLAY", 6)
    end
    D.holder = holder
end

B.OnButtonCreated(function(b) pcall(StyleButton, b) end)

-- Zugriff für andere Dateien (z. B. Hervorhebung, Markierungen): Zeichnungs-Texturen eines Knopfes
function B.ButtonDeco(btn)
    return W.deco[btn]
end

local function SetCooldown(D, bag, slot, hasItem)
    local cd = D.cooldown
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

local function QuestMarksOn()
    return ns.db and ns.db.questItemMarks and true or false
end

-- Suche: leer = alles passt; sonst Name enthält den Text (leere Plätze passen nie)
function B.SetSearch(text)
    text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    W.search = text
    if search:GetText():lower() ~= text then search:SetText(text) end
end

function B.GetSearch() return W.search end

function B.MatchesSearch(rec)
    if W.search == "" then return true end
    if not rec or not rec.hasItem or not rec.nameLower then return false end
    return rec.nameLower:find(W.search, 1, true) ~= nil
end

local triageBag, triageSlot

-- Schnittstelle für triage.lua: Löschkandidat markieren (bag, slot) oder aufheben (nil)
function B.SetTriage(bag, slot)
    if IsSecret(bag) or IsSecret(slot) or type(bag) ~= "number" or type(slot) ~= "number" then
        bag, slot = nil, nil
    end
    if bag == triageBag and slot == triageSlot then return end
    triageBag, triageSlot = bag, slot
    if B.RequestPaint then B.RequestPaint() end
end
ns.BagWindowSetTriage = B.SetTriage

-- Zeichnet einen Knopf nach seinem Datensatz (nie im Kampf geschützt: nur Texturen und Texte)
local function Paint(b, rec)
    local D = W.deco[b]
    if not D or not rec then return end
    local hasItem = rec.hasItem
    local questNeeded = rec.questNeeded and QuestMarksOn()
    local isTriage = hasItem and rec.bag == triageBag and rec.slot == triageSlot
    if SetItemButtonTexture then
        pcall(SetItemButtonTexture, b, rec.icon)
    elseif D.icon then
        D.icon:SetTexture(rec.icon)
    end
    if D.icon then D.icon:SetShown(rec.icon ~= nil) end
    local count = rec.displayCount or rec.count
    count = (type(count) == "number") and count or 0
    if SetItemButtonCount then
        pcall(SetItemButtonCount, b, count)
    else
        local fs = Region(b, "Count", "Count")
        if fs then
            fs:SetText(count > 1 and count or "")
            fs:SetShown(count > 1)
        end
    end
    local locked = rec.locked and true or false
    if SetItemButtonDesaturated then
        pcall(SetItemButtonDesaturated, b, locked)
    elseif D.icon then
        D.icon:SetDesaturated(locked)
    end
    if D.icon then
        local v = locked and 0.5 or 1
        D.icon:SetVertexColor(v, v, v)
    end

    -- Rand: Löschkandidat rot, Quest gold, sonst Qualität (ab „ungewöhnlich“ farbig, Schrott grau)
    local q = rec.quality
    if isTriage then
        SetEdges(D.edges, C.triage[1], C.triage[2], C.triage[3], 1)
    elseif rec.questItem or questNeeded or rec.questStarter then
        SetEdges(D.edges, C.quest[1], C.quest[2], C.quest[3], 1)
    elseif hasItem and type(q) == "number" and q >= 2 and API.QualityColor(q) then
        local r, g, bl = API.QualityColor(q)
        SetEdges(D.edges, r, g, bl, 1)
    elseif hasItem and q == 0 then
        SetEdges(D.edges, 0.40, 0.40, 0.40, 1)
    elseif hasItem then
        SetEdges(D.edges, C.itemEdge[1], C.itemEdge[2], C.itemEdge[3], 1)
    else
        SetEdges(D.edges, C.slotEdge[1], C.slotEdge[2], C.slotEdge[3], 0.7)
    end
    D.bg:SetColorTexture(C.slot[1], C.slot[2], C.slot[3], hasItem and 1 or 0.7)

    if rec.questStarter or questNeeded then
        D.quest:SetTexture(TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang")
        D.quest:Show()
    elseif rec.questItem then
        D.quest:SetTexture(TEXTURE_ITEM_QUEST_BORDER or "Interface\\ContainerFrame\\UI-Icon-QuestBorder")
        D.quest:Show()
    else
        D.quest:Hide()
    end
    D.triage:SetShown(isTriage and true or false)
    D.new:SetShown(rec.isNew and true or false)
    D.dim:SetShown(not B.MatchesSearch(rec))
    SetCooldown(D, rec.bag, rec.slot, hasItem)
end
B.PaintButton = Paint

local function PaintAll()
    for _, it in ipairs(W.items) do
        -- feste Plätze: frisch aus dem Scan lesen, Kopien der Ansicht (z. B. zusammengefasst) wie gebaut
        local rec = it.rec
        if not rec.synthetic then rec = B.GetRecord(it.rec.bag, it.rec.slot) or rec end
        pcall(Paint, it.btn, rec)
    end
    for _, v in ipairs(W.virt) do
        if v.shown then
            local dim = W.search ~= ""
            v.dim:SetShown(dim)
        end
    end
end

---------------------------------------------------------------------------
-- Überschriften, gedimmte Felder, Plus-Felder (aus Pools)
---------------------------------------------------------------------------

local function HeaderColors()
    local hc = W.hc
    return hc.text or C.text, hc.dim or C.textDim, hc.line or C.line, hc.btn or C.accentText
end

local function MakeHeader()
    local h = CreateFrame("Button", nil, child)
    h:SetHeight(K.HDR_H)
    h.arrow = h:CreateTexture(nil, "ARTWORK")
    h.arrow:SetSize(12, 12)
    h.arrow:SetPoint("LEFT", 0, 0)
    h.label = Text(h, 13, C.text)
    h.count = Text(h, 11, C.textDim, FONT_BODY)
    h.line = h:CreateTexture(nil, "BORDER")
    h.line:SetHeight(1)
    h.right = CreateFrame("Button", nil, h)
    h.right:SetHeight(K.HDR_H - 4)
    h.right.text = Text(h.right, 11, C.accentText, FONT_BODY)
    h.right.text:SetPoint("CENTER")
    h.right:SetScript("OnClick", function(self)
        local d = self.def
        if d and d.onClick then
            local ok, err = pcall(d.onClick, self.section)
            if not ok then geterrorhandler()(err) end
        end
    end)
    h.right:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        local d = self.def
        if d and d.tooltip then Tip(self, L[d.tooltip]) end
    end)
    h.right:SetScript("OnLeave", function(self)
        local _, _, _, bc = HeaderColors()
        self.text:SetTextColor(bc[1], bc[2], bc[3])
        GameTooltip:Hide()
    end)
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h:SetScript("OnClick", function(self, mouse)
        local s = self.section
        if mouse == "RightButton" then
            -- Kontextmenü der Ansicht (sec.onContext = fn(section, headerButton))
            if s and s.onContext then
                local ok, err = pcall(s.onContext, s, self)
                if not ok then geterrorhandler()(err) end
            end
            return
        end
        if s and s.collapsible then
            if s.onToggle then pcall(s.onToggle, s) end
            B.RequestRefresh(0, "layout")
        end
    end)
    return h
end

local function StyleHeader(h, sec)
    local tc, dc, lc, bc = HeaderColors()
    h.section = sec
    h.label:SetTextColor(tc[1], tc[2], tc[3])
    h.count:SetTextColor(dc[1], dc[2], dc[3])
    h.line:SetColorTexture(lc[1], lc[2], lc[3], lc[4] or 1)
    h.label:SetText(sec.title or "")
    h.count:SetText(sec.counter or "")
    h.arrow:SetShown(sec.collapsible and true or false)
    if sec.collapsible then
        h.arrow:SetTexture(sec.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        h.label:ClearAllPoints()
        h.label:SetPoint("LEFT", h.arrow, "RIGHT", 4, 0)
    else
        h.label:ClearAllPoints()
        h.label:SetPoint("LEFT", 0, 0)
    end
    h.count:ClearAllPoints()
    h.count:SetPoint("LEFT", h.label, "RIGHT", 8, -1)
    local hb = sec.headerButton
    if type(hb) == "table" and hb.text then
        h.right.def, h.right.section = hb, sec
        h.right.text:SetText(L[hb.text])
        h.right.text:SetTextColor(bc[1], bc[2], bc[3])
        h.right:SetWidth(math.max(20, math.floor((h.right.text:GetStringWidth() or 30) + 12)))
        h.right:ClearAllPoints()
        h.right:SetPoint("RIGHT", h, "RIGHT", 0, 0)
        h.right:Show()
    else
        h.right:Hide()
    end
    h.line:ClearAllPoints()
    h.line:SetPoint("LEFT", h.count, "RIGHT", 10, 0)
    if h.right:IsShown() then
        h.line:SetPoint("RIGHT", h.right, "LEFT", -8, 0)
    else
        h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    end
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

local function MakePlus()
    local p = CreateFrame("Button", nil, child)
    p.bg = Tex(p, "BACKGROUND", C.slot)
    p.bg:SetAllPoints()
    p.edges = Border(p, C.slotEdge)
    p.text = Text(p, 20, C.textDim, FONT_BODY)
    p.text:SetPoint("CENTER", 0, 1)
    p.text:SetText("+")
    local hl = p:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    local function PlusClick(self)
        local s = self.section
        if s and s.onPlus then
            local ok, err = pcall(s.onPlus, s, self)
            if not ok then geterrorhandler()(err) end
        end
    end
    p:SetScript("OnClick", PlusClick)
    p:SetScript("OnReceiveDrag", PlusClick) -- Gegenstand vom Cursor ablegen
    p:SetScript("OnEnter", function(self)
        if self.section and self.section.plusTooltip then Tip(self, L[self.section.plusTooltip]) end
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return p
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

-- Darf das Fenster gerade Knöpfe zeigen/verstecken/verschieben?
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

-- Knöpfe außerhalb des sichtbaren Bereichs verstecken (nur außerhalb des Kampfes; Beschnitt macht der ScrollFrame)
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

local liveCols -- Spalten während des Ziehens

-- Setzt einen Knopf (nur Position/Größe, wenn sich etwas geändert hat)
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
        b:SetPoint("TOPLEFT", B.host, "TOPLEFT", x, -y)
        p.x, p.y = x, y
    end
end

local function Layout(live, keepBottomRight)
    local size, gap, pad = SlotSize(), K.GAP, K.PAD
    local cols = (live and liveCols) or Columns()
    local sections = B.BuildSections()
    local seen, nowPlaced = {}, {}
    wipe(W.items)
    local hdrN, virtN, plusN = 0, 0, 0
    local y = pad
    local first = true

    for _, sec in ipairs(sections) do
        if not sec.hidden then
            if not first then y = y + K.SEC_GAP end
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
                y = y + K.HDR_H + K.HDR_GAP
            end
            if not sec.collapsed then
                -- Zellen: Gegenstände, echte leere Plätze, gedimmte Felder, Plus-Feld
                local cell = 0
                local function Next()
                    cell = cell + 1
                    return ((cell - 1) % cols) * (size + gap), y + math.floor((cell - 1) / cols) * (size + gap)
                end
                local function Add(rec)
                    local x, cy = Next()
                    local id = rec.bag * 1000 + rec.slot
                    seen[id] = (seen[id] or 0) + 1
                    local b = B.AcquireButton(rec.bag, rec.slot, seen[id])
                    if b then
                        PlaceButton(b, x, cy, size)
                        W.bound[b] = rec
                        nowPlaced[b] = true
                        W.items[#W.items + 1] = { btn = b, rec = rec, y = cy, shown = b:IsShown() }
                    end
                end
                for _, rec in ipairs(sec.items or {}) do Add(rec) end
                for _, rec in ipairs(sec.empties or {}) do Add(rec) end
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
                if sec.plus then
                    local x, cy = Next()
                    plusN = plusN + 1
                    local p = W.plus[plusN]
                    if not p then
                        p = MakePlus()
                        W.plus[plusN] = p
                    end
                    p.section = sec
                    p:ClearAllPoints()
                    p:SetPoint("TOPLEFT", child, "TOPLEFT", x, -cy)
                    p:SetSize(size, size)
                    p:Show()
                end
                local rows = math.ceil(cell / cols)
                if rows > 0 then y = y + rows * (size + gap) - gap end
            else
                y = y - K.HDR_GAP -- eingeklappt: nur die Überschrift
            end
        end
    end
    for i = hdrN + 1, #W.headers do W.headers[i]:Hide() end
    for i = virtN + 1, #W.virt do W.virt[i]:Hide(); W.virt[i].shown = false end
    for i = plusN + 1, #W.plus do W.plus[i]:Hide() end
    emptyText:SetShown(#sections == 0)

    -- nicht mehr benutzte Knöpfe weg
    for b in pairs(W.placed) do
        if not nowPlaced[b] then B.ReleaseButton(b) end
    end
    W.placed = nowPlaced

    -- Größe: Breite folgt den Spalten, Höhe automatisch oder fest (bagHeight); der Rest scrollt
    local contentH = y + pad
    local width = WidthFor(cols)
    local innerW = width - W.sideW - 1 - K.BAR_W
    child:SetSize(math.max(1, innerW), math.max(1, contentH))
    W.contentH = contentH
    local height
    if live then
        height = frame:GetHeight() or K.MIN_H
    else
        height = FixedHeight() or math.max(K.MIN_H, math.min(MaxHeight(), K.HEAD + 1 + contentH + K.FOOT + 1))
    end
    W.viewH = math.max(1, height - K.HEAD - K.FOOT - 2)
    W.scrollMax = math.max(0, contentH - W.viewH)
    if not live then
        if not keepBottomRight then Reanchor() end
        frame:SetSize(width, height)
        UpdateResizeBounds()
    end
    SetScroll(W.scrollY, true)
    -- Sichtbarkeit nach Scrollbereich; neue Knöpfe erst jetzt zeigen
    local top, bottom = W.scrollY - size * 2, W.scrollY + W.viewH + size * 2
    for _, it in ipairs(W.items) do
        local vis = it.y + size >= top and it.y <= bottom
        it.shown = vis
        if vis then it.btn:Show() else it.btn:Hide() end
    end
end

local function UpdateHeader()
    slotsText:SetText(L("%d / %d Plätze", B.used, B.total))
    local money = GetMoney and ns.Public(GetMoney())
    moneyText:SetText(type(money) == "number" and ns.FormatMoney(money) or "")
end

local function SizeSignature()
    local parts = {}
    for _, bag in ipairs(B.bagIDs) do
        local info = B.bags[bag]
        parts[#parts + 1] = bag .. ":" .. (info and info.size or 0)
    end
    return table.concat(parts, ",")
end

local function Update()
    if not frame:IsShown() then return end
    -- Taschen getauscht oder gewachsen? Fehlende Knöpfe anlegen (nur außerhalb des Kampfes)
    local sig = SizeSignature()
    if sig ~= W.sizeSig or not W.poolReady then
        if not InCombatLockdown() then
            W.poolReady = B.WarmPool()
            W.sizeSig = sig
        end
    end
    if CanLayout() then
        W.pendingLayout = false
        Layout(W.sizing)
    else
        W.pendingLayout = true
    end
    PaintAll()
    UpdateHeader()
end

function B.RequestLayout() B.RequestRefresh(0, "layout") end

local paintPending = false
function B.RequestPaint()
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

B.OnRefresh(function()
    if frame:IsShown() then Update() end
end)

function B.SetSidebarWidth(w)
    w = math.max(0, math.floor(tonumber(w) or 0))
    if w == W.sideW then return end
    W.sideW = w
    if CanLayout() then PositionScroll() else W.pendingLayout = true end
    UpdateResizeBounds()
    B.RequestLayout()
end

function B.SidebarWidth() return W.sideW end

search:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    placeholder:SetShown(text == "" and not self:HasFocus())
    W.search = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    B.RequestPaint()
end)

---------------------------------------------------------------------------
-- Blättern: Mausrad, Scrollbalken ziehen oder in die Spur klicken
---------------------------------------------------------------------------

do
local function OnWheel(_, delta)
    if type(delta) ~= "number" or W.scrollMax <= 0 then return end
    SetScroll(W.scrollY - delta * (SlotSize() + K.GAP) * 1.5)
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
        local moved = thumb.startY - CursorY()
        SetScroll(thumb.startScroll + moved / free * W.scrollMax)
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
    SetScroll(math.max(0, math.min(free, pos)) / free * W.scrollMax)
end)
end

---------------------------------------------------------------------------
-- Größe ziehen: Breite rastet auf Spalten ein, Höhe frei
---------------------------------------------------------------------------

do
local startW, startH, startCols

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
    -- kleine Wackler (unter 8 px) ändern die Spalten nicht
    if math.abs(w - startW) >= 8 then
        liveCols = ColumnsForWidth(w)
    else
        liveCols = startCols
    end
    Layout(true)
end

frame:SetScript("OnSizeChanged", function()
    if W.sizing then pcall(OnSizing) end
end)

local function StopSizing()
    if not W.sizing then return end
    W.sizing = false
    frame:StopMovingOrSizing()
    local w, h = frame:GetSize()
    if ns.db and type(w) == "number" and type(h) == "number" then
        if math.abs(w - startW) >= 8 then
            ns.db.bagColumns = ColumnsForWidth(w)
            if ns.RefreshConfig then pcall(ns.RefreshConfig) end
        end
        -- Nur wer die Höhe wirklich verändert, legt eine feste Höhe fest
        if math.abs(h - startH) >= 19 then
            ns.db.bagHeight = math.max(K.MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
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
    PaintAll()
end

grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or W.sizing or not ns.db or not W.poolReady or Locked() then return end
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
        W.sizing = true
    else
        liveCols = nil
        Reanchor()
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
    GameTooltip:AddLine(L["Höhe wieder automatisch: im Bearbeitungsmodus Shift+Rechtsklick auf das Taschenfenster."], C.textDim[1], C.textDim[2], C.textDim[3], true)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", function(self)
    self:SetAlpha(0.5)
    GameTooltip:Hide()
end)
end

---------------------------------------------------------------------------
-- Stil „forever“: Bronze-Rahmen mit Eckwinkeln, Schiefer, Gold-Titel, Plätze als dunkle Felder mit
-- Bronzerand (Qualitätsfarben bleiben). Bei einem Fehler bleibt die stray-Optik.
---------------------------------------------------------------------------

function FX.Apply()
    if FX.done or FX.failed or not FX.On() then return end
    -- Nur außerhalb des Kampfes, solange geschützte Knöpfe am Fenster hängen
    if InCombatLockdown() and AnyProtected(frame) then
        FX.retry = true
        return
    end
    FX.retry = false
    local S = ns.Style
    local made = {}
    local ok = pcall(function()
        -- Rahmen: liegt größtenteils außerhalb des Fensters, damit der Inhalt unverändert bleibt
        local deco = CreateFrame("Frame", nil, frame)
        made[#made + 1] = deco
        deco:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, 5)
        deco:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
        deco:SetFrameLevel(frame:GetFrameLevel() + 1)
        S.Border(deco, { size = 8, cornerSize = 16, cornerOffset = 3 })
        made[#made + 1] = S.Fill(frame, "window")

        -- Seitenleiste auf eigener Schieferfläche
        local side = CreateFrame("Frame", nil, frame)
        made[#made + 1] = side
        side:SetPoint("TOPLEFT", sideHost, "TOPLEFT", 0, 0)
        side:SetPoint("BOTTOMRIGHT", sideHost, "BOTTOMRIGHT", 0, 0)
        side:SetFrameLevel(frame:GetFrameLevel())
        made[#made + 1] = S.Fill(side, "panel")
        FX.side = side

        for _, item in ipairs(FX.btns) do
            local obj = S.Button(item.btn, item.kind or "secondary")
            made[#made + 1] = obj
            item.obj = obj
        end
        made[#made + 1] = S.EditBox(search)
    end)
    if not ok then
        for _, o in ipairs(made) do FXHide(o) end
        FX.failed = true
        return
    end
    FX.done = true
    FX.side:SetShown(W.sideW > 0)

    for _, o in ipairs(FX.stray) do FXHide(o) end

    -- Palette der Plätze und Felder (wirkt auch auf später gebaute Knöpfe)
    local P = ns.Colors
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
    local function Safe(fn, ...) pcall(fn, ...) end

    local br = P.bronze or P.line
    for _, t in ipairs(FX.lines) do t:SetColorTexture(br[1], br[2], br[3], 0.85) end
    if FX.track then FX.track:SetColorTexture(br[1], br[2], br[3], 0.5) end
    local gd = P.goldDim or P.accentText
    W.hc.gold, W.hc.text, W.hc.dim = P.gold, P.gold or P.text, P.textDim
    W.hc.line = { br[1], br[2], br[3], 0.85 }
    W.hc.btn = gd

    Safe(title.SetFont, title, S.FontTitle(), 15, "")
    Tint(title, P.gold)
    Tint(slotsText, P.textDim)
    Tint(placeholder, P.textFaint)
    Tint(emptyText, P.textDim)
    Tint(moneyText, P.text)
    Tint(hintText, P.textDim)
    search:SetTextColor(P.text[1], P.text[2], P.text[3])
    for _, item in ipairs(FX.btns) do
        if item.text and item.obj and item.obj.textColor then Tint(item.text, item.obj.textColor) end
    end
    for _, h in ipairs(W.headers) do Safe(h.label.SetFont, h.label, S.FontTitle(), 13, "") end

    -- Größen-Griff: in Bronze, etwas aus der Ecke gerückt (Eckwinkel)
    grip:ClearAllPoints()
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    local nt = grip.GetNormalTexture and grip:GetNormalTexture()
    local bl = P.bronzeLight or br
    if nt then Safe(nt.SetVertexColor, nt, bl[1], bl[2], bl[3]) end

    PaintLock()
    if frame:IsShown() then B.RequestLayout() end
end

---------------------------------------------------------------------------
-- Öffnen und Schließen
---------------------------------------------------------------------------

local previewOpened = false

-- Sichtbare Texte erst beim Anzeigen übersetzen (Sprache ist umschaltbar)
local function RefreshTexts()
    title:SetText(L["Inventar"])
    placeholder:SetText(L["Suchen …"])
    emptyText:SetText(L["Keine Gegenstände."])
end

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
    B.Refresh("open")
end)

frame:SetScript("OnHide", function()
    B.openerName = nil
    previewOpened = false
    search:ClearFocus()
    PlayOpenSound(false)
end)

-- Kann das Fenster jetzt aufgehen? (Kern: Übernahme nur, wenn ja; sonst bleiben Blizzards Taschen)
function B.CanShow()
    if not B.Enabled() then return false end
    if InCombatLockdown() then
        -- im Kampf nur, wenn alle Knöpfe schon da sind und das Fenster (noch) nicht geschützt ist
        return W.poolReady == true and not AnyProtected(frame)
    end
    return true
end

function B.Open()
    if frame:IsShown() then return true end
    if not B.CanShow() then return false end
    if not W.poolReady then W.poolReady = B.WarmPool() end
    if not W.poolReady and InCombatLockdown() then return false end
    frame:Show()
    return true
end

function B.Close()
    if not frame:IsShown() then return true end
    if InCombatLockdown() and AnyProtected(frame) then return false end
    frame:Hide()
    return true
end

function B.Toggle()
    if frame:IsShown() then return B.Close() end
    return B.Open()
end

function B.IsOpen()
    return frame:IsShown()
end

-- Höhe im Bearbeitungsmodus: bagHeight 0 = automatisch (nach Inhalt). Untergrenze 0, damit
-- „Zurücksetzen“ (Standard 0) nicht auf die kleinste feste Höhe geklemmt wird.
do
local function NormalizeHeight()
    if not ns.db then return end
    local h = tonumber(ns.db.bagHeight)
    if not h or IsSecret(h) or h <= 0 then
        ns.db.bagHeight = 0
    else
        ns.db.bagHeight = math.max(K.MIN_H, math.min(MaxHeight(), math.floor(h + 0.5)))
    end
end

ns.RegisterMovable(frame, "Taschenfenster", function(on)
    if on then
        if B.Enabled() and not frame:IsShown() and not InCombatLockdown() and B.Open() then
            previewOpened = true
        end
    elseif previewOpened then
        B.Close()
    end
end, {
    heightKey = "bagHeight",
    heightMin = 0,
    heightMax = K.MAX_H,
    onSize = function(which)
        if which ~= "height" then return end
        NormalizeHeight()
        B.RequestLayout()
    end,
})
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    local h = tonumber(ns.db.bagHeight)
    ns.db.bagHeight = (h and h > 0) and math.max(K.MIN_H, math.min(K.MAX_H, math.floor(h + 0.5))) or 0
    pcall(FX.Apply)
    UpdateResizeBounds()
    ns.RestorePosition(frame)
    PaintLock()
    grip:SetShown(not Locked())
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if FX.retry then pcall(FX.Apply) end
    if W.pendingLayout and frame:IsShown() then B.RequestLayout() end
end)

ns.On("PLAYER_MONEY", function() if frame:IsShown() then UpdateHeader() end end)
