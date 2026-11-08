-- stray – Warnung bei Konflikten mit anderen Addons
--
-- Manche stray-Optionen machen dasselbe wie ein anderes beliebtes Addon (Taschen, Aktionsleisten,
-- Minimap, Gruppenrahmen …). Ist so ein Addon geladen, fragt stray vor dem Einschalten nach und
-- zeigt an der Option dauerhaft einen Hinweis. stray ändert nie Einstellungen anderer Addons;
-- ob die Funktion dort an ist, wird nur gelesen, wo das sicher geht (sonst „falls …“-Hinweis).
--
-- Vertrag (stray-regeln-023):
--   ns.Conflicts[optionsschlüssel] = { { addon = "Questie" oder { "A", "B" }, name = "Anzeigename" (optional),
--       feature = L-Schlüssel, hint = L-Schlüssel, check = function(addon) return true/false/nil end }, … }
--       check: true = dort sicher an, false = dort sicher aus (kein Konflikt), nil = unbekannt.
--   ns.ConflictHint(key)  → übersetzter Hinweistext oder nil (kein passendes Addon geladen)
--   ns.ConfirmOption(key, newValue, apply, onCancel) → apply() sofort, sonst Dialog
--       „Trotzdem einschalten / Abbrechen“ + „Nicht mehr fragen“ (ns.db.conflictIgnore[key] = true).
--       onCancel ist optional (z. B. Schalter in der Oberfläche zurückdrehen).
-- Andere Dateien tragen eigene Einträge mit ns.Conflicts = ns.Conflicts or {} ein.

local _, ns = ...
local L = ns.L

ns.defaults.conflictIgnore = {}

ns.Conflicts = ns.Conflicts or {}
local Conflicts = ns.Conflicts

---------------------------------------------------------------------------
-- Lesen anderer Addons (nur lesend, alles abgesichert)
---------------------------------------------------------------------------

local function IsLoaded(name)
    if type(name) ~= "string" or name == "" then return false end
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
        return ok and loaded == true
    end
    if IsAddOnLoaded then
        local ok, loaded = pcall(IsAddOnLoaded, name)
        return ok and (loaded and true or false)
    end
    return false
end

-- Wert über eine Kette von Feldern lesen, z. B. Read(_G.Questie, "db", "profile", "autocomplete")
local function Read(root, ...)
    local ok, value = pcall(function(...)
        local v = root
        for i = 1, select("#", ...) do
            if type(v) ~= "table" then return nil end
            v = v[select(i, ...)]
        end
        return v
    end, ...)
    if ok then return value end
    return nil
end

local function Bool(v)
    if type(v) == "boolean" then return v end
    return nil
end

-- Leatrix Plus speichert seine Schalter als "On"/"Off" in LeaPlusDB
local function Leatrix(setting)
    return function()
        local v = Read(_G.LeaPlusDB, setting)
        if v == "On" then return true end
        if v == "Off" then return false end
        return nil
    end
end

-- ElvUI: Module lassen sich in den privaten Einstellungen abschalten (ElvUI[1] = Engine)
local function ElvUI(...)
    local path = { ... }
    return function()
        local E = Read(_G.ElvUI, 1)
        if type(E) ~= "table" then return nil end
        return Bool(Read(E, unpack(path)))
    end
end

local function ElvUIParty()
    local E = Read(_G.ElvUI, 1)
    if type(E) ~= "table" then return nil end
    local module = Bool(Read(E, "private", "unitframe", "enable"))
    if module == false then return false end
    local party = Bool(Read(E, "db", "unitframe", "units", "party", "enable"))
    if party ~= nil then return party end
    return module
end

---------------------------------------------------------------------------
-- Hinweistexte (deutscher Text = Übersetzungsschlüssel, zur Anzeigezeit mit L[...] geholt)
---------------------------------------------------------------------------

