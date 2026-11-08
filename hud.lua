-- stray – Oberfläche: Minimap-Knopfspalte (Freunde, stray, Addon-Tasche), Menü auf der Minimap
-- (mittlere Maustaste und Kartenmenü-Knopf), Uhrzeit und FPS unter der Minimap, Erfahrungsleiste
-- oben, Taschen- und Menüleiste unten rechts (gehört zu „Eigene Aktionsleisten“).
-- Alles defensiv: Blizzard-Rahmen können im Client anders heißen oder fehlen.
-- Sichere/geschützte Rahmen nur außerhalb des Kampfes anfassen, sonst nach Kampfende nachholen.
-- Keine Felder auf Blizzard-Frames: Merker stehen in lokalen Tabellen mit dem Frame als Schlüssel.

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
    questxp = { 1.000, 0.820, 0.000, 0.40 }, -- Gold, EP abgabebereiter Quests
}

ns.defaults.questXPBar = false
ns.defaults.minimapMiddleMenu = false
ns.defaults.bottomMicroButtons = false
ns.defaults.bottomBarSize = 28

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
    ns.Print("Kein Verfolgungs-Menü gefunden.")
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
            root:CreateTitle("Verfolgung")
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
    ns.Print("Kein Kalender gefunden.")
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
local MENU_ENTRIES = {
    { key = "char", label = "Charakter", micro = true, secure = { "CharacterMicroButton" },
        icons = { "Interface\\Icons\\INV_Chest_Cloth_17" } },
    { key = "spell", label = "Zauberbuch", micro = true, secure = { "SpellbookMicroButton", "PlayerSpellsMicroButton" },
        icons = { "Interface\\Icons\\INV_Misc_Book_09" } },
    { key = "talent", label = "Talente", micro = true, secure = { "TalentMicroButton" },
        icons = { "Interface\\Icons\\Ability_Marksmanship" } },
    { key = "prof", label = "Berufe", micro = true, secure = { "ProfessionMicroButton" },
        icons = { "Interface\\Icons\\INV_Pick_02", "Interface\\Icons\\Trade_Engineering" } },
    { key = "quest", label = "Questlog", micro = true, secure = { "QuestLogMicroButton" },
        icons = { "Interface\\Icons\\INV_Misc_Book_08" } },
    { key = "friends", label = "Freunde", micro = true, icons = { "Interface\\Icons\\INV_Misc_GroupNeedMore" },
        has = function() return ToggleFriendsFrame ~= nil end,
        frame = function() return _G.FriendsFrame end,
        run = function() ToggleFriendsFrame(FRIEND_TAB_FRIENDS or 1) end },
    { key = "guild", label = "Gilde", micro = true, secure = { "GuildMicroButton" },
        icons = { "Interface\\Icons\\INV_Shirt_GuildTabard_01" } },
    { key = "lfg", label = "Gruppensuche", micro = true, secure = { "LFDMicroButton", "LFGMicroButton" },
        icons = { "Interface\\Icons\\INV_Misc_GroupLooking" } },
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

local function Has(entry)
    if entry.divider then return false end
    if entry.secure then return MicroFor(entry) ~= nil end
    local ok, has = pcall(entry.has)
    return ok and has and true or false
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
        if UIErrorsFrame then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Im Kampf nicht möglich.", 1, 0.3, 0.3) end
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
    hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18)
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
                row.text:SetText(entry.label)
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
        ns.Print("Menü geht erst nach dem Kampf.")
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
SafeOn("GLOBAL_MOUSE_DOWN", function()
    if not menu:IsShown() or InCombat() then return end
    if menu:IsMouseOver() then return end
    if menuOwner == mapButton and mapButton:IsMouseOver() then return end
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
    GameTooltip:AddLine("Kartenmenü")
    GoldLine("Linksklick: Charakter, Zauberbuch, Talente, Berufe, Questlog, Freunde, Gilde, Gruppensuche, Kalender, Verfolgung, Weltkarte")
    GameTooltip:AddLine("Geht nur außerhalb des Kampfes.", C.textDim[1], C.textDim[2], C.textDim[3], true)
    GameTooltip:Show()
end)
mapButton:SetScript("OnLeave", function(self)
    self:SetAlpha(0.75)
    SetBorder(self, C.border)
    GameTooltip:Hide()
end)

