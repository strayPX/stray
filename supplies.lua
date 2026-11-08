-- stray – Vorrat: Erinnerung an Reagenzien, Munition, Essen, Wasser und eigene Buffs
--
-- Eine verschiebbare Symbolreihe zeigt nur, was gerade fehlt oder knapp wird. Der Tooltip
-- jedes Symbols sagt, was fehlt und wie viel noch da ist.
--
--   Reagenzien: für gelernte Zauber, die welche brauchen. Die Zauberkosten auf Forever
--               (C_Spell.GetSpellPowerCost) enthalten keine Reagenzien, darum eine kleine
--               Tabelle der Classic-Zauber. Hat ein Zauber mehrere Ränge mit anderem
--               Reagenz, zählt das Reagenz des höchsten gelernten Rangs.
--   Munition:   Jäger, Anzahl der angelegten Munition (Munitionsplatz) in den Taschen.
--   Essen:      Nahrung in den Taschen; Wasser nur für Klassen mit Mana.
--   Buffs:      fehlende eigene Klassenbuffs (Rüstungszauber, Inneres Feuer …). Auren sind
--               im Kampf versiegelt, darum nur außerhalb des Kampfes prüfen und den Stand vor
--               dem Kampf behalten.
--
-- Um die Symbole laufen immer gelbe Striche (ns.Glow aus glow.lua), sobald die Erinnerung an ist.
--
-- Sichtbare Texte in den Tabellen stehen als deutsche Schlüssel und werden erst beim Anzeigen
-- mit L übersetzt (die Sprache ist zur Ladezeit noch nicht gewählt).
--
-- Aktualisiert bei BAG_UPDATE_DELAYED, UNIT_AURA (player, gedrosselt, nicht im Kampf),
-- PLAYER_REGEN_ENABLED, SPELLS_CHANGED und beim Wechsel der Ausrüstung.

local _, ns = ...
local L = ns.L

local SECTION = "Vorrat"

ns.defaults.supplies = false
ns.defaults.supReagents = true -- wirken erst, wenn „supplies“ an ist
ns.defaults.supAmmo = true
ns.defaults.supFood = true
ns.defaults.supBuffs = true
ns.defaults.supThreshold = 10

local AMMO_FACTOR = 20 -- Munition: Warnschwelle × 20 (bei 10 also 200 Schuss = ein Stapel)
local MANA_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, HUNTER = true }

local FONT = "Fonts\\ARIALN.TTF"
-- stray-Farben aus ns.Colors (stray.lua); Ersatzwerte, falls die Tabelle fehlt. Rot bleibt Warnfarbe.
local COLORS = ns.Colors or {}
local C = {
    bg     = COLORS.bg or { 0.078, 0.078, 0.098, 0.96 },
    border = COLORS.line or { 0.149, 0.149, 0.184, 1 },
    text   = COLORS.text or { 0.902, 0.902, 0.925, 1 },
    dim    = COLORS.textDim or { 0.545, 0.545, 0.600, 1 },
    faint  = COLORS.textFaint or { 0.369, 0.369, 0.420, 1 },
    warn   = { 1.000, 0.300, 0.300, 1 },
}

local ICON = 32
local GAP = 4

---------------------------------------------------------------------------
-- Tabellen (Classic-Zauber-IDs = Rang 1, Gegenstands-IDs)
---------------------------------------------------------------------------

