-- stray – eigene Aktionsleisten
-- 5 Leisten à 12 Knöpfe statt Blizzards Leisten, frei verschiebbar über den Bearbeitungsmodus.
-- Teil der „stray-Oberfläche“: wirksam nur mit Hauptoption (ns.db.strayUI) und Unterschalter
-- „Eigene Aktionsleisten“ (ns.db.abEnabled). Beide Schalter stehen in hud.lua.
-- Jede Leiste einzeln an/aus, mit eigener Knopfgröße und Knöpfen pro Reihe (Raster).
-- Optik: quadratische Knöpfe, 1-px-dunkler Rand, beschnittenes Symbol, Tastenkürzel oben rechts,
-- Anzahl unten rechts, Abklingzeit mit großer Zahl, Reichweite rot, nicht nutzbar dunkel, kein Mana blau.
--
-- Aufbau:
--   strayAB1 … strayAB5         – SecureHandlerStateTemplate (Leiste 1 mit Seitenwechsel-Treiber)
--   strayAB<l>Button<i>         – CheckButton mit SecureActionButtonTemplate, type = "action"
-- Alles Geschützte (Erzeugen, SetAttribute, SetPoint/SetSize, Show/Hide, RegisterForClicks,
-- Tastenbelegung) läuft nur außerhalb des Kampfes; im Kampf Gewünschtes wird bei
-- PLAYER_REGEN_ENABLED nachgeholt. Im Kampf ändern sich nur Texturen, Texte und Abklingzeiten.
--
-- WoW Forever kann Werte versiegeln („secret values“): versiegelte Werte werden nie verglichen
-- oder verrechnet, sondern höchstens in pcall an Anzeige-Funktionen weitergereicht.

local _, ns = ...
local L = ns.L

-- Veralteter Zauberrang (Option im Bereich „Zaubern“), neu ab 0.19.0-alpha
ns.defaults.abRankCheck = false
-- Leere Plätze dauerhaft zeigen und deren Deckkraft in Prozent, neu ab 0.21.0-alpha
ns.defaults.abShowEmpty = false
ns.defaults.abEmptyAlpha = 40

local IsSecret = ns.IsSecret
local Public = ns.Public

local NUM_BARS = 5
local NUM_BUTTONS = 12
local BASE_Y = 4 -- Abstand der untersten Leiste zum unteren Bildschirmrand

-- Leiste → erster Aktionsplatz und Blizzard-Tastenbefehl (wie Blizzard die Leisten belegt)
local BARS = {
    { first = 1,  binding = "ACTIONBUTTON",          paging = true }, -- Hauptleiste (mit Seitenwechsel)
    { first = 61, binding = "MULTIACTIONBAR1BUTTON" },                -- MultiBarBottomLeft
    { first = 49, binding = "MULTIACTIONBAR2BUTTON" },                -- MultiBarBottomRight
    { first = 25, binding = "MULTIACTIONBAR3BUTTON" },                -- MultiBarRight
    { first = 37, binding = "MULTIACTIONBAR4BUTTON" },                -- MultiBarLeft („Rechts 2“)
}

local COLOR_NORMAL = { 1, 1, 1 }
local COLOR_RANGE = { 0.85, 0.15, 0.15 }
local COLOR_MANA = { 0.35, 0.45, 1 }
local COLOR_UNUSABLE = { 0.35, 0.35, 0.35 }
local BORDER_COLOR = { 0, 0, 0, 1 }
local BORDER_EQUIPPED = { 0.1, 0.6, 0.1, 1 }
local GLOW_COLOR = { 1, 0.82, 0, 1 }

-- Stil „forever“: Knopfrand fein bronze statt schwarz, leere Plätze dunkles Schieferfeld.
-- Zugriff erst zur Anzeigezeit (ns.db ist beim Laden der Datei noch nicht da).
local function Forever()
    local ok, v = pcall(function() return ns.Style and ns.Style.IsForever() end)
    return ok and v and true or false
end

-- Randfarbe der Knöpfe (stray: schwarz wie bisher)
local function BorderColor()
    if Forever() and ns.Colors and ns.Colors.line then return ns.Colors.line end
    return BORDER_COLOR
end

local bars = {}      -- [l] = Leistenrahmen
local buttons = {}   -- alle Knöpfe
local built = false
local pending = false        -- Apply nach dem Kampf nachholen
local hidePending = false    -- Blizzards Leisten nach dem Kampf erneut verstecken
local bindingsPending = false
local showGrid = false       -- Blizzard meldet „Aktion auf dem Mauszeiger“ (ACTIONBAR_SHOWGRID)
local blizzardHidden = false

