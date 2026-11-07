-- stray – Einstellungsfenster
-- Dunkles Fenster mit blauem Akzent: Seitenleiste mit Logo, Suche und Bereichen,
-- rechts die Optionen des gewählten Bereichs als Zeilen mit Schaltern.
-- Die Optionen kommen aus dem Register in stray.lua (ns.AddOption); die Spaltennummer
-- dort stammt aus dem alten Fenster und wird hier nicht mehr gebraucht.

local _, ns = ...

---------------------------------------------------------------------------
-- Maße und Farben
---------------------------------------------------------------------------

local WIDTH, HEIGHT = 760, 540
local SIDE_W = 190
local ROW_H = 48
local MAX_ROWS = 7
local CONTENT_PAD = 22

local MEDIA = "Interface\\AddOns\\stray\\media\\"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BODY = "Fonts\\ARIALN.TTF"

local C = {
    bg        = { 0.051, 0.067, 0.090, 0.97 },
    sideTop   = { 0.063, 0.102, 0.165, 1 },
    sideBot   = { 0.043, 0.067, 0.106, 1 },
    line      = { 0.122, 0.200, 0.322, 1 },
    border    = { 0.169, 0.290, 0.451, 1 },
    card      = { 0.067, 0.102, 0.157, 1 },
    rowLine   = { 0.094, 0.153, 0.251, 1 },
    accent    = { 0.353, 0.659, 1.000, 1 },
    accentDim = { 0.165, 0.435, 0.839, 1 },
    text      = { 0.890, 0.914, 0.953, 1 },
    textDim   = { 0.435, 0.525, 0.651, 1 },
    textSide  = { 0.682, 0.733, 0.816, 1 },
    green     = { 0.184, 0.820, 0.478, 1 },
    off       = { 0.227, 0.275, 0.345, 1 },
    red       = { 1.000, 0.350, 0.350, 1 },
}

-- Gruppen und Reihenfolge der Bereiche in der Seitenleiste
local GROUPS = {
    { name = "Komfort", sections = { "Beute", "Händler", "Taschen", "Quests", "Filmsequenzen", "Chat" } },
    { name = "Kampf", sections = { "Bedrohung" } },
    { name = "Oberfläche", sections = { "Kamera & Karte", "Interface", "Sozial" } },
}

local SUBTITLES = {
    ["Beute"] = "Schneller plündern, ohne Klickerei.",
    ["Händler"] = "Verkaufen und reparieren beim Händler.",
    ["Taschen"] = "Gegenstände zerstören ohne Tipparbeit.",
    ["Quests"] = "Quests annehmen und abgeben ohne Klicks.",
    ["Filmsequenzen"] = "Filmsequenzen und Videos überspringen.",
    ["Chat"] = "Kleine Helfer für den Chat.",
    ["Bedrohung"] = "Wer hat Aggro – für dich und deine Gruppe.",
    ["Kamera & Karte"] = "Kamera, Minimap und der stray-Knopf.",
    ["Interface"] = "Weniger Meldungen, mehr Überblick.",
    ["Sozial"] = "Duelle, Wiederbelebung und Beschwörung.",
}

---------------------------------------------------------------------------
-- Kleine Bausteine
---------------------------------------------------------------------------

local function Color(tex, c)
    -- Eckfarben eines früheren Verlaufs zurücksetzen, sonst mischt sich die alte Farbe hinein
    tex:SetVertexColor(1, 1, 1, 1)
    pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor and CreateColor(1, 1, 1, 1), CreateColor and CreateColor(1, 1, 1, 1))
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function Gradient(tex, orientation, c1, c2)
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and pcall(tex.SetGradient, tex, orientation,
        CreateColor(c1[1], c1[2], c1[3], c1[4] or 1), CreateColor(c2[1], c2[2], c2[3], c2[4] or 1))
    if not ok then
        -- Älterer Client: einfache Fläche in der ersten Farbe
        tex:SetColorTexture(c1[1], c1[2], c1[3], c1[4] or 1)
    end
end

local function Line(parent, c, layer)
    local t = parent:CreateTexture(nil, layer or "BORDER")
    Color(t, c)
    return t
end

