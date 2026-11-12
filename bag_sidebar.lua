-- stray – stray-Tasche: Seitenleiste (Kategorien-Filter) und Kopf-Symbole
--   Seitenleiste:  links im Fenster, nur in der Ansicht „Kategorien“ (Option bagSidebar); ein Knopf je
--                  Kategorie (B.Categories.List) plus „Alle“. Klick setzt B.Categories.SetFilter.
--   Kopf-Symbole:  Taschen (Taschenplätze, Tasche einsetzen/tauschen), Schrott-Markierer, Sortieren,
--                  Schnellaktionen (nur Hervorhebung). „Schrott verkaufen“ sitzt beim Händler im Fuß.
-- Taint: Markier-Modus und Hervorhebungen laufen über eigene Rahmen (Klick-Overlay) und eigene Texturen;
-- an Blizzards Gegenstandsknöpfen wird nichts geschrieben (Zustand in schwachen Tabellen).
-- Einhängepunkt im Fenster: B.AfterPaint(btn, rec, deco) wird von B.PaintButton gerufen.

local _, ns = ...
local L = ns.L
local B = ns.Bag
local IsSecret = ns.IsSecret
local API = B.API
local Container = C_Container or {}

local FONT_BODY = "Fonts\\ARIALN.TTF"
local RED = { 0.992, 0.071, 0.129 } -- Markenrot #FD1221

ns.defaults.bagSidebar = true
ns.defaults.bagSidebarCollapsed = false
ns.defaults.bagSlotsShown = false
ns.defaults.bagIconSlots = true
ns.defaults.bagIconJunk = true
ns.defaults.bagIconSort = true
ns.defaults.bagIconQuick = false
ns.defaults.bagJunkGrey = false

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------

local function Pal(key, fb)
    local P = ns.Colors
    local c = type(P) == "table" and P[key]
    if type(c) == "table" and type(c[1]) == "number" then return c end
    return fb
end

local function Forever()
    local S = ns.Style
    if not (S and S.IsForever) then return false end
    local ok, v = pcall(S.IsForever)
    return ok and v == true
end

local P = {} -- Farben (bei der Anzeige neu gelesen, damit der Stilwechsel wirkt)
local function LoadPalette()
    P.text = Pal("text", { 0.9, 0.9, 0.93, 1 })
    P.dim = Pal("textDim", { 0.55, 0.55, 0.6, 1 })
    P.line = Pal("line", { 0.15, 0.15, 0.18, 1 })
    P.accent = Pal("accentText", { 0.7, 0.66, 0.98, 1 })
    if Forever() then
        P.line = Pal("bronze", P.line)
        P.accent = Pal("gold", P.accent)
    end
end
LoadPalette()

local function Tex(parent, layer, c, sub)
    local t = parent:CreateTexture(nil, layer or "BORDER", nil, sub)
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

local function Edges(frame, c)
    local e = {}
    for i = 1, 4 do e[i] = Tex(frame, "BORDER", c) end
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(1)
    return e
end

local function SetEdges(e, r, g, b, a)
    for _, t in ipairs(e) do t:SetColorTexture(r, g, b, a or 1) end
end

local function Text(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT_BODY, size, "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Enabled()
    return B.Enabled() and ns.db ~= nil
end

local function InCombat()
    return InCombatLockdown() and true or false
end

local hintToken = 0
local function Hint(text, seconds)
    local fs = B.hintText
    if not fs then return end
    hintToken = hintToken + 1
    local token = hintToken
    fs:SetText(text or "")
    if seconds then
        C_Timer.After(seconds, function()
            if token == hintToken then fs:SetText("") end
        end)
    end
end

local function ClearHint(text)
    local fs = B.hintText
    if fs and text and fs:GetText() == text then
        hintToken = hintToken + 1
        fs:SetText("")
    end
end

local function CursorItemID()
    if not GetCursorInfo then return nil end
    local ok, kind, id = pcall(GetCursorInfo)
    if ok and not IsSecret(kind) and kind == "item" and not IsSecret(id) and type(id) == "number" then return id end
    return nil
end

local function ClearCursorSafe()
    if ClearCursor then pcall(ClearCursor) end
end

---------------------------------------------------------------------------
-- Seitenleiste
---------------------------------------------------------------------------

local SB = { W_COLLAPSED = 28, W_EXPANDED = 150, ROW = 24, entries = {}, data = setmetatable({}, { __mode = "k" }) }

local host = B.sidebarHost
local arrowBtn = CreateFrame("Button", nil, host)
arrowBtn:SetHeight(22)
arrowBtn:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -1)
arrowBtn:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -1)
arrowBtn.text = Text(arrowBtn, 13, P.dim)
arrowBtn.text:SetPoint("CENTER", 0, 1)
arrowBtn.hl = arrowBtn:CreateTexture(nil, "HIGHLIGHT")
arrowBtn.hl:SetAllPoints()
arrowBtn.hl:SetColorTexture(1, 1, 1, 0.07)

