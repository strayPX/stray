-- stray – Ausblenden-und-Text (Phase 2, Leatrix-Funktionen nachgebaut)
-- Bereich „Ausblenden“: Zonentext, Porträt-Zahlen, Tasten-/Makrotext, Talking Head, Alerts,
-- Boss-Banner, Gryphon-Verzierungen, Ruhe-Animation, Raidgruppen-Titel.
-- Bereich „Text“: größere Schrift für Post, Quests, Bücher.
-- Alles Standard aus; bei „aus“ bleibt Blizzards Verhalten unberührt. Es werden keine Felder auf
-- Blizzard-Frames geschrieben: nur Hooks, Event-Abmeldung, Alpha/Hide auf nicht geschützten Elementen.

local _, ns = ...
local L = ns.L

local function On(key) return ns.db and ns.db[key] and true or false end

for _, key in ipairs({
    "hideZoneText", "hidePortraitNumbers", "hideHotkeys", "hideMacroNames", "hideTalkingHead",
    "hideAlerts", "hideBossBanner", "hideGryphons", "hideRestAnim", "hideRaidGroupTitles",
    "mailTextLarge", "questTextLarge", "bookTextLarge",
}) do
    ns.defaults[key] = false
end
ns.defaults.mailTextSize = 16
ns.defaults.questTextSize = 16
ns.defaults.bookTextSize = 16

local function Safe(fn, ...)
    local ok = pcall(fn, ...)
    return ok
end

---------------------------------------------------------------------------
-- 1. Zonentext
---------------------------------------------------------------------------

local zoneHooked = {}
local function ApplyZoneText()
    if not On("hideZoneText") then return end
    for _, name in ipairs({ "ZoneTextFrame", "SubZoneTextFrame" }) do
        local f = _G[name]
        if f and f.HookScript and not zoneHooked[name] then
            zoneHooked[name] = true
            f:HookScript("OnShow", function(self)
                if On("hideZoneText") then self:Hide() end
            end)
        end
        if f and f:IsShown() then f:Hide() end
    end
end

---------------------------------------------------------------------------
-- 2. Schadens-/Heilungszahlen im Porträt (Spieler, Begleiter)
---------------------------------------------------------------------------