local function Border(frame, c)
    local top, bottom, left, right = Line(frame, c), Line(frame, c), Line(frame, c), Line(frame, c)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
end

local function Text(parent, size, c, font, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(font or FONT, size, "")
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Round(tex)
    pcall(tex.SetMask, tex, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
end

-- Flacher Knopf mit Rand; primary = blau gefüllt
local function FlatButton(parent, label, width, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 26)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    if primary then
        Gradient(b.bg, "VERTICAL", { 0.114, 0.310, 0.620, 1 }, { 0.165, 0.435, 0.839, 1 })
    else
        Color(b.bg, { 1, 1, 1, 0.03 })
    end
    Border(b, primary and C.accent or C.border)
    b.text = Text(b, 12, primary and { 1, 1, 1, 1 } or C.textSide, FONT_BODY)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.07)
    return b
end

-- Kurzbeschreibung: erster Satz des Tooltips (Abkürzungen wie „z. B.“ überspringen)
local function ShortDesc(option)
    if option.desc then return option.desc end
    local text = (option.tooltip or ""):match("^[^\n]*") or ""
    local start = 1
    while true do
        local pos = text:find("[%.!%?] ", start)
        if not pos then return text end
        local before = text:sub(math.max(1, pos - 2), pos - 1)
        local abbreviation = before:match("^[%s%.]%a$") or before:match("^%a$")
        if pos > 25 and not abbreviation then return text:sub(1, pos) end
        start = pos + 1
    end
end

---------------------------------------------------------------------------
-- Grundgerüst
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "strayFrame", UIParent)
frame:SetSize(WIDTH, HEIGHT)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()
tinsert(UISpecialFrames, "strayFrame") -- Esc schließt das Fenster

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
Color(bg, C.bg)

-- leichter blauer Schimmer oben rechts
local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
glow:SetPoint("TOPRIGHT")
glow:SetSize(WIDTH - SIDE_W, 140)
Gradient(glow, "VERTICAL", { 0.235, 0.471, 0.863, 0 }, { 0.235, 0.471, 0.863, 0.10 })

Border(frame, C.border)

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.point = { point, relPoint, x, y }
end)

---------------------------------------------------------------------------
-- Seitenleiste
---------------------------------------------------------------------------

local side = CreateFrame("Frame", nil, frame)
side:SetPoint("TOPLEFT", 1, -1)
side:SetPoint("BOTTOMLEFT", 1, 1)
side:SetWidth(SIDE_W)

local sideBg = side:CreateTexture(nil, "BACKGROUND", nil, 2)
sideBg:SetAllPoints()
Gradient(sideBg, "VERTICAL", C.sideBot, C.sideTop)

local sideLine = Line(side, C.line)
sideLine:SetPoint("TOPRIGHT"); sideLine:SetPoint("BOTTOMRIGHT"); sideLine:SetWidth(1)

local logo = side:CreateTexture(nil, "ARTWORK")
logo:SetSize(34, 34)
logo:SetPoint("TOPLEFT", 14, -14)
logo:SetTexture("Interface\\AddOns\\stray\\media\\minimap_icon")

local logoName = Text(side, 18, { 0.910, 0.949, 1, 1 })
logoName:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
logoName:SetText("stray")

local versionText = Text(side, 11, C.textDim, FONT_BODY)
versionText:SetPoint("TOPLEFT", logoName, "BOTTOMLEFT", 0, -2)

local logoLine = Line(side, C.line)
logoLine:SetPoint("TOPLEFT", 0, -62); logoLine:SetPoint("TOPRIGHT", -1, -62); logoLine:SetHeight(1)

-- Suchfeld
local search = CreateFrame("EditBox", nil, side)
search:SetSize(SIDE_W - 24, 24)
search:SetPoint("TOPLEFT", 12, -74)
search:SetAutoFocus(false)
search:SetFont(FONT_BODY, 12, "")
search:SetTextColor(C.text[1], C.text[2], C.text[3])
search:SetTextInsets(8, 8, 0, 0)
local searchBg = search:CreateTexture(nil, "BACKGROUND")
searchBg:SetAllPoints()
Color(searchBg, { 0.039, 0.059, 0.090, 1 })
Border(search, { 0.133, 0.220, 0.353, 1 })
local placeholder = Text(search, 12, { 0.365, 0.451, 0.576, 1 }, FONT_BODY)
placeholder:SetPoint("LEFT", 8, 0)
placeholder:SetText("Suchen …")

