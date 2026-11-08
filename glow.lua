-- stray – laufender Rand („Pixel-Glow“) für Symbole
--
-- ns.Glow(frame, on, color) legt um ein Symbol einen Rand aus kurzen hellen Strichen, die im
-- Uhrzeigersinn um den Rand laufen. color ist optional { r, g, b, a } (Standard Gelb).
-- Mehrfaches An/Aus ist sicher; ein zweites „an“ ändert nur die Farbe.
--
-- Aufbau:
--   - Jeder Rand ist ein eigener Frame aus einem Pool, als Kind des Symbols (so verschwindet er
--     mit dem Symbol). Auf das Symbol selbst wird nichts geschrieben: die Zuordnung steht in
--     der lokalen Tabelle „active“ mit dem Frame als Schlüssel.
--   - Ein einziger gemeinsamer Takt bewegt alle Ränder. Er läuft nur, solange mindestens ein
--     Rand wirklich sichtbar ist (OnShow/OnHide der eigenen Rand-Frames zählen mit).
--   - Jeder Strich besteht aus zwei Texturen, damit er sauber um die Ecken läuft.

local _, ns = ...

local LINES = 8        -- Anzahl der Striche
local THICKNESS = 2    -- Strichstärke in Pixeln
local PERIOD = 4       -- Sekunden für eine Runde
local OUTSET = 1       -- Rand liegt so weit außerhalb des Symbols
local DEFAULT_COLOR = { 0.95, 0.82, 0.20, 1 }

local active = {}   -- [Symbol-Frame] = Rand-Frame
local visible = {}  -- [Rand-Frame] = true, solange sichtbar
local data = {}     -- [Rand-Frame] = { lines = { { a, b }, … } }
local pool = {}
local visibleCount = 0
local elapsedTotal = 0
local pending = 0   -- seit dem letzten Zeichnen vergangene Zeit
local STEP = 1 / 30 -- höchstens 30 Aktualisierungen pro Sekunde (bei 4 s je Runde nicht sichtbar)
local EDGES = { 0, 0, 0, 0 } -- wiederverwendet, spart Speichermüll

local driver = CreateFrame("Frame")

---------------------------------------------------------------------------
-- Striche entlang des Randes setzen
---------------------------------------------------------------------------

-- Stück [from, to] auf einer Kante zeichnen (Abstände ab Kantenanfang, im Uhrzeigersinn).
-- Kante 0 oben (links → rechts), 1 rechts (oben → unten), 2 unten (rechts → links), 3 links (unten → oben)
local function PlaceOnEdge(tex, glow, edge, from, to)
    local len = to - from
    if len <= 0.01 then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    if edge == 0 then
        tex:SetPoint("TOPLEFT", glow, "TOPLEFT", from, 0)
        tex:SetSize(len, THICKNESS)
    elseif edge == 1 then
        tex:SetPoint("TOPRIGHT", glow, "TOPRIGHT", 0, -from)
        tex:SetSize(THICKNESS, len)
    elseif edge == 2 then
        tex:SetPoint("BOTTOMRIGHT", glow, "BOTTOMRIGHT", -from, 0)
        tex:SetSize(len, THICKNESS)
    else
        tex:SetPoint("BOTTOMLEFT", glow, "BOTTOMLEFT", 0, from)
        tex:SetSize(THICKNESS, len)
    end
    tex:Show()
end

local function UpdateGlow(glow, progress)
    local d = data[glow]
    if not d then return end
    local w, h = glow:GetWidth(), glow:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or w <= 4 or h <= 4 then return end

    local edges = EDGES
    edges[1], edges[2], edges[3], edges[4] = w, h, w, h
    local perimeter = 2 * (w + h)
    -- Strichlänge: knapp die Hälfte des Abstands zwischen zwei Strichen, höchstens die kürzere Seite
    local length = math.min(perimeter / LINES * 0.45, math.min(w, h))

    for i, pair in ipairs(d.lines) do
        local start = ((i - 1) / LINES + progress) % 1 * perimeter
        -- Kante und Position auf der Kante bestimmen
        local edge, pos = 0, start
        while pos >= edges[edge + 1] do
            pos = pos - edges[edge + 1]
            edge = (edge + 1) % 4
        end
        local first = math.min(pos + length, edges[edge + 1])
        PlaceOnEdge(pair[1], glow, edge, pos, first)
        local rest = length - (first - pos)
        if rest > 0.01 then
            PlaceOnEdge(pair[2], glow, (edge + 1) % 4, 0, math.min(rest, edges[(edge + 1) % 4 + 1]))
        else
            pair[2]:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Gemeinsamer Takt
