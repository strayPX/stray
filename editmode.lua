-- stray – Bearbeitungsmodus
-- Blendet alle eingeschalteten stray-Anzeigen mit Beispielinhalt ein und macht sie ohne Shift
-- verschiebbar: blaue Fläche mit Namen darüber, ziehen zum Verschieben, Rechtsklick setzt eine
-- Anzeige zurück. Oben mittig eine kompakte, verschiebbare Werkzeugleiste mit Raster, Einrasten,
-- Zurücksetzen (Symbol) und „Fertig“. Esc beendet den Modus (Leiste steht in UISpecialFrames).
-- Nur außerhalb des Kampfes (die Gruppenrahmen hängen an Blizzards geschützten Rahmen).
--
-- Auswahl (seit 0.22.0-alpha): Linksklick ohne Ziehen wählt eine Anzeige aus (heller Rand). Daneben
-- erscheint ein kleines Fenster mit X/Y (Pixel ab Bildschirmmitte), Größe in % (SetScale, gespeichert
-- in ns.db.scales), Breite/Höhe (nur wenn das Modul sie über opts von ns.RegisterMovable meldet),
-- mittig ausrichten, Zurücksetzen und Schließen. Pfeiltasten verschieben die gewählte Anzeige um 1 px,
-- mit Shift um 10 px; andere Tasten gehen ans Spiel weiter. Esc hebt zuerst die Auswahl auf (das
-- Fenster fängt nur diese Taste ab), erst das nächste Esc erreicht UISpecialFrames und beendet den Modus.
-- Klick in die Spielwelt hebt die Auswahl ebenfalls auf.
--
-- Einrasten: Beim Loslassen rastet eine Anzeige an Kanten und Mitten anderer sichtbarer
-- stray-Anzeigen und an der Bildschirmmitte ein (Abstand unter SNAP). Gilt vor dem Raster.
-- Pfeiltasten und Eingaben im Fenster rasten nicht ein.
-- Haken für Module: frame.strayOnDragStop(frame) wird nach dem Loslassen und Speichern aufgerufen
-- (auch nach Pfeiltasten, Eingaben und Größenänderung im Fenster).

local _, ns = ...

ns.defaults.editGrid = true     -- Raster im Bearbeitungsmodus
ns.defaults.editSnap = true     -- Einrasten an anderen Anzeigen und der Bildschirmmitte
ns.defaults.editBarPoint = false -- Position der Werkzeugleiste { Punkt, relPunkt, x, y }

local GRID = 8  -- Raster in Pixeln (Einrasten beim Loslassen)
local SNAP = 8  -- Fangabstand fürs Einrasten in Pixeln
local SCALE_MIN, SCALE_MAX = 50, 200 -- Größe in Prozent

local MEDIA = "Interface\\AddOns\\stray\\media\\"
local FONT_BODY = "Fonts\\ARIALN.TTF"

local C = {
    bg       = { 0.051, 0.067, 0.090, 0.95 },
    border   = { 0.169, 0.290, 0.451, 1 },
    accent   = { 0.353, 0.659, 1.000, 1 },
    text     = { 0.890, 0.914, 0.953, 1 },
    textSide = { 0.682, 0.733, 0.816, 1 },
    textDim  = { 0.435, 0.525, 0.651, 1 },
}
local ACCENT = C.accent

local HINT = "Ziehen verschiebt · Linksklick wählt eine Anzeige (Fenster mit Position und Größe, Pfeiltasten) · Rechtsklick setzt eine Anzeige zurück · ausgeschaltete Anzeigen erscheinen nicht · Esc hebt die Auswahl auf, sonst beendet es den Modus"

local overlays = {}
local bar, grid, panel
local ticker
local selected -- gewählter Eintrag aus ns.movables
local ExitEditMode, Deselect, RefreshPanel

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function Round(v)
    return math.floor(v / GRID + 0.5) * GRID
end

local function RoundInt(v)
    return math.floor(v + 0.5)
end

local function GridOn() return ns.db and ns.db.editGrid ~= false end
local function SnapOn() return ns.db and ns.db.editSnap ~= false end

local function Plain(v)
    return type(v) == "number" and not ns.IsSecret(v)
end

-- Rechteck eines Frames in UIParent-Einheiten: links, rechts, oben, unten
local function Rect(frame)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (Plain(l) and Plain(r) and Plain(t) and Plain(b)) then return end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, r * s, t * s, b * s
end

-- Mitte eines Frames in UIParent-Einheiten, gemessen ab der Bildschirmmitte
local function Center(frame)
    local l, r, t, b = Rect(frame)
    if not l then return end
    return (l + r) / 2 - UIParent:GetWidth() / 2, (t + b) / 2 - UIParent:GetHeight() / 2
end

-- Kleinster Abstand von eigenen Werten zu Zielwerten, nur wenn unter SNAP
local function Closest(own, targets)
    local best
    for _, o in ipairs(own) do
        for _, t in ipairs(targets) do
            local d = t - o
            if math.abs(d) < SNAP and (not best or math.abs(d) < math.abs(best)) then best = d end
        end
    end
    return best
end

-- Hängt other mit einem Ankerpunkt an frame (z. B. angedocktes DMG-Meter-Fenster 2)? Dann kein Einrast-Ziel.
local function AnchoredTo(other, frame)
    local n = other.GetNumPoints and other:GetNumPoints() or 0
    for i = 1, n do
        local _, rel = other:GetPoint(i)
        if rel == frame then return true end
    end
    return false
end