local HINT_BAGS = "Zwei Taschenfenster öffnen sich dann gleichzeitig oder überdecken sich. Nutze nur eins: entweder das stray-Taschenfenster oder das andere Addon."
local HINT_BAGS_ELVUI = "Falls in ElvUI das Taschen-Modul an ist, öffnen sich zwei Taschenfenster. Schalte es in ElvUI unter Taschen aus oder lass das stray-Taschenfenster aus."
local HINT_METER = "Beide zeigen Werte aus Blizzards Schadensmesser. Das schadet nicht, kostet aber Platz – meist reicht eins."
local HINT_BARS = "Beide verstecken Blizzards Leisten und legen eigene Knöpfe auf dieselben Aktionsplätze. Das gibt doppelte Leisten und Ärger mit den Tasten. Nutze nur eins."
local HINT_BARS_ELVUI = "Falls in ElvUI das Aktionsleisten-Modul an ist, gibt es doppelte Leisten. Schalte es in ElvUI unter Aktionsleisten aus oder lass die stray-Leisten aus."
local HINT_BAGBAR = "Falls dort die Taschen- oder Menüleiste an ist, siehst du beide Leisten. Blende sie dort aus oder lass die stray-Leiste aus."
local HINT_MINIMAP = "Form, Rahmen und Position der Minimap setzen dann zwei Addons – sie kann springen oder schief sitzen. Nutze nur eins."
local HINT_MINIMAP_ELVUI = "Falls in ElvUI das Minimap-Modul an ist, kämpfen beide um die Minimap. Schalte es in ElvUI unter Karten aus oder lass die eckige stray-Minimap aus."
local HINT_MINIMAP_LEATRIX = "Schalte in Leatrix Plus unter Interface „Enhance minimap“ aus, sonst kämpfen beide um Form und Position der Minimap."
local HINT_PARTY = "Falls du dort Gruppenrahmen nutzt, erscheint deine Gruppe doppelt. Blende die Gruppe dort aus oder lass die stray-Gruppenrahmen aus."
local HINT_PARTY_ELVUI = "Falls in ElvUI die Gruppenrahmen an sind, erscheint deine Gruppe doppelt. Schalte sie in ElvUI unter Einheitenfenster → Gruppe aus oder lass die stray-Gruppenrahmen aus."
local HINT_LOOT = "Zwei Addons greifen dann gleichzeitig nach der Beute – das kann Fehlermeldungen oder hängende Beutefenster geben. Nutze nur eins."
local HINT_LOOT_LEATRIX = "Schalte in Leatrix Plus unter Interface „Faster auto loot“ aus, sonst greifen beide gleichzeitig nach der Beute."
local HINT_QUEST_QUESTIE = "Falls das in Questie (Optionen → Automatik) an ist, nehmen zwei Addons gleichzeitig an bzw. geben ab. Schalte es dort aus oder lass diese Option aus."
local HINT_QUEST_LEATRIX = "Falls in Leatrix Plus „Automate quests“ an ist, arbeiten zwei Automatiken gleichzeitig. Schalte es dort unter Automation aus oder lass diese Option aus."
local HINT_SELL_LEATRIX = "Falls in Leatrix Plus „Sell junk automatically“ an ist, verkaufen beide gleichzeitig – das kann doppelte Meldungen geben. Nutze nur eins."
local HINT_REPAIR_LEATRIX = "Falls in Leatrix Plus „Repair automatically“ an ist, reparieren beide – das kann doppelte Meldungen geben. Nutze nur eins."

---------------------------------------------------------------------------
-- Liste (Ordnernamen exakt wie im AddOns-Ordner)
---------------------------------------------------------------------------

local function Add(key, entry)
    Conflicts[key] = Conflicts[key] or {}
    table.insert(Conflicts[key], entry)
end

-- Taschenfenster
for _, a in ipairs({ "Bagnon", "Baganator", "ArkInventory", "AdiBags", "BetterBags", "Sorted" }) do
    Add("bagWindow", { addon = a, feature = "ersetzt ebenfalls Blizzards Taschen", hint = HINT_BAGS })
