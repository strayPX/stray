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
-- Fester Bestandteil (ohne eigene Option): Heilvorhersage, Schild mit Überschild-Strich,
-- Symbole für Machtwort: Schild und „Geschwächte Seele“ – alles nicht-sichere Kinder von „art“.

local _, ns = ...
local L = ns.L

local IsSecret = ns.IsSecret
local Public = ns.Public

-- Begleiter am Gruppenrahmen (Jäger-Tier, Wichtel …), neu in 0.22.0 – standardmäßig aus
ns.defaults.partyPets = false
ns.defaults.partyPetWidth = 70
ns.defaults.partyPetHeight = 22
-- Andockstelle des Begleiters am Rahmen des Besitzers (Nachtrag 0.22.0); LEFT = bisheriges Verhalten
ns.defaults.partyPetAnchor = "LEFT"

local POWER_H = 4
local MAX_TILES = 5
local FADED = 0.4
-- Flache, einfarbige Balken (Design A, Leon 07.11.2026) – keine Streifen/Glanz der Blizzard-Textur
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local FALLBACK_DEBUFF_COLORS = {
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}
local NEUTRAL_BORDER = { 0.9, 0.9, 0.9 }

-- Gemeinsame stray-Farben (ns.Colors aus stray.lua); Rückfall, falls die Tabelle fehlt
local COLOR_FALLBACK = {
    bg = { 0.078, 0.078, 0.098, 0.96 },
    card = { 0.094, 0.094, 0.118, 1 },
    hover = { 0.122, 0.122, 0.153, 1 },
    line = { 0.149, 0.149, 0.184, 1 },
    accent = { 0.545, 0.486, 0.965, 1 },
    accentText = { 0.702, 0.659, 0.980, 1 },
    text = { 0.902, 0.902, 0.925, 1 },
    textDim = { 0.545, 0.545, 0.600, 1 },
}
local function Color(name)
    local c = type(ns.Colors) == "table" and ns.Colors[name]
    if type(c) == "table" and type(c[1]) == "number" then return c end
    return COLOR_FALLBACK[name] or COLOR_FALLBACK.text
end

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

-- Begleiter: Größe des kleinen Fensters neben dem Besitzer
local PET_GAP = 4
local function PetDims()
    local db = ns.db or ns.defaults
    local w = tonumber(db.partyPetWidth) or 70
    local h = tonumber(db.partyPetHeight) or 22
    w = math.max(40, math.min(160, math.floor(w + 0.5)))
    h = math.max(14, math.min(60, math.floor(h + 0.5)))
    return w, h
end

-- Andockstellen am Rahmen des Besitzers (Reihenfolge = Auswahl in den Optionen)
local PET_ANCHORS = { "LEFT_TOP", "LEFT", "LEFT_BOTTOM", "RIGHT_TOP", "RIGHT", "RIGHT_BOTTOM", "TOP", "BOTTOM" }
local PET_ANCHOR_LABELS = { "Links oben", "Links mittig", "Links unten", "Rechts oben", "Rechts mittig", "Rechts unten", "Oben", "Unten" }
local PET_ANCHOR_VALID = {}
for _, a in ipairs(PET_ANCHORS) do PET_ANCHOR_VALID[a] = true end

local function PetAnchor()
    local v = ns.db and ns.db.partyPetAnchor
    if type(v) == "string" and PET_ANCHOR_VALID[v] then return v end
    return "LEFT"
end

-- Obere linke Ecke des Begleiters relativ zur oberen linken Ecke des Besitzers (y nach oben positiv)
local function PetRect(where, w, h, pw, ph)
    local x, y
    if where == "TOP" or where == "BOTTOM" then
        x = math.floor((w - pw) / 2 + 0.5)
        y = (where == "TOP") and (PET_GAP + ph) or -(h + PET_GAP)
        return x, y
    end
    if where:sub(1, 4) == "LEFT" then x = -PET_GAP - pw else x = w + PET_GAP end
    if where:find("_TOP", 1, true) then
        y = 0
    elseif where:find("_BOTTOM", 1, true) then
        y = -(h - ph)
    else
        y = -math.floor((h - ph) / 2 + 0.5)
    end
    return x, y
end

local function PetsWanted()
    return ns.db and ns.db.partyPets and true or false
end

-- Echte Begleiter-Knöpfe nur zusammen mit den Gruppenrahmen
local function PetsEnabled()
    return Enabled() and PetsWanted()
end

-- Begleiter-Einheit je Platz in der Spalte (Platz 1 = du, dann party1–4; Sortierung INDEX)
local PET_UNITS = { "pet", "partypet1", "partypet2", "partypet3", "partypet4" }
-- Besitzer → Begleiter (für UNIT_PET, das die Besitzer-Einheit meldet)
local OWNER_PET = { player = "pet", party1 = "partypet1", party2 = "partypet2", party3 = "partypet3", party4 = "partypet4" }

-- Klassenfarbe, abgedunkelt nach „Helligkeit der Balken“ (Standard 60 %)
local function ClassColor(class)
    local f = ((ns.db and ns.db.partyBrightness) or 60) / 100
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r * f, color.g * f, color.b * f end
    return 0.2 * f, 0.75 * f, 0.3 * f
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
-- opts (ab 0.22.0): Breite/Höhe im Bearbeiten-Modus über die vorhandenen Regler; ältere Fassung ignoriert sie
ns.RegisterMovable(anchor, "Gruppenrahmen", nil, { widthKey = "partyWidth", heightKey = "partyHeight" })
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
-- Heilvorhersage, Schilde, „Geschwächte Seele“ (fester Bestandteil, ohne eigene Option)
---------------------------------------------------------------------------

local HEAL_TOTAL = { 0.3, 0.9, 0.45, 0.55 }  -- ein Balken: gesamte eingehende Heilung
local HEAL_OWN = { 0.35, 1, 0.5, 0.6 }       -- eigene Heilung
local HEAL_OTHER = { 0.2, 0.65, 0.35, 0.5 }  -- Heilung anderer
local ABSORB_COLOR = { 0.75, 0.88, 1, 0.5 }
local ABSORB_STRIPES = "Interface\\RaidFrame\\Shield-Overlay"
local OVERSHIELD_COLOR = { 0.9, 0.97, 1, 1 }
local WEAKENED_SOUL_IDS = { 6788 }
local SHIELD_IDS = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 } -- Machtwort: Schild, alle Ränge
local SHIELD_ICON_FALLBACK = "Interface\\Icons\\Spell_Holy_PowerWordShield"
local SOUL_ICON_FALLBACK = "Interface\\Icons\\Spell_Holy_AshesToAshes"

-- Methode eines Objekts (z. B. des Vorhersage-Rechners) geschützt aufrufen: ok, Rückgaben …
local function CallMethod(obj, method, ...)
    if type(obj) == "nil" then return false end
    local okGet, fn = pcall(function() return obj[method] end)
    if not okGet or type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

local function SpellTexture(id, fallback)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and not IsSecret(tex) and tex then return tex end
    end
    if GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, id)
        if ok and not IsSecret(tex) and tex then return tex end
    end
    return fallback
end

local spellNames = {}
local function SpellName(id)
    if spellNames[id] then return spellNames[id] end
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then name = Public(n) end
    end
    if type(name) ~= "string" and GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok then name = Public(n) end
    end
    if type(name) == "string" and name ~= "" then
        spellNames[id] = name
        return name
    end
    return nil
end

