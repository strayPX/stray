-- stray – Lehrer: Knopf „Alles lernen“
--
-- Am Klassen- und Berufslehrer steht links neben „Lernen“ ein Knopf „Alles lernen (Preis)“.
-- Ein Klick kauft alle verfügbaren Fertigkeiten, die das Gold noch hergibt, der Reihe nach
-- (billigste Stufe zuerst, wie Blizzard sie listet). Was das Gold nicht mehr deckt, bleibt
-- liegen. Neue Berufe (mit Blizzards Rückfrage) und Begleiter-Lehrer (Trainingspunkte) fasst
-- stray nicht an. Danach steht im Chat, was gelernt wurde.
--
-- APIs (Forever-Quellcode, Blizzard_TrainerUI): GetNumTrainerServices, GetTrainerServiceInfo
-- (Name, Typ "available"/"unavailable"/"used", …), GetTrainerServiceCost (Preis, neuer Beruf),
-- BuyTrainerService, C_Trainer.GetTrainerType. Der Knopf ist ein Klick, also ein
-- Hardware-Ereignis; gekauft wird nur innerhalb dieses Klicks.

local _, ns = ...

ns.defaults.trainerLearnAll = false

local FONT = "Fonts\\ARIALN.TTF"
local C = {
    bg     = { 0.051, 0.067, 0.090, 0.95 },
    border = { 0.169, 0.290, 0.451, 1 },
    accent = { 0.353, 0.659, 1.000, 1 },
    text   = { 0.890, 0.914, 0.953, 1 },
    dim    = { 0.435, 0.525, 0.651, 1 },
}

local button