---------------------------------------------------------------------------

local function Step(_, elapsed)
    pending = pending + (elapsed or 0)
    if pending < STEP then return end
    elapsedTotal = (elapsedTotal + pending) % PERIOD
    pending = 0
    local progress = elapsedTotal / PERIOD
    for glow in pairs(visible) do
        UpdateGlow(glow, progress)
    end
end

local failed = false
local function SafeStep(self, elapsed)
    local ok, err = pcall(Step, self, elapsed)
    if not ok then
        -- Keine Fehlerflut: Takt anhalten und einmal melden
        failed = true
        driver:SetScript("OnUpdate", nil)
        geterrorhandler()(err)
    end
end

local function RecheckDriver()
    if visibleCount > 0 and not failed then
        if not driver:GetScript("OnUpdate") then driver:SetScript("OnUpdate", SafeStep) end
    else
        driver:SetScript("OnUpdate", nil)
    end
end

local function OnGlowShow(glow)
    if visible[glow] then return end
    visible[glow] = true
    visibleCount = visibleCount + 1
    -- sofort richtig zeichnen, nicht erst im nächsten Bild
    pcall(UpdateGlow, glow, elapsedTotal / PERIOD)
    RecheckDriver()
end

local function OnGlowHide(glow)
    if not visible[glow] then return end
    visible[glow] = nil
    visibleCount = visibleCount - 1
    RecheckDriver()
end

---------------------------------------------------------------------------
-- Pool
---------------------------------------------------------------------------

local function CreateGlow()
    local glow = CreateFrame("Frame", nil, UIParent)
    glow:Hide()
    local d = { lines = {} }
    for i = 1, LINES do
        local a = glow:CreateTexture(nil, "OVERLAY", nil, 7)
        local b = glow:CreateTexture(nil, "OVERLAY", nil, 7)
        a:Hide()
        b:Hide()
        d.lines[i] = { a, b }
    end
    data[glow] = d
    glow:SetScript("OnShow", OnGlowShow)
    glow:SetScript("OnHide", OnGlowHide)
    return glow
end

local function SetColor(glow, color)
    local c = (type(color) == "table") and color or DEFAULT_COLOR
    local r, g, b, a = c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, c[4] or c.a or 1
    for _, pair in ipairs(data[glow].lines) do
        pair[1]:SetColorTexture(r, g, b, a)
        pair[2]:SetColorTexture(r, g, b, a)
    end
end

local function Acquire(frame)
    local glow = table.remove(pool) or CreateGlow()
    glow:SetParent(frame)
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -OUTSET, OUTSET)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", OUTSET, -OUTSET)
    glow:SetFrameStrata(frame:GetFrameStrata())
    glow:SetFrameLevel(frame:GetFrameLevel() + 5)
    return glow
end

local function Release(glow)
    glow:Hide() -- löst OnHide aus, falls er sichtbar war
    glow:ClearAllPoints()
    glow:SetParent(UIParent)
    for _, pair in ipairs(data[glow].lines) do
        pair[1]:Hide()
        pair[2]:Hide()
    end
    table.insert(pool, glow)
end

---------------------------------------------------------------------------
-- Öffentliche Funktion
---------------------------------------------------------------------------

-- frame: ein eigenes Symbol (Frame). on: true/false. color: optional { r, g, b, a }.
function ns.Glow(frame, on, color)
    if type(frame) ~= "table" or not frame.GetObjectType then return end
    local glow = active[frame]
    if on then
        if not glow then
            local ok, result = pcall(Acquire, frame)
            if not ok then
                geterrorhandler()(result)
                return
            end
            glow = result
            active[frame] = glow
        end
        SetColor(glow, color)
        glow:Show()
        -- Ist das Symbol gerade versteckt, kommt kein OnShow; sobald es erscheint, schon
        if glow:IsVisible() then OnGlowShow(glow) end
    elseif glow then
        active[frame] = nil
        Release(glow)
    end
end

-- Ist der Rand an einem Symbol gerade an?
function ns.IsGlowing(frame)
    return active[frame] ~= nil
end