-- Verschiebung (dx, dy) in UIParent-Einheiten, die den Frame einrasten lässt; nil je Achse = nichts
local function SnapOffset(frame)
    local l, r, t, b = Rect(frame)
    if not l then return end
    local xs = { UIParent:GetWidth() / 2 }
    local ys = { UIParent:GetHeight() / 2 }
    for _, entry in ipairs(ns.movables) do
        local other = entry.frame
        if other and other ~= frame and other:IsShown() and not AnchoredTo(other, frame) then
            local ol, or_, ot, ob = Rect(other)
            if ol then
                xs[#xs + 1] = ol; xs[#xs + 1] = or_; xs[#xs + 1] = (ol + or_) / 2
                ys[#ys + 1] = ot; ys[#ys + 1] = ob; ys[#ys + 1] = (ot + ob) / 2
            end
        end
    end
    local dx = Closest({ l, r, (l + r) / 2 }, xs)
    local dy = Closest({ t, b, (t + b) / 2 }, ys)
    return dx, dy
end

-- Nach dem Loslassen: einrasten (zuerst), sonst Raster, dann speichern
local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    if not point then return end
    local dx, dy
    if SnapOn() then dx, dy = SnapOffset(frame) end
    -- SetPoint-Versätze gelten im Maßstab des Frames
    local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    if dx then x = x + dx * k elseif GridOn() then x = Round(x) end
    if dy then y = y + dy * k elseif GridOn() then y = Round(y) end
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relPoint, x, y)
    ns.db.positions[frame.strayKey] = { point, relPoint, x, y }
end

-- Haken für Module (z. B. DMG-Meter-Andocken): nach dem Loslassen aufrufen
local function AfterDrop(frame)
    if type(frame.strayOnDragStop) == "function" then
        local ok, err = pcall(frame.strayOnDragStop, frame)
        if not ok then geterrorhandler()(err) end
    end
end

-- Einen einzigen Ankerpunkt an UIParent herstellen (angedockte oder an andere Rahmen gehängte
-- Anzeigen vorher auf ihre aktuelle Bildschirmstelle setzen). Gibt Punkt, relPunkt, x, y zurück.
local function Normalize(frame)
    local n = frame:GetNumPoints() or 0
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    if point and n == 1 and (rel == nil or rel == UIParent) and Plain(x) and Plain(y) then
        return point, relPoint, x, y
    end
    local l, b, w = frame:GetLeft(), frame:GetBottom(), frame:GetWidth()
    if not (Plain(l) and Plain(b)) then return end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    if n > 1 and Plain(w) then frame:SetWidth(w) end -- Breite kam aus zwei Ankern
    return "BOTTOMLEFT", "BOTTOMLEFT", l, b
end

-- Um (dx, dy) in UIParent-Einheiten verschieben und speichern (ohne Raster und Einrasten)
local function MoveBy(frame, dx, dy)
    if InCombatLockdown() or not frame.strayKey then return end
    local point, relPoint, x, y = Normalize(frame)
    if not point then return end
    local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    x, y = x + dx * k, y + dy * k
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relPoint, x, y)
    ns.db.positions[frame.strayKey] = { point, relPoint, x, y }
    AfterDrop(frame)
end

-- Mitte auf (cx, cy) ab Bildschirmmitte setzen; nil je Achse = unverändert
local function MoveTo(frame, cx, cy)
    local x, y = Center(frame)
    if not x then return end
    MoveBy(frame, cx and (cx - x) or 0, cy and (cy - y) or 0)
end

-- Größe in Prozent setzen; der Ankerpunkt bleibt an seiner Stelle am Bildschirm
local function SetScalePercent(frame, pct)
    if InCombatLockdown() or not frame.strayKey then return end
    pct = math.max(SCALE_MIN, math.min(SCALE_MAX, RoundInt(pct)))
    local new = pct / 100
    local old = frame:GetScale() or 1
    if math.abs(old - new) < 0.001 then return end
    local point, relPoint, x, y = Normalize(frame)
    if type(ns.db.scales) ~= "table" then ns.db.scales = {} end
    ns.db.scales[frame.strayKey] = (pct ~= 100) and new or nil
    ns.ApplyScale(frame)
    if not point then return end
    x, y = x * old / new, y * old / new
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relPoint, x, y)
    ns.db.positions[frame.strayKey] = { point, relPoint, x, y }
    AfterDrop(frame)
end

-- Option im Register von stray.lua suchen (für Breite/Höhe aus opts.widthKey/heightKey)
local function FindOption(key)
    for _, column in ipairs(ns.columns or {}) do
        for _, section in ipairs(column) do
            for _, opt in ipairs(section.options or {}) do
                if opt.key == key then return opt end
            end
        end
    end
end

-- Breite oder Höhe einer Anzeige: { min, max, step, get, set, enabled } oder nil
local function SizeSpec(entry, which)
    local opts = entry.opts
    local key = opts and opts[which .. "Key"]
    if not key then return end
    local opt = FindOption(key)
    if opt and opt.type == "slider" then
        return {
            min = tonumber(opt.min) or 1, max = tonumber(opt.max) or 9999, step = tonumber(opt.step) or 1,
            get = opt.get, set = opt.set, enabled = opt.isEnabled,
            default = ns.defaults[key],
        }
    end
    return {
        min = tonumber(opts[which .. "Min"]) or 1, max = tonumber(opts[which .. "Max"]) or 9999, step = 1,
        get = function() return ns.db[key] end,
        set = function(v)
            ns.db[key] = v
            if type(opts.onSize) == "function" then opts.onSize(which, v) end
        end,
        default = ns.defaults[key],
    }
end