---------------------------------------------------------------------------
-- Inhalt
---------------------------------------------------------------------------

local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", SIDE_W + 1 + CONTENT_PAD, -18)
content:SetPoint("BOTTOMRIGHT", -CONTENT_PAD, 14)

local title = Text(content, 22, { 0.949, 0.965, 1, 1 })
title:SetPoint("TOPLEFT")

local subtitle = Text(content, 12, C.textDim, FONT_BODY)
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

local close = CreateFrame("Button", nil, content)
close:SetSize(24, 24)
close:SetPoint("TOPRIGHT")
Border(close, C.border)
local closeText = Text(close, 13, C.textDim, FONT_BODY)
closeText:SetPoint("CENTER", 1, 0)
closeText:SetText("X")
local closeHover = close:CreateTexture(nil, "HIGHLIGHT")
closeHover:SetAllPoints()
closeHover:SetColorTexture(1, 1, 1, 0.07)
close:SetScript("OnClick", function() frame:Hide() end)

local headLine = Line(content, C.line)
headLine:SetPoint("TOPLEFT", 0, -56); headLine:SetPoint("TOPRIGHT", 0, -56); headLine:SetHeight(1)

-- Karte mit den Optionszeilen
local card = CreateFrame("Frame", nil, content)
card:SetPoint("TOPLEFT", 0, -70)
card:SetPoint("TOPRIGHT", 0, -70)
card:SetHeight(ROW_H)
local cardBg = card:CreateTexture(nil, "BACKGROUND")
cardBg:SetAllPoints()
Color(cardBg, C.card)
Border(card, C.line)

local emptyText = Text(content, 12, C.textDim, FONT_BODY)
emptyText:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 2, -10)

-- Vorschau-Bereich unter der Karte
local preview = CreateFrame("Frame", nil, content)
preview:SetSize(272, 150)
preview:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -12)
local previewBg = preview:CreateTexture(nil, "BACKGROUND")
previewBg:SetAllPoints()
Color(previewBg, C.card)
Border(preview, C.line)
local previewImage = preview:CreateTexture(nil, "ARTWORK")
previewImage:SetSize(256, 128)
previewImage:SetPoint("TOP", 0, -8)
local previewCaption = Text(preview, 11, C.textDim, FONT_BODY)
previewCaption:SetPoint("BOTTOMLEFT", 8, 3)
preview:Hide()

-- Fußzeile
local footNote = Text(content, 11, { 0.365, 0.451, 0.576, 1 }, FONT_BODY)
footNote:SetPoint("BOTTOMLEFT", 0, 6)
footNote:SetText("Änderungen gelten sofort.")

local closeButton = FlatButton(content, "Schließen", 96, true)
closeButton:SetPoint("BOTTOMRIGHT")
closeButton:SetScript("OnClick", function() frame:Hide() end)

-- „Neu laden“ sticht in Bernstein heraus; nach einer Änderung pulsiert er
local AMBER = { 1, 0.722, 0.251, 1 }

local reloadButton = FlatButton(content, "Neu laden", 104, false)
reloadButton:SetPoint("RIGHT", closeButton, "LEFT", -8, 0)
reloadButton:SetScript("OnClick", function() ReloadUI() end)
Border(reloadButton, AMBER)
reloadButton.text:SetTextColor(AMBER[1], AMBER[2], AMBER[3])
local reloadFill = reloadButton:CreateTexture(nil, "BACKGROUND", nil, 1)
reloadFill:SetAllPoints()
reloadFill:SetColorTexture(AMBER[1], AMBER[2], AMBER[3], 0.10)

local reloadGlow = reloadButton:CreateTexture(nil, "BACKGROUND", nil, 2)
reloadGlow:SetPoint("TOPLEFT", -4, 4)
reloadGlow:SetPoint("BOTTOMRIGHT", 4, -4)
reloadGlow:SetColorTexture(AMBER[1], AMBER[2], AMBER[3], 0.35)
reloadGlow:Hide()
local reloadPulse = reloadGlow:CreateAnimationGroup()
reloadPulse:SetLooping("BOUNCE")
local pulseAlpha = reloadPulse:CreateAnimation("Alpha")
pulseAlpha:SetFromAlpha(0.15)
pulseAlpha:SetToAlpha(1)
pulseAlpha:SetDuration(0.8)

