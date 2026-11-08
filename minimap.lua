-- stray – Minimap: stray-Knopf am Rand (rund oder eckig) und eckige Minimap bündig oben rechts
-- mit Gebietsname darüber, Post-Hinweis und eigenen Koordinaten.
--
-- Eckige Karte: Blizzards Minimap bleibt dasselbe Objekt, wird aber aus dem Edit-Mode-System
-- MinimapCluster herausgelöst (SetParent auf UIParent) und oben rechts bündig gesetzt. Den Cluster
-- selbst setzt stray nicht um, er wird nur durchsichtig und mausfrei (Zonentext, Verfolgung,
-- Kalender, Post, Addon-Fach). Alles nur außerhalb des Kampfes; keine Felder auf Blizzard-Frames.
-- Die eckige Karte ist ein Teil der „stray-Oberfläche“: Schalter und Größenregler stehen in hud.lua
-- (Bereich „stray-Oberfläche“), hier nur der Umbau (ns.ApplySquareMinimap).

local _, ns = ...

ns.defaults.squareMinimap = false
ns.defaults.squareMinimapSize = 200

-- Wirksam nur mit Hauptoption „stray-Oberfläche“ (ns.db.strayUI) und eigenem Unterschalter
local function SquareWanted()
    return ns.db and ns.db.strayUI and ns.db.squareMinimap and true or false
end

local ICON = "Interface\\AddOns\\stray\\media\\minimap_icon"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT_BODY = "Fonts\\ARIALN.TTF"

local C = {
    bg     = { 0.051, 0.067, 0.090, 0.92 },
    border = { 0.169, 0.290, 0.451, 1 },
    accent = { 0.353, 0.659, 1.000, 1 },
    text   = { 0.890, 0.914, 0.953, 1 },
    dim    = { 0.435, 0.525, 0.651, 1 },
}

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

-- Eigener Ereignis-Rahmen: unbekannte Ereignisse (je nach Client) werfen keinen Fehler
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