local function Enabled()
    return ns.db and ns.db.strayUI and ns.db.abEnabled and true or false
end

-- Gespeicherter Wert, sonst Standardwert
local function DbVal(key)
    local v = ns.db and ns.db[key]
    if v == nil and ns.defaults then v = ns.defaults[key] end
    return v
end

local function Clamp(v, lo, hi, default)
    v = tonumber(v) or default
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

-- Soll Leiste l angezeigt werden (Einstellung, unabhängig von abEnabled)?
local function ShowWanted(l)
    local v = DbVal("abShow" .. l)
    if v == nil then return l <= 4 end
    return v and true or false
end

-- Leiste l aktiv: eigene Leisten an und Leiste eingeschaltet
local function BarActive(l)
    return Enabled() and ShowWanted(l)
end

local function BarSize(l) return Clamp(DbVal("abSize" .. l), 24, 56, 36) end
local function BarCols(l) return Clamp(DbVal("abCols" .. l), 1, NUM_BUTTONS, NUM_BUTTONS) end
local function Spacing() return Clamp(DbVal("abSpacing"), 0, 10, 2) end

-- Knopfgröße, Knöpfe pro Reihe, Zeilen, Abstand
local function BarDims(l)
    local cols = BarCols(l)
    return BarSize(l), cols, math.ceil(NUM_BUTTONS / cols), Spacing()
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

-- Dritter Eintrag true: Kürzel ist ein deutscher Sprachschlüssel, wird beim Anzeigen übersetzt.
-- Seit 0.23: Modifikatoren mit Bindestrich (S-R, C-1, A-S-2), Maustasten M3–M5, Mausrad MW↑/MW↓.
local KEY_SHORT = {
    { "ALT%-", "A-" }, { "CTRL%-", "C-" }, { "SHIFT%-", "S-" }, { "META%-", "Cmd-" },
    { "MOUSEWHEELUP", "MW↑" }, { "MOUSEWHEELDOWN", "MW↓" },
    { "MIDDLEBUTTON", "M3" }, { "BUTTON", "M" },
    { "NUMPADPLUS", "N+" }, { "NUMPADMINUS", "N-" }, { "NUMPADMULTIPLY", "N*" },
    { "NUMPADDIVIDE", "N/" }, { "NUMPADDECIMAL", "N," }, { "NUMPAD", "N" },
    { "PAGEUP", "PU" }, { "PAGEDOWN", "PD" }, { "BACKSPACE", "Bks" }, { "SPACE", "Spc" },
    { "INSERT", "Ins" }, { "DELETE", "Del" }, { "HOME", "Pos1", true }, { "CAPSLOCK", "Caps" },
}

local function ShortKey(key)
    if type(key) ~= "string" or key == "" then return "" end
    local s = key:upper()
    for _, pair in ipairs(KEY_SHORT) do s = s:gsub(pair[1], pair[3] and L[pair[2]] or pair[2]) end
    return s
end
ns.ShortKey = ShortKey -- auch für keybinds.lua

-- Alle Tasten eines Befehls (GetBindingKey liefert beliebig viele)
local function BindingKeys(command)
    if type(GetBindingKey) ~= "function" then return {} end
    local res = { pcall(GetBindingKey, command) }
    if not res[1] then return {} end
    local keys = {}
    for i = 2, #res do
        local k = res[i]
        if type(k) == "string" and not IsSecret(k) and k ~= "" then table.insert(keys, k) end
    end
    return keys
end

-- Eigener Befehl eines stray-Knopfs (Tastenbelegung per SetBindingClick, keybinds.lua)
local function ClickCommand(b)
    return "CLICK " .. b:GetName() .. ":LeftButton"
end

-- Läuft gerade die Tastenbelegung per Mouseover (keybinds.lua)?
local function KeybindMode()
    return ns.KeybindModeActive and ns.KeybindModeActive() and true or false
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

-- Tastenkürzel in Arial Narrow (hat die Pfeile für MW↑/MW↓, schmal wie Blizzards Kürzel)
local function SetHotkeyFont(fs, size)
    local ok, res = pcall(fs.SetFont, fs, "Fonts\\ARIALN.TTF", size, "OUTLINE")
    if not ok or res == false then SetFont(fs, size) end
end

