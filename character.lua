-- stray – Charakter (Phase 2, Leatrix-Funktionen nachgebaut)
-- Lautstärkeregler, Helm-/Umhang-Kästchen im Charakterfenster, Auskleiden in der Anprobe,
-- Wowhead-Link für Quests. Eigene Frames hängen als Kinder an Blizzards Fenstern; auf
-- Blizzard-Frames werden keine Felder geschrieben, Blizzard-Code wird nur gehookt.
-- Bei „aus“ bleibt alles unverändert.

local _, ns = ...
local L = ns.L

ns.defaults.charVolume = false
ns.defaults.charHelmCloak = false
ns.defaults.dressUndress = false
ns.defaults.wowheadQuest = false

-- Adresse der Datenbank passend zur Spielversion. Hier ändern, falls die Links nicht passen
-- (z. B. "https://www.wowhead.com/wotlk", "https://www.wowhead.com/cata" oder "https://www.wowhead.com").
local WOWHEAD_BASE = "https://www.wowhead.com/classic"

local VOLUME_CVAR = "Sound_MasterVolume"
local TABARD_SLOT = INVSLOT_TABARD or 19

local function On(key)
    return ns.db and ns.db[key] and true or false
end

local C = ns.Colors

local function SetText(fontString, text, color)
    fontString:SetText(text)
    color = color or C.text
    fontString:SetTextColor(color[1], color[2], color[3])
end

---------------------------------------------------------------------------
-- Charakterfenster: Helm, Umhang, Lautstärke
---------------------------------------------------------------------------

local bar -- { frame, helm, cloak, volRow, slider, pct }

local function GetVolume()
    local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(VOLUME_CVAR) or GetCVar(VOLUME_CVAR)
    value = tonumber(value) or 1
    if value < 0 then value = 0 elseif value > 1 then value = 1 end
    return math.floor(value * 100 + 0.5)
end

local function MakeCheck(parent, labelKey, getter, setter)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", check, "RIGHT", 0, 1)
    check.strayLabel = label
    check:SetScript("OnClick", function(self)
        pcall(setter, self:GetChecked() and true or false)
        self:SetChecked(getter() and true or false)
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L[labelKey], 1, 1, 1)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    check.labelKey = labelKey
    return check
end

