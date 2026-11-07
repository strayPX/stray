-- stray – Bearbeiten-Modus
-- Blendet alle eingeschalteten stray-Anzeigen mit Beispielinhalt ein und macht sie ohne Shift
-- verschiebbar: blaue Fläche mit Namen darüber, ziehen zum Verschieben, Rechtsklick setzt eine
-- Anzeige zurück. Oben eine Leiste mit Raster, „Alles zurücksetzen“ und „Fertig“.
-- Nur außerhalb des Kampfes (die Gruppenrahmen hängen an Blizzards geschützten Rahmen).

local _, ns = ...

local GRID = 8 -- Raster in Pixeln (Einrasten beim Loslassen)
local ACCENT = { 0.353, 0.659, 1 }

local overlays = {}
local bar, grid
local snapping = true
local ticker

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function Round(v)
    return math.floor(v / GRID + 0.5) * GRID
end

local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    if not point then return end
    if snapping then x, y = Round(x), Round(y) end
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relPoint, x, y)
    ns.db.positions[frame.strayKey] = { point, relPoint, x, y }
end

local function ResetPosition(frame)
    ns.db.positions[frame.strayKey] = nil
    ns.RestorePosition(frame)
end

local function Text(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
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
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = o:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT"); edge:SetPoint(side .. "RIGHT"); edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side); edge:SetPoint("BOTTOM" .. side); edge:SetWidth(1)
        end
    end

    o.label = Text(o, 12)
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
-- Raster und Leiste
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

local function BarButton(label, width, onClick)
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(width, 24)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.05)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.text = Text(b, 12)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", onClick)
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

local ExitEditMode

local function CreateBar()
    bar = CreateFrame("Frame", "strayEditBar", UIParent)
    bar:SetSize(620, 40)
    bar:SetPoint("TOP", 0, -12)
    bar:SetFrameStrata("TOOLTIP")
    bar:EnableMouse(true)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.051, 0.067, 0.090, 0.95)
    local line = bar:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(2)
    line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)

    local title = Text(bar, 13, ACCENT[1], ACCENT[2], ACCENT[3])
    title:SetPoint("LEFT", 12, 6)
    title:SetText("stray · Bearbeiten-Modus")
    local hint = Text(bar, 10, 0.75, 0.8, 0.9)
    hint:SetPoint("LEFT", 12, -8)
    hint:SetText("Ziehen zum Verschieben · Rechtsklick setzt zurück · Bedrohung, Schadensmesser und Haltbarkeit nur, wenn eingeschaltet")

    local done = BarButton("Fertig", 70, function() ExitEditMode() end)
    done:SetPoint("RIGHT", -8, 0)
    local reset = BarButton("Alles zurücksetzen", 130, function() StaticPopup_Show("STRAY_EDIT_RESET") end)
    reset:SetPoint("RIGHT", done, "LEFT", -6, 0)
    local gridButton
    gridButton = BarButton("Raster: an", 84, function()
        snapping = not snapping
        grid:SetShown(snapping)
        gridButton.text:SetText(snapping and "Raster: an" or "Raster: aus")
    end)
    gridButton:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    bar:Hide()
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
    bar:Show()
    grid:SetShown(snapping)
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
    tooltip = "Blendet alle eingeschalteten stray-Anzeigen ein und macht sie frei verschiebbar – ohne Shift. Rechtsklick auf eine Anzeige setzt sie auf ihre Standardposition zurück, „Fertig“ beendet den Modus.\n\nBetrifft Gruppenrahmen, Bedrohungsliste, Schadensmesser, Haltbarkeit und die Warntexte. Geht nur außerhalb des Kampfes. Auch per /stray edit.",
    onClick = function() ns.EnterEditMode() end,
})