local feedbackHooked
local function FeedbackTexts()
    local list = {}
    local ok, text = pcall(function()
        return PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator.HitText
    end)
    if ok and text then list[#list + 1] = text end
    if PetHitIndicator then list[#list + 1] = PetHitIndicator end
    return list
end

local function ApplyPortraitNumbers()
    if not On("hidePortraitNumbers") then return end
    if not feedbackHooked and CombatFeedback_OnCombatEvent then
        feedbackHooked = true
        hooksecurefunc("CombatFeedback_OnCombatEvent", function(self)
            if not On("hidePortraitNumbers") then return end
            local text = self and self.feedbackText
            if text then
                text:SetText("")
                text:Hide()
            end
        end)
    end
    for _, text in ipairs(FeedbackTexts()) do
        text:SetText("")
        text:Hide()
    end
end

---------------------------------------------------------------------------
-- 3. Tastenkürzel- und Makrotext auf den Aktionsleisten
---------------------------------------------------------------------------

local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "MultiBar8Button",
}

-- Wirkt nur über Alpha der Beschriftung, damit Blizzards Update (Show/Hide/SetText) ungestört bleibt
local function ForButtons(prefixes, count, suffix, alpha)
    for _, prefix in ipairs(prefixes) do
        for i = 1, count do
            local text = _G[prefix .. i .. suffix]
            if text and text.SetAlpha then text:SetAlpha(alpha) end
        end
    end
end

local hotkeysTouched, macrosTouched
local function ApplyHotkeys()
    local hide = On("hideHotkeys")
    if not hide and not hotkeysTouched then return end
    hotkeysTouched = hide
    local alpha = hide and 0 or 1
    ForButtons(BAR_PREFIXES, 12, "HotKey", alpha)
    ForButtons({ "PetActionButton", "StanceButton" }, 10, "HotKey", alpha)
end

local function ApplyMacroNames()
    local hide = On("hideMacroNames")
    if not hide and not macrosTouched then return end
    macrosTouched = hide
    ForButtons(BAR_PREFIXES, 12, "Name", hide and 0 or 1)
end

---------------------------------------------------------------------------
-- 4. Talking Head, 5. Alerts, 6. Boss-Banner (über Ereignisse bzw. Blizzards Schalter)
---------------------------------------------------------------------------

local talkingHeadOff
local function ApplyTalkingHead()
    local f = _G.TalkingHeadFrame
    if not f then return end
    if On("hideTalkingHead") then
        if not talkingHeadOff then
            talkingHeadOff = true
            f:UnregisterEvent("TALKINGHEAD_REQUESTED")
        end
        if f:IsShown() and f.CloseImmediately then Safe(f.CloseImmediately, f) end
    elseif talkingHeadOff then
        talkingHeadOff = false
        f:RegisterEvent("TALKINGHEAD_REQUESTED")
    end
end

local alertsOff
local function ApplyAlerts()
    local f = _G.AlertFrame
    if not f or not f.SetAlertsEnabled then return end
    if On("hideAlerts") then
        alertsOff = true
        Safe(f.SetAlertsEnabled, f, false, "stray")
    elseif alertsOff then
        alertsOff = false
        Safe(f.SetAlertsEnabled, f, true, "stray")
    end
end

local bossOff
local function ApplyBossBanner()
    local f = _G.BossBanner
    if not f then return end
    if On("hideBossBanner") then
        bossOff = true
        f:UnregisterEvent("BOSS_KILL")
        f:UnregisterEvent("ENCOUNTER_LOOT_RECEIVED")
        if f:IsShown() and f.StopBanner then Safe(f.StopBanner, f) end
    elseif bossOff then
        bossOff = false
        f:RegisterEvent("BOSS_KILL")
        f:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
    end
end

---------------------------------------------------------------------------
-- 7. Gryphon-Verzierungen der Hauptleiste
---------------------------------------------------------------------------

local gryphonsTouched
local function ApplyGryphons()
    local hide = On("hideGryphons")
    if not hide and not gryphonsTouched then return end
    local ok, caps = pcall(function() return MainActionBar.EndCaps end)
    if not ok or not caps then return end
    gryphonsTouched = hide
    for _, key in ipairs({ "LeftEndCap", "RightEndCap" }) do
        local cap = caps[key]
        local tex = cap and cap.Texture
        if tex and tex.SetAlpha then tex:SetAlpha(hide and 0 or 1) end
    end
end

---------------------------------------------------------------------------
-- 8. Ruhe-Animation („Zzz“) und Raidgruppen-Titel
---------------------------------------------------------------------------

local restHooked
local function RestLoop()
    local ok, loop = pcall(function()
        return PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop
    end)
    return ok and loop or nil
end

local function ApplyRestAnim()
    if not On("hideRestAnim") then return end
    if not restHooked and PlayerFrame_UpdatePlayerRestLoop then
        restHooked = true
        hooksecurefunc("PlayerFrame_UpdatePlayerRestLoop", function()
            if not On("hideRestAnim") then return end
            local loop = RestLoop()
            if loop then loop:Hide() end
        end)
    end
    local loop = RestLoop()
    if loop then loop:Hide() end
end

local titlesHooked, titlesTouched
local function ApplyGroupTitles()
    local hide = On("hideRaidGroupTitles")
    if hide and not titlesHooked and CompactRaidGroup_InitializeForGroup then
        titlesHooked = true
        hooksecurefunc("CompactRaidGroup_InitializeForGroup", function(frame)
            if On("hideRaidGroupTitles") and frame and frame.title then frame.title:SetAlpha(0) end
        end)
    end
    if not hide and not titlesTouched then return end
    titlesTouched = hide
    for i = 1, 8 do
        local frame = _G["CompactRaidGroup" .. i]
        if frame and frame.title then frame.title:SetAlpha(hide and 0 or 1) end
    end
end

---------------------------------------------------------------------------
-- 9. Textgröße: Post, Quests, Bücher
---------------------------------------------------------------------------

local function ClampSize(value)
    value = tonumber(value) or 16
    if value < 10 then value = 10 elseif value > 28 then value = 28 end
    return math.floor(value + 0.5)
end

-- Post: gemeinsame Schriftart von Lese- und Schreibfeld
local mailOriginal
local function ApplyMail()
    local font = _G.MailTextFontNormal
    if not font or not font.SetFont then return end
    if not mailOriginal and not On("mailTextLarge") then return end
    if not mailOriginal then
        local path, size, flags = font:GetFont()
        if not path then return end
        mailOriginal = { path, size, flags }
    end
    if On("mailTextLarge") then
        font:SetFont(mailOriginal[1], ClampSize(ns.db.mailTextSize), mailOriginal[3])
    else
        font:SetFont(mailOriginal[1], mailOriginal[2], mailOriginal[3])
    end
end

-- Quests: Beschreibung, Ziele, Belohnungstext, Begrüßung und Fortschritt je Textfeld
local QUEST_TEXTS = { "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoRewardText", "QuestProgressText", "GreetingText" }
local questTouched
local function ApplyQuest()
    local large = On("questTextLarge")
    if not large and not questTouched then return end
    if not _G.QuestFont then return end
    local path, _, flags = QuestFont:GetFont()
    if not path then return end
    questTouched = large
    for _, name in ipairs(QUEST_TEXTS) do
        local text = _G[name]
        if text and text.SetFont then
            if large then
                text:SetFont(path, ClampSize(ns.db.questTextSize), flags)
            else
                text:SetFontObject(QuestFont)
            end
        end
    end
end

-- Bücher: eigene Schriftart für die Seitentexte, wird je Buch nach Blizzards Zuweisung gesetzt
local bookFont, bookHooked, bookTouched
local function ApplyBookFont()
    local page = _G.ItemTextPageText
    if not page or not page.SetFontObject or not _G.QuestFont then return end
    local large = On("bookTextLarge")
    if not large and not bookTouched then return end
    bookTouched = large
    local tags = { "P" }
    local okMat, material = pcall(ItemTextGetMaterial)
    if okMat and material ~= "ParchmentLarge" then tags = { "P", "H1", "H2", "H3" } end
    if large then
        if not bookFont then bookFont = CreateFont("strayBookTextFont") end
        local path, _, flags = QuestFont:GetFont()
        if not path then return end
        bookFont:SetFont(path, ClampSize(ns.db.bookTextSize), flags)
        for _, tag in ipairs(tags) do page:SetFontObject(tag, bookFont) end
    else
        for _, tag in ipairs(tags) do page:SetFontObject(tag, QuestFont) end
    end
end

local function HookBook()
    local frame = _G.ItemTextFrame
    if bookHooked or not frame or not frame.HookScript then return end
    bookHooked = true
    frame:HookScript("OnEvent", function(_, event)
        if event == "ITEM_TEXT_BEGIN" and On("bookTextLarge") then ApplyBookFont() end
    end)
end

local function ApplyBook()
    HookBook()
    ApplyBookFont()
end

---------------------------------------------------------------------------
-- Gesamt
---------------------------------------------------------------------------

local function ApplyAll()
    if not ns.db then return end
    Safe(ApplyZoneText)
    Safe(ApplyPortraitNumbers)
    Safe(ApplyHotkeys)
    Safe(ApplyMacroNames)
    Safe(ApplyTalkingHead)
    Safe(ApplyAlerts)
    Safe(ApplyBossBanner)
    Safe(ApplyGryphons)
    Safe(ApplyRestAnim)
    Safe(ApplyGroupTitles)
    Safe(ApplyMail)
    Safe(ApplyQuest)
    Safe(ApplyBook)
end

ns.On("PLAYER_LOGIN", ApplyAll)
ns.On("PLAYER_ENTERING_WORLD", ApplyAll)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_UIPanels_Game" or name == "Blizzard_MailFrame" or name == "Blizzard_ActionBar"
        or name == "Blizzard_CompactRaidFrames" then
        ApplyAll()
    end
end)