local function SafeOn(event, fn)
    if not eventHandlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return false end
        eventHandlers[event] = {}
    end
    table.insert(eventHandlers[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for _, fn in ipairs(list) do pcall(fn, ...) end
end)

local button = CreateFrame("Button", "strayMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:SetMovable(true)
button:RegisterForClicks("LeftButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:Hide()

-- Aufbau wie die Blizzard-Knöpfe: Hintergrund, Symbol, goldener Ring
local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(24, 24)
background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(18, 18)
icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
icon:SetTexture(ICON)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT", button, "TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

---------------------------------------------------------------------------
-- Position am Rand (rund oder eckig, z. B. mit Leatrix „Square minimap“ oder stray)
---------------------------------------------------------------------------

-- Angedockt (z. B. in der Knopfspalte aus hud.lua)? Dann nicht am Rand platzieren.
local dockParent = nil

local function UpdatePosition()
    if dockParent or not ns.db then return end
    local angle = math.rad(ns.db.minimapAngle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    local w = Minimap:GetWidth() / 2 + 5
    local h = Minimap:GetHeight() / 2 + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        -- Auf das Rechteck projizieren: weiter nach außen schieben, dann an den Kanten begrenzen
        local diagW, diagH = math.sqrt(2) * w - 10, math.sqrt(2) * h - 10
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    else
        x, y = x * w, y * h
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    ns.db.minimapAngle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

button:SetScript("OnDragStart", function(self)
    if dockParent then return end
    self.isMoving = true
    self:LockHighlight()
    self:SetScript("OnUpdate", FollowCursor)
    GameTooltip:Hide()
end)

button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
    self.isMoving = nil
end)

---------------------------------------------------------------------------
-- Klick und Tooltip
---------------------------------------------------------------------------

button:SetScript("OnClick", function()
    if SlashCmdList and SlashCmdList["STRAY"] then SlashCmdList["STRAY"]() end
end)

button:SetScript("OnEnter", function(self)
    if self.isMoving then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddDoubleLine("stray", ns.GetVersion(), 1, 1, 1, 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Linksklick: Optionen öffnen/schließen", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
    if not dockParent then
        GameTooltip:AddLine("Ziehen: am Rand verschieben", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
    end
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Option
---------------------------------------------------------------------------

local function Apply()
    if ns.db.minimapButton then
        UpdatePosition()
        button:Show()
    else
        button:Hide()
    end
end

ns.AddOption(3, "Kamera & Karte", {
    key = "minimapButton",
    label = "Minimap-Knopf anzeigen",
    tooltip = "Runder stray-Knopf am Rand der Minimap. Linksklick öffnet dieses Fenster, mit gedrückter linker Maustaste ziehst du ihn am Rand entlang.\n\n/stray funktioniert weiterhin.",
    set = function(value)
        ns.db.minimapButton = value
        Apply()
        -- hud.lua ordnet die Knopfspalte neu, falls der Knopf dort sitzt
        if ns.OnMinimapButtonOption then pcall(ns.OnMinimapButtonOption) end
    end,
})

---------------------------------------------------------------------------
-- Andocken: hud.lua setzt den Knopf in die Minimap-Knopfspalte
---------------------------------------------------------------------------

local highlight = button:GetHighlightTexture()

-- Knopf füllt danach parent aus (eckig, ohne Ring); Sichtbarkeit folgt der Option
function ns.MinimapButtonDock(parent)
    if not parent then return end
    if dockParent ~= parent then
        dockParent = parent
        button:SetScript("OnUpdate", nil)
        button.isMoving = nil
        button:SetParent(parent)
        button:SetFrameStrata(parent:GetFrameStrata())
        button:SetFrameLevel(parent:GetFrameLevel() + 2)
        button:ClearAllPoints()
        button:SetAllPoints(parent)
        background:Hide()
        border:Hide()
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", button, "CENTER", 0, 0)
        icon:SetSize(16, 16)
        if highlight then highlight:SetAlpha(0) end
    end
    button:SetShown(ns.db and ns.db.minimapButton and true or false)
end

-- Zurück an den Minimap-Rand
function ns.MinimapButtonUndock()
    if not dockParent then return end
    dockParent = nil
    button:SetParent(Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:ClearAllPoints()
    button:SetSize(31, 31)
    background:Show()
    border:Show()
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    icon:SetSize(18, 18)
    if highlight then highlight:SetAlpha(1) end
    if ns.db then Apply() end
end

function ns.IsMinimapButtonDocked()
    return dockParent ~= nil
end

---------------------------------------------------------------------------
-- Eckige Minimap
---------------------------------------------------------------------------

local HEADER_H = 18
local ROUND_MASK = "ui-hud-minimap-frame-generic-mask"            -- Forever (Camelot), Atlas
local ROUND_MASK_FILE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local squareActive = false   -- eckige Karte gerade aufgebaut
local saved = nil            -- Blizzards Zustand der Minimap vor dem Umbau
local prevShape = nil        -- GetMinimapShape vor stray (z. B. von einem anderen Addon)
local mouseOff = {}          -- [Blizzard-Rahmen] = true: Maus von stray abgeschaltet
local alphaOff = {}          -- [Blizzard-Rahmen/Textur] = alter Alpha-Wert
local zoomHooked = {}        -- [Zoomknopf] = true

local function SquareShape() return "SQUARE" end

function ns.IsSquareMinimap()
    return squareActive
end

local function Size()
    local v = tonumber(ns.db and ns.db.squareMinimapSize) or 200
    return math.max(140, math.min(260, math.floor(v + 0.5)))
end

-- 1-px-Rand im stray-Stil an den Innenkanten eines Rahmens
local function AddLines(frame, layer)
    local lines = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4])
        lines[i] = t
    end
    lines[1]:SetPoint("TOPLEFT"); lines[1]:SetPoint("TOPRIGHT"); lines[1]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT"); lines[2]:SetHeight(1)
    lines[3]:SetPoint("TOPLEFT"); lines[3]:SetPoint("BOTTOMLEFT"); lines[3]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT"); lines[4]:SetPoint("BOTTOMRIGHT"); lines[4]:SetWidth(1)
    return lines
end

local function Text(parent, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontHighlightSmall)
    pcall(fs.SetFont, fs, FONT_BODY, size, flags or "")
    fs:SetTextColor(C.text[1], C.text[2], C.text[3])
    return fs
end

-- Rand über der Karte (eigener Rahmen, Kind der Minimap)
local mapBorder = CreateFrame("Frame", nil, Minimap)
mapBorder:SetAllPoints(Minimap)
mapBorder:SetFrameLevel(Minimap:GetFrameLevel() + 5)
AddLines(mapBorder, "OVERLAY")
mapBorder:Hide()

-- Gebietsname über der Karte ---------------------------------------------------

local header = CreateFrame("Button", "strayMinimapHeader", UIParent)
header:SetSize(200, HEADER_H)
header:SetFrameStrata("LOW")
header:RegisterForClicks("LeftButtonUp")
do
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    AddLines(header, "BORDER")
end
header.text = Text(header, 11)
header.text:SetPoint("LEFT", header, "LEFT", 18, 0)
header.text:SetPoint("RIGHT", header, "RIGHT", -18, 0)
header.text:SetJustifyH("CENTER")
header.text:SetWordWrap(false)
header:Hide()

-- Post-Hinweis links im Kopf
local mail = CreateFrame("Frame", nil, header)
mail:SetSize(14, 14)
mail:SetPoint("LEFT", header, "LEFT", 3, 0)
mail.icon = mail:CreateTexture(nil, "ARTWORK")
mail.icon:SetAllPoints()
mail.icon:SetTexture("Interface\\Minimap\\Tracking\\Mailbox")
mail:EnableMouse(true)
mail:Hide()

ns.SquareMinimapTop = function() return squareActive and header or nil end

-- Farben wie Blizzards Zonentext
local PVP_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94 },
    arena     = { 1.0, 0.1, 0.1 },
    combat    = { 1.0, 0.1, 0.1 },
    friendly  = { 0.1, 1.0, 0.1 },
    hostile   = { 1.0, 0.1, 0.1 },
    contested = { 1.0, 0.7, 0.0 },
}

local function UpdateZone()
    if not squareActive then return end
    local zone = GetMinimapZoneText and GetMinimapZoneText()
    if ns.IsSecret(zone) then
        header.text:SetText(zone) -- versiegelt: nur an den Setter weiterreichen
    else
        header.text:SetText(type(zone) == "string" and zone or "")
    end
    local c = C.text
    if GetZonePVPInfo then
        local ok, pvpType = pcall(GetZonePVPInfo)
        pvpType = ok and ns.Public(pvpType)
        if type(pvpType) == "string" and PVP_COLORS[pvpType] then c = PVP_COLORS[pvpType] end
    end
    header.text:SetTextColor(c[1], c[2], c[3])
end

local function UpdateMail()
    if not squareActive or not HasNewMail then mail:Hide() return end
    local ok, has = pcall(HasNewMail)
    mail:SetShown(ok and ns.Public(has) and true or false)
end

header:SetScript("OnClick", function()
    if ToggleWorldMap then pcall(ToggleWorldMap) end
end)
header:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local zone = GetRealZoneText and ns.Public(GetRealZoneText())
    local sub = GetSubZoneText and ns.Public(GetSubZoneText())
    GameTooltip:AddLine(type(zone) == "string" and zone or "Gebiet")
    if type(sub) == "string" and sub ~= "" and sub ~= zone then GameTooltip:AddLine(sub, 1, 1, 1) end
    GameTooltip:AddLine("Linksklick: Weltkarte", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
    GameTooltip:Show()
end)
header:SetScript("OnLeave", function() GameTooltip:Hide() end)

mail:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Neue Post")
    if GetLatestThreeSenders then
        local senders = { pcall(GetLatestThreeSenders) }
        if senders[1] then
            for i = 2, #senders do
                local name = ns.Public(senders[i])
                if type(name) == "string" then GameTooltip:AddLine(name, 1, 1, 1) end
            end
        end
    end
    GameTooltip:Show()
end)
mail:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Koordinaten (Blizzards Anzeige sitzt im ausgeblendeten Cluster) ---------------

local coords = CreateFrame("Frame", "strayMinimapCoords", UIParent)
coords:SetSize(120, 14)
coords:SetFrameStrata("LOW")
coords.text = Text(coords, 11, "OUTLINE")
coords.text:SetPoint("CENTER")
coords:Hide()

ns.SquareMinimapCoords = coords

local function CVarOn(name)
    local ok, v = pcall(ns.GetCVarOn, name)
    return ok and v and true or false
end

local coordTimer = 0
coords:SetScript("OnUpdate", function(self, elapsed)
    coordTimer = coordTimer - elapsed
    if coordTimer > 0 then return end
    coordTimer = 0.2
    local text = ""
    if CVarOn("minimapShowPlayerCoords") and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        mapID = okMap and ns.Public(mapID)
        if type(mapID) == "number" then
            local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
            pos = okPos and ns.Public(pos)
            if type(pos) == "table" and pos.GetXY then
                local okXY, x, y = pcall(pos.GetXY, pos)
                x, y = okXY and ns.Public(x), okXY and ns.Public(y)
                if type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then
                    if CVarOn("coordsByTenths") then
                        text = string.format("%.1f, %.1f", x * 100, y * 100)
                    else
                        text = string.format("%d, %d", math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5))
                    end
                end
            end
        end
    end
    self.text:SetText(text)
end)

-- Blizzard-Teile -----------------------------------------------------------------

local function Cluster() return _G.MinimapCluster end

-- Rahmen des Clusters, die sonst unsichtbar über der eckigen Karte Klicks abfangen
local function ClusterMouseFrames()
    local list = {}
    local cluster = Cluster()
    local function add(f)
        if type(f) == "table" and f.EnableMouse and f.IsMouseEnabled then table.insert(list, f) end
    end
    if cluster then
        add(cluster)
        add(cluster.ZoneTextButton)
        add(cluster.Tracking)
        add(cluster.Tracking and cluster.Tracking.Button)
        add(cluster.IndicatorFrame)
        add(cluster.IndicatorFrame and cluster.IndicatorFrame.MailFrame)
        add(cluster.IndicatorFrame and cluster.IndicatorFrame.CraftingOrderFrame)
        add(cluster.InstanceDifficulty)
        add(cluster.Selection)
    end
    add(_G.GameTimeFrame)
    add(_G.AddonCompartmentFrame)
    add(_G.MinimapZoneTextButton)
    add(_G.MiniMapTracking)
    return list
end

local function SetAlphaSaved(region, alpha)
    if type(region) ~= "table" or not region.SetAlpha then return end
    if alphaOff[region] == nil then alphaOff[region] = region:GetAlpha() or 1 end
    pcall(region.SetAlpha, region, alpha)
end

local function RestoreAlphas()
    for region, alpha in pairs(alphaOff) do
        pcall(region.SetAlpha, region, alpha)
        alphaOff[region] = nil
    end
end

local function ZoomButtons()
    return { Minimap.ZoomIn, Minimap.ZoomOut, _G.MinimapZoomIn, _G.MinimapZoomOut }
end

local function HideZoom()
    for _, z in pairs(ZoomButtons()) do
        if type(z) == "table" and z.Hide then
            pcall(z.Hide, z)
            if not zoomHooked[z] then
                zoomHooked[z] = true
                pcall(z.HookScript, z, "OnShow", function(self)
                    if squareActive then pcall(self.Hide, self) end
                end)
            end
        end
    end
end

local function RingScalars(v)
    for _, fn in ipairs({ "SetQuestBlobRingScalar", "SetArchBlobRingScalar", "SetTaskBlobRingScalar" }) do
        if Minimap[fn] then pcall(Minimap[fn], Minimap, v) end
    end
end

-- Neu zeichnen nach Größenwechsel (sonst sitzen Punkte kurz falsch)
local function RefreshRender()
    local okZ, zoom = pcall(Minimap.GetZoom, Minimap)
    if not okZ or type(zoom) ~= "number" then return end
    local top = (Minimap:GetZoomLevels() or 1) - 1
    local other = (zoom > 0) and (zoom - 1) or math.min(zoom + 1, top)
    if other ~= zoom then
        pcall(Minimap.SetZoom, Minimap, other)
        pcall(Minimap.SetZoom, Minimap, zoom)
    end
end

local function Capture()
    if saved then return end
    saved = {
        parent = Minimap:GetParent(),
        points = {},
        strata = Minimap:GetFrameStrata(),
        level = Minimap:GetFrameLevel(),
    }
    saved.w, saved.h = Minimap:GetSize()
    for i = 1, (Minimap:GetNumPoints() or 0) do
        saved.points[i] = { Minimap:GetPoint(i) }
    end
end

local function LayoutAround()
    if ns.HudLayoutAroundMap then pcall(ns.HudLayoutAroundMap) end
    if not dockParent and ns.db and ns.db.minimapButton then pcall(UpdatePosition) end
end

local pendingApply = false

local function BuildSquare()
    Capture()
    local size = Size()
    if Minimap:GetParent() ~= UIParent then Minimap:SetParent(UIParent) end
    Minimap:SetFrameStrata(saved.strata or "LOW")
    Minimap:SetFrameLevel(math.max(saved.level or 2, 2))

    header:ClearAllPoints()
    header:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    header:SetSize(size, HEADER_H)
    header:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    Minimap:ClearAllPoints()
    -- 1 px Überlappung: Kopf und Karte teilen sich die Randlinie
    Minimap:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 1)
    Minimap:SetSize(size, size)
    pcall(Minimap.SetMaskTexture, Minimap, WHITE)
    RingScalars(0)

    mapBorder:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    mapBorder:Show()

    -- Runde Deko und Cluster ausblenden, Cluster nicht umsetzen
    SetAlphaSaved(_G.MinimapCompassTexture, 0)
    SetAlphaSaved(_G.MinimapCompassTextureUnderlay, 0)
    SetAlphaSaved(Cluster(), 0)
    local cluster = Cluster()
    if cluster and cluster.Selection then SetAlphaSaved(cluster.Selection, 0) end
    for _, f in ipairs(ClusterMouseFrames()) do
        local ok, enabled = pcall(f.IsMouseEnabled, f)
        if ok and enabled and not mouseOff[f] then
            mouseOff[f] = true
            pcall(f.EnableMouse, f, false)
        end
    end
    HideZoom()

    if _G.GetMinimapShape ~= SquareShape then
        prevShape = _G.GetMinimapShape
        _G.GetMinimapShape = SquareShape
    end

    squareActive = true
    header:Show()
    coords:ClearAllPoints()
    coords:SetPoint("TOP", Minimap, "BOTTOM", 0, -3)
    coords:SetWidth(size)
    coords:Show()
    UpdateZone()
    UpdateMail()
    RefreshRender()
    LayoutAround()