local function ApplyFonts(b, size)
    SetHotkeyFont(b.hotkey, math.max(9, math.floor(size * 0.30 + 0.5)))
    -- Lange Kombinationen (A-C-S-MW↑) nicht über den Knopf hinausschreiben
    pcall(b.hotkey.SetWidth, b.hotkey, math.max(10, size - 4))
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
    -- Randfarbe nur bei belegten Plätzen; leere (auch halbtransparente) regelt UpdateVisibility
    if not b.hasAction then return end
    local equipped = Bool("IsEquippedAction", b.action)
    local c = equipped and BORDER_EQUIPPED or BorderColor()
    b.border:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
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

---------------------------------------------------------------------------
-- Veralteter Zauberrang: Pfeil oben links, wenn ein höherer Rang bekannt ist
-- (nur anzeigen, nie austauschen). Das Zauberbuch wird gedrosselt gelesen und
-- als „Name → höchster Rang“ zwischengespeichert; je Knopf nur eine Nachschau.
---------------------------------------------------------------------------

local RANK_ARROW = "Interface\\Buttons\\Arrow-Up-Up"
local PLAYER_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
local SPELL_ITEM = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell

local RANK_API = (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
    and C_SpellBook.GetSpellBookItemInfo and C_Spell and C_Spell.GetSpellName and PLAYER_BANK ~= nil) and true or false

local topRank = {}    -- [Zaubername] = { id = höchster Rang, rank = Zahl oder nil }
local rankCache = {}  -- [spellID] = Rangzahl des höheren Rangs, true (Zahl unbekannt) oder false
local rankScanned = false

local function RankCheckOn()
    return RANK_API and Enabled() and ns.db and ns.db.abRankCheck and true or false
end

-- Lesbarer Wert eines Typs, sonst nil
local function Plain(v, kind)
    if IsSecret(v) or type(v) ~= kind then return nil end
    return v
end

-- „Rang 4“ → 4 (Text des Clients, daher nur die Zahl herausziehen)
local function RankNumber(text)
    text = Plain(text, "string")
    if not text then return nil end
    return tonumber(text:match("(%d+)"))
end

local function SpellRank(id)
    if not (C_Spell and C_Spell.GetSpellSubtext) then return nil end
    local ok, sub = pcall(C_Spell.GetSpellSubtext, id)
    return ok and RankNumber(sub) or nil
end

local function BookCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then return nil end
    return v
end

-- Zauberbuch lesen: je Name der höchste bekannte Rang (keine passiven, keine der anderen Spezialisierung)
local function ScanSpellBook()
    wipe(topRank)
    wipe(rankCache)
    rankScanned = true
    local lines = BookCall(C_SpellBook.GetNumSpellBookSkillLines)
    if type(lines) ~= "number" then return end
    for line = 1, lines do
        local li = BookCall(C_SpellBook.GetSpellBookSkillLineInfo, line)
        if type(li) == "table" and type(li.offSpecID) == "nil" then
            local offset, count = Plain(li.itemIndexOffset, "number"), Plain(li.numSpellBookItems, "number")
            if offset and count then
                for slot = offset + 1, offset + count do
                    local info = BookCall(C_SpellBook.GetSpellBookItemInfo, slot, PLAYER_BANK)
                    if type(info) == "table" then
                        local id, name = Plain(info.spellID, "number"), Plain(info.name, "string")
                        local isSpell = SPELL_ITEM == nil or Plain(info.itemType, "number") == SPELL_ITEM
                        local passive = Plain(info.isPassive, "boolean") == true
                        local low = BookCall(C_SpellBook.IsSpellBookItemLowRank, slot, PLAYER_BANK) == true
                        if id and name and isSpell and not passive and not low then
                            local rank = RankNumber(info.subName) or SpellRank(id)
                            local old = topRank[name]
                            -- Zwei Einträge gleichen Namens: der höhere Rang gewinnt
                            if not old or (rank and (not old.rank or rank > old.rank)) then
                                topRank[name] = { id = id, rank = rank }
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Höherer Rang für spellID? Gibt Rangzahl, true (höher, Zahl unbekannt) oder false zurück
local function HigherRank(id)
    local cached = rankCache[id]
    if cached ~= nil then return cached end
    local result = false
    local okN, name = pcall(C_Spell.GetSpellName, id)
    name = okN and Plain(name, "string") or nil
    local top = name and topRank[name]
    if top and top.id ~= id then
        local mine = SpellRank(id)
        if top.rank and mine then
            if top.rank > mine then result = top.rank end
        elseif C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.IsSpellBookItemLowRank then
            -- Ränge nicht lesbar: Blizzards Kennzeichen „niedriger Rang“ im Zauberbuch nehmen
            local okF, slot, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, id)
            slot = okF and Plain(slot, "number") or nil
            bank = okF and Plain(bank, "number") or nil
            if slot and (bank == nil or bank == PLAYER_BANK)
                and BookCall(C_SpellBook.IsSpellBookItemLowRank, slot, PLAYER_BANK) == true then
                result = top.rank or true
            end
        end
    end
    rankCache[id] = result
    return result