local function SizeValue(spec)
    local ok, v = pcall(spec.get)
    return ok and tonumber(v) or nil
end

local function SetSize(spec, v)
    if InCombatLockdown() then return end
    v = math.max(spec.min, math.min(spec.max, v))
    v = spec.min + RoundInt((v - spec.min) / spec.step) * spec.step
    local ok, err = pcall(spec.set, v)
    if not ok then geterrorhandler()(err) end
end

-- Eine Anzeige ganz zurücksetzen: Position, Größe in % und (falls gemeldet) Breite/Höhe
local function ResetEntry(entry)
    local frame = entry.frame
    if InCombatLockdown() or not frame or not frame.strayKey then return end
    for _, which in ipairs({ "width", "height" }) do
        local spec = SizeSpec(entry, which)
        if spec and spec.default ~= nil and SizeValue(spec) ~= tonumber(spec.default) then
            SetSize(spec, tonumber(spec.default) or spec.min)
        end
    end
    if type(ns.db.scales) == "table" then ns.db.scales[frame.strayKey] = nil end
    ns.db.positions[frame.strayKey] = nil
    ns.RestorePosition(frame) -- wendet auch die Größe (wieder 1) an
end

local function Text(parent, size, c, font, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or STANDARD_TEXT_FONT, size, flags or "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end

local function Tex(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

-- 1-px-Rand; gibt die vier Linien zurück, damit sich die Farbe später ändern lässt
local function Border(frame, c)
    local top, bottom, left, right = Tex(frame, "BORDER", c), Tex(frame, "BORDER", c), Tex(frame, "BORDER", c), Tex(frame, "BORDER", c)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
    return { top, bottom, left, right }
end

local function Recolor(list, c)
    for _, t in ipairs(list) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

local function StringWidth(fs)
    if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() end
    return fs:GetStringWidth()
end

---------------------------------------------------------------------------
-- Blaue Flächen über den Anzeigen
---------------------------------------------------------------------------

-- Gewählte Fläche heller und mit weißem Rand
local function StyleOverlay(o, isSelected)
    if isSelected then
        o.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.34)
        Recolor(o.edges, { 1, 1, 1, 1 })
    else
        o.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
        Recolor(o.edges, { ACCENT[1], ACCENT[2], ACCENT[3], 0.9 })
    end
end

local function RestyleOverlays()
    for i, o in pairs(overlays) do
        StyleOverlay(o, selected ~= nil and ns.movables[i] == selected)
    end
end

local function Select(entry)
    if InCombatLockdown() then return end
    selected = entry
    RestyleOverlays()
    RefreshPanel(true)
end

local function CreateOverlay(entry)
    local o = CreateFrame("Button", nil, UIParent)
    o:SetFrameStrata("HIGH") -- unter den Popups (DIALOG), damit deren Knöpfe klickbar bleiben
    o:SetFrameLevel(50)
    o:SetMovable(false)
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    o:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    o.bg = o:CreateTexture(nil, "BACKGROUND")
    o.bg:SetAllPoints()
    o.edges = Border(o, { ACCENT[1], ACCENT[2], ACCENT[3], 0.9 })
    StyleOverlay(o, false)

    o.label = Text(o, 12, { 1, 1, 1 }, nil, "OUTLINE")
    o.label:SetPoint("CENTER")
    o.label:SetText(entry.label)

    -- Ziehen von Klicken unterscheiden: OnClick nach einem Ziehen wählt nicht aus
    o:SetScript("OnMouseDown", function() o.dragged = false end)
    o:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        o.dragged = true
        GameTooltip:Hide()
        entry.frame:StartMoving()
        o.moving = true
    end)
    o:SetScript("OnDragStop", function()
        if not o.moving then return end
        o.moving = false
        entry.frame:StopMovingOrSizing()
        SavePosition(entry.frame)
        AfterDrop(entry.frame)
        if selected == entry then RefreshPanel(true) end
    end)
    o:SetScript("OnClick", function(_, button)
        if InCombatLockdown() then return end
        if button == "RightButton" then
            ResetEntry(entry)
            if selected == entry then RefreshPanel(true) end
        elseif not o.dragged then
            Select(entry)
        end
        o.dragged = false
    end)
    o:SetScript("OnEnter", function(self)
        if o.moving then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(entry.label, 1, 1, 1)
        GameTooltip:AddLine("Ziehen: verschieben", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine("Linksklick: auswählen (Position, Größe, Pfeiltasten)", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine("Rechtsklick: auf Standard zurücksetzen", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:Show()
    end)
    o:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return o
end

local function UpdateOverlays()
    for i, entry in ipairs(ns.movables) do
        local frame = entry.frame
        local o = overlays[i]
        if ns.editMode and frame and frame:IsShown() then
            if not o then
                o = CreateOverlay(entry)
                overlays[i] = o
                StyleOverlay(o, entry == selected)
            end
            frame:SetMovable(true)
            o:ClearAllPoints()
            o:SetAllPoints(frame)
            o:Show()
        else
            if o then o:Hide() end
            -- Gewählte Anzeige verschwunden (z. B. ausgeschaltet): Auswahl aufheben
            if entry == selected then Deselect() end
        end
    end
    if selected then RefreshPanel(false) end
end

---------------------------------------------------------------------------
-- Raster
---------------------------------------------------------------------------

local function CreateGrid()
    grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local step = GRID * 4
    for x = 0, w, step do
        local t = grid:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, (x % (step * 4) == 0) and 0.10 or 0.04)
        t:SetPoint("TOPLEFT", x, 0); t:SetPoint("BOTTOMLEFT", x, 0); t:SetWidth(1)
    end
    for y = 0, h, step do
        local t = grid:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, (y % (step * 4) == 0) and 0.10 or 0.04)
        t:SetPoint("TOPLEFT", 0, -y); t:SetPoint("TOPRIGHT", 0, -y); t:SetHeight(1)
    end
    local cx = grid:CreateTexture(nil, "BACKGROUND")
    cx:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
    cx:SetPoint("TOP"); cx:SetPoint("BOTTOM"); cx:SetWidth(1)
    local cy = grid:CreateTexture(nil, "BACKGROUND")
    cy:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
    cy:SetPoint("LEFT"); cy:SetPoint("RIGHT"); cy:SetHeight(1)
    grid:Hide()
end

---------------------------------------------------------------------------
-- Symbole aus einfachen Flächen (keine Atlas-Abhängigkeit)
---------------------------------------------------------------------------

-- Raster: Kästchen mit je zwei Linien quer und längs
local function GridIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(12, 12)
    f.parts = Border(f, C.textSide)
    for _, pos in ipairs({ 4, 8 }) do
        local v = Tex(f, "ARTWORK", C.textSide)
        v:SetPoint("TOPLEFT", pos, 0); v:SetPoint("BOTTOMLEFT", pos, 0); v:SetWidth(1)
        local hz = Tex(f, "ARTWORK", C.textSide)
        hz:SetPoint("TOPLEFT", 0, -pos); hz:SetPoint("TOPRIGHT", 0, -pos); hz:SetHeight(1)
        f.parts[#f.parts + 1] = v
        f.parts[#f.parts + 1] = hz
    end
    return f
end

-- Einrasten: senkrechte Führungslinie, links und rechts je ein Block daran
local function SnapIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(12, 12)
    local line = Tex(f, "ARTWORK", C.textSide)
    line:SetPoint("TOP"); line:SetPoint("BOTTOM"); line:SetWidth(1)
    local a = Tex(f, "ARTWORK", C.textSide)
    a:SetSize(5, 4); a:SetPoint("TOPRIGHT", line, "TOPLEFT", 0, -1)
    local b = Tex(f, "ARTWORK", C.textSide)
    b:SetSize(5, 4); b:SetPoint("BOTTOMLEFT", line, "BOTTOMRIGHT", 0, 1)
    f.parts = { line, a, b }
    return f
end

---------------------------------------------------------------------------
-- Knöpfe der Leiste
---------------------------------------------------------------------------

local BTN_H = 22

local function ShowTip(owner, title, line)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(title, 1, 1, 1)
    if line then GameTooltip:AddLine(line, C.textSide[1], C.textSide[2], C.textSide[3], true) end
    GameTooltip:Show()
end

local function BaseButton(width, parent)
    local b = CreateFrame("Button", nil, parent or bar)
    b:SetSize(width, BTN_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.03)
    b.edges = Border(b, C.border)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.07)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Schalter mit Symbol und Text; isOn() liefert den Zustand, toggle() schaltet um
local function ToggleButton(label, makeIcon, isOn, toggle, tipTitle, tipLine)
    local b = BaseButton(10)
    b.icon = makeIcon(b)
    b.icon:SetPoint("LEFT", 8, 0)
    b.text = Text(b, 12, C.textSide, FONT_BODY)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
    b.text:SetText(label)
    local w = StringWidth(b.text)
    if not w or w < 1 then w = #label * 6 end -- Schrift noch nicht vermessen: grob schätzen
    b:SetWidth(math.floor(8 + 12 + 5 + w + 9 + 0.5))
    function b:Refresh()
        local on = isOn()
        if on then
            self.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
            Recolor(self.edges, ACCENT)
            Recolor(self.icon.parts, { 1, 1, 1 })
            self.text:SetTextColor(1, 1, 1)
        else
            self.bg:SetColorTexture(1, 1, 1, 0.03)
            Recolor(self.edges, C.border)
            Recolor(self.icon.parts, C.textDim)
            self.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end
    end
    b:SetScript("OnClick", function(self)
        toggle()
        self:Refresh()
        ShowTip(self, tipTitle .. (isOn() and ": an" or ": aus"), tipLine)
    end)
    b:SetScript("OnEnter", function(self)
        ShowTip(self, tipTitle .. (isOn() and ": an" or ": aus"), tipLine)
    end)
    b:Refresh()
    return b
end

-- Knopf mit Text (für das Fenster je Anzeige)
local function TextButton(parent, label, width, onClick, tipTitle, tipLine)
    local b = BaseButton(width, parent)
    b.text = Text(b, 12, C.textSide, FONT_BODY)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        if tipTitle then ShowTip(self, tipTitle, tipLine) end
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(C.textSide[1], C.textSide[2], C.textSide[3])
        GameTooltip:Hide()
    end)
    return b
end

StaticPopupDialogs["STRAY_EDIT_RESET"] = {
    text = "stray: Alle Anzeigen auf ihre Standardposition und -größe zurücksetzen?",
    button1 = "Zurücksetzen",
    button2 = "Abbrechen",
    OnAccept = function()
        if InCombatLockdown() then return end
        for _, entry in ipairs(ns.movables) do
            if entry.frame and entry.frame.strayKey then ResetEntry(entry) end
        end
        if selected then RefreshPanel(true) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Fenster je Anzeige (Auswahl)
---------------------------------------------------------------------------

local PANEL_W = 214
local PAD = 10
local LABEL_W = 46
local ROW_H = 20
local ROW_GAP = 6

-- Eingabefeld für Zahlen: Enter übernimmt, Esc verwirft, Mausrad ±1 (mit Shift ±10).
-- getValue() liefert den angezeigten Wert, commit(v) übernimmt einen neuen.
local function NumberField(parent, width, getValue, commit, tipTitle, tipLine)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, ROW_H)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT_BODY, 12, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(3, 3, 0, 0)
    eb:SetMaxLetters(7)
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    eb.edges = Border(eb, C.border)

    function eb:Refresh()
        if self:HasFocus() then return end
        local v = getValue()
        self:SetText(v and tostring(RoundInt(v)) or "–")
    end

    local function Commit(v)
        if InCombatLockdown() or not v then return end
        local ok, err = pcall(commit, v)
        if not ok then geterrorhandler()(err) end
    end

    eb:SetScript("OnEnterPressed", function(self)
        local v = tonumber((string.gsub(self:GetText() or "", ",", ".")))
        self:ClearFocus()
        Commit(v)
        RefreshPanel(true)
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:Refresh()
    end)
    eb:SetScript("OnEditFocusGained", function(self)
        Recolor(self.edges, ACCENT)
        self:HighlightText()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        Recolor(self.edges, C.border)
        self:HighlightText(0, 0)
        self:Refresh()
    end)
    eb:EnableMouseWheel(true)
    eb:SetScript("OnMouseWheel", function(self, delta)
        local v = getValue()
        if not v then return end
        Commit(RoundInt(v) + delta * (IsShiftKeyDown() and 10 or 1))
        RefreshPanel(true)
        if self:HasFocus() then self:SetText(tostring(RoundInt(getValue() or v))) end
    end)
    eb:SetScript("OnEnter", function(self) if tipTitle then ShowTip(self, tipTitle, tipLine) end end)
    eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    eb:Refresh()
    return eb
end

-- Zeile: Beschriftung links, danach Felder; gibt den Zeilenrahmen zurück
local function Row(label)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(PANEL_W - 2 * PAD, ROW_H)
    row.label = Text(row, 12, C.textSide, FONT_BODY)
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetText(label)
    return row
end

local function SmallText(parent, s)
    local fs = Text(parent, 11, C.textDim, FONT_BODY)
    fs:SetText(s)
    return fs
end

-- Fenster neben die gewählte Anzeige setzen; ohne Platz rückt es an den Bildschirmrand
local function PlacePanel()
    if not selected then return end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local pw, ph = panel:GetWidth(), panel:GetHeight()
    local l, r, t = Rect(selected.frame)
    if not l then
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    local x = r + 8
    if x + pw > W - 4 then x = l - 8 - pw end
    if x < 4 then x = W - pw - 4 end
    local y = math.min(t, H - 4)
    if y - ph < 4 then y = ph + 4 end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", RoundInt(x), RoundInt(y))
end

local function CreatePanel()
    panel = CreateFrame("Frame", "strayEditPanel", UIParent)
    panel:SetWidth(PANEL_W)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    Border(panel, C.border)
    -- Akzentlinie oben (wie die gewählte Fläche: diese Anzeige ist gemeint)
    local line = Tex(panel, "ARTWORK", ACCENT)
    line:SetPoint("TOPLEFT", 1, -1); line:SetPoint("TOPRIGHT", -1, -1); line:SetHeight(1)

    -- Kopf: Name der Anzeige, rechts Schließen-Kreuz
    panel.title = Text(panel, 13, C.text, FONT_BODY)
    panel.title:SetPoint("TOPLEFT", PAD, -PAD)
    panel.title:SetPoint("RIGHT", panel, "RIGHT", -PAD - 18, 0)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -PAD + 3, -PAD + 2)
    local cx = Text(close, 14, C.textSide, FONT_BODY)
    cx:SetPoint("CENTER", 0, 1)
    cx:SetText("×")
    close:SetScript("OnClick", function() Deselect() end)
    close:SetScript("OnEnter", function(self)
        cx:SetTextColor(1, 1, 1)
        ShowTip(self, "Schließen", "Hebt die Auswahl auf (auch mit Esc).")
    end)
    close:SetScript("OnLeave", function()
        cx:SetTextColor(C.textSide[1], C.textSide[2], C.textSide[3])
        GameTooltip:Hide()
    end)

    local function Frame() return selected and selected.frame end

    -- Position ab Bildschirmmitte
    panel.posRow = Row("Position")
    local function GetX() local f = Frame(); if f then return (Center(f)) end end
    local function GetY() local f = Frame(); if not f then return end local _, y = Center(f); return y end
    local xl = SmallText(panel.posRow, "X")
    xl:SetPoint("LEFT", LABEL_W + 4, 0)
    panel.xBox = NumberField(panel.posRow, 50, GetX, function(v)
        local f = Frame(); if f then MoveTo(f, v, nil) end
    end, "X", "Waagerechter Abstand der Mitte zur Bildschirmmitte in Pixeln (negativ = links). Enter übernimmt, Mausrad ±1, mit Shift ±10.")
    panel.xBox:SetPoint("LEFT", xl, "RIGHT", 5, 0)
    local yl = SmallText(panel.posRow, "Y")
    yl:SetPoint("LEFT", panel.xBox, "RIGHT", 9, 0)
    panel.yBox = NumberField(panel.posRow, 50, GetY, function(v)
        local f = Frame(); if f then MoveTo(f, nil, v) end
    end, "Y", "Senkrechter Abstand der Mitte zur Bildschirmmitte in Pixeln (negativ = unten). Enter übernimmt, Mausrad ±1, mit Shift ±10.")
    panel.yBox:SetPoint("LEFT", yl, "RIGHT", 5, 0)

    -- Größe in Prozent
    panel.scaleRow = Row("Größe")
    panel.scaleBox = NumberField(panel.scaleRow, 50, function()
        local f = Frame(); if f then return (f:GetScale() or 1) * 100 end
    end, function(v)
        local f = Frame(); if f then SetScalePercent(f, v) end
    end, "Größe", "Größe der ganzen Anzeige in Prozent (" .. SCALE_MIN .. "–" .. SCALE_MAX .. "). Enter übernimmt, Mausrad ±1, mit Shift ±10.")
    panel.scaleBox:SetPoint("LEFT", LABEL_W + 4 + 12, 0)
    local pctl = SmallText(panel.scaleRow, "%  (" .. SCALE_MIN .. "–" .. SCALE_MAX .. ")")
    pctl:SetPoint("LEFT", panel.scaleBox, "RIGHT", 5, 0)

    -- Breite und Höhe (nur, wenn das Modul sie meldet)
    panel.sizeRows = {}
    for _, which in ipairs({ "width", "height" }) do
        local row = Row(which == "width" and "Breite" or "Höhe")
        local name = which == "width" and "Breite" or "Höhe"
        row.box = NumberField(row, 50, function()
            local spec = selected and SizeSpec(selected, which)
            return spec and SizeValue(spec)
        end, function(v)
            local spec = selected and SizeSpec(selected, which)
            if spec and (not spec.enabled or spec.enabled()) then SetSize(spec, v) end
        end, name, name .. " der Anzeige in Pixeln, wie der Regler im stray-Fenster. Enter übernimmt, Mausrad ±1, mit Shift ±10.")
        row.box:SetPoint("LEFT", LABEL_W + 4 + 12, 0)
        row.range = SmallText(row, "")
        row.range:SetPoint("LEFT", row.box, "RIGHT", 5, 0)
        panel.sizeRows[which] = row
    end

    -- Knöpfe: mittig ausrichten, Zurücksetzen, Schließen
    local half = math.floor((PANEL_W - 2 * PAD - 6) / 2)
    panel.btnRow1 = CreateFrame("Frame", nil, panel)
    panel.btnRow1:SetSize(PANEL_W - 2 * PAD, BTN_H)
    local centerH = TextButton(panel.btnRow1, "Mitte waagerecht", half, function()
        local f = Frame(); if f then MoveTo(f, 0, nil); RefreshPanel(true) end
    end, "Waagerecht mittig", "Setzt die Anzeige waagerecht auf die Bildschirmmitte (X = 0).")
    centerH:SetPoint("LEFT")
    local centerV = TextButton(panel.btnRow1, "Mitte senkrecht", half, function()
        local f = Frame(); if f then MoveTo(f, nil, 0); RefreshPanel(true) end
    end, "Senkrecht mittig", "Setzt die Anzeige senkrecht auf die Bildschirmmitte (Y = 0).")
    centerV:SetPoint("RIGHT")

    panel.btnRow2 = CreateFrame("Frame", nil, panel)
    panel.btnRow2:SetSize(PANEL_W - 2 * PAD, BTN_H)
    local reset = TextButton(panel.btnRow2, "Zurücksetzen", half, function()
        if selected then ResetEntry(selected); RefreshPanel(true) end
    end, "Zurücksetzen", "Setzt Position und Größe dieser Anzeige auf den Standard (auch Breite/Höhe, wo vorhanden).")
    reset:SetPoint("LEFT")
    local closeBtn = TextButton(panel.btnRow2, "Schließen", half, function() Deselect() end,
        "Schließen", "Hebt die Auswahl auf (auch mit Esc).")
    closeBtn:SetPoint("RIGHT")

    panel.hint = Text(panel, 11, C.textDim, FONT_BODY)
    panel.hint:SetWidth(PANEL_W - 2 * PAD)
    panel.hint:SetJustifyH("LEFT")
    panel.hint:SetText("Pfeiltasten: 1 px · mit Shift: 10 px\nEsc hebt die Auswahl auf")

    -- Tastatur: nur Pfeiltasten und Esc abfangen, alles andere geht ans Spiel weiter.
    -- EnableKeyboard/SetPropagateKeyboardInput sind im Kampf gesperrt; der Modus endet dort ohnehin.
    panel:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local step = IsShiftKeyDown() and 10 or 1
        local dx, dy = 0, 0
        if key == "UP" then dy = step
        elseif key == "DOWN" then dy = -step
        elseif key == "LEFT" then dx = -step
        elseif key == "RIGHT" then dx = step
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            Deselect()
            return
        else
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        if selected then
            MoveBy(selected.frame, dx, dy)
            RefreshPanel(true)
        end
    end)

    -- Klick in die Spielwelt hebt die Auswahl auf (Klicks auf andere Fenster nicht)
    panel:SetScript("OnEvent", function(_, event)
        if event ~= "GLOBAL_MOUSE_DOWN" or not selected then return end
        local focus
        if GetMouseFoci then
            local foci = GetMouseFoci()
            focus = foci and foci[1]
        elseif GetMouseFocus then
            focus = GetMouseFocus()
        end
        if focus == nil or focus == WorldFrame then Deselect() end
    end)

    panel:Hide()
