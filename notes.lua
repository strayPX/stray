-- stray – Notizen zu Mitspielern: Eintrag im Rechtsklick-Menü, Zeile im Tooltip,
-- Hinweis im Chat, wenn ein Spieler mit Notiz in die Gruppe kommt.
-- Menü über Menu.ModifyMenu (keine UnitPopup-Tabellen, kein Taint).
-- Namen können versiegelt sein (Instanzen): dann nichts anzeigen und nichts speichern.

local _, ns = ...
local L = ns.L

ns.defaults.playerNotes = false
ns.defaults.playerNoteData = {} -- ["Name-Realm"] = "Text"

ns.AddOption(3, "Sozial", {
    key = "playerNotes",
    label = L["Notizen zu Mitspielern"],
    tooltip = L["Im Rechtsklick-Menü auf Spieler (Ziel, Gruppe, Name im Chat) gibt es „stray-Notiz …“.\nDie Notiz steht im Tooltip des Spielers. Kommt er in deine Gruppe, erinnert dich eine Chatzeile daran."],
})

local FONT_BODY = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MAX_LETTERS = 200

local C = {
    bg      = { 0.05, 0.067, 0.09, 0.95 },
    field   = { 0.02, 0.03, 0.045, 1 },
    border  = { 0.169, 0.290, 0.451, 1 },
    accent  = { 0.353, 0.659, 1.0, 1 },
    text    = { 0.89, 0.914, 0.953, 1 },
    textDim = { 0.435, 0.525, 0.651, 1 },
}

---------------------------------------------------------------------------
-- Namen
---------------------------------------------------------------------------

local function OwnRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if ns.IsSecret(realm) or type(realm) ~= "string" or realm == "" then
        realm = GetRealmName and GetRealmName()
        if ns.IsSecret(realm) or type(realm) ~= "string" then return nil end
        realm = realm:gsub("[%s%-]", "")
    end
    return realm ~= "" and realm or nil
end

-- „Name-Realm“ (ohne Realm, wenn der Client keinen kennt). nil bei versiegelten oder leeren Namen.
local function MakeKey(name, realm)
    if ns.IsSecret(name) or ns.IsSecret(realm) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    -- „Name-Realm“ in einem Feld aufteilen
    local base, inline = name:match("^([^%-]+)%-(.+)$")
    if base then name, realm = base, inline end
    if type(realm) ~= "string" or realm == "" then realm = OwnRealm() end
    -- Wie GetNormalizedRealmName: ohne Leer- und Bindestriche, damit alle Quellen denselben Schlüssel liefern
    if realm then realm = realm:gsub("[%s%-]", "") end
    return realm and (name .. "-" .. realm) or name, name
end

local function UnitKey(unit)
    if not unit or ns.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
    if not okPlayer or ns.IsSecret(isPlayer) or not isPlayer then return nil end
    local ok, name, realm = pcall(UnitName, unit)
    if not ok then return nil end
    return MakeKey(name, realm)
end

local function SelfKey()
    return UnitKey("player")
end

local function Note(key)
    if not key or not ns.db or type(ns.db.playerNoteData) ~= "table" then return nil end
    local text = ns.db.playerNoteData[key]
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

---------------------------------------------------------------------------
-- Eingabefenster
---------------------------------------------------------------------------