-- Sucht eine Aura nach Zauber-IDs bzw. Name. Gibt die Aura-Tabelle oder nil zurück.
-- spellId wird nur verglichen, wenn sie lesbar ist.
local function FindAura(unit, ids, name, filter)
    local api = C_UnitAuras
    -- Gezielte Abfrage nach ID; liefert sie nichts (z. B. bei anderen Spielern), weiter mit dem Namen
    if api and api.GetUnitAuraBySpellID then
        for _, id in ipairs(ids) do
            local ok, aura = pcall(api.GetUnitAuraBySpellID, unit, id)
            if ok and type(aura) == "table" then return aura end
        end
    end
    if name and api and api.GetAuraDataBySpellName then
        local ok, aura = pcall(api.GetAuraDataBySpellName, unit, name, filter)
        if ok then
            if type(aura) == "table" then return aura end
            return nil
        end
    end
    -- Rückfall: Auren durchgehen
    for i = 1, 40 do
        local aura
        if api and api.GetAuraDataByIndex then
            local ok, a = pcall(api.GetAuraDataByIndex, unit, i, filter)
            if not ok or type(a) ~= "table" then return nil end
            aura = a
        elseif UnitAura then
            local ok, n, icon, _, _, duration, expirationTime, _, _, _, spellId = pcall(UnitAura, unit, i, filter)
            if not ok or type(n) == "nil" then return nil end
            aura = { icon = icon, duration = duration, expirationTime = expirationTime, spellId = spellId }
        else
            return nil
        end
        local spellId = aura.spellId
        -- Versiegelte IDs: Durchsuchen kann nichts finden → abbrechen statt 40 Auren zu prüfen
        if IsSecret(spellId) then return nil end
        if type(spellId) == "number" then
            for _, id in ipairs(ids) do
                if spellId == id then return aura end
            end
        end
    end
    return nil
end

-- Vorhersage-Rechner (Midnight), je Kachel einmal; gibt calc, absorbClamp zurück
local function NewCalculator()
    if type(CreateUnitHealPredictionCalculator) ~= "function" then return nil, false end
    local ok, calc = pcall(CreateUnitHealPredictionCalculator)
    if not ok or type(calc) == "nil" then return nil, false end
    -- Schild auf fehlendes Leben klemmen lassen → „geklemmt“ heißt Überschild (nur falls bekannt)
    local clamp = false
    local modes = Enum and Enum.UnitDamageAbsorbClampMode
    local mode = type(modes) == "table" and modes.MissingHealth
    if type(mode) == "number" and CallMethod(calc, "SetDamageAbsorbClampMode", mode) then clamp = true end
    return calc, clamp
end

local function MakePredictBar(parent, after, color)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetFrameLevel(parent:GetFrameLevel() + 1)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
    -- Beginnt am rechten Ende der vorherigen Füllung; Überstand schneidet der Clip-Bereich ab
    bar:SetPoint("TOPLEFT", after, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT", 0, 0)
    bar:SetWidth(1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
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

    local bg, card = Color("bg"), Color("card")
    t.bg = art:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.bg:SetColorTexture(bg[1], bg[2], bg[3], 0.8)

    t.power = CreateFrame("StatusBar", nil, art)
    t.power:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 1, 1)
    t.power:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -1, 1)
    t.power:SetHeight(POWER_H)
    t.power:SetStatusBarTexture(BAR_TEXTURE)
    t.power:SetMinMaxValues(0, 1)
    t.power:SetValue(1)
    local powerBg = t.power:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints()
    powerBg:SetColorTexture(bg[1], bg[2], bg[3], 1)

    t.health = CreateFrame("StatusBar", nil, art)
    t.health:SetPoint("TOPLEFT", art, "TOPLEFT", 1, -1)
    t.health:SetPoint("BOTTOMRIGHT", t.power, "TOPRIGHT", 0, 1)
    t.health:SetStatusBarTexture(BAR_TEXTURE)
    t.health:SetMinMaxValues(0, 1)
    t.health:SetValue(1)
    local healthBg = t.health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints()
    healthBg:SetColorTexture(card[1], card[2], card[3], 0.85)

    -- Heilvorhersage und Schild: Balken in einem Clip-Bereich genau über dem Lebensbalken
    local clip = CreateFrame("Frame", nil, art)
    clip:SetAllPoints(t.health)
    clip:SetFrameLevel(t.health:GetFrameLevel() + 1)
    pcall(clip.SetClipsChildren, clip, true)
    t.clip = clip
    t.heal1 = MakePredictBar(clip, t.health:GetStatusBarTexture(), HEAL_TOTAL)
    t.heal2 = MakePredictBar(clip, t.heal1:GetStatusBarTexture(), HEAL_OTHER)
    t.absorb = MakePredictBar(clip, t.heal2:GetStatusBarTexture(), ABSORB_COLOR)
    -- Streifen-Optik über der Schild-Füllung (falls die Textur vorhanden ist)
    t.stripes = t.absorb:CreateTexture(nil, "OVERLAY")
    local okTex, res = pcall(t.stripes.SetTexture, t.stripes, ABSORB_STRIPES, "REPEAT", "REPEAT")
    if okTex and res ~= false then
        pcall(t.stripes.SetHorizTile, t.stripes, true)
        pcall(t.stripes.SetVertTile, t.stripes, true)
        t.stripes:SetAllPoints(t.absorb:GetStatusBarTexture())
        t.stripes:SetAlpha(0.7)
        t.hasStripes = true
    end
    t.stripes:Hide()

    -- Texte und Symbol über den Balken
    local top = CreateFrame("Frame", nil, art)
    top:SetAllPoints(art)
    top:SetFrameLevel(t.health:GetFrameLevel() + 4)
    t.top = top

    -- Überschild-Strich am rechten Rand des Lebensbalkens
    t.over = top:CreateTexture(nil, "ARTWORK")
    t.over:SetColorTexture(OVERSHIELD_COLOR[1], OVERSHIELD_COLOR[2], OVERSHIELD_COLOR[3], OVERSHIELD_COLOR[4])
    t.over:SetPoint("TOPRIGHT", t.health, "TOPRIGHT", 0, 0)
    t.over:SetPoint("BOTTOMRIGHT", t.health, "BOTTOMRIGHT", 0, 0)
    t.over:SetWidth(3)
    t.over:Hide()

    t.name = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.name:SetPoint("TOPLEFT", top, "TOPLEFT", 4, -4)
    t.name:SetPoint("TOPRIGHT", top, "TOPRIGHT", -34, -4)
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(false)
    t.name:SetShadowOffset(1, -1)

    t.pct = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.pct:SetPoint("TOPRIGHT", top, "TOPRIGHT", -4, -4)
    t.pct:SetJustifyH("RIGHT")
    t.pct:SetTextColor(Color("text")[1], Color("text")[2], Color("text")[3])
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

    -- Schild-Symbol (Machtwort: Schild) und „Geschwächte Seele“ links neben dem Prozenttext
    t.shieldIcon = top:CreateTexture(nil, "OVERLAY")
    t.shieldIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if not pcall(t.shieldIcon.SetTexture, t.shieldIcon, SpellTexture(17, SHIELD_ICON_FALLBACK)) then
        pcall(t.shieldIcon.SetTexture, t.shieldIcon, SHIELD_ICON_FALLBACK)
    end
    t.shieldIcon:Hide()

    t.soulIcon = top:CreateTexture(nil, "OVERLAY")
    t.soulIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.soulTexture = SpellTexture(6788, SOUL_ICON_FALLBACK)
    pcall(t.soulIcon.SetTexture, t.soulIcon, t.soulTexture)
    t.soulIcon:Hide()

    local okCD, cd = pcall(CreateFrame, "Cooldown", nil, top, "CooldownFrameTemplate")
    if not okCD or not cd then cd = CreateFrame("Cooldown", nil, top) end
    cd:SetAllPoints(t.soulIcon)
    pcall(cd.SetDrawEdge, cd, false)
    pcall(cd.SetHideCountdownNumbers, cd, false) -- Restzeit in Sekunden anzeigen
    cd:Hide()
    t.soulCD = cd
    t.iconOrder = { t.shieldIcon, t.soulIcon } -- von rechts nach links

    t.dispel = MakeBorder(top, 2, 0, "OVERLAY", 6)
    -- Auswahl (aktuelles Ziel) im stray-Lila
    t.target = MakeBorder(top, 1, 1, "OVERLAY", 7)
    local accent = Color("accent")
    t.target:SetColor(accent[1], accent[2], accent[3], 1)
    return t
