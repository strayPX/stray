-- stray – stray-Tasche: automatisches Öffnen und Schließen mit anderen Fenstern
--
-- Händler, Post, Auktionshaus, Bank, Handel, Berufsfenster (und optional das Charakterfenster) öffnen das
-- stray-Fenster und schließen es wieder – je Fenster schaltbar (Bereich „Tasche“, Reiter „Automatik“).
--
-- Zusammenspiel mit der Übernahme in bag_core.lua:
--   * Blizzard ruft bei Händler, Post, Auktionshaus und Bank selbst OpenAllBags(Fenster)/CloseAllBags(Fenster) auf.
--     bag_core wertet das aus („openBy“/„closeBy“) und fragt vor dem Öffnen B.AutoAllowed(Rahmenname).
--   * Fenster, bei denen Blizzard die Taschen nicht öffnet (Handel, Berufe, Charakter), öffnet dieses Modul über
--     die Ereignisse. Beide Wege setzen B.openerName auf denselben Rahmennamen; ist das Fenster schon offen, tut
--     der zweite Weg nichts – es schaltet also nie doppelt um.
--   * Schließen: nur, wenn dieses Fenster die Tasche geöffnet hat (B.openerName). War sie schon offen, bleibt sie
--     offen; schließt der Spieler sie von Hand, löscht das Fenster openerName – der Auslöser gilt als erledigt.
--   * „Taschen nicht automatisch öffnen“ (noAutoBags, automation.lua) hat Vorrang und gilt für alle diese Fenster.
--   * Aktive Gamepad-Oberfläche: stray hält sich raus (B.GamepadActive, bag_core.lua).

local _, ns = ...
local L = ns.L
local B = ns.Bag

ns.defaults.bagAutoMerchant = true
ns.defaults.bagAutoMail = true
ns.defaults.bagAutoAuction = true
ns.defaults.bagAutoBank = true
ns.defaults.bagAutoTrade = true
ns.defaults.bagAutoCraft = false
ns.defaults.bagOpenWithCharacter = false

---------------------------------------------------------------------------
-- Zuordnung: Rahmenname → Schalter
---------------------------------------------------------------------------

local A = {}

A.KEY = {
    MerchantFrame = "bagAutoMerchant",
    MailFrame = "bagAutoMail",
    AuctionHouseFrame = "bagAutoAuction",
    AuctionFrame = "bagAutoAuction",
    BankFrame = "bagAutoBank",
    TradeFrame = "bagAutoTrade",
    ProfessionsFrame = "bagAutoCraft",
    TradeSkillFrame = "bagAutoCraft",
    CraftFrame = "bagAutoCraft",
    CharacterFrame = "bagOpenWithCharacter",
}

-- Ereignis → Rahmenname (Öffnen / Schließen). Fehlende Ereignisse im Client werden übersprungen.
A.OPEN = {
    MERCHANT_SHOW = "MerchantFrame",
    MAIL_SHOW = "MailFrame",
    AUCTION_HOUSE_SHOW = "AuctionHouseFrame",
    BANKFRAME_OPENED = "BankFrame",
    TRADE_SHOW = "TradeFrame",
    TRADE_SKILL_SHOW = "TradeSkillFrame",
    CRAFT_SHOW = "CraftFrame",
}
A.CLOSE = {
    MERCHANT_CLOSED = "MerchantFrame",
    MAIL_CLOSED = "MailFrame",
    AUCTION_HOUSE_CLOSED = "AuctionHouseFrame",
    BANKFRAME_CLOSED = "BankFrame",
    TRADE_CLOSED = "TradeFrame",
    TRADE_SKILL_CLOSE = "TradeSkillFrame",
    CRAFT_CLOSE = "CraftFrame",
}

A.pendingClose = {} -- Rahmenname → true: Schließen im Kampf verschoben

---------------------------------------------------------------------------
-- Entscheidung (auch von bag_core.lua gerufen)
---------------------------------------------------------------------------

-- Darf der Rahmen `name` das Fenster öffnen? Unbekannte Rahmen (z. B. Gegenstandsauswahl bei Zaubern) verhalten
-- sich wie bei Blizzard und dürfen.
function B.AutoAllowed(name)
    if B.GamepadActive() then return false end
    local key = type(name) == "string" and A.KEY[name] or nil
    if not key then return true end
    local db = ns.db
    if not db then return true end
    if db.noAutoBags then return false end
    return db[key] == true
end

local function TryOpen(name)
    if not B.Enabled() or not B.AutoAllowed(name) then return end
    if B.IsOpen() then return end
    if B.Open() then B.openerName = name end
end

local function TryClose(name)
    A.pendingClose[name] = nil
    if not B.Enabled() or not B.IsOpen() then return end
    if B.openerName ~= name then return end
    if not B.Close() then A.pendingClose[name] = true end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

