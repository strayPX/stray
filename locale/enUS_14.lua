-- stray – englische Texte (Teil 14), Schlüssel = deutscher Originaltext
local _, ns = ...
local E = ns.LocaleEN

-- bagwindow.lua: Anheft-Leiste (5 Plätze) und Taschenplätze mit Tauschen (0.23.0-alpha)
E["Zeigt alle Taschen in einem Fenster mit Suche und Kategorien (Ausrüstung, Verbrauchbar, Handwerk, Quest, Neu). B-Taste, Rucksack-Knopf und Händler öffnen dann dieses Fenster statt Blizzards Taschen.\n\nQuestgegenstände stehen nur unter „Quest“, bis die Quest abgegeben ist.\n\nIn „Alle“ steht oben eine Anheft-Leiste mit 5 Plätzen (der Ruhestein sitzt anfangs auf Platz 1): Gegenstand hineinziehen heftet ihn an, Shift+Rechtsklick oder Herausziehen löst ihn. Angeheftetes benutzt du dort wie in der Tasche; unten im Raster steht es zusätzlich. Auch Alt+Rechtsklick auf einen Gegenstand heftet ihn an oder löst ihn. Kopfzeile ziehen verschiebt das Fenster, der Griff unten rechts ändert die Größe. Passt nicht alles hinein, blätterst du mit dem Mausrad. Der Besen neben der Suche sortiert die Taschen.\n\nAusschalten wirkt sofort; ganz sauber wird es nach Neuladen (/reload)."] = "Shows all bags in one window with search and categories (Gear, Consumables, Trade Goods, Quest, New). The B key, the backpack button and vendors then open this window instead of Blizzard's bags.\n\nQuest items stay under \"Quest\" until the quest is turned in.\n\nIn \"All\" there is a pin bar with 5 slots at the top (your Hearthstone starts in slot 1): drag an item in to pin it, Shift+right-click or drag it out to unpin. Pinned items are used there just like in your bags and still show up in the grid below. Alt+right-clicking an item also pins or unpins it. Drag the title bar to move the window, the grip at the bottom right resizes it. If not everything fits, scroll with the mouse wheel. The broom next to the search sorts your bags.\n\nTurning this off works right away; a reload (/reload) makes it fully clean."
E["Taschenplätze im Taschenfenster"] = "Bag slots in the bag window"
E["Zeigt links unten im stray-Taschenfenster den Rucksack und deine Taschenplätze. Tooltip: Name, Größe und freie Plätze; die Plätze dieser Tasche leuchten im Raster auf.\n\nTasche auf einen leeren Platz ziehen legt sie an. Neue Tasche auf einen belegten Platz ziehen: stray räumt die alte Tasche Schritt für Schritt in deine anderen Taschen aus, setzt die neue ein und legt die alte in deine Taschen. Nur außerhalb des Kampfes; Kampfbeginn bricht ab. Reicht der Platz nicht, sagt stray, wie viele Plätze fehlen."] = "Shows your backpack and bag slots at the bottom left of the stray bag window. Tooltip: name, size and free slots; that bag's slots light up in the grid.\n\nDrag a bag onto an empty slot to equip it. Drag a new bag onto a used slot: stray empties the old bag into your other bags step by step, equips the new one and puts the old one into your bags. Out of combat only; entering combat cancels it. If there isn't enough room, stray tells you how many slots are missing."
E["TASCHEN"] = "BAGS"
E["Tasche"] = "Bag"
E["Leerer Taschenplatz"] = "Empty bag slot"
E["Tasche hierher ziehen, um sie anzulegen."] = "Drag a bag here to equip it."
E["%d Plätze, davon %d frei"] = "%d slots, %d free"
E["Neue Tasche hierher ziehen: stray räumt die alte aus, setzt die neue ein und legt die alte in deine Taschen (nur außerhalb des Kampfes)."] = "Drag a new bag here: stray empties the old one, equips the new one and puts the old one into your bags (out of combat only)."
E["Packe um … %d / %d"] = "Repacking … %d / %d"
E["Tausche Tasche …"] = "Swapping bag …"
E["Kampf – Taschentausch abgebrochen. Bereits umgelagerte Gegenstände bleiben, wo sie sind."] = "Combat – bag swap cancelled. Items already moved stay where they are."
E["Umpacken hat nicht geklappt (Gegenstand gesperrt?). Abgebrochen."] = "Repacking failed (item locked?). Cancelled."
E["Die alte Tasche ist noch nicht leer. Abgebrochen."] = "The old bag isn't empty yet. Cancelled."
E["Die neue Tasche wurde nicht gefunden. Abgebrochen."] = "Couldn't find the new bag. Cancelled."
E["Einsetzen hat nicht geklappt – WoW hat die Tasche nicht angenommen."] = "Equipping failed – WoW didn't accept the bag."
E["Tasche getauscht – die alte liegt jetzt in deinen Taschen."] = "Bag swapped – the old one is now in your bags."
E["Taschen tauschen geht erst nach dem Kampf."] = "Bags can only be swapped out of combat."
E["Zieh die neue Tasche aus deinen Taschen auf den Taschenplatz."] = "Drag the new bag from your bags onto the bag slot."
E["Es fehlen %d freie Plätze – erst Platz schaffen."] = "%d free slots missing – make some room first."
E["stray tauscht gerade schon eine Tasche."] = "stray is already swapping a bag."
