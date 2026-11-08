-- stray – Oberfläche: Hauptoption „stray-Oberfläche“ mit Unterschaltern, Minimap-Knopfspalte
-- (Freunde, stray, Addon-Tasche), Menü auf der Minimap (mittlere Maustaste ohne Ping und
-- Kartenmenü-Knopf), Uhrzeit und FPS unter der Minimap, Erfahrungsleiste oben, Taschen- und
-- Menüleiste unten rechts.
-- Alles defensiv: Blizzard-Rahmen können im Client anders heißen oder fehlen.
-- Sichere/geschützte Rahmen nur außerhalb des Kampfes anfassen, sonst nach Kampfende nachholen.
-- Keine Felder auf Blizzard-Frames: Merker stehen in lokalen Tabellen mit dem Frame als Schlüssel.

local _, ns = ...
local L = ns.L

local SECTION = "stray-Oberfläche"
local SECTION_XP = "Erfahrung"

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BODY = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Farben aus der gemeinsamen Tabelle ns.Colors (stray.lua, lila Look); Ersatzwerte, falls sie fehlt
local function Col(key, fallback)
    local c = type(ns.Colors) == "table" and ns.Colors[key]
    if type(c) == "table" and c[1] then return c end
    return fallback
end

local ACCENT_TEXT = Col("accentText", { 0.702, 0.659, 0.980, 1 })

local C = {
    bg      = Col("bg", { 0.078, 0.078, 0.098, 0.96 }),
    border  = Col("line", { 0.149, 0.149, 0.184, 1 }),
    accent  = Col("accent", { 0.545, 0.486, 0.965, 1 }),
    hover   = Col("hover", { 0.122, 0.122, 0.153, 1 }),
    text    = Col("text", { 0.902, 0.902, 0.925, 1 }),
    textDim = Col("textDim", { 0.545, 0.545, 0.600, 1 }),
    xp      = Col("accent", { 0.545, 0.486, 0.965, 1 }),                       -- Lila
    rested  = { ACCENT_TEXT[1], ACCENT_TEXT[2], ACCENT_TEXT[3], 0.40 },        -- helles Lila dahinter
    questxp = { 1.000, 0.820, 0.000, 0.40 }, -- Gold, EP abgabebereiter Quests
}

-- Farbe als Hex für |c-Codes ("ffrrggbb")
local function Hex(c)
    return string.format("ff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
local HEX_ACCENT = Hex(ACCENT_TEXT)
local HEX_DIM = Hex(C.textDim)

ns.defaults.questXPBar = false
ns.defaults.minimapMiddleMenu = false
ns.defaults.bottomMicroButtons = false
ns.defaults.bottomBarSize = 28
-- Neu ab 0.22.0-alpha: Hauptoption, eigener Schalter für die Taschenleiste, EP-Leiste einstellbar
ns.defaults.strayUI = false
ns.defaults.bottomBar = false
ns.defaults.xpBarWidth = 560
ns.defaults.xpBarHeight = 20
ns.defaults.xpBarFontSize = 13

-- Teile der stray-Oberfläche (Unterschalter). Ein Teil wirkt nur, wenn auch die Hauptoption an ist.
-- „Menüknöpfe unten“ (bottomMicroButtons) gehört zur Taschenleiste und zählt hier nicht mit.
local UI_PARTS = { "abEnabled", "bottomBar", "squareMinimap", "minimapMiddleMenu", "hudMinimapColumn", "hudClock", "hudXPBar" }

-- Teil der stray-Oberfläche wirksam? (Hauptschalter und Unterschalter an)
local function UIOn(key)
    return ns.db and ns.db.strayUI and ns.db[key] and true or false
end
ns.StrayUIPart = UIOn

-- Einmalig beim Laden von 0.22: Wer schon Teile an hat, bekommt die Hauptoption an, die Teile
-- bleiben wie sie sind. Die Taschenleiste hing bisher an „Eigene Aktionsleisten“.
local function MigrateStrayUI()
    if not ns.db or ns.db.strayUIMigrated then return end
    ns.db.strayUIMigrated = true
    ns.db.bottomBar = ns.db.abEnabled and true or false
    for _, key in ipairs(UI_PARTS) do
        if ns.db[key] then
            ns.db.strayUI = true
            break
        end
    end
end

ns.On("ADDON_LOADED", function(name)
    if name == ns.name then MigrateStrayUI() end
end)

local CELL = 24
local CELL_GAP = 4

---------------------------------------------------------------------------
-- Kleinkram: Ereignisse, Kampf-Warteschlange, Stil
---------------------------------------------------------------------------

-- Eigener Ereignis-Rahmen: unbekannte Ereignisse (je nach Client) werfen keinen Fehler
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

local function SafeOn(event, fn)
    if not eventHandlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return false end
        eventHandlers[event] = {}
    end
    table.insert(eventHandlers[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for _, fn in ipairs(list) do pcall(fn, ...) end
end)

-- Im Kampf gemerkte Änderungen, nachgeholt bei PLAYER_REGEN_ENABLED
local pending = {}

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function Defer(key, fn)
    pending[key] = fn
end

SafeOn("PLAYER_REGEN_ENABLED", function()
    for key, fn in pairs(pending) do
        pending[key] = nil
        pcall(fn)
    end
end)

local function IsProtectedFrame(frame)
    if not frame or not frame.IsProtected then return false end
    local ok, protected, implicit = pcall(frame.IsProtected, frame)
    return ok and (protected or implicit) and true or false
end

-- Einfacher Rahmen im stray-Stil: dunkle Fläche, 1-px-Rand
local function Style(frame, bg)
    local c = bg or C.bg
    frame.strayBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.strayBg:SetAllPoints()
    frame.strayBg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    local lines = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4])
        lines[i] = t
    end
    lines[1]:SetPoint("TOPLEFT"); lines[1]:SetPoint("TOPRIGHT"); lines[1]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT"); lines[2]:SetHeight(1)
    lines[3]:SetPoint("TOPLEFT"); lines[3]:SetPoint("BOTTOMLEFT"); lines[3]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT"); lines[4]:SetPoint("BOTTOMRIGHT"); lines[4]:SetWidth(1)
    frame.strayLines = lines
end

local function SetBorder(frame, c)
    if not frame.strayLines then return end
    for _, t in ipairs(frame.strayLines) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

local function Text(parent, size, font, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontHighlightSmall)
    pcall(fs.SetFont, fs, font or FONT_BODY, size, flags or "")
    fs:SetTextColor(C.text[1], C.text[2], C.text[3])
    return fs
end

-- Erste Textur aus der Liste, die der Client kennt
local function SetFirstTexture(tex, paths)
    for _, path in ipairs(paths) do
        local ok, result = pcall(tex.SetTexture, tex, path)
        -- Neuere Clients melden Erfolg zurück; ältere geben nichts zurück
        if ok and result ~= false then return true end
    end
    return false
end

local function GoldLine(text)
    GameTooltip:AddLine(text, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], true)
end

-- 12345 → "12.345"
local function Num(n)
    local s = tostring(math.floor(n + 0.5))
    local count
    repeat
        s, count = s:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
    until count == 0
    return s
end

-- 17.46 → "17,5"
local function Pct(v)
    return (string.format("%.1f", v):gsub("%.", ","))
end

local function Number(value)
    value = ns.Public(value)
    if type(value) == "number" then return value end
    return nil
end

local function String(value)
    value = ns.Public(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

---------------------------------------------------------------------------
-- Klassenfarben (lokalisierte Klassennamen → Farbe)
---------------------------------------------------------------------------

local classTokens

local function ClassColorHex(className)
    className = String(className)
    if not className then return "ffffffff" end
    if not classTokens then
        classTokens = {}
        for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
            if type(list) == "table" then
                for token, name in pairs(list) do classTokens[name] = token end
            end
        end
    end
    local token = classTokens[className] or className:upper()
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = colors and colors[token]
    if not c then return "ffffffff" end
    if c.colorStr then return c.colorStr end
    return string.format("ff%02x%02x%02x", math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
end

---------------------------------------------------------------------------
-- 1) Minimap-Knopfspalte
---------------------------------------------------------------------------

local column = CreateFrame("Frame", "strayMinimapColumn", Minimap)
column:SetSize(CELL, CELL)
column:SetFrameStrata("MEDIUM")
column:SetFrameLevel(10)
column:Hide()

local columnSide = nil -- "RIGHT" oder "LEFT"

local function MakeCell(name)
    local b = CreateFrame("Button", name, column)
    b:SetSize(CELL, CELL)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Style(b)
    b:HookScript("OnEnter", function(self) SetBorder(self, C.accent) end)
    b:HookScript("OnLeave", function(self) SetBorder(self, C.border) end)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(16, 16)
    return b
end

local function TooltipAnchor()
    return (columnSide == "LEFT") and "ANCHOR_RIGHT" or "ANCHOR_LEFT"
end

-- Freunde ---------------------------------------------------------------

local friendsCell = MakeCell("strayFriendsButton")
if not SetFirstTexture(friendsCell.icon, {
    "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
    "Interface\\FriendsFrame\\Battlenet-Battleneticon",
    "Interface\\Icons\\INV_Misc_GroupNeedMore",
}) then
    friendsCell.icon:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
end
friendsCell.count = Text(friendsCell, 10, FONT_BODY, "OUTLINE")
friendsCell.count:SetPoint("BOTTOMRIGHT", friendsCell, "BOTTOMRIGHT", -1, 1)

-- Deutsche Schlüssel; übersetzt erst beim Anzeigen (Sprachumschaltung)
local BNET_CLIENT_NAMES = { App = "Battle.net", BSAp = "Battle.net (Handy)", WoW = "WoW" }

local function WowFriends()
    local list = {}
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local ok, num = pcall(C_FriendList.GetNumFriends)
        num = ok and Number(num) or 0
        for i = 1, num do
            local okInfo, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            info = okInfo and ns.Public(info)
            if type(info) == "table" and ns.Public(info.connected) then
                table.insert(list, {
                    name = String(info.name) or "?",
                    class = info.className,
                    level = Number(info.level),
                    area = String(info.area),
                })
            end
        end
    elseif GetNumFriends and GetFriendInfo then
        local num = Number(GetNumFriends()) or 0
        for i = 1, num do
            local name, level, class, area, connected = GetFriendInfo(i)
            if ns.Public(connected) then
                table.insert(list, { name = String(name) or "?", class = class, level = Number(level), area = String(area) })
            end
        end
    end
    return list
end

local function BNetFriends()
    local list = {}
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return list end
    local ok, total = pcall(BNGetNumFriends)
    total = ok and Number(total) or 0
    for i = 1, total do
        local okInfo, acc = pcall(C_BattleNet.GetFriendAccountInfo, i)
        acc = okInfo and ns.Public(acc)
        local game = type(acc) == "table" and ns.Public(acc.gameAccountInfo)
        if type(game) == "table" and ns.Public(game.isOnline) then
            local client = String(game.clientProgram)
            local entry = {
                account = ns.Public(acc.accountName) or String(acc.battleTag) or "?",
                favorite = ns.Public(acc.isFavorite) and true or false,
            }
            if client == (BNET_CLIENT_WOW or "WoW") then
                entry.name = String(game.characterName)
                entry.class = game.className
                entry.level = Number(game.characterLevel)
                entry.area = String(game.areaName) or String(game.richPresence)
            else
                entry.area = (client and BNET_CLIENT_NAMES[client] and L[BNET_CLIENT_NAMES[client]]) or client or ""
            end
            table.insert(list, entry)
        end
    end
    return list
end

local function UpdateFriendCount()
    local count = #WowFriends()
    if BNGetNumFriends then
        local ok, _, online = pcall(BNGetNumFriends)
        count = count + ((ok and Number(online)) or 0)
    end
    friendsCell.count:SetText(count > 0 and tostring(count) or "")
end

local function FriendLine(entry)
    local left
    local hex = ClassColorHex(entry.class)
    if entry.account then
        left = tostring(entry.account)
        if entry.name then left = left .. "  |c" .. hex .. entry.name .. "|r" end
    else
        left = "|c" .. hex .. entry.name .. "|r"
    end
    if entry.level then left = left .. "  |c" .. HEX_DIM .. entry.level .. "|r" end
    GameTooltip:AddDoubleLine(left, entry.area or "", 1, 1, 1, C.textDim[1], C.textDim[2], C.textDim[3])
end

local MAX_LINES = 30

friendsCell:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, TooltipAnchor())
    GameTooltip:AddLine(L["Freunde"])
    local favorites, others = {}, {}
    for _, entry in ipairs(BNetFriends()) do
        table.insert(entry.favorite and favorites or others, entry)
    end
    for _, entry in ipairs(WowFriends()) do table.insert(others, entry) end
    local shown = 0
    if #favorites > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Favoriten"], C.accent[1], C.accent[2], C.accent[3])
        for _, entry in ipairs(favorites) do
            if shown < MAX_LINES then FriendLine(entry) shown = shown + 1 end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L("Freunde (%d)", #others), C.accent[1], C.accent[2], C.accent[3])
    if #others == 0 then
        GameTooltip:AddLine(L["Niemand online"], C.textDim[1], C.textDim[2], C.textDim[3])
    end
    for _, entry in ipairs(others) do
        if shown < MAX_LINES then FriendLine(entry) shown = shown + 1 end
    end
    if #favorites + #others > shown then
        GameTooltip:AddLine(L("… und %d weitere", #favorites + #others - shown), C.textDim[1], C.textDim[2], C.textDim[3])
    end
    GameTooltip:AddLine(" ")
    GoldLine(L["Linksklick: Freundesliste öffnen"])
    GameTooltip:Show()
end)
friendsCell:HookScript("OnLeave", function() GameTooltip:Hide() end)

friendsCell:SetScript("OnClick", function()
    if ToggleFriendsFrame then
        pcall(ToggleFriendsFrame, FRIEND_TAB_FRIENDS or 1)
    elseif FriendsFrame then
        pcall(FriendsFrame.SetShown, FriendsFrame, not FriendsFrame:IsShown())
    end
end)

local friendTimer = false
local function ScheduleFriends()
    if friendTimer or not (UIOn("hudMinimapColumn")) then return end
    friendTimer = true
    C_Timer.After(0.3, function()
        friendTimer = false
        pcall(UpdateFriendCount)
    end)
end

for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
    "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED", "BN_DISCONNECTED", "BN_FRIEND_LIST_SIZE_CHANGED" }) do
    SafeOn(event, ScheduleFriends)
