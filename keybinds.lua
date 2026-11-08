-- stray – Tastenbelegung per Mouseover für die stray-Aktionsleisten (neu ab 0.23.0-alpha)
-- Start über den Knopf „Tasten belegen“ (Bereich „Tastenbelegung“) oder ns.StartKeybindMode()
-- (/stray keys verdrahtet ui.lua). Oben erscheint eine Leiste mit Hinweis, Speichern/Abbrechen und
-- der Wahl „alle Charaktere / nur dieser Charakter“.
--
-- Ablauf: Maus über einen stray-Knopf → eigener (nicht-sicherer) Rahmen legt sich lila darüber und
-- fängt Klicks, Mausrad und – über die Leiste – die Tastatur ab. Taste drücken = SetBindingClick auf
-- den sicheren stray-Knopf. Entf oder Rechtsklick löscht die eigenen Tasten des Knopfs.
-- Liegt eine Taste schon woanders, nimmt WoW sie dort weg (eine Taste hat nur einen Befehl); stray
-- meldet „vorher: …“. Jede Änderung wird mit dem alten Befehl gemerkt: Abbrechen spielt sie
-- rückwärts zurück. Speichern schreibt mit SaveBindings in die gewählte Belegung.
--
-- Blizzards Leistenbefehle (ACTIONBUTTON1 …) setzt stray nie selbst; ihre Tasten erreichen die
-- stray-Knöpfe weiter über die Umleitung in actionbars.lua („geerbte“ Tasten).
-- Alles nur außerhalb des Kampfes; im Kampf ist der Modus gesperrt und geht danach weiter.

local _, ns = ...
local L = ns.L

local C = ns.Colors
local FONT = "Fonts\\ARIALN.TTF"
local IsSecret = ns.IsSecret

local SETS = Enum and Enum.BindingSet
local ACCOUNT = (SETS and SETS.Account) or 1
local CHARACTER = (SETS and SETS.Character) or 2

local active = false       -- Modus läuft
local locked = false       -- im Kampf gesperrt
local hovered              -- stray-Knopf unter der Maus
local changes = {}         -- { key=, old=, new= } in Reihenfolge
local notes = {}           -- [Knopf] = letzter Hinweis (Tooltip)
local saveSet = ACCOUNT    -- gewählte Belegung zum Speichern
local reopenConfig = false -- stray-Fenster war offen → nach dem Ende wieder öffnen

local bar, overlay, dialog

function ns.KeybindModeActive()
    return active
end

---------------------------------------------------------------------------
-- API-Hilfen (alles in pcall, fehlende Funktionen abfangen)
---------------------------------------------------------------------------

local function ApiOk()
    return type(SetBinding) == "function" and type(GetBindingKey) == "function"
        and type(GetBindingAction) == "function" and type(SaveBindings) == "function"
end

local function CurrentSet()
    if type(GetCurrentBindingSet) ~= "function" then return ACCOUNT end
    local ok, v = pcall(GetCurrentBindingSet)
    if ok and not IsSecret(v) and v == CHARACTER then return CHARACTER end
    return ACCOUNT
end

-- Normaler Befehl einer Taste ("" = keiner), ohne die stray-Umleitungen
local function BindingAction(key)
    local ok, v = pcall(GetBindingAction, key)
    if not ok or IsSecret(v) or type(v) ~= "string" then return "" end
    return v
end

local function SetKey(key, command)
    local ok, res = pcall(SetBinding, key, command)
    return ok and res ~= false
end

local function BindClick(key, b, command)
    if type(SetBindingClick) == "function" then
        local ok, res = pcall(SetBindingClick, key, b:GetName(), "LeftButton")
        if ok and res ~= false then return true end
    end
    return SetKey(key, command)
end

-- Lesbarer Tastenname (Client-Text, sonst Kurzform)
local function KeyText(key)
    if type(GetBindingText) == "function" then
        local ok, v = pcall(GetBindingText, key)
        if ok and type(v) == "string" and not IsSecret(v) and v ~= "" then return v end
    end
    return ns.ShortKey and ns.ShortKey(key) or key
