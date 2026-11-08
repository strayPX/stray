-- stray – Profile: alle Einstellungen als Text exportieren und wieder importieren
-- Format: "stray1:" gefolgt von Einträgen "schlüssel=typ:wert", getrennt durch ";".
-- Typen: b (1/0), n (Zahl), s (Text, Sonderzeichen als %XX maskiert).
-- Inhalt: alle Optionen aus dem Register, alle weiteren einfachen Werte aus ns.db, die ein
-- Modul in ns.defaults anmeldet (außer Charakter-/Verlaufsdaten), Positionen (pos.*),
-- Größen je Anzeige (scale.*), Minimap-Winkel und Werkzeugleisten-Punkt.

local _, ns = ...
local L = ns.L

local PREFIX = "stray1:"

-- Diese Knöpfe selbst nie exportieren
local SKIP_KEYS = { profileExport = true, profileImport = true }

-- Gültige Ankerpunkte für Positionen
local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local exportText = ""
local pending -- geprüfter Import, wartet auf „Übernehmen“

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

-- ; = : % | und Steuerzeichen maskieren („|“ würde WoW sonst als Farbcode/Link lesen)
local function Escape(text)
    return (tostring(text):gsub("[%%;=:|%c]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function Unescape(text)
    return (text:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function IsFinite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Zahl kurz schreiben: ganze Zahlen ohne Nachkommastellen
local function FormatNumber(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%d", v)
    end
    return string.format("%.6g", v)
end

local function Round1(v)
    return math.floor(v * 10 + 0.5) / 10
end

-- Position { Punkt, relPunkt, x, y } → "CENTER,CENTER,-220,0" (nil, wenn ungültig)
local function EncodePosition(pos)
    if type(pos) ~= "table" then return nil end
    local p, rp, x, y = pos[1], pos[2], pos[3], pos[4]
    if not ANCHORS[p] or not ANCHORS[rp] or not IsFinite(x) or not IsFinite(y) then return nil end
    return p .. "," .. rp .. "," .. FormatNumber(Round1(x)) .. "," .. FormatNumber(Round1(y))
end

local function DecodePosition(text)
    local p, rp, x, y = text:match("^(%u+),(%u+),([%-%d%.]+),([%-%d%.]+)$")
    x, y = tonumber(x), tonumber(y)
    if not p or not ANCHORS[p] or not ANCHORS[rp] or not IsFinite(x) or not IsFinite(y) then return nil end
    return { p, rp, x, y }
end

-- Alle exportierbaren Optionen aus dem Register: Schlüssel → Option.
-- blocked: Schlüssel von Knöpfen, Auswahlfeldern und noExport-Optionen (auch nicht über ns.db)
local function CollectOptions()
    local list, byKey, blocked = {}, {}, {}
    for _, sections in ipairs(ns.columns) do
        for _, section in ipairs(sections) do
            for _, option in ipairs(section.options) do
                local key = option.key
                if key and option.type ~= "button" and option.type ~= "choice" and not option.noExport and not SKIP_KEYS[key] and not byKey[key] then
                    byKey[key] = option
                    table.insert(list, option)
                elseif key then
                    blocked[key] = true
                end
            end
        end
    end
    return list, byKey, blocked
end

---------------------------------------------------------------------------
-- Weitere Werte direkt aus ns.db (ohne eigene Option, z. B. Fenstergrößen, Modus, Andocken).
-- Grundsatz: alle einfachen Werte, die ein Modul in ns.defaults anmeldet, außer Charakter-,
-- Verlaufs- und internen Daten. So kommen neue Einstellungen ohne Liste automatisch mit.
---------------------------------------------------------------------------

-- Nie exportieren: Twinks, Notizen, Post-Twinks, Flugzeiten, Kontodaten, interner Zustand
local NO_EXPORT_DB = {
    altData = true, playerNoteData = true, mailAltList = true, flightRouteTimes = true,
    accountCVarData = true, bagPinned = true, cdCVarByStray = true,
    flightTimer = true, flightTimes = true,
}

-- Namensmuster für Verläufe und Messdaten (z. B. EP-Verlauf), die nicht ins Profil gehören
local HISTORY_PATTERNS = { "Data$", "History", "Hist$", "Log$", "List$", "Times$", "Session", "Played" }

-- Positionen { Punkt, relPunkt, x, y } unter eigenem Schlüssel
local POSITION_KEYS = { point = true, editBarPoint = true }

-- Feste Auswahlwerte; NONE steht für „nicht gesetzt“ (nil)
local NONE = "none"
local ENUMS = {
    dmMode = { damage = true, healing = true },
    dm2Mode = { damage = true, healing = true },
    dm2Dock = { top = true, bottom = true, [NONE] = true },
}

local function IsHistoryKey(key)
    for _, pattern in ipairs(HISTORY_PATTERNS) do
        if key:find(pattern) then return true end
    end
    return false
end

local function IsScalar(v)
    local t = type(v)
    return t == "boolean" or t == "string" or (t == "number" and IsFinite(v))
end

-- Darf dieser ns.db-Schlüssel als einfacher Wert ins Profil?
local function IsGenericKey(key, byKey, blocked)
    if type(key) ~= "string" or not key:match("^%a[%w_]*$") then return false end
    if byKey[key] or blocked[key] or SKIP_KEYS[key] or NO_EXPORT_DB[key] then return false end
    if POSITION_KEYS[key] or key == "positions" or key == "scales" or key == "minimapAngle" then return false end
    if ENUMS[key] then return true end
    if IsHistoryKey(key) then return false end
    local default = ns.defaults[key]
    return default ~= nil and type(default) ~= "table"
end

-- Passt der Wert zum Schlüssel (Typ wie Standardwert, Auswahlwerte)?
local function ValidGeneric(key, value)
    if not IsScalar(value) then return false end
    if ENUMS[key] then return type(value) == "string" and ENUMS[key][value] == true end
    return type(value) == type(ns.defaults[key])
end

-- Aktueller Wert für den Export (nil bei NONE-Schlüsseln wird zu NONE)
local function GenericValue(key)
    local v = ns.db[key]
    if v == nil and ENUMS[key] and ENUMS[key][NONE] then return NONE end
    if ValidGeneric(key, v) then return v end
    return nil
end

-- Aktueller Wert einer Option (nil, wenn nicht lesbar oder kein einfacher Typ)
local function OptionValue(option)
    local ok, value = pcall(option.get)
    if not ok or ns.IsSecret(value) then return nil end
    if value == nil and option.type ~= "slider" then value = false end
    local t = type(value)
    if t == "boolean" or t == "string" or (t == "number" and IsFinite(value)) then return value end
    return nil
end

local function EncodeValue(value)
    local t = type(value)
    if t == "boolean" then return "b:" .. (value and "1" or "0") end
    if t == "number" then return "n:" .. FormatNumber(value) end
    return "s:" .. Escape(value)
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

local function BuildExport()
    local parts = {}
    local options, byKey, blocked = CollectOptions()
    for _, option in ipairs(options) do
        local value = OptionValue(option)
        if value ~= nil then
            table.insert(parts, Escape(option.key) .. "=" .. EncodeValue(value))
        end
    end

    local db = ns.db

    -- Einfache Werte ohne eigene Option (sortiert, damit der Text stabil bleibt)
    local generic = {}
    for key in pairs(db) do
        if IsGenericKey(key, byKey, blocked) then table.insert(generic, key) end
    end
    for key in pairs(ENUMS) do
        if db[key] == nil and IsGenericKey(key, byKey, blocked) then table.insert(generic, key) end
    end
    table.sort(generic)
    for _, key in ipairs(generic) do
        local value = GenericValue(key)
        if value ~= nil then
            table.insert(parts, key .. "=" .. EncodeValue(value))
        end
    end

    if IsFinite(db.minimapAngle) then
        table.insert(parts, "minimapAngle=n:" .. FormatNumber(Round1(db.minimapAngle)))
    end
    for _, key in ipairs({ "point", "editBarPoint" }) do
        local pos = EncodePosition(db[key])
        if pos then table.insert(parts, key .. "=s:" .. pos) end
    end

    -- Größen je Anzeige: scales[Anzeige] = Zahl oder { Feld = Zahl, … }
    if type(db.scales) == "table" then
        local keys = {}
        for key in pairs(db.scales) do
            if type(key) == "string" and key:match("^[%w_]+$") then table.insert(keys, key) end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local v = db.scales[key]
            if IsFinite(v) then
                table.insert(parts, "scale." .. key .. "=n:" .. FormatNumber(v))
            elseif type(v) == "table" then
                local fields = {}
                for field, n in pairs(v) do
                    local name = (type(field) == "number" and field == math.floor(field) and field >= 1) and tostring(field)
                        or (type(field) == "string" and field:match("^[%a_][%w_]*$") and field)
                    if name and IsFinite(n) then table.insert(fields, name) end
                end
                table.sort(fields)
                for _, name in ipairs(fields) do
                    local n = v[tonumber(name) or name]
                    table.insert(parts, "scale." .. key .. "." .. name .. "=n:" .. FormatNumber(n))
                end
            end
        end
    end

    if type(db.positions) == "table" then
        local keys = {}
        for key in pairs(db.positions) do
            if type(key) == "string" and key:match("^[%w_]+$") then table.insert(keys, key) end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local pos = EncodePosition(db.positions[key])
            if pos then table.insert(parts, "pos." .. key .. "=s:" .. pos) end
        end
    end

    return PREFIX .. table.concat(parts, ";")
end

---------------------------------------------------------------------------
-- Import: prüfen, dann übernehmen
---------------------------------------------------------------------------

-- Wert aus Typkennung und Text lesen
local function DecodeValue(t, raw)
    if t == "b" then
        if raw == "1" then return true end
        if raw == "0" then return false end
        return nil
    elseif t == "n" then
        local n = tonumber(raw)
        if IsFinite(n) then return n end
        return nil
    elseif t == "s" then
        return Unescape(raw)
    end
    return nil
end

local function SamePosition(a, b)
    return EncodePosition(a) == EncodePosition(b)
end

-- Gibt eine Liste von Änderungen zurück, oder nil bei falscher Kennung
local function ParseImport(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, #PREFIX) ~= PREFIX then return nil end

    local _, byKey, blocked = CollectOptions()
    local db = ns.db
    local result = { changes = {}, unknown = 0, invalid = 0 }
    local seen = {}

    local body = text:sub(#PREFIX + 1)
    for entry in body:gmatch("[^;]+") do
        local rawKey, t, raw = entry:match("^([^=]+)=(%a):(.*)$")
        if not rawKey then
            result.invalid = result.invalid + 1
        else
            local key = Unescape(rawKey)
            local value = DecodeValue(t, raw)
            local option = byKey[key]
            local posKey = key:match("^pos%.([%w_]+)$")
            local scaleKey, scaleField = key:match("^scale%.([%w_]+)%.([%w_]+)$")
            if not scaleKey then scaleKey = key:match("^scale%.([%w_]+)$") end

            if seen[key] then
                -- doppelte Einträge: nur den ersten verwenden
            elseif scaleKey then
                seen[key] = true
                if type(value) ~= "number" or value <= 0 then
                    result.invalid = result.invalid + 1
                else
                    local field = scaleField and (tonumber(scaleField) or scaleField) or nil
                    local scales = type(db.scales) == "table" and db.scales or {}
                    local current = scales[scaleKey]
                    if field then current = type(current) == "table" and current[field] or nil end
                    if not IsFinite(current) or FormatNumber(current) ~= FormatNumber(value) then
                        table.insert(result.changes, { scaleKey = scaleKey, field = field, value = value })
                    end
                end
            elseif not option and IsGenericKey(key, byKey, blocked) then
                seen[key] = true
                if not ValidGeneric(key, value) then
                    result.invalid = result.invalid + 1
                elseif value ~= GenericValue(key) then
                    if value == NONE and ENUMS[key] and ENUMS[key][NONE] then value = nil end
                    table.insert(result.changes, { dbKey = key, value = value })
                end
            elseif option then
                seen[key] = true
                local current = OptionValue(option)
                if option.type == "slider" then
                    if type(value) ~= "number" then
                        value = nil
                    else
                        local step = option.step or 1
                        value = math.floor(value / step + 0.5) * step
                        value = math.max(option.min or 0, math.min(option.max or 100, value))
                    end
                elseif value ~= nil and current ~= nil and type(value) ~= type(current) then
                    value = nil
                end
                if value == nil then
                    result.invalid = result.invalid + 1
                elseif value ~= current then
                    table.insert(result.changes, { option = option, value = value })
                end
            elseif key == "minimapAngle" then
                seen[key] = true
                if type(value) ~= "number" then
                    result.invalid = result.invalid + 1
                else
                    value = value % 360
                    if not IsFinite(db.minimapAngle) or Round1(db.minimapAngle) ~= Round1(value) then
                        table.insert(result.changes, { dbKey = "minimapAngle", value = value })
                    end
                end
            elseif POSITION_KEYS[key] or posKey then
                seen[key] = true
                local pos = (t == "s") and DecodePosition(value) or nil
                if not pos then
                    result.invalid = result.invalid + 1
                elseif POSITION_KEYS[key] then
                    if not SamePosition(db[key], pos) then
                        table.insert(result.changes, { dbKey = key, value = pos })
                    end
                elseif not SamePosition(db.positions and db.positions[posKey], pos) then
                    table.insert(result.changes, { posKey = posKey, value = pos })
                end
            else
                result.unknown = result.unknown + 1
            end
        end
    end
    return result
end

local function ApplyImport(result)
    if not result or not ns.db then return end
    local failed = 0
    for _, change in ipairs(result.changes) do
        if change.option then
            local ok = pcall(change.option.set, change.value)
            if not ok then failed = failed + 1 end
        elseif change.dbKey then
            ns.db[change.dbKey] = change.value
        elseif change.scaleKey then
            if type(ns.db.scales) ~= "table" then ns.db.scales = {} end
            if change.field then
                local t = ns.db.scales[change.scaleKey]
                if type(t) ~= "table" then
                    t = {}
                    ns.db.scales[change.scaleKey] = t
                end
                t[change.field] = change.value
            else
                ns.db.scales[change.scaleKey] = change.value
            end
        elseif change.posKey then
            if type(ns.db.positions) ~= "table" then ns.db.positions = {} end
            ns.db.positions[change.posKey] = change.value
        end
    end
    if failed > 0 then
        ns.Print(L("%d Einstellung(en) konnten nicht übernommen werden.", failed))
    end
    ReloadUI()
end

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------

local function GetEditBox(popup)
    return popup.editBox or popup.EditBox or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "EditBox"])
end

-- Feld ohne Längenbegrenzung (StaticPopup setzt sonst 255 Zeichen)
local function Unlimit(box)
    if box.SetMaxLetters then pcall(box.SetMaxLetters, box, 0) end
    if box.SetMaxBytes then pcall(box.SetMaxBytes, box, 0) end
end

local function Later(fn)
    if C_Timer and C_Timer.After then C_Timer.After(0, fn) else fn() end
end

local function FillExportBox(popup)
    local box = popup and GetEditBox(popup)
    if not box then return end
    Unlimit(box)
    box:SetText(exportText)
    box:HighlightText()
    box:SetFocus()
end

StaticPopupDialogs["STRAY_PROFILE_EXPORT"] = {
    text = L["stray-Profil – mit Strg+C kopieren:"],
    button1 = CLOSE or L["Schließen"],
    hasEditBox = true,
    editBoxWidth = 350,
    maxLetters = 0,
    maxBytes = 0,
    OnShow = function(self) pcall(FillExportBox, self) end,
    EditBoxOnTextChanged = function(box)
        -- Text bleibt unverändert, auch wenn man versehentlich tippt
        if box:GetText() ~= exportText then
            box:SetText(exportText)
            box:HighlightText()
        end
    end,
    EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["STRAY_PROFILE_CONFIRM"] = {
    text = "%s",
    button1 = L["Übernehmen"],
    button2 = CANCEL or L["Abbrechen"],
    OnAccept = function()
        local result = pending
        pending = nil
        local ok, err = pcall(ApplyImport, result)
        if not ok then ns.Print(L("Import fehlgeschlagen: %s", tostring(err))) end
    end,
    OnCancel = function() pending = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CheckImport(text)
    local ok, result = pcall(ParseImport, text)
    if not ok then
        ns.Print(L["Profil konnte nicht gelesen werden."])
        return
    end
    if not result then
        ns.Print(L["Das ist kein stray-Profil."])
        return
    end

    local changes = #result.changes
    local notes = {}
    if result.unknown > 0 then table.insert(notes, L("%d unbekannte ignoriert", result.unknown)) end
    if result.invalid > 0 then table.insert(notes, L("%d ungültige übersprungen", result.invalid)) end
    local noteText = (#notes > 0) and (", " .. table.concat(notes, ", ")) or ""

    if changes == 0 then
        ns.Print(L("Das Profil entspricht schon deinen Einstellungen%s.", noteText))
        return
    end

    local message = (changes == 1) and L("1 Einstellung wird geändert%s. Übernehmen und neu laden?", noteText)
        or L("%d Einstellungen werden geändert%s. Übernehmen und neu laden?", changes, noteText)
    pending = result
    Later(function() StaticPopup_Show("STRAY_PROFILE_CONFIRM", message) end)
end

StaticPopupDialogs["STRAY_PROFILE_IMPORT"] = {
    text = L["stray-Profil mit Strg+V einfügen:"],
    button1 = L["Prüfen"],
    button2 = CANCEL or L["Abbrechen"],
    hasEditBox = true,
    editBoxWidth = 350,
    maxLetters = 0,
    maxBytes = 0,
    OnShow = function(self)
        local box = GetEditBox(self)
        if not box then return end
        Unlimit(box)
        box:SetText("")
        box:SetFocus()
    end,
    OnAccept = function(self)
        local box = GetEditBox(self)
        CheckImport(box and box:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(box)
        local text = box:GetText()
        box:GetParent():Hide()
        CheckImport(text)
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ShowExport()
    if not ns.db then return end
    local ok, text = pcall(BuildExport)
    if not ok then
        ns.Print(L("Export fehlgeschlagen: %s", tostring(text)))
        return
    end
    exportText = text
    local popup = StaticPopup_Show("STRAY_PROFILE_EXPORT")
    -- Absicherung, falls der Client das Feld erst nach OnShow fertig einrichtet
    if popup then pcall(FillExportBox, popup) end
end

local function ShowImport()
    if not ns.db then return end
    pending = nil
    StaticPopup_Show("STRAY_PROFILE_IMPORT")
end

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(3, "Profile", {
    key = "profileExport",
    type = "button",
    label = L["Profil exportieren"],
    buttonText = L["Exportieren"],
    tooltip = L["Zeigt alle stray-Einstellungen als Text zum Kopieren.\nDen Text kannst du z. B. einem Freund schicken, der ihn mit „Profil importieren“ übernimmt."],
    onClick = ShowExport,
})

ns.AddOption(3, "Profile", {
    key = "profileImport",
    type = "button",
    label = L["Profil importieren"],
    buttonText = L["Importieren"],
    tooltip = L["Übernimmt stray-Einstellungen aus einem eingefügten Profil-Text.\nVorher siehst du, wie viele Einstellungen sich ändern. Danach wird die Oberfläche neu geladen."],
    onClick = ShowImport,
})
