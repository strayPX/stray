-- stray – Gruppenrahmen für Heiler: du + party1–4 als senkrechte Spalte (kein Schlachtzug)
--
-- Aufbau:
--   strayPartyAnchor  – nicht-sicherer Container, mit Shift + Ziehen verschiebbar (nur außerhalb des Kampfes)
--   strayPartyHeader  – Blizzards SecureGroupHeaderTemplate; legt die Knöpfe selbst an und weist
--                       ihnen die Einheiten zu (auch im Kampf). Linksklick = Ziel, Rechtsklick = Menü.
-- Alles Geschützte (SetAttribute, Show/Hide, SetSize, SetPoint, SetParent sicherer Rahmen) läuft
-- nur außerhalb des Kampfes; im Kampf gewünschte Änderungen werden bei PLAYER_REGEN_ENABLED nachgeholt.
--
-- WoW Forever kann Werte versiegeln („secret values“). Versiegelte Werte werden nie verglichen
-- oder verrechnet, sondern nur an Anzeige-Funktionen (SetText, SetValue, SetTexture …) in pcall
-- weitergereicht. Die Optik jeder Kachel liegt in einem nicht-sicheren Unterrahmen („art“).

local _, ns = ...

local IsSecret = ns.IsSecret
local Public = ns.Public

local POWER_H = 4
local MAX_TILES = 5
local FADED = 0.4
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local FALLBACK_DEBUFF_COLORS = {
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}
local NEUTRAL_BORDER = { 0.9, 0.9, 0.9 }

local function Dims()
    local db = ns.db or ns.defaults
    local w = tonumber(db.partyWidth) or 96
    local h = tonumber(db.partyHeight) or 42
    local sp = tonumber(db.partySpacing) or 4
    w = math.max(60, math.min(200, math.floor(w + 0.5)))
    h = math.max(24, math.min(80, math.floor(h + 0.5)))
    sp = math.max(0, math.min(20, math.floor(sp + 0.5)))
    return w, h, sp
end

local function Enabled()
    return ns.db and ns.db.partyFrames and true or false
end

local function ClassColor(class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return 0.2, 0.75, 0.3
end

local function DebuffColor(dispelName)
    local colors = DebuffTypeColor or FALLBACK_DEBUFF_COLORS
    local c = colors[dispelName] or FALLBACK_DEBUFF_COLORS[dispelName]
    if c then return c.r, c.g, c.b end
    return NEUTRAL_BORDER[1], NEUTRAL_BORDER[2], NEUTRAL_BORDER[3]
end

local function PowerColor(powerType, powerToken)
    local colors = PowerBarColor
    local c = colors and ((powerToken and colors[powerToken]) or (powerType and colors[powerType]))
    if c and c.r then return c.r, c.g, c.b end
    return 0.2, 0.4, 1
end

---------------------------------------------------------------------------
-- Anker
---------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "strayPartyAnchor", UIParent)
anchor:SetPoint("CENTER", UIParent, "CENTER", -220, 0)
anchor:SetSize(96, 5 * 42 + 4 * 4)
ns.MakeMovable(anchor, "party", { "CENTER", "CENTER", -220, 0 })
-- Der Anker selbst fängt keine Klicks ab; gezogen wird über die Kacheln
anchor:EnableMouse(false)
anchor:Hide()

local moving = false

local function StartDrag()
    if moving or not IsShiftKeyDown() or InCombatLockdown() then return end
    if pcall(anchor.StartMoving, anchor) then moving = true end
end

local stopPending = false

local function StopDrag()
    if not moving then return end
    -- Im Kampf ist der Anker über den sicheren Header geschützt: Abschluss nach dem Kampf
    if InCombatLockdown() then
        stopPending = true
        return
    end
    moving, stopPending = false, false
    local onStop = anchor:GetScript("OnDragStop") -- aus ns.MakeMovable: anhalten und Position speichern
    if onStop then pcall(onStop, anchor) else pcall(anchor.StopMovingOrSizing, anchor) end
end

---------------------------------------------------------------------------
-- Kachel-Optik (für echte Knöpfe und Beispielkacheln gleich)
---------------------------------------------------------------------------

