-- stray – Filmsequenzen: schnell bzw. immer überspringen

local _, ns = ...

ns.AddOption(2, "Filmsequenzen", {
    key = "cinematicFast",
    label = "Schnell überspringen",
    tooltip = "Esc beendet Filmsequenzen und Videos sofort, ohne „Wirklich überspringen?“-Abfrage.",
})

ns.AddOption(2, "Filmsequenzen", {
    key = "cinematicAlways",
    label = "Immer überspringen",
    tooltip = "Filmsequenzen und Videos werden beim Start automatisch beendet. Sequenzen, die Blizzard als nicht abbrechbar markiert, laufen trotzdem.",
})

local function CancelCinematic()
    if CinematicFrame and CinematicFrame.closeDialog then
        CinematicFrame.closeDialog:Hide()
    end
    if CinematicFrame_CancelCinematic then
        CinematicFrame_CancelCinematic()
    elseif StopCinematic then
        StopCinematic()
    end
end

local function StopMovie()
    if MovieFrame and MovieFrame:IsShown() and MovieFrame.StopMovie then
        MovieFrame:StopMovie()
    end
end

-- Spielgrafik-Sequenzen
ns.On("CINEMATIC_START", function(canBeCancelled)
    if not ns.db or not ns.db.cinematicAlways then return end
    if canBeCancelled == false then return end
    C_Timer.After(0.1, CancelCinematic)
    ns.Print("Filmsequenz übersprungen.")
end)

-- Vorgerenderte Videos
if MovieFrame then
    MovieFrame:HookScript("OnShow", function()
        if not ns.db or not ns.db.cinematicAlways then return end
        C_Timer.After(0.1, StopMovie)
        ns.Print("Video übersprungen.")
    end)
end

-- Esc ohne Rückfrage
local function HookEscape(frame, cancel)
    if not frame then return end
    local function OnKey(_, key)
        if ns.db and ns.db.cinematicFast and key == "ESCAPE" then
            cancel()
        end
    end
    frame:HookScript("OnKeyDown", OnKey)
    frame:HookScript("OnKeyUp", OnKey)
end

HookEscape(CinematicFrame, CancelCinematic)
HookEscape(MovieFrame, StopMovie)
