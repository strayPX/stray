-- stray – Chat: Webadressen anklickbar und kopierbar machen, Koordinaten als Kartenpin-Link
-- Eigene Links laufen über den Linktyp „addon:“: Blizzard reicht Klicks darauf als
-- EventRegistry-Ereignis „SetItemRef“ weiter, ohne Blizzard-Code zu verändern (kein Taint).

local _, ns = ...
local L = ns.L

ns.defaults.chatCoords = false

ns.AddOption(1, "Chat", {
    key = "chatLinks",
    label = L["Links kopierbar"],
    tooltip = L["Webadressen im Chat werden blau und anklickbar. Ein Klick öffnet ein Feld, aus dem du den Link mit Strg+C kopierst."],
})

ns.AddOption(1, "Chat", {
    key = "chatCoords",
    label = L["Koordinaten anklickbar"],
    tooltip = L["Koordinaten im Chat wie „45.2, 67.8“ oder „45,2 67,8“ werden zu Links. Ganze Zahlen wie „45 67“ nur mit einem Wort davor, z. B. „bei 45 67“ oder „/way 45 67“.\nEin Klick setzt einen Kartenpin auf deiner aktuellen Karte.\nIn Instanzen ist der Chat versiegelt, dort bleibt alles unverändert."],
})

local LINK_COLOR = "|cffb3a8fa" -- stray-Lila (ns.Colors.accentText), gut lesbar im Chat
local LINK_PREFIX = "addon:stray:"

-- Eigener Linktyp „addon:“ vorhanden? (Forever: ja, über LinkUtil und EventRegistry)
local function HasAddonLinks()
    return EventRegistry and EventRegistry.RegisterCallback and LinkTypes and LinkTypes.AddOn == "addon"
end

local USE_ADDON_LINKS = HasAddonLinks() and true or false

local AddMessageFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local function RegisterFilter(fn)
    if not AddMessageFilter then return end
    for _, event in ipairs(CHAT_EVENTS) do
        pcall(AddMessageFilter, event, fn)
    end
end

---------------------------------------------------------------------------
-- Webadressen
---------------------------------------------------------------------------

local function MakeUrlLink(url)
    if USE_ADDON_LINKS then
        return LINK_COLOR .. "|H" .. LINK_PREFIX .. "url:" .. url .. "|h[" .. url .. "]|h|r"
    end
    return LINK_COLOR .. "|Hurl:" .. url .. "|h[" .. url .. "]|h|r"
end

local function LooksLikeUrl(word)
    return word:match("^%a[%w%+%.%-]*://%S+")
        or word:match("^www%.[%w%-]+%.%a%a")
        or word:match("^[%w%-]+%.[%w%-%.]*%a%a/%S*") -- z. B. discord.gg/abc
end