end
Add("bagWindow", { addon = "EllesmereUIBags", name = "EllesmereUI", feature = "Taschen-Modul", hint = HINT_BAGS })
Add("bagWindow", { addon = "ElvUI", feature = "Taschen-Modul", hint = HINT_BAGS_ELVUI,
    check = ElvUI("private", "bags", "enable") })

-- DMG-Meter
Add("dmShow", { addon = "Details", name = "Details!", feature = "eigener Schadensmesser", hint = HINT_METER })
for _, a in ipairs({ "Skada", "Recount" }) do
    Add("dmShow", { addon = a, feature = "eigener Schadensmesser", hint = HINT_METER })
end
Add("dmShow", { addon = "EllesmereUIDamageMeters", name = "EllesmereUI", feature = "eigener Schadensmesser", hint = HINT_METER })

-- Eigene Aktionsleisten
for _, a in ipairs({ "Bartender4", "Dominos" }) do
    Add("abEnabled", { addon = a, feature = "ersetzt ebenfalls die Aktionsleisten", hint = HINT_BARS })
end
Add("abEnabled", { addon = "EllesmereUIActionBars", name = "EllesmereUI", feature = "Aktionsleisten-Modul", hint = HINT_BARS })
Add("abEnabled", { addon = "ElvUI", feature = "Aktionsleisten-Modul", hint = HINT_BARS_ELVUI,
    check = ElvUI("private", "actionbar", "enable") })

-- Taschenleiste unten rechts (Bartender4/Dominos bringen eigene Taschen- und Menüleisten mit)
for _, a in ipairs({ "Bartender4", "Dominos" }) do
    Add("bottomBar", { addon = a, feature = "eigene Taschen- und Menüleiste", hint = HINT_BAGBAR })
end

-- Eckige Minimap
for _, a in ipairs({ "SexyMap", "BasicMinimap" }) do
    Add("squareMinimap", { addon = a, feature = "verändert ebenfalls die Minimap", hint = HINT_MINIMAP })
end
Add("squareMinimap", { addon = "EllesmereUIMinimap", name = "EllesmereUI", feature = "Minimap-Modul", hint = HINT_MINIMAP })
Add("squareMinimap", { addon = "ElvUI", feature = "Minimap-Modul", hint = HINT_MINIMAP_ELVUI,
    check = ElvUI("private", "general", "minimap", "enable") })
Add("squareMinimap", { addon = "Leatrix_Plus", name = "Leatrix Plus", feature = "„Enhance minimap“", hint = HINT_MINIMAP_LEATRIX,
    check = Leatrix("MinimapModder") })

-- Gruppenrahmen
for _, a in ipairs({ "Grid2", "VuhDo", "Cell", "HealBot" }) do
    Add("partyFrames", { addon = a, feature = "eigene Gruppen- und Heilrahmen", hint = HINT_PARTY })
end
Add("partyFrames", { addon = "ElvUI", feature = "Gruppenrahmen", hint = HINT_PARTY_ELVUI, check = ElvUIParty })

-- Beute
Add("fastLoot", { addon = "Leatrix_Plus", name = "Leatrix Plus", feature = "„Faster auto loot“", hint = HINT_LOOT_LEATRIX,
    check = Leatrix("FasterLooting") })
Add("fastLoot", { addon = "AutoLooter", feature = "plündert ebenfalls automatisch", hint = HINT_LOOT })

-- Quest-Automatik
Add("questAccept", { addon = "Questie", feature = "Quests automatisch annehmen", hint = HINT_QUEST_QUESTIE,
    check = function() return Bool(Read(_G.Questie, "db", "profile", "autoAccept", "enabled")) end })
Add("questAccept", { addon = "Leatrix_Plus", name = "Leatrix Plus", feature = "„Automate quests“", hint = HINT_QUEST_LEATRIX,
    check = Leatrix("AutomateQuests") })
Add("questTurnIn", { addon = "Questie", feature = "Quests automatisch abgeben", hint = HINT_QUEST_QUESTIE,
    check = function() return Bool(Read(_G.Questie, "db", "profile", "autocomplete")) end })