end

-- Größe der Symbole und Breite der Vorhersage-/Schildbalken (= Breite des Lebensbalkens)
local function ResizeTile(t, h, w)
    local size = math.max(10, math.min(18, math.floor(h * 0.38)))
    t.icon:SetSize(size, size)
    local small = math.max(12, math.min(14, math.floor(h * 0.32)))
    t.shieldIcon:SetSize(small, small)
    t.soulIcon:SetSize(small, small)
    local barW = math.max(1, (tonumber(w) or 96) - 2)
    t.heal1:SetWidth(barW)
    t.heal2:SetWidth(barW)
    t.absorb:SetWidth(barW)
end

-- Schild-/Seelen-Symbol links neben dem Prozenttext reihen; Name endet vor dem ersten Symbol
local function LayoutIcons(t)
    local last
    for _, icon in ipairs(t.iconOrder) do
        if icon:IsShown() then
            icon:ClearAllPoints()
            if last then
                icon:SetPoint("TOPRIGHT", last, "TOPLEFT", -1, 0)
            else
                icon:SetPoint("TOPRIGHT", t.pct, "TOPLEFT", -2, 1)
            end
            last = icon
        end
    end
    t.name:ClearAllPoints()
    t.name:SetPoint("TOPLEFT", t.top, "TOPLEFT", 4, -4)
    if last then
        t.name:SetPoint("TOPRIGHT", last, "TOPLEFT", -2, -1)
    else
        t.name:SetPoint("TOPRIGHT", t.top, "TOPRIGHT", -34, -4)
    end
end

-- Balkenwert setzen; nil → 0. Versiegelte Werte gehen nur an SetMinMaxValues/SetValue.
local function SetBar(bar, maxValue, value)
    if not pcall(bar.SetMinMaxValues, bar, 0, maxValue) then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        return
    end
    if type(value) == "nil" or not pcall(bar.SetValue, bar, value) then bar:SetValue(0) end
end

local function SetHeals(t, maxValue, mode, a, b)
    if mode == "split" then
        t.heal1:SetStatusBarColor(HEAL_OWN[1], HEAL_OWN[2], HEAL_OWN[3], HEAL_OWN[4])
        t.heal2:SetStatusBarColor(HEAL_OTHER[1], HEAL_OTHER[2], HEAL_OTHER[3], HEAL_OTHER[4])
        SetBar(t.heal1, maxValue, a)
        SetBar(t.heal2, maxValue, b)
    else
        t.heal1:SetStatusBarColor(HEAL_TOTAL[1], HEAL_TOTAL[2], HEAL_TOTAL[3], HEAL_TOTAL[4])
        SetBar(t.heal1, maxValue, a)
        SetBar(t.heal2, maxValue, 0)
    end
end

-- Restzeit nur mit lesbaren Werten; versiegelt → Dauerobjekt (Midnight), sonst ohne Abklinganzeige
local function SetSoulCooldown(t, duration, expirationTime, unit, auraInstanceID)
    local cd = t.soulCD
    if not IsSecret(duration) and not IsSecret(expirationTime)
        and type(duration) == "number" and type(expirationTime) == "number" then
        if duration > 0 and pcall(cd.SetCooldown, cd, expirationTime - duration, duration) then
            cd:Show()
            return
        end
    elseif unit and type(auraInstanceID) ~= "nil" and C_UnitAuras and C_UnitAuras.GetAuraDuration
        and cd.SetCooldownFromDurationObject then
        local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
        if ok and type(durationObj) ~= "nil" and pcall(cd.SetCooldownFromDurationObject, cd, durationObj) then
            cd:Show()
            return
        end
    end
    if cd.Clear then pcall(cd.Clear, cd) else pcall(cd.SetCooldown, cd, 0, 0) end
    cd:Hide()
end

local function HideSoul(t)
    t.soulIcon:Hide()
    if t.soulCD.Clear then pcall(t.soulCD.Clear, t.soulCD) end
    t.soulCD:Hide()
end

local function ClearPrediction(t)
    SetBar(t.heal1, 1, 0)
    SetBar(t.heal2, 1, 0)
    SetBar(t.absorb, 1, 0)
    t.stripes:Hide()
    t.over:Hide()
    t.shieldIcon:Hide()
    HideSoul(t)
    LayoutIcons(t)
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
    if not IsSecret(connected) and connected == false then return L["Offline"] end
    local dead = UnitIsDeadOrGhost(unit)
    if not IsSecret(dead) and dead then
        local ghost = UnitIsGhost(unit)
        if not IsSecret(ghost) and ghost then return L["Geist"] end
        return L["Tot"]
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
    -- Mana & Co. sind in der Gruppe versiegelt und dürfen nicht in SetMinMaxValues.
    -- UnitPowerPercent rechnet im Spiel selbst und liefert 0–100 (Methode wie EllesmereUI).
    -- type() ist auf versiegelten Werten erlaubt, ein Vergleich (auch mit nil) nicht.
    if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, pct = pcall(UnitPowerPercent, unit, powerType, true, CurveConstants.ScaleTo100)
        if ok and type(pct) == "number" then
            t.power:SetMinMaxValues(0, 100)
            pcall(t.power.SetValue, t.power, pct)
            return
        end
    end
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

-- Eingehende Heilung: gibt "split", eigene, fremde  oder  "total", gesamt  zurück
local function IncomingHeals(t, unit, calcFilled)
    if calcFilled then
        local ok, total, own, others = CallMethod(t.calc, "GetIncomingHeals")
        if ok then
            if type(own) == "number" and type(others) == "number" then return "split", own, others end
            if type(total) == "number" then return "total", total end
        end
    end
    if type(UnitGetIncomingHeals) ~= "function" then return "total", nil end
    local okT, total = pcall(UnitGetIncomingHeals, unit)
    if not okT then total = nil end
    local okO, own = pcall(UnitGetIncomingHeals, unit, "player")
    if okO and not IsSecret(total) and not IsSecret(own) then
        total = type(total) == "number" and total or 0
        own = type(own) == "number" and own or 0
        if own > total then own = total end
        return "split", own, total - own
    end
    -- Versiegelt: kein Rechnen → ein Balken mit der Gesamtheilung
    return "total", total
end