end

-- stray-Knopf -------------------------------------------------------------

local strayCell = CreateFrame("Frame", nil, column)
strayCell:SetSize(CELL, CELL)
Style(strayCell)

if strayMinimapButton then
    strayMinimapButton:HookScript("OnEnter", function()
        if ns.IsMinimapButtonDocked and ns.IsMinimapButtonDocked() then SetBorder(strayCell, C.accent) end
    end)
    strayMinimapButton:HookScript("OnLeave", function() SetBorder(strayCell, C.border) end)
end

-- Addon-Tasche ------------------------------------------------------------

local bagCell = MakeCell("strayAddonBagButton")
if not SetFirstTexture(bagCell.icon, { "Interface\\Icons\\INV_Misc_Bag_08", "Interface\\Buttons\\Button-Backpack-Up" }) then
    bagCell.icon:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
end
bagCell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local addonBag = CreateFrame("Frame", "strayAddonBag", column)
addonBag:SetFrameStrata("HIGH")
addonBag:SetClampedToScreen(true)
addonBag:SetSize(40, 40)
Style(addonBag)
addonBag:Hide()

local BAG_COLS = 4
local BAG_SLOT = 32
local BAG_PAD = 4

-- Blizzard-Knöpfe und Kartenmarkierungen anderer Addons bleiben, wo sie sind
local EXCLUDE = {
    MiniMapTracking = true, MiniMapTrackingButton = true, MiniMapTrackingFrame = true,
    MinimapZoomIn = true, MinimapZoomOut = true, MiniMapMailFrame = true, GameTimeFrame = true,
    MiniMapWorldMapButton = true, MinimapToggleButton = true, QueueStatusMinimapButton = true,
    MiniMapBattlefieldFrame = true, MiniMapLFGFrame = true, LFGMinimapFrame = true,
    TimeManagerClockButton = true, MinimapZoneTextButton = true, MiniMapInstanceDifficulty = true,
    MiniMapVoiceChatFrame = true, MiniMapMeetingStoneFrame = true, ExpansionLandingPageMinimapButton = true,
    AddonCompartmentFrame = true, GarrisonLandingPageMinimapButton = true, MinimapBackdrop = true,
    MinimapCompassTexture = true, MinimapNorthTag = true,
}
local EXCLUDE_PREFIX = {
    "^MiniMap", "^Minimap", "^GameTime", "^TimeManager", "^QueueStatus", "^stray",
    -- Kartenpunkte (keine Knöpfe): Questie, GatherMate, HandyNotes, TomTom …
    "^Questie", "^GatherMate", "^Gatherer", "^HandyNotes", "^TomTom", "^Routes", "^Cartographer",
}

local collected = {} -- [Knopf] = { parent, points, dragStart, dragStop }
local collectedList = {}
local placing = false

local function ShouldCollect(child)
    if collected[child] then return false end
    if not child.IsObjectType or not child:IsObjectType("Button") then return false end
    local name = child.GetName and child:GetName()
    if type(name) ~= "string" or EXCLUDE[name] then return false end
    for _, pattern in ipairs(EXCLUDE_PREFIX) do
        if name:find(pattern) then return false end
    end
    if name:find("Pin%d*$") then return false end
    if IsProtectedFrame(child) then return false end
    local w, h = child:GetWidth(), child:GetHeight()
    if not w or not h or w < 12 or h < 12 or w > 44 or h > 44 then return false end
    return true
end

local LayoutBag -- unten definiert

local function ScheduleBagLayout()
    if addonBag.strayScheduled then return end
    addonBag.strayScheduled = true
    C_Timer.After(0, function()
        addonBag.strayScheduled = false
        pcall(LayoutBag)
    end)
end

local function Collect(child)
    local info = { parent = child:GetParent(), points = {} }
    for i = 1, (child:GetNumPoints() or 0) do
        info.points[i] = { child:GetPoint(i) }
    end
    info.dragStart = child:GetScript("OnDragStart")
    info.dragStop = child:GetScript("OnDragStop")
    collected[child] = info
    table.insert(collectedList, child)
    child:SetScript("OnDragStart", nil)
    child:SetScript("OnDragStop", nil)
    child:SetParent(addonBag)
    child:SetFrameStrata("HIGH")
    child:SetFrameLevel(addonBag:GetFrameLevel() + 2)
    -- Manche Addons (z. B. LibDBIcon) setzen ihren Knopf später wieder an den Minimap-Rand
    hooksecurefunc(child, "SetPoint", function()
        if not placing and collected[child] and UIOn("hudMinimapColumn") then ScheduleBagLayout() end
    end)
    child:HookScript("OnShow", ScheduleBagLayout)
    child:HookScript("OnHide", ScheduleBagLayout)
end

local function CollectButtons()
    if not (UIOn("hudMinimapColumn")) then return end
    local found = false
    for _, holder in ipairs({ Minimap, MinimapBackdrop }) do
        if holder and holder.GetChildren then
            for _, child in ipairs({ holder:GetChildren() }) do
                if ShouldCollect(child) then
                    local ok = pcall(Collect, child)
                    if ok then found = true end
                end
            end
        end
    end
    if found then table.sort(collectedList, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end) end
    pcall(LayoutBag)
end

function LayoutBag()
    local shown = {}
    for _, child in ipairs(collectedList) do
        if collected[child] and child:IsShown() then table.insert(shown, child) end
    end
    placing = true
    for i, child in ipairs(shown) do
        local col = (i - 1) % BAG_COLS
        local row = math.floor((i - 1) / BAG_COLS)
        if child:GetParent() ~= addonBag then pcall(child.SetParent, child, addonBag) end
        child:ClearAllPoints()
        child:SetPoint("CENTER", addonBag, "TOPLEFT",
            BAG_PAD + col * BAG_SLOT + BAG_SLOT / 2, -(BAG_PAD + row * BAG_SLOT + BAG_SLOT / 2))
        child:SetAlpha(1)
    end
    placing = false
    local n = math.max(#shown, 1)
    local cols = math.min(n, BAG_COLS)
    local rows = math.ceil(n / BAG_COLS)
    addonBag:SetSize(cols * BAG_SLOT + 2 * BAG_PAD, rows * BAG_SLOT + 2 * BAG_PAD)
    if not addonBag.empty then
        addonBag.empty = Text(addonBag, 11)
        addonBag.empty:SetPoint("CENTER")
        addonBag.empty:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end
    addonBag.empty:SetText(L["leer"])
    addonBag.empty:SetShown(#shown == 0)
    if #shown == 0 then addonBag:SetSize(BAG_SLOT * 2 + 2 * BAG_PAD, BAG_SLOT + 2 * BAG_PAD) end
end

local function ReleaseButtons()
    placing = true
    for _, child in ipairs(collectedList) do
        local info = collected[child]
        if info then
            pcall(function()
                child:SetParent(info.parent or Minimap)
                child:ClearAllPoints()
                for _, p in ipairs(info.points) do child:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
                child:SetScript("OnDragStart", info.dragStart)
                child:SetScript("OnDragStop", info.dragStop)
                child:SetFrameStrata("MEDIUM")
            end)
            collected[child] = nil
        end
    end
    placing = false
    collectedList = {}
    addonBag:Hide()
end

bagCell:SetScript("OnClick", function()
    if addonBag:IsShown() then
        addonBag:Hide()
    else
        CollectButtons()
        addonBag:Show()
    end
end)

bagCell:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, TooltipAnchor())
    GameTooltip:AddLine(L["Addon-Tasche"])
    local n = 0
    for _ in pairs(collected) do n = n + 1 end
    GameTooltip:AddLine(L("Minimap-Knöpfe anderer Addons: %d", n), C.text[1], C.text[2], C.text[3])
    GoldLine(L["Linksklick: auf- und zuklappen"])
    GameTooltip:AddLine(L["Leatrix Plus „Hide addon buttons“ verträgt sich nicht damit – dort ausschalten, wenn Knöpfe fehlen."],
        C.textDim[1], C.textDim[2], C.textDim[3], true)
    GameTooltip:Show()
end)
bagCell:HookScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Menü: Kartenmenü-Knopf (oben links in der Minimap) und mittlere Maustaste
--
-- Blizzard-Fenster (Charakter, Zauberbuch, Talente, Berufe, Questlog, Gilde, Gruppensuche) öffnet
-- stray nie aus eigenem Code: Das würde diese Fenster bis zum Ende der Sitzung verseuchen (Taint).
-- Stattdessen sind die Zeilen sichere Klick-Knöpfe (SecureActionButtonTemplate, type „click“),
-- die Blizzards eigenen Mikroknopf anklicken. Dessen OnClick läuft dann unverseucht.
-- Die Mikroknöpfe sind auf Forever nicht geschützt; Click() wirkt auch, wenn sie in
-- „Taschen- und Menüleiste“ versteckt geparkt sind (nur nicht, wenn Blizzard sie abschaltet).
---------------------------------------------------------------------------

local function TrackingButton()
    local cluster = MinimapCluster
    local tracking = _G.MiniMapTracking
    -- Kandidaten als Funktionen: fehlende Rahmen dürfen keine Lücke in die Liste reißen
    local candidates = {
        function() return _G.MiniMapTrackingButton end,
        function() return tracking and tracking.Button end,
        function() return cluster and cluster.Tracking and cluster.Tracking.Button end,
        function() return cluster and cluster.TrackingFrame and cluster.TrackingFrame.Button end,
        function() return tracking end,
    }
    for _, get in ipairs(candidates) do
        local ok, b = pcall(get)
        if ok and type(b) == "table" and b.IsObjectType and b:IsObjectType("Button") then return b end
    end
    return nil
end

local function OpenTracking(anchor)
    local b = TrackingButton()
    if b then
        if b.OpenMenu then
            if pcall(b.OpenMenu, b) then return true end
        end
        if pcall(b.Click, b, "LeftButton") then return true end
    end
    if _G.MiniMapTrackingDropDown and ToggleDropDownMenu then
        if pcall(ToggleDropDownMenu, 1, nil, _G.MiniMapTrackingDropDown, anchor, 0, 0) then return true end
    end
    ns.Print(L["Kein Verfolgungs-Menü gefunden."])
    return false
end

-- Verfolgung als Liste mit Häkchen (wie Blizzards Liste, ohne versteckte Einträge)
local function TrackingList()
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo and C_Minimap.SetTracking) then
        return nil
    end
    local ok, n = pcall(C_Minimap.GetNumTrackingTypes)
    n = ok and Number(n) or 0
    local optional = type(MinimapConstants) == "table" and MinimapConstants.OPTIONAL_FILTERS
    local list = {}
    for i = 1, n do
        local okInfo, info = pcall(C_Minimap.GetTrackingInfo, i)
        info = okInfo and ns.Public(info)
        local name = type(info) == "table" and String(info.name)
        local show = name ~= nil
        if show and C_Minimap.GetTrackingFilter then
            local okF, filter = pcall(C_Minimap.GetTrackingFilter, i)
            filter = okF and ns.Public(filter)
            if type(filter) == "table" then
                local fid = ns.Public(filter.filterID)
                show = (ns.Public(filter.spellID) ~= nil) or (type(optional) == "table" and fid ~= nil and optional[fid] and true or false)
            else
                show = false
            end
        end
        if show then
            local index = i
            local function isActive()
                local okA, inf = pcall(C_Minimap.GetTrackingInfo, index)
                inf = okA and ns.Public(inf)
                return type(inf) == "table" and ns.Public(inf.active) and true or false
            end
            table.insert(list, {
                name = name,
                isSelected = isActive,
                toggle = function() pcall(C_Minimap.SetTracking, index, not isActive()) end,
            })
        end
    end
    return list
end

-- Untermenü „Verfolgung“ über Blizzards Kontextmenü (MenuUtil), sonst Blizzards Verfolgungsknopf
local function OpenTrackingMenu(owner)
    local list = TrackingList()
    if list and #list > 0 and MenuUtil and MenuUtil.CreateContextMenu then
        local ok = pcall(MenuUtil.CreateContextMenu, owner or Minimap, function(_, root)
            root:CreateTitle(L["Verfolgung"])
            for _, t in ipairs(list) do
                local cb = root:CreateCheckbox(t.name, t.isSelected, t.toggle)
                if cb and cb.SetResponse and MenuResponse and MenuResponse.Refresh then
                    cb:SetResponse(MenuResponse.Refresh)
                end
            end
        end)
        if ok then return true end
    end
    return OpenTracking(owner)
end

local function OpenCalendar()
    if ToggleCalendar then
        if pcall(ToggleCalendar) then return end
    end
    if GameTimeFrame and GameTimeFrame.Click then
        if pcall(GameTimeFrame.Click, GameTimeFrame) then return end
    end
    ns.Print(L["Kein Kalender gefunden."])
end

local function OpenWorldMap()
    if ToggleWorldMap then
        if pcall(ToggleWorldMap) then return end
    end
    if WorldMapFrame then pcall(WorldMapFrame.SetShown, WorldMapFrame, not WorldMapFrame:IsShown()) end
