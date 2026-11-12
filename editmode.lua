-- stray – Bearbeitungsmodus
-- Blendet alle eingeschalteten stray-Anzeigen mit Beispielinhalt ein und macht sie ohne Shift
-- verschiebbar: lila Fläche mit Namen darüber, ziehen zum Verschieben, Shift + Rechtsklick setzt eine
-- Anzeige ganz auf Standard zurück (einfacher Rechtsklick tut nichts, kein Versehen). Oben mittig eine
-- schlanke, verschiebbare Werkzeugleiste (seit 0.23): „Bearbeiten · Zurück · ☐ Raster · ☑ Einrasten ·
-- Alles zurücksetzen · Fertig“, darunter eine kompakte Hinweiszeile.
-- Die gewählte Anzeige trägt einen lila Umriss mit Eck-Griffen; ns.EditSelected / ns.OnEditSelect melden
-- die Auswahl an ui.lua. Anzeigen dürfen jederzeit dazukommen oder verschwinden (Flächen je Eintrag).
-- Esc beendet den Modus (Leiste steht in UISpecialFrames).
-- Nur außerhalb des Kampfes.
--
-- Rückgängig (seit Nachtrag 0.22.0-alpha): Jede Änderung (Ziehen, Pfeiltasten, X/Y, Größe %,
-- Breite/Höhe, Zurücksetzen, Alles zurücksetzen) legt vorher einen Schnappschuss der betroffenen
-- Anzeige(n) in den Verlauf (Position, Größe %, Breite/Höhe). „Zurück“ bzw. Strg+Z stellt den letzten
-- Schritt wieder her. Schnelle Folgen von Pfeiltasten oder Mausrad an derselben Anzeige zählen als ein
-- Schritt. Der Verlauf gilt bis zum Ende des Modus.
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
local L = ns.L

ns.defaults.editGrid = true     -- Raster im Bearbeitungsmodus
ns.defaults.editSnap = true     -- Einrasten an anderen Anzeigen und der Bildschirmmitte
ns.defaults.editBarPoint = false -- Position der Werkzeugleiste { Punkt, relPunkt, x, y }

local GRID = 8  -- Raster in Pixeln (Einrasten beim Loslassen)
local SNAP = 8  -- Fangabstand fürs Einrasten in Pixeln
local SCALE_MIN, SCALE_MAX = 50, 200 -- Größe in Prozent

local MEDIA = "Interface\\AddOns\\stray\\media\\"
local FONT_BODY = "Fonts\\ARIALN.TTF"

-- Farben aus der gemeinsamen Tabelle ns.Colors (stray.lua); Ersatzwerte nur, falls sie fehlt
local NC = ns.Colors or {
    bg = { 0.078, 0.078, 0.098, 0.96 }, card = { 0.094, 0.094, 0.118, 1 },
    hover = { 0.122, 0.122, 0.153, 1 }, line = { 0.149, 0.149, 0.184, 1 },
    accent = { 0.545, 0.486, 0.965, 1 }, accentText = { 0.702, 0.659, 0.980, 1 },
    text = { 0.902, 0.902, 0.925, 1 }, textDim = { 0.545, 0.545, 0.600, 1 },
    textFaint = { 0.369, 0.369, 0.420, 1 },
}
local C = {
    bg         = NC.bg,
    card       = NC.card,
    hover      = NC.hover,
    border     = NC.line,
    accent     = NC.accent,
    accentText = NC.accentText,
    text       = NC.text,
    textSide   = NC.textDim,   -- grau: Beschriftungen, Knopftexte
    textDim    = NC.textFaint, -- schwach: ausgeschaltete Schalter
}
local ACCENT = C.accent

-- Stil „forever“ (nur Optik, kein Verhalten): Werte erst zur Anzeigezeit lesen, ns.db fehlt beim Laden
local function Forever()
    local ok, v = pcall(function() return ns.Style and ns.Style.IsForever() end)
    return ok and v and true or false
end

-- Palettenfarbe (gold, bronze …) oder Ersatz
local function Pal(key, fallback)
    local c = ns.Colors and ns.Colors[key]
    if type(c) == "table" then return c end
    return fallback
end

-- Bronze-Rahmen mit Schiefer; false, wenn nicht „forever“ (dann zeichnet der Aufrufer wie bisher)
local function ForeverFrame(frame, size)
    if not Forever() then return false end
    local ok = pcall(function()
        ns.Style.Fill(frame, "window")
        ns.Style.Border(frame, { size = size, cornerSize = 12, cornerOffset = 2 })
    end)
    return ok
end

-- Knopf- und Feldränder: bei „forever“ Bronze statt der dunklen Linienfarbe
local function ForeverBorderColor()
    if Forever() then C.border = Pal("bronze", C.border) end
end

local overlays = {}
local bar, grid, panel
local ticker
local selected -- gewählter Eintrag aus ns.movables
local undoButton
local ExitEditMode, Deselect, RefreshPanel, UpdateOverlays, SetBarKeys

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

-- Hängt other (auch über eine Kette, z. B. angedockte DMG-Meter-Fenster 2–5) an frame? Dann kein
-- Einrast-Ziel, weil es beim Ziehen mitwandert.
local function AnchoredTo(other, frame, depth)
    depth = depth or 0
    if depth > 8 or not other or not other.GetNumPoints then return false end
    local n = other:GetNumPoints() or 0
    for i = 1, n do
        local _, rel = other:GetPoint(i)
        if rel == frame then return true end
        if rel and rel ~= UIParent and AnchoredTo(rel, frame, depth + 1) then return true end
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