end

local function UpdateRank(b)
    local higher = false
    if b.hasAction and RankCheckOn() then
        if not rankScanned then pcall(ScanSpellBook) end
        local ok, kind, id = Call("GetActionInfo", b.action)
        if ok and not IsSecret(kind) and not IsSecret(id) and kind == "spell" and type(id) == "number" then
            higher = HigherRank(id)
        end
    end
    b.rankUp = higher
    b.rankArrow:SetShown(higher and true or false)
end

-- Zauberbuch geändert: gedrosselt neu lesen und alle Knöpfe nachziehen
local rankQueued = false
local function QueueRankScan()
    rankScanned = false
    wipe(rankCache)
    if rankQueued or not built then return end
    rankQueued = true
    C_Timer.After(0.5, function()
        rankQueued = false
        if RankCheckOn() then pcall(ScanSpellBook) end
        for _, b in ipairs(buttons) do pcall(UpdateRank, b) end
    end)
end

-- Tasten eines Knopfs: eigene (CLICK-Befehl des Knopfs) und geerbte (Blizzards Leistenbefehl,
-- per Override auf den Knopf umgeleitet, nur bei angezeigter Leiste)
local function ButtonKeys(b)
    local own = BindingKeys(ClickCommand(b))
    local inherited = BarActive(b.barIndex) and BindingKeys(b.bindingCommand) or {}
    return own, inherited
end

local function UpdateHotkey(b)
    local text = ""
    if (ns.db and ns.db.abKeybinds) or KeybindMode() then
        local own, inherited = ButtonKeys(b)
        local key = own[1] or inherited[1]
        if key then text = ShortKey(key) end
    end
    b.hotkey:SetText(text)
end

-- „Leere Plätze immer zeigen“ an?
local function ShowEmptyOn()
    return ns.db and ns.db.abShowEmpty and true or false
end

-- Deckkraft leerer Plätze 0–1 (Einstellung in Prozent)
local function EmptyAlpha()
    return Clamp(DbVal("abEmptyAlpha"), 0, 100, 40) / 100
end