local sideScroll = CreateFrame("ScrollFrame", nil, host)
sideScroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -25)
sideScroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 2)
local sideChild = CreateFrame("Frame", nil, sideScroll)
sideChild:SetSize(10, 10)
sideScroll:SetScrollChild(sideChild)
sideScroll:EnableMouseWheel(true)
sideScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (sideChild:GetHeight() or 0) - (self:GetHeight() or 0))
    local y = math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * SB.ROW * 2))
    self:SetVerticalScroll(y)
end)

local function Collapsed()
    return ns.db and ns.db.bagSidebarCollapsed and true or false
end

local function SidebarActive()
    return Enabled() and ns.db.bagSidebar and ns.db.bagView == "categories" and B.Categories ~= nil
end

local function EntryTooltip(self)
    local d = SB.data[self]
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(string.format("%s (%d)", d.title or "", d.count or 0), 1, 1, 1)
    GameTooltip:Show()
end

local function PickEntry(self)
    local d = SB.data[self]
    local Cat = B.Categories
    if not (d and Cat) then return end
    if d.key == nil or Cat.GetFilter() == d.key then
        Cat.SetFilter(nil)
    else
        Cat.SetFilter(d.key)
    end
end

local function MakeEntry()
    local e = CreateFrame("Button", nil, sideChild)
    e:SetHeight(SB.ROW)
    e.bg = Tex(e, "BACKGROUND", { RED[1], RED[2], RED[3], 0.12 })
    e.bg:SetAllPoints()
    e.bar = Tex(e, "ARTWORK", RED)
    e.bar:SetPoint("TOPLEFT", 0, -2)
    e.bar:SetPoint("BOTTOMLEFT", 0, 2)
    e.bar:SetWidth(3)
    e.icon = e:CreateTexture(nil, "ARTWORK")
    e.icon:SetSize(18, 18)
    e.icon:SetPoint("LEFT", 7, 0)
    e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    e.count = Text(e, 11, P.dim)
    e.count:SetPoint("RIGHT", -6, 0)
    e.count:SetJustifyH("RIGHT")
    e.name = Text(e, 12, P.text)
    e.name:SetPoint("LEFT", e.icon, "RIGHT", 6, 0)
    e.name:SetPoint("RIGHT", e.count, "LEFT", -4, 0)
    e.name:SetWordWrap(false)
    local hl = e:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    e:SetScript("OnClick", PickEntry)
    e:SetScript("OnEnter", EntryTooltip)
    e:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return e
end

function SB.Update()
    if not SidebarActive() then
        if B.SetSidebarWidth then B.SetSidebarWidth(0) end
        return
    end
    LoadPalette()
    local collapsed = Collapsed()
    local w = collapsed and SB.W_COLLAPSED or SB.W_EXPANDED
    B.SetSidebarWidth(w)
    sideChild:SetWidth(w)
    arrowBtn.text:SetText(collapsed and "»" or "«")
    arrowBtn.text:SetTextColor(P.dim[1], P.dim[2], P.dim[3])

    local Cat = B.Categories
    local filter = Cat.GetFilter()
    local rows = {
        { key = nil, title = L["Alle"], icon = "Interface\\Icons\\INV_Misc_Bag_08", count = B.used or 0 },
    }
    for _, c in ipairs(Cat.List()) do rows[#rows + 1] = c end
    for i, r in ipairs(rows) do
        local e = SB.entries[i]
        if not e then
            e = MakeEntry()
            SB.entries[i] = e
        end
        local d = SB.data[e]
        if not d then
            d = {}
            SB.data[e] = d
        end
        d.key, d.title, d.count = r.key, r.title, r.count
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, -(i - 1) * SB.ROW)
        e:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", 0, -(i - 1) * SB.ROW)
        e.icon:SetTexture(r.icon)
        local active = (filter == r.key)
        e.bar:SetShown(active)
        e.bg:SetShown(active)
        e.name:SetShown(not collapsed)
        e.count:SetShown(not collapsed)
        e.name:SetText(r.title or "")
        e.count:SetText(tostring(r.count or 0))
        local tc = active and P.text or P.dim
        e.name:SetTextColor(tc[1], tc[2], tc[3])
        e.count:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
        e.icon:SetAlpha(active and 1 or 0.8)
        e:Show()
    end
    for i = #rows + 1, #SB.entries do SB.entries[i]:Hide() end
    sideChild:SetHeight(#rows * SB.ROW)
end

arrowBtn:SetScript("OnClick", function()
    if not ns.db then return end
    ns.db.bagSidebarCollapsed = not ns.db.bagSidebarCollapsed
    SB.Update()
end)
arrowBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(Collapsed() and L["Seitenleiste ausklappen"] or L["Seitenleiste einklappen"], 1, 1, 1)
    GameTooltip:Show()
end)
arrowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Schrott: Markierungen, Markier-Modus, Münze an den Gegenständen
---------------------------------------------------------------------------

local J = { on = false, coins = setmetatable({}, { __mode = "k" }), glow = setmetatable({}, { __mode = "k" }) }
local Q = { on = false, de = false, lock = false, lockCache = {} }
local icons = {} -- [key] = Kopf-Symbol

