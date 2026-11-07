-- stray – eigene Aktionsleisten
-- 4 Leisten à 12 Knöpfe statt Blizzards Leisten, frei verschiebbar über den Bearbeiten-Modus.
-- Optik: quadratische Knöpfe, 1-px-dunkler Rand, beschnittenes Symbol, Tastenkürzel oben rechts,
-- Anzahl unten rechts, Abklingzeit mit großer Zahl, Reichweite rot, nicht nutzbar dunkel, kein Mana blau.
--
-- Aufbau:
--   strayAB1 … strayAB4         – SecureHandlerStateTemplate (Leiste 1 mit Seitenwechsel-Treiber)
--   strayAB<l>Button<i>         – CheckButton mit SecureActionButtonTemplate, type = "action"
-- Alles Geschützte (Erzeugen, SetAttribute, SetPoint/SetSize, Show/Hide, RegisterForClicks,
-- Tastenbelegung) läuft nur außerhalb des Kampfes; im Kampf Gewünschtes wird bei
-- PLAYER_REGEN_ENABLED nachgeholt. Im Kampf ändern sich nur Texturen, Texte und Abklingzeiten.
--
-- WoW Forever kann Werte versiegeln („secret values“): versiegelte Werte werden nie verglichen
-- oder verrechnet, sondern höchstens in pcall an Anzeige-Funktionen weitergereicht.

local _, ns = ...

local IsSecret = ns.IsSecret
local Public = ns.Public

local NUM_BARS = 4
local NUM_BUTTONS = 12
local BASE_Y = 4 -- Abstand der untersten Leiste zum unteren Bildschirmrand

-- Leiste → erster Aktionsplatz und Blizzard-Tastenbefehl (wie Blizzard die Leisten belegt)
local BARS = {
    { first = 1,  binding = "ACTIONBUTTON",          paging = true }, -- Hauptleiste (mit Seitenwechsel)
    { first = 61, binding = "MULTIACTIONBAR1BUTTON" },                -- MultiBarBottomLeft
    { first = 49, binding = "MULTIACTIONBAR2BUTTON" },                -- MultiBarBottomRight
    { first = 25, binding = "MULTIACTIONBAR3BUTTON" },                -- MultiBarRight
}

local COLOR_NORMAL = { 1, 1, 1 }
local COLOR_RANGE = { 0.85, 0.15, 0.15 }
local COLOR_MANA = { 0.35, 0.45, 1 }
local COLOR_UNUSABLE = { 0.35, 0.35, 0.35 }
local BORDER_COLOR = { 0, 0, 0, 1 }
local BORDER_EQUIPPED = { 0.1, 0.6, 0.1, 1 }
local GLOW_COLOR = { 1, 0.82, 0, 1 }

local bars = {}      -- [l] = Leistenrahmen
local buttons = {}   -- alle Knöpfe
local built = false
local pending = false        -- Apply nach dem Kampf nachholen
local hidePending = false    -- Blizzards Leisten nach dem Kampf erneut verstecken
local bindingsPending = false
local showGrid = false       -- Blizzard meldet „Aktion auf dem Mauszeiger“ (ACTIONBAR_SHOWGRID)
local blizzardHidden = false

local function Enabled()
    return ns.db and ns.db.abEnabled and true or false
end

local function Dims()
    local db = ns.db or ns.defaults
    local size = tonumber(db.abSize) or 36
    local sp = tonumber(db.abSpacing) or 2
    size = math.max(24, math.min(56, math.floor(size + 0.5)))
    sp = math.max(0, math.min(10, math.floor(sp + 0.5)))
    return size, sp
end

---------------------------------------------------------------------------
-- API-Hilfen (alte globale Funktionen bevorzugt, sonst C_ActionBar)
---------------------------------------------------------------------------

local function Fn(name)
    local fn = _G[name]
    if type(fn) == "function" then return fn end
    if C_ActionBar and type(C_ActionBar[name]) == "function" then return C_ActionBar[name] end
    return nil
end

-- ok, Rückgaben … (ok = false, wenn die Funktion fehlt oder fehlschlägt)
local function Call(name, ...)
    local fn = Fn(name)
    if not fn then return false end
    return pcall(fn, ...)
end

-- Lesbarer Wahrheitswert oder nil (fehlend/versiegelt/Fehler)
local function Bool(name, ...)
    local ok, v = Call(name, ...)
    if not ok or IsSecret(v) then return nil end
    if type(v) == "nil" then return false end
    return v and v ~= 0 and true or false
end

local function ActionExists(action)
    local ok, has = Call("HasAction", action)
    if not ok then return false end
    if IsSecret(has) then return true end -- versiegelt: lieber anzeigen
    return has and true or false