---------------------------------------------------------------------------
-- Optionen: Ausblenden
---------------------------------------------------------------------------

local function Toggle(key, apply)
    return function(value)
        ns.db[key] = value
        Safe(apply)
    end
end

ns.AddOption(1, "Ausblenden", {
    key = "hideZoneText",
    label = L["Zonentext ausblenden"],
    tooltip = L["Die großen Gebietsnamen beim Betreten einer Zone oder eines Unterbereichs erscheinen nicht mehr."],
    keywords = { "zone", "zonentext", "gebiet", "gebietsname", "subzone", "zone text", "area name" },
    set = Toggle("hideZoneText", ApplyZoneText),
})

ns.AddOption(1, "Ausblenden", {
    key = "hidePortraitNumbers",
    label = L["Schadenszahlen im Porträt ausblenden"],
    tooltip = L["Die großen Schadens- und Heilungszahlen, die im Porträt von Spieler und Begleiter aufblitzen, verschwinden. Der Lebensbalken bleibt unverändert."],
    keywords = { "porträt", "portrait", "schaden", "heilung", "zahlen", "damage", "healing", "numbers", "hit", "kampftext", "combat feedback", "begleiter", "pet" },
    set = Toggle("hidePortraitNumbers", ApplyPortraitNumbers),
})