end

-- secure: Blizzards Mikroknöpfe in Wunschreihenfolge (erster vorhandener gewinnt) → sicherer Klick-Knopf.
-- Forever: getrennte SpellbookMicroButton/TalentMicroButton; PlayerSpellsMicroButton gibt es dort
-- auch, er öffnet aber den zuletzt gezeigten Reiter (nur Ersatz für Clients ohne getrennte Knöpfe).
-- has: gibt es einen normalen Eintrag in diesem Client? frame: im Kampf nur, wenn der Rahmen
-- schon geladen und nicht geschützt ist (nur für normale Knöpfe der unteren Leiste).
-- micro: erscheint auch als Knopf in der Taschen- und Menüleiste.
-- rule: Spielregel (Enum.GameRule), mit der Blizzard den Knopf auf Forever abschaltet; ruleFn: eigene
-- Prüfung (Abenteuerführer). Liste wie Blizzard_MicroMenu/Camelot/MicroMenuContainerOverrides.lua.
-- label ist der deutsche Schlüssel: übersetzt wird erst beim Anzeigen (Sprachumschaltung).
local MENU_ENTRIES = {
    { key = "char", label = "Charakter", micro = true, secure = { "CharacterMicroButton" },
        rule = "CharacterPanelDisabled", icons = { "Interface\\Icons\\INV_Chest_Cloth_17" } },
    { key = "spell", label = "Zauberbuch", micro = true, secure = { "SpellbookMicroButton", "PlayerSpellsMicroButton" },
        icons = { "Interface\\Icons\\INV_Misc_Book_09" } },
    { key = "talent", label = "Talente", micro = true, secure = { "TalentMicroButton" },
        icons = { "Interface\\Icons\\Ability_Marksmanship" } },
    { key = "prof", label = "Berufe", micro = true, secure = { "ProfessionMicroButton" },
        rule = "ProfessionsPanelDisabled", icons = { "Interface\\Icons\\INV_Pick_02", "Interface\\Icons\\Trade_Engineering" } },
    { key = "legacy", label = "Vermächtnis", secure = { "LegacyMicroButton" } },
    { key = "quest", label = "Questlog", micro = true, secure = { "QuestLogMicroButton" },
        rule = "QuestLogMicrobuttonDisabled", icons = { "Interface\\Icons\\INV_Misc_Book_08" } },
    { key = "housing", label = "Wohnen", secure = { "HousingMicroButton" }, rule = "HousingDashboardDisabled" },
    { key = "friends", label = "Freunde", icons = { "Interface\\Icons\\INV_Misc_GroupNeedMore" },
        has = function() return ToggleFriendsFrame ~= nil end,
        frame = function() return _G.FriendsFrame end,
        run = function() ToggleFriendsFrame(FRIEND_TAB_FRIENDS or 1) end },
    { key = "guild", label = "Gilde", micro = true, secure = { "GuildMicroButton" },
        rule = "CommunitiesPanelDisabled", icons = { "Interface\\Icons\\INV_Shirt_GuildTabard_01" } },
    { key = "lfg", label = "Gruppensuche", micro = true, secure = { "LFDMicroButton", "LFGMicroButton" },
        rule = "FinderPanelDisabled", icons = { "Interface\\Icons\\INV_Misc_GroupLooking" } },
    { key = "collections", label = "Sammlung", micro = true, secure = { "CollectionsMicroButton" },
        rule = "CollectionsPanelDisabled", icons = { "Interface\\Icons\\Ability_Mount_RidingHorse" } },
    { key = "journal", label = "Abenteuerführer", micro = true, secure = { "EJMicroButton" },
        ruleFn = function()
            if GameRulesUtil and type(GameRulesUtil.EJIsDisabled) == "function" then
                local ok, off = pcall(GameRulesUtil.EJIsDisabled)
                return ok and off and true or false
            end
            return false
        end,
        icons = { "Interface\\Icons\\INV_Misc_Book_17" } },
    { divider = true },
    { key = "calendar", label = "Kalender",
        has = function() return ToggleCalendar ~= nil or GameTimeFrame ~= nil end,
        frame = function() return _G.CalendarFrame end,
        run = OpenCalendar },
    { key = "tracking", label = "Verfolgung",
        has = function()
            return (C_Minimap and C_Minimap.GetNumTrackingTypes) ~= nil
                or TrackingButton() ~= nil or _G.MiniMapTrackingDropDown ~= nil
        end,
        run = OpenTrackingMenu },
    { key = "worldmap", label = "Weltkarte",
        has = function() return ToggleWorldMap ~= nil or WorldMapFrame ~= nil end,
        frame = function() return _G.WorldMapFrame end,
        run = OpenWorldMap },
    { key = "alts", label = "Twinks",
        has = function() return ns.ToggleAlts ~= nil and ns.db and ns.db.alts and true or false end,
        run = function() ns.ToggleAlts() end },
}

-- Blizzards Mikroknopf zu einem sicheren Eintrag (oder nil)
local function MicroFor(entry)
    if not entry.secure then return nil end
    for _, name in ipairs(entry.secure) do
        local b = _G[name]
        if type(b) == "table" and b.IsObjectType then
            local ok, isButton = pcall(b.IsObjectType, b, "Button")
            if ok and isButton then return b end
        end
    end
    return nil
end

-- Blizzard schaltet Mikroknöpfe ab (z. B. Talente unter Stufe 10): Click() bewirkt dann nichts
local function MicroUsable(entry)
    local b = MicroFor(entry)
    if not b then return false end
    local ok, enabled = pcall(b.IsEnabled, b)
    if not ok then return true end
    return ns.Public(enabled) and true or false
end

-- Von Blizzard per Spielregel gesperrt? (Blizzard nimmt den Knopf dann gar nicht in die Menüleiste)
local function RuleOff(entry)
    if entry.ruleFn then
        local ok, off = pcall(entry.ruleFn)
        if ok and off then return true end
    end
    if entry.rule and C_GameRules and C_GameRules.IsGameRuleActive and type(Enum) == "table"
        and type(Enum.GameRule) == "table" then
        local rule = Enum.GameRule[entry.rule]
        if rule ~= nil then
            local ok, active = pcall(C_GameRules.IsGameRuleActive, rule)
            if ok and ns.Public(active) == true then return true end
        end
    end
    return false
end

local function Has(entry)
    if entry.divider then return false end
    if entry.secure then return MicroFor(entry) ~= nil and not RuleOff(entry) end
    local ok, has = pcall(entry.has)
    return ok and has and true or false
end

-- Namen aller gerade verfügbaren Einträge, z. B. für Tooltips
local function AvailableLabels()
    local names = {}
    for _, entry in ipairs(MENU_ENTRIES) do
        if not entry.divider and Has(entry) then table.insert(names, L[entry.label]) end
    end
    return table.concat(names, ", ")
end

-- Normaler Eintrag im Kampf gesperrt? (geschützte oder noch nicht geladene Fenster)
local function BlockedNow(entry)
    if entry.secure or not InCombat() then return false end
    if entry.frame then
        local ok, f = pcall(entry.frame)
        if not ok or type(f) ~= "table" then return true end
        return IsProtectedFrame(f)
    end
    return false
end

local function RunEntry(entry, anchor)
    if entry.secure or not entry.run then return end
    if BlockedNow(entry) then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or L["Im Kampf nicht möglich."], 1, 0.3, 0.3) end
        return
    end
    pcall(entry.run, anchor)
end

-- Sicherer Klick-Knopf auf einen Blizzard-Mikroknopf. Nur außerhalb des Kampfes bauen; kein
-- SetScript("OnClick") darauf, sonst ist der Klick nicht mehr sicher.
local function MakeSecureClick(name, parent, target)
    if InCombat() then return nil end
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("type", "click")
    b:SetAttribute("clickbutton", target)
    -- Sonst reagiert der Knopf je nach CVar ActionButtonUseKeyDown nur beim Drücken
    b:SetAttribute("useOnKeyDown", false)
    return b
end

-- Kartenmenü-Knopf -------------------------------------------------------------

local mapButton = CreateFrame("Button", "strayMapMenuButton", Minimap)
mapButton:SetSize(18, 18)
mapButton:SetFrameStrata("MEDIUM")
mapButton:SetFrameLevel(12)
mapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
mapButton:SetAlpha(0.75)
Style(mapButton)
mapButton.icon = mapButton:CreateTexture(nil, "ARTWORK")
mapButton.icon:SetPoint("CENTER")
mapButton.icon:SetSize(12, 12)
if not SetFirstTexture(mapButton.icon, { "Interface\\Icons\\INV_Misc_Map_01", "Interface\\Icons\\INV_Misc_Map02" }) then
    mapButton.icon:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
end
mapButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
mapButton:Hide()

-- stray-Klappmenü -------------------------------------------------------------------
-- Mit sicheren Zeilen ist der Rahmen selbst geschützt: Öffnen, Umbau und Schließen nur außerhalb
-- des Kampfes. Kein Ankern an Minimap oder Knopf (sonst würden die mit geschützt), nur an UIParent.

local MENU_NAME = "strayMinimapMenu"
local MENU_W = 130
local ROW_H = 18

local menu = CreateFrame("Frame", MENU_NAME, UIParent)
menu:SetFrameStrata("DIALOG")
menu:SetClampedToScreen(true)
menu:EnableMouse(true)
menu:SetSize(MENU_W, 40)
Style(menu)
menu:Hide()

-- Esc schließt das Menü
if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, MENU_NAME) end

local menuItems = {}   -- { entry, row } bzw. { divider = Textur } in Reihenfolge
local menuBuilt = false
local menuOwner = nil

local function CloseMenu()
    if menu:IsShown() and not InCombat() then menu:Hide() end
end

local function RowText(row)
    row.text = Text(row, 11)
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
end

local function BuildMenu()
    if menuBuilt then return true end
    if InCombat() then return false end
    menuBuilt = true
    for _, entry in ipairs(MENU_ENTRIES) do
        if entry.divider then
            local line = menu:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
            line:SetHeight(1)
            line:Hide()
            table.insert(menuItems, { divider = line })
        else
            local row
            if entry.secure then
                local target = MicroFor(entry)
                if target then
                    row = MakeSecureClick("strayMinimapMenu_" .. entry.key, menu, target)
                    -- Nach dem sicheren Klick (unverseucht) das Menü schließen
                    if row then row:SetScript("PostClick", function() CloseMenu() end) end
                end
            else
                row = CreateFrame("Button", nil, menu)
                row:RegisterForClicks("LeftButtonUp")
                row:SetScript("OnClick", function(self)
                    local owner = menuOwner
                    CloseMenu()
                    RunEntry(self.entry, owner or mapButton)
                end)
            end
            if row then
                row.entry = entry
                row:SetSize(MENU_W - 2, ROW_H)
                RowText(row)
                row:Hide()
                table.insert(menuItems, { entry = entry, row = row })
            end
        end
    end
    return true
end

-- Zeilen nach Verfügbarkeit ein-/ausblenden; Trennlinie nur zwischen zwei sichtbaren Gruppen
local function LayoutMenu()
    local visible = {}
    for _, item in ipairs(menuItems) do
        if item.divider then
            item.divider:Hide()
            if #visible > 0 and not visible[#visible].divider then table.insert(visible, item) end
        else
            item.row:Hide()
            if Has(item.entry) then table.insert(visible, item) end
        end
    end
    if #visible > 0 and visible[#visible].divider then table.remove(visible) end
    local y = -4
    for _, item in ipairs(visible) do
        if item.divider then
            item.divider:ClearAllPoints()
            item.divider:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, y - 3)
            item.divider:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -6, y - 3)
            item.divider:Show()
            y = y - 7
        else
            local row = item.row
            local usable = not item.entry.secure or MicroUsable(item.entry)
            local c = usable and C.text or C.textDim
            row.text:SetText(L[item.entry.label])
            row.text:SetTextColor(c[1], c[2], c[3])
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, y)
            row:Show()
            y = y - ROW_H
        end
    end
    menu:SetSize(MENU_W, -y + 4)
end

-- Bildschirmpunkt (UIParent-Koordinaten) für das Menü
local function MenuPoint(owner)
    local ui = UIParent:GetEffectiveScale()
    if owner == mapButton and mapButton:IsVisible() then
        local left, bottom = mapButton:GetLeft(), mapButton:GetBottom()
        if left and bottom then
            local s = mapButton:GetEffectiveScale() / ui
            return left * s, bottom * s - 2
        end
    end
    local x, y = GetCursorPosition()
    return x / ui + 2, y / ui - 2
end

local function OpenMenu(owner)
    if InCombat() then
        ns.Print(L["Menü geht erst nach dem Kampf."])
        return
    end
    if not BuildMenu() then return end
    menuOwner = owner
    LayoutMenu()
    local x, y = MenuPoint(owner)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    menu:Show()
end

ns.OpenStrayMinimapMenu = function() OpenMenu(Minimap) end

-- Klick daneben schließt (Knopf und Karte selbst regeln ihr Auf/Zu im Klick)
SafeOn("GLOBAL_MOUSE_DOWN", function(mouseButton)
    if not menu:IsShown() or InCombat() then return end
    if menu:IsMouseOver() then return end
    if menuOwner == mapButton and mapButton:IsMouseOver() then return end
    -- Zweiter Mittelklick auf die Karte schließt im eigenen Handler (sonst ginge es gleich wieder auf)
    if menuOwner == Minimap and mouseButton == "MiddleButton" and Minimap:IsMouseOver() then return end
    menu:Hide()
end)