end

---------------------------------------------------------------------------
-- Tastenkürzel kurz schreiben
---------------------------------------------------------------------------

local KEY_SHORT = {
    { "ALT%-", "A" }, { "CTRL%-", "C" }, { "SHIFT%-", "S" }, { "META%-", "M" },
    { "MOUSEWHEELUP", "WU" }, { "MOUSEWHEELDOWN", "WD" }, { "MIDDLEBUTTON", "M3" }, { "BUTTON", "M" },
    { "NUMPADPLUS", "N+" }, { "NUMPADMINUS", "N-" }, { "NUMPADMULTIPLY", "N*" },
    { "NUMPADDIVIDE", "N/" }, { "NUMPADDECIMAL", "N," }, { "NUMPAD", "N" },
    { "PAGEUP", "PU" }, { "PAGEDOWN", "PD" }, { "BACKSPACE", "Bks" }, { "SPACE", "Spc" },
    { "INSERT", "Ins" }, { "DELETE", "Del" }, { "HOME", "Pos1" }, { "CAPSLOCK", "Caps" },
}

local function ShortKey(key)
    if type(key) ~= "string" or key == "" then return "" end
    local s = key:upper()
    for _, pair in ipairs(KEY_SHORT) do s = s:gsub(pair[1], pair[2]) end
    return s
end

local function BindingKeys(command)
    if type(GetBindingKey) ~= "function" then return {} end
    local ok, k1, k2, k3 = pcall(GetBindingKey, command)
    if not ok then return {} end
    local keys = {}
    for _, k in ipairs({ k1, k2, k3 }) do
        if type(k) == "string" and not IsSecret(k) and k ~= "" then table.insert(keys, k) end
    end
    return keys
end

---------------------------------------------------------------------------
-- Knopf-Optik
---------------------------------------------------------------------------

local function MakeEdges(parent, layer, sublevel)
    local e = {}
    for i = 1, 4 do
        e[i] = parent:CreateTexture(nil, layer, nil, sublevel)
        e[i]:SetColorTexture(1, 1, 1, 1)
    end
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(1)
    function e:SetColor(r, g, b, a) for i = 1, 4 do self[i]:SetVertexColor(r, g, b, a or 1) end end
    function e:SetShown(show) for i = 1, 4 do self[i]:SetShown(show) end end
    return e
end

local function SetFont(fs, size)
    if not pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, "OUTLINE") then
        pcall(fs.SetFontObject, fs, "NumberFontNormalSmall")
    end
end

local function ApplyFonts(b, size)
    SetFont(b.hotkey, math.max(8, math.floor(size * 0.28 + 0.5)))
    SetFont(b.count, math.max(8, math.floor(size * 0.30 + 0.5)))
    local cd = b.cooldown
    if cd.GetCountdownFontString then
        local ok, fs = pcall(cd.GetCountdownFontString, cd)
        if ok and fs then SetFont(fs, math.max(10, math.floor(size * 0.45 + 0.5))) end
    end
end

---------------------------------------------------------------------------
-- Knopf-Zustand
---------------------------------------------------------------------------

local function ApplyColor(b)
    local c = COLOR_NORMAL
    if b.outOfRange then c = COLOR_RANGE
    elseif b.noMana then c = COLOR_MANA
    elseif b.unusable then c = COLOR_UNUSABLE end
    b.icon:SetVertexColor(c[1], c[2], c[3])
end

local function UpdateUsable(b)
    b.unusable, b.noMana = false, false
    if not b.hasAction then return ApplyColor(b) end
    local ok, usable, noMana = Call("IsUsableAction", b.action)
    if ok then
        if not IsSecret(noMana) and noMana then
            b.noMana = true
        elseif not IsSecret(usable) and not usable then
            b.unusable = true
        end
    end
    ApplyColor(b)
end

local function UpdateRange(b)
    local out = false
    if b.hasAction then
        local ok, inRange = Call("IsActionInRange", b.action)
        -- nil = keine Reichweite; versiegelt = unbekannt → normal anzeigen
        if ok and not IsSecret(inRange) and (inRange == false or inRange == 0) then out = true end
    end
    if out ~= b.outOfRange then
        b.outOfRange = out
        ApplyColor(b)
    end
end

local function ClearCooldown(cd)
    if cd.Clear then pcall(cd.Clear, cd) else pcall(cd.SetCooldown, cd, 0, 0) end
end