ns.AddOption(1, "Ausblenden", {
    key = "hideHotkeys",
    label = L["Tastenkürzel auf Aktionsleisten ausblenden"],
    tooltip = L["Blendet die Tastenbeschriftung (z. B. „1“, „S-F“) auf Blizzards Aktionsleisten, Begleiter- und Haltungsleiste aus. Die Belegung selbst bleibt erhalten."],
    keywords = { "tastenkürzel", "taste", "hotkey", "keybind", "keybinding", "binding", "aktionsleiste", "action bar", "beschriftung", "text" },
    set = Toggle("hideHotkeys", ApplyHotkeys),
})

ns.AddOption(1, "Ausblenden", {
    key = "hideMacroNames",
    label = L["Makronamen auf Aktionsleisten ausblenden"],
    tooltip = L["Blendet die Makronamen auf den Knöpfen von Blizzards Aktionsleisten aus. Die Makros bleiben unverändert."],
    keywords = { "makro", "macro", "makroname", "macro name", "name", "aktionsleiste", "action bar", "beschriftung" },
    set = Toggle("hideMacroNames", ApplyMacroNames),
})

ns.AddOption(1, "Ausblenden", {
    key = "hideTalkingHead",
    label = L["„Talking Head“-Fenster ausblenden"],
    tooltip = L["Das Fenster mit dem sprechenden NPC-Kopf erscheint nicht mehr. Ein laufendes Fenster wird sofort geschlossen."],
    keywords = { "talking head", "sprechender kopf", "npc", "dialog", "sprachausgabe", "voice", "fenster", "cutscene" },
    set = Toggle("hideTalkingHead", ApplyTalkingHead),
})

ns.AddOption(1, "Ausblenden", {
    key = "hideAlerts",
    label = L["Ereignis-Banner (Alerts) ausblenden"],
    tooltip = L["Blendet Blizzards Hinweis-Banner am Bildschirmrand aus: Erfolge, Beute, Währungen, neue Rezepte, Reittiere, Haustiere, Spielzeuge u. a. Fehler und Warnungen sind nicht betroffen.\n\nBeim Ausschalten erscheinen höchstens die wenigen zwischenzeitlich gesammelten Banner nachträglich."],
    keywords = { "alert", "alerts", "toast", "banner", "erfolg", "achievement", "beute", "loot", "währung", "currency", "ereignis", "hinweis" },
    set = Toggle("hideAlerts", ApplyAlerts),
})

ns.AddOption(1, "Ausblenden", {
    key = "hideBossBanner",
    label = L["Boss-Banner ausblenden"],
    tooltip = L["Das große Banner nach einem Bosskampf („Besiegt“) und die dazugehörige Beuteanzeige erscheinen nicht mehr. Die Beute selbst bleibt unverändert."],
    keywords = { "boss", "banner", "besiegt", "defeated", "beute", "loot", "encounter", "begegnung", "schlachtzug", "raid" },
    set = Toggle("hideBossBanner", ApplyBossBanner),
})

ns.AddOption(1, "Ausblenden", {
    key = "hideGryphons",
    label = L["Gryphon-Verzierungen ausblenden"],
    tooltip = L["Blendet die Gryphonen links und rechts der Hauptaktionsleiste aus."],
    keywords = { "gryphon", "greif", "greifen", "endkappe", "end cap", "verzierung", "hauptleiste", "aktionsleiste", "main bar", "art", "dekoration" },
    set = Toggle("hideGryphons", ApplyGryphons),
})

