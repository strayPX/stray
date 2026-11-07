-- stray – Oberfläche: Minimap-Knopfspalte (Freunde, stray, Addon-Tasche, Kartenmenü),
-- Uhrzeit und FPS unter der Minimap, Erfahrungsleiste oben, Taschen- und Menüleiste.
-- Alles defensiv: Blizzard-Rahmen können im Client anders heißen oder fehlen.
-- Sichere/geschützte Rahmen nur außerhalb des Kampfes anfassen, sonst nach Kampfende nachholen.

local _, ns = ...

local SECTION = "Leisten & Minimap"

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_BODY = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local C = {
    bg      = { 0.051, 0.067, 0.090, 0.92 },
    border  = { 0.169, 0.290, 0.451, 1 },
    accent  = { 0.353, 0.659, 1.000, 1 },
    text    = { 0.890, 0.914, 0.953, 1 },
    textDim = { 0.435, 0.525, 0.651, 1 },
    xp      = { 0.557, 0.369, 0.929, 1 },   -- Lila
    rested  = { 0.353, 0.659, 1.000, 0.45 }, -- Blau, heller Bereich dahinter
}

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
                entry.area = (client and BNET_CLIENT_NAMES[client]) or client or ""
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
    if entry.level then left = left .. "  |cff8899aa" .. entry.level .. "|r" end
    GameTooltip:AddDoubleLine(left, entry.area or "", 1, 1, 1, C.textDim[1], C.textDim[2], C.textDim[3])
end

local MAX_LINES = 30

friendsCell:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, TooltipAnchor())
    GameTooltip:AddLine("Freunde")
    local favorites, others = {}, {}
    for _, entry in ipairs(BNetFriends()) do
        table.insert(entry.favorite and favorites or others, entry)
    end
    for _, entry in ipairs(WowFriends()) do table.insert(others, entry) end
    local shown = 0
    if #favorites > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Favoriten", C.accent[1], C.accent[2], C.accent[3])
        for _, entry in ipairs(favorites) do
            if shown < MAX_LINES then FriendLine(entry) shown = shown + 1 end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Freunde (" .. #others .. ")", C.accent[1], C.accent[2], C.accent[3])
    if #others == 0 then
        GameTooltip:AddLine("Niemand online", C.textDim[1], C.textDim[2], C.textDim[3])
    end
    for _, entry in ipairs(others) do
        if shown < MAX_LINES then FriendLine(entry) shown = shown + 1 end
    end
    if #favorites + #others > shown then
        GameTooltip:AddLine("… und " .. (#favorites + #others - shown) .. " weitere", C.textDim[1], C.textDim[2], C.textDim[3])
    end
    GameTooltip:AddLine(" ")
    GoldLine("Linksklick: Freundesliste öffnen")
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
    if friendTimer or not (ns.db and ns.db.hudMinimapColumn) then return end
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
        if not placing and collected[child] and ns.db and ns.db.hudMinimapColumn then ScheduleBagLayout() end
    end)
    child:HookScript("OnShow", ScheduleBagLayout)
    child:HookScript("OnHide", ScheduleBagLayout)
end

local function CollectButtons()
    if not (ns.db and ns.db.hudMinimapColumn) then return end
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
        addonBag.empty:SetText("leer")
        addonBag.empty:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end
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
    GameTooltip:AddLine("Addon-Tasche")
    local n = 0
    for _ in pairs(collected) do n = n + 1 end
    GameTooltip:AddLine("Minimap-Knöpfe anderer Addons: " .. n, C.text[1], C.text[2], C.text[3])
    GoldLine("Linksklick: auf- und zuklappen")
    GameTooltip:AddLine("Leatrix Plus „Hide addon buttons“ verträgt sich nicht damit – dort ausschalten, wenn Knöpfe fehlen.",
        C.textDim[1], C.textDim[2], C.textDim[3], true)
    GameTooltip:Show()
end)
bagCell:HookScript("OnLeave", function() GameTooltip:Hide() end)

-- Kartenmenü (oben links in der Minimap) -----------------------------------

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