local function UpdateCooldown(b)
    local cd = b.cooldown
    if not b.hasAction then return ClearCooldown(cd) end
    local action = b.action

    local start, duration, enable, modRate
    local ok, a1, a2, a3, a4 = Call("GetActionCooldown", action)
    if ok then
        if type(a1) == "table" then -- C_ActionBar-Variante liefert eine Tabelle
            start, duration, enable, modRate = a1.startTime, a1.duration, a1.isEnabled, a1.modRate
        else
            start, duration, enable, modRate = a1, a2, a3, a4
        end
    end

    local readable = ok and not IsSecret(start) and not IsSecret(duration) and not IsSecret(enable)
        and not IsSecret(modRate)
    if readable then
        -- Globale Abklingzeit ohne Zahl, echte Abklingzeiten mit Zahl
        local short = type(duration) == "number" and duration <= 1.6
        pcall(cd.SetHideCountdownNumbers, cd, short and true or false)
        if type(CooldownFrame_Set) == "function" then
            if not pcall(CooldownFrame_Set, cd, start or 0, duration or 0, enable, false, modRate) then ClearCooldown(cd) end
        elseif type(start) == "number" and type(duration) == "number" and start > 0 and duration > 0 then
            pcall(cd.SetCooldown, cd, start, duration, modRate)
        else
            ClearCooldown(cd)
        end
        return
    end

    -- Versiegelt: Dauerobjekt (Midnight), sonst Werte direkt weiterreichen
    pcall(cd.SetHideCountdownNumbers, cd, false)
    if C_ActionBar and C_ActionBar.GetActionCooldownDuration and cd.SetCooldownFromDurationObject then
        local okD, durationObj = pcall(C_ActionBar.GetActionCooldownDuration, action)
        if okD and type(durationObj) ~= "nil" and pcall(cd.SetCooldownFromDurationObject, cd, durationObj) then
            return
        end
    end
    if not (ok and pcall(cd.SetCooldown, cd, start, duration)) then ClearCooldown(cd) end
end

-- Anzahl (Verbrauchsgüter, Reagenzien) bzw. Ladungen
local function CountText(action)
    local consumable = Bool("IsConsumableAction", action)
    local stackable = Bool("IsStackableAction", action)
    local item = Bool("IsItemAction", action)
    local okC, count = Call("GetActionCount", action)
    if okC and not IsSecret(count) and type(count) == "number" then
        if consumable or stackable then
            return count > 9999 and "*" or tostring(count)
        end
        if item == false and count > 0 then return tostring(count) end
    elseif okC and IsSecret(count) and (consumable or stackable) then
        return count -- versiegelt: nur an SetText weiterreichen
    end
    local okG, charges, maxCharges = Call("GetActionCharges", action)
    if okG then
        if type(charges) == "table" then
            charges, maxCharges = charges.currentCharges, charges.maxCharges
        end
        if not IsSecret(charges) and not IsSecret(maxCharges) and type(charges) == "number"
            and type(maxCharges) == "number" and maxCharges > 1 then
            return tostring(charges)
        end
    end
    return ""
end

local function UpdateCount(b)
    if not b.hasAction then b.count:SetText("") return end
    local ok, text = pcall(CountText, b.action)
    if not ok or not pcall(b.count.SetText, b.count, text) then b.count:SetText("") end
end

local function UpdateState(b)
    local checked = false
    if b.hasAction then
        checked = Bool("IsCurrentAction", b.action) or Bool("IsAutoRepeatAction", b.action) or false
    end
    b:SetChecked(checked and true or false)
    local equipped = b.hasAction and Bool("IsEquippedAction", b.action)
    local c = equipped and BORDER_EQUIPPED or BORDER_COLOR
    b.border:SetVertexColor(c[1], c[2], c[3], c[4])
end

local function SpellOverlayed(spellID)
    local fn = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, spellID)
    return ok and not IsSecret(v) and v and true or false
end

local function UpdateGlow(b)
    local glow = false
    if b.hasAction then
        local ok, kind, id = Call("GetActionInfo", b.action)
        if ok and not IsSecret(kind) and not IsSecret(id) and kind == "spell" and type(id) == "number" then
            glow = SpellOverlayed(id)
        end
    end
    b.glow:SetShown(glow)
end

local function UpdateHotkey(b)
    local text = ""
    if ns.db and ns.db.abKeybinds then
        local keys = BindingKeys(b.bindingCommand)
        if #keys == 0 then keys = BindingKeys("CLICK " .. b:GetName() .. ":LeftButton") end
        if keys[1] then text = ShortKey(keys[1]) end
    end
    b.hotkey:SetText(text)
end