local function MakeBorder(parent, thickness, offset, layer, sublevel)
    local b = {}
    for i = 1, 4 do
        b[i] = parent:CreateTexture(nil, layer, nil, sublevel)
        b[i]:SetColorTexture(1, 1, 1, 1)
    end
    local top, bottom, left, right = b[1], b[2], b[3], b[4]
    top:SetPoint("TOPLEFT", -offset, offset); top:SetPoint("TOPRIGHT", offset, offset); top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", -offset, -offset); bottom:SetPoint("BOTTOMRIGHT", offset, -offset); bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", -offset, offset); left:SetPoint("BOTTOMLEFT", -offset, -offset); left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", offset, offset); right:SetPoint("BOTTOMRIGHT", offset, -offset); right:SetWidth(thickness)
    function b:SetColor(r, g, bl, a)
        for i = 1, 4 do self[i]:SetVertexColor(r, g, bl, a or 1) end
    end
    function b:SetShown(show)
        for i = 1, 4 do self[i]:SetShown(show) end
    end
    b:SetShown(false)
    return b
end

-- Baut die Optik in einen nicht-sicheren Rahmen „art“ über dem Elternrahmen
local function BuildTile(parent)
    local art = CreateFrame("Frame", nil, parent)
    art:SetAllPoints(parent)
    art:SetFrameLevel(parent:GetFrameLevel() + 1)

    local t = { art = art }

    t.bg = art:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.bg:SetColorTexture(0.05, 0.06, 0.08, 0.9)

    t.power = CreateFrame("StatusBar", nil, art)
    t.power:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 1, 1)
    t.power:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -1, 1)
    t.power:SetHeight(POWER_H)
    t.power:SetStatusBarTexture(BAR_TEXTURE)
    t.power:SetMinMaxValues(0, 1)
    t.power:SetValue(1)
    local powerBg = t.power:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints()
    powerBg:SetColorTexture(0, 0, 0, 0.6)

    t.health = CreateFrame("StatusBar", nil, art)
    t.health:SetPoint("TOPLEFT", art, "TOPLEFT", 1, -1)
    t.health:SetPoint("BOTTOMRIGHT", t.power, "TOPRIGHT", 0, 1)
    t.health:SetStatusBarTexture(BAR_TEXTURE)
    t.health:SetMinMaxValues(0, 1)
    t.health:SetValue(1)
    local healthBg = t.health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints()
    healthBg:SetColorTexture(0.12, 0.12, 0.14, 0.9)

    -- Texte und Symbol über den Balken
    local top = CreateFrame("Frame", nil, art)
    top:SetAllPoints(art)
    top:SetFrameLevel(t.health:GetFrameLevel() + 2)
    t.top = top

    t.name = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.name:SetPoint("TOPLEFT", top, "TOPLEFT", 4, -4)
    t.name:SetPoint("TOPRIGHT", top, "TOPRIGHT", -34, -4)
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(false)
    t.name:SetShadowOffset(1, -1)

    t.pct = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.pct:SetPoint("TOPRIGHT", top, "TOPRIGHT", -4, -4)
    t.pct:SetJustifyH("RIGHT")
    t.pct:SetTextColor(0.85, 0.85, 0.85)
    t.pct:SetShadowOffset(1, -1)

    t.status = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.status:SetPoint("TOPRIGHT", top, "TOPRIGHT", -4, -4)
    t.status:SetJustifyH("RIGHT")
    t.status:SetTextColor(1, 0.35, 0.35)
    t.status:SetShadowOffset(1, -1)

    t.icon = top:CreateTexture(nil, "OVERLAY")
    t.icon:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", -2, 2)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.icon:Hide()

    t.dispel = MakeBorder(top, 2, 0, "OVERLAY", 6)
    t.target = MakeBorder(top, 1, 1, "OVERLAY", 7)
    t.target:SetColor(1, 1, 1, 0.9)
    return t
end

local function ResizeTile(t, h)
    local size = math.max(10, math.min(18, math.floor(h * 0.38)))
    t.icon:SetSize(size, size)
end

---------------------------------------------------------------------------
-- Werte einer echten Einheit in die Kachel schreiben (alles einzeln in pcall)
---------------------------------------------------------------------------