local function Color(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function Border(frame, c)
    local lines = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER")
        Color(t, c)
        lines[i] = t
    end
    lines[1]:SetPoint("TOPLEFT"); lines[1]:SetPoint("TOPRIGHT"); lines[1]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT"); lines[2]:SetHeight(1)
    lines[3]:SetPoint("TOPLEFT"); lines[3]:SetPoint("BOTTOMLEFT"); lines[3]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT"); lines[4]:SetPoint("BOTTOMRIGHT"); lines[4]:SetWidth(1)
    return lines
end

local function Text(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontHighlightSmall)
    pcall(fs.SetFont, fs, FONT_BODY, size, "")
    c = c or C.text
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function Button(parent, label, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Color(bg, C.field)
    local lines = Border(b, C.border)
    b.text = Text(b, 12)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnEnter", function()
        for _, t in ipairs(lines) do Color(t, C.accent) end
    end)
    b:SetScript("OnLeave", function()
        for _, t in ipairs(lines) do Color(t, C.border) end
    end)
    return b
end

local editor = CreateFrame("Frame", "strayNoteEditor", UIParent)
editor:SetSize(320, 132)
editor:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
editor:SetFrameStrata("DIALOG")
editor:SetToplevel(true)
editor:SetClampedToScreen(true)
editor:SetMovable(true)
editor:EnableMouse(true)
editor:RegisterForDrag("LeftButton")
editor:SetScript("OnDragStart", editor.StartMoving)
editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
editor:Hide()
if UISpecialFrames then table.insert(UISpecialFrames, "strayNoteEditor") end -- Esc schließt

do
    local bg = editor:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Color(bg, C.bg)
    Border(editor, C.border)
end

local title = Text(editor, 13, C.accent)
title:SetPoint("TOPLEFT", 10, -9)
title:SetPoint("RIGHT", editor, "RIGHT", -10, 0)
title:SetJustifyH("LEFT")

local hint = Text(editor, 11, C.textDim)
hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
hint:SetText(L["Enter speichert, Esc schließt. Leer speichern löscht die Notiz."])

local field = CreateFrame("Frame", nil, editor)
field:SetPoint("TOPLEFT", 10, -46)
field:SetPoint("TOPRIGHT", -10, -46)
field:SetHeight(26)
do
    local bg = field:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Color(bg, C.field)
    Border(field, C.border)
end

local box = CreateFrame("EditBox", nil, field)
box:SetPoint("TOPLEFT", 6, -2)
box:SetPoint("BOTTOMRIGHT", -6, 2)
box:SetAutoFocus(false)
box:SetMaxLetters(MAX_LETTERS)
box:SetFontObject(ChatFontNormal)
pcall(box.SetFont, box, FONT_BODY, 13, "")
box:SetTextColor(C.text[1], C.text[2], C.text[3])

local currentKey, currentName

local function Save()
    if not currentKey or not ns.db then return end
    if type(ns.db.playerNoteData) ~= "table" then ns.db.playerNoteData = {} end
    local text = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    -- „|“ würde WoW als Farbcode oder Link lesen
    text = text:gsub("|", "/")
    if text == "" then
        if ns.db.playerNoteData[currentKey] then
            ns.Print(L("Notiz zu %s gelöscht.", currentName or currentKey))
        end
        ns.db.playerNoteData[currentKey] = nil
    else
        ns.db.playerNoteData[currentKey] = text
        ns.Print(L("Notiz zu %s gespeichert.", currentName or currentKey))
    end
    editor:Hide()
end

local saveButton = Button(editor, L["Speichern"], 92)
saveButton:SetPoint("BOTTOMRIGHT", -10, 10)
saveButton:SetScript("OnClick", Save)

local cancelButton = Button(editor, L["Abbrechen"], 92)
cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
cancelButton:SetScript("OnClick", function() editor:Hide() end)

local deleteButton = Button(editor, L["Löschen"], 92)
deleteButton:SetPoint("BOTTOMLEFT", 10, 10)
deleteButton:SetScript("OnClick", function()
    box:SetText("")
    Save()
end)

box:SetScript("OnEnterPressed", Save)
box:SetScript("OnEscapePressed", function() editor:Hide() end)
editor:SetScript("OnHide", function()
    box:ClearFocus()
    currentKey, currentName = nil, nil
end)

local function OpenEditor(key, name)
    if not key then return end
    currentKey, currentName = key, name or key
    title:SetText(L("stray-Notiz: %s", currentName))
    box:SetText(Note(key) or "")
    deleteButton:SetShown(Note(key) ~= nil)
    editor:Show()
    box:SetFocus()
    box:HighlightText()
end

---------------------------------------------------------------------------
-- Rechtsklick-Menü
---------------------------------------------------------------------------

-- Menüs, die auf Spieler zeigen (Forever: Blizzard_UnitPopupShared, Tag „MENU_UNIT_“ .. which)
local MENU_TAGS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
    "MENU_UNIT_FRIEND", "MENU_UNIT_FRIEND_OFFLINE",
    "MENU_UNIT_GUILD", "MENU_UNIT_GUILD_OFFLINE", "MENU_UNIT_CHAT_ROSTER",
    "MENU_UNIT_COMMUNITIES_WOW_MEMBER", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
}

