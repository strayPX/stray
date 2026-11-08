-- stray – Grafik-und-Ton (Phase 2, Leatrix-Funktionen nachgebaut)
--
-- Jede Option ist einzeln und standardmäßig aus; bei „aus“ greift stray nicht ein.
-- CVars werden nur gesetzt, wenn die Option umgeschaltet wird oder beim Einloggen (Option an).
-- Vor dem ersten Eingriff merkt sich stray den Originalwert (ns.db.sysOrig) und stellt ihn beim
-- Ausschalten wieder her. CVars, die der Client nicht kennt, werden übersprungen.
--
-- Bewusst weggelassen (nicht nachprüfbar): Stummschalten einzelner Töne/Ruhe-Emotes (keine
-- gesicherten Dateinummern), klassenfarbene Spieler-/Zielrahmen (Taint-Risiko bei Blizzards Rahmen).
local _, ns = ...
local L = ns.L

ns.defaults.sysNoGlow = false
ns.defaults.sysNoFx = false
ns.defaults.sysWeather = false
ns.defaults.sysWeatherLevel = 1
ns.defaults.sysSoundFollow = false
ns.defaults.sysOrig = {} -- [CVar] = ursprünglicher Wert, solange stray eingreift

local Sys = {}

local function Exists(name)
    local api = C_CVar and C_CVar.GetCVarInfo
    if api then
        local ok, value = pcall(api, name)
        return ok and value ~= nil
    end
    local getValue = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, value = pcall(getValue, name)
    return ok and value ~= nil
end

local function Current(name)
    local getValue = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, value = pcall(getValue, name)
    if ok and value ~= nil then return tostring(value) end
end

-- CVar auf Wert setzen (on) oder Originalwert wiederherstellen (aus)
local function Apply(name, value, on)
    if not ns.db then return end
    if type(ns.db.sysOrig) ~= "table" then ns.db.sysOrig = {} end
    local orig = ns.db.sysOrig
    if on then
        if not Exists(name) then return end
        if orig[name] == nil then orig[name] = Current(name) end
        value = tostring(value)
        if Current(name) ~= value then pcall(ns.SetCVarValue, name, value) end
    elseif orig[name] ~= nil then
        if Exists(name) then pcall(ns.SetCVarValue, name, orig[name]) end
        orig[name] = nil
    end
end

local function ApplyGlow(on) Apply("ffxGlow", 0, on) end

local function ApplyFx(on)
    Apply("ffxDeath", 0, on)
    Apply("ffxNetherWorld", 0, on)
end

local function ApplyWeather(on)
    local level = tonumber(ns.db and ns.db.sysWeatherLevel) or 1
    Apply("weatherDensity", math.max(0, math.min(3, math.floor(level + 0.5))), on)
end

local function ApplySound(on) Apply("Sound_OutputDriverIndex", 0, on) end

---------------------------------------------------------------------------
-- Optionen (Bereich „Grafik & Ton“, Seite „Welt“)
---------------------------------------------------------------------------

ns.AddOption(3, "Grafik & Ton", {
    key = "sysNoGlow",
    label = L["Bildschirmglühen ausschalten"],
    tooltip = L["Schaltet den Glüheffekt (Bloom) des Bildes aus – klarere, weniger überstrahlte Darstellung. Ausschalten stellt deinen vorherigen Wert wieder her."],
    keywords = { "glühen", "glow", "bloom", "überstrahlt", "grafik", "graphics", "effekt" },
    set = function(value)
        ns.db.sysNoGlow = value
        ApplyGlow(value)
    end,
})

ns.AddOption(3, "Grafik & Ton", {
    key = "sysNoFx",
    label = L["Bildschirmeffekte ausschalten"],
    tooltip = L["Schaltet die graue Sicht als Geist und den Effekt in der Netherwelt aus. Ausschalten stellt deine vorherigen Werte wieder her."],
    keywords = { "tod", "geist", "grau", "death", "ghost", "netherwelt", "nether", "effekt", "screen effect", "grafik", "graphics" },
    set = function(value)
        ns.db.sysNoFx = value
        ApplyFx(value)
    end,
})

ns.AddOption(3, "Grafik & Ton", {
    key = "sysWeather",
    label = L["Wetterdichte festlegen"],
    tooltip = L["Legt fest, wie dicht Regen, Schnee und Nebel dargestellt werden. Die Stärke stellst du direkt darunter ein. Ausschalten stellt deinen vorherigen Wert wieder her."],
    keywords = { "wetter", "weather", "regen", "rain", "schnee", "snow", "dichte", "density", "partikel", "particle" },
    set = function(value)
        ns.db.sysWeather = value
        ApplyWeather(value)
    end,
})

ns.AddOption(3, "Grafik & Ton", {
    key = "sysWeatherLevel",
    type = "slider",
    min = 0,
    max = 3,
    step = 1,
    label = L["Wetterdichte (0 = aus, 3 = voll)"],
    tooltip = L["0 blendet Wettereffekte praktisch aus, 3 ist die volle Dichte."],
    keywords = { "wetter", "weather", "regen", "rain", "dichte", "density" },
    isEnabled = function() return ns.db and ns.db.sysWeather and true or false end,
    disabledHint = L["Erst „Wetterdichte festlegen“ einschalten (direkt darüber)."],
    set = function(value)
        ns.db.sysWeatherLevel = value
        if ns.db.sysWeather then ApplyWeather(true) end
    end,
})

ns.AddOption(3, "Grafik & Ton", {
    key = "sysSoundFollow",
    label = L["Ton folgt dem System-Ausgabegerät"],
    tooltip = L["Nutzt das Standard-Ausgabegerät von Windows für den Spielton und startet den Ton neu, wenn du zwischen Lautsprechern und Kopfhörern wechselst. Ausschalten stellt deine vorherige Auswahl wieder her."],
    keywords = { "ton", "sound", "audio", "lautsprecher", "speaker", "kopfhörer", "headphones", "ausgabe", "output", "gerät", "device", "wechsel" },
    set = function(value)
        ns.db.sysSoundFollow = value
        ApplySound(value)
    end,
})

---------------------------------------------------------------------------
-- Einloggen und Geräte-Wechsel
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    if not ns.db then return end
    if ns.db.sysNoGlow then ApplyGlow(true) end
    if ns.db.sysNoFx then ApplyFx(true) end
    if ns.db.sysWeather then ApplyWeather(true) end
    if ns.db.sysSoundFollow then ApplySound(true) end
end)

-- Wechselt das Windows-Ausgabegerät, meldet der Client das über das Sprachchat-Ereignis.
-- Dann den Ton neu starten, damit er auf das neue Standardgerät springt.
Sys.restartPending = false
ns.On("VOICE_CHAT_OUTPUT_DEVICES_UPDATED", function()
    if not (ns.db and ns.db.sysSoundFollow) or Sys.restartPending then return end
    if type(Sound_GameSystem_RestartSoundSystem) ~= "function" then return end
    Sys.restartPending = true
    C_Timer.After(0.5, function()
        Sys.restartPending = false
        if ns.db and ns.db.sysSoundFollow then pcall(Sound_GameSystem_RestartSoundSystem) end
    end)
end)