-- Kurzer Goldbetrag: „1g 20s“, „35s 10k“
local function ShortMoney(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local k = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if k > 0 or #parts == 0 then parts[#parts + 1] = k .. "k" end
    return table.concat(parts, " ")
end

local function IsPetTrainer()
    if not (C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType) then return false end
    local ok, kind = pcall(C_Trainer.GetTrainerType)
    return ok and kind == Enum.TrainerType.Pet
end

-- Liste der Fertigkeiten, die ein Klick jetzt kaufen würde.
-- Gibt plan (Liste mit index, name, sub, cost), Summe, Anzahl der zu teuren zurück.
local function Plan()
    local plan, total, tooExpensive = {}, 0, 0
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceCost) then
        return plan, total, tooExpensive
    end
    if IsPetTrainer() then return plan, total, tooExpensive end
    local money = GetMoney()
    local num = GetNumTrainerServices() or 0
    for i = 1, num do
        local name, kind, _, _, sub = GetTrainerServiceInfo(i)
        if kind == "available" and name then
            local cost, isProfession = GetTrainerServiceCost(i)
            cost = cost or 0
            if not isProfession then
                if total + cost <= money then
                    plan[#plan + 1] = { index = i, name = name, sub = sub, cost = cost }
                    total = total + cost
                else
                    tooExpensive = tooExpensive + 1
                end
            end
        end
    end
    return plan, total, tooExpensive
end

local function Update()
    if not button then return end
    local frame = ClassTrainerFrame
    if not (ns.db and ns.db.trainerLearnAll) or not frame or not frame:IsShown() then
        button:Hide()
        return
    end
    local plan, total, tooExpensive = Plan()
    if #plan > 0 then
        button.text:SetText(("Alles lernen (%s)"):format(ShortMoney(total)))
        button.text:SetTextColor(C.text[1], C.text[2], C.text[3])
        button:Enable()
    elseif tooExpensive > 0 then
        button.text:SetText("Alles lernen: zu wenig Gold")
        button.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        button:Disable()
    else
        button.text:SetText("Alles lernen")
        button.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        button:Disable()
    end
    button:SetWidth(math.max(110, button.text:GetStringWidth() + 20))
    button:Show()
end

local function LearnAll()
    if not (ns.db and ns.db.trainerLearnAll) or not BuyTrainerService then return end
    local plan, total, tooExpensive = Plan()
    if #plan == 0 then
        if tooExpensive > 0 then ns.Print("Nicht genug Gold für die nächste Fertigkeit.") end
        return
    end
    if total > GetMoney() then
        ns.Print("Nicht genug Gold.")
        return
    end
    -- Von hinten nach vorn: falls die Liste sich während des Kaufs verkürzt, stimmen die
    -- vorderen Nummern noch
    local names = {}
    for i = #plan, 1, -1 do
        local entry = plan[i]
        local ok = pcall(BuyTrainerService, entry.index)
        if ok then
            local label = entry.name
            if type(entry.sub) == "string" and entry.sub ~= "" then label = label .. " (" .. entry.sub .. ")" end
            table.insert(names, 1, label)
        end
    end
    if #names > 0 then
        ns.Print(("%d %s für %s gelernt: %s"):format(#names,
            #names == 1 and "Fertigkeit" or "Fertigkeiten", ns.FormatMoney(total), table.concat(names, ", ")))
    end
    if tooExpensive > 0 then
        ns.Print(("%d weitere %s zu teuer."):format(tooExpensive, tooExpensive == 1 and "ist" or "sind"))
    end
end

local function Style(b)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    local function Line(p1, p2, horizontal)
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        t:SetPoint(p1); t:SetPoint(p2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    end
    Line("TOPLEFT", "TOPRIGHT", true)
    Line("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Line("TOPLEFT", "BOTTOMLEFT", false)
    Line("TOPRIGHT", "BOTTOMRIGHT", false)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
end

local function CreateButton()
    if button or not ClassTrainerFrame then return end
    button = CreateFrame("Button", "strayTrainerLearnAll", ClassTrainerFrame)
    button:SetSize(130, 22)
    Style(button)
    button.text = button:CreateFontString(nil, "OVERLAY")
    button.text:SetFont(FONT, 12, "")
    button.text:SetPoint("CENTER")
    if ClassTrainerTrainButton then
        button:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -6, 0)
    else
        button:SetPoint("BOTTOMRIGHT", ClassTrainerFrame, "BOTTOMRIGHT", -120, 4)
    end
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", LearnAll)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Alles lernen", 1, 1, 1)
        local plan, total, tooExpensive = Plan()
        for _, entry in ipairs(plan) do
            local label = entry.name
            if type(entry.sub) == "string" and entry.sub ~= "" then label = label .. " (" .. entry.sub .. ")" end
            GameTooltip:AddDoubleLine(label, ShortMoney(entry.cost), C.text[1], C.text[2], C.text[3], 1, 0.82, 0)
        end
        if #plan == 0 then
            GameTooltip:AddLine("Gerade gibt es nichts zu lernen.", C.dim[1], C.dim[2], C.dim[3])
        else
            GameTooltip:AddDoubleLine("Summe", ShortMoney(total), C.accent[1], C.accent[2], C.accent[3], 1, 0.82, 0)
        end
        if tooExpensive > 0 then
            GameTooltip:AddLine(("%d weitere: zu wenig Gold"):format(tooExpensive), 1, 0.3, 0.3)
        end
        GameTooltip:AddLine("Neue Hauptberufe lernst du weiter selbst. Am Waffenmeister lernt der Knopf alle angebotenen Waffen.", C.dim[1], C.dim[2], C.dim[3], true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
end

-- Blizzards Lehrerfenster lädt erst beim ersten Lehrer; danach Knopf anlegen
local function Setup()
    CreateButton()
    Update()
end

ns.AddOption(1, "NPCs", {
    key = "trainerLearnAll",
    label = "Lehrer: Alles lernen",
    tooltip = "Am Klassen- und Berufslehrer erscheint ein Knopf „Alles lernen“ mit dem Gesamtpreis. Ein Klick lernt alles, was du jetzt lernen kannst und bezahlen kannst. Reicht das Gold nicht für alles, lernt stray nur, was das Gold deckt.\n\nNeue Hauptberufe lernst du weiter selbst, weil Blizzard dabei nachfragt. Nebenberufe (Kochen, Erste Hilfe, Angeln) und am Waffenmeister alle angebotenen Waffen lernt der Knopf mit – Liste und Preis stehen im Tooltip des Knopfes.",
    set = function(value)
        ns.db.trainerLearnAll = value
        Setup()
    end,
})

ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_TrainerUI" and ns.db then Setup() end
end)

ns.On("TRAINER_SHOW", function()
    -- Blizzard lädt und öffnet sein Fenster beim selben Ereignis, deshalb einen Takt warten
    C_Timer.After(0, Setup)
end)

ns.On("TRAINER_UPDATE", Update)
ns.On("PLAYER_MONEY", Update)
ns.On("TRAINER_CLOSED", function() if button then button:Hide() end end)