local function Marks()
    if not ns.db then return nil end
    if type(ns.db.bagJunkMarks) ~= "table" then ns.db.bagJunkMarks = {} end
    return ns.db.bagJunkMarks
end

local function SetGlow(btn, on)
    if not btn then return end
    local g = J.glow[btn]
    if not g then
        g = btn:CreateTexture(nil, "OVERLAY")
        g:SetAllPoints()
        g:SetColorTexture(RED[1], RED[2], RED[3], 0.35)
        J.glow[btn] = g
    end
    g:SetShown(on and true or false)
end

local function Repaint()
    B.RequestLayout()
    B.RequestPaint()
end

-- Markierung umschalten: normaler Gegenstand → Schrott, grauer → geschützt, zweiter Klick löscht
local function ToggleMark(rec)
    local marks = Marks()
    if not (marks and rec and rec.hasItem and rec.itemID) then return end
    local id = rec.itemID
    local cur = marks[id]
    if rec.quality == 0 then
        if cur == false then marks[id] = nil else marks[id] = false end
    else
        if cur == true then marks[id] = nil else marks[id] = true end
    end
    local name = rec.name or ""
    if marks[id] == true then
        Hint(L("%s als Schrott markiert", name), 3)
    elseif marks[id] == false then
        Hint(L("%s ist vor dem Verkauf geschützt", name), 3)
    else
        Hint(L("Markierung von %s entfernt", name), 3)
    end
    Repaint()
end

-- Klick-Overlay über dem Raster: fängt die Klicks im Markier-Modus ab, Blizzards Knöpfe bleiben unberührt
local overlay = CreateFrame("Button", nil, B.frame)
overlay:SetFrameLevel(B.frame:GetFrameLevel() + 15)
overlay:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, 0)
overlay:SetPoint("BOTTOMRIGHT", B.frame, "BOTTOMRIGHT", -8, 29)
overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
overlay:EnableMouseWheel(true)
overlay:Hide()
overlay:SetScript("OnMouseWheel", function(_, delta)
    local f = B.frame:GetScript("OnMouseWheel")
    if f then pcall(f, B.frame, delta) end
end)

local function ButtonUnderMouse()
    local found
    B.ForEachButton(function(b)
        if not found and b:IsShown() and b:IsMouseOver() then found = b end
    end)
    return found
end

local function SetHover(btn)
    if J.hover == btn then return end
    if J.hover then
        local D = B.ButtonDeco(J.hover)
        if D and D.hover then D.hover:Hide() end
    end
    J.hover = btn
    GameTooltip:Hide()
    if btn then
        local D = B.ButtonDeco(btn)
        if D and D.hover then D.hover:Show() end
        local st = B.ButtonState(btn)
        if st then
            GameTooltip:SetOwner(overlay, "ANCHOR_CURSOR_RIGHT")
            if pcall(GameTooltip.SetBagItem, GameTooltip, st.bag, st.slot) then GameTooltip:Show() end
        end
    end
end

overlay:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.05 then return end
    self.t = 0
    SetHover(ButtonUnderMouse())
end)

overlay:SetScript("OnClick", function(_, mouse)
    if mouse ~= "LeftButton" then
        J.End()
        return
    end
    local btn = ButtonUnderMouse()
    local st = btn and B.ButtonState(btn)
    if not st then return end
    ToggleMark(B.GetRecord(st.bag, st.slot))
end)
overlay:SetScript("OnHide", function() SetHover(nil) end)

function J.Start()
    if J.on or not Enabled() or InCombat() then return end
    J.on = true
    overlay:Show()
    SetGlow(icons.junk, true)
    J.hintText = L["Schrott markieren: Gegenstände anklicken"]
    Hint(J.hintText)
end

function J.End()
    if not J.on then return end
    J.on = false
    overlay:Hide()
    SetGlow(icons.junk, false)
    ClearHint(J.hintText)
end

-- Gegenstand vom Cursor auf die Münze legen: markiert ihn (oder hebt die Markierung auf)
local function DropOnCoin()
    local id = CursorItemID()
    local marks = Marks()
    if not (id and marks) then return false end
    J.dropT = GetTime()
    ClearCursorSafe()
    marks[id] = (marks[id] ~= true) and true or nil
    Repaint()
    return true
end