local function PaintPrediction(t, unit)
    if StatusText(unit) then
        ClearPrediction(t)
        return
    end
    local maxHP = UnitHealthMax(unit)

    local calcFilled = false
    if t.calc and type(UnitGetDetailedHealPrediction) == "function" then
        calcFilled = pcall(UnitGetDetailedHealPrediction, unit, "player", t.calc)
    end

    -- Heilung
    local ok, mode, a, b = pcall(IncomingHeals, t, unit, calcFilled)
    if ok then SetHeals(t, maxHP, mode, a, b) else SetHeals(t, 1, "total", 0) end

    -- Schild
    local absorb
    if type(UnitGetTotalAbsorbs) == "function" then
        local okA, v = pcall(UnitGetTotalAbsorbs, unit)
        if okA then absorb = v end
    end
    SetBar(t.absorb, maxHP, absorb)
    local readable = type(absorb) == "number" and not IsSecret(absorb)
    if t.hasStripes then
        if readable then t.stripes:SetShown(absorb > 0)
        else t.stripes:SetShown(type(absorb) ~= "nil") end
    end

    -- Überschild-Strich: nur mit lesbaren Werten vergleichen
    t.over:SetAlpha(1)
    local over = false
    if readable then
        local cur = UnitHealth(unit)
        if not IsSecret(cur) and not IsSecret(maxHP) and type(cur) == "number" and type(maxHP) == "number" then
            over = absorb > 0 and absorb > (maxHP - cur)
        end
        t.over:SetShown(over)
    elseif calcFilled and t.absorbClamp and t.over.SetAlphaFromBoolean then
        -- Rechner klemmt den Schild aufs fehlende Leben: „geklemmt“ = Überschild, ohne Vergleich
        local okD, _, clamped = CallMethod(t.calc, "GetDamageAbsorbs")
        if okD and type(clamped) == "boolean" then
            if IsSecret(clamped) then
                if pcall(t.over.SetAlphaFromBoolean, t.over, clamped, 1, 0) then t.over:Show() else t.over:Hide() end
            else
                t.over:SetShown(clamped)
            end
        else
            t.over:Hide()
        end
    else
        t.over:Hide()
    end

    -- Schild-Symbol: lesbarer Wert > 0 (hier) oder Buff Machtwort: Schild (PaintBuffIcons, nur bei UNIT_AURA)
    t.hasShieldValue = (readable and absorb > 0) and true or false
    t.shieldIcon:SetShown(t.hasShieldValue or t.shieldBuff == true)
    LayoutIcons(t)
end

-- Symbole aus Auren (Schild-Buff, „Geschwächte Seele“) – nur bei UNIT_AURA und vollem Neuzeichnen,
-- nicht bei jeder Lebens- oder Mana-Änderung (Auren durchsuchen kostet)
local function PaintBuffIcons(t, unit)
    local okShield, shieldAura = pcall(FindAura, unit, SHIELD_IDS, SpellName(17), "HELPFUL")
    t.shieldBuff = okShield and type(shieldAura) == "table"
    t.shieldIcon:SetShown(t.hasShieldValue == true or t.shieldBuff)

    local okSoul, soul = pcall(FindAura, unit, WEAKENED_SOUL_IDS, SpellName(6788), "HARMFUL")
    if okSoul and type(soul) == "table" then
        if type(soul.icon) == "nil" or not pcall(t.soulIcon.SetTexture, t.soulIcon, soul.icon) then
            pcall(t.soulIcon.SetTexture, t.soulIcon, t.soulTexture)
        end
        t.soulIcon:Show()
        pcall(SetSoulCooldown, t, soul.duration, soul.expirationTime, unit, soul.auraInstanceID)
    else
        pcall(HideSoul, t)
    end

    LayoutIcons(t)
end

---------------------------------------------------------------------------
-- Begleiter-Optik und -Werte (kleine Kachel: Name, Lebensbalken, Prozent)
---------------------------------------------------------------------------

local function BuildPetTile(parent)
    local art = CreateFrame("Frame", nil, parent)
    art:SetAllPoints(parent)
    art:SetFrameLevel(parent:GetFrameLevel() + 1)

    local t = { art = art }

    local bg, card = Color("bg"), Color("card")
    t.bg = art:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.bg:SetColorTexture(bg[1], bg[2], bg[3], 0.8)

    t.health = CreateFrame("StatusBar", nil, art)
    t.health:SetPoint("TOPLEFT", art, "TOPLEFT", 1, -1)
    t.health:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -1, 1)
    t.health:SetStatusBarTexture(BAR_TEXTURE)
    t.health:SetMinMaxValues(0, 1)
    t.health:SetValue(1)
    local healthBg = t.health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints()
    healthBg:SetColorTexture(card[1], card[2], card[3], 0.85)

    local top = CreateFrame("Frame", nil, art)
    top:SetAllPoints(art)
    top:SetFrameLevel(t.health:GetFrameLevel() + 2)
    t.top = top

    t.pct = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.pct:SetPoint("RIGHT", top, "RIGHT", -3, 0)
    t.pct:SetJustifyH("RIGHT")
    t.pct:SetTextColor(Color("text")[1], Color("text")[2], Color("text")[3])
    t.pct:SetShadowOffset(1, -1)

    t.status = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.status:SetPoint("RIGHT", top, "RIGHT", -3, 0)
    t.status:SetJustifyH("RIGHT")
    t.status:SetTextColor(1, 0.35, 0.35)
    t.status:SetShadowOffset(1, -1)
    t.status:Hide()

    t.name = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.name:SetPoint("LEFT", top, "LEFT", 3, 0)
    t.name:SetPoint("RIGHT", top, "RIGHT", -30, 0)
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(false)
    t.name:SetShadowOffset(1, -1)

    t.target = MakeBorder(top, 1, 1, "OVERLAY", 7)
    local accent = Color("accent")
    t.target:SetColor(accent[1], accent[2], accent[3], 1)
    return t
end

-- Leben des Begleiters: Rohwerte nur an SetMinMaxValues/SetValue, Prozent über SetPercent
-- (lesbar selbst gerechnet, versiegelt über UnitHealthPercent mit Kurve) – nie vergleichen
local function PaintPetHealth(t, unit)
    pcall(t.health.SetMinMaxValues, t.health, 0, UnitHealthMax(unit))
    pcall(t.health.SetValue, t.health, UnitHealth(unit))

    local dead = UnitIsDeadOrGhost(unit)
    if not IsSecret(dead) and dead then
        t.status:SetText(L["Tot"])
        t.status:Show()
        t.pct:Hide()
        t.health:SetStatusBarColor(0.35, 0.35, 0.35)
        return
    end
    t.status:Hide()
    -- Begleiter haben keine Klassenfarbe: Grün, gedämpft wie die übrigen Balken
    t.health:SetStatusBarColor(ClassColor(nil))
    local ok, shown = pcall(SetPercent, t, unit)
    t.pct:SetShown(ok and shown == true)
end

-- Einheit eines sicheren Knopfs, nur wenn sie existiert (für Gruppen- und Begleiter-Knöpfe)
local function ButtonUnit(button)
    local unit = button:GetAttribute("unit")
    if type(unit) ~= "string" then return nil end
    local exists = UnitExists(unit)
    if IsSecret(exists) or not exists then return nil end
    return unit
end

local petButtons = {} -- Platz (1–5) → sicherer Begleiter-Knopf
local petByUnit = {}  -- "pet"/"partypetN" → Knopf

local function UpdatePet(button)
    local t = button.stray
    if not t or not button:IsShown() then return end
    local unit = ButtonUnit(button)
    if not unit then return end
    pcall(PaintName, t, unit)
    pcall(PaintPetHealth, t, unit)
    pcall(PaintTarget, t, unit)
    pcall(PaintRange, t, unit)