local function PaintName(t, unit)
    local name = UnitName(unit)
    if not pcall(t.name.SetText, t.name, name) then t.name:SetText("") end
end

-- Gibt zurück: Statustext oder nil (versiegelt → kein Status)
local function StatusText(unit)
    local connected = UnitIsConnected(unit)
    if not IsSecret(connected) and connected == false then return "Offline" end
    local dead = UnitIsDeadOrGhost(unit)
    if not IsSecret(dead) and dead then
        local ghost = UnitIsGhost(unit)
        if not IsSecret(ghost) and ghost then return "Geist" end
        return "Tot"
    end
    return nil
end

local function SetPercent(t, unit)
    -- Lesbare Werte: selbst rechnen
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if not IsSecret(cur) and not IsSecret(max) and type(cur) == "number" and type(max) == "number" then
        if max > 0 then
            t.pct:SetText(("%.0f%%"):format(cur / max * 100))
            return true
        end
        return false
    end
    -- Versiegelt: Blizzard rechnet (UnitHealthPercent mit Kurve 0–100), wir formatieren nur
    if not UnitHealthPercent then return false end
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if curve then
        local ok, value = pcall(UnitHealthPercent, unit, true, curve)
        if not ok then return false end
        if not IsSecret(value) then
            if type(value) ~= "number" then return false end
            t.pct:SetText(("%.0f%%"):format(value))
            return true
        end
        return pcall(t.pct.SetFormattedText, t.pct, "%.0f%%", value)
    end
    -- Ohne Kurve liefert UnitHealthPercent einen Anteil 0–1; nur lesbar verwendbar
    local ok, value = pcall(UnitHealthPercent, unit)
    if ok and not IsSecret(value) and type(value) == "number" then
        t.pct:SetText(("%.0f%%"):format(value * 100))
        return true
    end
    return false
end

local function PaintHealth(t, unit)
    pcall(t.health.SetMinMaxValues, t.health, 0, UnitHealthMax(unit))
    pcall(t.health.SetValue, t.health, UnitHealth(unit))

    local status = StatusText(unit)
    if status then
        t.status:SetText(status)
        t.status:Show()
        t.pct:Hide()
        t.health:SetStatusBarColor(0.35, 0.35, 0.35)
        return
    end
    t.status:Hide()

    local _, class = UnitClass(unit)
    class = Public(class)
    t.health:SetStatusBarColor(ClassColor(class))

    -- SetPercent liefert false, wenn kein Text möglich ist; pcall-Erfolg allein reicht nicht
    local ok, shown = pcall(SetPercent, t, unit)
    t.pct:SetShown(ok and shown == true)
end

local function PaintPower(t, unit)
    local powerType, powerToken = UnitPowerType(unit)
    t.power:SetStatusBarColor(PowerColor(Public(powerType), Public(powerToken)))
    pcall(t.power.SetMinMaxValues, t.power, 0, UnitPowerMax(unit))
    pcall(t.power.SetValue, t.power, UnitPower(unit))
end

-- Erste Schwächung, die du entfernen kannst: gibt found, icon, dispelName zurück
local function FirstDispellable(unit)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|RAID")
        if ok then
            if type(aura) == "table" then return true, aura.icon, aura.dispelName end
            return false
        end
    end
    if UnitAura then
        local ok, name, icon, _, debuffType = pcall(UnitAura, unit, 1, "HARMFUL|RAID")
        if ok then
            if type(name) ~= "nil" then return true, icon, debuffType end
            return false
        end
    end
    if UnitDebuff then
        local ok, name, icon, _, debuffType = pcall(UnitDebuff, unit, 1, "RAID")
        if ok and type(name) ~= "nil" then return true, icon, debuffType end
    end
    return false
end

local function PaintDispel(t, found, icon, dispelName)
    if not found then
        t.icon:Hide()
        t.dispel:SetShown(false)
        return
    end
    if pcall(t.icon.SetTexture, t.icon, icon) then t.icon:Show() else t.icon:Hide() end
    if IsSecret(dispelName) or type(dispelName) ~= "string" then
        t.dispel:SetColor(NEUTRAL_BORDER[1], NEUTRAL_BORDER[2], NEUTRAL_BORDER[3], 1)
    else
        local r, g, b = DebuffColor(dispelName)
        t.dispel:SetColor(r, g, b, 1)
    end
    t.dispel:SetShown(true)
