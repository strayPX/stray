-- stray – Post: Twink-Liste neben „Post senden“
--
-- Beim Login merkt sich stray den Charakter (Name, Realm, Fraktion, Klasse, Stufe) in
-- ns.db.mailAltList. Auf der Seite „Post senden“ steht daneben eine schmale Liste der Twinks
-- auf demselben Realm und derselben Fraktion. Linksklick setzt den Namen ins Empfängerfeld,
-- Rechtsklick nimmt den Charakter aus der Liste (er kommt beim nächsten Login wieder).
--
-- Ohne Taint: Kein stray-Code läuft in Blizzards Post-Abläufen.
--   - Die Liste ist ein Kind von SendMailFrame und hat keine OnShow-/OnHide-Skripte, sie
--     erscheint und verschwindet also mit der Seite, ohne dass stray dabei mitläuft.
--   - Die Position folgt einem hooksecurefunc auf MailFrameTab_OnClick (Tab-Wechsel, auch
--     „Antworten“) und auf InboxFrame:Update (läuft, wenn der Brief rechts geschlossen wird).
--   - Ein Klick ruft nur SendMailNameEditBox:SetText auf. Fokus und Tab bleiben unberührt.
--
-- „Alles öffnen“ baut stray nicht: Blizzards Posteingang auf Forever hat schon den Knopf
-- „Alle Briefe öffnen“ (OpenAllMail; überspringt GM- und Nachnahmebriefe, stoppt bei vollen
-- Taschen).

local _, ns = ...
local L = ns.L

ns.defaults.mailAlts = false
ns.defaults.mailAltList = {} -- ["Name-Realm"] = { name, realm, faction, class, level, seen }

local FONT = "Fonts\\ARIALN.TTF"
local C = {
    bg     = { 0.051, 0.067, 0.090, 0.95 },
    border = { 0.169, 0.290, 0.451, 1 },
    accent = { 0.353, 0.659, 1.000, 1 },
    text   = { 0.890, 0.914, 0.953, 1 },
    dim    = { 0.435, 0.525, 0.651, 1 },
}

local WIDTH = 160
local ROW_H = 18
local TOP_H = 24
local MAX_ROWS = 16

local panel, title, emptyNote, moreNote
local rows = {}
local hooked = false
local myKey

---------------------------------------------------------------------------
-- Charakterliste
---------------------------------------------------------------------------

local function Plain(v)
    if ns.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

local function List()
    if not ns.db then return nil end
    if type(ns.db.mailAltList) ~= "table" then ns.db.mailAltList = {} end
    return ns.db.mailAltList
end

local function RecordPlayer(level)
    local list = List()
    if not list then return end
    local name = Plain((UnitName("player")))
    local realm = Plain(GetRealmName())
    local faction = Plain((UnitFactionGroup("player")))
    local _, class = UnitClass("player")
    class = Plain(class)
    if not (name and realm and faction and class) then return end
    myKey = name .. "-" .. realm
    local entry = list[myKey]
    if type(entry) ~= "table" then
        entry = {}
        list[myKey] = entry
    end
    entry.name, entry.realm, entry.faction, entry.class = name, realm, faction, class
    local lvl = ns.Public(level) or ns.Public(UnitLevel("player"))
    if type(lvl) == "number" and lvl > 0 then entry.level = lvl end
    entry.seen = time()
end

-- Twinks auf diesem Realm und dieser Fraktion, höchste Stufe zuerst
local function Collect()
    local out = {}
    local list = List()
    if not list then return out end
    local realm = Plain(GetRealmName())
    local faction = Plain((UnitFactionGroup("player")))
    for key, e in pairs(list) do
        if key ~= myKey and type(e) == "table" and e.realm == realm and e.faction == faction and e.name then
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        local la, lb = a.level or 0, b.level or 0
        if la ~= lb then return la > lb end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- Liste neben dem Postfenster
---------------------------------------------------------------------------

