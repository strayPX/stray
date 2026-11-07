-- stray – Zaubern: Blizzards „Mouseover-Zauber“ direkt in stray umschalten
-- Ist die Einstellung an, gehen Zauber auf das Ziel unter der Maus (z. B. ein Gruppenrahmen),
-- ohne es vorher anzuklicken. stray schaltet nur Blizzards eigene Einstellung um.

local _, ns = ...

-- Mögliche Namen der Einstellung; der erste, den der Client kennt, wird benutzt
local CANDIDATES = { "enableMouseoverCast" }

local function CVarExists(name)
    local getDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if not getDefault then return false end
    local ok, value = pcall(getDefault, name)
    return ok and value ~= nil
end

local CVAR
for _, name in ipairs(CANDIDATES) do
    if CVarExists(name) then
        CVAR = name
        break
    end
end

ns.AddOption(2, "Zaubern", {
    key = "mouseoverCast",
    label = "Mouseover-Zauber",
    tooltip = "Zauber gehen auf das Gruppenmitglied oder Ziel unter deiner Maus, ohne es vorher anzuklicken – praktisch zum Heilen über die Gruppenrahmen. Schaltet Blizzards eigene Einstellung „Mouseover-Zauber“ (Optionen → Kampf) um.\n\nIst die Maus über keinem Ziel, wirkt der Zauber wie gewohnt auf dein aktuelles Ziel.",
    get = function() return CVAR and ns.GetCVarOn(CVAR) or false end,
    set = function(value)
        if CVAR then ns.SetCVarValue(CVAR, value and "1" or "0") end
    end,
    isEnabled = function() return CVAR ~= nil end,
    disabledHint = "Diese Spielversion hat die Einstellung „Mouseover-Zauber“ nicht.",
})