-- Kartenmenü-Knopf mit der Knopfspalte, bei eckiger Karte immer (dort fehlen Blizzards
-- Verfolgungs- und Kalenderknopf)
local function UpdateMapButton()
    local want = ns.db and (ns.db.hudMinimapColumn or (ns.IsSquareMinimap and ns.IsSquareMinimap())) and true or false
    mapButton:SetShown(want)
    if not want and menuOwner == mapButton then CloseMenu() end
end

-- Mittlere Maustaste auf der Minimap. Blizzard pingt bei jeder Maustaste im Innenkreis der Karte,
-- also auch hier; Mausrad: camera.lua
Minimap:HookScript("OnMouseUp", function(self, mouseButton)
    if mouseButton == "MiddleButton" and ns.db and ns.db.minimapMiddleMenu then
        OpenMenu(self)
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
    if ns.db and ns.db.hudMinimapColumn then LayoutColumn() end
end

local function ApplyColumn(toggled)
    if ns.db.hudMinimapColumn then
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

-- Blizzards Koordinaten (Edit Mode „Spielerkoordinaten“, CVar minimapShowPlayerCoords) stehen
-- bei der runden Karte 8–18 px unter der Minimap: die Uhr rückt dann darunter.
local function BlizzardCoordsOn()
    local ok, on = pcall(ns.GetCVarOn, "minimapShowPlayerCoords")
    return ok and on and true or false
end

local clockLayoutKey = nil

local function LayoutClock(force)
    local square = ns.IsSquareMinimap and ns.IsSquareMinimap() or false
    local clockOn = ns.db and ns.db.hudClock and true or false
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
    clock.text:SetText(string.format("|cff5aa8ff%s|r FPS   %s", fpsText, date("%H:%M")))
    LayoutClock(false)
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
local hookedClock = {} -- Blizzard-Uhrknöpfe mit OnShow-Hook (keine Felder auf Blizzard-Frames)

local function HideBlizzardClock()
    local b = _G.TimeManagerClockButton
    if not b then return end
    pcall(b.Hide, b)
    if not hookedClock[b] then
        hookedClock[b] = true
        pcall(b.HookScript, b, "OnShow", function(self)
            if ns.db and ns.db.hudClock then pcall(self.Hide, self) end
        end)
    end
end

local function ApplyClock(toggled)
    LayoutClock(true)
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

-- minimap.lua meldet, wenn die Karte eckig/rund wird oder die Größe wechselt
ns.HudLayoutAroundMap = function()
    pcall(UpdateMapButton)
    if ns.db and ns.db.hudMinimapColumn then pcall(LayoutColumn) end
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
    if not ns.db or not ns.db.hudXPBar then xpBar:Hide() return end
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
            local text = Pct(cur / max * 100) .. " %"
            if rested > 0 then text = text .. "  (Erholt: " .. Pct(rested / max * 100) .. " %)" end
            if questXP > 0 then text = text .. "  Quests: +" .. Num(questXP) .. " EP" end
            xpText:SetText(text)
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
        if xpData.quest and xpData.quest > 0 then
            GameTooltip:AddDoubleLine("Quests", "+" .. Num(xpData.quest) .. " EP (" .. Pct(xpData.quest / xpData.max * 100) .. " %)",
                1, 1, 1, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
            if xpData.cur + xpData.quest >= xpData.max then
                GameTooltip:AddLine("Reicht für die nächste Stufe.", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
            end
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

local hookedXP = {} -- Blizzard-Rahmen, an denen schon ein OnShow-Hook hängt (keine Felder auf Blizzard-Frames)

local function HideBlizzardXP()
    if not ns.db.hudXPBar then return end
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

-- QUEST_LOG_UPDATE kommt oft in Schüben: Quest-EP höchstens alle 0,5 s neu zählen
local questXPTimer = false
SafeOn("QUEST_LOG_UPDATE", function()
    if questXPTimer or not (ns.db and ns.db.hudXPBar and ns.db.questXPBar) then return end
    questXPTimer = true
    C_Timer.After(0.5, function()
        questXPTimer = false
        pcall(UpdateXP)
    end)
end)

---------------------------------------------------------------------------
-- 4) Taschen- und Menüleiste unten rechts
-- Erscheint mit „Eigene Aktionsleisten“ (ns.db.abEnabled). Eigene, flache stray-Knöpfe;
-- Blizzards Taschen- und Menüknöpfe werden außerhalb des Kampfes in einen versteckten
-- eigenen Rahmen umgehängt (kein Umsetzen von Edit-Mode-Systemen, keine Felder auf Blizzard-Frames).
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

local BAR_PAD = 3
local BAR_GAP = 2
local GROUP_GAP = 6

local function BottomActive()
    return ns.db and ns.db.abEnabled and true or false
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

local bottomBar = CreateFrame("Frame", "strayMicroBar", UIParent)
bottomBar:SetSize(200, 34)
bottomBar:SetFrameStrata("MEDIUM")
Style(bottomBar, { C.bg[1], C.bg[2], C.bg[3], 0.6 })
bottomBar:Hide()

-- Schlüssel „microbar“ wie bisher: eine schon verschobene Leiste bleibt, wo sie war
ns.MakeMovable(bottomBar, "microbar", { "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 4 })
ns.RegisterMovable(bottomBar, "Taschen und Menü", nil)
-- Mit sicheren Kindern ist die Leiste geschützt: im Kampf nicht ziehen
bottomBar:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombat() then self:StartMoving() end
end)

-- secureTarget: Blizzards Mikroknopf → sicherer Klick-Knopf, sonst normaler Knopf
local function MakeBarButton(secureTarget, name)
    local b
    if secureTarget then
        b = MakeSecureClick(name, bottomBar, secureTarget)
    else
        b = CreateFrame("Button", name, bottomBar)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    Style(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.12)
    b.count = Text(b, 10, FONT_BODY, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b:HookScript("OnEnter", function(self) SetBorder(self, C.accent) end)
    b:HookScript("OnLeave", function(self)
        SetBorder(self, C.border)
        GameTooltip:Hide()
    end)
    b:Hide()
    return b
end

-- Menüknöpfe (dieselben Einträge wie das Minimap-Menü), erst bei Bedarf außerhalb des Kampfes gebaut
local microButtons = {}
local microBuilt = false

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
                if not SetFirstTexture(b.icon, entry.icons) then
                    b.icon:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
                end
                if not entry.secure then
                    b:SetScript("OnClick", function(self) RunEntry(self.entry, self) end)
                end
                b:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(self.entry.label)
                    if self.entry.secure then
                        if not MicroUsable(self.entry) then
                            GameTooltip:AddLine("Gerade nicht verfügbar", C.textDim[1], C.textDim[2], C.textDim[3])
                        end
                    elseif BlockedNow(self.entry) then
                        GameTooltip:AddLine("Im Kampf gesperrt", 1, 0.3, 0.3)
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
        pcall(b.icon.SetDesaturated, b.icon, off)
        b.icon:SetAlpha(off and 0.5 or 1)
    end
end

-- Taschen
local function ContainerCall(name, ...)
    local fn = (C_Container and C_Container[name]) or _G[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and Number(v) or nil
end

local function BagInvID(bag)
    return ContainerCall("ContainerIDToInventoryID", bag)
end

-- Freie Plätze in allen Taschen: Blizzards Summe, sonst selbst zählen
local function TotalFreeSlots()
    local total = ContainerCall("CalculateTotalNumberOfFreeBagSlots")
    if total then return total end
    local sum = 0
    for i = 0, 4 do sum = sum + (ContainerCall("GetContainerNumFreeSlots", i) or 0) end
    return sum
end

local function KeyringShown()
    if type(KEYRING_CONTAINER) ~= "number" then return false end
    if C_ActionBar and C_ActionBar.ShouldShowKeyring then
        local ok, show = pcall(C_ActionBar.ShouldShowKeyring)
        return ok and ns.Public(show) and true or false
    end
    return false
end

local function PutIntoBag(bag)
    if not (CursorHasItem and CursorHasItem()) then return false end
    if bag == 0 then
        if PutItemInBackpack then pcall(PutItemInBackpack) end
    elseif bag == KEYRING_CONTAINER then
        if PutKeyInKeyRing then pcall(PutKeyInKeyRing) end
    else
        local inv = BagInvID(bag)
        if inv and PutItemInBag then pcall(PutItemInBag, inv) end
    end
    return true
end

local bagButtons = {}

local function MakeBagButton(bag, keyring)
    local b = MakeBarButton(nil, nil)
    b.bag = bag
    b.keyring = keyring
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self)
        if PutIntoBag(self.bag) then return end
        if self.bag == 0 then
            if IsModifiedClick and IsModifiedClick("OPENALLBAGS") and ToggleAllBags then
                pcall(ToggleAllBags)
            elseif ToggleBackpack then
                pcall(ToggleBackpack)
            end
        elseif ToggleBag then
            pcall(ToggleBag, self.bag)
        end
    end)
    b:SetScript("OnReceiveDrag", function(self) PutIntoBag(self.bag) end)
    b:SetScript("OnDragStart", function(self)
        if self.bag == 0 or self.keyring then return end
        local inv = BagInvID(self.bag)
        if inv and PickupBagFromSlot then pcall(PickupBagFromSlot, inv) end
    end)
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.keyring then
            GameTooltip:AddLine(KEYRING or "Schlüsselbund")
        elseif self.bag == 0 then
            GameTooltip:AddLine("Rucksack")
        else
            local inv = BagInvID(self.bag)
            local hasItem = false
            if inv then
                local ok, has = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", inv)
                hasItem = ok and ns.Public(has) and true or false
            end
            if not hasItem then GameTooltip:AddLine("Leerer Taschenplatz") end
        end
        if not self.keyring then
            local free, total = ContainerCall("GetContainerNumFreeSlots", self.bag), ContainerCall("GetContainerNumSlots", self.bag)
            if free and total and total > 0 then
                GameTooltip:AddLine("Frei: " .. free .. " von " .. total, C.text[1], C.text[2], C.text[3])
            end
            if self.bag == 0 then
                GameTooltip:AddLine("Frei in allen Taschen: " .. TotalFreeSlots(), C.text[1], C.text[2], C.text[3])
            end
        end
        GoldLine("Linksklick: öffnen")
        GameTooltip:Show()
    end)
    return b
end

for bag = 0, 4 do bagButtons[#bagButtons + 1] = MakeBagButton(bag, false) end
local keyringButton = MakeBagButton(type(KEYRING_CONTAINER) == "number" and KEYRING_CONTAINER or -2, true)

local BAG_EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local function UpdateBags()
    for _, b in ipairs(bagButtons) do
        local tex
        if b.bag == 0 then
            tex = "Interface\\Buttons\\Button-Backpack-Up"
        else
            local inv = BagInvID(b.bag)
            if inv and GetInventoryItemTexture then
                local ok, t = pcall(GetInventoryItemTexture, "player", inv)
                tex = ok and ns.Public(t) or nil
            end
        end
        b.icon:SetTexture(tex or BAG_EMPTY)
        local total = ContainerCall("GetContainerNumSlots", b.bag) or 0
        local free = ContainerCall("GetContainerNumFreeSlots", b.bag)
        b.count:SetText((total > 0 and free) and tostring(free) or "")
        pcall(b.icon.SetDesaturated, b.icon, total == 0)
    end
    keyringButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Key_14")
    keyringButton.count:SetText("")
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
    local font = math.max(8, math.floor(size * 0.38))
    local x = BAR_PAD
    local function place(b)
        b:SetSize(size, size)
        pcall(b.count.SetFont, b.count, FONT_BODY, font, "OUTLINE")
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", bottomBar, "BOTTOMLEFT", x, BAR_PAD)
        b:Show()
        x = x + size + BAR_GAP
    end
    local anyMicro = false
    for _, b in ipairs(microButtons) do
        if ns.db.bottomMicroButtons and Has(b.entry) then
            place(b)
            anyMicro = true
        else
            b:Hide()
        end
    end
    if anyMicro then x = x + GROUP_GAP - BAR_GAP end
    -- Rechts außen der Rucksack, links davon die Taschen 4 bis 1 (wie bei Blizzard)
    if KeyringShown() then place(keyringButton) else keyringButton:Hide() end
    for i = #bagButtons, 1, -1 do place(bagButtons[i]) end
    bottomBar:SetSize(x - BAR_GAP + BAR_PAD, size + 2 * BAR_PAD)
    UpdateMicroState()
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

-- Von actionbars.lua beim Umschalten von „Eigene Aktionsleisten“ und nach dem Login aufgerufen
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

ns.AddOption(3, SECTION, {
    key = "hudMinimapColumn",
    label = "Minimap-Knopfspalte",
    tooltip = "Senkrechte Knopfspalte neben der Minimap mit Freunden, stray-Knopf und Addon-Tasche.\n\n"
        .. "Freunde: Zahl der Freunde online, Liste im Tooltip, Linksklick öffnet die Freundesliste.\n"
        .. "Addon-Tasche: sammelt die Minimap-Knöpfe anderer Addons und klappt sie per Klick auf "
        .. "(verträgt sich nicht mit Leatrix „Hide addon buttons“).\n"
        .. "Oben links in der Minimap sitzt ein kleines Kartenmenü (Charakter, Zauberbuch, Talente, Berufe, Questlog, Freunde, Gilde, Gruppensuche, Kalender, Verfolgung, Weltkarte). Bei der eckigen Minimap ist es immer da, auch ohne diese Spalte.\n\n"
        .. "Die Spalte steht rechts neben der Minimap, am rechten Bildschirmrand links davon. "
        .. "Bei der eckigen Minimap sitzt sie links bündig daran.",
    set = function(value)
        ns.db.hudMinimapColumn = value
        ApplyColumn(true)
    end,
})

ns.AddOption(3, SECTION, {
    key = "hudClock",
    label = "Uhrzeit und FPS",
    tooltip = "Kleine Zeile unter der Minimap mit Bildern pro Sekunde und Uhrzeit.\n\n"
        .. "Im Tooltip stehen Latenz und Serverzeit. Blizzards Uhr wird solange ausgeblendet. "
        .. "Sind Blizzards Spielerkoordinaten an, rückt die Zeile darunter.",
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
    key = "questXPBar",
    label = "Quest-EP auf der EP-Leiste",
    tooltip = "Zeigt auf der stray-Erfahrungsleiste einen goldenen Bereich: so viele EP bringen alle abgeschlossenen Quests, die du noch nicht abgegeben hast. Er beginnt am aktuellen EP-Stand, die Summe steht in der Leiste und im Tooltip.\n\nBraucht die Option „Erfahrungsleiste oben“ (direkt darüber).",
    isEnabled = function() return ns.db and ns.db.hudXPBar and true or false end,
    disabledHint = "Erst „Erfahrungsleiste oben“ einschalten (direkt darüber).",
    set = function(value)
        ns.db.questXPBar = value
        if ns.db.hudXPBar then pcall(UpdateXP) end
    end,
})

local BOTTOM_HINT = "Erst „Eigene Aktionsleisten“ einschalten (Aktionsleisten → Aktionsleisten)."

ns.AddOption(3, SECTION, {
    key = "bottomMicroButtons",
    label = "Menüknöpfe unten anzeigen",
    tooltip = "Die Taschenleiste unten rechts erscheint mit „Eigene Aktionsleisten“ und zeigt Rucksack und Taschen mit der Zahl freier Plätze.\n\n"
        .. "Mit dieser Option kommen links davon die Menüknöpfe dazu: Charakter, Zauberbuch, Talente, Berufe, Questlog, Freunde, Gilde und Gruppensuche. "
        .. "Sie klicken Blizzards eigene Menüknöpfe an und gehen deshalb auch im Kampf. Grau heißt: Blizzard hat den Knopf gerade abgeschaltet (z. B. Talente unter Stufe 10). "
        .. "Das Spielmenü öffnest du wie gewohnt mit Esc.\n\n"
        .. "Shift + Ziehen am Rand verschiebt die Leiste (nicht im Kampf). Ein- und Umbau im Kampf geschieht erst danach.",
    isEnabled = BottomActive,
    disabledHint = BOTTOM_HINT,
    set = function(value)
        ns.db.bottomMicroButtons = value
        if BottomActive() then pcall(LayoutBottom) end
    end,
})

ns.AddOption(3, SECTION, {
    key = "bottomBarSize",
    type = "slider",
    label = "Größe Taschenleiste",
    min = 20, max = 40, step = 1,
    tooltip = "Kantenlänge der Knöpfe in der Taschen- und Menüleiste in Pixeln.",
    isEnabled = BottomActive,
    disabledHint = BOTTOM_HINT,
    set = function(v)
        ns.db.bottomBarSize = math.max(20, math.min(40, math.floor((tonumber(v) or 28) + 0.5)))
        if BottomActive() then pcall(LayoutBottom) end
    end,
})

ns.AddOption(3, "Kamera & Karte", {
    key = "minimapMiddleMenu",
    label = "Menü auf der mittleren Maustaste",
    tooltip = "Mittlere Maustaste auf der Minimap öffnet an der Maus ein kleines stray-Menü: Charakter, Zauberbuch, Talente, Berufe, Questlog, Freunde, Gilde, Gruppensuche sowie Kalender, Verfolgung, Weltkarte und, falls eingeschaltet, Twinks. "
        .. "Dasselbe Menü öffnet der Kartenmenü-Knopf oben links in der Karte.\n\n"
        .. "Im Kampf geht es nicht auf, dann kommt ein Hinweis im Chat. Schließen per Klick daneben oder Esc.\n\n"
        .. "Hinweis: Blizzard pingt bei jeder Maustaste innerhalb des runden Innenbereichs der Karte, also auch bei der mittleren. "
        .. "Ohne Ping geht es nah am Rand (bei eckiger Karte in einer Ecke). Mausrad bleibt wie gewohnt.",
    set = function(value)
        ns.db.minimapMiddleMenu = value
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
    MigrateOldMicroBar()
    pcall(ApplyClock, false)
    pcall(ApplyXP, false)
    pcall(ns.HudUpdateBottomBar)
    -- Minimap-Form und andere Addon-Knöpfe stehen oft erst kurz nach dem Login fest
    C_Timer.After(1, function()
        pcall(UpdateMapButton)
        if ns.db.hudMinimapColumn then pcall(ApplyColumn, false) end
        pcall(LayoutClock, true)
    end)
    C_Timer.After(5, function()
        if ns.db.hudMinimapColumn then
            pcall(CollectButtons)
            pcall(LayoutColumn)
        end
        if BottomActive() then SchedulePark() end
    end)
end)

SafeOn("PLAYER_ENTERING_WORLD", function()
    if not ns.db then return end
    if ns.db.hudXPBar then ScheduleXP() HideBlizzardXP() end
    if BottomActive() then
        SchedulePark()
        ScheduleBags()
    end
end)