end

local function UpdatePets()
    for _, button in ipairs(petButtons) do UpdatePet(button) end
end

---------------------------------------------------------------------------
-- Sichere Knöpfe
---------------------------------------------------------------------------

local buttons = {}   -- Knöpfe des Headers in Erstellungsreihenfolge
local needSetup = {} -- im Kampf erstellte Knöpfe: Klick-/Zieh-Einrichtung nach dem Kampf

local function UpdateButton(button)
    local t = button.stray
    if not t then return end
    local unit = ButtonUnit(button)
    if not unit then return end
    pcall(PaintName, t, unit)
    pcall(PaintHealth, t, unit)
    pcall(PaintPrediction, t, unit)
    pcall(PaintPower, t, unit)
    pcall(PaintAuras, t, unit)
    pcall(PaintBuffIcons, t, unit)
    pcall(PaintTarget, t, unit)
    pcall(PaintRange, t, unit)
end

local function UpdateAll()
    for _, button in ipairs(buttons) do
        if button:IsShown() then UpdateButton(button) end
    end
    UpdatePets()
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
    t.calc, t.absorbClamp = NewCalculator()
    ResizeTile(t, h, w)
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
-- Begleiter-Knöpfe: je Platz ein SecureUnitButton mit fester Einheit (pet, partypet1–4).
-- Der Header ordnet nach INDEX: Platz 1 = du, Platz N+1 = partyN – die Position je Platz
-- ist daher fest und muss im Kampf nicht umgesetzt werden. Ein-/Ausblenden übernimmt ein
-- Zustandstreiber (sicher, auch im Kampf). Anlegen, Attribute, Größe, Position nur außerhalb
-- des Kampfes.
---------------------------------------------------------------------------

local petsActive = false -- Zustandstreiber angemeldet

-- Sichtbarkeit: wie der Header nur in einer 5er-Gruppe (nicht allein, nicht im Schlachtzug)
local function PetCondition(unit)
    return "[group:raid] hide; [nogroup] hide; [@" .. unit .. ",exists] show; hide"
end

-- Obere linke Ecke des Begleiters relativ zur oberen linken Ecke des Ankers, Platz 1–5,
-- je nach gewählter Andockstelle (partyPetAnchor) am Rahmen des Besitzers
local function PetOffset(slot)
    local w, h, sp = Dims()
    local pw, ph = PetDims()
    local x, y = PetRect(PetAnchor(), w, h, pw, ph)
    return x, -(slot - 1) * (h + sp) + y
end

local function EnsurePetButtons()
    if #petButtons > 0 then return true end
    if InCombatLockdown() then return false end
    for slot, unit in ipairs(PET_UNITS) do
        local ok, b = pcall(CreateFrame, "Button", "strayPartyPet" .. slot, anchor, "SecureUnitButtonTemplate")
        if not ok or not b then return #petButtons > 0 end
        -- Über den Gruppenkacheln (bei „oben“/„unten“ liegt der Begleiter auf der Nachbarkachel)
        b:SetFrameLevel(anchor:GetFrameLevel() + 20)
        b:SetAttribute("unit", unit)
        b:SetAttribute("type1", "target")
        b:SetAttribute("type2", "togglemenu")
        pcall(b.RegisterForClicks, b, "AnyUp")
        pcall(b.RegisterForDrag, b, "LeftButton")
        pcall(b.HookScript, b, "OnDragStart", StartDrag)
        pcall(b.HookScript, b, "OnDragStop", StopDrag)
        pcall(b.HookScript, b, "OnEnter", OnButtonEnter)
        pcall(b.HookScript, b, "OnLeave", function() GameTooltip:Hide() end)
        pcall(b.HookScript, b, "OnShow", function(self) UpdatePet(self) end)
        b.stray = BuildPetTile(b)
        b:Hide()
        petButtons[slot] = b
        petByUnit[unit] = b
    end
    return true
end

-- Größe/Position (nur außerhalb des Kampfes)
local function LayoutPetButtons()
    if InCombatLockdown() then return end
    local pw, ph = PetDims()
    for slot, b in ipairs(petButtons) do
        b:SetSize(pw, ph)
        b:ClearAllPoints()
        local x, y = PetOffset(slot)
        b:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
    end
end

-- Begleiter ein-/ausschalten (nur außerhalb des Kampfes; sonst holt Refresh es nach)
local function ApplyPets()
    if InCombatLockdown() then return false end
    local want = PetsEnabled()
    if want and not EnsurePetButtons() then want = false end
    LayoutPetButtons()
    if want and not petsActive then
        for slot, b in ipairs(petButtons) do
            pcall(RegisterStateDriver, b, "visibility", PetCondition(PET_UNITS[slot]))
        end
    elseif not want and petsActive then
        for _, b in ipairs(petButtons) do
            pcall(UnregisterStateDriver, b, "visibility")
            b:Hide()
        end
    end
    petsActive = want
    return true
end

---------------------------------------------------------------------------
-- Beispielkacheln (nur solange das stray-Fenster offen ist und du in keiner Gruppe bist)
---------------------------------------------------------------------------

local SAMPLES = {
    -- Du selbst (Name, Klasse und Ressource des eingeloggten Charakters): Schild größer als das fehlende Leben → Überschild-Strich
    -- Feste Texte (Du, Tot, Wolf) stehen deutsch hier und werden erst beim Zeichnen übersetzt
    { isPlayer = true, name = "Du", translate = true, class = "PRIEST", hp = 0.92, power = "MANA", mp = 0.7, absorb = 0.15 },
    -- Kael: laufende Heilung +30 % (eigene 20 % hell, fremde 10 % dunkler)
    { name = "Kael", class = "MAGE", hp = 0.64, power = "MANA", mp = 0.45, dispel = "Poison", icon = "Interface\\Icons\\Ability_Creature_Poison_03", healOwn = 0.2, healOther = 0.1 },
    { name = "Mira", class = "DRUID", hp = 1.0, power = "MANA", mp = 0.9, faded = true },
    { name = "Brom", class = "WARRIOR", hp = 0, power = "RAGE", mp = 0, status = "Tot" },
    -- Sera (Jägerin): Schild (gestreift) mit Schild-Symbol und „Geschwächte Seele“ (noch 9 von 15 s),
    -- dazu ihr Begleiter an der gewählten Andockstelle (nur mit „Begleiter anzeigen“)
    { name = "Sera", class = "HUNTER", hp = 0.38, power = "MANA", mp = 0.8, target = true, absorb = 0.25, soulLeft = 9, soulDuration = 15,
      pet = { name = "Wolf", translate = true, hp = 0.55 } },
}

local samples = {}