Add("questTurnIn", { addon = "Leatrix_Plus", name = "Leatrix Plus", feature = "„Automate quests“", hint = HINT_QUEST_LEATRIX,
    check = Leatrix("AutomateQuests") })

-- Händler
Add("autoSell", { addon = "Leatrix_Plus", name = "Leatrix Plus", feature = "„Sell junk automatically“", hint = HINT_SELL_LEATRIX,
    check = Leatrix("AutoSellJunk") })
Add("autoRepair", { addon = "Leatrix_Plus", name = "Leatrix Plus", feature = "„Repair automatically“", hint = HINT_REPAIR_LEATRIX,
    check = Leatrix("AutoRepairGear") })

---------------------------------------------------------------------------
-- Auswertung
---------------------------------------------------------------------------

-- Erstes geladenes Addon eines Eintrags (addon darf Text oder Liste sein)
local function LoadedAddon(entry)
    local a = entry.addon
    if type(a) == "table" then
        for _, name in ipairs(a) do
            if IsLoaded(name) then return name end
        end
        return nil
    end
    if IsLoaded(a) then return a end
    return nil
end

-- Liste der aktiven Konflikte: { { entry =, addon =, state = true/nil }, … }
local function Active(key)
    local list = Conflicts[key]
    if type(list) ~= "table" then return nil end
    local found
    for _, entry in ipairs(list) do
        if type(entry) == "table" then
            local addon = LoadedAddon(entry)
            if addon then
                local state
                if type(entry.check) == "function" then
                    local ok, res = pcall(entry.check, addon)
                    if ok and type(res) == "boolean" then state = res end
                end
                -- false = dort sicher aus → kein Konflikt
                if state ~= false then
                    found = found or {}
                    found[#found + 1] = { entry = entry, addon = addon, state = state }
                end
            end
        end
    end
    return found
end

-- Übersetzungsschlüssel zur Anzeigezeit auflösen
local function Text(key)
    if type(key) ~= "string" then return nil end
    return L[key]
end

local function DisplayName(item)
    local entry = item.entry
    if type(entry.name) == "string" and entry.name ~= "" then return entry.name end
    return item.addon
end

-- Hinweistext: je Addon ein Absatz „Name (Funktion): Hinweis“; gleiche Hinweise zusammengefasst
local function BuildText(found)
    local lines, byHint, order = {}, {}, {}
    for _, item in ipairs(found) do
        local hint = Text(item.entry.hint) or ""
        local label = DisplayName(item)
        local feature = Text(item.entry.feature)
        if feature and feature ~= "" then label = label .. " (" .. feature .. ")" end
        if not byHint[hint] then
            byHint[hint] = {}
            order[#order + 1] = hint
        end
        local names = byHint[hint]
        local dup = false
        for _, n in ipairs(names) do if n == label then dup = true end end
        if not dup then names[#names + 1] = label end
    end
    for _, hint in ipairs(order) do
        local names = table.concat(byHint[hint], ", ")
        if hint ~= "" then
            lines[#lines + 1] = names .. ": " .. hint
        else
            lines[#lines + 1] = names
        end
    end
    return table.concat(lines, "\n\n")
end

function ns.ConflictHint(key)
    local found = Active(key)
    if not found then return nil end
    return BuildText(found)
end

-- Gibt es für die Option aktuell einen Konflikt? (für andere Module, ohne Text)
function ns.HasConflict(key)
    return Active(key) ~= nil
end

local function IsOn(v)
    if v == nil or v == false or v == 0 or v == "off" or v == "" then return false end
    return true
end

local function Ignored(key)
    local db = ns.db
    local t = db and db.conflictIgnore
    return type(t) == "table" and t[key] == true
end

local function SetIgnored(key)
    local db = ns.db
    if not db then return end
    if type(db.conflictIgnore) ~= "table" then db.conflictIgnore = {} end
    db.conflictIgnore[key] = true
end

---------------------------------------------------------------------------
-- Dialog in stray-Optik (erst beim ersten Gebrauch gebaut)
---------------------------------------------------------------------------

local FONT = "Fonts\\ARIALN.TTF"
local WIDTH = 400
local PAD = 16

local dialog
local pending -- { key =, apply =, cancel = }

local function Col(c, a)
    return c[1], c[2], c[3], a or c[4] or 1
end

local function Border(f, c)
    local lines = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(Col(c))
        lines[i] = t
    end
    lines[1]:SetPoint("TOPLEFT"); lines[1]:SetPoint("TOPRIGHT"); lines[1]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT"); lines[2]:SetHeight(1)
    lines[3]:SetPoint("TOPLEFT"); lines[3]:SetPoint("BOTTOMLEFT"); lines[3]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT"); lines[4]:SetPoint("BOTTOMRIGHT"); lines[4]:SetWidth(1)
    return lines
end

local function SetBorderColor(lines, c)
    for _, t in ipairs(lines) do t:SetColorTexture(Col(c)) end
end

local function FontString(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontHighlightSmall)
    pcall(fs.SetFont, fs, FONT, size, "")
    fs:SetTextColor(Col(color))
    fs:SetJustifyH("LEFT")
    return fs
end

local function MakeButton(parent, primary)
    local C = ns.Colors
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(26)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(Col(C.card))
    b.lines = Border(b, primary and C.accent or C.line)
    b.text = FontString(b, 13, primary and C.accentText or C.text)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(Col(C.hover)) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(Col(C.card)) end)
    return b
end

local function Finish(confirmed)
    local p = pending
    pending = nil
    if dialog then dialog:Hide() end
    if not p then return end
    if confirmed then
        if dialog and dialog.ignore and dialog.ignore.checked then SetIgnored(p.key) end
        if p.apply then
            local ok, err = pcall(p.apply)
            if not ok then geterrorhandler()(err) end
        end
    elseif p.cancel then
        local ok, err = pcall(p.cancel)
        if not ok then geterrorhandler()(err) end
    end
end

local function SetChecked(box, on)
    box.checked = on and true or false
    box.mark:SetShown(box.checked)
end

local function BuildDialog()
    local C = ns.Colors
    local f = CreateFrame("Frame", "strayConflictDialog", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetWidth(WIDTH)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:EnableMouse(true)
    f:Hide()

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(Col(C.bg, 0.98))
    Border(f, C.line)
    -- schmaler lila Strich oben als Akzent
    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 1, -1); accent:SetPoint("TOPRIGHT", -1, -1); accent:SetHeight(2)
    accent:SetColorTexture(Col(C.accent))

    f.title = FontString(f, 15, C.accentText)
    f.title:SetPoint("TOPLEFT", PAD, -PAD)
    f.title:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)

    f.option = FontString(f, 12, C.textDim)
    f.option:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.option:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)

    f.body = FontString(f, 13, C.text)
    f.body:SetPoint("TOPLEFT", f.option, "BOTTOMLEFT", 0, -10)
    f.body:SetWidth(WIDTH - 2 * PAD)
    f.body:SetSpacing(2)
    f.body:SetWordWrap(true)

    f.note = FontString(f, 12, C.textDim)
    f.note:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -10)
    f.note:SetWidth(WIDTH - 2 * PAD)
    f.note:SetWordWrap(true)

    -- Häkchen „Nicht mehr fragen“
    local box = CreateFrame("Button", nil, f)
    box:SetSize(16, 16)
    box:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", 0, -12)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(Col(C.card))
    box.lines = Border(box, C.line)
    box.mark = box:CreateTexture(nil, "ARTWORK")
    box.mark:SetPoint("TOPLEFT", 4, -4); box.mark:SetPoint("BOTTOMRIGHT", -4, 4)
    box.mark:SetColorTexture(Col(C.accent))
    box.label = FontString(box, 12, C.textDim)
    box.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    box:SetHitRectInsets(0, -160, 0, 0)
    box:SetScript("OnClick", function(self) SetChecked(self, not self.checked) end)
    box:SetScript("OnEnter", function(self) SetBorderColor(self.lines, C.accent) end)
    box:SetScript("OnLeave", function(self) SetBorderColor(self.lines, C.line) end)
    f.ignore = box

    f.ok = MakeButton(f, true)
    f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    f.ok:SetScript("OnClick", function() Finish(true) end)

    f.cancel = MakeButton(f, false)
    f.cancel:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
    f.cancel:SetScript("OnClick", function() Finish(false) end)

    -- Esc = Abbrechen, andere Tasten gehen weiter ans Spiel. Tastatur nur außerhalb des Kampfes
    -- annehmen (Weiterreichen lässt sich im Kampf nicht umstellen; sonst würde der Dialog Tasten schlucken).
    f:EnableKeyboard(false)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            pcall(self.SetPropagateKeyboardInput, self, false)
            Finish(false)
        end
    end)
    f:SetScript("OnShow", function(self)
        if InCombatLockdown() then
            self:EnableKeyboard(false)
        else
            pcall(self.SetPropagateKeyboardInput, self, true)
            self:EnableKeyboard(true)
        end
    end)
    f:SetScript("OnHide", function()
        -- Fenster verschwindet ohne Entscheidung (z. B. Oberfläche ausgeblendet) = Abbrechen
        if pending then Finish(false) end
    end)
    return f