-- Kampfbeginn: Das Ereignis kommt kurz vor der Sperre, das Menü lässt sich dann meist noch schließen
SafeOn("PLAYER_REGEN_DISABLED", function()
    if menu:IsShown() and not InCombatLockdown() then menu:Hide() end
end)

mapButton:SetScript("OnClick", function(self)
    if menu:IsShown() and menuOwner == self then
        CloseMenu()
    else
        OpenMenu(self)
    end
end)
mapButton:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    SetBorder(self, C.accent)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(L["Kartenmenü"])
    GoldLine(L("Linksklick: %s", AvailableLabels()))
    GameTooltip:AddLine(L["Geht nur außerhalb des Kampfes."], C.textDim[1], C.textDim[2], C.textDim[3], true)
    GameTooltip:Show()
end)
mapButton:SetScript("OnLeave", function(self)
    self:SetAlpha(0.75)
    SetBorder(self, C.border)
    GameTooltip:Hide()
end)

-- Mittlere Maustaste auf der Minimap ohne Ping -------------------------------------
-- Blizzard pingt bei jeder Maustaste im Innenkreis der Karte (Minimap OnClick). Ein unsichtbarer
-- eigener Rahmen über der Karte fängt deshalb nur die mittlere Taste: Links, Rechts und die
-- Seitentasten reicht er per SetPassThroughButtons an die Karte (und Kartenpunkte) durch, das
-- Mausrad nimmt er gar nicht an, Mausbewegung möglichst auch nicht (Tooltips der Kartenpunkte).
-- Blizzards Kartenskript bleibt unberührt. Klappt das im Client nicht, bleibt nur der Kartenmenü-Knopf.

local middleCatcher = CreateFrame("Frame", "strayMinimapMiddleClick", Minimap)
middleCatcher:SetAllPoints(Minimap)
middleCatcher:Hide()

local catcherReady = nil -- nil = noch nicht eingerichtet, true/false = Ergebnis

local function SetupCatcher()
    if catcherReady ~= nil then return catcherReady end
    if InCombat() then return false end -- SetPassThroughButtons ist eine geschützte Funktion
    local ok = pcall(middleCatcher.SetPassThroughButtons, middleCatcher, "LeftButton", "RightButton", "Button4", "Button5")
    if ok then
        middleCatcher:EnableMouse(true)
        pcall(middleCatcher.EnableMouseWheel, middleCatcher, false)
        -- Bewegung nicht abfangen, sonst fehlen die Tooltips der Kartenpunkte
        if not pcall(middleCatcher.SetMouseMotionEnabled, middleCatcher, false) then
            pcall(middleCatcher.SetPropagateMouseMotion, middleCatcher, true)
        end
    else
        middleCatcher:EnableMouse(false)
    end
    catcherReady = ok and true or false
    return catcherReady
end

middleCatcher:SetScript("OnMouseUp", function(_, mouseButton)
    if mouseButton ~= "MiddleButton" or not UIOn("minimapMiddleMenu") then return end
    if menu:IsShown() and menuOwner == Minimap then
        CloseMenu()
    else
        OpenMenu(Minimap)
    end
end)

local UpdateMapButton -- unten

local function UpdateMiddleClick()
    local want = UIOn("minimapMiddleMenu")
    if want and SetupCatcher() then
        -- Über der Karte, aber unter eigenen Knöpfen und den Kartenpunkten anderer Addons
        middleCatcher:SetFrameStrata(Minimap:GetFrameStrata())
        middleCatcher:SetFrameLevel(Minimap:GetFrameLevel() + 1)
        middleCatcher:Show()
    else
        middleCatcher:Hide()
        if want and catcherReady == nil then Defer("middleCatcher", UpdateMiddleClick) end
    end
    if UpdateMapButton then pcall(UpdateMapButton) end
end

-- Kartenmenü-Knopf mit der Knopfspalte, bei eckiger Karte immer (dort fehlen Blizzards
-- Verfolgungs- und Kalenderknopf) und als Ersatz, wenn die mittlere Maustaste nicht abfangbar ist
function UpdateMapButton()
    local square = ns.IsSquareMinimap and ns.IsSquareMinimap() or false
    local middleFallback = UIOn("minimapMiddleMenu") and catcherReady == false
    local want = (UIOn("hudMinimapColumn") or square or middleFallback) and true or false
    mapButton:SetShown(want)
    if not want and menuOwner == mapButton then CloseMenu() end
end

-- Aufbau der Spalte ----------------------------------------------------------

local function ScreenSide()
    local right = Minimap:GetRight()
    local uiRight = UIParent:GetRight()
    if not right or not uiRight then return "RIGHT" end
    local mapScale = Minimap:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local need = (CELL + CELL_GAP + 2) * column:GetEffectiveScale()
    if right * mapScale + need > uiRight * uiScale then return "LEFT" end
    return "RIGHT"
end

local function LayoutColumn()
    if not (UIOn("hudMinimapColumn")) then return end
    -- Eckige Minimap (minimap.lua): Spalte links bündig am Block aus Gebietsname und Karte
    local top = ns.SquareMinimapTop and ns.SquareMinimapTop()
    local gap = CELL_GAP
    column:ClearAllPoints()
    if top then
        columnSide = "LEFT"
        gap = 2
        column:SetPoint("TOPRIGHT", top, "TOPLEFT", 1, 0)
    else
        columnSide = ScreenSide()
        if columnSide == "RIGHT" then
            column:SetPoint("TOPLEFT", Minimap, "TOPRIGHT", CELL_GAP, 0)
        else
            column:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -CELL_GAP, 0)
        end
    end

    local cells = { friendsCell }
    if ns.db.minimapButton and strayMinimapButton and ns.MinimapButtonDock then
        table.insert(cells, strayCell)
        strayCell:Show()
        ns.MinimapButtonDock(strayCell)
    else
        strayCell:Hide()
        if ns.MinimapButtonDock then ns.MinimapButtonDock(strayCell) end -- versteckt mit der Zelle
    end
    table.insert(cells, bagCell)

    for i, cell in ipairs(cells) do
        cell:ClearAllPoints()
        cell:SetPoint("TOP", column, "TOP", 0, -(i - 1) * (CELL + gap))
        cell:Show()
    end
    column:SetSize(CELL, #cells * (CELL + gap) - gap)

    -- Die Tasche klappt von der Karte weg auf
    addonBag:ClearAllPoints()
    if columnSide == "RIGHT" then
        addonBag:SetPoint("TOPRIGHT", bagCell, "BOTTOMRIGHT", 0, -CELL_GAP)
    else
        addonBag:SetPoint("TOPRIGHT", bagCell, "TOPLEFT", -CELL_GAP, 0)
    end
end

ns.OnMinimapButtonOption = function()
    if UIOn("hudMinimapColumn") then LayoutColumn() end
end

local function ApplyColumn(toggled)
    if UIOn("hudMinimapColumn") then
        LayoutColumn()
        column:Show()
        UpdateMapButton()
        pcall(UpdateFriendCount)
        if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
        CollectButtons()
    else
        column:Hide()
        UpdateMapButton()
        if ns.MinimapButtonUndock then ns.MinimapButtonUndock() end
        if toggled and #collectedList > 0 then
            ReleaseButtons()
            ns.Print(L["Die Minimap-Knöpfe anderer Addons sind zurück an der Minimap – nach /reload sitzen sie wieder richtig."])
        end
    end
end

-- Minimap verschoben oder neu skaliert: Seite neu prüfen
Minimap:HookScript("OnSizeChanged", function()
    if UIOn("hudMinimapColumn") then C_Timer.After(0, function() pcall(LayoutColumn) end) end
end)
SafeOn("EDIT_MODE_LAYOUTS_UPDATED", function()
    if UIOn("hudMinimapColumn") then C_Timer.After(0.5, function() pcall(LayoutColumn) end) end
end)

---------------------------------------------------------------------------
-- 2) Uhrzeit und FPS
---------------------------------------------------------------------------

local clock = CreateFrame("Button", "strayClock", Minimap)
clock:SetSize(120, 16)
clock:SetFrameStrata("MEDIUM")
clock:SetFrameLevel(10)
clock:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
clock:RegisterForClicks("LeftButtonUp")
clock.text = Text(clock, 12, FONT_BODY, "OUTLINE")
clock.text:SetPoint("CENTER")
clock:Hide()

-- Blizzards Koordinaten (Edit Mode „Spielerkoordinaten“, CVar minimapShowPlayerCoords) stehen
-- bei der runden Karte 8–18 px unter der Minimap: die Uhr rückt dann darunter.
local function BlizzardCoordsOn()
    local ok, on = pcall(ns.GetCVarOn, "minimapShowPlayerCoords")
    return ok and on and true or false
end

local clockLayoutKey = nil

local function LayoutClock(force)
    local square = ns.IsSquareMinimap and ns.IsSquareMinimap() or false
    local clockOn = UIOn("hudClock") and true or false
    local coordsOn = (not square) and BlizzardCoordsOn()
    local key = (square and "s" or "r") .. (coordsOn and "c" or "") .. (clockOn and "u" or "")
    if not force and key == clockLayoutKey then return end
    clockLayoutKey = key
    clock:ClearAllPoints()
    if square then
        clock:SetPoint("TOP", Minimap, "BOTTOM", 0, -3)
    elseif coordsOn then
        clock:SetPoint("TOP", Minimap, "BOTTOM", 0, -20)
    else
        clock:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
    end
    -- Eckig: stray-Koordinaten (minimap.lua) unter der Uhr, sonst direkt unter der Karte
    local coords = ns.SquareMinimapCoords
    if square and coords then
        coords:ClearAllPoints()
        if clockOn then
            coords:SetPoint("TOP", clock, "BOTTOM", 0, 1)
        else
            coords:SetPoint("TOP", Minimap, "BOTTOM", 0, -3)
        end
    end
end

local function UpdateClock()
    local fps = GetFramerate and Number(GetFramerate())
    local fpsText = fps and tostring(math.floor(fps + 0.5)) or "?"
    clock.text:SetText(string.format("|c%s%s|r FPS   %s", HEX_ACCENT, fpsText, date("%H:%M")))
    LayoutClock(false)
end

clock:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Uhrzeit und Leistung"])
    GameTooltip:AddDoubleLine(L["Ortszeit"], date("%H:%M"), 1, 1, 1, 1, 1, 1)
    if GetGameTime then
        local h, m = GetGameTime()
        h, m = Number(h), Number(m)
        if h and m then GameTooltip:AddDoubleLine(L["Serverzeit"], string.format("%02d:%02d", h, m), 1, 1, 1, 1, 1, 1) end
    end
    if GetNetStats then
        local _, _, home, world = GetNetStats()
        home, world = Number(home), Number(world)
        if home then GameTooltip:AddDoubleLine(L["Latenz (Heim)"], home .. " ms", 1, 1, 1, 1, 1, 1) end
        if world then GameTooltip:AddDoubleLine(L["Latenz (Welt)"], world .. " ms", 1, 1, 1, 1, 1, 1) end
    end
    local fps = GetFramerate and Number(GetFramerate())
    if fps then GameTooltip:AddDoubleLine(L["Bilder pro Sekunde"], tostring(math.floor(fps + 0.5)), 1, 1, 1, 1, 1, 1) end
    if TimeManager_Toggle or ToggleTimeManager then
        GameTooltip:AddLine(" ")
        GoldLine(L["Linksklick: Uhr und Wecker"])
    end
    GameTooltip:Show()
end)
clock:SetScript("OnLeave", function() GameTooltip:Hide() end)
clock:SetScript("OnClick", function()
    local toggle = TimeManager_Toggle or ToggleTimeManager
    if toggle then pcall(toggle) end
end)

local clockTicker
local hookedClock = {} -- Blizzard-Uhrknöpfe mit OnShow-Hook (keine Felder auf Blizzard-Frames)

local function HideBlizzardClock()
    local b = _G.TimeManagerClockButton
    if not b then return end
    pcall(b.Hide, b)
    if not hookedClock[b] then
        hookedClock[b] = true
        pcall(b.HookScript, b, "OnShow", function(self)
            if UIOn("hudClock") then pcall(self.Hide, self) end
        end)
    end
end

local function ApplyClock(toggled)
    LayoutClock(true)
    if UIOn("hudClock") then
        UpdateClock()
        clock:Show()
        if not clockTicker then
            clockTicker = C_Timer.NewTicker(1, function() pcall(UpdateClock) end)
        end
        HideBlizzardClock()
    else
        clock:Hide()
        if clockTicker then clockTicker:Cancel() clockTicker = nil end
        if toggled and _G.TimeManagerClockButton then pcall(_G.TimeManagerClockButton.Show, _G.TimeManagerClockButton) end
    end
end

-- minimap.lua meldet, wenn die Karte eckig/rund wird oder die Größe wechselt
ns.HudLayoutAroundMap = function()
    pcall(UpdateMiddleClick)
    pcall(UpdateMapButton)
    if UIOn("hudMinimapColumn") then pcall(LayoutColumn) end
    pcall(LayoutClock, true)
end


---------------------------------------------------------------------------
-- 3) Erfahrungsleiste oben
---------------------------------------------------------------------------

local xpBar = CreateFrame("Frame", "strayXPBar", UIParent)
xpBar:SetSize(500, 14)
xpBar:SetFrameStrata("MEDIUM")
Style(xpBar)
xpBar:Hide()

local restBar = CreateFrame("StatusBar", nil, xpBar)
restBar:SetPoint("TOPLEFT", 1, -1)
restBar:SetPoint("BOTTOMRIGHT", -1, 1)
restBar:SetStatusBarTexture(WHITE)
restBar:SetStatusBarColor(C.rested[1], C.rested[2], C.rested[3], C.rested[4])
restBar:SetMinMaxValues(0, 1)
restBar:SetValue(0)