-- Leere Plätze nur bei offenem stray-Fenster/Bearbeiten-Modus oder beim Ziehen einer Aktion zeigen.
-- Nur Texturen ein-/ausblenden (geht auch im Kampf), der sichere Knopf selbst bleibt sichtbar.
local function UpdateVisibility(b)
    local show = b.hasAction or showGrid or ns.IsConfigOpen()
    b.border:SetShown(show)
    b.empty:SetShown(show and not b.hasAction)
    b.icon:SetShown(b.hasAction and true or false)
    b.hotkey:SetShown(show)
    b.count:SetShown(b.hasAction and true or false)
    b.highlight:SetAlpha(show and 1 or 0)
    if not b.hasAction then b.glow:SetShown(false) end
    -- Leere, unsichtbare Plätze sollen keine Mausklicks in die Welt abfangen
    if not InCombatLockdown() then
        pcall(b.EnableMouse, b, show and true or false)
    end
end

local function UpdateButton(b)
    local action = b.action
    b.hasAction = type(action) == "number" and ActionExists(action)
    if b.hasAction then
        local ok, tex = Call("GetActionTexture", action)
        if not ok or type(tex) == "nil" or not pcall(b.icon.SetTexture, b.icon, tex) then
            b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    else
        b.icon:SetTexture(nil)
        b.outOfRange = false
    end
    pcall(UpdateCount, b)
    pcall(UpdateCooldown, b)
    pcall(UpdateUsable, b)
    pcall(UpdateRange, b)
    pcall(UpdateState, b)
    pcall(UpdateGlow, b)
    pcall(UpdateHotkey, b)
    UpdateVisibility(b)
end

local function UpdateAll()
    for _, b in ipairs(buttons) do UpdateButton(b) end
end

local requested = false
local function RequestAll()
    if requested or not built then return end
    requested = true
    C_Timer.After(0, function()
        requested = false
        if Enabled() then UpdateAll() end
    end)
end

local function ForEach(fn)
    for _, b in ipairs(buttons) do pcall(fn, b) end
end

---------------------------------------------------------------------------
-- Knöpfe erstellen (nur außerhalb des Kampfes)
---------------------------------------------------------------------------

local function OnEnter(self)
    if not self.hasAction then return end
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    if pcall(GameTooltip.SetAction, GameTooltip, self.action) then GameTooltip:Show() end
end

local function ActionBarsLocked()
    local ok, v = pcall(ns.GetCVarOn, "lockActionBars")
    if ok and type(v) == "boolean" then return v end
    return LOCK_ACTIONBAR == "1"
end

local function OnDragStart(self)
    if InCombatLockdown() or type(self.action) ~= "number" then return end
    if ActionBarsLocked() and not (IsModifiedClick and IsModifiedClick("PICKUPACTION")) then return end
    if pcall(PickupAction, self.action) then
        UpdateButton(self)
    end
end

local function OnReceiveDrag(self)
    if InCombatLockdown() or type(self.action) ~= "number" then return end
    if pcall(PlaceAction, self.action) then
        UpdateButton(self)
    end
end

