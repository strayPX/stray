-- stray – englische Texte (Teil 8), Schlüssel = deutscher Originaltext
local _, ns = ...
local E = ns.LocaleEN

-- Datei: editmode.lua (Nachtrag 0.22.0-alpha: Shift + Rechtsklick, Rückgängig, neue Leiste)

-- Flächen über den Anzeigen
E["Klick: auswählen (Position, Größe, Pfeiltasten)"] = "Click: select (position, size, arrow keys)"
E["Shift + Rechtsklick: auf Standard zurücksetzen"] = "Shift + right-click: reset to default"

-- Fenster je Anzeige
E["auto"] = "auto"
E["Setzt diese Anzeige ganz auf den Standard zurück: Position, Größe und – wo vorhanden – Breite und Höhe. Auch mit Shift + Rechtsklick auf die Anzeige."] = "Fully resets this display to default: position, size and – where available – width and height. Also with Shift + right-click on the display."
E["Pfeiltasten: 1 px · mit Shift: 10 px\nStrg + Z: rückgängig · Esc hebt die Auswahl auf"] = "Arrow keys: 1 px · with Shift: 10 px\nCtrl + Z: undo · Esc clears the selection"

-- Hinweiszeile der Leiste
E["Klick"] = "Click"
E["auswählen"] = "select"
E["Ziehen"] = "Drag"
E["verschieben"] = "move"
E["Pfeiltasten"] = "Arrow keys"
E["fein verschieben"] = "fine-tune"
E["Shift + Rechtsklick"] = "Shift + right-click"
E["auf Standard zurücksetzen"] = "reset to default"
E["Strg + Z"] = "Ctrl + Z"
E["rückgängig"] = "undo"
E["Esc"] = "Esc"
E["beenden"] = "exit"

-- Knopf „Zurück“ und Alles zurücksetzen
E["Macht den letzten Schritt rückgängig (auch mit Strg + Z). Im Verlauf: %d. Er gilt bis zum Ende des Bearbeitungsmodus."] = "Undoes the last step (also with Ctrl + Z). In history: %d. It lasts until you exit Edit Mode."
E["Noch nichts rückgängig zu machen. Verschieben, Pfeiltasten, X/Y, Größe, Breite/Höhe und Zurücksetzen lassen sich hier Schritt für Schritt zurücknehmen (auch mit Strg + Z)."] = "Nothing to undo yet. Moving, arrow keys, X/Y, size, width/height and resets can be undone here step by step (also with Ctrl + Z)."
E["Setzt alle stray-Anzeigen auf ihre Standardposition und -größe (mit Rückfrage). Lässt sich mit „Zurück“ rückgängig machen."] = "Resets all stray displays to their default position and size (asks first). Can be undone with “Back”."

-- Option im stray-Fenster
E["Blendet alle eingeschalteten stray-Anzeigen ein und macht sie frei verschiebbar – ohne Shift. Klick wählt eine Anzeige aus: Daneben öffnet sich ein kleines Fenster mit X/Y (ab Bildschirmmitte), Größe in Prozent und – wo vorhanden – Breite und Höhe; Pfeiltasten schieben sie um 1 px, mit Shift um 10 px. Shift + Rechtsklick setzt eine Anzeige ganz auf Standard zurück. „Zurück“ oder Strg + Z macht den letzten Schritt rückgängig. Esc hebt die Auswahl auf, ein weiteres Esc oder „Fertig“ beendet den Modus. Die Leiste oben schaltet Raster und Einrasten an anderen Anzeigen und der Bildschirmmitte.\n\nBetrifft alle eingeschalteten stray-Anzeigen: Gruppenrahmen, Aktionsleisten, Abklingzeiten, Bedrohungsliste, DMG-Meter, Haltbarkeit, Erfahrungsleiste, Taschen- und Menüleiste, Taschenfenster, Swing-Timer, Vorrat, Flugzeit, Würfelfenster, Gefahr-Hinweis und die Warntexte. Geht nur außerhalb des Kampfes. Auch per /stray edit."] = "Shows all enabled stray displays and makes them freely movable – no Shift needed. Click selects a display: a small window opens next to it with X/Y (from the screen center), size in percent and – where available – width and height; arrow keys move it by 1 px, with Shift by 10 px. Shift + right-click fully resets a display to default. “Back” or Ctrl + Z undoes the last step. Esc clears the selection, another Esc or “Done” ends the mode. The bar at the top toggles the grid and snapping to other displays and the screen center.\n\nAffects all enabled stray displays: party frames, action bars, cooldowns, threat list, damage meter, durability, experience bar, bag and menu bar, bag window, swing timer, supplies, flight time, roll window, danger notice and the warning texts. Only out of combat. Also via /stray edit."
E["Erst die Tastenbelegung beenden (Speichern, Abbrechen oder Esc)."] = "Finish key binding first (Save, Cancel or Esc)."