-- Reagenzien: ranks = { { Zauber, Gegenstand }, … } aufsteigend; es zählt der höchste
-- gelernte Eintrag. cap begrenzt die Warnschwelle für Reagenzien, die man nur in kleiner
-- Zahl dabeihat. name ist der Ersatzname, solange der Gegenstand nicht im Cache ist.
local REAGENTS = {
    PRIEST = {
        { label = "Gebet der Seelenstärke", ranks = {
            { 21562, 17028 }, -- Gebet der Seelenstärke R1 → Heilige Kerze
            { 21564, 17029 }, -- Gebet der Seelenstärke R2 → Geweihte Kerze
        } },
        { label = "Gebet der Willenskraft / des Schattenschutzes", ranks = {
            { 27681, 17029 }, -- Gebet der Willenskraft → Geweihte Kerze
            { 27683, 17029 }, -- Gebet des Schattenschutzes → Geweihte Kerze
        } },
        { label = "Levitieren", cap = 5, ranks = {
            { 1706, 17056 }, -- Levitieren → Leichte Feder
        } },
    },
    MAGE = {
        { label = "Teleportieren", cap = 5, ranks = {
            { 3561, 17031 }, -- Teleportieren: Sturmwind → Rune der Teleportation
            { 3562, 17031 }, -- Teleportieren: Eisenschmiede
            { 3565, 17031 }, -- Teleportieren: Darnassus
            { 3567, 17031 }, -- Teleportieren: Orgrimmar
            { 3563, 17031 }, -- Teleportieren: Unterstadt
            { 3566, 17031 }, -- Teleportieren: Donnerfels
        } },
        { label = "Portale", cap = 5, ranks = {
            { 10059, 17032 }, -- Portal: Sturmwind → Rune der Portale
            { 11416, 17032 }, -- Portal: Eisenschmiede
            { 11419, 17032 }, -- Portal: Darnassus
            { 11417, 17032 }, -- Portal: Orgrimmar
            { 11418, 17032 }, -- Portal: Unterstadt
            { 11420, 17032 }, -- Portal: Donnerfels
        } },
        { label = "Arkane Brillanz", ranks = {
            { 23028, 17020 }, -- Arkane Brillanz → Arkanes Pulver
        } },
        { label = "Langsamer Fall", cap = 5, ranks = {
            { 130, 17056 }, -- Langsamer Fall → Leichte Feder
        } },
    },
    SHAMAN = {
        { label = "Reinkarnation", cap = 2, ranks = {
            { 20608, 17030 }, -- Reinkarnation → Ankh
        } },
    },
    WARLOCK = {
        { label = "Seelensplitter-Zauber", cap = 5, ranks = {
            { 697, 6265 },  -- Leerwandler beschwören → Seelensplitter
            { 6201, 6265 }, -- Gesundheitsstein herstellen (schwach)
            { 693, 6265 },  -- Seelenstein herstellen (schwach)
            { 698, 6265 },  -- Ritual der Beschwörung
        } },
    },
    DRUID = {
        { label = "Wiedergeburt", cap = 3, ranks = {
            { 20484, 17034 }, -- Wiedergeburt R1 → Ahornsamen
            { 20739, 17035 }, -- R2 → Schlingdornsamen
            { 20742, 17036 }, -- R3 → Eschenholzsamen
            { 20747, 17037 }, -- R4 → Hainbuchensamen
            { 20748, 17038 }, -- R5 → Eisenholzsamen
        } },
        { label = "Gabe der Wildnis", ranks = {
            { 21849, 17021 }, -- Gabe der Wildnis R1 → Wildbeeren
            { 21850, 17026 }, -- R2 → Wilddornrose
        } },
    },
    PALADIN = {
        { label = "Große Segen", ranks = {
            { 25898, 21177 }, -- Großer Segen der Könige → Symbol der Könige
            { 25782, 21177 }, -- Großer Segen der Macht
            { 25894, 21177 }, -- Großer Segen der Weisheit
            { 25895, 21177 }, -- Großer Segen der Rettung
            { 25890, 21177 }, -- Großer Segen des Lichts
            { 25899, 21177 }, -- Großer Segen des Refugiums
        } },
    },
    -- Schurke: Blitzpulver und Gifte bewusst nicht
}

local ITEM_NAMES = {
    [17028] = "Heilige Kerze", [17029] = "Geweihte Kerze", [17056] = "Leichte Feder",
    [17031] = "Rune der Teleportation", [17032] = "Rune der Portale", [17020] = "Arkanes Pulver",
    [17030] = "Ankh", [6265] = "Seelensplitter", [17034] = "Ahornsamen", [17035] = "Schlingdornsamen",
    [17036] = "Eschenholzsamen", [17037] = "Hainbuchensamen", [17038] = "Eisenholzsamen",
    [17021] = "Wildbeeren", [17026] = "Wilddornrose", [21177] = "Symbol der Könige",
}