end

local function PaintAuras(t, unit)
    PaintDispel(t, FirstDispellable(unit))
end

local function PaintTarget(t, unit)
    local same = UnitIsUnit(unit, "target")
    t.target:SetShown(not IsSecret(same) and same and true or false)
end

local function PaintRange(t, unit)
    if unit == "player" then
        t.art:SetAlpha(1)
        return
    end
    local inRange, checked = UnitInRange(unit)
    if IsSecret(inRange) then
        if t.art.SetAlphaFromBoolean and pcall(t.art.SetAlphaFromBoolean, t.art, inRange, 1, FADED) then return end
        t.art:SetAlpha(1)
        return
    end
    -- Nicht geprüft (z. B. kein Gruppenmitglied) → voll sichtbar
    if not IsSecret(checked) and checked == false then
        t.art:SetAlpha(1)
        return
    end
    t.art:SetAlpha(inRange and 1 or FADED)
end

---------------------------------------------------------------------------
-- Sichere Knöpfe
---------------------------------------------------------------------------

local buttons = {}   -- Knöpfe des Headers in Erstellungsreihenfolge
local needSetup = {} -- im Kampf erstellte Knöpfe: Klick-/Zieh-Einrichtung nach dem Kampf

local function ButtonUnit(button)
    local unit = button:GetAttribute("unit")
    if type(unit) ~= "string" then return nil end
    local exists = UnitExists(unit)
    if IsSecret(exists) or not exists then return nil end
    return unit
end

local function UpdateButton(button)
    local t = button.stray
    if not t then return end
    local unit = ButtonUnit(button)
    if not unit then return end
    pcall(PaintName, t, unit)
    pcall(PaintHealth, t, unit)
    pcall(PaintPower, t, unit)
    pcall(PaintAuras, t, unit)
    pcall(PaintTarget, t, unit)
    pcall(PaintRange, t, unit)
end

local function UpdateAll()
    for _, button in ipairs(buttons) do
        if button:IsShown() then UpdateButton(button) end
    end
end

local requested = false
local function RequestAll()
    if requested then return end
    requested = true
    C_Timer.After(0, function()
        requested = false
        UpdateAll()
    end)
end

local function SetupInteraction(button)
    if InCombatLockdown() then
        needSetup[button] = true
        return
    end
    needSetup[button] = nil
    pcall(button.RegisterForClicks, button, "AnyUp")
    pcall(button.RegisterForDrag, button, "LeftButton")
end

local function OnButtonEnter(self)
    local unit = self:GetAttribute("unit")
    if type(unit) ~= "string" then return end
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    if pcall(GameTooltip.SetUnit, GameTooltip, unit) then GameTooltip:Show() end
end

-- Lua-Teil der Einrichtung, aufgerufen aus initialConfigFunction über CallMethod
local function InitButton(_, name)
    local button = type(name) == "string" and _G[name]
    if not button or button.stray then return end
    local w, h = Dims()
    local t = BuildTile(button)
    ResizeTile(t, h)
    button.stray = t
    table.insert(buttons, button)

    SetupInteraction(button)
    pcall(button.HookScript, button, "OnDragStart", StartDrag)
    pcall(button.HookScript, button, "OnDragStop", StopDrag)
    pcall(button.HookScript, button, "OnEnter", OnButtonEnter)
    pcall(button.HookScript, button, "OnLeave", function() GameTooltip:Hide() end)
    -- Header weist eine neue Einheit zu → neu zeichnen (nach dem Header-Durchlauf)
    pcall(button.HookScript, button, "OnAttributeChanged", function(_, key)
        if key == "unit" then RequestAll() end
    end)
    pcall(button.HookScript, button, "OnShow", RequestAll)
end

