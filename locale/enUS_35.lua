-- stray – englische Texte (Teil 35), Schlüssel = deutscher Originaltext
local _, ns = ...
local E = ns.LocaleEN

-- Einstellungsseite „Tasche“ (ui.lua)
E["Fenster"] = "Window"
E["Abschnitte"] = "Sections"
E["Symbole"] = "Icons"
E["Automatik"] = "Automatic"

-- bag_auto.lua: automatisches Öffnen und Schließen
E["Ist „Taschen nicht automatisch öffnen“ (Automation, Reiter „Automatisch“) an, öffnet sich nichts von selbst."] = "If \"Don't open bags automatically\" (Automation, tab \"Automatisch\") is on, nothing opens by itself."
E["Beim Händler öffnen"] = "Open at vendors"
E["Öffnet die stray-Tasche, wenn du ein Händlerfenster aufmachst, und schließt sie mit dem Fenster wieder. War sie vorher schon offen, bleibt sie offen."] = "Opens the stray bag when you open a vendor window and closes it again with that window. If it was already open, it stays open."
E["Bei der Post öffnen"] = "Open at the mailbox"
E["Öffnet die stray-Tasche am Briefkasten und schließt sie mit dem Postfenster wieder. War sie vorher schon offen, bleibt sie offen."] = "Opens the stray bag at the mailbox and closes it again with the mail window. If it was already open, it stays open."
E["Im Auktionshaus öffnen"] = "Open at the auction house"
E["Öffnet die stray-Tasche im Auktionshaus und schließt sie mit dem Fenster wieder. War sie vorher schon offen, bleibt sie offen."] = "Opens the stray bag at the auction house and closes it again with that window. If it was already open, it stays open."
E["Bei der Bank öffnen"] = "Open at the bank"
E["Öffnet die stray-Tasche, wenn du die Bank aufmachst, und schließt sie mit der Bank wieder. War sie vorher schon offen, bleibt sie offen."] = "Opens the stray bag when you open the bank and closes it again with the bank. If it was already open, it stays open."
E["Beim Handel öffnen"] = "Open when trading"
E["Öffnet die stray-Tasche, wenn ein Handel mit einem Spieler beginnt, und schließt sie mit dem Handelsfenster wieder. War sie vorher schon offen, bleibt sie offen."] = "Opens the stray bag when a trade with a player starts and closes it again with the trade window. If it was already open, it stays open."
E["Bei Berufen öffnen"] = "Open with professions"
E["Öffnet die stray-Tasche mit dem Berufsfenster (Herstellen, Verzaubern) und schließt sie mit ihm wieder. War sie vorher schon offen, bleibt sie offen."] = "Opens the stray bag with the profession window (crafting, enchanting) and closes it again with that window. If it was already open, it stays open."
E["Mit dem Charakterfenster öffnen"] = "Open with the character window"
E["Öffnet die stray-Tasche zusammen mit dem Charakterfenster (C) und schließt sie mit ihm wieder. Hast du sie vorher selbst geöffnet, bleibt sie offen."] = "Opens the stray bag together with the character window (C) and closes it again with that window. If you opened it yourself beforehand, it stays open."

-- triage.lua: Tooltip der Option (stray-Tasche ergänzt)
E["Ist höchstens noch ein Platz frei, markiert stray den billigsten Gegenstand (Verkaufspreis × Anzahl) rot als Löschkandidat – in der stray-Tasche bzw. Blizzards Taschen und im Tooltip. Beute, die mehr wert ist, bekommt beim Plündern eine Goldmünze.\n\nNie vorgeschlagen werden Questgegenstände, Gegenstände ohne Verkaufswert und alles ab „selten“ (blau).\n\nstray löscht nichts selbst."] = "When at most one slot is left, stray marks the cheapest item (sell price × count) in red as a deletion candidate – in the stray bag or Blizzard's bags, and in the tooltip. Loot worth more gets a gold coin while looting.\n\nNever suggested: quest items, items without sell value and anything \"rare\" (blue) or better.\n\nstray never deletes anything itself."