local function SamplePetEnter(self)
    if self.docking then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Begleiter – Beispiel"], 1, 1, 1)
    GameTooltip:AddLine(L["So erscheint das Tier oder der Dämon eines Gruppenmitglieds am Rahmen seines Besitzers. Breite und Höhe stellst du im stray-Fenster ein."], ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    GameTooltip:AddLine(L["Ziehen: an eine andere Seite des Besitzers andocken (lila Punkte zeigen die Andockstellen)."], 1, 1, 1, true)
    GameTooltip:AddLine(L["Shift + ziehen: ganze Gruppe verschieben."], 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function PaintSamplePet(t, p)
    t.name:SetText(p.translate and L[p.name] or p.name)
    t.health:SetMinMaxValues(0, 1)
    t.health:SetValue(p.hp)
    t.health:SetStatusBarColor(ClassColor(nil))
    t.status:Hide()
    t.pct:SetText(("%.0f%%"):format(p.hp * 100))
    t.pct:Show()
    t.target:SetShown(false)
    t.art:SetAlpha(1)
end

local function SampleEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Gruppenrahmen – Beispiel"], 1, 1, 1)
    GameTooltip:AddLine(L["Shift + ziehen zum Verschieben. Breite, Höhe und Abstand stellst du im stray-Fenster ein."], ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    GameTooltip:AddLine(L["Die Testgruppe verschwindet, wenn du das stray-Fenster schließt (oder echte Gruppenrahmen in deiner Gruppe laufen)."], 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

-- Beispielwerte sind lesbare Zahlen (Anteile 0–1)
local function PaintSamplePrediction(t, s)
    if s.status then
        ClearPrediction(t)
        return
    end
    if s.healOwn then
        SetHeals(t, 1, "split", s.healOwn, s.healOther or 0)
    else
        SetHeals(t, 1, "total", s.heal or 0)
    end
    local absorb = s.absorb or 0
    SetBar(t.absorb, 1, absorb)
    if t.hasStripes then t.stripes:SetShown(absorb > 0) end
    t.over:SetAlpha(1)
    t.over:SetShown(absorb > 0 and absorb > 1 - s.hp)
    t.shieldIcon:SetShown(absorb > 0)
    if s.soulDuration then
        pcall(t.soulIcon.SetTexture, t.soulIcon, t.soulTexture)
        t.soulIcon:Show()
        SetSoulCooldown(t, s.soulDuration, GetTime() + (s.soulLeft or s.soulDuration))
    else
        HideSoul(t)
    end
    LayoutIcons(t)
end

-- Erster Beispielplatz: eigener Charakter statt eines festen Namens
local function PlayerSample(s)
    if not s.isPlayer then return s.name, s.class, s.power end
    local name, class, power = s.translate and L[s.name] or s.name, s.class, s.power
    local n = ns.Public(UnitName("player"))
    if type(n) == "string" and n ~= "" then name = n end
    local _, c = UnitClass("player")
    c = ns.Public(c)
    if type(c) == "string" then class = c end
    local _, token = UnitPowerType("player")
    token = ns.Public(token)
    if type(token) == "string" then power = token end
    return name, class, power
end

local function PaintSample(t, s)
    local name, class, power = PlayerSample(s)
    t.name:SetText(name)
    t.health:SetMinMaxValues(0, 1)
    t.health:SetValue(s.hp)
    t.power:SetMinMaxValues(0, 1)
    t.power:SetValue(s.mp)
    t.power:SetStatusBarColor(PowerColor(nil, power))
    if s.status then
        t.status:SetText(L[s.status])
        t.status:Show()
        t.pct:Hide()
        t.health:SetStatusBarColor(0.35, 0.35, 0.35)
    else
        t.status:Hide()
        t.pct:SetText(("%.0f%%"):format(s.hp * 100))
        t.pct:Show()
        t.health:SetStatusBarColor(ClassColor(class))
    end
    PaintDispel(t, s.dispel ~= nil, s.icon, s.dispel)
    t.target:SetShown(s.target and true or false)
    t.art:SetAlpha(s.faded and FADED or 1)
    pcall(PaintSamplePrediction, t, s)
end

local function RepaintSamples()
    for _, f in ipairs(samples) do
        if f.sample then PaintSample(f.stray, f.sample) end
        if f.petFrame and f.sample and f.sample.pet then PaintSamplePet(f.petFrame.stray, f.sample.pet) end
    end
end

local function LayoutSamples()
    local w, h, sp = Dims()
    -- Anker so groß wie die Spalte (auch bei ausgeschalteten Rahmen), damit das Bearbeiten-Overlay passt
    if not InCombatLockdown() then anchor:SetSize(w, MAX_TILES * h + (MAX_TILES - 1) * sp) end
    for i, f in ipairs(samples) do
        f:SetSize(w, h)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * (h + sp))
        ResizeTile(f.stray, h, w)
        if f.petFrame then
            local pw, ph = PetDims()
            local x, y = PetOffset(i)
            f.petFrame:SetSize(pw, ph)
            f.petFrame:ClearAllPoints()
            f.petFrame:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
        end
    end
end

---------------------------------------------------------------------------
-- Begleiter andocken: Beispiel-Begleiter ziehen (stray-Fenster offen oder Bearbeitungsmodus).
-- Beim Ziehen zeigen lila Punkte die Andockstellen am Besitzer, ein Umriss die nächste Stelle;
-- beim Loslassen rastet er dort ein. Gespeichert wird nur die Seite (partyPetAnchor).
---------------------------------------------------------------------------

local dock -- Hinweis-Rahmen über der Besitzer-Kachel

-- Mittelpunkt des Andockpunkts am Besitzer, relativ zu dessen oberer linker Ecke
local function DockPoint(where, w, h, ph)
    local half = math.min(ph, h) / 2
    if where == "TOP" then return w / 2, 0 end
    if where == "BOTTOM" then return w / 2, -h end
    local x = (where:sub(1, 4) == "LEFT") and 0 or w
    if where:find("_TOP", 1, true) then return x, -half end
    if where:find("_BOTTOM", 1, true) then return x, -h + half end
    return x, -h / 2
end

-- Hinweis-Rahmen hängt an der Besitzer-Kachel (gleiche Skalierung wie der Begleiter)
local function EnsureDock(owner)
    if dock then return dock end
    dock = CreateFrame("Frame", nil, owner)
    dock:SetAllPoints(owner)
    dock:SetFrameStrata("HIGH")
    dock:SetFrameLevel(90)
    dock:Hide()
    dock.marks = {}
    for _, where in ipairs(PET_ANCHORS) do
        local m = dock:CreateTexture(nil, "OVERLAY")
        m:SetColorTexture(1, 1, 1, 1)
        dock.marks[where] = m
    end
    local ghost = CreateFrame("Frame", nil, dock)
    ghost.fill = ghost:CreateTexture(nil, "BACKGROUND")
    ghost.fill:SetAllPoints()
    ghost.fill:SetColorTexture(1, 1, 1, 1)
    ghost.border = MakeBorder(ghost, 1, 0, "OVERLAY", 7)
    ghost.border:SetShown(true)
    dock.ghost = ghost
    return dock
end

-- Nächste Andockstelle zum aktuellen Mittelpunkt des gezogenen Begleiters
local function NearestDock(owner, pet)
    local ol, ot = owner:GetLeft(), owner:GetTop()
    local cx, cy = pet:GetCenter()
    if not (ol and ot and cx and cy) then return PetAnchor() end
    local w, h, pw, ph = owner:GetWidth(), owner:GetHeight(), pet:GetWidth(), pet:GetHeight()
    local best, bestD
    for _, where in ipairs(PET_ANCHORS) do
        local x, y = PetRect(where, w, h, pw, ph)
        local dx = (ol + x + pw / 2) - cx
        local dy = (ot + y - ph / 2) - cy
        local d = dx * dx + dy * dy
        if not bestD or d < bestD then best, bestD = where, d end
    end
    return best
end

local function PaintDock(owner, pet, nearest)
    local d = EnsureDock(owner)
    local w, h, pw, ph = owner:GetWidth(), owner:GetHeight(), pet:GetWidth(), pet:GetHeight()
    local accent = Color("accent")
    for where, m in pairs(d.marks) do
        local x, y = DockPoint(where, w, h, ph)
        local hit = (where == nearest)
        local size = hit and 9 or 6
        m:SetSize(size, size)
        m:ClearAllPoints()
        m:SetPoint("CENTER", owner, "TOPLEFT", x, y)
        m:SetVertexColor(accent[1], accent[2], accent[3], hit and 1 or 0.55)
    end
    local x, y = PetRect(nearest, w, h, pw, ph)
    d.ghost:SetSize(pw, ph)
    d.ghost:ClearAllPoints()
    d.ghost:SetPoint("TOPLEFT", owner, "TOPLEFT", x, y)
    d.ghost.fill:SetVertexColor(accent[1], accent[2], accent[3], 0.15)
    d.ghost.border:SetColor(accent[1], accent[2], accent[3], 1)
    d:Show()
end

-- Andockstelle übernehmen: Beispiel sofort, echte sichere Knöpfe nur außerhalb des Kampfes
-- (im Kampf merkt ns.PartyApplyLayout die Änderung vor; Refresh holt sie danach nach)
local function ApplyPetAnchor()
    LayoutSamples()
    if InCombatLockdown() then
        ns.PartyApplyLayout()
        return
    end
    LayoutPetButtons()
end

local function SetPetAnchor(where)
    if not ns.db or not PET_ANCHOR_VALID[where] then return end
    ns.db.partyPetAnchor = where
    ApplyPetAnchor()
end

local function PetDragUpdate(self)
    if not self.docking or not self.owner then return end
    PaintDock(self.owner, self, NearestDock(self.owner, self))
end

local function PetDragStart(self)
    -- Shift + ziehen verschiebt wie bisher die ganze Gruppe
    if IsShiftKeyDown() then
        StartDrag()
        return
    end
    if self.docking or not self.owner or not ns.IsConfigOpen() then return end
    if not pcall(self.StartMoving, self) then return end
    self.docking = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", PetDragUpdate)
    PetDragUpdate(self)
end

local function PetDragStop(self)
    if not self.docking then
        StopDrag()
        return
    end
    self.docking = false
    self:SetScript("OnUpdate", nil)
    local where = self.owner and NearestDock(self.owner, self) or PetAnchor()
    pcall(self.StopMovingOrSizing, self)
    pcall(self.SetUserPlaced, self, false)
    if dock then dock:Hide() end
    SetPetAnchor(where)
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
        f.sample = s
        PaintSample(f.stray, s)
        f:Hide()
        if s.pet then
            local p = CreateFrame("Frame", nil, anchor)
            p:SetFrameStrata(anchor:GetFrameStrata())
            p:SetFrameLevel(anchor:GetFrameLevel() + 20)
            p:EnableMouse(true)
            p:SetMovable(true)
            p:SetClampedToScreen(true)
            p:RegisterForDrag("LeftButton")
            p.owner = f
            p:SetScript("OnDragStart", PetDragStart)
            p:SetScript("OnDragStop", PetDragStop)
            -- Verschwindet die Testgruppe mitten im Ziehen: Ziehen sauber beenden
            p:SetScript("OnHide", function(self) if self.docking then PetDragStop(self) end end)
            p:SetScript("OnEnter", SamplePetEnter)
            p:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.stray = BuildPetTile(p)
            PaintSamplePet(p.stray, s.pet)
            p:Hide()
            f.petFrame = p
        end
        samples[i] = f
    end
    LayoutSamples()
end

-- Testgruppe: Solange das stray-Fenster offen ist, erscheinen 5 Beispielspieler – auch wenn
-- die Gruppenrahmen aus sind. Nur wenn echte Rahmen in einer Gruppe laufen, bleibt sie weg.
local function UpdatePreview()
    local show = ns.IsConfigOpen() and not (Enabled() and IsInGroup())
    if show then EnsureSamples() end
    for _, f in ipairs(samples) do
        -- Beim Einblenden neu zeichnen: startet die Abklinganzeige der Testgruppe neu
        if show and not f:IsShown() and f.sample then PaintSample(f.stray, f.sample) end
        f:SetShown(show)
        local p = f.petFrame
        if p then
            -- Im Bearbeitungsmodus über dem Rahmen-Overlay (HIGH), damit sich der Begleiter ziehen lässt
            if ns.editMode then
                p:SetFrameStrata("HIGH")
                p:SetFrameLevel(60)
            else
                p:SetFrameStrata(anchor:GetFrameStrata())
                p:SetFrameLevel(anchor:GetFrameLevel() + 20)
            end
            p:SetShown(show and PetsWanted())
        end
    end
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
    -- Heilvorhersage und Schilde (per pcall registriert, falls der Client sie nicht kennt)
    "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    -- Begleiter gerufen/entlassen (meldet die Besitzer-Einheit)
    "UNIT_PET",
}

-- Diese Ereignisse zeichnen nur Heilvorhersage/Schild neu
local PREDICTION_EVENTS = {
    UNIT_HEAL_PREDICTION = true, UNIT_ABSORB_AMOUNT_CHANGED = true, UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
}
-- Häufige Ereignisse: nur den betroffenen Teil neu zeichnen (keine Aura-Suche)
local HEALTH_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true }
local POWER_EVENTS = { UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true }

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
        for _, button in ipairs(petButtons) do
            local u = button:IsShown() and ButtonUnit(button)
            if u and button.stray then pcall(PaintTarget, button.stray, u) end
        end
        return
    end
    if event == "UNIT_PET" then
        -- Neuer Begleiter: Name/Leben nach dem Zustandstreiber-Durchlauf neu zeichnen
        local petUnit = type(unit) == "string" and OWNER_PET[unit]
        local b = petUnit and petByUnit[petUnit]
        if b then C_Timer.After(0.3, function() UpdatePet(b) end) end
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
    local predictionOnly = PREDICTION_EVENTS[event]
    for _, button in ipairs(buttons) do
        if button:IsShown() and button:GetAttribute("unit") == unit then
            if predictionOnly then
                if button.stray and ButtonUnit(button) then pcall(PaintPrediction, button.stray, unit) end
            elseif HEALTH_EVENTS[event] then
                if button.stray and ButtonUnit(button) then
                    pcall(PaintHealth, button.stray, unit)
                    pcall(PaintPrediction, button.stray, unit)
                end
            elseif POWER_EVENTS[event] then
                if button.stray and ButtonUnit(button) then pcall(PaintPower, button.stray, unit) end
            else
                UpdateButton(button)
            end
        end
    end
    -- Begleiter (pet, partypet1–4): nur Leben, Name und Flags sind für sie wichtig
    local pb = petByUnit[unit]
    if pb and pb:IsShown() and pb.stray and ButtonUnit(pb) then
        if HEALTH_EVENTS[event] then
            pcall(PaintPetHealth, pb.stray, unit)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_FLAGS" then
            UpdatePet(pb)
        end
    end
end)