end

-- Zeilen je nach Anzeige ein-/ausblenden und untereinander setzen
local function LayoutPanel()
    local entry = selected
    local y = -PAD - 18 - 8
    local function Put(f, h)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", PAD, y)
        f:Show()
        y = y - h - ROW_GAP
    end
    Put(panel.posRow, ROW_H)
    if entry.opts and entry.opts.noScale then
        panel.scaleRow:Hide()
    else
        Put(panel.scaleRow, ROW_H)
    end
    for _, which in ipairs({ "width", "height" }) do
        local row = panel.sizeRows[which]
        local spec = SizeSpec(entry, which)
        if spec then
            row.range:SetText("px  (" .. RoundInt(spec.min) .. "–" .. RoundInt(spec.max) .. ")")
            Put(row, ROW_H)
        else
            row:Hide()
        end
    end
    y = y - 2
    Put(panel.btnRow1, BTN_H)
    Put(panel.btnRow2, BTN_H)
    panel.hint:ClearAllPoints()
    panel.hint:SetPoint("TOPLEFT", PAD, y)
    local hh = panel.hint:GetStringHeight()
    if not hh or hh < 1 then hh = 26 end
    panel:SetHeight(math.floor(-y + hh + PAD + 0.5))
end

-- Werte und Lage des Fensters auffrischen; relayout = Zeilen neu aufbauen (neue Auswahl)
function RefreshPanel(relayout)
    if not selected or not ns.editMode then return end
    if not panel then CreatePanel() end
    if relayout or not panel:IsShown() then
        panel.title:SetText(selected.label or "")
        LayoutPanel()
    end
    panel.xBox:Refresh()
    panel.yBox:Refresh()
    panel.scaleBox:Refresh()
    for _, row in pairs(panel.sizeRows) do
        if row:IsShown() then row.box:Refresh() end
    end
    PlacePanel()
    if not panel:IsShown() then
        panel:Show()
        if not InCombatLockdown() then
            pcall(panel.EnableKeyboard, panel, true)
            pcall(panel.SetPropagateKeyboardInput, panel, true)
        end
        pcall(panel.RegisterEvent, panel, "GLOBAL_MOUSE_DOWN")
    end