end

local function KeyList(keys)
    local out = {}
    for i, k in ipairs(keys) do out[i] = KeyText(k) end
    return table.concat(out, ", ")
end

local function Label(b)
    return L("Aktionsleiste %d, Knopf %d", b.barIndex or 0, b.index or 0)
end

-- Befehl für Menschen: stray-/Blizzard-Leistenplatz oder Blizzards Befehlsname
local function Describe(command)
    local l, i
    if ns.ActionBarCommandSlot then l, i = ns.ActionBarCommandSlot(command) end
    if l then return L("Aktionsleiste %d, Knopf %d", l, i) end
    local name = _G["BINDING_NAME_" .. command]
    if type(name) == "string" and name ~= "" then return name end
    return command
end

local function Contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Taste mit gedrückten Modifikatoren (Reihenfolge wie Blizzard: ALT-CTRL-SHIFT-META)
local function Chord(key)
    local parts = {}
    if IsAltKeyDown() then table.insert(parts, "ALT") end
    if IsControlKeyDown() then table.insert(parts, "CTRL") end
    if IsShiftKeyDown() then table.insert(parts, "SHIFT") end
    if type(IsMetaKeyDown) == "function" and IsMetaKeyDown() then table.insert(parts, "META") end
    table.insert(parts, key)
    return table.concat(parts, "-")
end

-- Tasten, die allein nichts auslösen
local IGNORED = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, SHIFT = true, CTRL = true, ALT = true, META = true,
    UNKNOWN = true, PRINTSCREEN = true,
}

local MOUSE = {
    MiddleButton = "BUTTON3", Button3 = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5",
}

---------------------------------------------------------------------------
-- Optik-Helfer (stray-Farben über ns.Colors)
---------------------------------------------------------------------------