local function BuildBar()
    if bar or not PaperDollFrame then return end
    local holder = CreateFrame("Frame", nil, PaperDollFrame)
    holder:SetSize(230, 52)
    holder:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 200)
    if CharacterModelScene then
        holder:SetPoint("TOP", CharacterModelScene, "TOP", 0, -6)
    else
        holder:SetPoint("TOP", PaperDollFrame, "TOP", 0, -70)
    end

    bar = { frame = holder }

    bar.helm = MakeCheck(holder, "Helm anzeigen",
        function() return ShowingHelm and ShowingHelm() end,
        function(value) ShowHelm(value) end)
    bar.cloak = MakeCheck(holder, "Umhang anzeigen",
        function() return ShowingCloak and ShowingCloak() end,
        function(value) ShowCloak(value) end)

    -- Lautstärke: Beschriftung, Regler, Prozentwert
    local volRow = CreateFrame("Frame", nil, holder)
    volRow:SetSize(230, 20)
    bar.volRow = volRow

    local volLabel = volRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    volLabel:SetPoint("LEFT", 0, 0)
    bar.volLabel = volLabel

    local slider = CreateFrame("Slider", nil, volRow)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(110, 14)
    slider:SetPoint("LEFT", volLabel, "RIGHT", 8, 0)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:EnableMouseWheel(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 14)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    slider:SetThumbTexture(thumb)
    bar.slider = slider

    local pct = volRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pct:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    bar.pct = pct

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        pct:SetText(value .. " %")
        if self.strayUpdating then return end
        pcall(ns.SetCVarValue, VOLUME_CVAR, tostring(value / 100))
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * 5)
    end)
    slider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Gesamtlautstärke"], 1, 1, 1)
        GameTooltip:AddLine(L["Ändert die Hauptlautstärke des Spiels."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)

    holder:SetScript("OnShow", function() ns.RefreshCharacter() end)
end

function ns.RefreshCharacter()
    if not bar then return end
    local helmCloak = On("charHelmCloak")
    local volume = On("charVolume")
    bar.frame:SetShown(helmCloak or volume)
    if not (helmCloak or volume) then return end

    bar.helm:SetShown(helmCloak)
    bar.cloak:SetShown(helmCloak)
    bar.volRow:SetShown(volume)

    SetText(bar.helm.strayLabel, L[bar.helm.labelKey])
    SetText(bar.cloak.strayLabel, L[bar.cloak.labelKey])
    SetText(bar.volLabel, L["Ton"], C.textDim)

    bar.helm:ClearAllPoints()
    bar.helm:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", 0, 0)
    bar.cloak:ClearAllPoints()
    bar.cloak:SetPoint("LEFT", bar.helm.strayLabel, "RIGHT", 14, -1)
    bar.volRow:ClearAllPoints()
    if helmCloak then
        bar.volRow:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", 4, -28)
    else
        bar.volRow:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", 4, -4)
    end

    if helmCloak then
        bar.helm:SetChecked(ShowingHelm and ShowingHelm() and true or false)
        bar.cloak:SetChecked(ShowingCloak and ShowingCloak() and true or false)
    end
    if volume then
        bar.slider.strayUpdating = true
        bar.slider:SetValue(GetVolume())
        bar.slider.strayUpdating = false
        bar.pct:SetText(GetVolume() .. " %")
    end
end

ns.On("CVAR_UPDATE", function(name)
    if bar and bar.frame:IsShown() and On("charVolume") and name == VOLUME_CVAR then
        ns.RefreshCharacter()
    end
end)

---------------------------------------------------------------------------
-- Anprobe: Auskleiden, Wappenrock ab
---------------------------------------------------------------------------

local dress -- { undress, tabard }

local function PlayerActor()
    local frame = DressUpFrame
    local scene = frame and frame.ModelScene
    if not scene or not scene.GetPlayerActor then return nil end
    local ok, actor = pcall(scene.GetPlayerActor, scene)
    return ok and actor or nil
end

local function DressMode()
    local frame = DressUpFrame
    if not frame or not frame.GetMode then return "player" end
    local ok, mode = pcall(frame.GetMode, frame)
    return ok and mode or "player"
end

local function MakeDressButton(textKey, onClick)
    local button = CreateFrame("Button", nil, DressUpFrame, "UIPanelButtonTemplate")
    button:SetSize(112, 22)
    button:SetFrameLevel(DressUpFrame:GetFrameLevel() + 20)
    button.labelKey = textKey
    button:SetScript("OnClick", function()
        local actor = PlayerActor()
        if actor then pcall(onClick, actor) end
    end)
    return button
end

local function BuildDress()
    if dress or not DressUpFrame or not DressUpFrame.ModelScene then return end
    dress = {}
    dress.undress = MakeDressButton("Auskleiden", function(actor) actor:Undress() end)
    dress.undress:SetPoint("BOTTOMLEFT", DressUpFrame.ModelScene, "BOTTOMLEFT", 6, 8)
    dress.tabard = MakeDressButton("Wappenrock ab", function(actor) actor:UndressSlot(TABARD_SLOT) end)
    dress.tabard:SetPoint("LEFT", dress.undress, "RIGHT", 4, 0)
    DressUpFrame:HookScript("OnShow", function() ns.RefreshDress() end)
end

function ns.RefreshDress()
    if not dress then return end
    local show = On("dressUndress") and DressMode() == "player"
    for _, button in pairs(dress) do
        button:SetText(L[button.labelKey])
        button:SetShown(show)
    end
end

local dressHooked = false
local function HookDress()
    if dressHooked or not DressUpFrame_Show then return end
    dressHooked = true
    hooksecurefunc("DressUpFrame_Show", function() ns.RefreshDress() end)
end

---------------------------------------------------------------------------
-- Wowhead-Link (Questlog)
---------------------------------------------------------------------------

local currentUrl -- zuletzt angezeigter Link (statt eines Feldes auf Blizzards Popup)

local function GetEditBox(popup)
    return popup.editBox or popup.EditBox or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "EditBox"])
end