-- Für das stray-Fenster (Abschnitt POSITION): Mitte ab Bildschirmmitte lesen und setzen, gleiche
-- Werte wie X/Y im Bearbeitungsmodus. Setzen speichert und ruft frame.strayOnDragStop auf.
function ns.GetMovableCenter(frame)
    if not frame then return end
    local x, y = Center(frame)
    if not x then return end
    return RoundInt(x), RoundInt(y)
end

function ns.SetMovableCenter(frame, cx, cy)
    if not frame or not frame.strayKey or InCombatLockdown() or not ns.db then return end
    MoveTo(frame, cx, cy)
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

-- Wert ohne Grenzen und Raster setzen (Zurücksetzen, Rückgängig): z. B. Taschenfenster-Höhe 0 =
-- automatisch liegt unter dem kleinsten einstellbaren Wert. Läuft über set der Option bzw. onSize.
local function RawSize(spec, v)
    if InCombatLockdown() or v == nil then return end
    local ok, err = pcall(spec.set, v)
    if not ok then geterrorhandler()(err) end
end

local function SafeRestore(frame)
    local ok, err = pcall(ns.RestorePosition, frame)
    if not ok then geterrorhandler()(err) end
end

-- Eine Anzeige ganz zurücksetzen: Position, Größe in % und (falls gemeldet) Breite/Höhe
-- auf ns.defaults[Schlüssel]
local function ResetEntry(entry)
    local frame = entry.frame
    if InCombatLockdown() or not frame or not frame.strayKey then return end
    for _, which in ipairs({ "width", "height" }) do
        local spec = SizeSpec(entry, which)
        local def = spec and tonumber(spec.default)
        if def and SizeValue(spec) ~= def then RawSize(spec, def) end
    end
    if type(ns.db.scales) == "table" then ns.db.scales[frame.strayKey] = nil end
    ns.db.positions[frame.strayKey] = nil
    SafeRestore(frame) -- wendet auch die Größe (wieder 1) an
end

---------------------------------------------------------------------------
-- Rückgängig: Verlauf aus Schnappschüssen (bis zum Ende des Modus)
---------------------------------------------------------------------------

local history = {}
local MAX_STEPS = 100
local MERGE_TIME = 1.0 -- Pfeiltasten/Mausrad an derselben Anzeige innerhalb dieser Zeit = ein Schritt

local function CopyPos(p)
    if type(p) ~= "table" then return nil end
    return { p[1], p[2], p[3], p[4] }
end

-- Stand einer Anzeige: Position (gespeichert), Größe %, Breite/Höhe
local function Snapshot(entry)
    local key = entry.frame.strayKey
    local s = {
        entry = entry,
        pos = CopyPos(ns.db.positions[key]),
        scale = type(ns.db.scales) == "table" and ns.db.scales[key] or nil,
        size = {},
    }
    for _, which in ipairs({ "width", "height" }) do
        local spec = SizeSpec(entry, which)
        if spec then s.size[which] = SizeValue(spec) end
    end
    return s
end

local function Near(a, b)
    if a == b then return true end
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 0.01 end
    return false
end

local function SameSnap(a, b)
    if (a.pos == nil) ~= (b.pos == nil) then return false end
    if a.pos then
        for i = 1, 4 do if not Near(a.pos[i], b.pos[i]) then return false end end
    end
    if not Near(a.scale, b.scale) then return false end
    for _, which in ipairs({ "width", "height" }) do
        if not Near(a.size[which], b.size[which]) then return false end
    end
    return true
end

-- Schnappschuss wiederherstellen
local function ApplySnap(s)
    local entry = s.entry
    local frame = entry.frame
    if not frame or not frame.strayKey then return end
    for which, v in pairs(s.size) do
        local spec = SizeSpec(entry, which)
        if spec and not Near(SizeValue(spec), v) then RawSize(spec, v) end
    end
    if type(ns.db.scales) ~= "table" then ns.db.scales = {} end
    ns.db.scales[frame.strayKey] = s.scale
    ns.db.positions[frame.strayKey] = CopyPos(s.pos)
    SafeRestore(frame)
    -- Andock-Haken (DMG-Meter) neu entscheiden lassen; ohne Position regelt das RestorePosition
    if s.pos and type(frame.strayOnDragStop) == "function" then
        local ok, err = pcall(frame.strayOnDragStop, frame)
        if not ok then geterrorhandler()(err) end
    end
end

local function UpdateUndo()
    if undoButton then undoButton:Refresh() end
end