-- EP abgeschlossener, noch nicht abgegebener Quests: ab dem aktuellen EP-Stand, über dem Erholt-Bereich
local questBar = CreateFrame("StatusBar", nil, xpBar)
questBar:SetAllPoints(restBar)
questBar:SetFrameLevel(restBar:GetFrameLevel() + 1)
questBar:SetStatusBarTexture(WHITE)
questBar:SetStatusBarColor(C.questxp[1], C.questxp[2], C.questxp[3], C.questxp[4])
questBar:SetMinMaxValues(0, 1)
questBar:SetValue(0)
questBar:Hide()

local mainBar = CreateFrame("StatusBar", nil, xpBar)
mainBar:SetAllPoints(restBar)
mainBar:SetFrameLevel(restBar:GetFrameLevel() + 2)
mainBar:SetStatusBarTexture(WHITE)
mainBar:SetStatusBarColor(C.xp[1], C.xp[2], C.xp[3], C.xp[4])
mainBar:SetMinMaxValues(0, 1)
mainBar:SetValue(0)

-- Drei Texte: links Stufe und Prozent, Mitte Erholt (+ EP-Tracker), rechts Quest-EP.
-- Schatten statt Kontur, damit die Schrift auf der Leiste ruhig und lesbar bleibt.
local function XPText(justify)
    local fs = mainBar:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontHighlightSmall)
    fs:SetTextColor(C.text[1], C.text[2], C.text[3])
    fs:SetJustifyH(justify)
    fs:SetWordWrap(false)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    return fs
end

local xpLeft = XPText("LEFT")
local xpMid = XPText("CENTER")
local xpRight = XPText("RIGHT")
xpLeft:SetPoint("LEFT", xpBar, "LEFT", 6, 0)
xpMid:SetPoint("CENTER", xpBar, "CENTER", 0, 0)
xpRight:SetPoint("RIGHT", xpBar, "RIGHT", -6, 0)

local function XPDim(key, lo, hi, default)
    local v = tonumber(ns.db and ns.db[key]) or default
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

local function XPWidth() return XPDim("xpBarWidth", 300, 1200, 560) end
local function XPHeight() return XPDim("xpBarHeight", 10, 40, 20) end
local function XPFontSize() return XPDim("xpBarFontSize", 8, 20, 13) end

-- Größe und Schrift auf ganze Pixel
local function LayoutXPBar()
    xpBar:SetSize(XPWidth(), XPHeight())
    local size = XPFontSize()
    for _, fs in ipairs({ xpLeft, xpMid, xpRight }) do
        pcall(fs.SetFont, fs, FONT_BODY, size, "")
    end
end

local function SetXPTexts(left, mid, right)
    xpLeft:SetText(left or "")
    xpMid:SetText(mid or "")
    xpRight:SetText(right or "")
end

-- Zeile des EP-Trackers (xptracker.lua), falls an und mit Daten
local function TrackerLine()
    if not (ns.XPTracker and ns.XPTracker.GetLine) then return nil end
    local ok, line = pcall(ns.XPTracker.GetLine)
    if ok and type(line) == "string" and line ~= "" then return line end
    return nil
end

ns.MakeMovable(xpBar, "xpbar", { "TOP", "TOP", 0, -6 })

local xpMode = "xp" -- "xp", "rep" oder "none"
local xpData = {}

local function AtMaxLevel()
    if IsXPUserDisabled then
        local ok, disabled = pcall(IsXPUserDisabled)
        if ok and ns.Public(disabled) then return true end
    end
    if IsPlayerAtEffectiveMaxLevel then
        local ok, atMax = pcall(IsPlayerAtEffectiveMaxLevel)
        if ok then
            atMax = ns.Public(atMax)
            if atMax ~= nil then return atMax and true or false end
        end
    end
    local level = Number(UnitLevel("player"))
    local maxLevel = Number((GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL)
    if level and maxLevel then return level >= maxLevel end
    return false
end

local function WatchedFaction()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local ok, d = pcall(C_Reputation.GetWatchedFactionData)
        d = ok and ns.Public(d)
        if type(d) == "table" then
            local name = String(d.name)
            local reaction = Number(d.reaction)
            local low, high = Number(d.currentReactionThreshold), Number(d.nextReactionThreshold)
            local value = Number(d.currentStanding)
            if name and low and high and value then return name, reaction, value - low, high - low end
        end
    end
    if GetWatchedFactionInfo then
        local ok, name, reaction, low, high, value = pcall(GetWatchedFactionInfo)
        if ok then
            name, reaction, low, high, value = String(name), Number(reaction), Number(low), Number(high), Number(value)
            if name and low and high and value then return name, reaction, value - low, high - low end
        end
    end
    return nil
end

-- Summe der EP aller abgeschlossenen, noch nicht abgegebenen Quests im Questlog
local function CompletedQuestXP()
    if not GetQuestLogRewardXP or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return 0 end
    local ok, entries = pcall(C_QuestLog.GetNumQuestLogEntries)
    entries = ok and Number(entries)
    if not entries then return 0 end
    local total = 0
    for i = 1, entries do
        local questID
        if C_QuestLog.GetQuestIDForLogIndex then
            local okID, id = pcall(C_QuestLog.GetQuestIDForLogIndex, i)
            questID = okID and Number(id)
        elseif C_QuestLog.GetInfo then
            local okInfo, info = pcall(C_QuestLog.GetInfo, i)
            info = okInfo and ns.Public(info)
            if type(info) == "table" and not ns.Public(info.isHeader) then questID = Number(info.questID) end
        end
        if questID and questID > 0 then
            local okDone, done = pcall(C_QuestLog.IsComplete, questID)
            if okDone and ns.Public(done) == true then
                local okXP, xp = pcall(GetQuestLogRewardXP, questID)
                xp = okXP and Number(xp)
                if xp and xp > 0 then total = total + xp end
            end
        end
    end
    return total
end

local function UpdateXP()
    if not UIOn("hudXPBar") then xpBar:Hide() return end
    if not AtMaxLevel() then
        local cur, max = Number(UnitXP("player")), Number(UnitXPMax("player"))
        local rested = GetXPExhaustion and Number(GetXPExhaustion()) or 0
        if cur and max and max > 0 then
            xpMode = "xp"
            local questXP = 0
            if ns.db.questXPBar then
                local ok, sum = pcall(CompletedQuestXP)
                questXP = ok and sum or 0
            end
            xpData = { cur = cur, max = max, rested = rested, quest = questXP, level = Number(UnitLevel("player")) }
            mainBar:SetStatusBarColor(C.xp[1], C.xp[2], C.xp[3], C.xp[4])
            mainBar:SetMinMaxValues(0, max)
            mainBar:SetValue(cur)
            restBar:SetMinMaxValues(0, max)
            restBar:SetValue(math.min(cur + rested, max))
            restBar:Show()
            if questXP > 0 then
                questBar:SetMinMaxValues(0, max)
                questBar:SetValue(math.min(cur + questXP, max))
                questBar:Show()
            else
                questBar:Hide()
            end
            local left = Pct(cur / max * 100) .. " %"
            if xpData.level then left = L("Stufe %d", xpData.level) .. " · " .. left end
            local mid = rested > 0 and L("Erholt %s %%", Pct(rested / max * 100)) or nil
            local line = TrackerLine()
            if line then mid = mid and (mid .. " · " .. line) or line end
            local right = questXP > 0 and L("Quests +%s EP", Num(questXP)) or nil
            SetXPTexts(left, mid, right)
            xpBar:Show()
            return
        end
    end
    questBar:Hide()
    local name, reaction, value, span = WatchedFaction()
    if name then
        xpMode = "rep"
        local label = reaction and _G["FACTION_STANDING_LABEL" .. reaction] or ""
        xpData = { name = name, label = label, value = value, span = span }
        local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if color then
            mainBar:SetStatusBarColor(color.r, color.g, color.b, 1)
        else
            mainBar:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end
        local full = (span <= 0)
        mainBar:SetMinMaxValues(0, full and 1 or span)
        mainBar:SetValue(full and 1 or value)
        restBar:Hide()
        local pct = full and "100,0" or Pct(value / span * 100)
        SetXPTexts(name .. " · " .. pct .. " %", label ~= "" and label or nil,
            (not full) and (Num(value) .. " / " .. Num(span)) or nil)
        xpBar:Show()
        return
    end
    xpMode = "none"
    if ns.IsConfigOpen() then
        -- Beispiel, damit man die Leiste sehen und verschieben kann
        mainBar:SetMinMaxValues(0, 1)
        mainBar:SetValue(0.5)
        restBar:Hide()
        SetXPTexts(L["Stufe ?"], L["Erfahrungsleiste (keine Fraktion beobachtet)"], nil)
        xpBar:Show()
    else
        xpBar:Hide()
    end
end

xpBar:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if xpMode == "xp" and xpData.max then
        GameTooltip:AddLine(xpData.level and L("Erfahrung – Stufe %d", xpData.level) or L["Erfahrung"])
        GameTooltip:AddDoubleLine(L["EP"], Num(xpData.cur) .. " / " .. Num(xpData.max), 1, 1, 1, 1, 1, 1)
        local missing = xpData.max - xpData.cur
        GameTooltip:AddDoubleLine(L["Fehlend"], Num(missing) .. " (" .. Pct(missing / xpData.max * 100) .. " %)", 1, 1, 1, 1, 1, 1)
        if xpData.rested > 0 then
            GameTooltip:AddDoubleLine(L["Erholt"], Num(xpData.rested) .. " (" .. Pct(xpData.rested / xpData.max * 100) .. " %)",
                1, 1, 1, C.accent[1], C.accent[2], C.accent[3])
        end
        if xpData.quest and xpData.quest > 0 then
            GameTooltip:AddDoubleLine(L["Quests"], L("+%s EP (%s %%)", Num(xpData.quest), Pct(xpData.quest / xpData.max * 100)),
                1, 1, 1, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
            if xpData.cur + xpData.quest >= xpData.max then
                GameTooltip:AddLine(L["Reicht für die nächste Stufe."], ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
            end
        end
    elseif xpMode == "rep" and xpData.name then
        GameTooltip:AddLine(xpData.name)
        if xpData.label ~= "" then GameTooltip:AddLine(xpData.label, 1, 1, 1) end
        if xpData.span > 0 then
            GameTooltip:AddDoubleLine(L["Ruf"], Num(xpData.value) .. " / " .. Num(xpData.span), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Fehlend"], Num(xpData.span - xpData.value), 1, 1, 1, 1, 1, 1)
        end
    else
        GameTooltip:AddLine(L["Erfahrungsleiste"])
        GameTooltip:AddLine(L["Auf Höchststufe zeigt sie den Ruf der beobachteten Fraktion."], 1, 1, 1, true)
    end
    -- EP-Tracker (xptracker.lua): EP/h, Zeit bis Levelaufstieg, Spielzeit …
    if xpMode ~= "rep" and ns.XPTracker and ns.XPTracker.AddTooltip then
        if TrackerLine() then GameTooltip:AddLine(" ") end
        pcall(ns.XPTracker.AddTooltip, GameTooltip)
    end
    GameTooltip:AddLine(" ")
    GoldLine(L["Shift + Ziehen: verschieben"])
    GameTooltip:Show()
end)
xpBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Breite und Höhe auch im Bearbeitungsmodus (opts wird von älteren Ständen ignoriert)
ns.RegisterMovable(xpBar, "Erfahrungsleiste", function() pcall(UpdateXP) end,
    { widthKey = "xpBarWidth", heightKey = "xpBarHeight" })

-- Blizzards EP- und Rufleisten: nur verstecken, keine Edit-Mode-Systeme umhängen
local BLIZZARD_XP = {
    "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar", "ExhaustionTick",
    "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
}

local hookedXP = {} -- Blizzard-Rahmen, an denen schon ein OnShow-Hook hängt (keine Felder auf Blizzard-Frames)

local function HideBlizzardXP()
    if not UIOn("hudXPBar") then return end
    for _, name in ipairs(BLIZZARD_XP) do
        local f = _G[name]
        if type(f) == "table" and f.Hide then
            if InCombat() and IsProtectedFrame(f) then
                Defer("blizzardXP", HideBlizzardXP)
            else
                pcall(f.Hide, f)
                if not hookedXP[f] and f.HookScript then
                    hookedXP[f] = true
                    pcall(f.HookScript, f, "OnShow", function(self)
                        if not (UIOn("hudXPBar")) then return end
                        if InCombat() and IsProtectedFrame(self) then
                            Defer("blizzardXP", HideBlizzardXP)
                        else
                            pcall(self.Hide, self)
                        end
                    end)
                end
            end
        end
    end
end

local function ApplyXP(toggled)
    if UIOn("hudXPBar") then
        LayoutXPBar()
        ns.RestorePosition(xpBar)
        UpdateXP()
        HideBlizzardXP()
    else
        xpBar:Hide()
        if toggled then ns.Print(L["Blizzards Erfahrungsleiste kommt nach /reload zurück."]) end
    end
end

local xpTimer = false
local function ScheduleXP()
    if xpTimer or not (UIOn("hudXPBar")) then return end
    xpTimer = true
    C_Timer.After(0.1, function()
        xpTimer = false
        pcall(UpdateXP)
    end)
end

for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION",
    "PLAYER_UPDATE_RESTING", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }) do
    SafeOn(event, ScheduleXP)
end

-- QUEST_LOG_UPDATE kommt oft in Schüben: Quest-EP höchstens alle 0,5 s neu zählen
local questXPTimer = false
SafeOn("QUEST_LOG_UPDATE", function()
    if questXPTimer or not (UIOn("hudXPBar") and ns.db.questXPBar) then return end
    questXPTimer = true
    C_Timer.After(0.5, function()
        questXPTimer = false
        pcall(UpdateXP)
    end)
end)

---------------------------------------------------------------------------
-- 4) Taschen- und Menüleiste unten rechts
-- Unterschalter „Taschenleiste unten rechts“ der stray-Oberfläche (ns.db.bottomBar). Eigene Knöpfe;
-- Blizzards Taschenknöpfe werden außerhalb des Kampfes in einen versteckten
-- eigenen Rahmen umgehängt, die Menüleiste nur ausgeblendet (Mikroknöpfe nie umhängen, keine
-- Edit-Mode-Systeme umsetzen, keine Felder auf Blizzard-Frames).
-- Die Menüknöpfe sind sichere Klick-Knöpfe auf Blizzards Mikroknöpfe. Sobald es sie gibt, ist
-- die Leiste selbst geschützt: Aufbau, Größe, Position und Ein-/Ausblenden nur außerhalb des Kampfes.
---------------------------------------------------------------------------