local function UpdateRangeAll()
    for _, button in ipairs(buttons) do
        local u = button:IsShown() and ButtonUnit(button)
        if u and button.stray then pcall(PaintRange, button.stray, u) end
    end
    for _, button in ipairs(petButtons) do
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
        if button.stray then ResizeTile(button.stray, h, w) end
    end
    LayoutPetButtons()
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
    pcall(ApplyPets)
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
    if InCombatLockdown() then ns.Print(L["Gruppenrahmen: Die Änderung gilt nach dem Kampf."]) end
end

local function ReloadNote()
    if blizzardHidden then
        ns.Print(L["Blizzards Gruppenrahmen kommen nach /reload zurück."])
    end
end

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyFrames",
    label = L["Gruppenrahmen anzeigen"],
    tooltip = L["Eigene Gruppenrahmen für Heiler: du und deine 5er-Gruppe als senkrechte Spalte (nicht im Schlachtzug). Lebensbalken in Klassenfarbe, Leben in Prozent, Ressourcenbalken, „Tot“/„Geist“/„Offline“; wer außer Reichweite ist, wird blass. Hat jemand eine Schwächung, die du entfernen kannst, bekommt die Kachel einen farbigen Rahmen (Gift grün, Krankheit braun, Fluch lila, Magie blau) und ein kleines Symbol. Außerdem zeigen die Kacheln eingehende Heilung (hellgrün), Schilde (hellblau gestreift, mit Symbol) und „Geschwächte Seele“ mit Restzeit.\n\nLinksklick wählt das Mitglied als Ziel, Rechtsklick öffnet sein Menü. Mit eingeschaltetem „Mouseover-Zauber“ (Kampf → Zaubern) heilt deine normale Heiltaste das Mitglied unter der Maus.\n\nVerschieben mit Shift + Ziehen; solange das stray-Fenster offen ist, zeigt eine Testgruppe mit 5 Spielern Größe und Position – auch wenn die Gruppenrahmen noch aus sind. Änderungen wirken nur außerhalb des Kampfes."],
    set = function(value)
        ns.db.partyFrames = value
        CombatNote()
        if not value then ReloadNote() end
        Refresh()
    end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyHideBlizzard",
    label = L["Blizzards Gruppenrahmen ausblenden"],
    tooltip = L["Blendet Blizzards eigene Gruppenrahmen aus, solange die stray-Gruppenrahmen an sind. So siehst du jedes Mitglied nur einmal.\n\nWieder einblenden: Option ausschalten und /reload eingeben (Neuladen nötig)."],
    isEnabled = function() return ns.db and ns.db.partyFrames and true or false end,
    disabledHint = L["Erst „Gruppenrahmen anzeigen“ einschalten (oben auf dieser Seite)."],
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
    label = L["Breite"],
    min = 60, max = 200, step = 1,
    tooltip = L["Breite jeder Kachel in Pixeln. Im Kampf wird die Änderung erst danach übernommen."],
    set = function(v) ns.db.partyWidth = v; ns.PartyApplyLayout() end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyHeight",
    type = "slider",
    label = L["Höhe"],
    min = 24, max = 80, step = 1,
    tooltip = L["Höhe jeder Kachel in Pixeln. Im Kampf wird die Änderung erst danach übernommen."],
    set = function(v) ns.db.partyHeight = v; ns.PartyApplyLayout() end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partySpacing",
    type = "slider",
    label = L["Abstand"],
    min = 0, max = 20, step = 1,
    tooltip = L["Abstand zwischen den Kacheln in Pixeln. Im Kampf wird die Änderung erst danach übernommen."],
    set = function(v) ns.db.partySpacing = v; ns.PartyApplyLayout() end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyBrightness",
    type = "slider",
    label = L["Helligkeit der Balken"],
    min = 30, max = 100, step = 5,
    tooltip = L["Dunkelt die Klassenfarben der Lebensbalken ab, damit die Rahmen nicht so grell leuchten (100 = volle Klassenfarbe). Die Testgruppe zeigt die Änderung sofort."],
    set = function(v)
        ns.db.partyBrightness = v
        RepaintSamples()
        pcall(RequestAll)
    end,
})