-- Leere Plätze nur bei offenem stray-Fenster/Bearbeiten-Modus oder beim Ziehen einer Aktion zeigen.
-- Mit „Leere Plätze immer zeigen“ zusätzlich dauerhaft als schwarze Fläche mit dünnem Rand,
-- dann aber ohne Maus (Klicks gehen weiter in die Welt).
-- Nur Texturen ein-/ausblenden (geht auch im Kampf), der sichere Knopf selbst bleibt sichtbar.
local function UpdateVisibility(b)
    local show = b.hasAction or showGrid or ns.IsConfigOpen() or KeybindMode()
    -- Dauerhaft gezeigter leerer Platz (nur Optik, keine Maus)
    local ghost = not show and ShowEmptyOn()
    if ghost then
        local a = EmptyAlpha()
        local gc = Forever() and BorderColor() or { 0, 0, 0 }
        b.border:SetVertexColor(gc[1], gc[2], gc[3], a)
        b.emptyEdge:SetColor(gc[1], gc[2], gc[3], math.min(1, a * 2))
    elseif not b.hasAction then
        local c = BorderColor()
        b.border:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
    b.emptyEdge:SetShown(ghost)
    b.border:SetShown(show or ghost)
    b.empty:SetShown(show and not b.hasAction)
    b.icon:SetShown(b.hasAction and true or false)
    b.hotkey:SetShown(show or ghost)
    b.count:SetShown(b.hasAction and true or false)
    b.highlight:SetAlpha(show and 1 or 0)
    if not b.hasAction then
        b.glow:SetShown(false)
        b.rankArrow:SetShown(false)
    end
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
    pcall(UpdateRank, b)
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
    if pcall(GameTooltip.SetAction, GameTooltip, self.action) then
        local higher = self.rankUp
        if higher and RankCheckOn() then
            if type(higher) == "number" then
                GameTooltip:AddLine(L("stray: höherer Rang bekannt (Rang %d)", higher), 0.4, 1, 0.4)
            else
                GameTooltip:AddLine(L["stray: höherer Rang bekannt"], 0.4, 1, 0.4)
            end
        end
        GameTooltip:Show()
    end
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
    local bc = BorderColor()
    b.border:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)

    b.empty = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.empty:SetPoint("TOPLEFT", 1, -1)
    b.empty:SetPoint("BOTTOMRIGHT", -1, 1)
    b.empty:SetColorTexture(0.094, 0.094, 0.118, 0.6) -- ns.Colors.card
    if Forever() then
        local ok, r, g, bl = pcall(ns.Style.FillColor, "inset")
        if ok and r then b.empty:SetColorTexture(r, g, bl, 0.85) end
    end

    -- Dünner Rand für dauerhaft gezeigte leere Plätze („Leere Plätze immer zeigen“)
    b.emptyEdge = MakeEdges(b, "BACKGROUND", 2)
    b.emptyEdge:SetShown(false)

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

    -- Pfeil „höherer Rang bekannt“ oben links (auf dem nicht-sicheren Unterrahmen, keine Maus)
    b.rankArrow = top:CreateTexture(nil, "OVERLAY", nil, 6)
    b.rankArrow:SetSize(14, 14)
    b.rankArrow:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 1)
    if b.rankArrow:SetTexture(RANK_ARROW) == false then
        b.rankArrow:SetColorTexture(0.4, 1, 0.4, 0.9)
        b.rankArrow:SetSize(6, 6)
        b.rankArrow:SetPoint("TOPLEFT", top, "TOPLEFT", 2, -2)
    else
        pcall(b.rankArrow.SetDesaturated, b.rankArrow, true)
        b.rankArrow:SetVertexColor(0.4, 1, 0.4)
    end
    b.rankArrow:Hide()
    b.rankUp = false

    b.outOfRange, b.unusable, b.noMana, b.hasAction = false, false, false, false
    -- Schrift sofort setzen: SetText vor SetFont wäre ein Fehler
    ApplyFonts(b, BarSize(l))

    b:RegisterForDrag("LeftButton", "RightButton")
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", OnDragStart)
    b:SetScript("OnReceiveDrag", OnReceiveDrag)
    -- CheckButton schaltet beim Klick selbst um → echten Zustand danach wieder setzen
    -- Shift (Aufheben-Taste) + Mausklick bei gesperrten Leisten: nur aufheben, nicht auslösen
    -- (wie Blizzards Knöpfe). Nur außerhalb des Kampfes und nur für echte Mausklicks, damit
    -- Tastenbelegungen mit Shift weiter funktionieren.
    b:SetScript("PreClick", function(self, button, down)
        if InCombatLockdown() then return end
        -- Sicherheitsnetz: falls eine frühere Unterdrückung nicht zurückgenommen wurde
        if self.strayNoUse then
            self.strayNoUse = nil
            pcall(self.SetAttribute, self, "type", "action")
        end
        if not down then return end
        if not (IsModifiedClick and IsModifiedClick("PICKUPACTION")) then return end
        if not ActionBarsLocked() then return end
        if GetCursorInfo() then return end
        if not (IsMouseButtonDown and IsMouseButtonDown(button)) then return end
        if pcall(self.SetAttribute, self, "type", nil) then self.strayNoUse = true end
    end)
    b:SetScript("PostClick", function(self)
        if self.strayNoUse and not InCombatLockdown() then
            self.strayNoUse = nil
            pcall(self.SetAttribute, self, "type", "action")
        end
        pcall(UpdateState, self)
    end)
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

-- Standard: angezeigte Leisten mittig unten übereinander (1 unten, 5 oben)
local function DefaultPoint(l)
    local y = BASE_Y
    for k = 1, l - 1 do
        if ShowWanted(k) then
            local size, _, rows, sp = BarDims(k)
            y = y + rows * size + (rows - 1) * sp + sp
        end
    end
    return { "BOTTOM", "BOTTOM", 0, y }
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
        -- Verschieben nur über den Bearbeitungsmodus (die Leiste ist geschützt)
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
    for l, bar in ipairs(bars) do
        local size, cols, rows, sp = BarDims(l)
        bar:SetSize(cols * size + (cols - 1) * sp, rows * size + (rows - 1) * sp)
        for i, b in ipairs(bar.buttons) do
            local r, c = math.floor((i - 1) / cols), (i - 1) % cols
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", c * (size + sp), -r * (size + sp))
            ApplyFonts(b, size)
        end
        -- Standardstapel folgt Zeilen, Größe und Abstand; gespeicherte Positionen bleiben
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
        -- Ausgeschaltete Leisten: Tasten bleiben bei Blizzards (unsichtbaren) Knöpfen
        if BarActive(b.barIndex) then
            for _, key in ipairs(BindingKeys(b.bindingCommand)) do
                table.insert(list, { key, b:GetName() })
                table.insert(sig, key .. "=" .. b:GetName())
            end
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
-- Alle vier Zusatzleisten, auch MultiBarLeft (Plätze 37–48 = stray-Leiste 5) – unabhängig davon,
-- ob die jeweilige stray-Leiste angezeigt wird
local OTHER_BARS = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }
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