-- Ein Wort prüfen; vorhandene WoW-Links und Farbcodes (enthalten „|“) bleiben unangetastet
local function ConvertWord(word)
    if word:find("|", 1, true) then return nil end
    local lead = word:match("^[%(%[\"']+") or ""
    local trail = word:match("[%.,;:!%?%)%]\"']+$") or ""
    local core = word:sub(#lead + 1, #word - #trail)
    if core == "" or not LooksLikeUrl(core) then return nil end
    return lead .. MakeUrlLink(core) .. trail
end

local function UrlFilter(_, _, msg, ...)
    if not ns.db or not ns.db.chatLinks or ns.IsSecret(msg) or type(msg) ~= "string" then return false end
    local changed = false
    local newMsg = msg:gsub("%S+", function(word)
        local link = ConvertWord(word)
        if link then changed = true end
        return link
    end)
    if changed then return false, newMsg, ... end
    return false
end

RegisterFilter(UrlFilter)

---------------------------------------------------------------------------
-- Koordinaten
---------------------------------------------------------------------------

-- Wörter, nach denen auch ganze Zahlen („bei 45 67“) als Koordinaten gelten
local CONTEXT_WORDS = {
    ["bei"] = true, ["at"] = true, ["@"] = true, ["auf"] = true, ["nach"] = true,
    ["way"] = true, ["/way"] = true, ["/tway"] = true, ["loc"] = true, ["ort"] = true,
    ["pos"] = true, ["position"] = true,
    ["coord"] = true, ["coords"] = true, ["coordinates"] = true,
    ["koord"] = true, ["koords"] = true, ["koordinaten"] = true,
}

local function HasContextWord(before)
    local word = before:match("(%S+)%s*$")
    if not word then return false end
    word = word:lower():gsub("^[%(%[\"']+", ""):gsub("[:%.,;]+$", "")
    return CONTEXT_WORDS[word] == true
end

local function ToNumber(text)
    local n = tonumber((text:gsub(",", ".")))
    if not n or n ~= n or n < 0 or n > 100 then return nil end
    return n
end

-- Anzeige: Komma wird Punkt, sonst wie geschrieben
local function Display(text)
    return (text:gsub(",", "."))
end

local function MakeCoordLink(xText, yText)
    local x, y = Display(xText), Display(yText)
    return LINK_COLOR .. "|H" .. LINK_PREFIX .. "coord:" .. x .. ":" .. y .. "|h[" .. x .. ", " .. y .. "]|h|r"
end

local PAIR_PATTERNS = {
    -- Dezimalkomma: „45,2 67,8“, „45,2; 67,8“ (zuerst, sonst läse der nächste Fall „45“ und „2“)
    { pattern = "^(%d+,%d+)()%s*[;/]?%s*()(%d+,%d+)()", comma = true },
    -- Dezimalpunkt oder ganze Zahlen: „45.2, 67.8“, „45.2 67.8“, „45 67“, „45, 67“
    { pattern = "^(%d+%.?%d*)()%s*[,;/]?%s*()(%d+%.?%d*)()" },
}

-- Ende eines Treffers prüfen: danach darf keine weitere Ziffer oder kein Buchstabe folgen
local function CleanEnd(rest, stop)
    local nextChar = rest:sub(stop, stop)
    if nextChar == "" then return true end
    if nextChar:match("[%a%d_]") then return false end
    if (nextChar == "." or nextChar == ",") and rest:sub(stop + 1, stop + 1):match("%d") then return false end
    return true
end

-- Versucht an Position pos (dort beginnt eine Ziffer) ein Koordinatenpaar zu lesen.
-- Gibt Endposition (exklusiv), x-Text und y-Text zurück.
-- Ganze Zahlen („45 67“) zählen nur mit Kontextwort davor, z. B. „bei 45 67“.
local function MatchPair(s, pos, before)
    local rest = s:sub(pos)
    for _, entry in ipairs(PAIR_PATTERNS) do
        local x, sepStart, yStart, y, stop = rest:match(entry.pattern)
        if x and yStart > sepStart and x:sub(-1) ~= "." then
            -- Satzpunkt am Ende („bei 45 67.“) gehört nicht zur Zahl
            if y:sub(-1) == "." then
                y = y:sub(1, -2)
                stop = stop - 1
            end
            local separator = rest:sub(sepStart, yStart - 1)
            local decimal = entry.comma or x:find(".", 1, true) or y:find(".", 1, true)
            -- Ohne Kontextwort nur, wenn beide Zahlen Nachkommastellen haben (sonst würde „19.30 20“ ein Link)
            local bothDecimal = entry.comma or (x:find(".", 1, true) and y:find(".", 1, true))
            -- „45,2“ ohne Leerzeichen ist eher eine einzelne Zahl mit Komma als ein Paar
            local ambiguous = not decimal and separator == ","
            if not ambiguous and CleanEnd(rest, stop) and ToNumber(x) and ToNumber(y) then
                if bothDecimal or HasContextWord(before) then
                    return pos + stop - 1, x, y
                end
            end
        end
    end
    return nil
end

-- Klartext (ohne Links und Farbcodes) nach Koordinaten durchsuchen
local function ConvertPlain(s, prefixText)
    local out, i, changed = {}, 1, false
    local len = #s
    while i <= len do
        local p = s:find("%d", i)
        if not p then
            out[#out + 1] = s:sub(i)
            break
        end
        local prev = p > 1 and s:sub(p - 1, p - 1) or ""
        local stop, x, y
        if not prev:match("[%w%.,]") then
            stop, x, y = MatchPair(s, p, prefixText .. s:sub(1, p - 1))
        end
        if stop then
            out[#out + 1] = s:sub(i, p - 1)
            out[#out + 1] = MakeCoordLink(x, y)
            changed = true
            i = stop
        else
            -- ganze Zahl überspringen, damit „1234“ nicht als „34“ weitergelesen wird
            local numEnd = s:find("[^%d%.,]", p) or (len + 1)
            out[#out + 1] = s:sub(i, numEnd - 1)
            i = numEnd
        end
    end
    return table.concat(out), changed
end

-- Länge einer Escape-Sequenz ab Position p („|“), damit Links, Farben und Symbole unangetastet bleiben
local function EscapeEnd(msg, p)
    local kind = msg:sub(p + 1, p + 1)
    if kind == "H" then
        local a = msg:find("|h", p + 2, true)
        local b = a and msg:find("|h", a + 2, true)
        return b and (b + 2) or (#msg + 1)
    elseif kind == "c" then
        -- „|cnNAME:“ (benannte Farbe) oder „|cAARRGGBB“
        if msg:sub(p + 2, p + 2) == "n" then
            local colon = msg:find(":", p + 3, true)
            return colon and (colon + 1) or (#msg + 1)
        end
        return p + 10
    elseif kind == "T" or kind == "A" or kind == "K" then
        local close = msg:find("|" .. kind:lower(), p + 2, true)
        return close and (close + 2) or (#msg + 1)
    end
    return p + 2
end

local function ConvertCoords(msg)
    local out, i, changed = {}, 1, false
    local len = #msg
    local plainSoFar = ""
    while i <= len do
        local p = msg:find("|", i, true)
        local plain = msg:sub(i, (p or (len + 1)) - 1)
        if plain ~= "" then
            local converted, didChange = ConvertPlain(plain, plainSoFar)
            out[#out + 1] = converted
            if didChange then changed = true end
            plainSoFar = plainSoFar .. plain
        end
        if not p then break end
        local stop = EscapeEnd(msg, p)
        out[#out + 1] = msg:sub(p, stop - 1)
        -- Ein Link trennt den Text: Kontextwort davor zählt nicht über Links hinweg
        plainSoFar = plainSoFar .. " "
        i = stop
    end
    return table.concat(out), changed
end

local function CoordFilter(_, _, msg, ...)
    -- Versiegelte Nachrichten (Instanzen) unverändert durchlassen, ohne sie anzufassen
    if not USE_ADDON_LINKS or not ns.db or not ns.db.chatCoords then return false end
    if ns.IsSecret(msg) or type(msg) ~= "string" then return false end
    if not msg:find("%d") then return false end
    local ok, newMsg, changed = pcall(ConvertCoords, msg)
    if ok and changed then return false, newMsg, ... end
    return false
end

RegisterFilter(CoordFilter)

---------------------------------------------------------------------------
-- Kartenpin setzen
---------------------------------------------------------------------------

local function SetPin(xText, yText)
    local x, y = tonumber(xText), tonumber(yText)
    if not x or not y then return end
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.SetUserWaypoint or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then
        ns.Print(L["Kartenpins gibt es in diesem Client nicht."])
        return
    end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or ns.IsSecret(mapID) or type(mapID) ~= "number" then
        ns.Print(L["Keine Karte für den Pin gefunden."])
        return
    end
    if C_Map.CanSetUserWaypointOnMap then
        local okCan, can = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
        if okCan and not ns.IsSecret(can) and can == false then
            ns.Print(L["Auf dieser Karte kann kein Pin gesetzt werden."])
            return
        end
    end
    local point = UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100)
    local okSet, wasSet = pcall(C_Map.SetUserWaypoint, point)
    if not okSet or wasSet == false then
        ns.Print(L["Pin konnte nicht gesetzt werden."])
        return
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    ns.Print(L("Pin gesetzt (%s, %s)", xText, yText))
end

---------------------------------------------------------------------------
-- Kopierfeld
---------------------------------------------------------------------------

local function GetEditBox(popup)
    return popup.editBox or popup.EditBox or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "EditBox"])
end

local copyURL -- zuletzt angezeigte Adresse (statt eines Feldes auf Blizzards Popup)
StaticPopupDialogs["STRAY_COPY_URL"] = {
    text = L["Link kopieren mit Strg+C:"],
    button1 = L["Schließen"],
    hasEditBox = true,
    editBoxWidth = 320,
    OnShow = function(self, data)
        local box = GetEditBox(self)
        if not box then return end
        box:SetText(data or self.data or "")
        box:HighlightText()
        box:SetFocus()
    end,
    EditBoxOnTextChanged = function(box)
        -- Text bleibt unverändert, auch wenn man versehentlich tippt
        local url = copyURL
        if url and box:GetText() ~= url then
            box:SetText(url)
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

local function ShowCopy(url)
    copyURL = url
    if ItemRefTooltip then ItemRefTooltip:Hide() end
    -- Texte beim Anzeigen holen, damit sie der gewählten Sprache folgen
    local dialog = StaticPopupDialogs["STRAY_COPY_URL"]
    if dialog then
        dialog.text = L["Link kopieren mit Strg+C:"]
        dialog.button1 = L["Schließen"]
    end
    local popup = StaticPopup_Show("STRAY_COPY_URL", nil, nil, url)
    -- Absicherung, falls der Client „data“ erst nach OnShow setzt (keine Felder auf das Popup schreiben)
    if popup then
        local box = GetEditBox(popup)
        if box then
            box:SetText(url)
            box:HighlightText()
            box:SetFocus()
        end
    end
end

---------------------------------------------------------------------------
-- Klicks auf eigene Links
---------------------------------------------------------------------------

local function HandleStrayLink(link)
    if ns.IsSecret(link) or type(link) ~= "string" then return end
    if link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return end
    local body = link:sub(#LINK_PREFIX + 1)
    local url = body:match("^url:(.+)$")
    if url then
        ShowCopy(url)
        return
    end
    local x, y = body:match("^coord:([%d%.]+):([%d%.]+)$")
    if x then SetPin(x, y) end
end

if USE_ADDON_LINKS then
    -- Blizzard meldet Klicks auf „addon:“-Links hier; der Link-Tooltip öffnet sich dabei nicht
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        local ok, err = pcall(HandleStrayLink, link)
        if not ok then geterrorhandler()(err) end
    end, ns)
else
    -- Älterer Client ohne „addon:“-Links: Klicks auf „url:“-Links im Link-Tooltip abfangen
    local function WrapTooltip(method)
        if not ItemRefTooltip or not ItemRefTooltip[method] then return end
        local original = ItemRefTooltip[method]
        ItemRefTooltip[method] = function(self, link, ...)
            if not ns.IsSecret(link) and type(link) == "string" and link:sub(1, 4) == "url:" then
                ShowCopy(link:sub(5))
                return
            end
            return original(self, link, ...)
        end
    end
    WrapTooltip("SetHyperlink")
    WrapTooltip("ItemRefSetHyperlink")
end

---------------------------------------------------------------------------
-- Chat-Fenster und Chat-Komfort (Paket B)
-- Jede Option ist einzeln schaltbar, Standard aus. Bei „aus“ bleibt Blizzards Verhalten unberührt.
-- Keine Felder auf Blizzard-Frames: Ursprungswerte stehen in lokalen Tabellen (Frame als Schlüssel).
---------------------------------------------------------------------------

do
    local WIN = "Chat-Fenster"
    local MAX_LINES_ON, MAX_LINES_OFF = 4096, 128
    local RESTORE_LINES, RESTORE_MAX_AGE, RESTORE_MAX_LEN = 60, 600, 600
    local COPY_LINES = 1000

    local features = {}     -- Schlüssel → function(on), idempotent
    local frameLevel = {}   -- Schlüssel, deren Wirkung pro Chatfenster gilt (neue Fenster nachziehen)
    local original = {}     -- Ursprungswerte, nach Art getrennt: original.<art>[frame/…]
    for _, kind in ipairs({ "clamp", "bounds", "anchors", "parent", "fading" }) do original[kind] = {} end
    local hider

    local function On(key) return ns.db and ns.db[key] == true end

    local function Safe(fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end

    -- Alle Chatfenster (feste und temporäre), jedes nur einmal
    local function ForEachFrame(fn)
        local seen = {}
        local function Visit(frame)
            if type(frame) == "table" and not seen[frame] and frame.GetName then
                seen[frame] = true
                Safe(fn, frame)
            end
        end
        if type(CHAT_FRAMES) == "table" then
            for _, name in pairs(CHAT_FRAMES) do Visit(_G[name]) end
        end
        for i = 1, (NUM_CHAT_WINDOWS or 10) do Visit(_G["ChatFrame" .. i]) end
    end

    local function EditBoxOf(frame)
        local name = frame:GetName()
        return frame.editBox or (name and _G[name .. "EditBox"])
    end

    local function Hider()
        if not hider then
            hider = CreateFrame("Frame")
            hider:Hide()
        end
        return hider
    end

    -- Ein Frame in den versteckten Rahmen schieben und später zurückholen
    local function Reparent(frame, hide)
        if not frame or not frame.SetParent then return end
        if hide then
            if original.parent[frame] == nil then original.parent[frame] = frame:GetParent() or false end
            frame:SetParent(Hider())
        else
            local parent = original.parent[frame]
            if parent then frame:SetParent(parent) end
            original.parent[frame] = nil
        end
    end

    ---------------------------------------------------------------------
    -- 1. Fenster frei verschieben und größer ziehen
    ---------------------------------------------------------------------

    features.chatWindowFree = function(on)
        ForEachFrame(function(frame)
            local clamp, bounds = original.clamp, original.bounds
            if on then
                if clamp[frame] == nil then
                    clamp[frame] = frame.IsClampedToScreen and frame:IsClampedToScreen() or false
                end
                if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end
                if frame.GetResizeBounds and frame.SetResizeBounds then
                    if bounds[frame] == nil then bounds[frame] = { frame:GetResizeBounds() } end
                    local b = bounds[frame]
                    frame:SetResizeBounds(b[1] or 250, b[2] or 120, 1600, 1200)
                end
            else
                if clamp[frame] ~= nil and frame.SetClampedToScreen then frame:SetClampedToScreen(clamp[frame]) end
                local b = bounds[frame]
                if b and frame.SetResizeBounds then frame:SetResizeBounds(b[1] or 250, b[2] or 120, b[3], b[4]) end
                clamp[frame], bounds[frame] = nil, nil
            end
        end)
    end
    frameLevel.chatWindowFree = true

    ---------------------------------------------------------------------
    -- 2. Eingabezeile oben
    ---------------------------------------------------------------------

    local function SavePoints(box)
        if original.anchors[box] then return end
        local points = {}
        for i = 1, box:GetNumPoints() do
            points[i] = { box:GetPoint(i) }
        end
        original.anchors[box] = points
    end

    features.chatEditTop = function(on)
        ForEachFrame(function(frame)
            local box = EditBoxOf(frame)
            if not box or not box.GetNumPoints then return end
            if on then
                SavePoints(box)
                -- Über den Reitern: bei angedockten Fenstern über der Reiterleiste, sonst über dem eigenen Reiter
                local anchor = frame.isDocked and GENERAL_CHAT_DOCK
                    or _G[(frame:GetName() or "") .. "Tab"]
                    or frame
                box:ClearAllPoints()
                box:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -5, 2)
                box:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 5, 2)
            else
                local points = original.anchors[box]
                if points then
                    box:ClearAllPoints()
                    for _, p in ipairs(points) do box:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
                    original.anchors[box] = nil
                end
            end
        end)
    end
    frameLevel.chatEditTop = true

    ---------------------------------------------------------------------
    -- 3. Kein „klebender“ Chatkanal
    ---------------------------------------------------------------------

    local stickyOriginal = {}
    features.chatNoSticky = function(on)
        if type(ChatTypeInfo) ~= "table" then return end
        if on then
            for chatType, info in pairs(ChatTypeInfo) do
                if type(info) == "table" and info.sticky == 1 and stickyOriginal[chatType] == nil then
                    stickyOriginal[chatType] = 1
                    info.sticky = 0
                end
            end
        else
            for chatType, value in pairs(stickyOriginal) do
                if type(ChatTypeInfo[chatType]) == "table" then ChatTypeInfo[chatType].sticky = value end
                stickyOriginal[chatType] = nil
            end
        end
    end

    ---------------------------------------------------------------------
    -- 4. Pfeiltasten in der Eingabezeile ohne Alt
    ---------------------------------------------------------------------

    features.chatArrowKeys = function(on)
        ForEachFrame(function(frame)
            local box = EditBoxOf(frame)
            if box and box.SetAltArrowKeyMode then box:SetAltArrowKeyMode(not on) end
        end)
    end
    frameLevel.chatArrowKeys = true

    ---------------------------------------------------------------------
    -- 5. Chat verblasst nicht
    ---------------------------------------------------------------------

    features.chatNoFade = function(on)
        ForEachFrame(function(frame)
            if frame.SetFading then frame:SetFading(not on) end
        end)
    end
    frameLevel.chatNoFade = true

    ---------------------------------------------------------------------
    -- 6. Klassenfarben in allen Kanälen
    ---------------------------------------------------------------------

    local CLASS_TYPES = {
        "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "ACHIEVEMENT", "GUILD_ACHIEVEMENT", "WHISPER",
        "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
        "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    }
    for i = 1, 10 do CLASS_TYPES[#CLASS_TYPES + 1] = "CHANNEL" .. i end

    -- Die Einstellung speichert der Client selbst; stray merkt sich, was es eingeschaltet hat, um es zurückzunehmen
    features.chatClassColors = function(on)
        if type(SetChatColorNameByClass) ~= "function" or type(ChatTypeInfo) ~= "table" then return end
        if type(ns.db.chatClassColorsSet) ~= "table" then ns.db.chatClassColorsSet = {} end
        local mine = ns.db.chatClassColorsSet
        if on then
            for _, chatType in ipairs(CLASS_TYPES) do
                local info = ChatTypeInfo[chatType]
                if info and not info.colorNameByClass then
                    mine[chatType] = true
                    SetChatColorNameByClass(chatType, true)
                end
            end
        else
            for chatType in pairs(mine) do
                SetChatColorNameByClass(chatType, false)
                mine[chatType] = nil
            end
        end
    end

    ---------------------------------------------------------------------
    -- 7. Raid-Chat in der Gruppenfarbe
    ---------------------------------------------------------------------

    local RAID_PAIRS = { { "RAID", "PARTY" }, { "RAID_LEADER", "PARTY_LEADER" } }

    features.chatRaidColor = function(on)
        if type(ChangeChatColor) ~= "function" or type(ChatTypeInfo) ~= "table" then return end
        if type(ns.db.chatRaidColorPrev) ~= "table" then ns.db.chatRaidColorPrev = {} end
        local prev = ns.db.chatRaidColorPrev
        for _, pair in ipairs(RAID_PAIRS) do
            local raid, party = ChatTypeInfo[pair[1]], ChatTypeInfo[pair[2]]
            if on then
                if raid and party and type(party.r) == "number" and type(party.g) == "number" and type(party.b) == "number" then
                    if not prev[pair[1]] then prev[pair[1]] = { raid.r, raid.g, raid.b } end
                    ChangeChatColor(pair[1], party.r, party.g, party.b)
                end
            elseif prev[pair[1]] then
                local c = prev[pair[1]]
                ChangeChatColor(pair[1], c[1], c[2], c[3])
                prev[pair[1]] = nil
            end
        end
    end

    ---------------------------------------------------------------------
    -- 8. Chatverlauf auf 4096 Zeilen
    ---------------------------------------------------------------------

    features.chatMaxLines = function(on)
        ForEachFrame(function(frame)
            if frame.SetMaxLines then frame:SetMaxLines(on and MAX_LINES_ON or MAX_LINES_OFF) end
        end)
    end
    frameLevel.chatMaxLines = true

    ---------------------------------------------------------------------
    -- 9. Chat nach /reload wiederherstellen
    ---------------------------------------------------------------------

    local function FrameLines(frame, limit, maxLen)
        local lines = {}
        if not frame.GetNumMessages or not frame.GetMessageInfo then return lines end
        local count = frame:GetNumMessages()
        if ns.IsSecret(count) or type(count) ~= "number" then return lines end
        for i = math.max(1, count - limit + 1), count do
            local text, r, g, b = frame:GetMessageInfo(i)
            -- Versiegelte Zeilen (Instanzen) nie anfassen
            if type(text) == "string" and not ns.IsSecret(text) and text ~= "" and (not maxLen or #text <= maxLen) then
                if ns.IsSecret(r) or ns.IsSecret(g) or ns.IsSecret(b) or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
                    r, g, b = 1, 1, 1
                end
                lines[#lines + 1] = { text, math.floor(r * 100 + 0.5) / 100, math.floor(g * 100 + 0.5) / 100, math.floor(b * 100 + 0.5) / 100 }
            end
        end
        return lines
    end

    local function IsCombatLog(frame)
        return COMBATLOG ~= nil and frame == COMBATLOG
    end

    ns.On("PLAYER_LOGOUT", function()
        if not On("chatRestore") then return end
        local frames = {}
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local frame = _G["ChatFrame" .. i]
            if frame and not IsCombatLog(frame) then
                local ok, lines = pcall(FrameLines, frame, RESTORE_LINES, RESTORE_MAX_LEN)
                if ok and #lines > 0 then frames[frame:GetName()] = lines end
            end
        end
        ns.db.chatHistory = { time = time(), frames = frames }
    end)

    ns.On("PLAYER_ENTERING_WORLD", function(_, isReloadingUi)
        if not isReloadingUi or not On("chatRestore") then return end
        local history = ns.db.chatHistory
        ns.db.chatHistory = nil
        if type(history) ~= "table" or type(history.frames) ~= "table" or type(history.time) ~= "number" then return end
        if time() - history.time > RESTORE_MAX_AGE then return end
        local dim = ns.Colors.textDim
        for name, lines in pairs(history.frames) do
            local frame = _G[name]
            if frame and frame.AddMessage and type(lines) == "table" and not IsCombatLog(frame) then
                for _, line in ipairs(lines) do
                    if type(line[1]) == "string" then
                        frame:AddMessage(line[1], tonumber(line[2]) or 1, tonumber(line[3]) or 1, tonumber(line[4]) or 1)
                    end
                end
                frame:AddMessage(L["— Chat vor dem Neuladen —"], dim[1], dim[2], dim[3])
            end
        end
    end)

    features.chatRestore = function(on)
        if not on then ns.db.chatHistory = nil end
    end

    ---------------------------------------------------------------------
    -- 10. Kopierbares Fenster mit dem Chatverlauf
    ---------------------------------------------------------------------

    local copyWindow

    local function PlainText(text)
        text = text:gsub("|K.-|k", "")
        text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
        text = text:gsub("|cn.-:", "")
        text = text:gsub("|r", "")
        text = text:gsub("|H.-|h(.-)|h", "%1")
        text = text:gsub("|T.-|t", "")
        text = text:gsub("|A.-|a", "")
        text = text:gsub("|n", " ")
        text = text:gsub("||", "|")
        return text
    end

    local function WindowName(frame)
        local ok, name = pcall(GetChatWindowInfo, frame:GetID())
        if ok and type(name) == "string" and not ns.IsSecret(name) and name ~= "" then return name end
        return L["Chat"]
    end

    local function BuildCopyWindow()
        local Style = ns.Style
        local C = ns.Colors
        local f = CreateFrame("Frame", "strayChatCopy", UIParent)
        f:SetSize(660, 440)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:Hide()
        Style.Fill(f, "window")
        Style.Border(f, { size = 3, corners = false })
        if UISpecialFrames then table.insert(UISpecialFrames, "strayChatCopy") end -- Esc schließt

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(Style.Font(), 14, "")
        f.title:SetTextColor(C.accentText[1], C.accentText[2], C.accentText[3], 1)
        f.title:SetPoint("TOPLEFT", 16, -12)

        f.hint = f:CreateFontString(nil, "OVERLAY")
        f.hint:SetFont(Style.Font(), 12, "")
        f.hint:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1)
        f.hint:SetPoint("BOTTOMLEFT", 16, 14)

        local close = CreateFrame("Button", nil, f)
        close:SetSize(80, 24)
        close:SetPoint("BOTTOMRIGHT", -14, 10)
        Style.Fill(close, "panel")
        Style.Border(close, { size = 3, corners = false })
        close.text = close:CreateFontString(nil, "OVERLAY")
        close.text:SetFont(Style.Font(), 12, "")
        close.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        close.text:SetPoint("CENTER")
        close:SetScript("OnClick", function() f:Hide() end)
        f.close = close

        local scroll = CreateFrame("ScrollFrame", nil, f)
        scroll:SetPoint("TOPLEFT", 14, -40)
        scroll:SetPoint("BOTTOMRIGHT", -14, 44)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local value = self:GetVerticalScroll() - delta * 48
            self:SetVerticalScroll(math.max(0, math.min(value, self:GetVerticalScrollRange())))
        end)
        f.scroll = scroll

        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFont(Style.Font(), 13, "")
        box:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        box:SetTextInsets(4, 4, 4, 4)
        box:SetWidth(620)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        box:SetScript("OnTextChanged", function(self, userInput)
            -- Nur zum Markieren und Kopieren: Tippen ändert nichts
            if userInput and f.shownText and self:GetText() ~= f.shownText then
                self:SetText(f.shownText)
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(box)
        f.box = box

        f.measure = f:CreateFontString(nil, "OVERLAY")
        f.measure:SetFont(Style.Font(), 13, "")
        f.measure:SetWidth(612)
        f.measure:Hide()
        return f
    end

    local function ShowCopyWindow(frame)
        frame = frame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if not frame then return end
        if not copyWindow then copyWindow = BuildCopyWindow() end
        local f = copyWindow

        local lines = FrameLines(frame, COPY_LINES)
        local out = {}
        for _, line in ipairs(lines) do out[#out + 1] = PlainText(line[1]) end
        local text = table.concat(out, "\n")
        if text == "" then text = L["(Keine Chatzeilen gefunden.)"] end

        f.shownText = text
        f.title:SetText(L("Chatverlauf – %s", WindowName(frame)))
        f.hint:SetText(L["Alles markieren mit Strg+A, kopieren mit Strg+C. Es erscheinen die letzten 1000 Zeilen."])
        f.close.text:SetText(L["Schließen"])
        f.box:SetText(text)
        f.measure:SetText(text)
        local okHeight, height = pcall(f.measure.GetStringHeight, f.measure)
        if not okHeight or type(height) ~= "number" then height = #out * 16 end
        f.box:SetHeight(math.max(height + 12, f.scroll:GetHeight()))
        f:Show()
        f.box:ClearFocus()
        C_Timer.After(0.05, function()
            if f:IsShown() then f.scroll:SetVerticalScroll(f.scroll:GetVerticalScrollRange()) end
        end)
    end

    ns.slashCommands = ns.slashCommands or {}
    ns.slashCommands.chat = function() ShowCopyWindow() end

    -- Strg+Klick auf einen Chat-Reiter (Hook läuft nur bei eingeschalteter Option)
    local hookedTabs = {}
    features.chatCopy = function(on)
        if not on then return end
        ForEachFrame(function(frame)
            local tab = _G[(frame:GetName() or "") .. "Tab"]
            if tab and tab.HookScript and not hookedTabs[tab] then
                hookedTabs[tab] = true
                tab:HookScript("OnClick", function()
                    if On("chatCopy") and IsControlKeyDown() then ShowCopyWindow(frame) end
                end)
            end
        end)
    end
    frameLevel.chatCopy = true

    ---------------------------------------------------------------------
    -- 11. Chat-Spam filtern
    ---------------------------------------------------------------------

    -- Formattext aus Blizzards Globalstrings („%s hat …“) in ein Suchmuster verwandeln
    local patternCache = {}
    local function PatternsFor(names)
        local key = table.concat(names, ",")
        if patternCache[key] then return patternCache[key] end
        local list = {}
        for _, name in ipairs(names) do
            local text = _G[name]
            if type(text) == "string" and text ~= "" then
                text = text:gsub("%%%d?%$?s", "\1")
                text = text:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
                text = text:gsub("\1", ".+")
                list[#list + 1] = "^" .. text .. "$"
            end
        end
        patternCache[key] = list
        return list
    end

    local function MatchesAny(msg, patterns)
        for _, pattern in ipairs(patterns) do
            if msg:find(pattern) then return true end
        end
        return false
    end

    local DUEL_NAMES = { "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }
    local DRUNK_NAMES = {
        "DRUNK_MESSAGE_OTHER1", "DRUNK_MESSAGE_OTHER2", "DRUNK_MESSAGE_OTHER3", "DRUNK_MESSAGE_OTHER4",
        "DRUNK_MESSAGE_ITEM_OTHER1", "DRUNK_MESSAGE_ITEM_OTHER2", "DRUNK_MESSAGE_ITEM_OTHER3", "DRUNK_MESSAGE_ITEM_OTHER4",
    }

    local function IsKnownSender(author, guid)
        if ns.IsSecret(author) or ns.IsSecret(guid) then return true end -- im Zweifel nichts blocken
        if type(guid) == "string" and guid ~= "" then
            if guid == UnitGUID("player") then return true end
            if C_FriendList and C_FriendList.IsFriend then
                local ok, friend = pcall(C_FriendList.IsFriend, guid)
                if ok and friend == true then return true end
            end
            if IsGuildMember then
                local ok, member = pcall(IsGuildMember, guid)
                if ok and member == true then return true end
            end
        end
        if type(author) == "string" and author ~= "" then
            local short = author:match("^([^%-]+)") or author
            if UnitInParty(short) or UnitInRaid(short) then return true end
        end
        return false
    end

    local function SpellLinkFilter(_, _, msg, author, _, _, _, _, _, _, _, _, _, guid)
        if not On("chatBlockSpellLinks") or type(msg) ~= "string" or ns.IsSecret(msg) then return false end
        if not msg:find("|Hspell:", 1, true) then return false end
        if IsKnownSender(author, guid) then return false end
        return true
    end

    local function SystemSpamFilter(_, _, msg)
        if type(msg) ~= "string" or ns.IsSecret(msg) then return false end
        local me = UnitName("player")
        if me and msg:find(me, 1, true) then return false end -- eigene Duelle und eigener Zustand bleiben
        if On("chatBlockDuels") and MatchesAny(msg, PatternsFor(DUEL_NAMES)) then return true end
        if On("chatBlockDrunk") and MatchesAny(msg, PatternsFor(DRUNK_NAMES)) then return true end
        return false
    end

    for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL" }) do
        if AddMessageFilter then pcall(AddMessageFilter, event, SpellLinkFilter) end
    end
    for _, event in ipairs({ "CHAT_MSG_SYSTEM", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_EMOTE", "CHAT_MSG_COMBAT_MISC_INFO" }) do
        if AddMessageFilter then pcall(AddMessageFilter, event, SystemSpamFilter) end
    end

    ---------------------------------------------------------------------
    -- 12. Kampflog-Reiter und Chat-Knöpfe ausblenden
    ---------------------------------------------------------------------

    local function CombatLogTab()
        if not COMBATLOG or not COMBATLOG.GetName then return nil end
        return _G[COMBATLOG:GetName() .. "Tab"]
    end

    local function HideCombatTab()
        local tab = CombatLogTab()
        if not tab then return end
        tab:SetAlpha(0)
        tab:EnableMouse(false)
    end

    features.chatHideCombatTab = function(on)
        local tab = CombatLogTab()
        if not tab then return end
        if on then
            HideCombatTab()
        else
            tab:EnableMouse(true)
            if FCFTab_UpdateAlpha then FCFTab_UpdateAlpha(COMBATLOG) else tab:SetAlpha(1) end
        end
    end

    local BUTTON_NAMES = { "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton" }

    local function ApplyButtons(on)
        for _, name in ipairs(BUTTON_NAMES) do Reparent(_G[name], on) end
        ForEachFrame(function(frame)
            Reparent(frame.ScrollBar, on)
            Reparent(frame.ScrollToBottomButton, on)
            Reparent(frame.buttonFrame, on)
        end)
    end
    features.chatHideButtons = ApplyButtons
    frameLevel.chatHideButtons = true

    ---------------------------------------------------------------------
    -- Anwenden
    ---------------------------------------------------------------------

    local function Apply(key, on)
        local fn = features[key]
        if fn then Safe(fn, on) end
    end

    local function ApplyFrameLevel()
        for key in pairs(frameLevel) do
            if On(key) then Apply(key, true) end
        end
    end

    local reapplyQueued
    local function ReapplySoon()
        if reapplyQueued then return end
        reapplyQueued = true
        C_Timer.After(0, function()
            reapplyQueued = false
            ApplyFrameLevel()
        end)
    end

    local hooksDone
    local function InstallHooks()
        if hooksDone then return end
        hooksDone = true
        -- Neue Fenster (Flüstern, eigene Reiter) bekommen dieselben Einstellungen
        for _, name in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow" }) do
            if type(_G[name]) == "function" then hooksecurefunc(name, ReapplySoon) end
        end
        -- Docken ändert, worüber die Eingabezeile hängt
        for _, name in ipairs({ "FCF_DockFrame", "FCF_UnDockFrame" }) do
            if type(_G[name]) == "function" then
                hooksecurefunc(name, function()
                    if On("chatEditTop") then ReapplySoon() end
                end)
            end
        end
        -- Blizzard setzt die Reiterhelligkeit häufig neu
        for _, name in ipairs({ "FCFTab_UpdateAlpha", "FCF_FadeInChatFrame", "FCF_FadeOutChatFrame", "FCFDock_UpdateTabs" }) do
            if type(_G[name]) == "function" then
                hooksecurefunc(name, function()
                    if On("chatHideCombatTab") then HideCombatTab() end
                end)
            end
        end
    end

    ns.On("PLAYER_LOGIN", function()
        local any = false
        for key in pairs(features) do
            if On(key) then any = true end
        end
        if not any then return end
        InstallHooks()
        -- Blizzard baut die Chatfenster erst kurz nach dem Login fertig auf
        C_Timer.After(1, function()
            for key in pairs(features) do
                if On(key) and key ~= "chatRestore" then Apply(key, true) end
            end
        end)
    end)

    ---------------------------------------------------------------------
    -- Optionen
    ---------------------------------------------------------------------

    local function Add(area, key, label, tooltip, keywords)
        ns.defaults[key] = false
        ns.AddOption(1, area, {
            key = key,
            label = label,
            tooltip = tooltip,
            keywords = keywords,
            set = function(value)
                ns.db[key] = value and true or false
                if value then InstallHooks() end
                Apply(key, value and true or false)
            end,
        })
    end

    -- Bereich „Chat-Fenster“
    Add(WIN, "chatWindowFree", L["Chatfenster frei verschieben und größer ziehen"],
        L["Das Chatfenster lässt sich über den Bildschirmrand hinaus schieben und größer aufziehen als bei Blizzard. Das Fenster „Allgemein“ stellst du im Bearbeitungsmodus von Blizzard ein.\nAus: Blizzards Grenzen gelten wieder."],
        { "chat", "fenster", "verschieben", "größe", "vergrößern", "rand", "move", "resize", "window", "bigger", "clamp", "screen" })
    Add(WIN, "chatEditTop", L["Eingabezeile oben"],
        L["Die Zeile, in die du tippst, steht über dem Chatfenster statt darunter.\nAus: wieder unten."],
        { "chat", "eingabe", "eingabezeile", "oben", "editbox", "input", "top" })
    Add(WIN, "chatNoSticky", L["Kein „klebender“ Chatkanal"],
        L["Nach dem Senden springt die Eingabezeile wieder auf „Sagen“, statt im letzten Kanal (Gruppe, Gilde, Flüstern …) zu bleiben.\nAus: Blizzards Verhalten."],
        { "chat", "kanal", "sticky", "klebend", "sagen", "channel", "say", "stay" })
    Add(WIN, "chatArrowKeys", L["Pfeiltasten in der Eingabezeile ohne Alt"],
        L["Links und Rechts bewegen den Cursor in der Eingabezeile, Hoch und Runter holen frühere Eingaben – ohne dass du Alt halten musst.\nAus: Blizzards Verhalten (mit Alt)."],
        { "chat", "pfeiltasten", "alt", "cursor", "arrow", "keys", "editbox" })
    Add(WIN, "chatNoFade", L["Chat verblasst nicht"],
        L["Chatzeilen bleiben sichtbar, statt nach einer Weile auszublenden.\nAus: Blizzards Ausblenden gilt wieder."],
        { "chat", "verblassen", "ausblenden", "fade", "fading", "hide", "text" })
    Add(WIN, "chatMaxLines", L["Chatverlauf auf 4096 Zeilen erhöhen"],
        L["Das Chatfenster merkt sich 4096 statt 128 Zeilen zum Zurückscrollen. Braucht etwas mehr Speicher.\nAus: wieder 128 Zeilen; ältere Zeilen gehen dabei verloren."],
        { "chat", "verlauf", "zeilen", "history", "lines", "scroll", "scrollback" })
    Add(WIN, "chatHideCombatTab", L["Kampflog-Reiter ausblenden"],
        L["Der Reiter „Kampflog“ wird unsichtbar und nicht mehr anklickbar. Die Lücke in der Reiterleiste bleibt.\nAus: Reiter erscheint wieder."],
        { "chat", "kampflog", "reiter", "tab", "combat", "log", "combatlog" })
    Add(WIN, "chatHideButtons", L["Chat-Knöpfe ausblenden"],
        L["Blendet das Chat-Menü, den Kanal-/Social-Knopf (Schnellbeitritt) und die Scrollleiste samt „Nach unten“-Knopf aus. Scrollen mit dem Mausrad bleibt möglich.\nAus: alles wieder da."],
        { "chat", "knöpfe", "buttons", "menü", "menu", "social", "scrollleiste", "scrollbar", "kanal", "channel", "quickjoin" })

    -- Bereich „Chat“
    Add("Chat", "chatClassColors", L["Klassenfarben für Namen in allen Kanälen"],
        L["Spielernamen im Chat erscheinen in der Klassenfarbe: Sagen, Rufen, Gruppe, Raid, Gilde, Flüstern, Instanz und Kanäle 1–10.\nAus: stray nimmt nur zurück, was es selbst eingeschaltet hat."],
        { "chat", "klassenfarben", "namen", "farbe", "class", "colors", "names", "color" })
    Add("Chat", "chatRaidColor", L["Raid-Chat in der Gruppenfarbe"],
        L["Raid- und Raidleiter-Nachrichten haben dieselbe Farbe wie Gruppen- und Gruppenleiter-Nachrichten.\nAus: die vorherige Raid-Farbe kommt zurück."],
        { "chat", "raid", "gruppe", "farbe", "party", "color", "colour" })
    Add("Chat", "chatRestore", L["Chat nach /reload wiederherstellen"],
        L["Nach /reload kommen die letzten Zeilen jedes Chatfensters zurück (bis zu 60, höchstens 10 Minuten alt). Nur normale Zeilen, nichts aus versiegelten Instanzen.\nGespeichert werden sie beim Neuladen und Abmelden."],
        { "chat", "wiederherstellen", "reload", "neuladen", "verlauf", "restore", "history", "ui" })
    Add("Chat", "chatCopy", L["Chatverlauf kopieren (Strg+Klick auf den Reiter)"],
        L["Strg+Klick auf einen Chat-Reiter öffnet ein Fenster mit den letzten 1000 Zeilen zum Markieren und Kopieren. Den Befehl /stray chat gibt es immer, auch bei „aus“."],
        { "chat", "kopieren", "verlauf", "fenster", "strg", "copy", "history", "window", "ctrl" })
    Add("Chat", "chatBlockSpellLinks", L["Zauber-Links von Fremden filtern"],
        L["Nachrichten mit Zauber-Links von Spielern, die weder Freund noch Gildenmitglied noch in deiner Gruppe sind, erscheinen nicht in Sagen, Rufen und Kanälen."],
        { "chat", "spam", "filter", "zauber", "links", "fremde", "spell", "strangers", "block" })
    Add("Chat", "chatBlockDuels", L["Duell-Meldungen filtern"],
        L["Blendet Meldungen über Duelle anderer Spieler aus („… hat … im Duell besiegt“). Deine eigenen Duelle bleiben sichtbar."],
        { "chat", "spam", "filter", "duell", "duel", "winner", "block" })
    Add("Chat", "chatBlockDrunk", L["„Betrunken“-Meldungen filtern"],
        L["Blendet die Meldungen aus, wenn andere Spieler betrunken werden oder sich übergeben. Deine eigenen bleiben sichtbar."],
        { "chat", "spam", "filter", "betrunken", "alkohol", "drunk", "block" })
end