end

function Deselect()
    selected = nil
    RestyleOverlays()
    if not panel then return end
    for _, f in ipairs({ panel.xBox, panel.yBox, panel.scaleBox, panel.sizeRows.width.box, panel.sizeRows.height.box }) do
        if f:HasFocus() then f:ClearFocus() end
    end
    pcall(panel.UnregisterEvent, panel, "GLOBAL_MOUSE_DOWN")
    if not InCombatLockdown() then pcall(panel.EnableKeyboard, panel, false) end
    panel:Hide()
end

---------------------------------------------------------------------------
-- Werkzeugleiste
---------------------------------------------------------------------------

local function RestoreBar()
    bar:ClearAllPoints()
    local p = ns.db and ns.db.editBarPoint
    if type(p) == "table" and p[1] then
        bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -12)
    end
end

local function CreateBar()
    -- Benannt, damit die Leiste in UISpecialFrames stehen kann (Esc versteckt sie → Modus endet).
    -- Ist eine Anzeige gewählt, fängt das Fenster je Anzeige das Esc vorher ab (hebt nur die Auswahl auf).
    bar = CreateFrame("Frame", "strayEditBar", UIParent)
    bar:SetHeight(30)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    Border(bar, C.border)

    -- Links: stray-Symbol und Titel
    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(MEDIA .. "minimap_icon")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 8, 0)
    local title = Text(bar, 12, C.text, FONT_BODY)
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText("Bearbeitungsmodus")
    local tw = StringWidth(title)
    if not tw or tw < 1 then tw = 110 end
    local x = 8 + 16 + 6 + tw + 10

    local sep = Tex(bar, "ARTWORK", C.border)
    sep:SetSize(1, 16)
    sep:SetPoint("LEFT", x, 0)
    x = x + 1 + 10

    local gridButton = ToggleButton("Raster", GridIcon, GridOn, function()
        ns.db.editGrid = not GridOn()
        if grid then grid:SetShown(GridOn()) end
    end, "Raster", "Zeigt ein Hilfsraster. Ohne Einrasten landen Anzeigen beim Loslassen auf dem " .. GRID .. "-px-Raster.")
    gridButton:SetPoint("LEFT", x, 0)
    x = x + gridButton:GetWidth() + 4

    local snapButton = ToggleButton("Einrasten", SnapIcon, SnapOn, function()
        ns.db.editSnap = not SnapOn()
    end, "Einrasten", "Beim Loslassen rastet eine Anzeige an Kanten und Mitten anderer stray-Anzeigen und an der Bildschirmmitte ein. Geht vor dem Raster.")
    snapButton:SetPoint("LEFT", x, 0)
    x = x + snapButton:GetWidth() + 4

    local reset = BaseButton(BTN_H + 2)
    local icon = reset:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    icon:SetSize(14, 14)
    icon:SetPoint("CENTER")
    icon:SetVertexColor(C.textSide[1], C.textSide[2], C.textSide[3])
    reset:SetPoint("LEFT", x, 0)
    reset:SetScript("OnClick", function() StaticPopup_Show("STRAY_EDIT_RESET") end)
    reset:SetScript("OnEnter", function(self)
        ShowTip(self, "Alles zurücksetzen", "Setzt alle stray-Anzeigen auf ihre Standardposition und -größe (mit Rückfrage).")
    end)
    x = x + reset:GetWidth() + 8

    -- Fertig: blauer Hauptknopf
    local done = CreateFrame("Button", nil, bar)
    done:SetSize(64, BTN_H)
    local dbg = done:CreateTexture(nil, "BACKGROUND")
    dbg:SetAllPoints()
    dbg:SetColorTexture(1, 1, 1, 1)
    if not (CreateColor and pcall(dbg.SetGradient, dbg, "VERTICAL",
            CreateColor(0.114, 0.310, 0.620, 1), CreateColor(0.165, 0.435, 0.839, 1))) then
        dbg:SetColorTexture(0.165, 0.435, 0.839, 1)
    end
    Border(done, ACCENT)
    local dhl = done:CreateTexture(nil, "HIGHLIGHT")
    dhl:SetAllPoints()
    dhl:SetColorTexture(1, 1, 1, 0.07)
    local dtext = Text(done, 12, { 1, 1, 1 }, FONT_BODY)
    dtext:SetPoint("CENTER")
    dtext:SetText("Fertig")
    done:SetPoint("LEFT", x, 0)
    done:SetScript("OnClick", function() ExitEditMode() end)
    done:SetScript("OnEnter", function(self) ShowTip(self, "Fertig", "Positionen speichern und den Bearbeitungsmodus beenden (auch mit Esc).") end)
    done:SetScript("OnLeave", function() GameTooltip:Hide() end)
    x = x + done:GetWidth() + 4

    bar:SetWidth(math.floor(x + 0.5))

    -- Erklärtext nur als Tooltip über der Leiste
    bar:SetScript("OnEnter", function(self) ShowTip(self, "Bearbeitungsmodus", HINT) end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Leiste selbst verschieben und Position merken
    bar:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, px, py = self:GetPoint()
        if point then ns.db.editBarPoint = { point, relPoint, px, py } end
    end)

    -- Esc (CloseSpecialWindows) oder sonstiges Verstecken beendet den Modus
    bar:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        -- Nur echtes Verstecken (Esc), nicht Alt+Z: dann bleibt IsShown() wahr
        if ns.editMode and not self:IsShown() then ExitEditMode() end
    end)

    bar.toggles = { gridButton, snapButton }
    bar:Hide()
    tinsert(UISpecialFrames, "strayEditBar")