local header = CreateFrame("Frame", "strayPartyHeader", anchor, "SecureGroupHeaderTemplate")
header.strayInit = InitButton
header:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
do
    local w, h, sp = Dims()
    header:SetAttribute("showRaid", false)
    header:SetAttribute("showParty", true)
    header:SetAttribute("showPlayer", true)
    header:SetAttribute("showSolo", false)
    header:SetAttribute("point", "TOP")
    header:SetAttribute("yOffset", -sp)
    header:SetAttribute("sortMethod", "INDEX")
    header:SetAttribute("unitsPerColumn", MAX_TILES)
    header:SetAttribute("maxColumns", 1)
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    header:SetAttribute("strayWidth", w)
    header:SetAttribute("strayHeight", h)
    header:SetAttribute("initialConfigFunction", [[
        local header = self:GetParent()
        self:SetWidth(header:GetAttribute("strayWidth"))
        self:SetHeight(header:GetAttribute("strayHeight"))
        self:SetAttribute("type1", "target")
        self:SetAttribute("type2", "togglemenu")
        header:CallMethod("strayInit", self:GetName())
    ]])
end
header:Hide()

---------------------------------------------------------------------------
-- Beispielkacheln (nur solange das stray-Fenster offen ist und du in keiner Gruppe bist)
---------------------------------------------------------------------------

local SAMPLES = {
    { name = "Leon", class = "PRIEST", hp = 0.92, power = "MANA", mp = 0.7 },
    { name = "Kael", class = "MAGE", hp = 0.64, power = "MANA", mp = 0.45, dispel = "Poison", icon = "Interface\\Icons\\Ability_Creature_Poison_03" },
    { name = "Mira", class = "DRUID", hp = 1.0, power = "MANA", mp = 0.9, faded = true },
    { name = "Brom", class = "WARRIOR", hp = 0, power = "RAGE", mp = 0, status = "Tot" },
    { name = "Sera", class = "ROGUE", hp = 0.38, power = "ENERGY", mp = 0.8, target = true },
}

local samples = {}

local function SampleEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Gruppenrahmen – Beispiel", 1, 1, 1)
    GameTooltip:AddLine("Shift + ziehen zum Verschieben. Breite, Höhe und Abstand stellst du im stray-Fenster ein.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    GameTooltip:AddLine("Die Testgruppe verschwindet, wenn du das stray-Fenster schließt (oder echte Gruppenrahmen in deiner Gruppe laufen).", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function PaintSample(t, s)
    t.name:SetText(s.name)
    t.health:SetMinMaxValues(0, 1)
    t.health:SetValue(s.hp)
    t.power:SetMinMaxValues(0, 1)
    t.power:SetValue(s.mp)
    t.power:SetStatusBarColor(PowerColor(nil, s.power))
    if s.status then
        t.status:SetText(s.status)
        t.status:Show()
        t.pct:Hide()
        t.health:SetStatusBarColor(0.35, 0.35, 0.35)
    else
        t.status:Hide()
        t.pct:SetText(("%.0f%%"):format(s.hp * 100))
        t.pct:Show()
        t.health:SetStatusBarColor(ClassColor(s.class))
    end
    PaintDispel(t, s.dispel ~= nil, s.icon, s.dispel)
    t.target:SetShown(s.target and true or false)
    t.art:SetAlpha(s.faded and FADED or 1)
end

local function LayoutSamples()
    local w, h, sp = Dims()
    for i, f in ipairs(samples) do
        f:SetSize(w, h)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * (h + sp))
        ResizeTile(f.stray, h)
    end
end

local function EnsureSamples()
    if #samples > 0 then return end
    for i, s in ipairs(SAMPLES) do
        local f = CreateFrame("Frame", nil, anchor)
        f:SetFrameStrata(anchor:GetFrameStrata())
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", StartDrag)
        f:SetScript("OnDragStop", StopDrag)
        f:SetScript("OnEnter", SampleEnter)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.stray = BuildTile(f)
        PaintSample(f.stray, s)
        f:Hide()
        samples[i] = f
    end
    LayoutSamples()
end

-- Testgruppe: Solange das stray-Fenster offen ist, erscheinen 5 Beispielspieler – auch wenn
-- die Gruppenrahmen aus sind. Nur wenn echte Rahmen in einer Gruppe laufen, bleibt sie weg.
local function UpdatePreview()
    local show = ns.IsConfigOpen() and not (Enabled() and IsInGroup())
    if show then EnsureSamples() end
    for _, f in ipairs(samples) do f:SetShown(show) end
    -- Der Anker hält den sicheren Header: nur außerhalb des Kampfes ein-/ausblenden
    if not InCombatLockdown() then
        if show then
            anchor:Show()
        elseif not Enabled() then
            anchor:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Blizzards Gruppenrahmen ausblenden (Wieder-Einblenden nur per Neuladen)