end

local function RestoreRound()
    if not saved then return end
    squareActive = false
    header:Hide()
    coords:Hide()
    mapBorder:Hide()

    Minimap:SetParent(saved.parent or UIParent)
    Minimap:ClearAllPoints()
    if #saved.points > 0 then
        for _, p in ipairs(saved.points) do Minimap:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    else
        Minimap:SetPoint("CENTER")
    end
    if saved.w and saved.h then Minimap:SetSize(saved.w, saved.h) end
    if saved.strata then Minimap:SetFrameStrata(saved.strata) end
    if saved.level then Minimap:SetFrameLevel(saved.level) end
    if not pcall(Minimap.SetMaskTexture, Minimap, ROUND_MASK) then
        pcall(Minimap.SetMaskTexture, Minimap, ROUND_MASK_FILE)
    end
    RingScalars(1)

    RestoreAlphas()
    for f in pairs(mouseOff) do
        pcall(f.EnableMouse, f, true)
        mouseOff[f] = nil
    end
    if _G.GetMinimapShape == SquareShape then _G.GetMinimapShape = prevShape end
    prevShape = nil
    saved = nil
    RefreshRender()
    LayoutAround()
end

local function ApplySquare()
    if not ns.db then return end
    if InCombat() then
        pendingApply = true
        return
    end
    pendingApply = false
    if SquareWanted() then
        local ok, err = pcall(BuildSquare)
        if not ok then
            ns.Print("Eckige Minimap ging nicht: " .. tostring(err))
            pcall(RestoreRound)
        end
    elseif squareActive or saved then
        pcall(RestoreRound)
    end