end

---------------------------------------------------------------------------
-- Ein- und Ausschalten
---------------------------------------------------------------------------

function ns.EnterEditMode()
    if ns.editMode then return end
    if InCombatLockdown() then
        ns.Print("Der Bearbeitungsmodus geht nur außerhalb des Kampfes.")
        return
    end
    if not bar then CreateBar() end
    if not grid then CreateGrid() end
    if strayFrame and strayFrame:IsShown() then strayFrame:Hide() end
    ns.editMode = true
    selected = nil
    for _, entry in ipairs(ns.movables) do
        if entry.preview then pcall(entry.preview, true) end
    end
    ns.NotifyConfig()
    RestoreBar()
    for _, b in ipairs(bar.toggles) do b:Refresh() end
    bar:Show()
    grid:SetShown(GridOn())
    -- Manche Anzeigen bauen ihre Beispiele mit kurzer Verzögerung auf
    UpdateOverlays()
    -- Anzeigen, die später erscheinen oder verschwinden, laufend nachziehen
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.3, UpdateOverlays)
end

function ExitEditMode()
    if not ns.editMode then return end
    Deselect()
    ns.editMode = false
    StaticPopup_Hide("STRAY_EDIT_RESET")
    if ticker then ticker:Cancel(); ticker = nil end
    for _, o in pairs(overlays) do
        if o.moving then o:GetScript("OnDragStop")(o) end
        o:Hide()
    end
    for _, entry in ipairs(ns.movables) do
        if entry.preview then pcall(entry.preview, false) end
    end
    if bar then bar:Hide() end
    if grid then grid:Hide() end
    GameTooltip:Hide()
    ns.NotifyConfig()
    ns.Print("Positionen gespeichert.")
