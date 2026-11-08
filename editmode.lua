-- stray – Bearbeiten-Modus
-- Blendet alle eingeschalteten stray-Anzeigen mit Beispielinhalt ein und macht sie ohne Shift
-- verschiebbar: blaue Fläche mit Namen darüber, ziehen zum Verschieben, Rechtsklick setzt eine
-- Anzeige zurück. Oben mittig eine kompakte, verschiebbare Werkzeugleiste mit Raster, Einrasten,
-- Zurücksetzen (Symbol) und „Fertig“. Esc beendet den Modus (Leiste steht in UISpecialFrames).
-- Nur außerhalb des Kampfes (die Gruppenrahmen hängen an Blizzards geschützten Rahmen).
--
-- Einrasten: Beim Loslassen rastet eine Anzeige an Kanten und Mitten anderer sichtbarer
-- stray-Anzeigen und an der Bildschirmmitte ein (Abstand unter SNAP). Gilt vor dem Raster.
-- Haken für Module: frame.strayOnDragStop(frame) wird nach dem Loslassen und Speichern aufgerufen.

local _, ns = ...

ns.defaults.editGrid = true     -- Raster im Bearbeiten-Modus
ns.defaults.editSnap = true     -- Einrasten an anderen Anzeigen und der Bildschirmmitte
ns.defaults.editBarPoint = false -- Position der Werkzeugleiste { Punkt, relPunkt, x, y }

local GRID = 8  -- Raster in Pixeln (Einrasten beim Loslassen)
local SNAP = 8  -- Fangabstand fürs Einrasten in Pixeln

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

local HINT = "Ziehen verschiebt · Rechtsklick setzt eine Anzeige zurück · ausgeschaltete Anzeigen erscheinen nicht · Esc beendet"

local overlays = {}
local bar, grid
local ticker
local ExitEditMode

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function Round(v)
    return math.floor(v / GRID + 0.5) * GRID
end

local function GridOn() return ns.db and ns.db.editGrid ~= false end
local function SnapOn() return ns.db and ns.db.editSnap ~= false end

-- Rechteck eines Frames in UIParent-Einheiten: links, rechts, oben, unten
local function Rect(frame)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, r * s, t * s, b * s
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

local function ResetPosition(frame)
    ns.db.positions[frame.strayKey] = nil
    ns.RestorePosition(frame)
end

-- Haken für Module (z. B. DMG-Meter-Andocken): nach dem Loslassen aufrufen
local function AfterDrop(frame)
    if type(frame.strayOnDragStop) == "function" then
        local ok, err = pcall(frame.strayOnDragStop, frame)
        if not ok then geterrorhandler()(err) end
    end
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

local function CreateOverlay(entry)
    local o = CreateFrame("Button", nil, UIParent)
    o:SetFrameStrata("HIGH") -- unter den Popups (DIALOG), damit deren Knöpfe klickbar bleiben
    o:SetFrameLevel(50)
    o:SetMovable(false)
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    o:RegisterForClicks("RightButtonUp")

    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
    Border(o, { ACCENT[1], ACCENT[2], ACCENT[3], 0.9 })

    o.label = Text(o, 12, { 1, 1, 1 }, nil, "OUTLINE")
    o.label:SetPoint("CENTER")
    o.label:SetText(entry.label)

    o:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        entry.frame:StartMoving()
        o.moving = true
    end)
    o:SetScript("OnDragStop", function()
        if not o.moving then return end
        o.moving = false
        entry.frame:StopMovingOrSizing()
        SavePosition(entry.frame)
        AfterDrop(entry.frame)
    end)
    o:SetScript("OnClick", function(_, button)
        if button == "RightButton" and not InCombatLockdown() then ResetPosition(entry.frame) end
    end)
    o:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(entry.label, 1, 1, 1)
        GameTooltip:AddLine("Ziehen: verschieben", ACCENT[1], ACCENT[2], ACCENT[3])
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
            end
            frame:SetMovable(true)
            o:ClearAllPoints()
            o:SetAllPoints(frame)
            o:Show()
        elseif o then
            o:Hide()
        end
    end
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

local function BaseButton(width)
    local b = CreateFrame("Button", nil, bar)
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

StaticPopupDialogs["STRAY_EDIT_RESET"] = {
    text = "stray: Alle Anzeigen auf ihre Standardposition zurücksetzen?",
    button1 = "Zurücksetzen",
    button2 = "Abbrechen",
    OnAccept = function()
        if InCombatLockdown() then return end
        for _, entry in ipairs(ns.movables) do
            if entry.frame and entry.frame.strayKey then ResetPosition(entry.frame) end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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
    -- Benannt, damit die Leiste in UISpecialFrames stehen kann (Esc versteckt sie → Modus endet)
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
    title:SetText("Bearbeiten")
    local tw = StringWidth(title)
    if not tw or tw < 1 then tw = 60 end
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
        ShowTip(self, "Alles zurücksetzen", "Setzt alle stray-Anzeigen auf ihre Standardposition (mit Rückfrage).")
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
    done:SetScript("OnEnter", function(self) ShowTip(self, "Fertig", "Positionen speichern und den Bearbeiten-Modus beenden (auch mit Esc).") end)
    done:SetScript("OnLeave", function() GameTooltip:Hide() end)
    x = x + done:GetWidth() + 4

    bar:SetWidth(math.floor(x + 0.5))

    -- Erklärtext nur als Tooltip über der Leiste
    bar:SetScript("OnEnter", function(self) ShowTip(self, "Bearbeiten-Modus", HINT) end)
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
        ns.Print("Der Bearbeiten-Modus geht nur außerhalb des Kampfes.")
        return
    end
    if not bar then CreateBar() end
    if not grid then CreateGrid() end
    if strayFrame and strayFrame:IsShown() then strayFrame:Hide() end
    ns.editMode = true
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

-- Kampf beginnt: Bearbeiten-Modus sofort verlassen
ns.On("PLAYER_REGEN_DISABLED", function()
    if ns.editMode then ExitEditMode() end
end)

---------------------------------------------------------------------------
-- Option im stray-Fenster
---------------------------------------------------------------------------

ns.AddOption(3, "Bearbeiten", {
    key = "editModeButton",
    type = "button",
    label = "Anzeigen verschieben",
    buttonText = "Bearbeiten",
    tooltip = "Blendet alle eingeschalteten stray-Anzeigen ein und macht sie frei verschiebbar – ohne Shift. Rechtsklick auf eine Anzeige setzt sie auf ihre Standardposition zurück, „Fertig“ oder Esc beendet den Modus. Die Leiste oben schaltet Raster und Einrasten an anderen Anzeigen und der Bildschirmmitte.\n\nBetrifft alle eingeschalteten stray-Anzeigen: Gruppenrahmen, Aktionsleisten, Abklingzeiten, Bedrohungsliste, DMG-Meter, Haltbarkeit, Erfahrungsleiste, Taschen- und Menüleiste, Taschenfenster, Swing-Timer, Vorrat, Flugzeit, Würfelfenster, Gefahr-Hinweis und die Warntexte. Geht nur außerhalb des Kampfes. Auch per /stray edit.",
    onClick = function() ns.EnterEditMode() end,
})