-- Vorher aufgenommene Schnappschüsse als einen Schritt ablegen (nur, was sich wirklich geändert hat).
-- tag (optional) fasst schnelle Folgen gleicher Art an derselben Anzeige zusammen.
local function PushStep(snaps, tag)
    local changed = {}
    for _, s in ipairs(snaps) do
        if s.entry.frame and not SameSnap(s, Snapshot(s.entry)) then changed[#changed + 1] = s end
    end
    if #changed == 0 then return end
    local now = GetTime()
    local last = history[#history]
    if tag and last and last.tag == tag and #changed == 1 and #last.snaps == 1
            and last.snaps[1].entry == changed[1].entry and now - last.t < MERGE_TIME then
        last.t = now -- älterer Stand bleibt der Rücksprungpunkt
        return
    end
    history[#history + 1] = { snaps = changed, tag = tag, t = now }
    if #history > MAX_STEPS then table.remove(history, 1) end
    UpdateUndo()
end

-- fn(...) ausführen und die Änderung an entry in den Verlauf legen
local function Record(entry, tag, fn, ...)
    if not entry or not entry.frame or not entry.frame.strayKey or not ns.db then
        return fn(...)
    end
    local snap = Snapshot(entry)
    fn(...)
    PushStep({ snap }, tag)
end

local function Undo()
    if InCombatLockdown() then return end
    local step = table.remove(history)
    if not step then return end
    for i = #step.snaps, 1, -1 do ApplySnap(step.snaps[i]) end
    UpdateUndo()
    if UpdateOverlays then UpdateOverlays() end
    if selected then RefreshPanel(true) end
end

local function ClearHistory()
    wipe(history)
    UpdateUndo()
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

-- Name einer Anzeige zum Anzeigen übersetzen. Das Label aus ns.RegisterMovable bleibt deutscher
-- Schlüssel; bei Namen mit Nummer ohne eigene Übersetzung („Aktionsleiste 3“) zählt der Teil davor.
local function LabelText(label)
    if type(label) ~= "string" then return label end
    local text = L[label]
    if text == label and not ns.isGerman then
        local base, num = label:match("^(.-) (%d+)$")
        if base and L[base] ~= base then text = L[base] .. " " .. num end
    end
    return text
end

local function StringWidth(fs)
    if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() end
    return fs:GetStringWidth()
end

---------------------------------------------------------------------------
-- Lila Flächen über den Anzeigen
---------------------------------------------------------------------------

-- Gewählte Anzeige: kräftiger lila Umriss (2 px) mit kleinen Eck-Griffen, Fläche dezenter
local function StyleOverlay(o, isSelected)
    local fv = Forever()
    if isSelected then
        o.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
        Recolor(o.edges, fv and Pal("gold", ACCENT) or ACCENT)
        o.sel:Show()
    else
        o.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
        if fv then
            local b = Pal("bronzeLight", ACCENT)
            Recolor(o.edges, { b[1], b[2], b[3], 0.9 })
        else
            Recolor(o.edges, { ACCENT[1], ACCENT[2], ACCENT[3], 0.9 })
        end
        o.sel:Hide()
    end
end

local function RestyleOverlays()
    for entry, o in pairs(overlays) do
        StyleOverlay(o, selected ~= nil and entry == selected)
    end
end

-- Auswahl nach außen melden (ui.lua: „Im Spiel ausgewählt“, Sprung zur Seite).
-- ns.EditSelected = strayKey der gewählten Anzeige; bleibt nach „Fertig“ als letzte Auswahl stehen.
local selectCallbacks = {}
function ns.OnEditSelect(fn)
    if type(fn) == "function" then table.insert(selectCallbacks, fn) end
end
local function NotifySelect(entry)
    local key = entry and entry.frame and entry.frame.strayKey or nil
    if key == ns.EditSelected then return end
    ns.EditSelected = key
    for _, fn in ipairs(selectCallbacks) do
        local ok, err = pcall(fn, key, entry and entry.label)
        if not ok then geterrorhandler()(err) end
    end
end

local function Select(entry)
    if InCombatLockdown() then return end
    selected = entry
    RestyleOverlays()
    RefreshPanel(true)
    NotifySelect(entry)
end

local function CreateOverlay(entry)
    ForeverBorderColor()
    local selCol = Forever() and Pal("gold", ACCENT) or ACCENT
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
    -- Auswahl-Umriss: zweite Linie außen (zusammen 2 px) und vier Eck-Griffe
    o.sel = CreateFrame("Frame", nil, o)
    o.sel:SetPoint("TOPLEFT", -1, 1)
    o.sel:SetPoint("BOTTOMRIGHT", 1, -1)
    Border(o.sel, selCol)
    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local grip = Tex(o.sel, "OVERLAY", selCol)
        grip:SetSize(7, 7)
        grip:SetPoint("CENTER", o.sel, corner, 0, 0)
        local dot = Tex(o.sel, "OVERLAY", { 1, 1, 1, 0.9 })
        dot:SetDrawLayer("OVERLAY", 1)
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", grip, "CENTER")
    end
    StyleOverlay(o, false)

    o.label = Text(o, 12, Forever() and Pal("gold", { 1, 1, 1 }) or { 1, 1, 1 }, nil, "OUTLINE")
    o.label:SetPoint("CENTER")
    o.label:SetText(LabelText(entry.label))

    -- Ziehen von Klicken unterscheiden: OnClick nach einem Ziehen wählt nicht aus
    o:SetScript("OnMouseDown", function() o.dragged = false end)
    o:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        o.dragged = true
        GameTooltip:Hide()
        o.snap = entry.frame.strayKey and ns.db and Snapshot(entry) or nil
        entry.frame:StartMoving()
        o.moving = true
    end)
    o:SetScript("OnDragStop", function()
        if not o.moving then return end
        o.moving = false
        entry.frame:StopMovingOrSizing()
        SavePosition(entry.frame)
        AfterDrop(entry.frame)
        if o.snap then PushStep({ o.snap }) end
        o.snap = nil
        if selected == entry then RefreshPanel(true) end
    end)
    o:SetScript("OnClick", function(_, button)
        if InCombatLockdown() then return end
        if button == "RightButton" then
            -- Nur mit Shift: einfacher Rechtsklick setzt nichts zurück
            if IsShiftKeyDown() then
                Record(entry, nil, ResetEntry, entry)
                if selected == entry then RefreshPanel(true) end
            end
        elseif not o.dragged then
            Select(entry)
        end
        o.dragged = false
    end)
    o:SetScript("OnEnter", function(self)
        if o.moving then return end
        local a = C.accentText
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(LabelText(entry.label), 1, 1, 1)
        GameTooltip:AddLine(L["Klick: auswählen (Position, Größe, Pfeiltasten)"], a[1], a[2], a[3])
        GameTooltip:AddLine(L["Ziehen: verschieben"], a[1], a[2], a[3])
        GameTooltip:AddLine(L["Shift + Rechtsklick: auf Standard zurücksetzen"], a[1], a[2], a[3])
        GameTooltip:Show()
    end)
    o:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return o
end

-- Flächen hängen am Eintrag (nicht an seiner Nummer): Anzeigen dürfen jederzeit dazukommen oder aus
-- ns.movables verschwinden (z. B. DMG-Meter-Fenster 2–5).
function UpdateOverlays()
    local present = {}
    for _, entry in ipairs(ns.movables) do
        present[entry] = true
        local frame = entry.frame
        local o = overlays[entry]
        if ns.editMode and frame and frame:IsShown() then
            if not o then
                o = CreateOverlay(entry)
                overlays[entry] = o
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
    -- Abgemeldete Anzeigen: Fläche weg, Auswahl aufheben
    for entry, o in pairs(overlays) do
        if not present[entry] then
            if o.moving then
                o.moving = false
                if entry.frame then pcall(entry.frame.StopMovingOrSizing, entry.frame) end
            end
            o:Hide()
            overlays[entry] = nil
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
-- Knöpfe der Leiste
---------------------------------------------------------------------------

local BTN_H = 22      -- Knöpfe im Fenster je Anzeige
local BAR_BTN_H = 24  -- Knöpfe der Werkzeugleiste (schlank)
local BAR_FONT = 13

local function ShowTip(owner, title, line)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(title, 1, 1, 1)
    if line then GameTooltip:AddLine(line, C.textSide[1], C.textSide[2], C.textSide[3], true) end
    GameTooltip:Show()
end

local function BaseButton(width, parent, height)
    local b = CreateFrame("Button", nil, parent or bar)
    b:SetSize(width, height or BAR_BTN_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(C.card[1], C.card[2], C.card[3], 1)
    b.edges = Border(b, C.border)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Breite eines Textes; vor dem ersten Vermessen grob schätzen
local function TextWidth(fs, s, perChar)
    local w = StringWidth(fs)
    if not w or w < 1 then w = #(s or "") * (perChar or 6) end
    return w
end

-- Häkchen mit Text (Raster, Einrasten); isOn() liefert den Zustand, toggle() schaltet um
local function CheckToggle(label, isOn, toggle, tipTitle, tipLine)
    local b = CreateFrame("Button", nil, bar)
    b:SetHeight(BAR_BTN_H)
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    local boxBg = Tex(box, "BACKGROUND", C.card)
    boxBg:SetAllPoints()
    local edges = Border(box, C.textSide)
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetSize(12, 12)
    mark:SetPoint("CENTER")
    mark:SetTexture(MEDIA .. "icons\\check")
    b.text = Text(b, BAR_FONT, C.text, FONT_BODY)
    b.text:SetPoint("LEFT", box, "RIGHT", 7, 0)
    b.text:SetText(label)
    b:SetWidth(math.floor(14 + 7 + TextWidth(b.text, label, 7) + 2 + 0.5))
    function b:Refresh()
        local on = isOn()
        boxBg:SetColorTexture(on and ACCENT[1] or C.card[1], on and ACCENT[2] or C.card[2], on and ACCENT[3] or C.card[3], 1)
        Recolor(edges, on and ACCENT or C.textSide)
        mark:SetShown(on and true or false)
    end
    local function Tip(self)
        ShowTip(self, isOn() and L("%s: an", tipTitle) or L("%s: aus", tipTitle), tipLine)
    end
    b:SetScript("OnClick", function(self)
        toggle()
        self:Refresh()
        Tip(self)
    end)
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        Tip(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
        GameTooltip:Hide()
    end)
    b:Refresh()
    return b
end

-- Knopf mit Text (für das Fenster je Anzeige)
local function TextButton(parent, label, width, onClick, tipTitle, tipLine)
    local b = BaseButton(width, parent, BTN_H)
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
    text = "",
    button1 = "",
    button2 = "",
    OnAccept = function()
        if InCombatLockdown() then return end
        -- Ein einziger Schritt im Verlauf: „Zurück“ holt alle Anzeigen auf einmal wieder
        local snaps = {}
        for _, entry in ipairs(ns.movables) do
            if entry.frame and entry.frame.strayKey then snaps[#snaps + 1] = Snapshot(entry) end
        end
        for _, entry in ipairs(ns.movables) do
            if entry.frame and entry.frame.strayKey then ResetEntry(entry) end
        end
        PushStep(snaps)
        if selected then RefreshPanel(true) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Texte erst beim Zeigen holen (gewählte Sprache)
local function ShowResetAll()
    local d = StaticPopupDialogs["STRAY_EDIT_RESET"]
    d.text = L["stray: Alle Anzeigen auf ihre Standardposition und -größe zurücksetzen?"]
    d.button1 = L["Zurücksetzen"]
    d.button2 = CANCEL or L["Abbrechen"]
    StaticPopup_Show("STRAY_EDIT_RESET")
end

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
    bg:SetColorTexture(C.card[1], C.card[2], C.card[3], 1)
    eb.edges = Border(eb, C.border)

    -- getValue() darf als zweiten Wert einen Anzeigetext liefern (z. B. „auto“)
    function eb:Refresh()
        if self:HasFocus() then return end
        local v, shown = getValue()
        self:SetText(shown or (v and tostring(RoundInt(v))) or "–")
    end

    -- Jede Übernahme landet im Verlauf; Mausrad-Folgen zählen als ein Schritt
    local wheelTag = {}
    local function Commit(v, wheel)
        if InCombatLockdown() or not v then return end
        local ok, err = pcall(Record, selected, wheel and wheelTag or nil, commit, v)
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
        Commit(RoundInt(v) + delta * (IsShiftKeyDown() and 10 or 1), true)
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
    local fs = Text(parent, 11, C.textSide, FONT_BODY)
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
    ForeverBorderColor()
    panel = CreateFrame("Frame", "strayEditPanel", UIParent)
    panel:SetWidth(PANEL_W)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    local pi = 1
    if ForeverFrame(panel, 6) then
        pi = 6
    else
        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 1)
        Border(panel, C.border)
    end
    -- Lila Kante oben (wie die gewählte Fläche: diese Anzeige ist gemeint)
    local line = Tex(panel, "ARTWORK", ACCENT)
    line:SetPoint("TOPLEFT", pi, -pi); line:SetPoint("TOPRIGHT", -pi, -pi); line:SetHeight(2)

    -- Kopf: Name der Anzeige, rechts Schließen-Kreuz
    if Forever() then
        panel.title = Text(panel, 13, Pal("gold", C.text), ns.Style.FontTitle())
    else
        panel.title = Text(panel, 13, C.text, FONT_BODY)
    end
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
        ShowTip(self, L["Schließen"], L["Hebt die Auswahl auf (auch mit Esc)."])
    end)
    close:SetScript("OnLeave", function()
        cx:SetTextColor(C.textSide[1], C.textSide[2], C.textSide[3])
        GameTooltip:Hide()
    end)

    local function Frame() return selected and selected.frame end

    -- Position ab Bildschirmmitte
    panel.posRow = Row(L["Position"])
    local function GetX() local f = Frame(); if f then return (Center(f)) end end
    local function GetY() local f = Frame(); if not f then return end local _, y = Center(f); return y end
    local xl = SmallText(panel.posRow, "X")
    xl:SetPoint("LEFT", LABEL_W + 4, 0)
    panel.xBox = NumberField(panel.posRow, 50, GetX, function(v)
        local f = Frame(); if f then MoveTo(f, v, nil) end
    end, "X", L["Waagerechter Abstand der Mitte zur Bildschirmmitte in Pixeln (negativ = links). Enter übernimmt, Mausrad ±1, mit Shift ±10."])
    panel.xBox:SetPoint("LEFT", xl, "RIGHT", 5, 0)
    local yl = SmallText(panel.posRow, "Y")
    yl:SetPoint("LEFT", panel.xBox, "RIGHT", 9, 0)
    panel.yBox = NumberField(panel.posRow, 50, GetY, function(v)
        local f = Frame(); if f then MoveTo(f, nil, v) end
    end, "Y", L["Senkrechter Abstand der Mitte zur Bildschirmmitte in Pixeln (negativ = unten). Enter übernimmt, Mausrad ±1, mit Shift ±10."])
    panel.yBox:SetPoint("LEFT", yl, "RIGHT", 5, 0)

    -- Größe in Prozent
    panel.scaleRow = Row(L["Größe"])
    panel.scaleBox = NumberField(panel.scaleRow, 50, function()
        local f = Frame(); if f then return (f:GetScale() or 1) * 100 end
    end, function(v)
        local f = Frame(); if f then SetScalePercent(f, v) end
    end, L["Größe"], L("Größe der ganzen Anzeige in Prozent (%d–%d). Enter übernimmt, Mausrad ±1, mit Shift ±10.", SCALE_MIN, SCALE_MAX))
    panel.scaleBox:SetPoint("LEFT", LABEL_W + 4 + 12, 0)
    local pctl = SmallText(panel.scaleRow, "%  (" .. SCALE_MIN .. "–" .. SCALE_MAX .. ")")
    pctl:SetPoint("LEFT", panel.scaleBox, "RIGHT", 5, 0)

    -- Breite und Höhe (nur, wenn das Modul sie meldet)
    panel.sizeRows = {}
    for _, which in ipairs({ "width", "height" }) do
        local name = which == "width" and L["Breite"] or L["Höhe"]
        local row = Row(name)
        row.box = NumberField(row, 50, function()
            local spec = selected and SizeSpec(selected, which)
            local v = spec and SizeValue(spec)
            -- Standard 0 = automatisch (Taschenfenster-Höhe)
            if v == 0 and tonumber(spec.default) == 0 then return v, L["auto"] end
            return v
        end, function(v)
            local spec = selected and SizeSpec(selected, which)
            if spec and (not spec.enabled or spec.enabled()) then SetSize(spec, v) end
        end, name, L("%s der Anzeige in Pixeln, wie der Regler im stray-Fenster. Enter übernimmt, Mausrad ±1, mit Shift ±10.", name))
        row.box:SetPoint("LEFT", LABEL_W + 4 + 12, 0)
        row.range = SmallText(row, "")
        row.range:SetPoint("LEFT", row.box, "RIGHT", 5, 0)
        panel.sizeRows[which] = row
    end

    -- Knöpfe: mittig ausrichten, Zurücksetzen, Schließen
    local half = math.floor((PANEL_W - 2 * PAD - 6) / 2)
    panel.btnRow1 = CreateFrame("Frame", nil, panel)
    panel.btnRow1:SetSize(PANEL_W - 2 * PAD, BTN_H)
    local centerH = TextButton(panel.btnRow1, L["Mitte waagerecht"], half, function()
        local f = Frame(); if f then Record(selected, nil, MoveTo, f, 0, nil); RefreshPanel(true) end
    end, L["Waagerecht mittig"], L["Setzt die Anzeige waagerecht auf die Bildschirmmitte (X = 0)."])
    centerH:SetPoint("LEFT")
    local centerV = TextButton(panel.btnRow1, L["Mitte senkrecht"], half, function()
        local f = Frame(); if f then Record(selected, nil, MoveTo, f, nil, 0); RefreshPanel(true) end
    end, L["Senkrecht mittig"], L["Setzt die Anzeige senkrecht auf die Bildschirmmitte (Y = 0)."])
    centerV:SetPoint("RIGHT")

    panel.btnRow2 = CreateFrame("Frame", nil, panel)
    panel.btnRow2:SetSize(PANEL_W - 2 * PAD, BTN_H)
    local reset = TextButton(panel.btnRow2, L["Zurücksetzen"], half, function()
        if selected then Record(selected, nil, ResetEntry, selected); RefreshPanel(true) end
    end, L["Zurücksetzen"], L["Setzt diese Anzeige ganz auf den Standard zurück: Position, Größe und – wo vorhanden – Breite und Höhe. Auch mit Shift + Rechtsklick auf die Anzeige."])
    reset:SetPoint("LEFT")
    local closeBtn = TextButton(panel.btnRow2, L["Schließen"], half, function() Deselect() end,
        L["Schließen"], L["Hebt die Auswahl auf (auch mit Esc)."])
    closeBtn:SetPoint("RIGHT")

    panel.hint = Text(panel, 11, C.textSide, FONT_BODY)
    panel.hint:SetWidth(PANEL_W - 2 * PAD)
    panel.hint:SetJustifyH("LEFT")
    panel.hint:SetText(L["Pfeiltasten: 1 px · mit Shift: 10 px\nStrg + Z: rückgängig · Esc hebt die Auswahl auf"])

    -- Tastatur: nur Pfeiltasten, Strg+Z und Esc abfangen, alles andere geht ans Spiel weiter.
    -- EnableKeyboard/SetPropagateKeyboardInput sind im Kampf gesperrt; der Modus endet dort ohnehin.
    panel:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local step = IsShiftKeyDown() and 10 or 1
        local dx, dy = 0, 0
        if key == "Z" and IsControlKeyDown() then
            self:SetPropagateKeyboardInput(false)
            Undo()
            return
        elseif key == "UP" then dy = step
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
            Record(selected, "nudge", MoveBy, selected.frame, dx, dy)
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
        panel.title:SetText(LabelText(selected.label or ""))
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
        -- Solange das Fenster offen ist, nimmt es die Tasten (auch Strg+Z); die Leiste ruht
        SetBarKeys(false)
        if not InCombatLockdown() then
            pcall(panel.EnableKeyboard, panel, true)
            pcall(panel.SetPropagateKeyboardInput, panel, true)
        end
        pcall(panel.RegisterEvent, panel, "GLOBAL_MOUSE_DOWN")
    end
end

-- keep = true (Ende des Modus): letzte Auswahl bleibt als ns.EditSelected stehen
function Deselect(keep)
    selected = nil
    RestyleOverlays()
    if not keep then NotifySelect(nil) end
    if ns.editMode then SetBarKeys(true) end
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

local BAR_PAD = 12
local BAR_TOP_H = 36   -- obere Reihe: Logo, Titel, Knöpfe
local BAR_HINT_H = 22  -- Hinweiszeile darunter
local LOGO_SIZE = 20

-- Farbe als Hex für |cff…-Codes
local function Hex(c)
    return string.format("%02x%02x%02x", RoundInt(c[1] * 255), RoundInt(c[2] * 255), RoundInt(c[3] * 255))
end

-- Hinweiszeile unter der Leiste; Tasten in hellem Lila, Wirkung in Textfarbe.
-- Gibt den Text und eine Fassung ohne Farbcodes (zum Schätzen der Breite) zurück.
local function HintLine()
    local key = "|cff" .. Hex(C.accentText)
    local parts = {
        { L["Klick"], L["auswählen"] },
        { L["Ziehen"], L["verschieben"] },
        { L["Pfeiltasten"], L["fein verschieben"] },
        { L["Shift + Rechtsklick"], L["auf Standard zurücksetzen"] },
        { L["Strg + Z"], L["rückgängig"] },
        { L["Esc"], L["beenden"] },
    }
    local out, plain = {}, {}
    for i, p in ipairs(parts) do
        out[i] = key .. p[1] .. ":|r " .. p[2]
        plain[i] = p[1] .. ": " .. p[2]
    end
    return table.concat(out, "   ·   "), table.concat(plain, "   ·   ")
end

-- Pfeil nach links (Blizzards Pfeil-Textur gedreht); ohne Textur ein Textzeichen
local function UndoIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(16, 16)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    local ok = t:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
    if ok ~= false and t.SetRotation and pcall(t.SetRotation, t, math.pi / 2) then
        pcall(t.SetDesaturated, t, true)
        f.tex = t
    else
        t:Hide()
        f.fs = Text(f, 16, C.textSide, FONT_BODY)
        f.fs:SetPoint("CENTER", 0, 1)
        f.fs:SetText("<")
    end
    function f:SetColor(c)
        if self.tex then
            self.tex:SetVertexColor(c[1], c[2], c[3])
        else
            self.fs:SetTextColor(c[1], c[2], c[3])
        end
    end
    return f
end

-- Tasten der Leiste: nur Strg+Z abfangen (Rückgängig), alles andere geht ans Spiel weiter.
-- Aktiv, solange keine Anzeige gewählt ist; sonst übernimmt das Fenster je Anzeige.
function SetBarKeys(on)
    if not bar or InCombatLockdown() then return end
    pcall(bar.EnableKeyboard, bar, on and true or false)
    if on then pcall(bar.SetPropagateKeyboardInput, bar, true) end
end

local function CreateBar()
    -- Benannt, damit die Leiste in UISpecialFrames stehen kann (Esc versteckt sie → Modus endet).
    -- Ist eine Anzeige gewählt, fängt das Fenster je Anzeige das Esc vorher ab (hebt nur die Auswahl auf).
    -- Schlank nach Leons Vorlage: Bearbeiten · Zurück · ☐ Raster · ☑ Einrasten · ⟳ · Fertig
    ForeverBorderColor()
    bar = CreateFrame("Frame", "strayEditBar", UIParent)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    local bi = 1 -- Randstärke der Leiste (Forever 6)
    if ForeverFrame(bar, 6) then
        bi = 6
    else
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 1)
        Border(bar, C.border)
    end

    -- Hinweiszeile: eigene, leicht abgesetzte Fläche unter der Knopfreihe
    local hintBg = Tex(bar, "BORDER", C.card)
    hintBg:SetPoint("BOTTOMLEFT", bi, bi); hintBg:SetPoint("BOTTOMRIGHT", -bi, bi)
    hintBg:SetHeight(BAR_HINT_H - 1)
    local hintLine = Tex(bar, "ARTWORK", C.border)
    hintLine:SetPoint("BOTTOMLEFT", bi, BAR_HINT_H); hintLine:SetPoint("BOTTOMRIGHT", -bi, BAR_HINT_H)
    hintLine:SetHeight(1)
    local hint = Text(bar, 11, C.textSide, FONT_BODY)
    hint:SetPoint("CENTER", bar, "BOTTOM", 0, BAR_HINT_H / 2)
    hint:SetWordWrap(false)
    local hintText, hintPlain = HintLine()
    hint:SetText(hintText)

    local function Place(f, x)
        f:SetPoint("LEFT", bar, "TOPLEFT", x, -BAR_TOP_H / 2)
    end
    -- Trennpunkt „·“
    local function Dot(x)
        local d = Text(bar, BAR_FONT, C.textDim, FONT_BODY)
        d:SetText("·")
        Place(d, x)
        return x + 4 + 12
    end

    -- Links: kleines Logo und „Bearbeiten“
    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(MEDIA .. "logo")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    Place(logo, BAR_PAD)
    local title
    if Forever() then
        title = Text(bar, BAR_FONT + 1, Pal("gold", C.text), ns.Style.FontTitle())
    else
        title = Text(bar, BAR_FONT + 1, C.text, FONT_BODY)
    end
    title:SetPoint("LEFT", logo, "RIGHT", 7, 0)
    title:SetText(L["Bearbeiten"])
    local x = BAR_PAD + LOGO_SIZE + 7 + TextWidth(title, L["Bearbeiten"], 8) + 12
    x = Dot(x)

    -- Zurück (Rückgängig): aktiv, sobald etwas im Verlauf ist
    local undo = BaseButton(10, nil, BAR_BTN_H)
    undo.icon = UndoIcon(undo)
    undo.icon:SetPoint("LEFT", 7, 0)
    undo.text = Text(undo, BAR_FONT, C.textSide, FONT_BODY)
    undo.text:SetPoint("LEFT", undo.icon, "RIGHT", 4, 0)
    undo.text:SetText(L["Zurück"])
    undo:SetWidth(math.floor(7 + 16 + 4 + TextWidth(undo.text, L["Zurück"], 7) + 10 + 0.5))
    function undo:Refresh()
        local on = #history > 0
        self:SetEnabled(on)
        if on then
            Recolor(self.edges, ACCENT)
            self.icon:SetColor(C.accentText)
            self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
        else
            Recolor(self.edges, C.border)
            self.icon:SetColor(C.textDim)
            self.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end
    end
    local function UndoTip(self)
        local n = #history
        if n > 0 then
            ShowTip(self, L["Zurück"], L("Macht den letzten Schritt rückgängig (auch mit Strg + Z). Im Verlauf: %d. Er gilt bis zum Ende des Bearbeitungsmodus.", n))
        else
            ShowTip(self, L["Zurück"], L["Noch nichts rückgängig zu machen. Verschieben, Pfeiltasten, X/Y, Größe, Breite/Höhe und Zurücksetzen lassen sich hier Schritt für Schritt zurücknehmen (auch mit Strg + Z)."])
        end
    end
    undo:SetScript("OnClick", function(self)
        Undo()
        UndoTip(self)
    end)
    undo:SetScript("OnEnter", UndoTip)
    if undo.SetMotionScriptsWhileDisabled then undo:SetMotionScriptsWhileDisabled(true) end
    Place(undo, x)
    x = x + undo:GetWidth() + 14
    undoButton = undo

    local gridButton = CheckToggle(L["Raster"], GridOn, function()
        ns.db.editGrid = not GridOn()
        if grid then grid:SetShown(GridOn()) end
    end, L["Raster"], L("Zeigt ein Hilfsraster. Ohne Einrasten landen Anzeigen beim Loslassen auf dem %d-px-Raster.", GRID))
    Place(gridButton, x)
    x = x + gridButton:GetWidth() + 14

    local snapButton = CheckToggle(L["Einrasten"], SnapOn, function()
        ns.db.editSnap = not SnapOn()
    end, L["Einrasten"], L["Beim Loslassen rastet eine Anzeige an Kanten und Mitten anderer stray-Anzeigen und an der Bildschirmmitte ein. Geht vor dem Raster."])
    Place(snapButton, x)
    x = x + snapButton:GetWidth() + 10

    -- Alles zurücksetzen (Symbol)
    local reset = BaseButton(BAR_BTN_H, nil, BAR_BTN_H)
    local icon = reset:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    icon:SetSize(14, 14)
    icon:SetPoint("CENTER")
    pcall(icon.SetDesaturated, icon, true)
    icon:SetVertexColor(C.textSide[1], C.textSide[2], C.textSide[3])
    Place(reset, x)
    reset:SetScript("OnClick", function() ShowResetAll() end)
    reset:SetScript("OnEnter", function(self)
        icon:SetVertexColor(1, 1, 1)
        ShowTip(self, L["Alles zurücksetzen"], L["Setzt alle stray-Anzeigen auf ihre Standardposition und -größe (mit Rückfrage). Lässt sich mit „Zurück“ rückgängig machen."])
    end)
    reset:SetScript("OnLeave", function()
        icon:SetVertexColor(C.textSide[1], C.textSide[2], C.textSide[3])
        GameTooltip:Hide()
    end)
    x = x + reset:GetWidth() + 6

    x = x + 4
    x = Dot(x)

    -- Fertig: dunkler Knopf mit lila Rand
    local done = BaseButton(10, nil, BAR_BTN_H)
    Recolor(done.edges, ACCENT)
    if Forever() then
        -- Hauptknopf: rot-bronze mit hellem Bronzerand
        local rd, bl = Pal("red", C.card), Pal("bronzeLight", ACCENT)
        done.bg:SetColorTexture(rd[1], rd[2], rd[3], 1)
        Recolor(done.edges, bl)
    end
    local dtext = Text(done, BAR_FONT, Forever() and Pal("gold", { 1, 1, 1 }) or { 1, 1, 1 }, FONT_BODY)
    dtext:SetPoint("CENTER")
    dtext:SetText(L["Fertig"])
    local doneW = math.max(70, math.floor(TextWidth(dtext, L["Fertig"], 8) + 28 + 0.5))
    done:SetWidth(doneW)
    Place(done, x)
    done:SetScript("OnClick", function() ExitEditMode() end)
    done:SetScript("OnEnter", function(self) ShowTip(self, L["Fertig"], L["Positionen speichern und den Bearbeitungsmodus beenden (auch mit Esc)."]) end)

    -- Breite: Knopfreihe oder Hinweiszeile, je nachdem, was länger ist
    local rowW = x + doneW + BAR_PAD
    local hintW = TextWidth(hint, hintPlain, 5) + 2 * BAR_PAD + 8
    bar:SetSize(math.floor(math.max(rowW, hintW) + 0.5), BAR_TOP_H + BAR_HINT_H)

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

    -- Strg+Z ohne gewählte Anzeige; andere Tasten gehen weiter ans Spiel (auch Esc)
    bar:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "Z" and IsControlKeyDown() then
            self:SetPropagateKeyboardInput(false)
            Undo()
            return
        end
        self:SetPropagateKeyboardInput(true)
    end)

    -- Esc (CloseSpecialWindows) oder sonstiges Verstecken beendet den Modus
    bar:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        -- Nur echtes Verstecken (Esc), nicht Alt+Z: dann bleibt IsShown() wahr
        if ns.editMode and not self:IsShown() then ExitEditMode() end
    end)

    bar.toggles = { gridButton, snapButton, undo }
    bar:Hide()
    tinsert(UISpecialFrames, "strayEditBar")