local function CreateButton(bar, l, i)
    local name = "strayAB" .. l .. "Button" .. i
    local b = CreateFrame("CheckButton", name, bar, "SecureActionButtonTemplate")
    b.barIndex, b.index = l, i
    b.bindingCommand = BARS[l].binding .. i
    b.action = BARS[l].first + i - 1

    b:SetAttribute("type", "action")
    b:SetAttribute("action", b.action)
    b:SetAttribute("checkselfcast", true)
    b:SetAttribute("checkfocuscast", true)
    b:SetAttribute("checkmouseovercast", true)

    -- Rand: schwarze Fläche, Symbol 1 px eingerückt
    b.border = b:CreateTexture(nil, "BACKGROUND", nil, 0)
    b.border:SetAllPoints()
    b.border:SetColorTexture(1, 1, 1, 1)
    b.border:SetVertexColor(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], BORDER_COLOR[4])

    b.empty = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.empty:SetPoint("TOPLEFT", 1, -1)
    b.empty:SetPoint("BOTTOMRIGHT", -1, 1)
    b.empty:SetColorTexture(0.08, 0.09, 0.11, 0.6)

    b.icon = b:CreateTexture(name .. "Icon", "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.highlight = b:CreateTexture(nil, "HIGHLIGHT")
    b.highlight:SetPoint("TOPLEFT", 1, -1)
    b.highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    b.highlight:SetColorTexture(1, 1, 1, 0.15)

    local pushed = b:CreateTexture(nil, "OVERLAY", nil, 1)
    pushed:SetPoint("TOPLEFT", 1, -1)
    pushed:SetPoint("BOTTOMRIGHT", -1, 1)
    pushed:SetColorTexture(0, 0, 0, 0.35)
    if not pcall(b.SetPushedTexture, b, pushed) then pushed:Hide() end

    local checked = b:CreateTexture(nil, "OVERLAY", nil, 2)
    checked:SetPoint("TOPLEFT", 1, -1)
    checked:SetPoint("BOTTOMRIGHT", -1, 1)
    checked:SetColorTexture(1, 0.82, 0, 0.25)
    if not pcall(b.SetCheckedTexture, b, checked) then checked:Hide() end

    -- Abklingzeit (Blizzard-Countdown-Zahl in der Mitte)
    local okCD, cd = pcall(CreateFrame, "Cooldown", name .. "Cooldown", b, "CooldownFrameTemplate")
    if not okCD or not cd then cd = CreateFrame("Cooldown", name .. "Cooldown", b) end
    cd:SetPoint("TOPLEFT", 1, -1)
    cd:SetPoint("BOTTOMRIGHT", -1, 1)
    pcall(cd.SetDrawEdge, cd, false)
    pcall(cd.SetDrawBling, cd, false)
    pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.7)
    pcall(cd.SetHideCountdownNumbers, cd, false)
    b.cooldown = cd

    -- Texte und Glühen über der Abklingzeit (nicht-sicherer Unterrahmen, fängt keine Maus ab)
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints(b)
    top:SetFrameLevel(cd:GetFrameLevel() + 2)
    top:EnableMouse(false)
    b.top = top

    b.hotkey = top:CreateFontString(nil, "OVERLAY")
    b.hotkey:SetPoint("TOPRIGHT", top, "TOPRIGHT", -2, -2)
    b.hotkey:SetJustifyH("RIGHT")
    b.hotkey:SetTextColor(0.9, 0.9, 0.9)
    b.hotkey:SetWordWrap(false)

    b.count = top:CreateFontString(nil, "OVERLAY")
    b.count:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", -2, 2)
    b.count:SetJustifyH("RIGHT")
    b.count:SetTextColor(1, 1, 1)

    b.glow = MakeEdges(top, "OVERLAY", 7)
    b.glow:SetColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
    b.glow:SetShown(false)

    b.outOfRange, b.unusable, b.noMana, b.hasAction = false, false, false, false
    -- Schrift sofort setzen: SetText vor SetFont wäre ein Fehler
    ApplyFonts(b, (Dims()))

    b:RegisterForDrag("LeftButton", "RightButton")
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", OnDragStart)
    b:SetScript("OnReceiveDrag", OnReceiveDrag)
    -- CheckButton schaltet beim Klick selbst um → echten Zustand danach wieder setzen
    b:SetScript("PostClick", function(self) pcall(UpdateState, self) end)
    -- Seitenwechsel (Leiste 1) setzt „action“ neu, auch im Kampf → neu zeichnen
    b:HookScript("OnAttributeChanged", function(self, key, value)
        if key == "action" and type(value) == "number" and not IsSecret(value) then
            self.action = value
            UpdateButton(self)
        end
    end)

    table.insert(buttons, b)
    return b
end

---------------------------------------------------------------------------
-- Seitenwechsel der Leiste 1 (wie Blizzards Hauptleiste)
---------------------------------------------------------------------------

local function ConditionWorks(cond)
    if type(SecureCmdOptionParse) ~= "function" then return true end
    return pcall(SecureCmdOptionParse, cond .. " 1; 2")
end

local function BarIndex(fnName)
    local fn = _G[fnName]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    v = ok and Public(v) or nil
    if type(v) == "number" and v > 0 then return v end
    return nil
end

local function PagingDriver()
    local parts = {}
    local function Add(cond, page)
        if type(page) == "number" and ConditionWorks(cond) then
            table.insert(parts, cond .. page)
        end
    end
    -- Fahrzeug-/Übernahmeleisten (nur, falls der Client sie kennt)
    Add("[overridebar]", BarIndex("GetOverrideBarIndex"))
    Add("[vehicleui]", BarIndex("GetVehicleBarIndex"))
    Add("[shapeshift]", BarIndex("GetTempShapeshiftBarIndex"))
    Add("[bonusbar:5]", 11)
    -- Umgeschaltete Seite (Umschalt+Mausrad, „Nächste Seite“) hat Vorrang, wie bei Blizzard
    for page = 2, 6 do Add("[bar:" .. page .. "]", page) end
    -- Haltungen/Gestalten/Verstohlenheit: Krieger 1–3, Druide Katze/Schleichen/Bär/Mondkin, Schurke 1
    for n = 1, 4 do Add("[bonusbar:" .. n .. "]", 6 + n) end
    table.insert(parts, "1")
    return table.concat(parts, ";")
end