-- Rest-Rahmen unten (Forever/Camelot): Mikromenü und Taschenleiste stehen dort in der untersten Reihe
-- neben der Hauptleiste und tragen eigene dunkle Leistenkunst (BorderArt, BackgroundArt). Holt die
-- stray-Taschen- und Menüleiste die Knöpfe heraus, bleibt ein leerer dunkler Rahmen stehen.
-- Nur diese Texturen unsichtbar machen; die Rahmen selbst bleiben (Knöpfe könnten noch daran hängen),
-- nichts wird umgehängt oder im Edit Mode verändert.
local ART_FRAMES = { "MicroMenu", "BagsBar" }
local ART_KEYS = { "BorderArt", "BackgroundArt" }

local artHidden = {} -- [Textur] = { alpha, shown } vor dem Ausblenden (eigene Tabelle, keine Felder)

local function HideBarArt()
    for _, name in ipairs(ART_FRAMES) do
        local f = _G[name]
        if type(f) == "table" then
            for _, key in ipairs(ART_KEYS) do
                local ok, tex = pcall(function() return f[key] end)
                if ok and type(tex) == "table" and tex.SetAlpha then
                    if not artHidden[tex] then
                        local okA, alpha = pcall(tex.GetAlpha, tex)
                        local okS, shown = pcall(tex.IsShown, tex)
                        artHidden[tex] = { alpha = okA and alpha or 1, shown = (not okS) or shown }
                    end
                    pcall(tex.SetAlpha, tex, 0)
                    pcall(tex.Hide, tex)
                end
            end
        end
    end
end

-- Zurück, wenn „Eigene Aktionsleisten“ aus ist. hud.lua ruft das beim Zurückhängen der
-- Taschen- und Menüknöpfe auf (außerhalb des Kampfes).
function ns.ShowBlizzardBarArt()
    if Enabled() then return end
    for tex, info in pairs(artHidden) do
        pcall(tex.SetAlpha, tex, type(info.alpha) == "number" and info.alpha or 1)
        if info.shown then pcall(tex.Show, tex) end
        artHidden[tex] = nil
    end
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
    HideBarArt()
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
    "UNIT_POWER_FREQUENT", "UPDATE_SHAPESHIFT_FORMS", "LEARNED_SPELL_IN_SKILL_LINE",
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
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        -- Neuer Rang gelernt o. Ä.: Zauberbuch gedrosselt neu lesen (Rang-Pfeile)
        QueueRankScan()
        RequestAll()
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
        -- Ausgeschaltete Leisten verstecken (IsShown false, z. B. für die Abklingzeiten-Verankerung)
        for l, bar in ipairs(bars) do bar:SetShown(BarActive(l)) end
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