local BLIZZARD_BAGS = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton", "BagBarExpandToggle", "BagSlotCluster",
}
-- Forever (Camelot) plus ältere Namen; was es im Client nicht gibt, wird übersprungen
local MICRO_FALLBACK = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton", "SpellbookMicroButton",
    "TalentMicroButton", "AchievementMicroButton", "LegacyMicroButton", "QuestLogMicroButton",
    "HousingMicroButton", "SocialsMicroButton", "GuildMicroButton", "LFDMicroButton", "LFGMicroButton",
    "WorldMapMicroButton", "PVPMicroButton", "CollectionsMicroButton", "EJMicroButton",
    "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}

local BAR_PAD = 4
local BAR_GAP = 3
local GROUP_GAP = 10

local function BottomActive()
    return UIOn("bottomBar")
end

local function BarButtonSize()
    local v = tonumber(ns.db and ns.db.bottomBarSize) or 28
    return math.max(20, math.min(40, math.floor(v + 0.5)))
end

local function MicroNames()
    local list, seen = {}, {}
    if type(MICRO_BUTTONS) == "table" then
        for _, entry in ipairs(MICRO_BUTTONS) do
            local name = entry
            if type(entry) == "table" and entry.GetName then name = entry:GetName() end
            if type(name) == "string" and not seen[name] then
                seen[name] = true
                table.insert(list, name)
            end
        end
    end
    for _, name in ipairs(MICRO_FALLBACK) do
        if not seen[name] then
            seen[name] = true
            table.insert(list, name)
        end
    end
    return list
end

-- Alte Einstellung „hudMicroBar“ (bis 0.20) einmalig übernehmen
local function MigrateOldMicroBar()
    if not ns.db then return end
    if ns.db.hudMicroBar ~= nil then
        if ns.db.hudMicroBar then ns.db.bottomMicroButtons = true end
        ns.db.hudMicroBar = nil
    end
end

-- Blizzard-Knöpfe parken ------------------------------------------------------

local parking = CreateFrame("Frame", "strayBlizzardBarParking", UIParent)
parking:Hide()

-- [Blizzard-Knopf] = { parent = alter Parent, points = alte Punkte } (lokal, keine Felder auf Blizzard-Frames)
local parked = {}
local bagsBarFaded = false

-- Menüknöpfe NICHT umhängen: Jedes SetParent löst Blizzards MicroMenu:Layout aus, und das wirft
-- (GetEdgeButton vergleicht nil-Positionen). Stattdessen den ganzen Container ausblenden;
-- die sicheren stray-Knöpfe klicken die (versteckten) Blizzard-Knöpfe weiter an.
local microHidden = false
local microShowHooked = {}

local function MicroContainers()
    local list = {}
    for _, name in ipairs({ "MicroMenuContainer", "MicroMenu" }) do
        local f = _G[name]
        if type(f) == "table" and f.Hide and not IsProtectedFrame(f) then table.insert(list, f) end
    end
    return list
end

local function HideMicroMenu()
    microHidden = true
    for _, f in ipairs(MicroContainers()) do
        if not microShowHooked[f] then
            microShowHooked[f] = true
            pcall(f.HookScript, f, "OnShow", function(self)
                if microHidden and not InCombat() then self:Hide() end
            end)
        end
        pcall(f.Hide, f)
    end
end

local function ShowMicroMenu()
    microHidden = false
    for _, f in ipairs(MicroContainers()) do pcall(f.Show, f) end
end

local function ParkBlizzard()
    if not BottomActive() then return end
    if InCombat() then
        Defer("bottomPark", ParkBlizzard)
        return
    end
    local function park(name)
        local b = _G[name]
        if type(b) ~= "table" or not b.SetParent or not b.GetParent then return end
        if b:GetParent() == parking or IsProtectedFrame(b) then return end
        if not parked[b] then
            local info = { parent = b:GetParent(), points = {} }
            for i = 1, (b:GetNumPoints() or 0) do info.points[i] = { b:GetPoint(i) } end
            parked[b] = info
        end
        pcall(b.SetParent, b, parking)
    end
    for _, name in ipairs(BLIZZARD_BAGS) do park(name) end
    HideMicroMenu()
    -- Trennstriche der Taschenleiste sind Kinder von BagsBar und hängen an den Taschenknöpfen
    local bagsBar = _G.BagsBar
    if type(bagsBar) == "table" and bagsBar.SetAlpha then
        pcall(bagsBar.SetAlpha, bagsBar, 0)
        bagsBarFaded = true
    end
end

-- „Eigene Aktionsleisten“ aus: Blizzards Taschen- und Menüknöpfe zurückhängen.
-- Die Punkte bleiben beim Parken unverändert (Blizzard setzt sie beim Layout ggf. neu);
-- die gemerkten Punkte gelten nur, wenn ein Knopf gar keinen Punkt mehr hat.
local function UnparkBlizzard()
    if InCombat() then
        Defer("bottomUnpark", UnparkBlizzard)
        return
    end
    pending.bottomPark = nil
    ShowMicroMenu()
    for b, info in pairs(parked) do
        pcall(function()
            if b:GetParent() == parking then b:SetParent(info.parent or UIParent) end
            if (b:GetNumPoints() or 0) == 0 then
                for _, p in ipairs(info.points) do b:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            end
        end)
        parked[b] = nil
    end
    local bagsBar = _G.BagsBar
    if bagsBarFaded and type(bagsBar) == "table" and bagsBar.SetAlpha then
        pcall(bagsBar.SetAlpha, bagsBar, 1)
    end
    bagsBarFaded = false
    -- Leistenkunst von MicroMenu/BagsBar blendet actionbars.lua aus und wieder ein
    if ns.ShowBlizzardBarArt then pcall(ns.ShowBlizzardBarArt) end
end

local parkScheduled = false
local function SchedulePark()
    if parkScheduled or not BottomActive() then return end
    parkScheduled = true
    C_Timer.After(0, function()
        parkScheduled = false
        pcall(ParkBlizzard)
    end)
end

-- Blizzard setzt die Knöpfe bei Fahrzeug, Haustierkampf oder Edit Mode neu – zurückholen
local microHooksDone = false
local function HookBlizzardMicro()
    if microHooksDone then return end
    microHooksDone = true
    for _, fname in ipairs({ "UpdateMicroButtonsParent", "MoveMicroButtons", "MainMenuBarVehicleLeaveButton_Update" }) do
        if type(_G[fname]) == "function" then
            pcall(hooksecurefunc, fname, function() SchedulePark() end)
        end
    end
    for _, holder in ipairs({ "MicroMenu", "MicroMenuContainer", "BagsBar", "MicroButtonAndBagsBar" }) do
        local f = _G[holder]
        if type(f) == "table" and type(f.Layout) == "function" then
            pcall(hooksecurefunc, f, "Layout", function() SchedulePark() end)
        end
    end
end

-- Eigene Leiste ------------------------------------------------------------------
-- Entwurf 3: Blizzards Menüsymbole als freie Bildzeichen ohne Knopfrahmen auf einem leicht
-- dunklen, halbdurchsichtigen Streifen; Charakter als rundes Live-Porträt; Rucksack und Taschen
-- zusammen als ein Taschenknopf mit Füllbalken. Kein Schlüsselbund.

local ICON_DIM = 0.82  -- Grundhelligkeit der Bildzeichen, beim Überfahren voll hell
local FILL_H = 3       -- Höhe des Füllbalkens unter dem Taschenknopf

local bottomBar = CreateFrame("Frame", "strayMicroBar", UIParent)
bottomBar:SetSize(200, 34)
bottomBar:SetFrameStrata("MEDIUM")
do
    local strip = bottomBar:CreateTexture(nil, "BACKGROUND")
    strip:SetAllPoints()
    strip:SetColorTexture(0, 0, 0, 0.45)
end
bottomBar:Hide()

-- Schlüssel „microbar“ wie bisher: eine schon verschobene Leiste bleibt, wo sie war
ns.MakeMovable(bottomBar, "microbar", { "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 4 })
ns.RegisterMovable(bottomBar, "Taschen und Menü", nil)
-- Mit sicheren Kindern ist die Leiste geschützt: im Kampf nicht ziehen
bottomBar:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombat() then self:StartMoving() end
end)

-- Seitenverhältnis eines Atlas (Breite/Höhe), nil wenn der Client ihn nicht kennt
local function AtlasAspect(atlas)
    if type(atlas) ~= "string" or not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    info = ok and ns.Public(info)
    if type(info) ~= "table" then return nil end
    local w, h = Number(info.width), Number(info.height)
    if w and h and w > 0 and h > 0 then return w / h end
    return 1
end

-- Bildzeichen von Blizzards Mikroknopf lesen (nur lesen, nichts am Blizzard-Knopf ändern)
local function MicroAtlas(entry)
    local target = MicroFor(entry)
    if not target or type(target.GetNormalTexture) ~= "function" then return nil end
    local ok, tex = pcall(target.GetNormalTexture, target)
    if not ok or type(tex) ~= "table" or type(tex.GetAtlas) ~= "function" then return nil end
    local okA, atlas = pcall(tex.GetAtlas, tex)
    atlas = okA and ns.Public(atlas)
    if type(atlas) == "string" and atlas ~= "" then return atlas end
    return nil
end

-- secureTarget: Blizzards Mikroknopf → sicherer Klick-Knopf, sonst normaler Knopf.
-- Nur Bildzeichen, kein Rahmen; HIGHLIGHT-Kopie hellt beim Überfahren auf.
local function MakeBarButton(secureTarget, name)
    local b
    if secureTarget then
        b = MakeSecureClick(name, bottomBar, secureTarget)
    else
        b = CreateFrame("Button", name, bottomBar)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    if not b then return nil end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetVertexColor(ICON_DIM, ICON_DIM, ICON_DIM)
    b.glow = b:CreateTexture(nil, "HIGHLIGHT")
    b.glow:SetAllPoints(b.icon)
    b.glow:SetBlendMode("ADD")
    b.glow:SetAlpha(0.3)
    b.aspect = 1
    b:HookScript("OnEnter", function(self)
        if not self.off then self.icon:SetVertexColor(1, 1, 1) end
    end)
    b:HookScript("OnLeave", function(self)
        local v = self.off and 1 or ICON_DIM
        self.icon:SetVertexColor(v, v, v)
        GameTooltip:Hide()
    end)
    b:Hide()
    return b
end

-- Atlas (Blizzards Menüsymbol) bevorzugt, sonst Symbol-Datei mit beschnittenem Rand
local function SetGlyph(b, atlas, files)
    local aspect = AtlasAspect(atlas)
    if aspect and pcall(b.icon.SetAtlas, b.icon, atlas, false) then
        pcall(b.glow.SetAtlas, b.glow, atlas, false)
        b.aspect = aspect
        return true
    end
    b.aspect = 1
    if files and SetFirstTexture(b.icon, files) then
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SetFirstTexture(b.glow, files)
        b.glow:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return true
    end
    b.icon:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    return false
end

-- Menüknöpfe (dieselben Einträge wie das Minimap-Menü), erst bei Bedarf außerhalb des Kampfes gebaut
local microButtons = {}
local microBuilt = false
local portraitButton = nil -- Charakter-Knopf mit Live-Porträt

-- Rundes Porträt des eingeloggten Charakters (SetPortraitTexture maskiert selbst rund)
local function UpdatePortrait()
    if not portraitButton or not SetPortraitTexture then return end
    pcall(SetPortraitTexture, portraitButton.icon, "player")
    pcall(SetPortraitTexture, portraitButton.glow, "player")
end

local function BuildMicroButtons()
    if microBuilt then return true end
    if InCombat() then return false end
    microBuilt = true
    for _, entry in ipairs(MENU_ENTRIES) do
        if entry.micro and Has(entry) then
            local target = entry.secure and MicroFor(entry) or nil
            local ok, b = pcall(MakeBarButton, target, "strayBottomMenu_" .. entry.key)
            if ok and b then
                b.entry = entry
                if entry.key == "char" and SetPortraitTexture then
                    portraitButton = b
                    b.aspect = 1
                    UpdatePortrait()
                else
                    SetGlyph(b, MicroAtlas(entry), entry.icons)
                end
                if not entry.secure then
                    b:SetScript("OnClick", function(self) RunEntry(self.entry, self) end)
                end
                b:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(L[self.entry.label])
                    if self.entry.secure then
                        if not MicroUsable(self.entry) then
                            GameTooltip:AddLine(L["Gerade nicht verfügbar"], C.textDim[1], C.textDim[2], C.textDim[3])
                        end
                    elseif BlockedNow(self.entry) then
                        GameTooltip:AddLine(L["Im Kampf gesperrt"], 1, 0.3, 0.3)
                    end
                    GameTooltip:Show()
                end)
                table.insert(microButtons, b)
            end
        end
    end
    return true
