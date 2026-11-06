-- stray – Kamera & Karte: maximale Kamera-Entfernung, Minimap per Mausrad zoomen

local _, ns = ...

---------------------------------------------------------------------------
-- Kamera
---------------------------------------------------------------------------

local ZOOM_CVAR = "cameraDistanceMaxZoomFactor"
local ZOOM_TRY = { 4, 3.4, 2.6 } -- höchster Wert zuerst; der Client nimmt, was er erlaubt

local function GetDefault(name)
    local getDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    return getDefault and getDefault(name)
end

local function GetNumber(name)
    local getValue = (C_CVar and C_CVar.GetCVar) or GetCVar
    return tonumber(getValue(name))
end

local function ApplyCamera(turnedOff)
    if ns.db.cameraMax then
        -- Der Client lehnt zu hohe Werte ab oder kürzt sie auf sein Maximum.
        -- Sobald der Wert über dem Standard liegt, ist das Maximum erreicht.
        local default = tonumber(GetDefault(ZOOM_CVAR)) or 1
        for _, value in ipairs(ZOOM_TRY) do
            pcall(ns.SetCVarValue, ZOOM_CVAR, tostring(value))
            local now = GetNumber(ZOOM_CVAR)
            if now and now > default + 0.01 then break end
        end
    elseif turnedOff then
        -- Nur beim Ausschalten zurücksetzen, sonst bleibt eine eigene Einstellung erhalten
        local default = GetDefault(ZOOM_CVAR)
        if default then ns.SetCVarValue(ZOOM_CVAR, default) end
    end
end

ns.AddOption(3, "Kamera & Karte", {
    key = "cameraMax",
    label = "Maximale Kamera-Entfernung",
    tooltip = "Du kannst so weit herauszoomen, wie das Spiel erlaubt – deutlich weiter als normal. Ausschalten stellt den Blizzard-Standard wieder her.",
    set = function(value)
        ns.db.cameraMax = value
        ApplyCamera(not value)
    end,
})

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

local zoomButtons = { MinimapZoomIn, MinimapZoomOut }

-- Hat der Client schon selbst einen Mausrad-Zoom, nicht doppelt zoomen
local nativeWheel = Minimap:GetScript("OnMouseWheel") ~= nil

local function SyncButtons()
    local zoom, top = Minimap:GetZoom(), Minimap:GetZoomLevels() - 1
    if MinimapZoomIn then MinimapZoomIn:SetEnabled(zoom < top) end
    if MinimapZoomOut then MinimapZoomOut:SetEnabled(zoom > 0) end
end

local function OnMinimapWheel(self, delta)
    if not ns.db or not ns.db.minimapWheel then return end
    local zoom = self:GetZoom()
    if delta > 0 and zoom < self:GetZoomLevels() - 1 then
        self:SetZoom(zoom + 1)
    elseif delta < 0 and zoom > 0 then
        self:SetZoom(zoom - 1)
    end
end

local function ApplyMinimap(toggled)
    local on = ns.db.minimapWheel
    -- Ist die Option aus, beim Einloggen nichts anfassen (andere Addons nicht stören)
    if not on and not toggled then return end
    if on then
        Minimap:EnableMouseWheel(true)
    elseif not nativeWheel then
        Minimap:EnableMouseWheel(false)
    end
    for _, button in pairs(zoomButtons) do
        if on then button:Hide() else button:Show() end
    end
    if not on then SyncButtons() end
end

if not nativeWheel then
    Minimap:SetScript("OnMouseWheel", OnMinimapWheel)
end
for _, button in pairs(zoomButtons) do
    -- Falls Blizzard die Knöpfe wieder einblendet
    button:HookScript("OnShow", function(self)
        if ns.db and ns.db.minimapWheel then self:Hide() end
    end)
end

ns.AddOption(3, "Kamera & Karte", {
    key = "minimapWheel",
    label = "Minimap mit Mausrad zoomen",
    tooltip = "Mausrad über der Minimap zoomt hinein und heraus. Die Plus- und Minus-Knöpfe werden dafür ausgeblendet.",
    set = function(value)
        ns.db.minimapWheel = value
        ApplyMinimap(true)
    end,
})

ns.On("PLAYER_LOGIN", function()
    ApplyCamera(false)
    ApplyMinimap(false)
end)