---------------------------------------------------------------------------

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local blizzardHidden = false

local function HideFrame(frame, keepParent)
    if not frame or frame:GetParent() == hiddenParent then return end
    pcall(frame.Hide, frame)
    if keepParent then
        -- Edit-Mode-Systeme (PartyFrame) nicht umhängen, nur verstecken und versteckt halten
        if not frame.strayHideHooked then
            frame.strayHideHooked = true
            pcall(frame.HookScript, frame, "OnShow", function(self)
                if ns.db and ns.db.partyFrames and ns.db.partyHideBlizzard and not InCombatLockdown() then self:Hide() end
            end)
        end
        return
    end
    pcall(frame.UnregisterAllEvents, frame)
    pcall(frame.SetParent, frame, hiddenParent)
end

local function HideBlizzard()
    if InCombatLockdown() then return false end
    for i = 1, 4 do HideFrame(_G["PartyMemberFrame" .. i]) end
    HideFrame(_G.PartyMemberBackground)
    HideFrame(_G.PartyFrame, true)
    HideFrame(_G.CompactPartyFrame) -- kann erst später entstehen → bei Gruppenwechsel erneut
    blizzardHidden = true
    return true
end

---------------------------------------------------------------------------
-- Ereignisse, Reichweite, Ein-/Ausschalten
---------------------------------------------------------------------------

local EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_AURA", "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "UNIT_FLAGS",
    "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
}

local pendingRefresh = false
local Refresh -- weiter unten

local events = CreateFrame("Frame")
local registered = false
local ticker

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        for _, button in ipairs(buttons) do
            local u = button:IsShown() and ButtonUnit(button)
            if u and button.stray then pcall(PaintTarget, button.stray, u) end
        end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        if event == "PLAYER_REGEN_ENABLED" and stopPending then StopDrag() end
        if (event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED") and ns.db.partyHideBlizzard and ns.db.partyFrames and not InCombatLockdown() then
            HideBlizzard()
        end
        UpdatePreview()
        RequestAll()
        return
    end
    if type(unit) ~= "string" then return end
    for _, button in ipairs(buttons) do
        if button:IsShown() and button:GetAttribute("unit") == unit then
            UpdateButton(button)
        end
    end
end)

local function UpdateRangeAll()
    for _, button in ipairs(buttons) do
        local u = button:IsShown() and ButtonUnit(button)
        if u and button.stray then pcall(PaintRange, button.stray, u) end
    end
end

local function SetEventsRegistered(want)
    if want == registered then return end
    registered = want
    for _, event in ipairs(EVENTS) do
        if want then
            pcall(events.RegisterEvent, events, event)
        else
            pcall(events.UnregisterEvent, events, event)
        end
    end
    if want then
        if not ticker and C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(0.3, UpdateRangeAll)
        end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Größe und Abstand anwenden (öffentlich, für die Schieberegler)
function ns.PartyApplyLayout()
    LayoutSamples()
    if InCombatLockdown() then
        pendingRefresh = true
        return
    end
    local w, h, sp = Dims()
    anchor:SetSize(w, MAX_TILES * h + (MAX_TILES - 1) * sp)
    header:SetAttribute("strayWidth", w)
    header:SetAttribute("strayHeight", h)
    for _, button in ipairs(buttons) do
        button:SetSize(w, h)
        if button.stray then ResizeTile(button.stray, h) end
    end
    -- Zuletzt: löst die Neuanordnung durch den Header aus
    header:SetAttribute("yOffset", -sp)
end

local precreated = false
local positionPending = false