ns.AddOption(1, "Ausblenden", {
    key = "hideRestAnim",
    label = L["Ruhe-Animation („Zzz“) ausblenden"],
    tooltip = L["Blendet die schlafende Ruhe-Animation im Spielerporträt in Städten und Gasthäusern aus. Beim Ausschalten wirkt es wieder, sobald sich dein Ruhestatus ändert."],
    keywords = { "ruhe", "rested", "resting", "zzz", "schlafen", "sleep", "animation", "porträt", "portrait", "gasthaus", "inn" },
    set = Toggle("hideRestAnim", ApplyRestAnim),
})

ns.AddOption(1, "Ausblenden", {
    key = "hideRaidGroupTitles",
    label = L["Raidgruppen-Beschriftungen ausblenden"],
    tooltip = L["Blendet die Titel „Gruppe 1“, „Gruppe 2“ … über den Gruppen der Blizzard-Raidfenster aus."],
    keywords = { "raid", "gruppe", "group", "titel", "title", "beschriftung", "label", "raidfenster", "raid frames" },
    set = Toggle("hideRaidGroupTitles", ApplyGroupTitles),
})

---------------------------------------------------------------------------
-- Optionen: Text
---------------------------------------------------------------------------

local function SizeOption(toggleKey, sizeKey, label, tooltip, keywords, apply)
    ns.AddOption(1, "Text", {
        key = sizeKey,
        type = "slider",
        min = 10, max = 28, step = 1,
        label = label,
        tooltip = tooltip,
        keywords = keywords,
        isEnabled = function() return On(toggleKey) end,
        disabledHint = L["Erst die Option direkt darüber einschalten."],
        set = function(value)
            ns.db[sizeKey] = ClampSize(value)
            Safe(apply)
        end,
    })
end

ns.AddOption(1, "Text", {
    key = "mailTextLarge",
    label = L["Post-Text größer"],
    tooltip = L["Zeigt den Text im Postfach (Lesen und Schreiben) in der darunter eingestellten Schriftgröße."],
    keywords = { "post", "mail", "brief", "postfach", "text", "schrift", "größe", "font", "size", "größer", "bigger" },
    set = Toggle("mailTextLarge", ApplyMail),
})
SizeOption("mailTextLarge", "mailTextSize", L["Post-Schriftgröße"],
    L["Schriftgröße für Post-Texte."],
    { "post", "mail", "schriftgröße", "font size", "text", "größe" }, ApplyMail)

ns.AddOption(1, "Text", {
    key = "questTextLarge",
    label = L["Quest-Text größer"],
    tooltip = L["Zeigt Questbeschreibung, Ziele, Belohnungstext, NPC-Begrüßung und Fortschrittstext in der darunter eingestellten Schriftgröße. Wirkt ab dem nächsten Öffnen eines Questfensters."],
    keywords = { "quest", "aufgabe", "text", "gossip", "npc", "gespräch", "schrift", "größe", "font", "size", "größer", "bigger" },
    set = Toggle("questTextLarge", ApplyQuest),
})
SizeOption("questTextLarge", "questTextSize", L["Quest-Schriftgröße"],
    L["Schriftgröße für Quest-Texte."],
    { "quest", "schriftgröße", "font size", "text", "größe" }, ApplyQuest)

ns.AddOption(1, "Text", {
    key = "bookTextLarge",
    label = L["Buch-Text größer"],
    tooltip = L["Zeigt den Text von Büchern, Briefen und Tafeln in der darunter eingestellten Schriftgröße. Wirkt ab dem nächsten Öffnen."],
    keywords = { "buch", "book", "brief", "letter", "schriftrolle", "tafel", "text", "schrift", "größe", "font", "size", "größer", "bigger", "lesen", "read" },
    set = Toggle("bookTextLarge", ApplyBook),
})
SizeOption("bookTextLarge", "bookTextSize", L["Buch-Schriftgröße"],
    L["Schriftgröße für Buch-Texte."],
    { "buch", "book", "schriftgröße", "font size", "text", "größe" }, ApplyBook)