local function Border(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    local function Line(p1, p2, horizontal)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        t:SetPoint(p1); t:SetPoint(p2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    end
    Line("TOPLEFT", "TOPRIGHT", true)
    Line("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Line("TOPLEFT", "BOTTOMLEFT", false)
    Line("TOPRIGHT", "BOTTOMRIGHT", false)
end

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetWordWrap(false)
    return fs
end

local Refresh

local function OnRowClick(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
        local list = List()
        if list then list[e.name .. "-" .. e.realm] = nil end
        ns.Print(L("%s aus der Twink-Liste entfernt.", e.name))
        Refresh()
        return
    end
    if SendMailNameEditBox and SendMailNameEditBox.SetText then
        SendMailNameEditBox:SetText(e.name)
    end
end

local function OnRowEnter(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(e.name, 1, 1, 1)
    if e.level then GameTooltip:AddLine(L("Stufe %d", e.level), C.text[1], C.text[2], C.text[3]) end
    GameTooltip:AddLine(L["Linksklick: als Empfänger eintragen"], C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:AddLine(L["Rechtsklick: aus der Liste nehmen"], C.dim[1], C.dim[2], C.dim[3])
    GameTooltip:Show()
end

local function CreateRow(i)
    local r = CreateFrame("Button", nil, panel)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -(TOP_H + 2 + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -(TOP_H + 2 + (i - 1) * ROW_H))
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
    r.level = Text(r, 11, C.dim)
    r.level:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.name = Text(r, 12, C.text)
    r.name:SetPoint("LEFT", r, "LEFT", 7, 0)
    r.name:SetPoint("RIGHT", r.level, "LEFT", -4, 0)
    r.name:SetJustifyH("LEFT")
    r:SetScript("OnClick", OnRowClick)
    r:SetScript("OnEnter", OnRowEnter)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function CreatePanel()
    if panel or not SendMailFrame then return end
    panel = CreateFrame("Frame", "strayMailAlts", SendMailFrame)
    panel:SetWidth(WIDTH)
    panel:EnableMouse(true)
    Border(panel)

    local band = panel:CreateTexture(nil, "ARTWORK")
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(TOP_H - 1)
    band:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.35)

    title = Text(panel, 12, C.accent)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 7, -6)
    title:SetText(L["Twinks"])

    emptyNote = Text(panel, 11, C.dim)
    emptyNote:SetPoint("TOPLEFT", panel, "TOPLEFT", 7, -(TOP_H + 6))
    emptyNote:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -7, -(TOP_H + 6))
    emptyNote:SetWordWrap(true)
    emptyNote:SetJustifyH("LEFT")
    emptyNote:SetText(L["Noch keine Twinks auf diesem Realm. Logg sie einmal ein, dann stehen sie hier."])

    moreNote = Text(panel, 11, C.dim)
    moreNote:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 7, 5)
    panel:Hide()
end

-- Neben dem Postfenster, rechts vom offenen Brief, falls einer offen ist
local function Place()
    if not panel or not MailFrame then return end
    panel:ClearAllPoints()
    if OpenMailFrame and OpenMailFrame:IsShown() then
        panel:SetPoint("TOPLEFT", OpenMailFrame, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    end
end

Refresh = function()
    if not panel then return end
    if not (ns.db and ns.db.mailAlts) then
        panel:Hide()
        return
    end
    local alts = Collect()
    local shown = math.min(#alts, MAX_ROWS)
    for i = 1, shown do
        local r = rows[i] or CreateRow(i)
        local e = alts[i]
        r.entry = e
        local color = RAID_CLASS_COLORS and e.class and RAID_CLASS_COLORS[e.class]
        if color then
            r.name:SetTextColor(color.r, color.g, color.b)
        else
            r.name:SetTextColor(C.text[1], C.text[2], C.text[3])
        end
        r.name:SetText(e.name)
        r.level:SetText(e.level and tostring(e.level) or "")
        r:Show()
    end
    for i = shown + 1, #rows do
        rows[i].entry = nil
        rows[i]:Hide()
    end
    emptyNote:SetShown(#alts == 0)
    local extra = #alts - shown
    if extra > 0 then
        moreNote:SetText(L("+%d weitere", extra))
        moreNote:Show()
    else
        moreNote:Hide()
    end
    local height = TOP_H + 4
    if #alts == 0 then
        height = height + 44
    else
        height = height + shown * ROW_H + (extra > 0 and 16 or 2)
    end
    panel:SetHeight(height)
    Place()
    panel:Show()
end

local function OnTab()
    if not (ns.db and ns.db.mailAlts) or not panel then return end
    Place()
end

local function InstallHooks()
    if hooked or type(MailFrameTab_OnClick) ~= "function" then return end
    hooked = true
    hooksecurefunc("MailFrameTab_OnClick", OnTab)
    if InboxFrame and type(InboxFrame.Update) == "function" then
        hooksecurefunc(InboxFrame, "Update", OnTab)
    end
end

local function Setup()
    if not SendMailFrame then return end
    CreatePanel()
    InstallHooks()
    Refresh()
end

ns.AddOption(1, "NPCs", {
    key = "mailAlts",
    label = L["Twink-Liste beim Post senden"],
    tooltip = L["Neben „Post senden“ steht eine Liste deiner anderen Charaktere auf diesem Realm und derselben Fraktion. Ein Klick trägt den Namen als Empfänger ein, Rechtsklick nimmt einen Charakter aus der Liste.\n\nstray merkt sich jeden Charakter beim Einloggen. Twinks, die du seit der Installation noch nicht eingeloggt hast, fehlen also noch.\n\n„Alle Briefe öffnen“ hat Blizzards Posteingang auf Forever schon selbst."],
    set = function(value)
        ns.db.mailAlts = value
        if value then Setup() elseif panel then panel:Hide() end
    end,
})

ns.On("PLAYER_LOGIN", function()
    RecordPlayer()
    if ns.db.mailAlts then Setup() end
end)

ns.On("PLAYER_LEVEL_UP", function(level)
    RecordPlayer(level)
end)

ns.On("MAIL_SHOW", function()
    if not (ns.db and ns.db.mailAlts) then return end
    Setup()
end)