-- Wurde im Fenster etwas umgeschaltet? Dann beim Schließen Neuladen empfehlen.
local dirty = false

local function SetDirty(value)
    dirty = value
    if value then
        footNote:SetText("Geändert – Neu laden empfohlen.")
        footNote:SetTextColor(AMBER[1], AMBER[2], AMBER[3])
        reloadGlow:Show()
        reloadPulse:Play()
    else
        footNote:SetText("Änderungen gelten sofort.")
        footNote:SetTextColor(0.365, 0.451, 0.576)
        reloadPulse:Stop()
        reloadGlow:Hide()
    end
end

StaticPopupDialogs["STRAY_RELOAD"] = {
    text = "stray: Du hast Einstellungen geändert.\nJetzt neu laden, damit alles sicher übernommen wird?",
    button1 = "Neu laden",
    button2 = "Später",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Bereiche aus dem Register sammeln
---------------------------------------------------------------------------

local sections = {}      -- Name → Liste der Optionen
local sectionOrder = {}  -- { group = Name, section = Name } in Anzeige-Reihenfolge

local function CollectSections()
    for _, column in ipairs(ns.columns) do
        for _, section in ipairs(column) do
            sections[section.name] = sections[section.name] or {}
            for _, option in ipairs(section.options) do
                table.insert(sections[section.name], option)
            end
        end
    end
    local placed = {}
    for _, group in ipairs(GROUPS) do
        for _, name in ipairs(group.sections) do
            if sections[name] then
                table.insert(sectionOrder, { group = group.name, section = name })
                placed[name] = true
            end
        end
    end
    for name in pairs(sections) do
        if not placed[name] then table.insert(sectionOrder, { group = "Weitere", section = name }) end
    end
end
CollectSections()

local function OptionEnabled(option)
    return not option.isEnabled or option.isEnabled()
end

local function SectionActive(name)
    for _, option in ipairs(sections[name]) do
        if OptionEnabled(option) and option.get() then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Seitenleisten-Einträge
---------------------------------------------------------------------------

local selected = sectionOrder[1] and sectionOrder[1].section
local navButtons = {}
local Refresh

local function SelectSection(name)
    selected = name
    search:SetText("")
    search:ClearFocus()
    preview:Hide()
    ns.Sound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    Refresh()
end

do
    local y = -110
    local lastGroup
    for _, entry in ipairs(sectionOrder) do
        if entry.group ~= lastGroup then
            if lastGroup then y = y - 8 end
            lastGroup = entry.group
            local header = Text(side, 11, C.accent, FONT_BODY)
            header:SetPoint("TOPLEFT", 14, y)
            header:SetText(entry.group:upper())
            y = y - 18
        end
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDE_W - 1, 23)
        b:SetPoint("TOPLEFT", 0, y)
        b.section = entry.section

        b.active = b:CreateTexture(nil, "BACKGROUND", nil, 3)
        b.active:SetAllPoints()
        Gradient(b.active, "HORIZONTAL", { 0.275, 0.588, 1, 0.24 }, { 0.275, 0.588, 1, 0 })
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
        Color(b.bar, C.accent)

        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.04)

        b.text = Text(b, 13, C.textSide, FONT_BODY)
        b.text:SetPoint("LEFT", 14, 0)
        b.text:SetText(entry.section)

        b.dot = b:CreateTexture(nil, "ARTWORK")
        b.dot:SetSize(7, 7)
        b.dot:SetPoint("RIGHT", -14, 0)
        b.dot:SetTexture(MEDIA .. "dot")

        b:SetScript("OnClick", function(self) SelectSection(self.section) end)
        table.insert(navButtons, b)
        y = y - 23
    end
end

---------------------------------------------------------------------------
-- Optionszeilen mit Schaltern
---------------------------------------------------------------------------

local rows = {}