local function SetupPaging(bar)
    for i, b in ipairs(bar.buttons) do
        bar:SetFrameRef("b" .. i, b)
    end
    bar:SetAttribute("_onstate-page", [[
        local page = tonumber(newstate) or 1
        for i = 1, 12 do
            local b = self:GetFrameRef("b" .. i)
            if b then b:SetAttribute("action", (page - 1) * 12 + i) end
        end
    ]])
    RegisterStateDriver(bar, "page", PagingDriver())
end

---------------------------------------------------------------------------
-- Leisten bauen und anordnen
---------------------------------------------------------------------------

local function DefaultPoint(l)
    local size, sp = Dims()
    return { "BOTTOM", "BOTTOM", 0, BASE_Y + (l - 1) * (size + sp) }
end

local function Build()
    if built or InCombatLockdown() then return built end
    for l = 1, NUM_BARS do
        local bar = CreateFrame("Frame", "strayAB" .. l, UIParent, "SecureHandlerStateTemplate")
        bar:SetFrameStrata("MEDIUM")
        bar.buttons = {}
        for i = 1, NUM_BUTTONS do
            bar.buttons[i] = CreateButton(bar, l, i)
        end
        ns.MakeMovable(bar, "ab" .. l, DefaultPoint(l))
        -- Verschieben nur über den Bearbeiten-Modus (die Leiste ist geschützt)
        bar:EnableMouse(false)
        ns.RegisterMovable(bar, "Aktionsleiste " .. l)
        if BARS[l].paging then SetupPaging(bar) end
        bar:Hide()
        bars[l] = bar
    end
    built = true
    return true
end

local function Layout()
    if not built then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    local size, sp = Dims()
    for l, bar in ipairs(bars) do
        bar:SetSize(NUM_BUTTONS * size + (NUM_BUTTONS - 1) * sp, size)
        for i, b in ipairs(bar.buttons) do
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (size + sp), 0)
            ApplyFonts(b, size)
        end
        -- Standardstapel folgt Größe und Abstand; gespeicherte Positionen bleiben
        bar.strayDefault = DefaultPoint(l)
        pcall(ns.RestorePosition, bar)
    end
end

-- Klick bei Tastendruck: gedrückt (AnyDown) oder losgelassen (AnyUp), wie die Blizzard-Einstellung
local function RegisterClicks()
    if InCombatLockdown() then return false end
    local down = false
    local ok, v = pcall(ns.GetCVarOn, "ActionButtonUseKeyDown")
    if ok and v then down = true end
    for _, b in ipairs(buttons) do
        pcall(b.RegisterForClicks, b, down and "AnyDown" or "AnyUp")
    end
    return true
end

---------------------------------------------------------------------------
-- Tastenbelegung: Blizzards Tasten auf die stray-Knöpfe umleiten
---------------------------------------------------------------------------

local bindOwner = CreateFrame("Frame", "strayABBindings", UIParent)
local lastBindings

local function ApplyBindings()
    if not built then return end
    if InCombatLockdown() then
        bindingsPending = true
        return
    end
    bindingsPending = false
    local list, sig = {}, {}
    for _, b in ipairs(buttons) do
        for _, key in ipairs(BindingKeys(b.bindingCommand)) do
            table.insert(list, { key, b:GetName() })
            table.insert(sig, key .. "=" .. b:GetName())
        end
    end
    local signature = table.concat(sig, ";")
    -- Unverändert → nichts tun (verhindert Schleifen über UPDATE_BINDINGS)
    if signature == lastBindings then return end
    lastBindings = signature
    ClearOverrideBindings(bindOwner)
    for _, entry in ipairs(list) do
        pcall(SetOverrideBindingClick, bindOwner, false, entry[1], entry[2], "LeftButton")
    end
end

local function ClearBindings()
    if InCombatLockdown() then
        bindingsPending = true
        return
    end
    bindingsPending = false
    lastBindings = nil
    ClearOverrideBindings(bindOwner)
end

---------------------------------------------------------------------------
-- Blizzards Leisten ausblenden (Wieder-Einblenden nur per Neuladen)
---------------------------------------------------------------------------

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local hooked = {} -- eigene Tabelle statt Felder an Blizzard-Rahmen (kein Taint)

local MAIN_BARS = { "MainMenuBar", "MainActionBar" }
-- MultiBarLeft (Plätze 37–48) bleibt bei Blizzard: stray hat dafür keine eigene Leiste
local OTHER_BARS = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight" }
-- Bleiben sichtbar, auch wenn sie im Client Kinder der Hauptleiste sind
local KEEP = {
    "StanceBar", "StanceBarFrame", "PetActionBar", "PetActionBarFrame",
    "PossessBarFrame", "PossessActionBar", "MultiCastActionBarFrame",
    "MainMenuBarVehicleLeaveButton", "ExtraActionBarFrame", "ExtraAbilityContainer",
}

