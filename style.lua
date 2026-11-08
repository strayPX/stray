-- stray – Oberflächen-Stil
-- Zwei Arten: "stray" (lila, flach, Standard) und "forever" (Entwurf W1 „Gilded Dark“: Bronze-Rahmen,
-- Schiefer, Gold). Option ns.db.uiStyle, Wechsel braucht Neuladen. Alle Module bauen ihre Optik über
-- diese Datei bzw. über ns.Colors, das beim Laden an Ort und Stelle auf die Forever-Palette gesetzt wird.
--
-- API (alle Funktionen sind vor dem Laden der Einstellungen sicher, dann gilt „stray“):
--   ns.Style.IsForever()                        → bool
--   ns.Style.Border(frame, opts)                → Rahmen-Objekt { SetColor(r,g,b,a), Reset(), SetShown(b), Show(), Hide() }
--       opts: size (Kantenstärke, Forever 4–14, Standard 14), inset (px nach innen, Standard 0),
--             level (Textur-Unterebene, Standard 0), corners (Eckwinkel, Standard true, nur Forever),
--             cornerSize (Standard 22), cornerOffset (Standard 4), color ({r,g,b,a}, nur „stray“, Standard ns.Colors.line)
--   ns.Style.Fill(frame, kind, opts)            → Flächen-Objekt { SetShown, Show, Hide, SetAlpha }
--       kind: "window" | "panel" | "inset" | "bar"; opts: inset (Standard 0), level (Standard -8)
--   ns.Style.FillColor(kind)                    → r, g, b, a (Flachfarbe, wenn nur eine Farbe gebraucht wird)
--   ns.Style.Font() / FontNumbers() / FontTitle()
--   ns.Style.Button(btn, kind) / Tab(btn, selected) / EditBox(box)   → nur bei „forever“ ein Objekt, sonst nil
--   ns.Style.MEDIA, EDGE, CORNER, SLATE, TAB, TAB_LINE   Texturpfade
--   /stray style                                zeigt im Stil „forever“ ein Testfenster

local _, ns = ...
local L = ns.L

local Style = {}
ns.Style = Style

local MEDIA = "Interface\\AddOns\\stray\\media\\style\\"
Style.MEDIA = MEDIA
Style.EDGE = MEDIA .. "edge"
Style.CORNER = MEDIA .. "corner"
Style.SLATE = MEDIA .. "slate"
Style.TAB = MEDIA .. "tab"
Style.TAB_LINE = MEDIA .. "tab_line"

function Style.IsForever()
    return ns.db ~= nil and ns.db.uiStyle == "forever"
end
local IsForever = Style.IsForever

---------------------------------------------------------------------------
-- Palette (Forever); „stray“-Werte stehen in stray.lua
---------------------------------------------------------------------------