do
    local ev = CreateFrame("Frame")
    for event in pairs(A.OPEN) do pcall(ev.RegisterEvent, ev, event) end
    for event in pairs(A.CLOSE) do pcall(ev.RegisterEvent, ev, event) end
    ev:SetScript("OnEvent", function(_, event)
        local ok, err = pcall(function()
            if A.OPEN[event] then TryOpen(A.OPEN[event]) end
            if A.CLOSE[event] then TryClose(A.CLOSE[event]) end
        end)
        if not ok then geterrorhandler()(err) end
    end)
end

-- Nach dem Kampf nachholen, was dort nicht ging
ns.On("PLAYER_REGEN_ENABLED", function()
    for name in pairs(A.pendingClose) do TryClose(name) end
end)

---------------------------------------------------------------------------
-- Charakterfenster (nur HookScript, nichts am Rahmen verändert)
---------------------------------------------------------------------------

do
    local hooked = false
    local function HookCharacter()
        local frame = _G.CharacterFrame
        if hooked or not frame or not frame.HookScript then return end
        hooked = true
        frame:HookScript("OnShow", function()
            -- einen Frame warten: Blizzards Öffnen-Kette ist dann durch
            C_Timer.After(0, function()
                if frame:IsShown() then pcall(TryOpen, "CharacterFrame") end
            end)
        end)
        frame:HookScript("OnHide", function()
            C_Timer.After(0, function()
                if not frame:IsShown() then pcall(TryClose, "CharacterFrame") end
            end)
        end)
    end
    ns.On("PLAYER_LOGIN", HookCharacter)
    ns.On("PLAYER_ENTERING_WORLD", HookCharacter)
end

---------------------------------------------------------------------------
-- Optionen (Bereich „Tasche“, Reiter „Automatik“)
---------------------------------------------------------------------------

do
    local function On() return ns.db and ns.db.bagWindow and true or false end
    local HINT = L["Erst „stray-Tasche“ einschalten (weiter oben)."]
    local NOTE = "\n\n" .. L["Ist „Taschen nicht automatisch öffnen“ (Automation, Reiter „Automatisch“) an, öffnet sich nichts von selbst."]

    local function Switch(key, label, tooltip, keywords)
        ns.AddOption(1, "Tasche", {
            key = key, label = label, tooltip = tooltip .. NOTE, keywords = keywords,
            isEnabled = On, disabledHint = HINT,
        })
    end

    Switch("bagAutoMerchant", L["Beim Händler öffnen"],
        L["Öffnet die stray-Tasche, wenn du ein Händlerfenster aufmachst, und schließt sie mit dem Fenster wieder. War sie vorher schon offen, bleibt sie offen."],
        { "händler", "verkäufer", "merchant", "vendor", "automatisch", "auto", "öffnen", "open" })
    Switch("bagAutoMail", L["Bei der Post öffnen"],
        L["Öffnet die stray-Tasche am Briefkasten und schließt sie mit dem Postfenster wieder. War sie vorher schon offen, bleibt sie offen."],
        { "post", "briefkasten", "mail", "mailbox", "automatisch", "auto", "öffnen", "open" })
    Switch("bagAutoAuction", L["Im Auktionshaus öffnen"],
        L["Öffnet die stray-Tasche im Auktionshaus und schließt sie mit dem Fenster wieder. War sie vorher schon offen, bleibt sie offen."],
        { "auktionshaus", "auktion", "auction", "ah", "automatisch", "auto", "öffnen", "open" })
    Switch("bagAutoBank", L["Bei der Bank öffnen"],
        L["Öffnet die stray-Tasche, wenn du die Bank aufmachst, und schließt sie mit der Bank wieder. War sie vorher schon offen, bleibt sie offen."],
        { "bank", "automatisch", "auto", "öffnen", "open" })
    Switch("bagAutoTrade", L["Beim Handel öffnen"],
        L["Öffnet die stray-Tasche, wenn ein Handel mit einem Spieler beginnt, und schließt sie mit dem Handelsfenster wieder. War sie vorher schon offen, bleibt sie offen."],
        { "handel", "handeln", "tauschen", "trade", "automatisch", "auto", "öffnen", "open" })
    Switch("bagAutoCraft", L["Bei Berufen öffnen"],
        L["Öffnet die stray-Tasche mit dem Berufsfenster (Herstellen, Verzaubern) und schließt sie mit ihm wieder. War sie vorher schon offen, bleibt sie offen."],
        { "beruf", "berufe", "herstellen", "profession", "crafting", "tradeskill", "automatisch", "auto", "öffnen", "open" })
    Switch("bagOpenWithCharacter", L["Mit dem Charakterfenster öffnen"],
        L["Öffnet die stray-Tasche zusammen mit dem Charakterfenster (C) und schließt sie mit ihm wieder. Hast du sie vorher selbst geöffnet, bleibt sie offen."],
        { "charakter", "charakterfenster", "character", "paperdoll", "ausrüstung", "equipment", "automatisch", "auto", "öffnen", "open" })
end