-- Färbt eine Textur (z. B. die Pillenform) mit Verlauf, ohne die Textur zu ersetzen
local function Tint(tex, c1, c2)
    tex:SetVertexColor(c1[1], c1[2], c1[3], c1[4] or 1)
    if CreateColor then
        pcall(tex.SetGradient, tex, "HORIZONTAL",
            CreateColor(c1[1], c1[2], c1[3], c1[4] or 1), CreateColor(c2[1], c2[2], c2[3], c2[4] or 1))
    end
end

local SWITCH_OFF = { 0.149, 0.204, 0.290, 1 }

local function SetSwitch(switch, on, enabled)
    switch.knob:ClearAllPoints()
    if on then
        Tint(switch.track, C.accentDim, C.accent)
        switch.knob:SetPoint("RIGHT", -2, 0)
        switch.knob:SetVertexColor(1, 1, 1, 1)
    else
        Tint(switch.track, SWITCH_OFF, SWITCH_OFF)
        switch.knob:SetPoint("LEFT", 2, 0)
        switch.knob:SetVertexColor(0.486, 0.565, 0.678, 1)
    end
    switch:SetAlpha(enabled and 1 or 0.4)
end

local function ShowTooltip(row)
    local option = row.option
    if not option then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(option.label, 1, 1, 1)
    GameTooltip:AddLine(option.tooltip, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
    if not OptionEnabled(option) and option.disabledHint then
        GameTooltip:AddLine(option.disabledHint, 1, 0.3, 0.3, true)
    end
    GameTooltip:Show()
end

local function ShowPreview(option)
    if preview:IsShown() and preview.option == option then
        preview:Hide()
        return
    end
    preview.option = option
    previewImage:SetTexture("Interface\\AddOns\\stray\\media\\" .. option.preview)
    previewCaption:SetText("Beispielbild: " .. option.label)
    preview:Show()
end

local function CreateRow(i)
    local row = CreateFrame("Frame", nil, card)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 14, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -14, -(i - 1) * ROW_H)
    row:EnableMouse(true)

    row.line = Line(row, C.rowLine)
    row.line:SetPoint("BOTTOMLEFT"); row.line:SetPoint("BOTTOMRIGHT"); row.line:SetHeight(1)

    row.label = Text(row, 13, C.text, FONT_BODY)
    row.label:SetPoint("TOPLEFT", 0, -8)

    row.desc = Text(row, 11, C.textDim, FONT_BODY)
    row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row.desc:SetPoint("RIGHT", row, "RIGHT", -130, 0)
    row.desc:SetWordWrap(false)

    local switch = CreateFrame("Button", nil, row)
    switch:SetSize(34, 18)
    switch:SetPoint("RIGHT", 0, 0)
    switch.track = switch:CreateTexture(nil, "ARTWORK")
    switch.track:SetAllPoints()
    switch.track:SetTexture(MEDIA .. "pill")
    switch.knob = switch:CreateTexture(nil, "OVERLAY")
    switch.knob:SetSize(14, 14)
    switch.knob:SetTexture(MEDIA .. "dot")
    switch:SetScript("OnClick", function()
        local option = row.option
        if not option or not OptionEnabled(option) then return end
        local value = not option.get()
        ns.Sound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        option.set(value)
        SetDirty(true)
        Refresh()
    end)
    switch:SetScript("OnEnter", function() ShowTooltip(row) end)
    switch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.switch = switch

    local previewButton = FlatButton(row, "Vorschau", 70, false)
    previewButton:SetHeight(20)
    previewButton:SetPoint("RIGHT", switch, "LEFT", -12, 0)
    previewButton:SetScript("OnClick", function() if row.option then ShowPreview(row.option) end end)
    row.previewButton = previewButton

    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Klick auf die Zeile schaltet ebenfalls um
    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then switch:Click() end
    end)
    return row
end

for i = 1, MAX_ROWS do rows[i] = CreateRow(i) end

