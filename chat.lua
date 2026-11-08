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
