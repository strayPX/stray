-- stray – Tooltip (Phase 2, Leatrix-Funktionen nachgebaut)
-- Klassenfarbe, Ziel, Gildenrang, Ort/Größe des Tooltips, IDs.
-- Nur über TooltipDataProcessor-Nachrufe und hooksecurefunc; kein Blizzard-Code wird überschrieben,
-- keine Felder auf Blizzard-Frames. Bei „aus“ passiert nichts.

local _, ns = ...
local L = ns.L

ns.defaults.tipClassColor = false
ns.defaults.tipTarget = false
ns.defaults.tipGuildRank = false
ns.defaults.tipCursor = false
ns.defaults.tipScaleOn = false
ns.defaults.tipScale = 100
ns.defaults.tipIds = false

local function On(key)
    return ns.db and ns.db[key] and true or false
end

-- Wert nur nehmen, wenn er nicht versiegelt ist
local function Safe(value)
    if value == nil or ns.IsSecret(value) then return nil end
    return value
end

local function ClassColorOf(unit)
    local ok, _, classFile = pcall(UnitClass, unit)
    classFile = ok and Safe(classFile) or nil
    if type(classFile) ~= "string" then return nil end
    return (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]) or nil
end

local function IsPlayerUnit(unit)
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    return ok and Safe(isPlayer) == true
end

---------------------------------------------------------------------------
-- Spieler- und Gegner-Tooltip: Klassenfarbe, Gildenrang, Ziel
---------------------------------------------------------------------------

local function TooltipUnit(tooltip)
    if tooltip ~= GameTooltip or not tooltip.GetUnit then return nil end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok then return nil end
    unit = Safe(unit)
    if type(unit) ~= "string" then return nil end
    return unit
end

local function LeftLine(index)
    return _G["GameTooltipTextLeft" .. index]
end

local function ColorName(unit)
    local color = ClassColorOf(unit)
    local line = LeftLine(1)
    if color and line then line:SetTextColor(color.r, color.g, color.b) end
end

local function AddGuildRank(unit)
    local ok, guild, rank = pcall(GetGuildInfo, unit)
    if not ok then return end
    guild, rank = Safe(guild), Safe(rank)
    if type(guild) ~= "string" or type(rank) ~= "string" or guild == "" or rank == "" then return end
    for index = 2, 3 do
        local line = LeftLine(index)
        local text = line and Safe(line:GetText())
        if type(text) == "string" and text:find(guild, 1, true) and not text:find(rank, 1, true) then
            local d = ns.Colors.textDim
            line:SetText(("%s |cff%02x%02x%02x%s|r"):format(text,
                math.floor(d[1] * 255), math.floor(d[2] * 255), math.floor(d[3] * 255), rank))
            return
        end
    end
end

local function AddTarget(tooltip, unit)
    local target = unit .. "target"
    local ok, exists = pcall(UnitExists, target)
    if not ok or Safe(exists) ~= true then return end
    local okName, name = pcall(UnitName, target)
    name = okName and Safe(name) or nil
    if type(name) ~= "string" then return end
    local isMe = false
    local okSame, same = pcall(UnitIsUnit, target, "player")
    if okSame and Safe(same) == true then isMe = true end
    local color = IsPlayerUnit(target) and ClassColorOf(target) or nil
    local shown = isMe and L["Du"] or name
    local r, g, b = 1, 1, 1
    if color then r, g, b = color.r, color.g, color.b end
    local hex = ("%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    tooltip:AddLine(L("Ziel: |cff%s%s|r", hex, shown), 0.8, 0.8, 0.8)
end

local function OnUnitTooltip(tooltip)
    if not ns.db or not (ns.db.tipClassColor or ns.db.tipTarget or ns.db.tipGuildRank) then return end
    local unit = TooltipUnit(tooltip)
    if not unit then return end
    if IsPlayerUnit(unit) then
        if ns.db.tipClassColor then ColorName(unit) end
        if ns.db.tipGuildRank then AddGuildRank(unit) end
    end
    if ns.db.tipTarget then AddTarget(tooltip, unit) end
end

---------------------------------------------------------------------------
-- IDs (Gegenstand, Zauber, Quest, Währung, NPC)
---------------------------------------------------------------------------

local function AddIdLine(tooltip, label, id)
    id = Safe(id)
    if type(id) ~= "number" then return end
    local d = ns.Colors.textDim
    tooltip:AddLine(("%s: %d"):format(label, id), d[1], d[2], d[3])
end

local function NpcIdFromGuid(guid)
    guid = Safe(guid)
    if type(guid) ~= "string" then return nil end
    local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(npc) end
    return nil
end

-- Beschriftungen erst zur Anzeigezeit holen, damit die gewählte Sprache gilt
local function IdLabels()
    return {
        item = L["Gegenstands-ID"],
        spell = L["Zauber-ID"],
        quest = L["Quest-ID"],
        currency = L["Währungs-ID"],
        npc = L["NPC-ID"],
    }
end

local function Guard(tooltip)
    if not ns.db or not ns.db.tipIds then return false end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
    return true
end

---------------------------------------------------------------------------
-- Nachrufe registrieren
---------------------------------------------------------------------------

local function Register()
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall or not Enum or not Enum.TooltipDataType then
        return
    end
    local T = Enum.TooltipDataType

    local function Post(kind, fn)
        if kind == nil then return end
        TooltipDataProcessor.AddTooltipPostCall(kind, function(tooltip, data)
            pcall(fn, tooltip, data)
        end)
    end

    Post(T.Unit, function(tooltip, data)
        OnUnitTooltip(tooltip)
        if Guard(tooltip) and type(data) == "table" then
            local npc = NpcIdFromGuid(data.guid)
            if npc then AddIdLine(tooltip, IdLabels().npc, npc) end
        end
    end)

    local function IdPost(kind, labelKey)
        Post(kind, function(tooltip, data)
            if not Guard(tooltip) or type(data) ~= "table" then return end
            AddIdLine(tooltip, IdLabels()[labelKey], data.id)
        end)
    end

    IdPost(T.Item, "item")
    IdPost(T.Spell, "spell")
    IdPost(T.UnitAura, "spell")
    IdPost(T.Quest, "quest")
    IdPost(T.Currency, "currency")
end

pcall(Register)

---------------------------------------------------------------------------
-- Ort und Größe
---------------------------------------------------------------------------

local scaledByUs = false

local function ApplyScale()
    if not GameTooltip or not GameTooltip.SetScale then return end
    if On("tipScaleOn") then
        local pct = tonumber(ns.db.tipScale) or 100
        if pct < 50 then pct = 50 elseif pct > 150 then pct = 150 end
        GameTooltip:SetScale(pct / 100)
        scaledByUs = true
    elseif scaledByUs then
        GameTooltip:SetScale(1)
        scaledByUs = false
    end
end

hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
    if tooltip ~= GameTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if On("tipCursor") and parent == UIParent then
        tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 12, 8)
    end
    if On("tipScaleOn") then ApplyScale() end