local function FillRows(options)
    local shown = math.min(#options, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local row, option = rows[i], options[i]
        if i <= shown then
            local enabled = OptionEnabled(option)
            row.option = option
            row.label:SetText(option.label)
            row.label:SetTextColor(enabled and C.text[1] or C.textDim[1], enabled and C.text[2] or C.textDim[2], enabled and C.text[3] or C.textDim[3])
            if not enabled and option.disabledHint then
                row.desc:SetText(option.disabledHint)
                row.desc:SetTextColor(C.red[1], C.red[2], C.red[3])
            else
                row.desc:SetText(ShortDesc(option))
                row.desc:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end
            SetSwitch(row.switch, option.get() and true or false, enabled)
            -- In der Suche keine Vorschau: dort können mehr Zeilen stehen, als Platz für das Bild bleibt
            row.previewButton:SetShown(option.preview ~= nil and search:GetText() == "")
            row.line:SetShown(i < shown)
            row:Show()
        else
            row.option = nil
            row:Hide()
        end
    end
    card:SetHeight(math.max(shown, 1) * ROW_H)
    card:SetShown(shown > 0)
    return #options - shown
end

---------------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------------

local function SearchResults(query)
    query = query:lower()
    local results = {}
    for _, entry in ipairs(sectionOrder) do
        for _, option in ipairs(sections[entry.section]) do
            local haystack = (option.label .. " " .. (option.tooltip or "") .. " " .. entry.section):lower()
            if haystack:find(query, 1, true) then table.insert(results, option) end
        end
    end
    return results
end

search:SetScript("OnTextChanged", function(self)
    placeholder:SetShown(self:GetText() == "")
    preview:Hide()
    Refresh()
end)
search:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------

function Refresh()
    if not ns.db then return end

    for _, b in ipairs(navButtons) do
        local isSelected = b.section == selected and search:GetText() == ""
        b.active:SetShown(isSelected)
        b.bar:SetShown(isSelected)
        local c = isSelected and { 1, 1, 1, 1 } or C.textSide
        b.text:SetTextColor(c[1], c[2], c[3])
        local dot = SectionActive(b.section) and C.green or C.off
        b.dot:SetVertexColor(dot[1], dot[2], dot[3])
    end

    local query = search:GetText()
    local options, rest
    if query ~= "" then
        title:SetText("Suche")
        options = SearchResults(query)
        subtitle:SetText(#options == 0 and ("Nichts gefunden für „" .. query .. "“.")
            or (#options == 1 and "1 Option gefunden." or (#options .. " Optionen gefunden.")))
    else
        title:SetText(selected or "")
        subtitle:SetText(SUBTITLES[selected] or "")
        options = sections[selected] or {}
    end
    rest = FillRows(options)
    if rest > 0 then
        emptyText:SetText(("… und %d weitere – genauer suchen."):format(rest))
        emptyText:Show()
    else
        emptyText:Hide()
    end
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", card, card:IsShown() and "BOTTOMLEFT" or "TOPLEFT", 0, -12)
end

-- Module können reagieren, wenn das Fenster auf- oder zugeht (z. B. Beispielanzeigen)
ns.configCallbacks = ns.configCallbacks or {}

local function NotifyConfig(open)
    for _, fn in ipairs(ns.configCallbacks) do fn(open) end
end

frame:SetScript("OnShow", function()
    ns.Sound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    Refresh()
    NotifyConfig(true)
end)
frame:SetScript("OnHide", function()
    ns.Sound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    -- Egal wie geschlossen wird (X, „Schließen“, Esc): nach Änderungen Neuladen empfehlen
    if dirty then
        SetDirty(false)
        StaticPopup_Show("STRAY_RELOAD")
    end
    search:ClearFocus()
    preview:Hide()
    GameTooltip:Hide()
    NotifyConfig(false)
end)

-- Falls Einstellungen woanders geändert werden (z. B. Blizzard-Optionen)
ns.On("CVAR_UPDATE", function()
    if frame:IsShown() then Refresh() end
end)

function ns.OnLoaded()
    versionText:SetText(ns.GetVersion())
    if ns.db.point then
        frame:ClearAllPoints()
        frame:SetPoint(ns.db.point[1], UIParent, ns.db.point[2], ns.db.point[3], ns.db.point[4])
    end
end

---------------------------------------------------------------------------
-- Slash-Befehl
---------------------------------------------------------------------------

SLASH_STRAY1 = "/stray"
SlashCmdList["STRAY"] = function()
    if not ns.db then
        ns.Print("noch nicht geladen.")
        return
    end
    frame:SetShown(not frame:IsShown())
end
