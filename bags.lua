-- stray – Taschen: Zerstören ohne Tipparbeit bzw. ohne Nachfrage

local _, ns = ...
local L = ns.L

local CONFIRM_WORD = DELETE_ITEM_CONFIRM_STRING or "LÖSCHEN"

ns.AddOption(1, "Taschen", {
    key = "deleteFill",
    label = L("„%s“ vorausfüllen", CONFIRM_WORD),
    tooltip = L["Beim Zerstören wertvoller Gegenstände steht das Bestätigungswort schon im Feld. Du klickst nur noch auf „Ja“ oder drückst Enter."],
})

ns.AddOption(1, "Taschen", {
    key = "deleteNoConfirm",
    label = L["Ohne Nachfrage zerstören"],
    tooltip = L["Zerstört Gegenstände sofort, ohne Ja/Nein-Abfrage – auch epische und legendäre.\n\nZerstörte Gegenstände sind endgültig weg."],
})

-- Zerstören-Abfragen von WoW; true = Bestätigungswort muss eingetippt werden
local DELETE_POPUPS = {
    DELETE_ITEM = false,
    DELETE_QUEST_ITEM = false,
    DELETE_GOOD_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true,
}

local function GetEditBox(popup)
    if not popup then return end
    return popup.editBox or popup.EditBox or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "EditBox"])
end

hooksecurefunc("StaticPopup_Show", function(which)
    if not ns.db then return end
    local needsWord = DELETE_POPUPS[which]
    if needsWord == nil then return end

    if ns.db.deleteNoConfirm then
        if CursorHasItem() then
            DeleteCursorItem()
        end
        StaticPopup_Hide(which)
        return
    end

    if needsWord and ns.db.deleteFill then
        local box = GetEditBox(StaticPopup_FindVisible(which))
        if box then
            box:SetText(CONFIRM_WORD)
        end
    end
end)