end

local function Layout(f)
    local h = PAD + f.title:GetStringHeight() + 4 + f.option:GetStringHeight() + 10
        + f.body:GetStringHeight() + 10 + f.note:GetStringHeight() + 12 + 16 + 16 + 26 + PAD
    f:SetHeight(math.floor(h + 0.5))
    for _, b in ipairs({ f.ok, f.cancel }) do
        b:SetWidth(math.max(90, math.floor(b.text:GetStringWidth() + 28)))
    end
end

-- Name der Option für die Unterzeile (Label aus ns.options, falls vorhanden)
local function OptionLabel(key)
    if type(ns.columns) ~= "table" then return nil end
    for _, sections in pairs(ns.columns) do
        if type(sections) == "table" then
            for _, section in ipairs(sections) do
                for _, opt in ipairs(type(section) == "table" and section.options or {}) do
                    if type(opt) == "table" and opt.key == key and type(opt.label) == "string" then
                        return ns.T and ns.T(opt.label) or opt.label
                    end
                end
            end
        end
    end
    return nil
end

-- Kampfbeginn: Tastatur des offenen Dialogs freigeben (Esc geht dann nur per Knopf)
ns.On("PLAYER_REGEN_DISABLED", function()
    if dialog and dialog:IsShown() then dialog:EnableKeyboard(false) end
end)

local function ShowDialog(key, found, apply, cancel)
    if pending then Finish(false) end
    dialog = dialog or BuildDialog()
    pending = { key = key, apply = apply, cancel = cancel }
    dialog.title:SetText(L["Überschneidung mit einem anderen Addon"])
    local label = OptionLabel(key)
    dialog.option:SetText(label and L("Option: %s", label) or "")
    dialog.body:SetText(BuildText(found))
    dialog.note:SetText(L["stray ändert keine Einstellungen anderer Addons. Du kannst trotzdem einschalten und später entscheiden."])
    dialog.ignore.label:SetText(L["Nicht mehr fragen"])
    SetChecked(dialog.ignore, false)
    dialog.ok.text:SetText(L["Trotzdem einschalten"])
    dialog.cancel.text:SetText(L["Abbrechen"])
    dialog:Show()
    dialog:Raise()
    Layout(dialog)
end

function ns.ConfirmOption(key, newValue, apply, onCancel)
    if type(apply) ~= "function" then return end
    if not IsOn(newValue) or Ignored(key) then
        apply()
        return
    end
    local found = Active(key)
    if not found then
        apply()
        return
    end
    ShowDialog(key, found, apply, onCancel)
end