local function KeyFromContext(contextData)
    if type(contextData) ~= "table" then return nil end
    local unit = contextData.unit
    if ns.IsSecret(unit) then return nil end
    if type(unit) == "string" then
        -- Einheit vorhanden: nur echte Spieler (kein NPC im Ziel-Menü)
        return UnitKey(unit)
    end
    local name, server = contextData.name, contextData.server
    if ns.IsSecret(name) or ns.IsSecret(server) then return nil end
    return MakeKey(name, server)
end

local function ModifyMenu(_, rootDescription, contextData)
    if not ns.db or not ns.db.playerNotes then return end
    local key, name = KeyFromContext(contextData)
    if not key or key == SelfKey() then return end
    rootDescription:CreateDivider()
    local label = Note(key) and L["stray-Notiz bearbeiten …"] or L["stray-Notiz …"]
    rootDescription:CreateButton(label, function()
        local ok, err = pcall(OpenEditor, key, name)
        if not ok then geterrorhandler()(err) end
    end)
end

if Menu and Menu.ModifyMenu then
    for _, tag in ipairs(MENU_TAGS) do
        pcall(Menu.ModifyMenu, tag, function(...)
            local ok, err = pcall(ModifyMenu, ...)
            if not ok then geterrorhandler()(err) end
        end)
    end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function OnUnitTooltip(tooltip)
    if not ns.db or not ns.db.playerNotes then return end
    if tooltip ~= GameTooltip or not tooltip.GetUnit then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok then return end
    local key = UnitKey(unit)
    local text = Note(key)
    if not text then return end
    tooltip:AddLine(L("Notiz: %s", text), C.accent[1], C.accent[2], C.accent[3], true)
    tooltip:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        local ok, err = pcall(OnUnitTooltip, tooltip)
        if not ok then geterrorhandler()(err) end
    end)
end

---------------------------------------------------------------------------
-- Neue Gruppenmitglieder
---------------------------------------------------------------------------

local known = {}     -- Schlüssel der aktuellen Mitglieder
local primed = false -- erster Stand nach dem Einloggen wird still übernommen

local function GroupKeys()
    local keys = {}
    local prefix, count
    if IsInRaid and IsInRaid() then
        prefix, count = "raid", (GetNumGroupMembers and GetNumGroupMembers() or 0)
    else
        prefix, count = "party", (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    end
    if ns.IsSecret(count) or type(count) ~= "number" then return keys end
    for i = 1, count do
        local key, name = UnitKey(prefix .. i)
        if key then keys[key] = name or key end
    end
    return keys
end

local function UpdateGroup()
    local current = GroupKeys()
    if primed and ns.db and ns.db.playerNotes then
        local own = SelfKey()
        for key, name in pairs(current) do
            if not known[key] and key ~= own then
                local text = Note(key)
                if text then ns.Print(L("Notiz zu %s: %s", name, text)) end
            end
        end
    end
    known = current
    primed = true
end

ns.On("PLAYER_ENTERING_WORLD", function()
    -- Nach Laden/Neuladen: bestehende Gruppe nicht als „neu“ melden
    known = GroupKeys()
    primed = true
end)

ns.On("GROUP_ROSTER_UPDATE", UpdateGroup)
