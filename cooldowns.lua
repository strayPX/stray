-- stray – Abklingzeiten über den Aktionsleisten
-- Nutzt Blizzards eingebauten Cooldown-Manager (EssentialCooldownViewer, UtilityCooldownViewer,
-- BuffIconCooldownViewer) und gestaltet ihn im stray-Stil um: quadratische Symbole, schmaler dunkler
-- Rand, Blizzard-Rahmen/-Masken/-Schatten unsichtbar, große Abklingzeit-Zahl in der Mitte.
-- Welche Fähigkeiten erscheinen, stellt man in Blizzards eigenem Cooldown-Manager ein.
--
-- Position: ein eigener verschiebbarer Anker „strayCooldownAnchor“ (Standard: über den
-- stray-Aktionsleisten bzw. unten mittig). EssentialCooldownViewer hängt daran, der
-- UtilityCooldownViewer direkt darüber. Kein SetParent (die Viewer sind Edit-Mode-Systeme);
-- Position und Größe nur außerhalb des Kampfes, nach Blizzard-Neupositionierungen erneut.
--
-- Taint vermeiden: Blizzards Tabellen werden nicht beschrieben (eigene Merkliste mit schwachen
-- Schlüsseln), Hooks nur per hooksecurefunc, Blizzard-Texturen nur per SetAlpha(0) unsichtbar.
-- Versiegelte Werte („secret values“) werden nie verglichen oder verrechnet.

local _, ns = ...

local IsSecret = ns.IsSecret

local CVAR = "cooldownViewerEnabled"
local GAP = 4            -- Abstand zwischen den Reihen (Pixel)
local DEFAULT_POINT = { "BOTTOM", "BOTTOM", 0, 200 }
local ACCENT = { 0.353, 0.659, 1 }
local BG = { 0.051, 0.067, 0.090 }
local EDGE = { 0.169, 0.290, 0.451 }

-- Symbol-Viewer, die umgestaltet werden (die Balken-Anzeige bleibt, wie sie ist)
local STYLE_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
-- Mögliche Rahmen der stray-Aktionsleisten (oberste zuerst)
local BAR_FRAMES = { "strayAB4", "strayAB3", "strayAB2", "strayAB1",
    "strayActionBar4", "strayActionBar3", "strayActionBar2", "strayActionBar1", "strayActionBars" }
-- Teile des Atlas-Namens, an denen Blizzards Rahmen/Schatten zu erkennen sind
local HIDE_ATLAS = { "cooldownmanager", "border", "shadow", "iconoverlay", "ring" }
-- Bekannte Felder mit Rahmen-Texturen (nur lesen, nie schreiben)
local HIDE_KEYS = { "Border", "IconBorder", "IconOverlay", "Shadow", "DropShadow", "Overlay" }

local styled = setmetatable({}, { __mode = "k" }) -- Symbol → { border = Textur, hidden = { Texturen } }
local hookedViewers = setmetatable({}, { __mode = "k" })
local baseSize = setmetatable({}, { __mode = "k" }) -- Viewer → zuletzt gemessene Symbolbreite
local pendingCombat = false
local scheduled = false
local editModeHooked = false

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function Num(v)
    if IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function Str(v)
    if IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

local function Call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(obj[method], obj, ...)
    if ok then return a, b, c, d, e end
    return nil
end

local function ObjectType(obj)
    if type(obj) ~= "table" then return nil end
    return Str(Call(obj, "GetObjectType"))
end

local function CVarExists()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return false end
    local ok, value = pcall(get, CVAR)
    return ok and value ~= nil
end

local function Available()
    if _G.EssentialCooldownViewer or _G.UtilityCooldownViewer or _G.BuffIconCooldownViewer then return true end
    if C_CooldownViewer then return true end
    return CVarExists()
end

local function Enabled()
    return ns.db and ns.db.cdManager and Available() and true or false
end

local function Size()
    local v = tonumber(ns.db and ns.db.cdSize) or 36
    return math.max(24, math.min(56, math.floor(v + 0.5)))
end

-- Darf ein Viewer jetzt bewegt/skaliert werden? Im Kampf grundsätzlich nicht –
-- auch ungeschützte Viewer nicht, damit Blizzards Edit Mode nicht mitten im Kampf gestört wird.
local function MayTouch()
    return not InCombatLockdown()
