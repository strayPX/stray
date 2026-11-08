-- stray – Sprache
-- Alle Texte stehen im Code auf Deutsch. Auf einem deutschen Client bleibt es dabei;
-- auf allen anderen Clients liefert ns.L die englische Fassung aus locale/enUS_*.lua.
-- Fehlt eine Übersetzung, erscheint der deutsche Text (kein Fehler).
--
--   local L = ns.L
--   fs:SetText(L["Taschen"])
--   print(L("%d Plätze frei", n))   -- mit Platzhaltern wie string.format
--
-- Sprache wählbar (Option „Sprache“, ns.db.language = "auto" | "deDE" | "enUS"):
-- stray.lua ruft beim eigenen ADDON_LOADED als Erstes ns.SetLanguage(ns.db.language) auf.
-- Ab dann liefert ns.L die gewählte Sprache. Texte, die schon beim Laden der Dateien übersetzt
-- wurden (z. B. Optionstexte), sind noch in der Client-Sprache – zur Anzeige durch ns.T(text) schicken.

local _, ns = ...

local EN = {}
ns.LocaleEN = EN

local locale = GetLocale and GetLocale() or "deDE"
ns.locale = locale
ns.isGerman = (locale == "deDE")   -- gewählte Sprache (nach ns.SetLanguage); bis dahin Client-Sprache
ns.loadGerman = ns.isGerman        -- Sprache, in der die Dateien beim Laden übersetzt wurden (fest)
ns.language = ns.isGerman and "deDE" or "enUS"

local L = setmetatable({}, {
    __index = function(t, k)
        if type(k) ~= "string" then return k end
        local v = k
        if not ns.isGerman then
            local en = EN[k]
            if type(en) == "string" and en ~= "" then v = en end
        end
        return v
    end,
    __call = function(t, k, ...)
        local s = t[k]
        if select("#", ...) > 0 and type(s) == "string" then
            local ok, res = pcall(string.format, s, ...)
            if ok then return res end
            ok, res = pcall(string.format, k, ...)
            if ok then return res end
        end
        return s
    end,
})
ns.L = L

---------------------------------------------------------------------------
-- Sprache umschalten
---------------------------------------------------------------------------

-- lang: "deDE", "enUS" oder "auto"/nil (= Client-Sprache). Wirkt sofort auf ns.L;
-- vollständig (auch beim Laden übersetzte Texte der Module) erst nach dem Neuladen.
function ns.SetLanguage(lang)
    if lang ~= "deDE" and lang ~= "enUS" then
        lang = (locale == "deDE") and "deDE" or "enUS"
    end
    ns.language = lang
    ns.isGerman = (lang == "deDE")
end

-- Rückwärtstabelle englisch → deutsch, beim ersten Gebrauch gebaut (zur Laufzeit; alle Sprachdateien
-- stehen in der toc vor stray.lua und sind dann geladen)
local DE
local function Reverse()
    if DE then return DE end
    DE = {}
    for de, en in pairs(EN) do
        if type(en) == "string" and en ~= "" and DE[en] == nil then DE[en] = de end
    end
    return DE
end

-- Übersetzt einen bereits aufgelösten Text (deutsch oder englisch) in die gewählte Sprache.
-- Gleiche Sprache wie beim Laden: unverändert. Unbekannte Texte und Nicht-Texte kommen unverändert zurück.
function ns.T(text)
    if type(text) ~= "string" or text == "" then return text end
    if ns.isGerman == ns.loadGerman then return text end
    if ns.isGerman then
        if EN[text] ~= nil then return text end        -- schon ein deutscher Schlüssel
        return Reverse()[text] or text
    end
    if Reverse()[text] ~= nil then return text end      -- schon englisch
    local en = EN[text]
    if type(en) == "string" and en ~= "" then return en end
    return text
end

-- Beide Fassungen eines Textes (für die Suche): deutsch, englisch
function ns.TBoth(text)
    if type(text) ~= "string" or text == "" then return text, text end
    local de = text
    if EN[text] == nil then de = Reverse()[text] or text end
    local en = EN[de]
    if type(en) ~= "string" or en == "" then en = text end
    return de, en
end