local FOREVER = {
    bg          = { 0.118, 0.120, 0.137, 0.97 }, -- Schiefer
    card        = { 0.145, 0.149, 0.169, 1 },
    hover       = { 0.180, 0.176, 0.165, 1 },
    line        = { 0.290, 0.216, 0.098, 1 },    -- #4a3719 Bronze dunkel
    text        = { 0.812, 0.776, 0.698, 1 },    -- #cfc6b2
    textDim     = { 0.561, 0.525, 0.447, 1 },    -- #8f8672
    textFaint   = { 0.384, 0.357, 0.310, 1 },
    gold        = { 0.890, 0.761, 0.478, 1 },    -- #e3c27a Überschriften
    goldDim     = { 0.788, 0.635, 0.310, 1 },    -- #c9a24f
    bronze      = { 0.541, 0.416, 0.204, 1 },    -- #8a6a34
    bronzeLight = { 0.784, 0.627, 0.353, 1 },    -- #c8a05a
    bronzeDark  = { 0.227, 0.176, 0.090, 1 },    -- #3a2d17
    red         = { 0.541, 0.184, 0.153, 1 },    -- #8a2f27 Hauptknopf
    redDim      = { 0.361, 0.110, 0.090, 1 },    -- #5c1c17
}
-- accent (#8b7cf6) und accentText (#b3a8fa) bleiben in beiden Stilen Lila

local FILLS = {
    stray   = { inset = { 0.055, 0.055, 0.070, 1 } },
    forever = { inset = { 0.043, 0.043, 0.051, 1 }, bar = { 0.043, 0.043, 0.051, 1 } },
}

-- Setzt die Werte in den vorhandenen Tabellen (Verweise der Module bleiben gültig)
local applied = false
function Style.Apply()
    if applied or not IsForever() then return end
    applied = true
    for key, value in pairs(FOREVER) do
        local c = ns.Colors[key]
        if type(c) == "table" then
            for i = 1, 4 do c[i] = value[i] end
        else
            ns.Colors[key] = { value[1], value[2], value[3], value[4] }
        end
    end
end

-- Läuft normalerweise schon aus stray.lua (vor ns.OnLoaded); hier als Sicherheit
ns.On("ADDON_LOADED", function(name)
    if name == ns.name then Style.Apply() end
end)

function Style.FillColor(kind)
    local C = ns.Colors
    local fills = FILLS[IsForever() and "forever" or "stray"]
    if fills[kind] then
        local c = fills[kind]
        return c[1], c[2], c[3], c[4]
    end
    local c = (kind == "panel" or kind == "bar") and C.card or C.bg
    return c[1], c[2], c[3], c[4] or 1
end

---------------------------------------------------------------------------
-- Schriften
---------------------------------------------------------------------------

-- Hauptschrift der Fenster; Forever: Friz Quadrata, stray: Arial Narrow wie bisher
function Style.Font()
    return IsForever() and "Fonts\\FRIZQT__.TTF" or "Fonts\\ARIALN.TTF"
end

function Style.FontNumbers()
    return "Fonts\\ARIALN.TTF"
end

-- Überschriften/Titel: Forever Friz Quadrata, stray Standardschrift des Spiels
function Style.FontTitle()
    if IsForever() then return "Fonts\\FRIZQT__.TTF" end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

---------------------------------------------------------------------------
-- Rahmen
---------------------------------------------------------------------------

local function Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local BorderMethods = {}
BorderMethods.__index = BorderMethods

function BorderMethods:SetColor(r, g, b, a)
    for _, t in ipairs(self.edges) do
        if self.flat then
            t:SetColorTexture(r, g, b, a or 1)
        else
            t:SetVertexColor(r, g, b, a or 1)
        end
    end
end

function BorderMethods:Reset()
    if self.flat then
        local c = self.color
        self:SetColor(c[1], c[2], c[3], c[4] or 1)
    else
        self:SetColor(1, 1, 1, 1)
    end
end

function BorderMethods:SetShown(shown)
    for _, t in ipairs(self.edges) do t:SetShown(shown) end
    for _, t in ipairs(self.ornaments) do t:SetShown(shown) end
end
function BorderMethods:Show() self:SetShown(true) end
function BorderMethods:Hide() self:SetShown(false) end

-- Stil „stray“: 1-px-Linienrand wie bisher
local function FlatBorder(frame, opts, obj)
    local c = opts.color or ns.Colors.line
    obj.flat, obj.color = true, c
    local i = opts.inset or 0
    local function Edge(p1, x1, y1, p2, x2, y2, horizontal)
        local t = frame:CreateTexture(nil, "BORDER", nil, opts.level or 0)
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetPoint(p1, frame, p1, x1, y1)
        t:SetPoint(p2, frame, p2, x2, y2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        table.insert(obj.edges, t)
    end
    Edge("TOPLEFT", i, -i, "TOPRIGHT", -i, -i, true)
    Edge("BOTTOMLEFT", i, i, "BOTTOMRIGHT", -i, i, true)
    Edge("TOPLEFT", i, -i, "BOTTOMLEFT", i, i, false)
    Edge("TOPRIGHT", -i, -i, "BOTTOMRIGHT", -i, i, false)
end

-- Stil „forever“: acht Teile aus edge.tga (Anordnung wie Blizzards edgeFile, 128x16, je Teil 14x14 Pixel
-- in einer 16er-Zelle) plus Eckwinkel aus corner.tga. Ohne BackdropTemplate, daher ohne Taint-Risiko.
local function BronzeBorder(frame, opts, obj)
    local n = Clamp(math.floor(opts.size or 14), 4, 14)
    local i = opts.inset or 0
    local lvl = opts.level or 0
    local ya, yb = 1 / 16, 15 / 16

    local function Piece(tex, w, h, p1, x, y, p2, x2, y2)
        local t = frame:CreateTexture(nil, "BORDER", nil, lvl)
        t:SetTexture(tex)
        t:SetPoint(p1, frame, p1, x, y)
        if p2 then t:SetPoint(p2, frame, p2, x2, y2) end
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        table.insert(obj.edges, t)
        return t
    end
    local EDGE = Style.EDGE

    -- Kanten: Dicke liegt in der Bildbreite (bei oben/unten gedreht), Länge wird gestreckt
    local t = Piece(EDGE, n, nil, "TOPLEFT", i, -i - n, "BOTTOMLEFT", i, i + n)
    t:SetTexCoord(1 / 128, ya, 1 / 128, yb, (1 + n) / 128, ya, (1 + n) / 128, yb)
    t = Piece(EDGE, n, nil, "TOPRIGHT", -i, -i - n, "BOTTOMRIGHT", -i, i + n)
    t:SetTexCoord((31 - n) / 128, ya, (31 - n) / 128, yb, 31 / 128, ya, 31 / 128, yb)
    t = Piece(EDGE, nil, n, "TOPLEFT", i + n, -i, "TOPRIGHT", -i - n, -i)
    t:SetTexCoord(33 / 128, yb, (33 + n) / 128, yb, 33 / 128, ya, (33 + n) / 128, ya)
    t = Piece(EDGE, nil, n, "BOTTOMLEFT", i + n, i, "BOTTOMRIGHT", -i - n, i)
    t:SetTexCoord((63 - n) / 128, yb, 63 / 128, yb, (63 - n) / 128, ya, 63 / 128, ya)

    -- Ecken der Kante
    t = Piece(EDGE, n, n, "TOPLEFT", i, -i)
    t:SetTexCoord(65 / 128, ya, 65 / 128, (1 + n) / 16, (65 + n) / 128, ya, (65 + n) / 128, (1 + n) / 16)
    t = Piece(EDGE, n, n, "TOPRIGHT", -i, -i)
    t:SetTexCoord((95 - n) / 128, ya, (95 - n) / 128, (1 + n) / 16, 95 / 128, ya, 95 / 128, (1 + n) / 16)
    t = Piece(EDGE, n, n, "BOTTOMLEFT", i, i)
    t:SetTexCoord(97 / 128, (15 - n) / 16, 97 / 128, yb, (97 + n) / 128, (15 - n) / 16, (97 + n) / 128, yb)
    t = Piece(EDGE, n, n, "BOTTOMRIGHT", -i, i)
    t:SetTexCoord((127 - n) / 128, (15 - n) / 16, (127 - n) / 128, yb, 127 / 128, (15 - n) / 16, 127 / 128, yb)

    -- Eckwinkel (Bronze-Gold, ragen leicht über den Rand)
    if opts.corners ~= false then
        local cs = opts.cornerSize or 22
        local off = opts.cornerOffset or 4
        local function Ornament(point, x, y, l, r, tp, bt)
            local o = frame:CreateTexture(nil, "OVERLAY", nil, 1)
            o:SetTexture(Style.CORNER)
            o:SetSize(cs, cs)
            o:SetPoint(point, frame, point, x, y)
            o:SetTexCoord(l, r, tp, bt)
            table.insert(obj.ornaments, o)
        end
        Ornament("TOPLEFT", i - off, off - i, 0, 1, 0, 1)
        Ornament("TOPRIGHT", off - i, off - i, 1, 0, 0, 1)
        Ornament("BOTTOMLEFT", i - off, i - off, 0, 1, 1, 0)
        Ornament("BOTTOMRIGHT", off - i, i - off, 1, 0, 1, 0)
    end
end

function Style.Border(frame, opts)
    opts = opts or {}
    local obj = setmetatable({ edges = {}, ornaments = {} }, BorderMethods)
    if IsForever() then
        BronzeBorder(frame, opts, obj)
    else
        FlatBorder(frame, opts, obj)
    end
    return obj
end

---------------------------------------------------------------------------
-- Flächen
---------------------------------------------------------------------------

local FillMethods = {}
FillMethods.__index = FillMethods

function FillMethods:SetShown(shown)
    for _, t in ipairs(self.parts) do t:SetShown(shown) end
end
function FillMethods:Show() self:SetShown(true) end
function FillMethods:Hide() self:SetShown(false) end
function FillMethods:SetAlpha(a)
    for _, t in ipairs(self.parts) do t:SetAlpha(a) end
end

function Style.Fill(frame, kind, opts)
    opts = opts or {}
    local i = opts.inset or 0
    local lvl = opts.level or -8
    local obj = setmetatable({ parts = {} }, FillMethods)

    local function Layer(sub)
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, sub)
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", i, -i)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -i, i)
        table.insert(obj.parts, t)
        return t
    end

    if IsForever() and kind ~= "bar" then
        local slate = Layer(lvl)
        slate:SetTexture(Style.SLATE, "REPEAT", "REPEAT")
        slate:SetHorizTile(true)
        slate:SetVertTile(true)
        if kind == "window" then
            slate:SetAlpha(ns.Colors.bg[4] or 1)
        elseif kind == "panel" then
            local tint = Layer(lvl + 1)
            tint:SetColorTexture(1, 1, 1, 0.03)
        else -- inset
            local tint = Layer(lvl + 1)
            tint:SetColorTexture(0, 0, 0, 0.45)
        end
    else
        local t = Layer(lvl)
        local r, g, b, a = Style.FillColor(kind)
        t:SetColorTexture(r, g, b, a)
    end
    return obj
end

---------------------------------------------------------------------------
-- Knöpfe, Reiter, Eingabefelder (nur bei „forever“ ein Objekt)
---------------------------------------------------------------------------

local function Rgb(c, a) return c[1], c[2], c[3], a or c[4] or 1 end

local function Line(parent, r, g, b, a, i, layer)
    local obj = {}
    local function Edge(p1, x1, y1, p2, x2, y2, horizontal)
        local t = parent:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(r, g, b, a or 1)
        t:SetPoint(p1, parent, p1, x1, y1)
        t:SetPoint(p2, parent, p2, x2, y2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        table.insert(obj, t)
    end
    Edge("TOPLEFT", i, -i, "TOPRIGHT", -i, -i, true)
    Edge("BOTTOMLEFT", i, i, "BOTTOMRIGHT", -i, i, true)
    Edge("TOPLEFT", i, -i, "BOTTOMLEFT", i, i, false)
    Edge("TOPRIGHT", -i, -i, "BOTTOMRIGHT", -i, i, false)
    return obj
end

-- kind "primary": rot-bronze (Übernehmen); "secondary": grau-bronze. Liefert obj.textColor für den Text.
function Style.Button(btn, kind)
    if not IsForever() then return nil end
    local top, bottom, rim, text
    if kind == "primary" then
        top, bottom, rim, text = { 0.541, 0.184, 0.153 }, { 0.357, 0.102, 0.082 }, { 0.722, 0.475, 0.310 }, { 0.941, 0.875, 0.690 }
    else
        top, bottom, rim, text = { 0.294, 0.275, 0.220 }, { 0.176, 0.165, 0.129 }, { 0.541, 0.463, 0.282 }, { 0.851, 0.796, 0.643 }
    end
    local obj = { textColor = text }
    obj.top = btn:CreateTexture(nil, "BACKGROUND")
    obj.top:SetPoint("TOPLEFT", 1, -1)
    obj.top:SetPoint("BOTTOMRIGHT", btn, "RIGHT", -1, 0)
    obj.top:SetColorTexture(top[1], top[2], top[3], 1)
    obj.bottom = btn:CreateTexture(nil, "BACKGROUND")
    obj.bottom:SetPoint("TOPLEFT", btn, "LEFT", 1, 0)
    obj.bottom:SetPoint("BOTTOMRIGHT", -1, 1)
    obj.bottom:SetColorTexture(bottom[1], bottom[2], bottom[3], 1)
    obj.outer = Line(btn, 0.04, 0.02, 0.02, 1, 0)           -- dunkler Außenrand
    obj.rim = Line(btn, rim[1], rim[2], rim[3], 0.9, 1, "ARTWORK") -- Innenrand Bronze
    obj.hover = btn:CreateTexture(nil, "HIGHLIGHT")
    obj.hover:SetPoint("TOPLEFT", 1, -1)
    obj.hover:SetPoint("BOTTOMRIGHT", -1, 1)
    obj.hover:SetColorTexture(1, 1, 1, 0.10)
    return obj
end

-- Trapez-Reiter; selected = golden mit lila Oberkante
function Style.Tab(btn, selected)
    if not IsForever() then return nil end
    local obj = {}
    obj.fill = btn:CreateTexture(nil, "BACKGROUND")
    obj.fill:SetTexture(Style.TAB)
    obj.fill:SetAllPoints()
    obj.line = btn:CreateTexture(nil, "BORDER")
    obj.line:SetTexture(Style.TAB_LINE)
    obj.line:SetAllPoints()
    obj.top = btn:CreateTexture(nil, "ARTWORK")
    obj.top:SetColorTexture(Rgb(ns.Colors.accent))
    obj.top:SetHeight(2)
    obj.top:SetPoint("TOPLEFT", 6, 0)
    obj.top:SetPoint("TOPRIGHT", -6, 0)
    function obj:SetSelected(sel)
        local C = ns.Colors
        if sel then
            self.fill:SetVertexColor(0.227, 0.200, 0.133, 1)
            self.line:SetVertexColor(Rgb(C.bronzeLight))
        else
            self.fill:SetVertexColor(0.149, 0.137, 0.114, 1)
            self.line:SetVertexColor(Rgb(C.line))
        end
        self.top:SetShown(sel and true or false)
    end
    obj:SetSelected(selected)
    return obj
end

-- Schwarzes Eingabefeld mit Bronzerand
function Style.EditBox(box)
    if not IsForever() then return nil end
    local obj = {}
    obj.bg = box:CreateTexture(nil, "BACKGROUND")
    obj.bg:SetAllPoints()
    obj.bg:SetColorTexture(0.043, 0.043, 0.051, 1)
    obj.border = Line(box, 0.541, 0.416, 0.204, 1, 0)
    return obj
end

---------------------------------------------------------------------------
-- Testfenster: /stray style (nur im Stil „forever“)
---------------------------------------------------------------------------

local testFrame

local function ShowTest()
    if not IsForever() then
        ns.Print(L["Der Stil „Forever UI“ ist nicht aktiv. Unter System → Allgemein einschalten und neu laden."])
        return
    end
    local C = ns.Colors
    if not testFrame then
        local f = CreateFrame("Frame", "strayStyleTest", UIParent)
        f:SetSize(440, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        Style.Fill(f, "window")
        Style.Border(f, { size = 14 })

        local function Text(parent, text, size, c, point, x, y)
            local fs = parent:CreateFontString(nil, "OVERLAY")
            fs:SetFont(Style.FontTitle(), size, "")
            fs:SetTextColor(c[1], c[2], c[3], 1)
            fs:SetPoint(point, x, y)
            fs:SetText(text)
            return fs
        end
        Text(f, "stray", 20, C.gold, "TOPLEFT", 24, -22)
        Text(f, L["Stil: Forever UI (Testfenster)"], 12, C.textDim, "TOPLEFT", 90, -28)
        Text(f, L["Rahmen, Schiefer und Gold-Überschrift"], 14, C.text, "TOPLEFT", 24, -56)

        local panel = CreateFrame("Frame", nil, f)
        panel:SetPoint("TOPLEFT", 24, -84)
        panel:SetSize(190, 90)
        Style.Fill(panel, "panel")
        Style.Border(panel, { size = 4, corners = false })
        Text(panel, L["Fläche: Panel"], 13, C.gold, "TOPLEFT", 10, -10)

        local inset = CreateFrame("Frame", nil, f)
        inset:SetPoint("TOPLEFT", 226, -84)
        inset:SetSize(190, 90)
        Style.Fill(inset, "inset")
        Style.Border(inset, { size = 4, corners = false })
        Text(inset, L["Fläche: Inset"], 13, C.gold, "TOPLEFT", 10, -10)

        local bar = CreateFrame("Frame", nil, f)
        bar:SetPoint("TOPLEFT", 24, -188)
        bar:SetSize(392, 20)
        Style.Fill(bar, "bar")
        Style.Border(bar, { size = 3, corners = false })

        local function Button(label, kind, x)
            local b = CreateFrame("Button", nil, f)
            b:SetSize(110, 26)
            b:SetPoint("BOTTOMLEFT", x, 24)
            local obj = Style.Button(b, kind)
            local fs = b:CreateFontString(nil, "OVERLAY")
            fs:SetFont(Style.Font(), 13, "")
            local tc = obj and obj.textColor or C.text
            fs:SetTextColor(tc[1], tc[2], tc[3], 1)
            fs:SetPoint("CENTER")
            fs:SetText(label)
            return b
        end
        Button(L["Verwerfen"], "secondary", 24)
        Button(L["Übernehmen"], "primary", 144)

        local close = CreateFrame("Button", nil, f)
        close:SetSize(60, 26)
        close:SetPoint("BOTTOMRIGHT", -24, 24)
        Style.Button(close, "secondary")
        local cfs = close:CreateFontString(nil, "OVERLAY")
        cfs:SetFont(Style.Font(), 13, "")
        cfs:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        cfs:SetPoint("CENTER")
        cfs:SetText(L["Schließen"])
        close:SetScript("OnClick", function() f:Hide() end)

        table.insert(UISpecialFrames, "strayStyleTest")
        testFrame = f
    end
    testFrame:SetShown(not testFrame:IsShown())
end

ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.style = ShowTest

---------------------------------------------------------------------------
-- Option (Seite System → Allgemein, neben der Sprache; wirkt nach dem Neuladen)
---------------------------------------------------------------------------

ns.AddOption(3, "Profile", {
    key = "uiStyle",
    type = "choice",
    label = L["Oberflächen-Stil"],
    values = { "stray", "forever" },
    labels = { L["stray (lila, flach)"], L["Forever UI (Bronze & Gold)"] },
    reload = true,
    tooltip = L["Aussehen von Fenstern und Anzeigen. „stray“ ist flach und lila, „Forever UI“ nutzt Bronze-Rahmen, Schiefer und Gold.\nWird nach dem Neuladen wirksam."],
    keywords = { "stil", "style", "forever", "bronze", "gold", "design", "theme", "aussehen", "look" },
})