end

---------------------------------------------------------------------------
-- Anker
---------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "strayCooldownAnchor", UIParent)
anchor:SetSize(240, 80)
anchor:SetFrameStrata("LOW")
anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
anchor:Hide()
ns.MakeMovable(anchor, "cooldowns", DEFAULT_POINT)
anchor:EnableMouse(false)
-- Shift + Ziehen nur außerhalb des Kampfes (die Viewer hängen am Anker)
anchor:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    if IsShiftKeyDown() then self:StartMoving() end
end)

anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
anchor.bg:SetAllPoints()
anchor.bg:SetColorTexture(BG[1], BG[2], BG[3], 0.6)
anchor.edges = {}
for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local edge = anchor:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
    if side == "TOP" or side == "BOTTOM" then
        edge:SetPoint(side .. "LEFT"); edge:SetPoint(side .. "RIGHT"); edge:SetHeight(1)
    else
        edge:SetPoint("TOP" .. side); edge:SetPoint("BOTTOM" .. side); edge:SetWidth(1)
    end
    table.insert(anchor.edges, edge)
end
anchor.label = anchor:CreateFontString(nil, "OVERLAY")
anchor.label:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
anchor.label:SetTextColor(EDGE[1] + 0.5, EDGE[2] + 0.5, EDGE[3] + 0.4)
anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
anchor.label:SetText("Abklingzeiten (Shift + Ziehen)")

local function SetAnchorVisual(on)
    anchor.bg:SetShown(on)
    for _, edge in ipairs(anchor.edges) do edge:SetShown(on) end
    anchor.label:SetShown(on)
end
SetAnchorVisual(false)

ns.RegisterMovable(anchor, "Abklingzeiten")

local function FindBarFrame()
    for _, name in ipairs(BAR_FRAMES) do
        local f = _G[name]
        if type(f) == "table" and Call(f, "IsShown") then return f end
    end
    return nil
end

local function PlaceAnchor()
    if ns.db and ns.db.positions and ns.db.positions.cooldowns then
        pcall(ns.RestorePosition, anchor)
        return
    end
    local bars = FindBarFrame()
    anchor:ClearAllPoints()
    if bars then
        anchor:SetPoint("BOTTOM", bars, "TOP", 0, 8)
    else
        anchor:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

---------------------------------------------------------------------------
-- Symbole umgestalten
---------------------------------------------------------------------------

local function Items(viewer)
    local list, seen = {}, {}
    local function add(f)
        if type(f) == "table" and not seen[f] and ObjectType(f) and (f.Cooldown or f.Icon) then
            seen[f] = true
            table.insert(list, f)
        end
    end
    if type(viewer.GetItemFrames) == "function" then
        local ok, frames = pcall(viewer.GetItemFrames, viewer)
        if ok and type(frames) == "table" then
            for _, f in pairs(frames) do add(f) end
        end
    end
    local ok, kids = pcall(function() return { viewer:GetChildren() } end)
    if ok and kids then
        for _, f in ipairs(kids) do add(f) end
    end
    return list
end

local function IconTexture(item)
    local icon = item.Icon
    local t = ObjectType(icon)
    if t and t ~= "Texture" and type(icon.Icon) == "table" then
        icon = icon.Icon
        t = ObjectType(icon)
    end
    if t == "Texture" then return icon end
    return nil
end

local function ShouldHide(region, item, icon)
    if region == icon or region == item.DebuffBorder then return false end
    if ObjectType(region) ~= "Texture" then return false end
    for _, key in ipairs(HIDE_KEYS) do
        if item[key] == region then return true end
    end
    local atlas = Str(Call(region, "GetAtlas"))
    if atlas then
        atlas = atlas:lower()
        for _, part in ipairs(HIDE_ATLAS) do
            if atlas:find(part, 1, true) then return true end
        end
    end
    return false
end

-- 1 Bildschirmpixel in Einheiten des Symbols
local function OnePixel(item)
    local es = Num(Call(item, "GetEffectiveScale"))
    local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and Num(select(2, pcall(PixelUtil.GetPixelToUIUnitFactor)))
    if not es or es <= 0 then return 1 end
    return (factor or 1) / es
end

