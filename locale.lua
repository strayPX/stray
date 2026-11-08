-- stray – Sprache
-- Alle Texte stehen im Code auf Deutsch. Auf einem deutschen Client bleibt es dabei;
-- auf allen anderen Clients liefert ns.L die englische Fassung aus locale/enUS_*.lua.
-- Fehlt eine Übersetzung, erscheint der deutsche Text (kein Fehler).
--
--   local L = ns.L
--   fs:SetText(L["Taschen"])
--   print(L("%d Plätze frei", n))   -- mit Platzhaltern wie string.format

local _, ns = ...

local EN = {}
ns.LocaleEN = EN

local locale = GetLocale and GetLocale() or "deDE"
ns.locale = locale
ns.isGerman = (locale == "deDE")

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
