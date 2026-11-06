-- stray – Chat: Webadressen anklickbar und kopierbar machen

local _, ns = ...

ns.AddOption(1, "Chat", {
    key = "chatLinks",
    label = "Links kopierbar",
    tooltip = "Webadressen im Chat werden blau und anklickbar. Ein Klick öffnet ein Feld, aus dem du den Link mit Strg+C kopierst.",
})

local LINK_COLOR = "|cff4fb3ff"

local function MakeLink(url)
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
    return lead .. MakeLink(core) .. trail
end

local function Filter(_, _, msg, ...)
    if not ns.db or not ns.db.chatLinks or type(msg) ~= "string" then return false end
    local changed = false
    local newMsg = msg:gsub("%S+", function(word)
        local link = ConvertWord(word)
        if link then changed = true end
        return link
    end)
    if changed then return false, newMsg, ... end
    return false
end

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
}

for _, event in ipairs(CHAT_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, Filter)
end

---------------------------------------------------------------------------
-- Kopierfeld
---------------------------------------------------------------------------

local function GetEditBox(popup)
    return popup.editBox or popup.EditBox or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "EditBox"])
end

StaticPopupDialogs["STRAY_COPY_URL"] = {
    text = "Link kopieren mit Strg+C:",
    button1 = CLOSE or "Schließen",
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
        local popup = box:GetParent()
        if popup.data and box:GetText() ~= popup.data then
            box:SetText(popup.data)
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
    if ItemRefTooltip then ItemRefTooltip:Hide() end
    local popup = StaticPopup_Show("STRAY_COPY_URL", nil, nil, url)
    -- Absicherung, falls der Client „data“ erst nach OnShow setzt
    if popup then
        popup.data = url
        local box = GetEditBox(popup)
        if box then
            box:SetText(url)
            box:HighlightText()
            box:SetFocus()
        end
    end
end

-- Klicks auf „url:“-Links abfangen, bevor WoW sie als unbekannten Linktyp anzeigen will.
-- Nur der Link-Tooltip wird angepasst, nicht der Chat selbst.
local function WrapTooltip(method)
    if not ItemRefTooltip or not ItemRefTooltip[method] then return end
    local original = ItemRefTooltip[method]
    ItemRefTooltip[method] = function(self, link, ...)
        if type(link) == "string" and link:sub(1, 4) == "url:" then
            ShowCopy(link:sub(5))
            return
        end
        return original(self, link, ...)
    end
end

WrapTooltip("SetHyperlink")
WrapTooltip("ItemRefSetHyperlink")