end)

ns.On("PLAYER_LOGIN", function()
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnShow", function()
            if On("tipScaleOn") then ApplyScale() end
        end)
    end
    ApplyScale()
end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(3, "Tooltip", {
    key = "tipClassColor",
    label = L["Spielernamen im Tooltip in Klassenfarbe"],
    tooltip = L["Der Name von Spielern im Tooltip erscheint in der Farbe ihrer Klasse. Gegner und NPCs bleiben unverändert."],
    keywords = { "klassenfarbe", "class", "color", "colour", "name", "tooltip", "spieler", "player" },
})

ns.AddOption(3, "Tooltip", {
    key = "tipTarget",
    label = L["Ziel der Einheit im Tooltip"],
    tooltip = L["Fügt dem Tooltip eine Zeile „Ziel: Name“ hinzu, wenn die Einheit unter der Maus jemanden anvisiert. Spieler erscheinen in Klassenfarbe, du selbst als „Du“. Im Kampf nur, soweit das Spiel die Werte freigibt."],
    keywords = { "ziel", "target", "tooltip", "anvisiert", "targeting" },
})

ns.AddOption(3, "Tooltip", {
    key = "tipGuildRank",
    label = L["Gildenrang im Tooltip"],
    tooltip = L["Zeigt hinter dem Gildennamen im Spieler-Tooltip zusätzlich den Rang in der Gilde."],
    keywords = { "gilde", "guild", "rang", "rank", "tooltip" },
})

ns.AddOption(3, "Tooltip", {
    key = "tipCursor",
    label = L["Tooltip am Mauszeiger"],
    tooltip = L["Tooltips von Einheiten und Objekten in der Spielwelt erscheinen neben dem Mauszeiger statt in der Bildschirmecke. Tooltips über Aktionsleisten, Taschen und Fenstern bleiben an ihrem Platz."],
    keywords = { "maus", "mauszeiger", "cursor", "mouse", "anker", "anchor", "tooltip", "position" },
})

ns.AddOption(3, "Tooltip", {
    key = "tipScaleOn",
    label = L["Tooltip-Größe ändern"],
    tooltip = L["Skaliert den Haupt-Tooltip des Spiels mit dem Regler darunter. Ausgeschaltet gilt wieder die normale Größe."],
    keywords = { "skalierung", "größe", "scale", "size", "tooltip", "klein", "groß" },
    set = function(value)
        ns.db.tipScaleOn = value
        ApplyScale()
    end,
})

ns.AddOption(3, "Tooltip", {
    key = "tipScale",
    type = "slider",
    min = 50, max = 150, step = 5, unit = "%",
    label = L["Tooltip-Größe"],
    tooltip = L["Größe des Tooltips in Prozent (50–150). Standard: 100."],
    keywords = { "skalierung", "größe", "scale", "size", "tooltip", "prozent" },
    isEnabled = function() return On("tipScaleOn") end,
    disabledHint = L["Erst „Tooltip-Größe ändern“ einschalten (direkt darüber)."],
    set = function(value)
        ns.db.tipScale = value
        ApplyScale()
    end,
})

ns.AddOption(3, "Tooltip", {
    key = "tipIds",
    label = L["IDs im Tooltip anzeigen"],
    tooltip = L["Hängt an Tooltips von Gegenständen, Zaubern, Auren, Quests, Währungen und NPCs eine graue Zeile mit der ID an – praktisch zum Nachschlagen oder Kopieren in Datenbanken."],
    keywords = { "id", "itemid", "spellid", "questid", "npc", "gegenstand", "zauber", "quest", "tooltip" },
})