end

-- Nur Texturen: geht auch im Kampf
local function UpdateMicroState()
    for _, b in ipairs(microButtons) do
        local off
        if b.entry.secure then
            off = not MicroUsable(b.entry)
        else
            off = BlockedNow(b.entry)
        end
        b.off = off and true or false
        pcall(b.icon.SetDesaturated, b.icon, b.off)
        b.icon:SetAlpha(b.off and 0.45 or 1)
        local v = b.off and 1 or ICON_DIM
        b.icon:SetVertexColor(v, v, v)
    end
end

-- Taschen
local function ContainerCall(name, ...)
    local fn = (C_Container and C_Container[name]) or _G[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and Number(v) or nil
end

local function BagName(bag)
    if C_Container and C_Container.GetBagName then
        local ok, name = pcall(C_Container.GetBagName, bag)
        name = ok and String(name)
        if name then return name end
    end
    if bag == 0 then return L["Rucksack"] end
    return L("Tasche %d", bag)
end

-- Freie und gesamte Plätze über Rucksack und Taschen 1–4
local function BagTotals()
    local free, total = 0, 0
    for bag = 0, 4 do
        local slots = ContainerCall("GetContainerNumSlots", bag) or 0
        if slots > 0 then
            total = total + slots
            free = free + (ContainerCall("GetContainerNumFreeSlots", bag) or 0)
        end
    end
    return free, total
end

local bagButton = MakeBarButton(nil, "strayBagButton")
bagButton.icon:ClearAllPoints()
bagButton.icon:SetPoint("TOP", bagButton, "TOP", 0, 0)
SetGlyph(bagButton, nil, { "Interface\\Buttons\\Button-Backpack-Up", "Interface\\Icons\\INV_Misc_Bag_08" })

bagButton.fill = CreateFrame("StatusBar", nil, bagButton)
bagButton.fill:SetPoint("BOTTOM", bagButton, "BOTTOM", 0, 0)
bagButton.fill:SetSize(20, FILL_H)
bagButton.fill:SetStatusBarTexture(WHITE)
bagButton.fill:SetMinMaxValues(0, 1)
bagButton.fill:SetValue(0)
do
    local bg = bagButton.fill:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
end

local function PutIntoBackpack()
    if not (CursorHasItem and CursorHasItem()) then return false end
    if PutItemInBackpack then pcall(PutItemInBackpack) end
    return true
end

bagButton:SetScript("OnClick", function()
    if PutIntoBackpack() then return end
    -- Öffnet Blizzards Taschen bzw. das stray-Taschenfenster (bagwindow.lua hängt sich daran)
    if ToggleAllBags then
        pcall(ToggleAllBags)
    elseif ToggleBackpack then
        pcall(ToggleBackpack)
    end
end)
bagButton:SetScript("OnReceiveDrag", function() PutIntoBackpack() end)

bagButton:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine(L["Taschen"])
    for bag = 0, 4 do
        local slots = ContainerCall("GetContainerNumSlots", bag) or 0
        if slots > 0 then
            local free = ContainerCall("GetContainerNumFreeSlots", bag) or 0
            GameTooltip:AddDoubleLine(BagName(bag), L("%d frei von %d", free, slots),
                1, 1, 1, C.text[1], C.text[2], C.text[3])
        end
    end
    local free, total = BagTotals()
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L["Frei gesamt"], L("%d von %d", free, total), 1, 1, 1, C.accent[1], C.accent[2], C.accent[3])
    GoldLine(L["Linksklick: Taschen öffnen"])
    GameTooltip:Show()
end)

-- Füllbalken: grün, ab drei Vierteln gelb, ab 90 % rot
local function UpdateBags()
    local free, total = BagTotals()
    local fill = bagButton.fill
    if total > 0 then
        local used = math.max(0, total - free)
        fill:SetMinMaxValues(0, total)
        fill:SetValue(used)
        local share = used / total
        if share >= 0.9 then
            fill:SetStatusBarColor(0.95, 0.25, 0.2, 1)
        elseif share >= 0.75 then
            fill:SetStatusBarColor(1, 0.82, 0, 1)
        else
            fill:SetStatusBarColor(0.3, 0.8, 0.35, 1)
        end
    else
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(0)
    end
end

local function LayoutBottom()
    if not BottomActive() then return end
    -- Sichere Knöpfe bauen bzw. die geschützte Leiste umbauen: nur außerhalb des Kampfes
    if InCombat() and (microBuilt or ns.db.bottomMicroButtons) then
        Defer("bottomLayout", LayoutBottom)
        return
    end
    if ns.db.bottomMicroButtons then BuildMicroButtons() end
    local size = BarButtonSize()
    local x = BAR_PAD
    local function place(b, w)
        b:SetSize(w, size)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", bottomBar, "BOTTOMLEFT", x, BAR_PAD)
        b:Show()
        x = x + w + BAR_GAP
    end
    local anyMicro = false
    for _, b in ipairs(microButtons) do
        if ns.db.bottomMicroButtons and Has(b.entry) then
            local w
            if b == portraitButton then
                w = size
                b.icon:SetSize(size - 2, size - 2)
            else
                -- Blizzard kann das Symbol tauschen (z. B. Gilde): bei jedem Aufbau neu lesen
                SetGlyph(b, MicroAtlas(b.entry), b.entry.icons)
                w = math.max(8, math.floor(size * (b.aspect or 1) + 0.5))
                b.icon:SetSize(w, size)
            end
            place(b, w)
            anyMicro = true
        else
            b:Hide()
        end
    end
    if anyMicro then x = x + GROUP_GAP - BAR_GAP end
    bagButton.icon:SetSize(size - FILL_H - 2, size - FILL_H - 2)
    bagButton.fill:SetSize(math.max(8, size - 6), FILL_H)
    place(bagButton, size)
    bottomBar:SetSize(x - BAR_GAP + BAR_PAD, size + 2 * BAR_PAD)
    UpdateMicroState()
    UpdatePortrait()
end

local bagTimer = false
local function ScheduleBags()
    if bagTimer or not BottomActive() then return end
    bagTimer = true
    C_Timer.After(0.2, function()
        bagTimer = false
        pcall(UpdateBags)
    end)
end

for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }) do
    SafeOn(event, ScheduleBags)
end
SafeOn("PLAYER_REGEN_DISABLED", function() if BottomActive() then pcall(UpdateMicroState) end end)
SafeOn("PLAYER_REGEN_ENABLED", function() if BottomActive() then pcall(UpdateMicroState) end end)
-- Blizzard schaltet Mikroknöpfe an/aus (Stufe, Gilde …): Graustufe nachziehen
if type(UpdateMicroButtons) == "function" then
    pcall(hooksecurefunc, "UpdateMicroButtons", function()
        if BottomActive() and #microButtons > 0 then pcall(UpdateMicroState) end
    end)
end

-- Live-Porträt: bei Ausrüstungs- oder Modellwechsel neu zeichnen (gedrosselt)
local portraitTimer = false
local function SchedulePortrait(unit)
    if ns.IsSecret(unit) then return end
    if unit ~= nil and unit ~= "player" then return end
    if portraitTimer or not portraitButton or not BottomActive() then return end
    portraitTimer = true
    C_Timer.After(0.3, function()
        portraitTimer = false
        pcall(UpdatePortrait)
    end)
end

for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PORTRAITS_UPDATED" }) do
    SafeOn(event, function(unit)
        if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PORTRAITS_UPDATED" then unit = nil end
        SchedulePortrait(unit)
    end)
end

-- Beim Umschalten von „Taschenleiste unten rechts“ bzw. der Hauptoption und nach dem Login
function ns.HudUpdateBottomBar()
    if not ns.db then return end
    MigrateOldMicroBar()
    -- Mit sicheren Menüknöpfen ist die Leiste geschützt
    if InCombat() and microBuilt then
        Defer("bottomUpdate", ns.HudUpdateBottomBar)
        return
    end
    if BottomActive() then
        pending.bottomUnpark = nil
        ns.RestorePosition(bottomBar)
        LayoutBottom()
        UpdateBags()
        bottomBar:Show()
        HookBlizzardMicro()
        ParkBlizzard()
    else
        bottomBar:Hide()
        -- Blizzards Taschen- und Menüknöpfe zurück (im Kampf danach)
        UnparkBlizzard()
    end
end

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

-- Hauptoption „stray-Oberfläche“ und Unterschalter ------------------------------------
-- Alle Schalter der stray-Oberfläche stehen hier (auch die Teile aus minimap.lua und
-- actionbars.lua), damit die Reihenfolge stimmt: Hauptschalter ganz oben, darunter je Teil.

local function Report(ok, err)
    if not ok and err then geterrorhandler()(err) end
end

-- Was beim Wirksam-Werden bzw. Abschalten eines Teils passieren muss
local PART_APPLY = {
    abEnabled = function() if ns.ActionBarsToggled then ns.ActionBarsToggled() end end,
    bottomBar = function() ns.HudUpdateBottomBar() end,
    squareMinimap = function() if ns.ApplySquareMinimap then ns.ApplySquareMinimap() end end,
    minimapMiddleMenu = function() UpdateMiddleClick() end,
    hudMinimapColumn = function() ApplyColumn(true) end,
    hudClock = function() ApplyClock(true) end,
    hudXPBar = function() ApplyXP(true) end,
}

-- Zuletzt angewandte Wirkung je Teil. Nicht aus ns.db ablesen: „Verwerfen“ (ui.lua) und Profile
-- schreiben ns.db zurück, bevor sie set() aufrufen – ein Vorher/Nachher-Vergleich sähe dann nichts.
local appliedUI = {}

local function RememberUIState()
    for _, k in ipairs(UI_PARTS) do appliedUI[k] = UIOn(k) end
end

-- Wert setzen und nur die Teile neu anwenden, deren Wirkung sich gegenüber dem Angewandten ändert
local function SetUIValue(key, value)
    ns.db[key] = value and true or false
    for _, k in ipairs(UI_PARTS) do
        local now = UIOn(k)
        if now ~= (appliedUI[k] or false) then
            appliedUI[k] = now
            Report(pcall(PART_APPLY[k]))
        end
    end
end

local function MainOn()
    return ns.db and ns.db.strayUI and true or false
end

local MAIN_HINT = L["Erst „stray-Oberfläche“ einschalten (oben in diesem Bereich)."]

ns.AddOption(3, SECTION, {
    key = "strayUI",
    label = L["stray-Oberfläche"],
    keywords = { "oberfläche", "ui", "interface", "hud", "leisten", "bars", "minimap", "layout" },
    tooltip = L["Ein Schalter für die ganze stray-Oberfläche: eigene Aktionsleisten, Taschenleiste unten rechts, eckige Minimap, Menü per Mittelklick, Minimap-Knopfspalte, Uhrzeit und FPS sowie die Erfahrungsleiste oben.\n\n"
        .. "Beim ersten Einschalten kommen alle Teile mit. Mit den Schaltern darunter schaltest du einzelne Teile wieder ab. "
        .. "Aus heißt: alles wie bei Blizzard (Blizzards Aktionsleisten erst nach dem Neuladen)."],
    set = function(value)
        -- Nichts gewählt? Dann bringt der Hauptschalter alle Teile mit (Menüknöpfe unten bleiben aus)
        if value and ns.db then
            local any = false
            for _, k in ipairs(UI_PARTS) do
                if ns.db[k] then any = true break end
            end
            if not any then
                for _, k in ipairs(UI_PARTS) do ns.db[k] = true end
            end
        end
        SetUIValue("strayUI", value)
    end,
})

ns.AddOption(3, SECTION, {
    key = "abEnabled",
    label = L["Eigene Aktionsleisten"],
    keywords = { "aktionsleisten", "actionbars", "bars", "leisten", "knöpfe", "buttons" },
    tooltip = L["Ersetzt Blizzards Aktionsleisten durch bis zu 5 schlichte stray-Leisten à 12 Knöpfe. Deine Belegung und deine Tasten bleiben: Leiste 1 ist die Hauptleiste (mit Seitenwechsel bei Haltung, Gestalt, Verstohlenheit und Umschalt+Mausrad), Leiste 2 die untere linke, Leiste 3 die untere rechte, Leiste 4 die rechte und Leiste 5 die Leiste „Rechts 2“. Haltungs- und Begleiterleiste bleiben von Blizzard.\n\n"
        .. "Die einzelnen Leisten stellst du auf der Seite Aktionsleisten ein (anzeigen, Knopfgröße, Knöpfe pro Reihe). Standard: Leisten 1–4 an, 5 aus.\n\n"
        .. "Verschieben über den Bearbeitungsmodus; dort und bei offenem stray-Fenster siehst du auch die leeren Plätze. Änderungen wirken nur außerhalb des Kampfes.\n\n"
        .. "Mit Blizzards Hauptleiste verschwindet auch die Blizzard-EP-Leiste: Schalte dafür „Erfahrungsleiste oben“ ein (weiter unten).\n\n"
        .. "Ausschalten erfordert Neuladen für Blizzards Aktionsleisten."],
    isEnabled = MainOn,
    disabledHint = MAIN_HINT,
    set = function(value) SetUIValue("abEnabled", value) end,
})

