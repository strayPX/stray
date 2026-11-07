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

local function UpdatePosition()
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
    GameTooltip:AddLine("Ziehen: am Rand verschieben", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
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
    end,
})

ns.On("PLAYER_LOGIN", function()
    Apply()
    -- Andere Addons (z. B. Leatrix) stellen die Minimap-Form evtl. erst nach dem Login um
    C_Timer.After(2, function()
        if ns.db.minimapButton then UpdatePosition() end
    end)
end)