local function StyleItem(item)
    local icon = IconTexture(item)
    local data = styled[item]
    if not data then
        data = { hidden = {} }
        styled[item] = data
        -- Blizzard-Rahmen, -Schatten und -Masken finden
        local ok, regions = pcall(function() return { item:GetRegions() } end)
        if ok and regions then
            for _, region in ipairs(regions) do
                if ShouldHide(region, item, icon) then table.insert(data.hidden, region) end
            end
        end
        for _, key in ipairs(HIDE_KEYS) do
            local r = item[key]
            if r and ObjectType(r) == "Texture" and r ~= icon then
                local dup = false
                for _, h in ipairs(data.hidden) do if h == r then dup = true break end end
                if not dup then table.insert(data.hidden, r) end
            end
        end
        if icon then
            -- Runde Maske entfernen → quadratisches Symbol
            local n = Num(Call(icon, "GetNumMaskTextures")) or 0
            for i = n, 1, -1 do
                local mask = Call(icon, "GetMaskTexture", i)
                if mask then Call(icon, "RemoveMaskTexture", mask) end
            end
            -- Schmaler dunkler Rand hinter dem Symbol
            local border = item:CreateTexture(nil, "BACKGROUND", nil, -8)
            border:SetColorTexture(0, 0, 0, 0.95)
            data.border = border
        end
    end

    for _, region in ipairs(data.hidden) do Call(region, "SetAlpha", 0) end

    if icon then
        Call(icon, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
        if data.border then
            local px = OnePixel(item)
            data.border:ClearAllPoints()
            data.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -px, px)
            data.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", px, -px)
        end
    end

    local cd = item.Cooldown
    if ObjectType(cd) == "Cooldown" then
        Call(cd, "SetHideCountdownNumbers", false)
        Call(cd, "SetSwipeTexture", "Interface\\Buttons\\WHITE8X8")
        local fs = Call(cd, "GetCountdownFontString")
        if fs then
            local w = Num(Call(item, "GetWidth")) or 36
            local size = math.max(10, math.floor(w * 0.45 + 0.5))
            Call(fs, "SetFont", STANDARD_TEXT_FONT, size, "OUTLINE")
            Call(fs, "ClearAllPoints")
            Call(fs, "SetPoint", "CENTER", cd, "CENTER", 0, 0)
        end
    end
end

local function StyleViewer(viewer)
    if InCombatLockdown() and Call(viewer, "IsProtected") then
        pendingCombat = true
        return
    end
    for _, item in ipairs(Items(viewer)) do pcall(StyleItem, item) end
end

---------------------------------------------------------------------------
-- Größe und Position
---------------------------------------------------------------------------

-- Breite eines Symbols in Einheiten des Viewers (inkl. Blizzards eigener Symbolskalierung)
local function Measure(viewer)
    for _, item in ipairs(Items(viewer)) do
        local w = Num(Call(item, "GetWidth"))
        local s = Num(Call(item, "GetScale")) or 1
        if w and w > 1 then return w * s end
    end
    return nil
end

local function ApplyScale(viewer)
    local base = Measure(viewer) or baseSize[viewer]
    if not base then return end
    baseSize[viewer] = base
    local scale = math.max(0.3, math.min(3, Size() / base))
    local current = Num(Call(viewer, "GetScale")) or 1
    if math.abs(current - scale) > 0.001 then Call(viewer, "SetScale", scale) end
end

-- Hängt frame mit point an relTo/relPoint – nur, wenn es nicht schon so hängt
local function Attach(frame, point, relTo, relPoint, x, y)
    local num = Num(Call(frame, "GetNumPoints")) or 0
    if num == 1 then
        local p, r, rp, px, py = Call(frame, "GetPoint", 1)
        if Str(p) == point and not IsSecret(r) and r == relTo and Str(rp) == relPoint
            and Num(px) and Num(py) and math.abs(px - x) < 0.01 and math.abs(py - y) < 0.01 then
            return
        end
    end
    Call(frame, "ClearAllPoints")
    Call(frame, "SetPoint", point, relTo, relPoint, x, y)
end

-- Größe eines Viewers in Einheiten des Ankers
local function EffectiveSize(viewer)
    local w = Num(Call(viewer, "GetWidth"))
    local h = Num(Call(viewer, "GetHeight"))
    local es = Num(Call(viewer, "GetEffectiveScale"))
    local as = Num(anchor:GetEffectiveScale())
    if not (w and h and es and as) or as <= 0 then return 0, 0 end
    return w * es / as, h * es / as