ns.AddOption(3, SECTION, {
    key = "bottomBar",
    label = L["Taschenleiste unten rechts"],
    keywords = { "taschen", "bags", "inventar", "inventory", "rucksack", "backpack", "menü", "micro" },
    tooltip = L["Schlanke Leiste unten rechts statt Blizzards Taschenleiste: ein Taschenknopf für Rucksack und alle Taschen. "
        .. "Der Balken darunter zeigt, wie voll die Taschen sind (grün, ab drei Vierteln gelb, ab 90 % rot); der Tooltip listet jede Tasche mit freien Plätzen. "
        .. "Linksklick öffnet die Taschen bzw. das stray-Taschenfenster. Den Schlüsselbund zeigt stray nicht.\n\n"
        .. "Shift + Ziehen verschiebt die Leiste (nicht im Kampf), ebenso der Bearbeitungsmodus."],
    isEnabled = MainOn,
    disabledHint = MAIN_HINT,
    set = function(value) SetUIValue("bottomBar", value) end,
})

local BOTTOM_HINT = L["Erst „Taschenleiste unten rechts“ einschalten (direkt darüber)."]
local function BottomOptionOn() return BottomActive() end

ns.AddOption(3, SECTION, {
    key = "bottomMicroButtons",
    label = L["Menüknöpfe unten"],
    keywords = { "menü", "menu", "micro", "mikromenü", "charakter", "zauberbuch", "talente", "sammlung", "collections",
        "abenteuerführer", "adventure guide", "reittiere", "mounts", "haustiere", "pets" },
    tooltip = L["Setzt links neben den Taschenknopf Blizzards Menüsymbole ohne Rahmen: Charakter (rundes Bild deines Charakters), Zauberbuch, Talente, Berufe, Questlog, Gilde, Gruppensuche, Sammlung (Reittiere und Haustiere) und Abenteuerführer – jeweils nur, wenn es das Fenster auf Forever gibt. Freunde findest du an der Minimap-Knopfspalte und im Minimap-Menü.\n\n"
        .. "Sie klicken Blizzards eigene Menüknöpfe an und gehen deshalb auch im Kampf. Grau heißt: Blizzard hat den Knopf gerade abgeschaltet (z. B. Talente unter Stufe 10). "
        .. "Das Spielmenü öffnest du wie gewohnt mit Esc. Ein- und Umbau im Kampf geschieht erst danach."],
    isEnabled = BottomOptionOn,
    disabledHint = BOTTOM_HINT,
    set = function(value)
        ns.db.bottomMicroButtons = value
        if BottomActive() then pcall(LayoutBottom) end
    end,
})

ns.AddOption(3, SECTION, {
    key = "bottomBarSize",
    type = "slider",
    label = L["Größe Taschenleiste"],
    min = 20, max = 40, step = 1,
    tooltip = L["Höhe der Symbole in der Taschen- und Menüleiste in Pixeln."],
    isEnabled = BottomOptionOn,
    disabledHint = BOTTOM_HINT,
    set = function(v)
        ns.db.bottomBarSize = math.max(20, math.min(40, math.floor((tonumber(v) or 28) + 0.5)))
        if BottomActive() then pcall(LayoutBottom) end
    end,
})

ns.AddOption(3, SECTION, {
    key = "squareMinimap",
    label = L["Eckige Minimap oben rechts"],
    keywords = { "minimap", "karte", "map", "eckig", "square" },
    tooltip = L["Macht die Minimap viereckig mit schmalem stray-Rand und setzt sie bündig in die obere rechte Bildschirmecke. Darüber steht der Gebietsname (Klick: Weltkarte), links im Kopf ein Briefsymbol bei neuer Post, darunter die Koordinaten, wenn Blizzards Einstellung „Spielerkoordinaten“ an ist.\n\n"
        .. "Blizzards runder Rahmen, Zoomknöpfe, Zonenleiste, Verfolgungs- und Kalenderknopf werden ausgeblendet. Verfolgung und Kalender erreichst du über den kleinen Kartenmenü-Knopf oben links in der Karte oder, falls eingeschaltet, per Mittelklick auf die Karte.\n\n"
        .. "Blizzards Bearbeitungsmodus kann die Minimap dann nicht mehr anwählen; die Größe stellst du mit dem Regler darunter ein.\n\n"
        .. "Ausschalten stellt die runde Karte wieder her. Sitzt danach etwas schief, hilft /reload. Im Kampf wird erst danach umgebaut."],
    isEnabled = MainOn,
    disabledHint = MAIN_HINT,
    set = function(value) SetUIValue("squareMinimap", value) end,
})

ns.AddOption(3, SECTION, {
    key = "squareMinimapSize",
    type = "slider",
    label = L["Größe eckige Minimap"],
    min = 140, max = 260, step = 10,
    tooltip = L["Kantenlänge der eckigen Minimap in Pixeln. Im Kampf wird die Änderung erst danach übernommen."],
    isEnabled = function() return UIOn("squareMinimap") end,
    disabledHint = L["Erst „Eckige Minimap oben rechts“ einschalten (direkt darüber)."],
    set = function(v)
        ns.db.squareMinimapSize = math.max(140, math.min(260, math.floor((tonumber(v) or 200) + 0.5)))
        if UIOn("squareMinimap") and ns.ApplySquareMinimap then pcall(ns.ApplySquareMinimap) end
    end,
})

ns.AddOption(3, SECTION, {
    key = "minimapMiddleMenu",
    label = L["Menü per Mittelklick auf die Minimap"],
    keywords = { "minimap", "menü", "menu", "mittelklick", "middle click", "maustaste" },
    tooltip = L["Mittlere Maustaste auf der Minimap öffnet an der Maus ein kleines stray-Menü mit allen Blizzard-Fenstern, die es auf Forever gibt: Charakter, Zauberbuch, Talente, Berufe, Vermächtnis, Questlog, Wohnen, Freunde, Gilde, Gruppensuche, Sammlung und Abenteuerführer sowie Kalender, Verfolgung, Weltkarte und, falls eingeschaltet, Twinks. Was Blizzard gerade sperrt, fehlt; grau heißt: im Moment abgeschaltet. "
        .. "Dasselbe Menü öffnet der Kartenmenü-Knopf oben links in der Karte.\n\n"
        .. "Der Mittelklick pingt nicht: stray fängt nur die mittlere Taste ab, Links- und Rechtsklick sowie Mausrad gehen wie gewohnt an die Karte. "
        .. "Im Kampf geht das Menü nicht auf, dann kommt ein Hinweis im Chat. Schließen per Klick daneben, zweitem Mittelklick oder Esc."],
    isEnabled = MainOn,
    disabledHint = MAIN_HINT,
    set = function(value) SetUIValue("minimapMiddleMenu", value) end,
})

ns.AddOption(3, SECTION, {
    key = "hudMinimapColumn",
    label = L["Minimap-Knopfspalte"],
    keywords = { "minimap", "freunde", "friends", "addon-knöpfe", "buttons" },
    tooltip = L["Senkrechte Knopfspalte neben der Minimap mit Freunden, stray-Knopf und Addon-Tasche.\n\n"
        .. "Freunde: Zahl der Freunde online, Liste im Tooltip, Linksklick öffnet die Freundesliste.\n"
        .. "Addon-Tasche: sammelt die Minimap-Knöpfe anderer Addons und klappt sie per Klick auf "
        .. "(verträgt sich nicht mit Leatrix „Hide addon buttons“).\n"
        .. "Oben links in der Minimap sitzt ein kleines Kartenmenü (dasselbe Menü wie per Mittelklick: alle Blizzard-Fenster, Kalender, Verfolgung, Weltkarte). Bei der eckigen Minimap ist es immer da, auch ohne diese Spalte.\n\n"
        .. "Die Spalte steht rechts neben der Minimap, am rechten Bildschirmrand links davon. "
        .. "Bei der eckigen Minimap sitzt sie links bündig daran."],
    isEnabled = MainOn,
    disabledHint = MAIN_HINT,
    set = function(value) SetUIValue("hudMinimapColumn", value) end,
})

ns.AddOption(3, SECTION, {
    key = "hudClock",
    label = L["Uhrzeit und FPS"],
    keywords = { "uhr", "clock", "zeit", "time", "fps", "latenz", "latency", "ping" },
    tooltip = L["Kleine Zeile unter der Minimap mit Bildern pro Sekunde und Uhrzeit.\n\n"
        .. "Im Tooltip stehen Latenz und Serverzeit. Blizzards Uhr wird solange ausgeblendet. "
        .. "Sind Blizzards Spielerkoordinaten an, rückt die Zeile darunter."],
    isEnabled = MainOn,
    disabledHint = MAIN_HINT,
    set = function(value) SetUIValue("hudClock", value) end,
})

ns.AddOption(3, SECTION, {
    key = "hudXPBar",
    label = L["Erfahrungsleiste oben"],
    keywords = { "ep", "xp", "erfahrung", "experience", "ruf", "reputation", "leiste" },
    tooltip = L["Erfahrungsleiste oben in der Mitte: links Stufe und Fortschritt, in der Mitte erholte EP (heller Bereich) und, falls eingeschaltet, der EP-Tracker, rechts die EP fertiger Quests.\n\n"
        .. "Auf Höchststufe zeigt sie den Ruf der beobachteten Fraktion. Breite, Höhe und Schrift stellst du im Bereich Erfahrung ein. Shift + Ziehen verschiebt sie. "
        .. "Blizzards Leiste kommt nach dem Ausschalten mit /reload zurück."],
    isEnabled = MainOn,
    disabledHint = MAIN_HINT,
    set = function(value) SetUIValue("hudXPBar", value) end,
})

-- Bereich „Erfahrung“: Feinheiten der EP-Leiste ------------------------------------------

local XP_HINT = L["Erst „Erfahrungsleiste oben“ einschalten (Oberfläche → stray-Oberfläche)."]
local function XPOptionOn() return UIOn("hudXPBar") end

local function RefreshXPBar()
    if UIOn("hudXPBar") then
        LayoutXPBar()
        pcall(UpdateXP)
    end
end

ns.AddOption(3, SECTION_XP, {
    key = "questXPBar",
    label = L["Quest-EP auf der EP-Leiste"],
    keywords = { "quest", "ep", "xp", "abgeben", "turn in" },
    tooltip = L["Zeigt auf der stray-Erfahrungsleiste einen goldenen Bereich: so viele EP bringen alle abgeschlossenen Quests, die du noch nicht abgegeben hast. Er beginnt am aktuellen EP-Stand, die Summe steht rechts in der Leiste und im Tooltip."],
    isEnabled = XPOptionOn,
    disabledHint = XP_HINT,
    set = function(value)
        ns.db.questXPBar = value
        if UIOn("hudXPBar") then pcall(UpdateXP) end
    end,
})

ns.AddOption(3, SECTION_XP, {
    key = "xpBarWidth",
    type = "slider",
    label = L["Breite EP-Leiste"],
    min = 300, max = 1200, step = 10,
    tooltip = L["Breite der stray-Erfahrungsleiste in Pixeln."],
    isEnabled = XPOptionOn,
    disabledHint = XP_HINT,
    set = function(v)
        ns.db.xpBarWidth = math.max(300, math.min(1200, math.floor((tonumber(v) or 560) + 0.5)))
        RefreshXPBar()
    end,
})

ns.AddOption(3, SECTION_XP, {
    key = "xpBarHeight",
    type = "slider",
    label = L["Höhe EP-Leiste"],
    min = 10, max = 40, step = 1,
    tooltip = L["Höhe der stray-Erfahrungsleiste in Pixeln."],
    isEnabled = XPOptionOn,
    disabledHint = XP_HINT,
    set = function(v)
        ns.db.xpBarHeight = math.max(10, math.min(40, math.floor((tonumber(v) or 20) + 0.5)))
        RefreshXPBar()
    end,
})

ns.AddOption(3, SECTION_XP, {
    key = "xpBarFontSize",
    type = "slider",
    label = L["Schriftgröße EP-Leiste"],
    min = 8, max = 20, step = 1,
    tooltip = L["Schriftgröße der Texte auf der stray-Erfahrungsleiste in Pixeln."],
    isEnabled = XPOptionOn,
    disabledHint = XP_HINT,
    set = function(v)
        ns.db.xpBarFontSize = math.max(8, math.min(20, math.floor((tonumber(v) or 13) + 0.5)))
        RefreshXPBar()
    end,
})

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

ns.OnConfig(function()
    if UIOn("hudXPBar") then pcall(UpdateXP) end
end)

SafeOn("ADDON_LOADED", function(name)
    if name == "Blizzard_TimeManager" and UIOn("hudClock") then HideBlizzardClock() end
end)

SafeOn("PLAYER_LOGIN", function()
    if not ns.db then return end
    MigrateStrayUI() -- greift nur, falls ADDON_LOADED es nicht schon erledigt hat
    RememberUIState() -- Stand beim Login (die Module wenden ihn selbst an)
    MigrateOldMicroBar()
    pcall(ApplyClock, false)
    pcall(ApplyXP, false)
    pcall(ns.HudUpdateBottomBar)
    pcall(UpdateMiddleClick)
    -- EP-Tracker (xptracker.lua) meldet neue Zeilen für die EP-Leiste
    if ns.XPTracker and ns.XPTracker.OnChange then
        pcall(ns.XPTracker.OnChange, function() ScheduleXP() end)
    end
    -- Minimap-Form und andere Addon-Knöpfe stehen oft erst kurz nach dem Login fest
    C_Timer.After(1, function()
        pcall(UpdateMapButton)
        if UIOn("hudMinimapColumn") then pcall(ApplyColumn, false) end
        pcall(LayoutClock, true)
    end)
    C_Timer.After(5, function()
        if UIOn("hudMinimapColumn") then
            pcall(CollectButtons)
            pcall(LayoutColumn)
        end
        if BottomActive() then SchedulePark() end
    end)
end)

SafeOn("PLAYER_ENTERING_WORLD", function()
    if not ns.db then return end
    if UIOn("hudXPBar") then ScheduleXP() HideBlizzardXP() end
    if BottomActive() then
        SchedulePark()
        ScheduleBags()
    end
end)