local function Tex(parent, layer, c, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

local function Edges(f, c, size, layer)
    size = size or 1
    local e = {}
    for i = 1, 4 do e[i] = Tex(f, layer or "BORDER", c) end
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(size)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(size)
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(size)
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(size)
    return e
end

local function Recolor(edges, c)
    for i = 1, 4 do edges[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

local function Text(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local ok, res = pcall(fs.SetFont, fs, FONT, size, "")
    if not ok or res == false then fs:SetFontObject("GameFontHighlight") end
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetWordWrap(false)
    return fs
end

-- Knopf mit Rand; primary = lila umrandet. SetLabel passt die Breite an.
local function MakeButton(parent, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    b.bg = Tex(b, "BACKGROUND", C.card)
    b.bg:SetAllPoints()
    b.edges = Edges(b, primary and C.accent or C.line)
    b.text = Text(b, 13, primary and C.accentText or C.text)
    b.text:SetPoint("CENTER")
    function b:SetLabel(s)
        self.text:SetText(s)
        local w = self.text:GetStringWidth() or 60
        self:SetWidth(math.floor(w + 24 + 0.5))
    end
    function b:SetSelected(on)
        self.selected = on
        Recolor(self.edges, on and C.accent or C.line)
        local c = on and C.accentText or C.textDim
        self.text:SetTextColor(c[1], c[2], c[3])
        self.bg:SetColorTexture(unpack(on and C.hover or C.card))
    end
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self.bg:SetColorTexture(unpack(C.hover)) end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.selected then self.bg:SetColorTexture(unpack(C.card)) end
    end)
    return b
end

---------------------------------------------------------------------------
-- Leiste oben: Anzeige aktualisieren
---------------------------------------------------------------------------

local function SetLabel()
    return saveSet == CHARACTER and L["nur für diesen Charakter"] or L["für alle Charaktere"]
end

local function UpdateBar()
    if not bar then return end
    bar.title:SetText(L["Tasten belegen"])
    bar.hint:SetText(L["über einen Knopf fahren und Taste drücken · Esc: fertig"])
    bar.help:SetText(L["Mit Shift / Strg / Alt, Maustasten 3–5 und Mausrad · Entf oder Rechtsklick: Tasten des Knopfs löschen"])
    bar.forLabel:SetText(L["Speichern für:"])
    bar.save:SetLabel(L["Speichern"])
    bar.cancel:SetLabel(L["Abbrechen"])
    bar.account:SetLabel(L["Alle Charaktere"])
    bar.character:SetLabel(L["Nur dieser Charakter"])
    bar.account:SetSelected(saveSet == ACCOUNT)
    bar.character:SetSelected(saveSet == CHARACTER)
    bar.save:SetEnabled(not locked)
    bar.cancel:SetEnabled(not locked)
    if locked then
        bar.status:SetText(L["Im Kampf gesperrt – geht nach dem Kampf weiter."])
        bar.status:SetTextColor(1, 0.45, 0.45)
    elseif bar.message then
        bar.status:SetText(bar.message)
        bar.status:SetTextColor(C.text[1], C.text[2], C.text[3])
    else
        local n = #changes
        bar.status:SetText(n == 0 and L["Noch keine Änderung"] or L("Ungespeicherte Änderungen: %d", n))
        bar.status:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end
end

local function Status(msg)
    if bar then bar.message = msg end
    UpdateBar()
end

---------------------------------------------------------------------------
-- Tooltip am Knopf unter der Maus
---------------------------------------------------------------------------

local function ShowTooltip()
    if not overlay or not hovered then return end
    GameTooltip:SetOwner(overlay, "ANCHOR_TOP")
    GameTooltip:AddLine(Label(hovered), C.accentText[1], C.accentText[2], C.accentText[3])
    local own, inherited = ns.ActionBarButtonKeys(hovered)
    if #own > 0 then
        GameTooltip:AddLine(L("Tasten: %s", KeyList(own)), 1, 1, 1)
    elseif #inherited == 0 then
        GameTooltip:AddLine(L["Keine Taste belegt"], C.textDim[1], C.textDim[2], C.textDim[3])
    end
    if #inherited > 0 then
        GameTooltip:AddLine(L("Über Blizzards Belegung: %s", KeyList(inherited)), 0.85, 0.85, 0.85)
    end
    local note = notes[hovered]
    if note then GameTooltip:AddLine(note, 1, 0.82, 0, true) end
    GameTooltip:AddLine(L["Taste drücken: belegen · Entf oder Rechtsklick: löschen"],
        C.textDim[1], C.textDim[2], C.textDim[3], true)
    GameTooltip:Show()
end

local function HideTooltip()
    if overlay and GameTooltip:GetOwner() == overlay then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Belegen und Löschen
---------------------------------------------------------------------------

local function AfterChange()
    if ns.ActionBarsRefreshBindings then pcall(ns.ActionBarsRefreshBindings) end
    ShowTooltip()
end

local function Assign(b, key)
    if InCombatLockdown() or not b then return end
    local own, inherited, command, blizzCommand = ns.ActionBarButtonKeys(b)
    local old = BindingAction(key)
    if old == command or Contains(own, key) or (old == blizzCommand and Contains(inherited, key)) then
        notes[b] = nil
        Status(L("%s liegt schon auf diesem Knopf.", KeyText(key)))
        ShowTooltip()
        return
    end
    if not BindClick(key, b, command) then
        Status(L("%s lässt sich nicht belegen.", KeyText(key)))
        return
    end
    table.insert(changes, { key = key, old = old, new = command })
    if old ~= "" then
        local prev = Describe(old)
        local msg = L("%s – vorher: %s (dort entfernt)", KeyText(key), prev)
        notes[b] = L("vorher: %s", prev)
        ns.Print(L("Tastenbelegung: %s", msg))
        Status(msg)
    else
        notes[b] = nil
        Status(L("%s → %s", KeyText(key), Label(b)))
    end
    AfterChange()
end

local function ClearButton(b)
    if InCombatLockdown() or not b then return end
    local own, inherited, command = ns.ActionBarButtonKeys(b)
    for _, key in ipairs(own) do
        if SetKey(key, nil) then
            table.insert(changes, { key = key, old = command, new = nil })
        end
    end
    if #inherited > 0 then
        -- Blizzards Leistenbefehle setzt stray nicht selbst
        notes[b] = L("%s bleibt: kommt aus Blizzards Tastaturbelegung. Dort ändern oder die Taste hier auf einen anderen Knopf legen.", KeyList(inherited))
    else
        notes[b] = nil
    end
    if #own > 0 then
        Status(L("Tasten gelöscht: %s", Label(b)))
    elseif #inherited > 0 then
        Status(notes[b])
    else
        Status(L["Dieser Knopf hat keine Taste."])
    end
    AfterChange()
end

-- Alle Änderungen rückwärts zurücknehmen (alter Befehl je Taste)
local function Revert()
    local ok = true
    for i = #changes, 1, -1 do
        local c = changes[i]
        local old = c.old ~= "" and c.old or nil
        if not SetKey(c.key, old) and old then ok = false end
    end
    wipe(changes)
    if not ok and type(LoadBindings) == "function" then
        -- Rückfall: gespeicherte Belegung neu laden (wie Blizzards Schnellbelegung beim Abbrechen)
        pcall(LoadBindings, CurrentSet())
    end
    if ns.ActionBarsRefreshBindings then pcall(ns.ActionBarsRefreshBindings) end
end

---------------------------------------------------------------------------
-- Rahmen über dem Knopf unter der Maus (lila, fängt Klicks und Mausrad)
---------------------------------------------------------------------------

local function HideOverlay()
    HideTooltip()
    hovered = nil
    if overlay then overlay:Hide() end
end

-- Absolut an UIParent setzen (nicht am sicheren Knopf verankern → bleibt ungeschützt)
local function PlaceOverlay(b)
    local left, bottom, w, h = b:GetRect()
    if type(left) ~= "number" or type(w) ~= "number" then return false end
    local s = (b:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
    overlay:SetSize(w * s, h * s)
    return true
end

local function CreateOverlay()
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(50)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)
    local fill = Tex(overlay, "ARTWORK", C.accent)
    fill:SetAllPoints()
    fill:SetAlpha(0.35)
    Edges(overlay, C.accent, 2, "OVERLAY")
    overlay:SetScript("OnMouseDown", function(_, button)
        if not hovered or locked then return end
        if button == "RightButton" then
            ClearButton(hovered)
        elseif MOUSE[button] then
            Assign(hovered, Chord(MOUSE[button]))
        end
        -- Linksklick: nichts (löst im Modus keine Aktion aus)
    end)
    overlay:SetScript("OnMouseWheel", function(_, delta)
        if not hovered or locked then return end
        Assign(hovered, Chord(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)
    overlay:Hide()
end

local function FindHovered()
    if bar:IsMouseOver() or (dialog and dialog:IsShown()) then return nil end
    for _, b in ipairs(ns.ActionBarButtons and ns.ActionBarButtons() or {}) do
        if b:IsVisible() and b:IsMouseOver() then return b end
    end
    return nil
end

local elapsedSum = 0
local function OnUpdate(_, elapsed)
    elapsedSum = elapsedSum + elapsed
    if elapsedSum < 0.03 then return end
    elapsedSum = 0
    if locked or InCombatLockdown() then
        if hovered then HideOverlay() end
        return
    end
    local b = FindHovered()
    if b == hovered then return end
    if not b then
        HideOverlay()
        return
    end
    if PlaceOverlay(b) then
        hovered = b
        overlay:Show()
        ShowTooltip()
    else
        HideOverlay()
    end
end

---------------------------------------------------------------------------
-- Rückfrage (eigener kleiner Kasten unter der Leiste, kein StaticPopup)
---------------------------------------------------------------------------

local function HideDialog()
    if dialog then dialog:Hide() end
end

-- buttons = { { text, fn, primary }, … }
local function ShowDialog(text, buttons)
    if not dialog then
        dialog = CreateFrame("Frame", nil, bar)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(bar:GetFrameLevel() + 20)
        dialog:EnableMouse(true)
        dialog:SetPoint("TOP", bar, "BOTTOM", 0, -6)
        dialog:SetWidth(460)
        Tex(dialog, "BACKGROUND", C.bg):SetAllPoints()
        Edges(dialog, C.accent)
        dialog.text = Text(dialog, 13, C.text)
        dialog.text:SetPoint("TOPLEFT", 14, -12)
        dialog.text:SetPoint("TOPRIGHT", -14, -12)
        dialog.text:SetWordWrap(true)
        dialog.text:SetJustifyH("LEFT")
        dialog.buttons = {}
    end
    dialog.text:SetText(text)
    local textH = dialog.text:GetStringHeight() or 16
    dialog:SetHeight(math.floor(12 + textH + 12 + 24 + 12 + 0.5))
    for _, btn in ipairs(dialog.buttons) do btn:Hide() end
    local prev
    for i = 1, #buttons do
        local info = buttons[i]
        local btn = dialog.buttons[i]
        if not btn then
            btn = MakeButton(dialog, false)
            dialog.buttons[i] = btn
        end
        Recolor(btn.edges, info[3] and C.accent or C.line)
        local c = info[3] and C.accentText or C.text
        btn.text:SetTextColor(c[1], c[2], c[3])
        btn:SetLabel(info[1])
        btn:ClearAllPoints()
        if prev then
            btn:SetPoint("RIGHT", prev, "LEFT", -8, 0)
        else
            btn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)
        end
        btn:SetScript("OnClick", function()
            HideDialog()
            pcall(info[2])
        end)
        btn:Show()
        prev = btn
    end
    HideOverlay()
    dialog:Show()
end

---------------------------------------------------------------------------
-- Start, Speichern, Abbrechen, Ende
---------------------------------------------------------------------------

local function Stop()
    active = false
    locked = false
    HideOverlay()
    HideDialog()
    wipe(notes)
    if bar then
        bar:SetScript("OnUpdate", nil)
        if not InCombatLockdown() then pcall(bar.EnableKeyboard, bar, false) end
        bar:Hide()
    end
    if ns.ActionBarsRefreshVisibility then pcall(ns.ActionBarsRefreshVisibility) end
    if reopenConfig and strayFrame and not InCombatLockdown() then
        pcall(strayFrame.Show, strayFrame)
    end
    reopenConfig = false
end

local function Cancel()
    if InCombatLockdown() then return end
    local had = #changes > 0
    Revert()
    Stop()
    if had then ns.Print(L["Tastenbelegung: Änderungen verworfen."]) end
end

local function DoSave()
    if InCombatLockdown() then
        Status(L["Im Kampf gesperrt – geht nach dem Kampf weiter."])
        return
    end
    local ok = true
    if saveSet == ACCOUNT and CurrentSet() == CHARACTER and type(LoadBindings) == "function" then
        -- Wie Blizzards Wechsel zur Account-Belegung: Account-Belegung laden, stray-Änderungen
        -- darauf legen, als Account-Belegung speichern (die eigene Charakter-Belegung entfällt)
        pcall(LoadBindings, ACCOUNT)
        for _, c in ipairs(changes) do SetKey(c.key, c.new) end
        ok = pcall(SaveBindings, ACCOUNT)
    else
        ok = pcall(SaveBindings, saveSet)
    end
    local label = SetLabel()
    wipe(changes)
    Stop()
    if ok then
        ns.Print(L("Tastenbelegung gespeichert (%s).", label))
    else
        ns.Print(L["Tastenbelegung: Speichern hat nicht geklappt."])
    end
    if ns.ActionBarsRefreshBindings then pcall(ns.ActionBarsRefreshBindings) end
end

local function Save()
    if locked or InCombatLockdown() then return end
    if #changes == 0 and saveSet == CurrentSet() then
        Stop()
        return
    end
    if saveSet == ACCOUNT and CurrentSet() == CHARACTER then
        ShowDialog(L["Dieser Charakter hat bisher eine eigene Tastenbelegung. „Alle Charaktere“ übernimmt die Belegung für alle Charaktere und legt deine Änderungen darauf – die eigene Belegung dieses Charakters entfällt (wie im Blizzard-Menü)."], {
            { L["Für alle speichern"], DoSave, true },
            { L["Zurück"], function() end },
        })
        return
    end
    DoSave()
end

-- Esc: fertig – mit Rückfrage, wenn noch etwas ungespeichert ist
local function RequestFinish()
    if #changes == 0 then
        Stop()
        return
    end
    ShowDialog(L("Es gibt %d ungespeicherte Änderungen. Speichern?", #changes), {
        { L["Speichern"], Save, true },
        { L["Verwerfen"], Cancel },
        { L["Weiter belegen"], function() end },
    })
end

-- Tastatur der Leiste: Esc immer, sonst nur über einem Knopf; alles andere geht ans Spiel weiter
local function HandleKey(key)
    if type(key) ~= "string" then return false end
    if dialog and dialog:IsShown() then
        if key == "ESCAPE" then
            HideDialog()
            return true
        end
        return false
    end
    if key == "ESCAPE" then
        RequestFinish()
        return true
    end
    if locked or not hovered or IGNORED[key] then return false end
    if key == "DELETE" then
        ClearButton(hovered)
        return true
    end
    Assign(hovered, Chord(key))
    return true
end

local function CreateBar()
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetFrameLevel(40)
    bar:SetClampedToScreen(true)
    bar:SetSize(780, 96)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -14)
    bar:EnableMouse(true)
    Tex(bar, "BACKGROUND", C.bg):SetAllPoints()
    Edges(bar, C.line)
    local top = Tex(bar, "ARTWORK", C.accent)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)

    -- Zeile 1: Titel, Hinweis, Speichern/Abbrechen
    bar.title = Text(bar, 16, C.accentText)
    bar.title:SetPoint("LEFT", bar, "TOPLEFT", 14, -22)
    bar.hint = Text(bar, 13, C.text)
    bar.hint:SetPoint("LEFT", bar.title, "RIGHT", 10, 0)

    bar.save = MakeButton(bar, true)
    bar.save:SetPoint("RIGHT", bar, "TOPRIGHT", -12, -22)
    bar.save:SetScript("OnClick", Save)
    bar.cancel = MakeButton(bar, false)
    bar.cancel:SetPoint("RIGHT", bar.save, "LEFT", -8, 0)
    bar.cancel:SetScript("OnClick", Cancel)

    -- Zeile 2: Speichern für … / Status
    bar.forLabel = Text(bar, 13, C.textDim)
    bar.forLabel:SetPoint("LEFT", bar, "TOPLEFT", 14, -52)
    bar.account = MakeButton(bar, false)
    bar.account:SetPoint("LEFT", bar.forLabel, "RIGHT", 10, 0)
    bar.account:SetScript("OnClick", function()
        saveSet = ACCOUNT
        UpdateBar()
    end)
    bar.character = MakeButton(bar, false)
    bar.character:SetPoint("LEFT", bar.account, "RIGHT", 6, 0)
    bar.character:SetScript("OnClick", function()
        saveSet = CHARACTER
        UpdateBar()
    end)
    bar.status = Text(bar, 13, C.textDim)
    bar.status:SetPoint("RIGHT", bar, "TOPRIGHT", -14, -52)
    bar.status:SetPoint("LEFT", bar.character, "RIGHT", 16, 0)
    bar.status:SetJustifyH("RIGHT")

    -- Zeile 3: Hilfe auf abgesetzter Fläche
    local helpBg = Tex(bar, "BORDER", C.card)
    helpBg:SetPoint("BOTTOMLEFT", 1, 1); helpBg:SetPoint("BOTTOMRIGHT", -1, 1)
    helpBg:SetHeight(24)
    local line = Tex(bar, "ARTWORK", C.line)
    line:SetPoint("BOTTOMLEFT", 1, 25); line:SetPoint("BOTTOMRIGHT", -1, 25)
    line:SetHeight(1)
    bar.help = Text(bar, 12, C.textDim)
    bar.help:SetPoint("CENTER", bar, "BOTTOM", 0, 13)

    -- Tastatur nur außerhalb des Kampfes an (EnableKeyboard/SetPropagateKeyboardInput sind dort gesperrt)
    bar:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local handled = HandleKey(key)
        pcall(self.SetPropagateKeyboardInput, self, not handled)
    end)
    bar:Hide()
end

local function KeysOn(on)
    if not bar or InCombatLockdown() then return end
    pcall(bar.EnableKeyboard, bar, on and true or false)
    if on then pcall(bar.SetPropagateKeyboardInput, bar, true) end
end

function ns.StartKeybindMode()
    if active then return end
    if InCombatLockdown() then
        ns.Print(L["Tasten belegen geht nur außerhalb des Kampfes."])
        return
    end
    if not ApiOk() then
        ns.Print(L["Diese Spielversion erlaubt das Belegen von Tasten durch Addons nicht."])
        return
    end
    if not (ns.ActionBarsActive and ns.ActionBarsActive()) then
        ns.Print(L["Tasten belegen: Erst die eigenen stray-Aktionsleisten einschalten (Oberfläche → stray-Oberfläche → Eigene Aktionsleisten)."])
        return
    end
    -- Nicht gleichzeitig mit dem Bearbeitungsmodus (beide Leisten wollen die Tastatur), z. B. /stray keys
    if ns.editMode and ns.ExitEditMode then ns.ExitEditMode() end
    if not bar then CreateBar() end
    if not overlay then CreateOverlay() end
    -- Das stray-Fenster verdeckt sonst Leisten; nach dem Ende wieder öffnen
    reopenConfig = false
    if strayFrame and strayFrame:IsShown() then
        reopenConfig = true
        strayFrame:Hide()
    end
    active = true
    locked = false
    hovered = nil
    wipe(changes)
    wipe(notes)
    saveSet = CurrentSet()
    bar.message = nil
    UpdateBar()
    bar:Show()
    KeysOn(true)
    elapsedSum = 0
    bar:SetScript("OnUpdate", OnUpdate)
    -- Leere Plätze und Kürzel zeigen
    if ns.ActionBarsRefreshVisibility then pcall(ns.ActionBarsRefreshVisibility) end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

-- Kampfbeginn: Ereignis kommt noch vor der Sperre → Tastatur jetzt abgeben, Modus sperren
ns.On("PLAYER_REGEN_DISABLED", function()
    if not active then return end
    locked = true
    HideOverlay()
    HideDialog()
    if bar then pcall(bar.EnableKeyboard, bar, false) end
    UpdateBar()
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if not active then return end
    locked = false
    KeysOn(true)
    if bar then bar.message = nil end
    UpdateBar()
end)

ns.On("UPDATE_BINDINGS", function()
    if active and hovered then ShowTooltip() end
end)

---------------------------------------------------------------------------
-- Option
---------------------------------------------------------------------------

ns.AddOption(2, "Tastenbelegung", {
    key = "abKeybindModeButton",
    type = "button",
    label = L["Tasten belegen"],
    buttonText = L["Starten"],
    keywords = { "tasten", "belegen", "tastenbelegung", "kürzel", "hotkey", "keybind", "keybinds", "binding", "bind", "mouseover", "keys" },
    tooltip = L["Maus über einen Knopf der stray-Aktionsleisten fahren und eine Taste drücken – auch mit Shift, Strg oder Alt, Maustasten 3–5 und Mausrad. Entf oder Rechtsklick löscht die Tasten des Knopfs. Liegt die Taste schon woanders, wird sie dort entfernt.\n\nOben wählst du, ob die Belegung für alle Charaktere oder nur diesen gilt; „Abbrechen“ stellt die vorherige Belegung wieder her. Blizzards eigene Leistenbelegungen ändert stray nicht. Nur außerhalb des Kampfes. Auch per /stray keys."],
    isEnabled = function() return ns.ActionBarsActive and ns.ActionBarsActive() or false end,
    disabledHint = L["Erst „stray-Oberfläche“ und darunter „Eigene Aktionsleisten“ einschalten (Oberfläche → stray-Oberfläche)."],
    onClick = function() ns.StartKeybindMode() end,
})