end

local function Layout()
    local essential = _G.EssentialCooldownViewer
    local utility = _G.UtilityCooldownViewer
    local size = Size()
    local width, height = size * 4, 0

    if type(essential) == "table" then
        if not MayTouch() then pendingCombat = true return end
        ApplyScale(essential)
        Attach(essential, "BOTTOM", anchor, "BOTTOM", 0, 0)
        local w, h = EffectiveSize(essential)
        width = math.max(width, w)
        height = height + h
    end
    if type(utility) == "table" then
        if not MayTouch() then pendingCombat = true return end
        ApplyScale(utility)
        local scale = Num(Call(utility, "GetScale")) or 1
        if scale <= 0 then scale = 1 end
        if type(essential) == "table" then
            Attach(utility, "BOTTOM", essential, "TOP", 0, GAP / scale)
            height = height + GAP
        else
            Attach(utility, "BOTTOM", anchor, "BOTTOM", 0, 0)
        end
        local w, h = EffectiveSize(utility)
        width = math.max(width, w)
        height = height + h
    end
    anchor:SetSize(math.max(width, size), math.max(height, size))
end

---------------------------------------------------------------------------
-- Anwenden
---------------------------------------------------------------------------

local Schedule

local function EnsureCVar()
    if InCombatLockdown() or not CVarExists() then return end
    local ok, on = pcall(ns.GetCVarOn, CVAR)
    if ok and not IsSecret(on) and on ~= true then
        -- Merken, dass stray die Blizzard-Anzeige eingeschaltet hat (beim Ausschalten wieder aus)
        if pcall(ns.SetCVarValue, CVAR, "1") then ns.db.cdCVarByStray = true end
    end
end

local function HookViewer(viewer)
    if hookedViewers[viewer] then return end
    hookedViewers[viewer] = true
    for _, method in ipairs({ "RefreshLayout", "Layout", "OnAcquireItemFrame", "RefreshData" }) do
        if type(viewer[method]) == "function" then
            pcall(hooksecurefunc, viewer, method, function() Schedule() end)
        end
    end
    -- Neu eingeblendet (z. B. Sichtbarkeit „Im Kampf“): nur Optik nachziehen
    pcall(viewer.HookScript, viewer, "OnShow", function() Schedule() end)
end

local function HookEditMode()
    if editModeHooked or type(EditModeManagerFrame) ~= "table" then return end
    editModeHooked = true
    for _, method in ipairs({ "ExitEditMode", "UpdateLayoutInfo" }) do
        if type(EditModeManagerFrame[method]) == "function" then
            pcall(hooksecurefunc, EditModeManagerFrame, method, function() Schedule(0.2) end)
        end
    end
end

local function UpdateAnchorVisual()
    if InCombatLockdown() then pendingCombat = true return end
    local open = Enabled() and ns.IsConfigOpen()
    SetAnchorVisual(open)
    anchor:EnableMouse(open and true or false)
end

local placePending = true -- Anker neu setzen (nicht bei jedem Blizzard-Neuaufbau, sonst springt er beim Ziehen)

local function Apply()
    if not ns.db then return end
    if not Enabled() then
        if InCombatLockdown() then pendingCombat = true return end
        anchor:Hide()
        return
    end
    -- Optik geht auch im Kampf (ungeschützte Texturen), Position/Größe nicht
    for _, name in ipairs(STYLE_VIEWERS) do
        local viewer = _G[name]
        if type(viewer) == "table" then
            HookViewer(viewer)
            StyleViewer(viewer)
        end
    end
    HookEditMode()
    if InCombatLockdown() then
        pendingCombat = true
        return
    end
    pendingCombat = false
    EnsureCVar()
    anchor:Show()
    if placePending then
        placePending = false
        pcall(PlaceAnchor)
    end
    pcall(Layout)
    UpdateAnchorVisual()
end

-- Gebündelt und leicht verzögert anwenden (Blizzard ordnet oft mehrfach hintereinander neu an).
-- place = true setzt zusätzlich den Anker neu (Anmeldung, Fenster zu, Option geändert).
function Schedule(delay, place)
    if place then placePending = true end
    if scheduled then return end
    scheduled = true
    C_Timer.After(delay or 0.05, function()
        scheduled = false
        pcall(Apply)
    end)