end
ns.ExitEditMode = ExitEditMode

-- Kampf beginnt: Bearbeitungsmodus sofort verlassen (das Ereignis kommt noch vor der Sperre)
ns.On("PLAYER_REGEN_DISABLED", function()
    if ns.editMode then ExitEditMode() end
end)

---------------------------------------------------------------------------
-- Option im stray-Fenster
---------------------------------------------------------------------------

ns.AddOption(3, "Bearbeiten", {
    key = "editModeButton",
    type = "button",
    label = "Bearbeitungsmodus",
    buttonText = "Bearbeiten",
    keywords = { "bearbeiten", "verschieben", "position", "größe", "skalierung", "edit mode", "move", "layout", "scale", "unlock" },
    tooltip = "Blendet alle eingeschalteten stray-Anzeigen ein und macht sie frei verschiebbar – ohne Shift. Linksklick wählt eine Anzeige aus: Daneben öffnet sich ein kleines Fenster mit X/Y (ab Bildschirmmitte), Größe in Prozent und – wo vorhanden – Breite und Höhe; Pfeiltasten schieben sie um 1 px, mit Shift um 10 px. Rechtsklick setzt eine Anzeige auf Standard zurück. Esc hebt die Auswahl auf, ein weiteres Esc oder „Fertig“ beendet den Modus. Die Leiste oben schaltet Raster und Einrasten an anderen Anzeigen und der Bildschirmmitte.\n\nBetrifft alle eingeschalteten stray-Anzeigen: Gruppenrahmen, Aktionsleisten, Abklingzeiten, Bedrohungsliste, DMG-Meter, Haltbarkeit, Erfahrungsleiste, Taschen- und Menüleiste, Taschenfenster, Swing-Timer, Vorrat, Flugzeit, Würfelfenster, Gefahr-Hinweis und die Warntexte. Geht nur außerhalb des Kampfes. Auch per /stray edit.",
    onClick = function() ns.EnterEditMode() end,
})