local PET_KEYWORDS = { "pet", "pets", "begleiter", "tier", "wichtel", "dämon", "daemon", "demon", "jäger", "hunter", "hexenmeister", "warlock", "partypet" }

local function PetsOptionOn()
    return ns.db and ns.db.partyFrames and ns.db.partyPets and true or false
end

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyPets",
    label = L["Begleiter anzeigen"],
    tooltip = L["Zeigt das Tier oder den Dämon eines Gruppenmitglieds (Jäger, Hexenmeister …) als kleines Fenster an seinem Rahmen (Seite unter „Begleiter-Position“, Standard links mittig): Name, Lebensbalken und Leben in Prozent. Auch dein eigener Begleiter erscheint an deinem Rahmen.\n\nLinksklick wählt den Begleiter als Ziel, Rechtsklick öffnet sein Menü; mit „Mouseover-Zauber“ (Kampf → Zaubern) heilst du ihn direkt unter der Maus. Die Testgruppe zeigt einen Begleiter bei der Jägerin. Ein- und Ausschalten wirkt nur außerhalb des Kampfes."],
    keywords = PET_KEYWORDS,
    isEnabled = function() return ns.db and ns.db.partyFrames and true or false end,
    disabledHint = L["Erst „Gruppenrahmen anzeigen“ einschalten (oben auf dieser Seite)."],
    set = function(value)
        ns.db.partyPets = value
        CombatNote()
        Refresh()
    end,
})

local PET_ANCHOR_LABELS_L = {}
for i, text in ipairs(PET_ANCHOR_LABELS) do PET_ANCHOR_LABELS_L[i] = L[text] end

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyPetAnchor",
    type = "choice",
    label = L["Begleiter-Position"],
    values = PET_ANCHORS,
    labels = PET_ANCHOR_LABELS_L,
    tooltip = L["Wo der Begleiter am Rahmen seines Besitzers andockt: links, rechts (jeweils oben, mittig oder unten), oben oder unten. Gespeichert wird nur die Seite – so sitzt jedes Tier immer an seinem Besitzer, egal an welcher Stelle der Gruppe er steht.\n\nBei offenem stray-Fenster oder im Bearbeitungsmodus kannst du auch den Beispiel-Begleiter (Wolf bei Sera) ziehen: Lila Punkte zeigen die Andockstellen, beim Loslassen rastet er an der nächsten ein. Im Kampf wird die Änderung erst danach übernommen."],
    keywords = { "pet", "begleiter", "position", "anchor", "andocken", "dock", "seite", "side", "links", "rechts", "left", "right" },
    isEnabled = PetsOptionOn,
    disabledHint = L["Erst „Begleiter anzeigen“ einschalten."],
    set = function(v)
        if not PET_ANCHOR_VALID[v] then return end
        CombatNote()
        SetPetAnchor(v)
    end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyPetWidth",
    type = "slider",
    label = L["Begleiter: Breite"],
    min = 40, max = 160, step = 1,
    tooltip = L["Breite des Begleiter-Fensters in Pixeln. Im Kampf wird die Änderung erst danach übernommen."],
    keywords = PET_KEYWORDS,
    isEnabled = PetsOptionOn,
    disabledHint = L["Erst „Begleiter anzeigen“ einschalten."],
    set = function(v) ns.db.partyPetWidth = v; ns.PartyApplyLayout() end,
})

ns.AddOption(3, "Gruppenrahmen", {
    key = "partyPetHeight",
    type = "slider",
    label = L["Begleiter: Höhe"],
    min = 14, max = 60, step = 1,
    tooltip = L["Höhe des Begleiter-Fensters in Pixeln; es sitzt an der gewählten Stelle am Rahmen des Besitzers („Begleiter-Position“). Im Kampf wird die Änderung erst danach übernommen."],
    keywords = PET_KEYWORDS,
    isEnabled = PetsOptionOn,
    disabledHint = L["Erst „Begleiter anzeigen“ einschalten."],
    set = function(v) ns.db.partyPetHeight = v; ns.PartyApplyLayout() end,
})