end

local function ApplySoonAndLater()
    Schedule(nil, true)
    C_Timer.After(1, function() placePending = true; pcall(Apply) end)
    C_Timer.After(3, function() placePending = true; pcall(Apply) end)
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function() ApplySoonAndLater() end)
ns.On("PLAYER_ENTERING_WORLD", function() ApplySoonAndLater() end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if pendingCombat then Schedule() end
end)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_CooldownViewer" or name == "Blizzard_EditMode" then ApplySoonAndLater() end
end)

-- Ereignisse, die es nicht in jedem Client gibt, einzeln und abgesichert anmelden
local extraEvents = CreateFrame("Frame")
for _, event in ipairs({ "EDIT_MODE_LAYOUTS_UPDATED", "COOLDOWN_VIEWER_DATA_LOADED" }) do
    pcall(extraEvents.RegisterEvent, extraEvents, event)
end
extraEvents:SetScript("OnEvent", function() ApplySoonAndLater() end)

ns.OnConfig(function(open)
    if not ns.db then return end
    UpdateAnchorVisual()
    -- Fenster/Bearbeiten-Modus zu: Position (z. B. nach „zurücksetzen“) neu anwenden
    if not open then Schedule(nil, true) end
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

local NOT_AVAILABLE = "Diese Spielversion hat Blizzards Cooldown-Manager nicht."

local function UnavailableReason()
    if not (C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable) then return nil end
    local ok, available, reason = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
    if ok and available == false and not IsSecret(reason) and type(reason) == "string" and reason ~= "" then
        return reason
    end
    return nil
end

ns.AddOption(2, "Abklingzeiten", {
    key = "cdManager",
    label = "Abklingzeiten über den Leisten",
    tooltip = "Zeigt über den Aktionsleisten eine Reihe mit deinen wichtigen Fähigkeiten und ihren Abklingzeiten – große Restzeit in der Mitte jedes Symbols.\n\nDafür nutzt stray Blizzards eingebauten Cooldown-Manager und schaltet ihn ein. Welche Fähigkeiten er zeigt (und ob immer oder nur im Kampf), stellst du in Blizzards eigenem Cooldown-Manager-Fenster bzw. im Edit Mode ein (Spielmenü). stray gestaltet ihn nur um (quadratische Symbole, schmaler Rand) und platziert ihn: wichtige Fähigkeiten unten, weitere direkt darüber.\n\nVerschieben mit Shift + Ziehen bei offenem stray-Fenster oder im Bearbeiten-Modus. Position und Größe ändern sich nur außerhalb des Kampfes.\n\nAusschalten: Blizzards eigene Optik und Position kommen erst nach /reload zurück.",
    isEnabled = function() return Available() end,
    disabledHint = NOT_AVAILABLE,
    set = function(value)
        ns.db.cdManager = value
        if value then
            if InCombatLockdown() then ns.Print("Abklingzeiten: Die Änderung gilt nach dem Kampf.") end
            local reason = UnavailableReason()
            if reason then ns.Print("Abklingzeiten: " .. reason) end
        else
            -- Hat stray Blizzards Cooldown-Manager eingeschaltet, schaltet stray ihn auch wieder aus
            if ns.db.cdCVarByStray and CVarExists() and not InCombatLockdown() then
                pcall(ns.SetCVarValue, CVAR, "0")
                ns.db.cdCVarByStray = nil
            end
            ns.Print("Abklingzeiten: Blizzards eigene Optik kommt nach /reload zurück.")
        end
        Schedule(nil, true)
    end,
})

ns.AddOption(2, "Abklingzeiten", {
    key = "cdSize",
    type = "slider",
    label = "Symbolgröße",
    min = 24, max = 56, step = 1,
    tooltip = "Größe der Abklingzeit-Symbole in Pixeln. Im Kampf wird die Änderung erst danach übernommen.",
    isEnabled = function() return Enabled() end,
    disabledHint = "Erst „Abklingzeiten über den Leisten“ einschalten.",
    set = function(v)
        ns.db.cdSize = v
        if InCombatLockdown() then pendingCombat = true return end
        Schedule()
    end,
})