function Refresh()
    if not ns.db then return end
    if InCombatLockdown() then
        pendingRefresh = true
        UpdatePreview()
        return
    end
    pendingRefresh = false
    if positionPending then
        positionPending = false
        pcall(ns.RestorePosition, anchor)
    end
    local on = Enabled()
    if on then
        ns.PartyApplyLayout()
        anchor:Show()
        if not precreated then
            -- Alle 5 Knöpfe jetzt (außerhalb des Kampfes) anlegen lassen: Startindex kurz negativ
            precreated = true
            header:SetAttribute("startingIndex", 1 - MAX_TILES)
            header:Show()
            header:SetAttribute("startingIndex", 1)
        else
            header:Show()
        end
        if ns.db.partyHideBlizzard then HideBlizzard() end
    else
        header:Hide()
        anchor:Hide()
    end
    for button in pairs(needSetup) do SetupInteraction(button) end
    SetEventsRegistered(on)
    UpdatePreview()
    if on then RequestAll() end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if not ns.db then return end
    if pendingRefresh or positionPending or next(needSetup) then Refresh() end
end)

ns.On("PLAYER_LOGIN", function()
    -- Im Kampf (Neuladen im Kampf) holt Refresh die Position nach dem Kampf nach
    positionPending = true
    Refresh()
end)

ns.OnConfig(function() UpdatePreview() end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

local function CombatNote()
    if InCombatLockdown() then ns.Print("Gruppenrahmen: Die Änderung gilt nach dem Kampf.") end
end

local function ReloadNote()
    if blizzardHidden then
        ns.Print("Blizzards Gruppenrahmen kommen nach /reload zurück.")
    end
end

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyFrames",
    label = "Gruppenrahmen anzeigen",
    tooltip = "Eigene Gruppenrahmen für Heiler: du und deine 5er-Gruppe als senkrechte Spalte (nicht im Schlachtzug). Lebensbalken in Klassenfarbe, Leben in Prozent, Ressourcenbalken, „Tot“/„Geist“/„Offline“; wer außer Reichweite ist, wird blass. Hat jemand eine Schwächung, die du entfernen kannst, bekommt die Kachel einen farbigen Rahmen (Gift grün, Krankheit braun, Fluch lila, Magie blau) und ein kleines Symbol.\n\nLinksklick wählt das Mitglied als Ziel, Rechtsklick öffnet sein Menü. Mit eingeschaltetem „Mouseover-Zauber“ (Kampf → Zaubern) heilt deine normale Heiltaste das Mitglied unter der Maus.\n\nVerschieben mit Shift + Ziehen; solange das stray-Fenster offen ist, zeigt eine Testgruppe mit 5 Spielern Größe und Position – auch wenn die Gruppenrahmen noch aus sind. Änderungen wirken nur außerhalb des Kampfes.",
    set = function(value)
        ns.db.partyFrames = value
        CombatNote()
        if not value then ReloadNote() end
        Refresh()
    end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyHideBlizzard",
    label = "Blizzards Gruppenrahmen ausblenden",
    tooltip = "Blendet Blizzards eigene Gruppenrahmen aus, solange die stray-Gruppenrahmen an sind. So siehst du jedes Mitglied nur einmal.\n\nWieder einblenden: Option ausschalten und /reload eingeben (Neuladen nötig).",
    isEnabled = function() return ns.db and ns.db.partyFrames and true or false end,
    disabledHint = "Erst „Gruppenrahmen anzeigen“ einschalten.",
    set = function(value)
        ns.db.partyHideBlizzard = value
        CombatNote()
        if not value then ReloadNote() end
        Refresh()
    end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyWidth",
    type = "slider",
    label = "Breite",
    min = 60, max = 200, step = 1,
    tooltip = "Breite jeder Kachel in Pixeln. Im Kampf wird die Änderung erst danach übernommen.",
    set = function(v) ns.db.partyWidth = v; ns.PartyApplyLayout() end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyHeight",
    type = "slider",
    label = "Höhe",
    min = 24, max = 80, step = 1,
    tooltip = "Höhe jeder Kachel in Pixeln. Im Kampf wird die Änderung erst danach übernommen.",
    set = function(v) ns.db.partyHeight = v; ns.PartyApplyLayout() end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partySpacing",
    type = "slider",
    label = "Abstand",
    min = 0, max = 20, step = 1,
    tooltip = "Abstand zwischen den Kacheln in Pixeln. Im Kampf wird die Änderung erst danach übernommen.",
    set = function(v) ns.db.partySpacing = v; ns.PartyApplyLayout() end,
})