-- Eigene Buffs: known = eine dieser Zauber gelernt → Buff erwartet;
-- present = jeder dieser Zauber (per Name, also jeder Rang) zählt als vorhanden
local BUFFS = {
    MAGE = {
        { label = "Rüstungszauber", known = { 168, 7302, 6117 } }, -- Frost-, Eis-, Magische Rüstung
        { label = "Arkane Intelligenz", known = { 1459 }, present = { 1459, 23028 } }, -- + Arkane Brillanz
    },
    PRIEST = {
        { label = "Inneres Feuer", known = { 588 } },
        { label = "Machtwort: Seelenstärke", known = { 1243 }, present = { 1243, 21562 } }, -- + Gebet
    },
    WARLOCK = {
        { label = "Dämonenhaut / Dämonenrüstung", known = { 687, 706 } },
    },
    DRUID = {
        { label = "Mal der Wildnis", known = { 1126 }, present = { 1126, 21849 } }, -- + Gabe der Wildnis
    },
    PALADIN = {
        -- Andacht, Vergeltung, Konzentration, Schatten-, Frost-, Feuerwiderstand, Heiligkeit
        { label = "Aura", known = { 465, 7294, 19746, 19876, 19888, 19891, 20218 } },
    },
    HUNTER = {
        -- Falke, Affe, Gepard, Rudel, Wildnis, Wildtier
        { label = "Aspekt", known = { 13165, 13163, 5118, 13159, 20043, 13161 } },
    },
    SHAMAN = {
        { label = "Blitzschlagschild", known = { 324 } },
    },
}

local FOOD_SPELL, DRINK_SPELL = 433, 430 -- „Essen“ und „Trinken“ (Name gilt für alle Ränge)
local FOOD_ICON = "Interface\\Icons\\INV_Misc_Food_15"
local DRINK_ICON = "Interface\\Icons\\INV_Drink_07"
local AMMO_ICON = "Interface\\Icons\\INV_Ammo_Arrow_02"

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function PlayerClass()
    local _, class = UnitClass("player")
    return ns.Public(class)
end

local function Known(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and not ns.IsSecret(known) then return known == true end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and not ns.IsSecret(known) then return known == true end
    end
    return false
end

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and not ns.IsSecret(name) and type(name) == "string" then return name end
    end
end

local function SpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and not ns.IsSecret(icon) then return icon end
    end
end

local function ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemID)
        if ok and type(n) == "number" then return n end
    end
    return 0
end

local function ItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if ITEM_NAMES[itemID] then return L[ITEM_NAMES[itemID]] end
    return L("Gegenstand %d", itemID)
end

local function ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Threshold(cap)
    local t = (ns.db and ns.db.supThreshold) or 10
    if cap and cap < t then return cap end
    return t
end

---------------------------------------------------------------------------
-- Prüfungen: jede liefert Einträge { icon, count, title, lines }
---------------------------------------------------------------------------