local mapMenu = CreateFrame("Frame", "strayMapMenu", mapButton)
mapMenu:SetFrameStrata("HIGH")
mapMenu:SetPoint("TOPLEFT", mapButton, "BOTTOMLEFT", 0, -2)
mapMenu:SetClampedToScreen(true)
Style(mapMenu)
mapMenu:Hide()

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
    ns.Print("Kein Verfolgungs-Menü gefunden.")
    return false
end

local function OpenCalendar()
    if ToggleCalendar then
        if pcall(ToggleCalendar) then return end
    end
    if GameTimeFrame and GameTimeFrame.Click then
        if pcall(GameTimeFrame.Click, GameTimeFrame) then return end
    end
    ns.Print("Kein Kalender gefunden.")
end

local function OpenWorldMap()
    if ToggleWorldMap then
        if pcall(ToggleWorldMap) then return end
    end
    if WorldMapFrame then pcall(WorldMapFrame.SetShown, WorldMapFrame, not WorldMapFrame:IsShown()) end
end

local MAP_ENTRIES = {
    { label = "Verfolgung", available = function() return TrackingButton() ~= nil or _G.MiniMapTrackingDropDown ~= nil end, run = OpenTracking },
    { label = "Kalender", available = function() return ToggleCalendar ~= nil or GameTimeFrame ~= nil end, run = OpenCalendar },
    { label = "Weltkarte", available = function() return ToggleWorldMap ~= nil or WorldMapFrame ~= nil end, run = OpenWorldMap },
}

local mapRows = {}

local function BuildMapMenu()
    local y = -3
    local width = 96
    for i, entry in ipairs(MAP_ENTRIES) do
        local row = mapRows[i]
        if not row then
            row = CreateFrame("Button", nil, mapMenu)
            row:SetSize(width - 6, 18)
            row.text = Text(row, 11)
            row.text:SetPoint("LEFT", 6, 0)
            row.text:SetText(entry.label)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18)
            row:SetScript("OnClick", function(self)
                mapMenu:Hide()
                pcall(entry.run, mapButton)
            end)
            mapRows[i] = row
        end
        local ok, available = pcall(entry.available)
        if ok and available then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 3, y)
            row:Show()
            y = y - 18
        else
            row:Hide()
        end
    end
    mapMenu:SetSize(width, -y + 3)
end

mapButton:SetScript("OnClick", function()
    if mapMenu:IsShown() then
        mapMenu:Hide()
    else
        BuildMapMenu()
        mapMenu:Show()
    end
end)
mapButton:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    SetBorder(self, C.accent)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("Kartenmenü")
    GoldLine("Linksklick: Verfolgung, Kalender, Weltkarte")
    GameTooltip:Show()
end)
mapButton:SetScript("OnLeave", function(self)
    self:SetAlpha(0.75)
    SetBorder(self, C.border)
    GameTooltip:Hide()
end)