local clearDialog = "STRAY_BAGJUNK_CLEAR"
StaticPopupDialogs[clearDialog] = {
    text = "",
    button1 = ACCEPT or "OK",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        local marks = Marks()
        if marks then wipe(marks) end
        Repaint()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function AskClearMarks()
    StaticPopupDialogs[clearDialog].text = L["Alle Schrott-Markierungen löschen? Auch die Schutz-Markierungen für graue Gegenstände gehen verloren."]
    StaticPopup_Show(clearDialog)
end

local function JunkMenu(owner)
    local Cat = B.Categories
    if not (Cat and Cat.ShowMenu) then
        AskClearMarks()
        return
    end
    Cat.ShowMenu(owner, {
        { text = L["Schrott-Markierer"], title = true },
        { text = L["Alle Markierungen löschen"], func = AskClearMarks },
    })
end

---------------------------------------------------------------------------
-- Schnellaktionen: abdunkeln, worauf Entzaubern / Schloss knacken nicht wirkt
---------------------------------------------------------------------------

local SPELL_DISENCHANT, SPELL_LOCKPICK = 13262, 1804

local function SpellKnown(id)
    if IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(v) and v then return true end
    end
    if IsSpellKnown then
        local ok, v = pcall(IsSpellKnown, id)
        if ok and not IsSecret(v) and v then return true end
    end
    return false
end

function Q.Refresh()
    Q.de = SpellKnown(SPELL_DISENCHANT)
    Q.lock = SpellKnown(SPELL_LOCKPICK) and C_TooltipInfo ~= nil and C_TooltipInfo.GetBagItem ~= nil
end

local function IsLockbox(rec)
    local id = rec.itemID
    if not id then return false end
    local c = Q.lockCache[id]
    if c ~= nil then return c end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, rec.bag, rec.slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    local surface = TooltipUtil and TooltipUtil.SurfaceArgs
    local locked = false
    for _, line in ipairs(data.lines) do
        if surface then pcall(surface, line) end
        local t = line.leftText
        if type(t) == "string" and not IsSecret(t) and LOCKED and t == LOCKED then
            locked = true
            break
        end
    end
    Q.lockCache[id] = locked
    return locked
end

local function QuickApplies(rec)
    if Q.de then
        local cl = B.C.CL
        if (rec.classID == cl.weapon or rec.classID == cl.armor) and type(rec.quality) == "number" and rec.quality >= 2 then
            return true
        end
    end
    if Q.lock and IsLockbox(rec) then return true end
    return false
end

---------------------------------------------------------------------------
-- Zeichnen an den Gegenstandsknöpfen (Einhängepunkt von bag_window.lua)
---------------------------------------------------------------------------

function B.AfterPaint(b, rec, D)
    if not ns.db then return end
    local marks = ns.db.bagJunkMarks
    local marked = rec.hasItem and rec.itemID and type(marks) == "table" and marks[rec.itemID] == true
    local coin = J.coins[b]
    if marked and D.holder then
        if not coin then
            coin = D.holder:CreateTexture(nil, "OVERLAY", nil, 5)
            coin:SetSize(12, 12)
            coin:SetPoint("TOPRIGHT", -2, -2)
            coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
            J.coins[b] = coin
        end
        coin:Show()
        if ns.db.bagJunkGrey and D.icon then D.icon:SetDesaturated(true) end
    elseif coin then
        coin:Hide()
    end
    if Q.on and rec.hasItem and D.dim and not QuickApplies(rec) then D.dim:Show() end
end

---------------------------------------------------------------------------
-- Taschenplätze: Fenster mit Rucksack + Taschen
---------------------------------------------------------------------------

local S = { slots = {}, swap = nil, BACKPACK = "Interface\\Buttons\\Button-Backpack-Up",
    EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag", SIZE = 32, GAP = 4, PAD = 6 }

local popup = CreateFrame("Frame", nil, B.frame)
popup:SetFrameLevel(B.frame:GetFrameLevel() + 25)
popup:SetPoint("TOPRIGHT", B.header.frame, "BOTTOMRIGHT", -8, -3)
popup:SetHeight(S.SIZE + S.PAD * 2)
popup.bg = Tex(popup, "BACKGROUND", { 0.078, 0.078, 0.098, 0.98 })
popup.bg:SetAllPoints()
popup.edges = Edges(popup, { 0.149, 0.149, 0.184, 1 })
popup:EnableMouse(true)
popup:Hide()

local function InvID(bag)
    if bag == 0 then return nil end
    local fn = Container.ContainerIDToInventoryID or ContainerIDToInventoryID
    if not fn then return nil end
    local ok, id = pcall(fn, bag)
    if ok and not IsSecret(id) and type(id) == "number" then return id end
    return nil
end

local function InvItemID(inv)
    if not inv or not GetInventoryItemID then return nil end
    local ok, id = pcall(GetInventoryItemID, "player", inv)
    if ok and not IsSecret(id) and type(id) == "number" then return id end
    return nil
end

local function InvLocked(inv)
    if not inv or not IsInventoryItemLocked then return false end
    local ok, v = pcall(IsInventoryItemLocked, inv)
    return ok and not IsSecret(v) and v and true or false
end

local function HasItemAt(bag, slot)
    local icon, _, _, _, link, itemID = API.SlotInfo(bag, slot)
    return (icon or link or itemID) and true or false
end

local function UsedSlots(bag)
    local used = 0
    for slot = 1, API.NumSlots(bag) do
        if HasItemAt(bag, slot) then used = used + 1 end
    end
    return used
end

local function HighlightBag(bag)
    S.hoverBag = bag
    B.ForEachButton(function(b, st)
        local D = B.ButtonDeco(b)
        if D and D.hover then D.hover:SetShown(bag ~= nil and st.bag == bag) end
    end)
end

local function Pickup(bag, slot)
    local fn = Container.PickupContainerItem or PickupContainerItem
    if not fn then return false end
    return pcall(fn, bag, slot)
end

local function CursorHas()
    if not CursorHasItem then return CursorItemID() ~= nil end
    local ok, has = pcall(CursorHasItem)
    return ok and not IsSecret(has) and has and true or false
end

local function FreeNormalSlots(except)
    local list = {}
    for bag = B.C.FIRST_BAG, B.C.LAST_BAG do
        if bag ~= except then
            local _, family = API.FreeSlots(bag)
            if family == 0 then
                for slot = 1, API.NumSlots(bag) do
                    if not HasItemAt(bag, slot) then list[#list + 1] = { bag = bag, slot = slot } end
                end
            end
        end
    end
    return list
end

-- Wo liegt der Gegenstand, der gerade am Cursor hängt? (gesperrter Platz mit dieser ID)
local function CursorSource(itemID)
    for bag = B.C.FIRST_BAG, B.C.LAST_BAG do
        for slot = 1, API.NumSlots(bag) do
            local _, _, locked, _, _, id = API.SlotInfo(bag, slot)
            if locked and id == itemID then return bag, slot end
        end
    end
end

-- Tasche tauschen mit Umpacken: erst alle Gegenstände der alten Tasche in freie Plätze, dann die neue
-- Tasche einsetzen, zuletzt die alte ablegen. Schritt für Schritt (der Server muss jeweils antworten).
local SW = { STEP = 0.2, TRIES = 15 }

function SW.Status()
    local s = S.swap
    if not s then return end
    if s.phase == "move" then
        Hint(L("Packe um … %d / %d", math.min(s.i - 1, #s.moves), #s.moves))
    else
        Hint(L["Tausche Tasche …"])
    end
end

function SW.End(message)
    if not S.swap then return end
    S.swap = nil
    if CursorHas() then ClearCursorSafe() end
    if message then ns.Print(message) end
    Hint("")
    B.RequestRefresh(0.1, "bag")
end

function SW.Next()
    if S.swap then C_Timer.After(SW.STEP, SW.Step) end
end

function SW.Step()
    local s = S.swap
    if not s then return end
    if InCombat() then
        SW.End(L["Kampf – Taschentausch abgebrochen. Bereits umgelagerte Gegenstände bleiben, wo sie sind."])
        return
    end
    SW.Status()
    if s.phase == "move" then
        local m, d = s.moves[s.i], s.dests[s.i]
        if not m then
            s.phase, s.issued, s.tries = "insert", false, 0
            return SW.Next()
        end
        if s.issued then
            local _, _, locked = API.SlotInfo(d.bag, d.slot)
            if not HasItemAt(m.bag, m.slot) and HasItemAt(d.bag, d.slot) and not locked then
                s.i, s.issued, s.tries = s.i + 1, false, 0
            else
                s.tries = s.tries + 1
                if s.tries > SW.TRIES then
                    SW.End(L["Umpacken hat nicht geklappt (Gegenstand gesperrt?). Abgebrochen."])
                    return
                end
            end
            return SW.Next()
        end
        if CursorHas() then ClearCursorSafe() end
        Pickup(m.bag, m.slot)
        if CursorHas() then Pickup(d.bag, d.slot) end
        -- lag die neue Tasche in der alten? dann merken, wohin sie umgezogen ist
        if m.bag == s.srcBag and m.slot == s.srcSlot then s.srcBag, s.srcSlot = d.bag, d.slot end
        s.issued = true
        return SW.Next()
    elseif s.phase == "insert" then
        if not s.issued then
            if UsedSlots(s.bag) > 0 then
                SW.End(L["Die alte Tasche ist noch nicht leer. Abgebrochen."])
                return
            end
            if CursorHas() then ClearCursorSafe() end
            Pickup(s.srcBag, s.srcSlot)
            if CursorItemID() ~= s.newID or not PutItemInBag then
                SW.End(L["Die neue Tasche wurde nicht gefunden. Abgebrochen."])
                return
            end
            pcall(PutItemInBag, s.inv)
            s.issued, s.tries = true, 0
            return SW.Next()
        end
        if InvItemID(s.inv) == s.newID and not InvLocked(s.inv) then
            s.phase, s.issued, s.tries = "stow", false, 0
        else
            s.tries = s.tries + 1
            if s.tries > SW.TRIES then
                SW.End(L["Einsetzen hat nicht geklappt – WoW hat die Tasche nicht angenommen."])
                return
            end
        end
        return SW.Next()
    end
    -- alte Tasche hängt am Cursor: in einen freien Platz legen
    if CursorHas() then
        local target = FreeNormalSlots(nil)[1]
        if target then
            Pickup(target.bag, target.slot)
        elseif PutItemInBackpack then
            pcall(PutItemInBackpack)
        end
    end
    SW.End(L["Tasche getauscht – die alte liegt jetzt in deinen Taschen."])
end

function SW.Start(bag, inv, newID)
    local srcBag, srcSlot = CursorSource(newID)
    ClearCursorSafe() -- neue Tasche zurück an ihren Platz
    if not srcBag then
        ns.Print(L["Zieh die neue Tasche aus deinen Taschen auf den Taschenplatz."])
        return
    end
    local moves = {}
    for slot = 1, API.NumSlots(bag) do
        if HasItemAt(bag, slot) then moves[#moves + 1] = { bag = bag, slot = slot } end
    end
    local dests = FreeNormalSlots(bag)
    if #dests < #moves then
        ns.Print(L("Es fehlen %d freie Plätze – erst Platz schaffen.", #moves - #dests))
        return
    end
    S.swap = { bag = bag, inv = inv, newID = newID, srcBag = srcBag, srcSlot = srcSlot,
        moves = moves, dests = dests, i = 1, phase = "move", issued = false, tries = 0 }
    HighlightBag(nil)
    SW.Status()
    SW.Step()
end

-- Gegenstand vom Cursor auf einen Taschenplatz (Klick mit Gegenstand oder Ablegen)
local function DropOnSlot(self)
    local id = CursorItemID()
    if not id then return end
    if InCombat() then
        ClearCursorSafe()
        ns.Print(L["Taschen tauschen geht erst nach dem Kampf."])
        return
    end
    if S.swap then
        ns.Print(L["stray tauscht gerade schon eine Tasche."])
        return
    end
    local bag = self.bag
    if bag == 0 then
        if PutItemInBackpack then pcall(PutItemInBackpack) end
        return
    end
    local inv = InvID(bag)
    if not inv or not PutItemInBag then return end
    local classID = API.ItemClass(id)
    local isBag = classID == B.C.CL.container or classID == B.C.CL.quiver
    -- leerer Platz, kein Taschen-Gegenstand, gesperrt oder alte Tasche leer: das erledigt WoW selbst
    if not InvItemID(inv) or not isBag or InvLocked(inv) or UsedSlots(bag) == 0 then
        pcall(PutItemInBag, inv)
        return
    end
    SW.Start(bag, inv, id)
end

local function SlotQualityColor(inv)
    if not (inv and GetInventoryItemQuality) then return nil end
    local ok, q = pcall(GetInventoryItemQuality, "player", inv)
    if ok and not IsSecret(q) and type(q) == "number" then return API.QualityColor(q) end
    return nil
end

local function SlotTooltip(self)
    local bag = self.bag
    local info = B.bags[bag]
    local inv = InvID(bag)
    local equipped = bag == 0 or InvItemID(inv) ~= nil
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if not equipped then
        GameTooltip:SetText(L["Leerer Taschenplatz"], 1, 1, 1)
        GameTooltip:AddLine(L["Tasche hierher ziehen oder mit der Tasche am Cursor anklicken, um sie anzulegen."], 0.8, 0.8, 0.8, true)
    else
        local r, g, b = SlotQualityColor(inv)
        GameTooltip:SetText(string.format("%s (%d/%d)", B.BagTitle(bag), info and info.used or 0, info and info.size or 0),
            r or 1, g or 1, b or 1)
        if bag ~= 0 then
            GameTooltip:AddLine(L["Ziehen: Tasche herausnehmen. Andere Tasche daraufziehen: tauschen (stray räumt die alte aus)."], 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:Show()
end

local function MakeSlot(index)
    local s = CreateFrame("Button", nil, popup)
    s:SetSize(S.SIZE, S.SIZE)
    s.bg = Tex(s, "BACKGROUND", { 0.051, 0.051, 0.064, 1 })
    s.bg:SetAllPoints()
    s.edges = Edges(s, { 0.235, 0.235, 0.286, 1 })
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.free = s:CreateFontString(nil, "OVERLAY")
    s.free:SetFont(FONT_BODY, 11, "OUTLINE")
    s.free:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = s:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)
    s:RegisterForClicks("LeftButtonUp")
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnEnter", function(self)
        HighlightBag(self.bag)
        SlotTooltip(self)
    end)
    s:SetScript("OnLeave", function()
        HighlightBag(nil)
        GameTooltip:Hide()
    end)
    s:SetScript("OnClick", DropOnSlot)
    s:SetScript("OnReceiveDrag", DropOnSlot)
    s:SetScript("OnDragStart", function(self)
        if S.swap or InCombat() or self.bag == 0 or not PickupBagFromSlot then return end
        local inv = InvID(self.bag)
        if inv and InvItemID(inv) then pcall(PickupBagFromSlot, inv) end
    end)
    S.slots[index] = s
    return s
end

function S.Update()
    local on = Enabled() and ns.db.bagIconSlots and ns.db.bagSlotsShown
    popup:SetShown(on and true or false)
    SetGlow(icons.slots, on)
    if not on then
        if S.hoverBag then HighlightBag(nil) end
        return
    end
    local ids = {}
    for i = #B.bagIDs, 1, -1 do ids[#ids + 1] = B.bagIDs[i] end -- Blizzard-Reihenfolge, Rucksack rechts
    popup:SetWidth(math.max(1, #ids * (S.SIZE + S.GAP) - S.GAP + S.PAD * 2))
    for i, bag in ipairs(ids) do
        local s = S.slots[i] or MakeSlot(i)
        s.bag = bag
        s:ClearAllPoints()
        s:SetPoint("LEFT", popup, "LEFT", S.PAD + (i - 1) * (S.SIZE + S.GAP), 0)
        local inv = InvID(bag)
        local equipped = bag == 0 or InvItemID(inv) ~= nil
        local tex
        if bag == 0 then
            tex = S.BACKPACK
        elseif equipped and GetInventoryItemTexture then
            local ok, t = pcall(GetInventoryItemTexture, "player", inv)
            if ok and not IsSecret(t) then tex = t end
        end
        s.icon:SetTexture(tex or S.EMPTY)
        s.icon:SetDesaturated(not equipped)
        s.icon:SetAlpha(equipped and 1 or 0.4)
        local info = B.bags[bag]
        s.free:SetText((equipped and info) and tostring(info.free or 0) or "")
        local r, g, b
        if equipped and bag ~= 0 then r, g, b = SlotQualityColor(inv) end
        SetEdges(s.edges, r or 0.235, g or 0.235, b or 0.286, 1)
        s:Show()
    end
    for i = #ids + 1, #S.slots do S.slots[i]:Hide() end
    if S.hoverBag then HighlightBag(S.hoverBag) end
end

---------------------------------------------------------------------------
-- Kopf-Symbole
---------------------------------------------------------------------------

local ICON_COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_SORT = "Interface\\Icons\\INV_Misc_Note_01"
local ICON_QUICK = "Interface\\Icons\\INV_Enchant_Disenchant"

icons.slots = B.AddHeaderIcon({
    key = "slots", icon = S.BACKPACK, tooltip = "Taschenplätze",
    onClick = function()
        if not ns.db then return end
        ns.db.bagSlotsShown = not ns.db.bagSlotsShown
        S.Update()
    end,
})

icons.junk = B.AddHeaderIcon({
    key = "junk", icon = ICON_COIN, tooltip = "Schrott markieren",
    onClick = function(btn, mouse)
        if mouse == "RightButton" then
            JunkMenu(btn)
        elseif CursorItemID() then
            DropOnCoin()
        elseif J.dropT and GetTime() - J.dropT < 0.3 then
            return -- Klick gehört noch zum Ablegen
        elseif J.on then
            J.End()
        elseif InCombat() then
            Hint(L["Schrott markieren geht erst nach dem Kampf."], 3)
        else
            J.Start()
        end
    end,
})
if icons.junk then
    icons.junk:SetScript("OnReceiveDrag", function() DropOnCoin() end)
    icons.junk:HookScript("OnEnter", function()
        GameTooltip:AddLine(L["Klick: Markier-Modus. Gegenstand daraufziehen: als Schrott markieren. Rechtsklick: Menü."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
end

local function SortFn()
    return Container.SortBags or SortBags
end

icons.sort = B.AddHeaderIcon({
    key = "sort", icon = ICON_SORT, tooltip = "Taschen sortieren",
    onClick = function()
        local fn = SortFn()
        if not fn then return end
        if InCombat() then
            Hint(L["Sortieren geht erst nach dem Kampf."], 3)
            return
        end
        if pcall(fn) then
            Hint(L["Sortiere …"], 2)
            C_Timer.After(1.5, function() B.RequestRefresh(0, "bag") end)
        end
    end,
})

icons.quick = B.AddHeaderIcon({
    key = "quick", icon = ICON_QUICK, tooltip = "Schnellaktionen",
    onClick = function()
        Q.on = not Q.on
        SetGlow(icons.quick, Q.on)
        B.RequestPaint()
    end,
})
if icons.quick then
    icons.quick:HookScript("OnEnter", function()
        GameTooltip:AddLine(L["Zeigt, worauf Entzaubern/Schloss knacken wirkt. Zauber selbst wirken und Gegenstand anklicken."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
end

local function QuickTexture()
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, SPELL_DISENCHANT)
        if ok and t and not IsSecret(t) then return t end
    end
    return ICON_QUICK
end

local function UpdateIcons()
    if not ns.db then return end
    local db = ns.db
    if icons.slots then icons.slots:SetShown(db.bagIconSlots and true or false) end
    if icons.junk then icons.junk:SetShown(db.bagIconJunk and true or false) end
    if icons.sort then icons.sort:SetShown((db.bagIconSort and SortFn() ~= nil) and true or false) end
    if icons.quick then
        Q.Refresh()
        local show = (db.bagIconQuick and (Q.de or Q.lock)) and true or false
        icons.quick:SetShown(show)
        if not show and Q.on then
            Q.on = false
            SetGlow(icons.quick, false)
            B.RequestPaint()
        end
        if show then icons.quick.icon:SetTexture(QuickTexture()) end
    end
    if not db.bagIconJunk then J.End() end
end

---------------------------------------------------------------------------
-- „Schrott verkaufen“ beim Händler (Fuß, links)
---------------------------------------------------------------------------

local sell = CreateFrame("Button", nil, B.footerLeft)
sell:SetSize(112, 20)
sell:SetPoint("BOTTOMLEFT", B.footerLeft, "BOTTOMLEFT", 0, 0)
sell.bg = Tex(sell, "BACKGROUND", { 0.055, 0.055, 0.071, 1 })
sell.bg:SetAllPoints()
sell.edges = Edges(sell, { 0.149, 0.149, 0.184, 1 })
sell.text = Text(sell, 11, P.text)
sell.text:SetPoint("CENTER")
sell.hl = sell:CreateTexture(nil, "HIGHLIGHT")
sell.hl:SetAllPoints()
sell.hl:SetColorTexture(1, 1, 1, 0.08)
sell:Hide()

local function SellInfo()
    local n, total = 0, 0
    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    B.ForEachRecord(function(rec)
        if rec.hasItem and not rec.noValue and not rec.questNeeded and B.IsJunk(rec) then
            local price
            if GetInfo and rec.link then
                local ok, _, _, _, _, _, _, _, _, _, _, p = pcall(GetInfo, rec.link)
                if ok and not IsSecret(p) then price = p end
            end
            if type(price) == "number" and price > 0 then
                n = n + 1
                total = total + price * (rec.count or 1)
            end
        end
    end)
    return n, total
end

local function UpdateSell()
    if not Enabled() or not ns.db.bagIconJunk or not ns.MerchantOpen or not ns.MerchantOpen() then
        sell:Hide()
        return
    end
    local n, total = SellInfo()
    sell.n, sell.total = n, total
    LoadPalette()
    sell.text:SetText(L["Schrott verkaufen"])
    sell.text:SetTextColor(P.text[1], P.text[2], P.text[3])
    sell:SetWidth(math.max(112, math.floor((sell.text:GetStringWidth() or 90) + 20)))
    sell:SetShown(n > 0)
end

sell:SetScript("OnClick", function()
    if not ns.SellJunk then return end
    if ns.SellJunk(function(rec) return B.IsJunk(rec) end) then Hint(L["Verkaufe Schrott …"], 3) end
end)
sell:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Schrott verkaufen"], 1, 1, 1)
    GameTooltip:AddLine(L("%d Gegenstände für %s", self.n or 0, ns.FormatMoney(self.total or 0)), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
sell:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Verkabelung
---------------------------------------------------------------------------

B.OnRefresh(function()
    UpdateIcons()
    SB.Update()
    S.Update()
    UpdateSell()
end)

if B.Categories and B.Categories.OnChanged then
    B.Categories.OnChanged(function() SB.Update() end)
end

B.frame:HookScript("OnHide", function()
    J.End()
    GameTooltip:Hide()
end)

ns.On("PLAYER_REGEN_DISABLED", function() J.End() end)
ns.On("SPELLS_CHANGED", function()
    if Enabled() then UpdateIcons() end
end)
ns.On("MERCHANT_SHOW", function() C_Timer.After(0.2, UpdateSell) end)
ns.On("MERCHANT_CLOSED", function() UpdateSell() end)
ns.On("PLAYER_LOGIN", function()
    Q.Refresh()
    UpdateIcons()
end)

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
                UpdateIcons()
                SB.Update()
                S.Update()
                UpdateSell()
                B.RequestLayout()
            end,
        })
    end
    Switch("bagSidebar", L["Seitenleiste zeigen"],
        L["Zeigt in der Ansicht „Kategorien“ links eine Leiste mit allen Kategorien. Ein Klick zeigt nur diese Kategorie, ein zweiter Klick oder „Alle“ wieder alles."],
        { "seitenleiste", "kategorien", "filter", "sidebar", "categories" })
    Switch("bagIconSlots", L["Symbol „Taschen“ zeigen"],
        L["Zeigt im Kopf des Taschenfensters ein Symbol, das ein kleines Fenster mit Rucksack und Taschenplätzen öffnet: freie Plätze je Tasche, Taschen einsetzen und tauschen."],
        { "taschen", "taschenplätze", "bag slots", "bags", "tauschen" })
    Switch("bagIconJunk", L["Symbol „Schrott“ zeigen"],
        L["Zeigt im Kopf das Münz-Symbol zum Markieren von Schrott. Beim Händler erscheint unten links „Schrott verkaufen“. Markierter Schrott wird auch automatisch mitverkauft, wenn „Automatisch verkaufen“ an ist."],
        { "schrott", "markieren", "verkaufen", "junk", "sell", "mark" })
    Switch("bagIconSort", L["Symbol „Sortieren“ zeigen"],
        L["Zeigt im Kopf ein Symbol, das deine Taschen sortiert (nicht im Kampf)."],
        { "sortieren", "aufräumen", "sort", "clean up" })
    Switch("bagIconQuick", L["Symbol „Schnellaktionen“ zeigen"],
        L["Zeigt im Kopf ein Symbol, das alle Gegenstände abdunkelt, auf die Entzaubern oder Schloss knacken nicht wirken. Nur wenn dein Charakter einen dieser Zauber kennt. Es wird nichts automatisch gewirkt."],
        { "schnellaktionen", "entzaubern", "schloss", "disenchant", "lockpicking", "quick" })
    Switch("bagJunkGrey", L["Markierten Schrott ausgrauen"],
        L["Zeigt als Schrott markierte Gegenstände zusätzlich entsättigt (grau) an. Das Münz-Zeichen erscheint immer."],
        { "ausgrauen", "entsättigen", "grau", "desaturate", "grey", "junk" })
end