end

---------------------------------------------------------------------------
-- Ein- und Ausschalten
---------------------------------------------------------------------------

function ns.EnterEditMode()
    if ns.editMode then return end
    if InCombatLockdown() then
        ns.Print(L["Der Bearbeitungsmodus geht nur außerhalb des Kampfes."])
        return
    end
    if not bar then CreateBar() end
    if not grid then CreateGrid() end
    if strayFrame and strayFrame:IsShown() then strayFrame:Hide() end
    ns.editMode = true
    selected = nil
    ClearHistory()
    for _, entry in ipairs(ns.movables) do
        if entry.preview then pcall(entry.preview, true) end
    end
    ns.NotifyConfig()
    RestoreBar()
    for _, b in ipairs(bar.toggles) do b:Refresh() end
    bar:Show()
    SetBarKeys(true)
    grid:SetShown(GridOn())
    -- Manche Anzeigen bauen ihre Beispiele mit kurzer Verzögerung auf
    UpdateOverlays()
    -- Anzeigen, die später erscheinen oder verschwinden, laufend nachziehen
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.3, UpdateOverlays)
end

function ExitEditMode()
    if not ns.editMode then return end
    Deselect(true)
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
    SetBarKeys(false)
    if bar then bar:Hide() end
    if grid then grid:Hide() end
    ClearHistory() -- Verlauf gilt nur bis zum Ende des Modus
    GameTooltip:Hide()
    ns.NotifyConfig()
    ns.Print(L["Positionen gespeichert."])
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
    label = L["Bearbeitungsmodus"],
    buttonText = L["Bearbeiten"],
    keywords = { "bearbeiten", "verschieben", "position", "größe", "skalierung", "edit mode", "move", "layout", "scale", "unlock" },
    tooltip = L["Blendet alle eingeschalteten stray-Anzeigen ein und macht sie frei verschiebbar – ohne Shift. Klick wählt eine Anzeige aus: Daneben öffnet sich ein kleines Fenster mit X/Y (ab Bildschirmmitte), Größe in Prozent und – wo vorhanden – Breite und Höhe; Pfeiltasten schieben sie um 1 px, mit Shift um 10 px. Shift + Rechtsklick setzt eine Anzeige ganz auf Standard zurück. „Zurück“ oder Strg + Z macht den letzten Schritt rückgängig. Esc hebt die Auswahl auf, ein weiteres Esc oder „Fertig“ beendet den Modus. Die Leiste oben schaltet Raster und Einrasten an anderen Anzeigen und der Bildschirmmitte.\n\nBetrifft alle eingeschalteten stray-Anzeigen: Bedrohungsliste, DMG-Meter, Haltbarkeit, EP-Tracker, Taschenfenster, Bankfenster, Flugzeit, Würfelfenster, Gefahr-Hinweis und die Warntexte. Geht nur außerhalb des Kampfes. Auch per /stray edit."],
    onClick = function() ns.EnterEditMode() end,
})