-- Edit-Mode-System? (nur lesen, nie schreiben)
local function IsEditModeSystem(frame)
    local ok, res = pcall(function() return frame.system ~= nil or frame.systemInfo ~= nil end)
    return ok and res
end

local function IsDescendant(frame, ancestor)
    local p = frame:GetParent()
    local depth = 0
    while p and depth < 20 do
        if p == ancestor then return true end
        p = p:GetParent()
        depth = depth + 1
    end
    return false
end

local function HideFrame(frame)
    if not frame or frame == UIParent then return end
    if frame:GetParent() == hiddenParent then return end
    if IsEditModeSystem(frame) then
        -- Edit-Mode-Systeme nicht umhängen, nur verstecken und versteckt halten
        pcall(frame.Hide, frame)
        if not hooked[frame] then
            hooked[frame] = true
            pcall(frame.HookScript, frame, "OnShow", function(self)
                if not Enabled() then return end
                if InCombatLockdown() then
                    pcall(self.SetAlpha, self, 0)
                    hidePending = true
                else
                    self:Hide()
                end
            end)
        end
        return
    end
    pcall(frame.Hide, frame)
    pcall(frame.UnregisterAllEvents, frame)
    pcall(frame.SetParent, frame, hiddenParent)
end

local function HideBlizzard()
    if InCombatLockdown() then
        hidePending = true
        return false
    end
    hidePending = false
    for _, name in ipairs(MAIN_BARS) do
        local main = _G[name]
        if main and main.GetParent then
            -- Haltungs-, Begleiter- und Sonderleisten vorher herausholen
            for _, keepName in ipairs(KEEP) do
                local keep = _G[keepName]
                if keep and keep ~= main and keep.GetParent and IsDescendant(keep, main)
                    and not IsEditModeSystem(keep) then
                    pcall(keep.SetParent, keep, UIParent)
                end
            end
            HideFrame(main)
        end
    end
    for _, name in ipairs(OTHER_BARS) do
        local f = _G[name]
        if f and f.GetParent then HideFrame(f) end
    end
    blizzardHidden = true
    return true
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

local EVENTS = {
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE",
    "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE",
    "SPELL_UPDATE_CHARGES", "UPDATE_BINDINGS", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
    "CURRENT_SPELL_CAST_CHANGED", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
    "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "UPDATE_MACROS", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED", "CVAR_UPDATE",
    "UNIT_POWER_FREQUENT", "UPDATE_SHAPESHIFT_FORMS",
}

local events = CreateFrame("Frame")
local registered = false
local ticker

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ACTIONBAR_SLOT_CHANGED" then
        local slot = Public(arg1)
        if type(slot) == "number" and slot > 0 then
            for _, b in ipairs(buttons) do
                if b.action == slot then UpdateButton(b) end
            end
        else
            RequestAll()
        end
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        ForEach(UpdateCooldown)
    elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "SPELL_UPDATE_USABLE" then
        ForEach(UpdateUsable)
    elseif event == "UNIT_POWER_FREQUENT" then
        if not IsSecret(arg1) and arg1 == "player" then ForEach(UpdateUsable) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        ForEach(UpdateRange)
        ForEach(UpdateUsable)
    elseif event == "ACTIONBAR_UPDATE_STATE" or event == "CURRENT_SPELL_CAST_CHANGED"
        or event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL"
        or event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT"
        or event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE" then
        ForEach(UpdateState)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        ForEach(UpdateGlow)
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "UNIT_INVENTORY_CHANGED"
        or event == "SPELL_UPDATE_CHARGES" then
        ForEach(UpdateCount)
    elseif event == "ACTIONBAR_SHOWGRID" then
        showGrid = true
        ForEach(UpdateVisibility)
    elseif event == "ACTIONBAR_HIDEGRID" then
        showGrid = false
        RequestAll()
    elseif event == "UPDATE_BINDINGS" then
        ApplyBindings()
        ForEach(UpdateHotkey)
    elseif event == "CVAR_UPDATE" then
        local name = Public(arg1)
        -- Je nach Client "ActionButtonUseKeyDown" oder "ACTION_BUTTON_USE_KEY_DOWN"
        if type(name) == "string" and name:upper():gsub("_", ""):find("ACTIONBUTTONUSEKEYDOWN", 1, true) then
            if not RegisterClicks() then pending = true end
        end
    else
        RequestAll()
    end
end)

local function UpdateRangeAll()
    for _, b in ipairs(buttons) do
        if b.hasAction then pcall(UpdateRange, b) end
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
            ticker = C_Timer.NewTicker(0.2, UpdateRangeAll)
        end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