StaticPopupDialogs["STRAY_WOWHEAD_LINK"] = {
    text = L["Link kopieren mit Strg+C:"],
    button1 = L["Schließen"],
    hasEditBox = true,
    editBoxWidth = 320,
    OnShow = function(self, data)
        local box = GetEditBox(self)
        if not box then return end
        box:SetText(data or currentUrl or "")
        box:HighlightText()
        box:SetFocus()
    end,
    EditBoxOnTextChanged = function(box)
        -- Text bleibt unverändert, auch wenn man versehentlich tippt
        if currentUrl and box:GetText() ~= currentUrl then
            box:SetText(currentUrl)
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

function ns.WowheadURL(kind, id)
    return ("%s/%s=%d"):format(WOWHEAD_BASE, kind, id)
end

local function ShowCopy(url)
    currentUrl = url
    local dialog = StaticPopupDialogs["STRAY_WOWHEAD_LINK"]
    if dialog then
        dialog.text = L["Link kopieren mit Strg+C:"]
        dialog.button1 = L["Schließen"]
    end
    local popup = StaticPopup_Show("STRAY_WOWHEAD_LINK", nil, nil, url)
    if popup then
        local box = GetEditBox(popup)
        if box then
            box:SetText(url)
            box:HighlightText()
            box:SetFocus()
        end
    end
end

local questButton
local shownQuestId -- Quest, deren Details gerade offen sind (statt Feld auf Blizzards Frame)

local function BuildQuestButton()
    if questButton or not QuestMapFrame or not QuestMapFrame.DetailsFrame then return end
    local details = QuestMapFrame.DetailsFrame
    local button = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
    button:SetSize(72, 20)
    button:SetPoint("TOPRIGHT", details, "TOPRIGHT", -10, -9)
    button:SetFrameLevel(details:GetFrameLevel() + 20)
    button:SetText("Wowhead")
    button:SetScript("OnClick", function()
        if shownQuestId then ShowCopy(ns.WowheadURL("quest", shownQuestId)) end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Wowhead-Link kopieren"], 1, 1, 1)
        if shownQuestId then
            GameTooltip:AddLine(L("Quest-ID: %d", shownQuestId), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    questButton = button
end

local function RefreshQuestButton()
    if not questButton then return end
    questButton:SetShown(On("wowheadQuest") and shownQuestId ~= nil)
end

local questHooked = false
local function HookQuest()
    if questHooked or not QuestMapFrame_ShowQuestDetails then return end
    questHooked = true
    hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
        shownQuestId = (not ns.IsSecret(questID) and type(questID) == "number") and questID or nil
        if On("wowheadQuest") then BuildQuestButton() end
        RefreshQuestButton()
    end)
    if QuestMapFrame_CloseQuestDetails then
        hooksecurefunc("QuestMapFrame_CloseQuestDetails", function()
            shownQuestId = nil
            RefreshQuestButton()
        end)
    end
end

---------------------------------------------------------------------------
-- Aufbau, sobald die Blizzard-Fenster da sind
---------------------------------------------------------------------------

local function Setup()
    if not ns.db then return end
    HookDress()
    HookQuest()
    if CharacterFrame and PaperDollFrame and (On("charVolume") or On("charHelmCloak")) then
        BuildBar()
        if bar then ns.RefreshCharacter() end
    end
    if DressUpFrame and On("dressUndress") then
        BuildDress()
        ns.RefreshDress()
    end
    if On("wowheadQuest") then BuildQuestButton() end
    RefreshQuestButton()
end

ns.On("PLAYER_LOGIN", Setup)
ns.On("ADDON_LOADED", function() Setup() end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

ns.AddOption(3, "Charakter", {
    key = "charVolume",
    label = L["Lautstärkeregler im Charakterfenster"],
    tooltip = L["Zeigt oben im Charakterfenster einen Regler für die Gesamtlautstärke des Spiels – ohne die Einstellungen zu öffnen."],
    keywords = { "lautstärke", "ton", "volume", "sound", "audio", "regler", "slider", "charakterfenster" },
    set = function(value)
        ns.db.charVolume = value
        Setup()
        ns.RefreshCharacter()
    end,
})

ns.AddOption(3, "Charakter", {
    key = "charHelmCloak",
    label = L["Helm- und Umhang-Kästchen im Charakterfenster"],
    tooltip = L["Zwei Kästchen oben im Charakterfenster schalten die Anzeige von Helm und Umhang an deinem Charakter ein oder aus (wie die Einstellung im Spiel)."],
    keywords = { "helm", "umhang", "cloak", "helmet", "anzeigen", "verstecken", "hide", "charakterfenster" },
    set = function(value)
        ns.db.charHelmCloak = value
        Setup()
        ns.RefreshCharacter()
    end,
})

ns.AddOption(3, "Charakter", {
    key = "dressUndress",
    label = L["Anprobe: Auskleiden und Wappenrock ab"],
    tooltip = L["Fügt dem Anprobe-Fenster zwei Knöpfe hinzu: „Auskleiden“ zieht dem Modell alles aus, „Wappenrock ab“ nur den Wappenrock. Das betrifft nur die Vorschau, nicht deine Ausrüstung."],
    keywords = { "anprobe", "anprobieren", "auskleiden", "ausziehen", "wappenrock", "tabard", "undress", "dressing", "room" },
    set = function(value)
        ns.db.dressUndress = value
        Setup()
        ns.RefreshDress()
    end,
})

ns.AddOption(3, "Charakter", {
    key = "wowheadQuest",
    label = L["Wowhead-Link im Questlog kopieren"],
    tooltip = L["Zeigt in den Quest-Details einen Knopf „Wowhead“. Ein Klick öffnet ein Feld mit dem Link zur Quest, den du mit Strg+C kopierst.\nDer Link passt zur Spielversion; die Adresse steht oben in character.lua."],
    keywords = { "wowhead", "link", "quest", "questlog", "kopieren", "copy", "id", "datenbank" },
    set = function(value)
        ns.db.wowheadQuest = value
        Setup()
        RefreshQuestButton()
    end,
})
