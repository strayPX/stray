-- stray – Minimap-Knopf: öffnet das stray-Fenster, lässt sich am Rand entlang verschieben

local _, ns = ...

local ICON = "Interface\\AddOns\\stray\\media\\minimap_icon"

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
-- Position am Rand (rund oder eckig, z. B. mit Leatrix „Square minimap“)
---------------------------------------------------------------------------

-- Angedockt (z. B. in der Knopfspalte aus hud.lua)? Dann nicht am Rand platzieren.
local dockParent = nil

local function UpdatePosition()
    if dockParent then return end
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

ns.On("PLAYER_LOGIN", function()
    Apply()
    -- Andere Addons (z. B. Leatrix) stellen die Minimap-Form evtl. erst nach dem Login um
    C_Timer.After(2, function()
        if ns.db.minimapButton then UpdatePosition() end
    end)
end)
