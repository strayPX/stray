-- stray – Profile: alle Einstellungen als Text exportieren und wieder importieren
-- Format: "stray1:" gefolgt von Einträgen "schlüssel=typ:wert", getrennt durch ";".
-- Typen: b (1/0), n (Zahl), s (Text, Sonderzeichen als %XX maskiert).

local _, ns = ...

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

-- Alle exportierbaren Optionen aus dem Register: Schlüssel → Option
local function CollectOptions()
    local list, byKey = {}, {}
    for _, sections in ipairs(ns.columns) do
        for _, section in ipairs(sections) do
            for _, option in ipairs(section.options) do
                local key = option.key
                if key and option.type ~= "button" and option.type ~= "choice" and not option.noExport and not SKIP_KEYS[key] and not byKey[key] then
                    byKey[key] = option
                    table.insert(list, option)
                end
            end
        end
    end
    return list, byKey
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
    local options = CollectOptions()
    for _, option in ipairs(options) do
        local value = OptionValue(option)
        if value ~= nil then
            table.insert(parts, Escape(option.key) .. "=" .. EncodeValue(value))
        end
    end

    local db = ns.db
    if type(db.dmMode) == "string" then
        table.insert(parts, "dmMode=s:" .. Escape(db.dmMode))
    end
    if IsFinite(db.minimapAngle) then
        table.insert(parts, "minimapAngle=n:" .. FormatNumber(Round1(db.minimapAngle)))
    end
    local point = EncodePosition(db.point)
    if point then table.insert(parts, "point=s:" .. point) end

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

    local _, byKey = CollectOptions()
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

            if seen[key] then
                -- doppelte Einträge: nur den ersten verwenden
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
            elseif key == "dmMode" then
                seen[key] = true
                if value ~= "damage" and value ~= "healing" then
                    result.invalid = result.invalid + 1
                elseif value ~= db.dmMode then
                    table.insert(result.changes, { dbKey = "dmMode", value = value })
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
            elseif key == "point" or posKey then
                seen[key] = true
                local pos = (t == "s") and DecodePosition(value) or nil
                if not pos then
                    result.invalid = result.invalid + 1
                elseif key == "point" then
                    if not SamePosition(db.point, pos) then
                        table.insert(result.changes, { dbKey = "point", value = pos })
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
        elseif change.posKey then
            if type(ns.db.positions) ~= "table" then ns.db.positions = {} end
            ns.db.positions[change.posKey] = change.value
        end
    end
    if failed > 0 then
        ns.Print(failed .. " Einstellung(en) konnten nicht übernommen werden.")
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
    text = "stray-Profil – mit Strg+C kopieren:",
    button1 = CLOSE or "Schließen",
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
    button1 = "Übernehmen",
    button2 = CANCEL or "Abbrechen",
    OnAccept = function()
        local result = pending
        pending = nil
        local ok, err = pcall(ApplyImport, result)
        if not ok then ns.Print("Import fehlgeschlagen: " .. tostring(err)) end
    end,
    OnCancel = function() pending = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

local function CheckImport(text)
    local ok, result = pcall(ParseImport, text)
    if not ok then
        ns.Print("Profil konnte nicht gelesen werden.")
        return
    end
    if not result then
        ns.Print("Das ist kein stray-Profil.")
        return
    end

    local changes = #result.changes
    local notes = {}
    if result.unknown > 0 then table.insert(notes, result.unknown .. " unbekannte ignoriert") end
    if result.invalid > 0 then table.insert(notes, result.invalid .. " ungültige übersprungen") end
    local noteText = (#notes > 0) and (", " .. table.concat(notes, ", ")) or ""

    if changes == 0 then
        ns.Print("Das Profil entspricht schon deinen Einstellungen" .. noteText .. ".")
        return
    end

    local verb = (changes == 1) and " wird geändert" or " werden geändert"
    local message = Plural(changes, "Einstellung", "Einstellungen") .. verb .. noteText .. ". Übernehmen und neu laden?"
    pending = result
    Later(function() StaticPopup_Show("STRAY_PROFILE_CONFIRM", message) end)
end

StaticPopupDialogs["STRAY_PROFILE_IMPORT"] = {
    text = "stray-Profil mit Strg+V einfügen:",
    button1 = "Prüfen",
    button2 = CANCEL or "Abbrechen",
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
        ns.Print("Export fehlgeschlagen: " .. tostring(text))
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
    label = "Profil exportieren",
    buttonText = "Exportieren",
    tooltip = "Zeigt alle stray-Einstellungen als Text zum Kopieren.\nDen Text kannst du z. B. einem Freund schicken, der ihn mit „Profil importieren“ übernimmt.",
    onClick = ShowExport,
})

ns.AddOption(3, "Profile", {
    key = "profileImport",
    type = "button",
    label = "Profil importieren",
    buttonText = "Importieren",
    tooltip = "Übernimmt stray-Einstellungen aus einem eingefügten Profil-Text.\nVorher siehst du, wie viele Einstellungen sich ändern. Danach wird die Oberfläche neu geladen.",
    onClick = ShowImport,
})