end

SafeOn("PLAYER_REGEN_ENABLED", function()
    if pendingApply then ApplySquare() end
end)

-- hud.lua ruft das beim Umschalten (Hauptoption, Unterschalter, Größe) auf
ns.ApplySquareMinimap = ApplySquare

-- Blizzard setzt die runde Maske neu, wenn sich „Minimap drehen“ ändert
if Cluster() and type(Cluster().UpdateMinimapConfig) == "function" then
    hooksecurefunc(Cluster(), "UpdateMinimapConfig", function()
        if squareActive then
            C_Timer.After(0, function()
                if squareActive then
                    pcall(Minimap.SetMaskTexture, Minimap, WHITE)
                    SetAlphaSaved(_G.MinimapCompassTexture, 0)
                    SetAlphaSaved(_G.MinimapCompassTextureUnderlay, 0)
                end
            end)
        end
    end)
end

for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
    SafeOn(event, UpdateZone)
end
for _, event in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "MAIL_INBOX_UPDATE" }) do
    SafeOn(event, UpdateMail)
end
SafeOn("PLAYER_ENTERING_WORLD", function()
    UpdateZone()
    UpdateMail()
end)

Minimap:HookScript("OnSizeChanged", function()
    if ns.db and ns.db.minimapButton and not dockParent then
        C_Timer.After(0, function() pcall(UpdatePosition) end)
    end
end)

-- Schalter „Eckige Minimap oben rechts“ und Regler „Größe eckige Minimap“: hud.lua, Bereich „stray-Oberfläche“

ns.On("PLAYER_LOGIN", function()
    -- Form früh melden, damit andere Addons ihre Knöpfe gleich richtig setzen
    if SquareWanted() and _G.GetMinimapShape ~= SquareShape then
        prevShape = _G.GetMinimapShape
        _G.GetMinimapShape = SquareShape
    end
    Apply()
    if SquareWanted() then C_Timer.After(0, ApplySquare) end
    -- Andere Addons (z. B. Leatrix) stellen die Minimap-Form evtl. erst nach dem Login um
    C_Timer.After(2, function()
        if ns.db.minimapButton then UpdatePosition() end
    end)
end)