end

---------------------------------------------------------------------------
-- Ein-/Ausschalten
---------------------------------------------------------------------------

local function Apply()
    if not ns.db then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    if Enabled() then
        if not Build() then
            pending = true
            return
        end
        Layout()
        RegisterClicks()
        for _, bar in ipairs(bars) do bar:Show() end
        HideBlizzard()
        lastBindings = nil
        ApplyBindings()
        SetEventsRegistered(true)
        UpdateAll()
    else
        if built then
            for _, bar in ipairs(bars) do bar:Hide() end
        end
        ClearBindings()
        SetEventsRegistered(false)
    end
end

ns.On("PLAYER_LOGIN", function() Apply() end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if not ns.db then return end
    for _, b in ipairs(buttons) do pcall(UpdateVisibility, b) end
    if pending then Apply() end
    if bindingsPending then
        if Enabled() then ApplyBindings() else ClearBindings() end
    end
    if hidePending and Enabled() then
        -- Im Kampf auf Alpha 0 gesetzte Blizzard-Leisten jetzt richtig verstecken
        for frame in pairs(hooked) do
            pcall(frame.Hide, frame)
            pcall(frame.SetAlpha, frame, 1)
        end
        HideBlizzard()
    end
end)

ns.OnConfig(function() if Enabled() then RequestAll() end end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

StaticPopupDialogs["STRAY_AB_RELOAD"] = {
    text = "stray: Blizzards Aktionsleisten kommen erst nach dem Neuladen zurück.\nJetzt neu laden?",
    button1 = "Neu laden",
    button2 = "Später",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CombatNote()
    if InCombatLockdown() then ns.Print("Aktionsleisten: Die Änderung gilt nach dem Kampf.") end
end

local function IsOn() return Enabled() end

ns.AddOption(2, "Aktionsleisten", {
    key = "abEnabled",
    label = "Eigene Aktionsleisten",
    tooltip = "Ersetzt Blizzards Aktionsleisten durch 4 schlichte stray-Leisten à 12 Knöpfe. Deine Belegung und deine Tasten bleiben: Leiste 1 ist die Hauptleiste (mit Seitenwechsel bei Haltung, Gestalt, Verstohlenheit und Umschalt+Mausrad), Leiste 2 die untere linke, Leiste 3 die untere rechte und Leiste 4 die rechte Leiste. Haltungs- und Begleiterleiste bleiben von Blizzard.\n\nVerschieben über „Anzeigen verschieben“ (Bearbeiten-Modus); dort und bei offenem stray-Fenster siehst du auch die leeren Plätze. Änderungen wirken nur außerhalb des Kampfes.\n\nMit Blizzards Hauptleiste verschwinden auch die Blizzard-EP-Leiste und – falls sie daran hängen – Taschen- und Menüknöpfe: Schalte unter „Leisten & Minimap“ die stray-EP-Leiste und die Taschen- und Menüleiste ein.\n\nAusschalten erfordert Neuladen.",
    set = function(value)
        ns.db.abEnabled = value
        CombatNote()
        Apply()
        if not value and blizzardHidden then
            ns.Print("Blizzards Aktionsleisten kommen nach /reload zurück.")
            StaticPopup_Show("STRAY_AB_RELOAD")
        end
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abSize",
    type = "slider",
    label = "Knopfgröße",
    min = 24, max = 56, step = 1,
    tooltip = "Größe der Aktionsknöpfe in Pixeln. Im Kampf wird die Änderung erst danach übernommen.",
    isEnabled = IsOn,
    disabledHint = "Erst „Eigene Aktionsleisten“ einschalten.",
    set = function(v)
        ns.db.abSize = v
        CombatNote()
        Layout()
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abSpacing",
    type = "slider",
    label = "Abstand",
    min = 0, max = 10, step = 1,
    tooltip = "Abstand zwischen den Knöpfen und zwischen den gestapelten Leisten in Pixeln. Im Kampf wird die Änderung erst danach übernommen.",
    isEnabled = IsOn,
    disabledHint = "Erst „Eigene Aktionsleisten“ einschalten.",
    set = function(v)
        ns.db.abSpacing = v
        CombatNote()
        Layout()
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abKeybinds",
    label = "Tastenkürzel anzeigen",
    tooltip = "Zeigt die Taste jedes Knopfs klein oben rechts (z. B. „S1“ für Umschalt+1).",
    isEnabled = IsOn,
    disabledHint = "Erst „Eigene Aktionsleisten“ einschalten.",
    set = function(value)
        ns.db.abKeybinds = value
        ForEach(UpdateHotkey)
    end,
})