local function CheckReagents(out)
    local list = REAGENTS[PlayerClass() or ""]
    if not list then return end
    local seen = {}
    for _, spell in ipairs(list) do
        local item
        for _, rank in ipairs(spell.ranks) do
            if Known(rank[1]) then item = rank[2] end
        end
        if item then
            local need = Threshold(spell.cap)
            local have = ItemCount(item)
            local entry = seen[item]
            if entry then
                entry.uses[#entry.uses + 1] = L[spell.label]
                if need > entry.need then entry.need = need end
            elseif have < need then
                entry = { icon = ItemIcon(item), count = have, need = need, item = item, uses = { L[spell.label] } }
                seen[item] = entry
                out[#out + 1] = entry
            end
        end
    end
    for _, entry in ipairs(out) do
        if entry.item then
            entry.title = ItemName(entry.item)
            entry.lines = {
                { L("Noch %d, Warnschwelle %d", entry.count, entry.need), entry.count == 0 and C.warn or C.text },
                { L("Für: %s", table.concat(entry.uses, ", ")), C.dim },
            }
        end
    end
end

local function AmmoSlot()
    if C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo then
        local ok, slot = pcall(C_PaperDollInfo.GetInventorySlotInfo, "AmmoSlot")
        if ok and type(slot) == "number" then return slot end
    end
    return INVSLOT_AMMO or 0
end

local function CheckAmmo(out)
    if PlayerClass() ~= "HUNTER" then return end
    -- Fernkampfwaffe ohne Munitionsbedarf (z. B. Wurfwaffe): nichts melden
    if C_PaperDollInfo and C_PaperDollInfo.AmmoNeeded then
        local ok, needed = pcall(C_PaperDollInfo.AmmoNeeded)
        if ok and needed == false then return end
    end
    local need = Threshold() * AMMO_FACTOR
    local ammoID = GetInventoryItemID and GetInventoryItemID("player", AmmoSlot())
    if ns.IsSecret(ammoID) then return end
    local have = ammoID and ItemCount(ammoID) or 0
    if have >= need then return end
    out[#out + 1] = {
        icon = ammoID and ItemIcon(ammoID) or AMMO_ICON,
        count = have,
        title = ammoID and ItemName(ammoID) or L["Munition"],
        lines = {
            ammoID and { L("Noch %d Schuss, Warnschwelle %d", have, need), have == 0 and C.warn or C.text }
                or { L["Keine Munition angelegt."], C.warn },
        },
    }
end

-- Essen/Trinken je Gegenstands-ID merken („food“, „drink“ oder false)
local foodKind = {}

local function FoodKind(itemID)
    local cached = foodKind[itemID]
    if cached ~= nil then return cached end
    if not (C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemSpell) then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= 0 then -- kein Verbrauchsgegenstand
        foodKind[itemID] = false
        return false
    end
    local spellName = C_Item.GetItemSpell(itemID)
    if type(spellName) ~= "string" then return false end -- noch nicht geladen, später nochmal
    local kind = false
    if spellName == SpellName(FOOD_SPELL) then
        kind = "food"
    elseif spellName == SpellName(DRINK_SPELL) then
        kind = "drink"
    end
    foodKind[itemID] = kind
    return kind
end

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots

local function CheckFood(out)
    if not (C_Container and C_Container.GetContainerItemInfo) then return end
    local food, drink = 0, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, GetNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and type(info.itemID) == "number" then
                local kind = FoodKind(info.itemID)
                if kind == "food" then
                    food = food + (info.stackCount or 1)
                elseif kind == "drink" then
                    drink = drink + (info.stackCount or 1)
                end
            end
        end
    end
    local need = Threshold()
    if food < need then
        out[#out + 1] = {
            icon = FOOD_ICON, count = food, title = L["Essen"],
            lines = { { L("Noch %d, Warnschwelle %d", food, need), food == 0 and C.warn or C.text } },
        }
    end
    if MANA_CLASSES[PlayerClass() or ""] and drink < need then
        out[#out + 1] = {
            icon = DRINK_ICON, count = drink, title = L["Wasser"],
            lines = { { L("Noch %d, Warnschwelle %d", drink, need), drink == 0 and C.warn or C.text } },
        }
    end
end

-- Stand der Buffs vor dem Kampf (im Kampf sind Auren versiegelt)
local missingBuffs = {}

local function ScanBuffs()
    if InCombatLockdown() then return end -- Stand vor dem Kampf behalten
    local result = {}
    local groups = BUFFS[PlayerClass() or ""]
    if not groups or UnitIsDeadOrGhost("player") or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        missingBuffs = result
        return
    end
    local names = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or type(aura) ~= "table" then break end
        local name = aura.name
        if not ns.IsSecret(name) and type(name) == "string" then names[name] = true end
    end
    for _, group in ipairs(groups) do
        local knownID
        for _, id in ipairs(group.known) do
            if Known(id) then knownID = knownID or id end
        end
        if knownID then
            local present = false
            for _, id in ipairs(group.present or group.known) do
                local name = SpellName(id)
                if name and names[name] then present = true break end
            end
            if not present then
                result[#result + 1] = {
                    icon = SpellIcon(knownID) or "Interface\\Icons\\INV_Misc_QuestionMark",
                    title = L[group.label],
                    lines = { { L["Fehlt gerade."], C.warn } },
                }
            end
        end
    end
    missingBuffs = result
end

local function CheckBuffs(out)
    for _, entry in ipairs(missingBuffs) do out[#out + 1] = entry end
end

---------------------------------------------------------------------------
-- Symbolreihe
---------------------------------------------------------------------------

local holder = CreateFrame("Frame", "straySupplies", UIParent)
holder:SetSize(ICON, ICON)
holder:SetFrameStrata("MEDIUM")
ns.MakeMovable(holder, "supplies", { "TOP", "TOP", 0, -120 })
holder:Hide()

local icons = {}

local function OnIconEnter(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(e.title or "", 1, 1, 1)
    for _, line in ipairs(e.lines or {}) do
        local c = line[2] or C.text
        GameTooltip:AddLine(line[1], c[1], c[2], c[3], true)
    end
    GameTooltip:AddLine(L["Shift + ziehen zum Verschieben"], C.faint[1], C.faint[2], C.faint[3])
    GameTooltip:Show()
end

local function CreateIcon(i)
    local b = CreateFrame("Frame", nil, holder)
    b:SetSize(ICON, ICON)
    b:SetPoint("LEFT", holder, "LEFT", (i - 1) * (ICON + GAP), 0)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
    end
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(FONT, 12, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.count:SetTextColor(C.text[1], C.text[2], C.text[3])
    b:EnableMouse(true)
    b:SetScript("OnEnter", OnIconEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Ziehen am Symbol verschiebt die ganze Reihe
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function() local f = holder:GetScript("OnDragStart"); if f then f(holder) end end)
    b:SetScript("OnDragStop", function() local f = holder:GetScript("OnDragStop"); if f then f(holder) end end)
    icons[i] = b
    return b
end

-- Beispielinhalt; wird beim Anzeigen gebaut, damit die gewählte Sprache gilt
local function SampleEntries()
    return {
        { icon = "Interface\\Icons\\INV_Misc_Candle_01", count = 3, title = L["Beispiel: Heilige Kerze"],
          lines = { { L["Noch 3, Warnschwelle 10"], C.text }, { L["Für: Gebet der Seelenstärke"], C.dim } } },
        { icon = AMMO_ICON, count = 120, title = L["Beispiel: Munition"], lines = { { L["Noch 120 Schuss, Warnschwelle 200"], C.text } } },
        { icon = FOOD_ICON, count = 4, title = L["Beispiel: Essen"], lines = { { L["Noch 4, Warnschwelle 10"], C.text } } },
        { icon = DRINK_ICON, count = 0, title = L["Beispiel: Wasser"], lines = { { L["Noch 0, Warnschwelle 10"], C.warn } } },
        { icon = "Interface\\Icons\\Spell_Holy_InnerFire", title = L["Beispiel: Inneres Feuer"], lines = { { L["Fehlt gerade."], C.warn } } },
    }
end

local function Collect()
    local out = {}
    local db = ns.db
    if db.supReagents then pcall(CheckReagents, out) end
    if db.supAmmo then pcall(CheckAmmo, out) end
    if db.supFood then pcall(CheckFood, out) end
    if db.supBuffs then CheckBuffs(out) end
    return out
end

local function SetGlow(b, on)
    if ns.Glow then pcall(ns.Glow, b, on and true or false) end
end

-- Der laufende Rand gehört fest zur Vorrats-Erinnerung (Show läuft nur, wenn sie an ist)
local function Show(entries)
    for i, e in ipairs(entries) do
        local b = icons[i] or CreateIcon(i)
        b.entry = e
        b.tex:SetTexture(e.icon)
        b.count:SetText(e.count and tostring(e.count) or "")
        b:Show()
        SetGlow(b, true)
    end
    for i = #entries + 1, #icons do
        icons[i].entry = nil
        icons[i]:Hide()
        SetGlow(icons[i], false)
    end
    if #entries == 0 then
        holder:Hide()
        return
    end
    holder:SetWidth(#entries * ICON + (#entries - 1) * GAP)
    holder:Show()
end

local function Update()
    if not ns.db or not ns.db.supplies then
        for _, b in ipairs(icons) do SetGlow(b, false) end
        holder:Hide()
        return
    end
    if ns.IsConfigOpen() then
        Show(SampleEntries())
        return
    end
    Show(Collect())
end

-- Kurz gesammelt aktualisieren (viele Ereignisse kommen gebündelt)
local pending = false
local function Request(scanBuffs)
    if scanBuffs and ns.db and ns.db.supplies and ns.db.supBuffs then pcall(ScanBuffs) end
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        local ok, err = pcall(Update)
        if not ok then geterrorhandler()(err) end
    end)
end

ns.RegisterMovable(holder, "Vorrat", function() Request() end)
ns.OnConfig(function() Request() end)

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

-- UNIT_AURA nur für den Spieler, gedrosselt, nie im Kampf
local auraFrame = CreateFrame("Frame")
local auraTimer = false
auraFrame:SetScript("OnEvent", function()
    if InCombatLockdown() or auraTimer then return end
    auraTimer = true
    C_Timer.After(0.5, function()
        auraTimer = false
        if not InCombatLockdown() then Request(true) end
    end)
end)

local function ApplyEvents()
    if ns.db.supplies and ns.db.supBuffs then
        if auraFrame.RegisterUnitEvent then
            pcall(auraFrame.RegisterUnitEvent, auraFrame, "UNIT_AURA", "player")
        else
            pcall(auraFrame.RegisterEvent, auraFrame, "UNIT_AURA")
        end
    else
        auraFrame:UnregisterAllEvents()
    end
end

local function Refresh()
    ApplyEvents()
    Request(true)
end

ns.On("PLAYER_LOGIN", function()
    ns.RestorePosition(holder)
    ApplyEvents()
    -- Gegenstands- und Zauberdaten sind kurz nach dem Login vollständiger
    C_Timer.After(3, function() Request(true) end)
end)
ns.On("PLAYER_ENTERING_WORLD", function() Request(true) end)
ns.On("BAG_UPDATE_DELAYED", function() Request() end)
ns.On("PLAYER_REGEN_ENABLED", function() Request(true) end)
ns.On("SPELLS_CHANGED", function() Request(true) end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() Request() end)
ns.On("PLAYER_DEAD", function() Request(true) end)
ns.On("PLAYER_UNGHOST", function() Request(true) end)

---------------------------------------------------------------------------
-- Optionen
---------------------------------------------------------------------------

local function IsOn() return ns.db and ns.db.supplies end

ns.AddOption(1, SECTION, {
    key = "supplies",
    label = L["Vorrats-Erinnerung"],
    tooltip = L["Eine kleine Symbolreihe zeigt, was dir fehlt oder knapp wird: Reagenzien für deine Zauber, Munition, Essen und Wasser, fehlende eigene Buffs. Ist alles da, bleibt sie unsichtbar. Gelbe Striche laufen um die Symbole, damit fehlende Sachen sofort auffallen.\n\nDer Tooltip jedes Symbols sagt, was fehlt und wie viel noch da ist. Mit Shift + linker Maustaste verschiebst du die Reihe."],
    set = function(value)
        ns.db.supplies = value
        Refresh()
    end,
})

ns.AddOption(1, SECTION, {
    key = "supReagents",
    label = L["Reagenzien"],
    tooltip = L["Reagenzien für Zauber, die du gelernt hast: z. B. Kerzen beim Priester, Runen beim Magier, Ankh beim Schamanen, Seelensplitter beim Hexenmeister, Samen und Kräuter beim Druiden, Symbol der Könige beim Paladin.\n\nAnkh, Seelensplitter, Runen, Federn und Samen warnen schon bei wenigen Stück."],
    isEnabled = IsOn,
    set = function(value) ns.db.supReagents = value; Refresh() end,
})

ns.AddOption(1, SECTION, {
    key = "supAmmo",
    label = L["Munition"],
    tooltip = L["Für Jäger: warnt, wenn die angelegte Munition in den Taschen knapp wird. Die Schwelle ist das Zwanzigfache der Warnschwelle (bei 10 also 200 Schuss)."],
    isEnabled = IsOn,
    set = function(value) ns.db.supAmmo = value; Refresh() end,
})

ns.AddOption(1, SECTION, {
    key = "supFood",
    label = L["Essen und Wasser"],
    tooltip = L["Warnt, wenn Essen knapp wird. Wasser nur für Klassen mit Mana."],
    isEnabled = IsOn,
    set = function(value) ns.db.supFood = value; Refresh() end,
})

ns.AddOption(1, SECTION, {
    key = "supBuffs",
    label = L["Eigene Buffs"],
    tooltip = L["Zeigt fehlende eigene Klassenbuffs, z. B. Rüstungszauber und Arkane Intelligenz beim Magier, Inneres Feuer und Seelenstärke beim Priester, Dämonenhaut beim Hexenmeister, Mal der Wildnis, Paladin-Aura, Jäger-Aspekt, Blitzschlagschild.\n\nGeprüft wird nur außerhalb des Kampfes, im Kampf bleibt der letzte Stand stehen."],
    isEnabled = IsOn,
    set = function(value) ns.db.supBuffs = value; Refresh() end,
})

ns.AddOption(1, SECTION, {
    key = "supThreshold",
    type = "slider",
    label = L["Warnschwelle (Stück)"],
    tooltip = L["Ab dieser Stückzahl warnt stray bei Reagenzien, Essen und Wasser. Munition: das Zwanzigfache."],
    min = 1, max = 40, step = 1,
    isEnabled = IsOn,
    set = function(value) ns.db.supThreshold = value; Request() end,
})