-- Taschen- und Menüleiste unten rechts hat seit 0.22 einen eigenen Unterschalter (hud.lua)
ns.On("PLAYER_LOGIN", function()
    Apply()
end)

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
    text = L["stray: Blizzards Aktionsleisten kommen erst nach dem Neuladen zurück.\nJetzt neu laden?"],
    button1 = L["Neu laden"],
    button2 = L["Später"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CombatNote()
    if InCombatLockdown() then ns.Print(L["Aktionsleisten: Die Änderung gilt nach dem Kampf."]) end
end

local function IsOn() return Enabled() end

local DISABLED_HINT = L["Erst „stray-Oberfläche“ und darunter „Eigene Aktionsleisten“ einschalten (Oberfläche → stray-Oberfläche)."]

-- Veralteter Zauberrang: Option im Bereich „Zaubern“ (der Bereich „Aktionsleisten“ ist voll)
ns.AddOption(2, "Zaubern", {
    key = "abRankCheck",
    label = L["Veralteten Zauberrang zeigen"],
    tooltip = L["Markiert auf den stray-Aktionsleisten Zauber, von denen du schon einen höheren Rang kennst: kleiner grüner Pfeil oben links und im Tooltip die Zeile „stray: höherer Rang bekannt“ mit der Rangnummer.\n\nstray tauscht nichts aus – zieh den neuen Rang selbst aus dem Zauberbuch auf den Platz. Wer absichtlich einen niedrigen Rang nutzt (z. B. zum Manasparen), kann die Markierung einfach ignorieren."],
    isEnabled = function() return RANK_API and Enabled() end,
    disabledHint = RANK_API and DISABLED_HINT or L["Diese Spielversion liefert die nötigen Zauberbuch-Daten nicht."],
    set = function(value)
        ns.db.abRankCheck = value
        QueueRankScan()
        if not value then ForEach(UpdateRank) end
    end,
})

-- Gerade bearbeitete Leiste (nur für diese Sitzung, nicht in ns.db, nicht im Profil)
local selectedBar = 1

-- Schalter „Eigene Aktionsleisten“ steht seit 0.22 in hud.lua (Bereich „stray-Oberfläche“).
-- hud.lua ruft das auf, wenn sich die Wirkung ändert (Unterschalter oder Hauptoption).
function ns.ActionBarsToggled()
    CombatNote()
    Apply()
    if Enabled() then return end
    -- Leistenkunst von Mikromenü/Taschenleiste zurück, falls die Taschenleiste sie nicht braucht
    if not (ns.db.strayUI and ns.db.bottomBar) and not InCombatLockdown() then
        pcall(ns.ShowBlizzardBarArt)
    end
    if blizzardHidden then
        ns.Print(L["Blizzards Aktionsleisten kommen nach /reload zurück."])
        -- Texte beim Anzeigen holen, damit sie der gewählten Sprache folgen
        local dialog = StaticPopupDialogs["STRAY_AB_RELOAD"]
        if dialog then
            dialog.text = L["stray: Blizzards Aktionsleisten kommen erst nach dem Neuladen zurück.\nJetzt neu laden?"]
            dialog.button1 = L["Neu laden"]
            dialog.button2 = L["Später"]
        end
        StaticPopup_Show("STRAY_AB_RELOAD")
    end
end

---------------------------------------------------------------------------
-- Schnittstelle für die Tastenbelegung per Mouseover (keybinds.lua)
---------------------------------------------------------------------------

-- Eigene Leisten wirksam (Hauptoption + Unterschalter) und gebaut?
function ns.ActionBarsActive()
    return Enabled() and built
end

-- Alle stray-Knöpfe (leer, solange die Leisten nicht gebaut sind)
function ns.ActionBarButtons()
    return built and buttons or {}
end

-- Tasten eines Knopfs: eigene (CLICK-Befehl), geerbte (Blizzards Leistenbefehl), Befehle dazu
function ns.ActionBarButtonKeys(b)
    local own, inherited = ButtonKeys(b)
    return own, inherited, ClickCommand(b), b.bindingCommand
end

-- Befehl → Leiste, Knopf (CLICK-Befehl eines stray-Knopfs oder Blizzards Leistenbefehl), sonst nil
function ns.ActionBarCommandSlot(command)
    if type(command) ~= "string" or IsSecret(command) or command == "" then return nil end
    local l, i = command:match("^CLICK strayAB(%d)Button(%d+):LeftButton$")
    if l then return tonumber(l), tonumber(i), "stray" end
    for bl, info in ipairs(BARS) do
        local n = command:match("^" .. info.binding .. "(%d+)$")
        n = tonumber(n)
        if n and n >= 1 and n <= NUM_BUTTONS then return bl, n, "blizzard" end
    end
    return nil
end

-- Nach einer Änderung der Belegung: Umleitungen und Kürzel sofort neu (nicht auf UPDATE_BINDINGS warten)
function ns.ActionBarsRefreshBindings()
    if not built then return end
    if Enabled() then
        lastBindings = nil
        ApplyBindings()
    end
    ForEach(UpdateHotkey)
end

-- Belegungsmodus an/aus: leere Plätze zeigen bzw. wieder ausblenden, Kürzel neu
function ns.ActionBarsRefreshVisibility()
    if not built then return end
    ForEach(UpdateHotkey)
    ForEach(UpdateVisibility)
end

ns.AddOption(2, "Tastenbelegung", {
    key = "abKeybinds",
    label = L["Tastenkürzel anzeigen"],
    tooltip = L["Zeigt die Taste jedes Knopfs klein oben rechts, in Kurzform: „S-R“ = Umschalt+R, „C-1“ = Strg+1, „A-“ = Alt, „M4“ = Maustaste 4, „MW↑“ = Mausrad hoch."],
    isEnabled = IsOn,
    disabledHint = DISABLED_HINT,
    set = function(value)
        ns.db.abKeybinds = value
        ForEach(UpdateHotkey)
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abSpacing",
    type = "slider",
    label = L["Abstand"],
    min = 0, max = 10, step = 1,
    tooltip = L["Abstand zwischen den Knöpfen und zwischen den gestapelten Leisten in Pixeln (gilt für alle Leisten). Im Kampf wird die Änderung erst danach übernommen."],
    isEnabled = IsOn,
    disabledHint = DISABLED_HINT,
    set = function(v)
        ns.db.abSpacing = v
        CombatNote()
        Layout()
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abShowEmpty",
    label = L["Leere Plätze immer zeigen"],
    tooltip = L["Zeigt leere Aktionsplätze dauerhaft als schwarze Fläche mit dünnem Rand, nicht nur bei offenem stray-Fenster. Die Deckkraft stellst du darunter ein.\n\nLeere Plätze fangen trotzdem keine Klicks ab. Ziehst du einen Zauber oder Gegenstand auf die Leiste, nehmen sie ihn wie gewohnt an (nicht im Kampf)."],
    isEnabled = IsOn,
    disabledHint = DISABLED_HINT,
    set = function(value)
        ns.db.abShowEmpty = value
        ForEach(UpdateVisibility)
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abEmptyAlpha",
    type = "slider",
    label = L["Deckkraft leerer Plätze"],
    min = 0, max = 100, step = 5,
    tooltip = L["Wie deckend die schwarze Fläche leerer Plätze ist, in Prozent (0 = unsichtbar). Der Rand wird mit abgestuft."],
    isEnabled = function() return Enabled() and ShowEmptyOn() end,
    disabledHint = L["Erst ‚Leere Plätze immer zeigen‘ einschalten (direkt darüber)."],
    set = function(v)
        ns.db.abEmptyAlpha = Clamp(v, 0, 100, 40)
        ForEach(UpdateVisibility)
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abEdit",
    type = "choice",
    label = L["Leiste bearbeiten"],
    values = { 1, 2, 3, 4, 5 },
    labels = { "1", "2", "3", "4", "5" },
    noExport = true,
    tooltip = L["Wählt die Leiste, die die drei Zeilen darunter einstellen. 1 Hauptleiste, 2 unten links, 3 unten rechts, 4 rechts, 5 rechts 2."],
    isEnabled = IsOn,
    disabledHint = DISABLED_HINT,
    get = function() return selectedBar end,
    set = function(v)
        v = tonumber(v)
        if v and v >= 1 and v <= NUM_BARS then selectedBar = math.floor(v) end
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abShowSel",
    label = L["Leiste anzeigen"],
    noExport = true,
    tooltip = L["Zeigt die gewählte Leiste an. Leiste 1 ersetzt die Hauptleiste, 2 die untere linke, 3 die untere rechte, 4 die rechte und 5 die Leiste „Rechts 2“.\n\nEine ausgeschaltete Leiste ist versteckt; ihre Tasten laufen dann über Blizzards unsichtbare Leiste weiter. Im Kampf gilt die Änderung erst danach."],
    isEnabled = IsOn,
    disabledHint = DISABLED_HINT,
    get = function() return ShowWanted(selectedBar) end,
    set = function(value)
        ns.db["abShow" .. selectedBar] = value and true or false
        CombatNote()
        Apply()
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abSizeSel",
    type = "slider",
    label = L["Knopfgröße"],
    min = 24, max = 56, step = 1,
    noExport = true,
    tooltip = L["Größe der Knöpfe der gewählten Leiste in Pixeln. Im Kampf wird die Änderung erst danach übernommen."],
    isEnabled = IsOn,
    disabledHint = DISABLED_HINT,
    get = function() return BarSize(selectedBar) end,
    set = function(v)
        ns.db["abSize" .. selectedBar] = Clamp(v, 24, 56, 36)
        CombatNote()
        Layout()
    end,
})

ns.AddOption(2, "Aktionsleisten", {
    key = "abColsSel",
    type = "slider",
    label = L["Knöpfe pro Reihe"],
    min = 1, max = NUM_BUTTONS, step = 1,
    noExport = true,
    tooltip = L["Wie viele Knöpfe der gewählten Leiste nebeneinander stehen; die übrigen bilden weitere Reihen (z. B. 6 → 2 Reihen, 4 → 3 Reihen). Im Kampf wird die Änderung erst danach übernommen."],
    isEnabled = IsOn,
    disabledHint = DISABLED_HINT,
    get = function() return BarCols(selectedBar) end,
    set = function(v)
        ns.db["abCols" .. selectedBar] = Clamp(v, 1, NUM_BUTTONS, NUM_BUTTONS)
        CombatNote()
        Layout()
    end,
})