-- Menü schließt sich, wenn die Maus eine Weile weg ist
local mapIdle = 0
mapMenu:SetScript("OnShow", function() mapIdle = 0 end)
mapMenu:SetScript("OnUpdate", function(self, elapsed)
    if self:IsMouseOver() or mapButton:IsMouseOver() then
        mapIdle = 0
    else
        mapIdle = mapIdle + elapsed
        if mapIdle > 2 then self:Hide() end
    end
end)

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
    if not (ns.db and ns.db.hudMinimapColumn) then return end
    local side = ScreenSide()
    columnSide = side
    column:ClearAllPoints()
    if side == "RIGHT" then
        column:SetPoint("TOPLEFT", Minimap, "TOPRIGHT", CELL_GAP, 0)
    else
        column:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -CELL_GAP, 0)
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
        cell:SetPoint("TOP", column, "TOP", 0, -(i - 1) * (CELL + CELL_GAP))
        cell:Show()
    end
    column:SetSize(CELL, #cells * (CELL + CELL_GAP) - CELL_GAP)

    addonBag:ClearAllPoints()
    if side == "RIGHT" then
        addonBag:SetPoint("TOPRIGHT", bagCell, "BOTTOMRIGHT", 0, -CELL_GAP)
    else
        addonBag:SetPoint("TOPLEFT", bagCell, "BOTTOMLEFT", 0, -CELL_GAP)
    end
end

ns.OnMinimapButtonOption = function()
    if ns.db and ns.db.hudMinimapColumn then LayoutColumn() end
end

local function ApplyColumn(toggled)
    if ns.db.hudMinimapColumn then
        LayoutColumn()
        column:Show()
        mapButton:Show()
        pcall(UpdateFriendCount)
        if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
        CollectButtons()
    else
        column:Hide()
        mapButton:Hide()
        mapMenu:Hide()
        if ns.MinimapButtonUndock then ns.MinimapButtonUndock() end
        if toggled and #collectedList > 0 then
            ReleaseButtons()
            ns.Print("Die Minimap-Knöpfe anderer Addons sind zurück an der Minimap – nach /reload sitzen sie wieder richtig.")
        end
    end
end

-- Minimap verschoben oder neu skaliert: Seite neu prüfen
Minimap:HookScript("OnSizeChanged", function()
    if ns.db and ns.db.hudMinimapColumn then C_Timer.After(0, function() pcall(LayoutColumn) end) end
end)
SafeOn("EDIT_MODE_LAYOUTS_UPDATED", function()
    if ns.db and ns.db.hudMinimapColumn then C_Timer.After(0.5, function() pcall(LayoutColumn) end) end
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

local function UpdateClock()
    local fps = GetFramerate and Number(GetFramerate())
    local fpsText = fps and tostring(math.floor(fps + 0.5)) or "?"
    clock.text:SetText(string.format("|cff5aa8ff%s|r FPS   %s", fpsText, date("%H:%M")))
end

clock:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Uhrzeit und Leistung")
    GameTooltip:AddDoubleLine("Ortszeit", date("%H:%M"), 1, 1, 1, 1, 1, 1)
    if GetGameTime then
        local h, m = GetGameTime()
        h, m = Number(h), Number(m)
        if h and m then GameTooltip:AddDoubleLine("Serverzeit", string.format("%02d:%02d", h, m), 1, 1, 1, 1, 1, 1) end
    end
    if GetNetStats then
        local _, _, home, world = GetNetStats()
        home, world = Number(home), Number(world)
        if home then GameTooltip:AddDoubleLine("Latenz (Heim)", home .. " ms", 1, 1, 1, 1, 1, 1) end
        if world then GameTooltip:AddDoubleLine("Latenz (Welt)", world .. " ms", 1, 1, 1, 1, 1, 1) end
    end
    local fps = GetFramerate and Number(GetFramerate())
    if fps then GameTooltip:AddDoubleLine("Bilder pro Sekunde", tostring(math.floor(fps + 0.5)), 1, 1, 1, 1, 1, 1) end
    if TimeManager_Toggle or ToggleTimeManager then
        GameTooltip:AddLine(" ")
        GoldLine("Linksklick: Uhr und Wecker")
    end
    GameTooltip:Show()
end)
clock:SetScript("OnLeave", function() GameTooltip:Hide() end)
clock:SetScript("OnClick", function()
    local toggle = TimeManager_Toggle or ToggleTimeManager
    if toggle then pcall(toggle) end
end)

local clockTicker

local function HideBlizzardClock()
    local b = _G.TimeManagerClockButton
    if not b then return end
    pcall(b.Hide, b)
    if not b.strayHooked then
        b.strayHooked = true
        pcall(b.HookScript, b, "OnShow", function(self)
            if ns.db and ns.db.hudClock then pcall(self.Hide, self) end
        end)
    end
end

local function ApplyClock(toggled)
    if ns.db.hudClock then
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

local mainBar = CreateFrame("StatusBar", nil, xpBar)
mainBar:SetAllPoints(restBar)
mainBar:SetFrameLevel(restBar:GetFrameLevel() + 1)
mainBar:SetStatusBarTexture(WHITE)
mainBar:SetStatusBarColor(C.xp[1], C.xp[2], C.xp[3], C.xp[4])
mainBar:SetMinMaxValues(0, 1)
mainBar:SetValue(0)

local xpText = Text(mainBar, 11, FONT_BODY, "OUTLINE")
xpText:SetPoint("CENTER", xpBar, "CENTER", 0, 0)

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

local function UpdateXP()
    if not ns.db or not ns.db.hudXPBar then xpBar:Hide() return end
    if not AtMaxLevel() then
        local cur, max = Number(UnitXP("player")), Number(UnitXPMax("player"))
        local rested = GetXPExhaustion and Number(GetXPExhaustion()) or 0
        if cur and max and max > 0 then
            xpMode = "xp"
            xpData = { cur = cur, max = max, rested = rested, level = Number(UnitLevel("player")) }
            mainBar:SetStatusBarColor(C.xp[1], C.xp[2], C.xp[3], C.xp[4])
            mainBar:SetMinMaxValues(0, max)
            mainBar:SetValue(cur)
            restBar:SetMinMaxValues(0, max)
            restBar:SetValue(math.min(cur + rested, max))
            restBar:Show()
            local text = Pct(cur / max * 100) .. " %"
            if rested > 0 then text = text .. "  (Erholt: " .. Pct(rested / max * 100) .. " %)" end
            xpText:SetText(text)
            xpBar:Show()
            return
        end
    end
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
        xpText:SetText(name .. ": " .. pct .. " %" .. (label ~= "" and ("  (" .. label .. ")") or ""))
        xpBar:Show()
        return
    end
    xpMode = "none"
    if ns.IsConfigOpen() then
        -- Beispiel, damit man die Leiste sehen und verschieben kann
        mainBar:SetMinMaxValues(0, 1)
        mainBar:SetValue(0.5)
        restBar:Hide()
        xpText:SetText("Erfahrungsleiste (keine Fraktion beobachtet)")
        xpBar:Show()
    else
        xpBar:Hide()
    end
end

xpBar:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if xpMode == "xp" and xpData.max then
        GameTooltip:AddLine("Erfahrung" .. (xpData.level and (" – Level " .. xpData.level) or ""))
        GameTooltip:AddDoubleLine("EP", Num(xpData.cur) .. " / " .. Num(xpData.max), 1, 1, 1, 1, 1, 1)
        local missing = xpData.max - xpData.cur
        GameTooltip:AddDoubleLine("Fehlend", Num(missing) .. " (" .. Pct(missing / xpData.max * 100) .. " %)", 1, 1, 1, 1, 1, 1)
        if xpData.rested > 0 then
            GameTooltip:AddDoubleLine("Erholt", Num(xpData.rested) .. " (" .. Pct(xpData.rested / xpData.max * 100) .. " %)",
                1, 1, 1, C.accent[1], C.accent[2], C.accent[3])
        end
    elseif xpMode == "rep" and xpData.name then
        GameTooltip:AddLine(xpData.name)
        if xpData.label ~= "" then GameTooltip:AddLine(xpData.label, 1, 1, 1) end
        if xpData.span > 0 then
            GameTooltip:AddDoubleLine("Ruf", Num(xpData.value) .. " / " .. Num(xpData.span), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Fehlend", Num(xpData.span - xpData.value), 1, 1, 1, 1, 1, 1)
        end
    else
        GameTooltip:AddLine("Erfahrungsleiste")
        GameTooltip:AddLine("Auf Höchststufe zeigt sie den Ruf der beobachteten Fraktion.", 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    GoldLine("Shift + Ziehen: verschieben")
    GameTooltip:Show()
end)
xpBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

ns.RegisterMovable(xpBar, "Erfahrungsleiste", function() pcall(UpdateXP) end)

-- Blizzards EP- und Rufleisten: nur verstecken, keine Edit-Mode-Systeme umhängen
local BLIZZARD_XP = {
    "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar", "ExhaustionTick",
    "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
}

local function HideBlizzardXP()
    if not ns.db.hudXPBar then return end
    for _, name in ipairs(BLIZZARD_XP) do
        local f = _G[name]
        if type(f) == "table" and f.Hide then
            if InCombat() and IsProtectedFrame(f) then
                Defer("blizzardXP", HideBlizzardXP)
            else
                pcall(f.Hide, f)
                if not f.strayHudHooked and f.HookScript then
                    f.strayHudHooked = true
                    pcall(f.HookScript, f, "OnShow", function(self)
                        if not (ns.db and ns.db.hudXPBar) then return end
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
    if ns.db.hudXPBar then
        ns.RestorePosition(xpBar)
        UpdateXP()
        HideBlizzardXP()
    else
        xpBar:Hide()
        if toggled then ns.Print("Blizzards Erfahrungsleiste kommt nach /reload zurück.") end
    end
end

local xpTimer = false
local function ScheduleXP()
    if xpTimer or not (ns.db and ns.db.hudXPBar) then return end
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

---------------------------------------------------------------------------
-- 4) Taschen- und Menüleiste
---------------------------------------------------------------------------

local MICRO_FALLBACK = {
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
    "SocialsMicroButton", "GuildMicroButton", "WorldMapMicroButton", "LFGMicroButton",
    "PVPMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}
local BAG_BUTTONS = {
    "KeyRingButton", "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot", "CharacterBag0Slot",
    "MainMenuBarBackpackButton",
}
local MICRO_PAD = 3
local GROUP_GAP = 8

local microBar = CreateFrame("Frame", "strayMicroBar", UIParent)
microBar:SetSize(200, 40)
microBar:SetFrameStrata("MEDIUM")
Style(microBar, { C.bg[1], C.bg[2], C.bg[3], 0.6 })
microBar:Hide()

ns.MakeMovable(microBar, "microbar", { "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 4 })
-- Die Leiste enthält Blizzard-Knöpfe: im Kampf nicht ziehen
local dragStart = microBar:GetScript("OnDragStart")
microBar:SetScript("OnDragStart", function(self, ...)
    if InCombat() then return end
    if dragStart then dragStart(self, ...) end
end)

local microTaken = false

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

local ScheduleMicro -- unten definiert

local function HookButton(b)
    if b.strayMicroHooked then return end
    b.strayMicroHooked = true
    pcall(b.HookScript, b, "OnShow", function() ScheduleMicro() end)
    pcall(b.HookScript, b, "OnHide", function() ScheduleMicro() end)
end

local function PlaceRow(names, x, yOffset, gapFor)
    local maxH = 0
    local any = false
    for _, name in ipairs(names) do
        local b = _G[name]
        if type(b) == "table" and b.SetParent and b.GetWidth then
            if b:GetParent() ~= microBar then pcall(b.SetParent, b, microBar) end
            HookButton(b)
            if b:IsShown() then
                local w, h = b:GetWidth() or 0, b:GetHeight() or 0
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", microBar, "BOTTOMLEFT", x, MICRO_PAD + yOffset)
                x = x + w + gapFor(w, h)
                if h + yOffset > maxH then maxH = h + yOffset end
                any = true
            end
        end
    end
    return x, maxH, any
end

local function LayoutMicro()
    if not (ns.db and ns.db.hudMicroBar) then return end
    if InCombat() then
        Defer("micro", LayoutMicro)
        return
    end
    -- Klassische Mikroknöpfe sind hoch mit leerem oberem Teil und überlappen bei Blizzard leicht
    local function microGap(w, h) return (w > 0 and h / w > 1.6) and -3 or 2 end
    local function bagGap() return 2 end
    local x, microH, anyMicro = PlaceRow(MicroNames(), MICRO_PAD, 0, microGap)
    if anyMicro then x = x + GROUP_GAP end
    local bagX, bagH, anyBag = PlaceRow(BAG_BUTTONS, x, 1, bagGap)
    if anyBag then x = bagX end
    microBar:SetSize(math.max(x + MICRO_PAD, 40), math.max(microH, bagH, 20) + 2 * MICRO_PAD)
    microTaken = true
end

local microScheduled = false
function ScheduleMicro()
    if microScheduled or not (ns.db and ns.db.hudMicroBar and microTaken) then return end
    microScheduled = true
    C_Timer.After(0, function()
        microScheduled = false
        pcall(LayoutMicro)
    end)
end

-- Blizzard setzt die Knöpfe bei Fahrzeug, Haustierkampf oder Edit Mode neu – zurückholen
local microHooksDone = false
local function HookBlizzardMicro()
    if microHooksDone then return end
    microHooksDone = true
    for _, fname in ipairs({ "UpdateMicroButtonsParent", "MoveMicroButtons", "MainMenuBarVehicleLeaveButton_Update" }) do
        if type(_G[fname]) == "function" then
            pcall(hooksecurefunc, fname, function() ScheduleMicro() end)
        end
    end
    for _, holder in ipairs({ "MicroMenu", "MicroMenuContainer", "BagsBar", "MicroButtonAndBagsBar" }) do
        local f = _G[holder]
        if type(f) == "table" and type(f.Layout) == "function" then
            pcall(hooksecurefunc, f, "Layout", function() ScheduleMicro() end)
        end
    end
end

local function ApplyMicro(toggled)
    if ns.db.hudMicroBar then
        if InCombat() then
            Defer("microApply", function() ApplyMicro(toggled) end)
            return
        end
        ns.RestorePosition(microBar)
        microBar:Show()
        HookBlizzardMicro()
        LayoutMicro()
    elseif toggled then
        ns.Print("Menü- und Taschenknöpfe kehren nach /reload an ihren Platz zurück.")
    end
end

ns.RegisterMovable(microBar, "Taschen und Menü", nil)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(3, SECTION, {
    key = "hudMinimapColumn",
    label = "Minimap-Knopfspalte",
    tooltip = "Senkrechte Knopfspalte neben der Minimap mit Freunden, stray-Knopf und Addon-Tasche.\n\n"
        .. "Freunde: Zahl der Freunde online, Liste im Tooltip, Linksklick öffnet die Freundesliste.\n"
        .. "Addon-Tasche: sammelt die Minimap-Knöpfe anderer Addons und klappt sie per Klick auf "
        .. "(verträgt sich nicht mit Leatrix „Hide addon buttons“).\n"
        .. "Oben links in der Minimap sitzt ein kleines Kartenmenü (Verfolgung, Kalender, Weltkarte).\n\n"
        .. "Die Spalte steht rechts neben der Minimap, am rechten Bildschirmrand links davon.",
    set = function(value)
        ns.db.hudMinimapColumn = value
        ApplyColumn(true)
    end,
})

ns.AddOption(3, SECTION, {
    key = "hudClock",
    label = "Uhrzeit und FPS",
    tooltip = "Kleine Zeile unter der Minimap mit Bildern pro Sekunde und Uhrzeit.\n\n"
        .. "Im Tooltip stehen Latenz und Serverzeit. Blizzards Uhr wird solange ausgeblendet.",
    set = function(value)
        ns.db.hudClock = value
        ApplyClock(true)
    end,
})

ns.AddOption(3, SECTION, {
    key = "hudXPBar",
    label = "Erfahrungsleiste oben",
    tooltip = "Schmale Erfahrungsleiste oben in der Mitte mit erholten EP als hellem Bereich.\n\n"
        .. "Auf Höchststufe zeigt sie den Ruf der beobachteten Fraktion. Shift + Ziehen verschiebt sie. "
        .. "Blizzards Leiste kommt nach dem Ausschalten mit /reload zurück.",
    set = function(value)
        ns.db.hudXPBar = value
        ApplyXP(true)
    end,
})

ns.AddOption(3, SECTION, {
    key = "hudMicroBar",
    label = "Taschen- und Menüleiste",
    tooltip = "Menü- und Taschenknöpfe als schlanke Reihe, anfangs unten rechts.\n\n"
        .. "Shift + Ziehen am Rand verschiebt sie (nicht im Kampf). "
        .. "Ausschalten wirkt erst nach /reload (Neuladen nötig).",
    set = function(value)
        ns.db.hudMicroBar = value
        ApplyMicro(true)
    end,
})

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

ns.OnConfig(function()
    if ns.db and ns.db.hudXPBar then pcall(UpdateXP) end
end)

SafeOn("ADDON_LOADED", function(name)
    if name == "Blizzard_TimeManager" and ns.db and ns.db.hudClock then HideBlizzardClock() end
end)

SafeOn("PLAYER_LOGIN", function()
    if not ns.db then return end
    pcall(ApplyClock, false)
    pcall(ApplyXP, false)
    pcall(ApplyMicro, false)
    -- Minimap-Form und andere Addon-Knöpfe stehen oft erst kurz nach dem Login fest
    C_Timer.After(1, function()
        if ns.db.hudMinimapColumn then pcall(ApplyColumn, false) end
    end)
    C_Timer.After(5, function()
        if ns.db.hudMinimapColumn then
            pcall(CollectButtons)
            pcall(LayoutColumn)
        end
        if ns.db.hudMicroBar then ScheduleMicro() end
    end)
end)

SafeOn("PLAYER_ENTERING_WORLD", function()
    if not ns.db then return end
    if ns.db.hudXPBar then ScheduleXP() HideBlizzardXP() end
    if ns.db.hudMicroBar then ScheduleMicro() end
end)
