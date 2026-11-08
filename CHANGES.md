# stray 2.0.0

**stray ist jetzt ein reines Komfort-Addon.** Alle eigenen Oberflächen-Elemente sind entfernt; Blizzards Oberfläche gilt wieder. Es bleiben DMG-Meter, Bedrohung, EP-Tracker und alle Komfort-Funktionen. Einstellungen der entfernten Teile werden beim ersten Start gelöscht (alle anderen bleiben).

**Entfernt**
- Eigene Aktionsleisten samt Tastenbelegung, Abklingzeiten über den Leisten, Taschenfenster, Taschen-/Menüleiste, eckige Minimap und Minimap-Knopf, Gruppenrahmen, Erfahrungsleiste, Uhr/FPS, Vorrats-Erinnerung und Schwungtimer.

**Neu (alles standardmäßig aus)**
- **Automation:** Geist im Schlachtfeld freigeben, automatisch aufstehen/absteigen, Beute-Bindung bestätigen, Taschen nicht automatisch öffnen.
- **Sozial:** Freundschaftsanfragen, Haustierduelle und geteilte Quests blockieren, Einladung per Flüstern.
- **Chat:** 14 neue Optionen (frei verschieben, Eingabezeile oben, kein Verblassen, Klassenfarben, Raid-Farbe, 4096 Zeilen, Wiederherstellen nach /reload, kopierbarer Verlauf, Spam-Filter, Kampflog- und Knöpfe ausblenden …).
- **Ausblenden & Text:** Zonentext, Porträtzahlen, Tasten-/Makrotext, Talking Head, Alerts, Boss-Banner, Greifen, Ruhe-Animation, Raid-Titel; größere Mail-, Quest- und Buchtexte.
- **Tooltip & Charakter:** Klassenfarbe, Ziel, Gildenrang, Maus-Anker, Skalierung, IDs; Lautstärkeregler, Helm/Umhang, Anprobe, Wowhead-Link.
- **Grafik & Ton:** Bildschirmglühen und -effekte aus, Wetterdichte, Sound folgt dem Systemgerät.
- **Einstellungsfenster neu geordnet:** Übersicht, Automation, Sozial & Chat, Interface, Kampf, Welt, stray.

**Geändert**
- EP-Tracker: ein Schalter für Tracking und Tabelle. DMG-Meter: Balkenhelligkeit fest.
- Hilfe bei vollen Taschen markiert nur noch in Blizzards Taschen.

# stray 1.1.0

**Neu**
- **DMG-Meter durchsichtig mit Symbol-Kopfzeile:** neue Option „Hintergrund-Deckkraft“ (0–100 %, Standard je Stil: „stray“ wie bisher, „Forever UI“ 0 % ohne Rahmen). Kopfzeile ohne Hintergrund: Titel weiß mit schwarzem Rand, rechts kleine graue Symbole statt Textknöpfen (Plus, Zurücksetzen, Schwerter/Herz für Schaden/Heilung, Zahnrad öffnet die DMG-Meter-Einstellungen, × bei Zusatzfenstern). Im Bearbeitungsmodus und beim Verschieben liegt eine halbdurchsichtige schwarze Fläche hinter dem Fenster.
- **Oberflächen-Art „Forever UI“** (System → Allgemein, wirkt nach dem Neuladen): Bronze-Gold-Rahmen, dunkler Schiefer, goldene Überschriften in Friz Quadrata, trapezförmige Reiter, rot-bronzene Hauptknöpfe. Gilt für das stray-Fenster, die DMG-Meter-Fenster, die Bedrohungsliste, die Aktionsleisten-Knöpfe und die Bearbeitungsleiste. Die bisherige Art „stray“ (lila, flach) bleibt Standard und unverändert.
- **Hinweis im Chat nach einem Update:** stray sagt, ob nach dem Update ein `/reload` reicht oder WoW komplett neu gestartet werden muss (abschaltbar).
- Aktionsleisten: **Shift+Klick zum Verschieben** löst die Aktion nicht mehr aus (gesperrte Leisten).
- Der laufende Rand um fehlende Vorrats-Symbole braucht weniger Leistung.
- **Einstellungsfenster neu geordnet:** 6 Seiten nach dem Ort im Spiel (Leisten & Menü, Karte & Gruppe, Taschen & Handel, Kampf, Welt & Quests, stray) plus **Übersicht** mit **Bildschirmkarte** (Klick auf einen Bereich öffnet dessen Einstellungen), „Zuletzt geändert“ und die Seite **Alle Anzeigen**. Alle Optionen sind noch da.
- **Taschenfenster und Taschen-/Menüleiste** im Stil „Forever UI“.
- **Taschenplätze im Taschenfenster** (Rucksack und ausgerüstete Taschen) sind jetzt standardmäßig an.

**Entfernt**
- **stray-Questtracker** samt Berufsreagenzien-Abschnitt und Questgegenstand-Knöpfen. Blizzards Questverfolgung (oder Questie) zeigt wieder die Quests. Die Konfliktwarnung für Questie (Auto-Annehmen/Abgeben) bleibt.

# stray 1.0.0

Erste stabile Version. Enthält alle Änderungen seit 0.19.0-alpha (0.20 bis 0.23), die nie einzeln veröffentlicht wurden.

**Neu**
- **Verfolgungs-Knopf an der eckigen Minimap:** kleine Lupe oben links neben dem Kartenmenü-Knopf. Klick öffnet die Verfolgungsliste (Briefkasten, Kräuter, Erze …) mit Häkchen, der Tooltip zeigt die aktive Verfolgung. Abschaltbar unter Minimap.
- **Berufsreagenzien im Questtracker:** verfolgte Rezepte erscheinen als eigener Abschnitt unter den Quests mit den Reagenzien als „vorhanden / benötigt“ (Taschen, Bank, Reagenzienbank). Einklappbar, abschaltbar. Blizzards eigene Liste überlappt den Tracker damit nicht mehr, wenn „Blizzard-Questverfolgung ausblenden“ an ist.

# Aus 0.23.0-alpha

Diese Version enthält auch 0.22.0-alpha, 0.21.0-alpha und 0.20.0-alpha, die nie einzeln veröffentlicht wurden (siehe unten).

**Neues stray-Fenster**
- Neu aufgebaut: breites Suchfeld oben, links die Seiten **Zentrale** · Oberfläche (Aktionsleisten, Einheiten, Taschen & Minimap) · Spielhilfen (Kampf & Anzeigen, Komfort) · System (Profile, Sprache & System), unten links die Profil-Auswahl.
- Jede Seite mit Häkchen **„Aktiv“** und **Reitern**, Inhalt in einer Spalte mit klaren Abschnitten. Regler haben ein **Zahlenfeld** zum Eintippen, Auswahlen sind Klapplisten.
- **Position X/Y** und „Zentrieren“ direkt auf der Seite. Bei mehreren Leisten bzw. DMG-Meter-Fenstern wählst du oben, welche du einstellst.
- Unten „n Änderungen“, **Verwerfen** und **Übernehmen** (neu laden nur, wenn nötig).
- Auf Englisch heißt „Komfort“ jetzt **„Quality of Life“**.

**Bearbeitungsmodus**
- Schlanke Leiste oben: Zurück, Raster, Einrasten, Alles zurücksetzen, **Tasten belegen**, Fertig.
- Die gewählte Anzeige bekommt einen lila Rahmen mit Eckgriffen; das stray-Fenster springt danach zur passenden Seite.

**DMG-Meter**
- **„+“** im Kopf öffnet eine Kopie, die oben andockt – bis zu **5 Fenster**. „×“ schließt ein zusätzliches Fenster.
- Alle Fenster lassen sich an jedes andere andocken oder frei verschieben. Dein bisheriges zweites Fenster wird zu Fenster 2.

**Questtracker (neu)**
- Eigene Questliste **rechts am Bildschirmrand**, leicht dunkel hinterlegt, rechtsbündig.
- Gebiete einzeln einklappbar, Klick auf „Quests“ klappt alles ein, Größe unten links ziehen.
- Questnamen in **Schwierigkeitsfarbe**, erfüllte Ziele grün mit Haken, „Bereit zur Abgabe“.
- **Questgegenstände als Knopf** direkt an der Quest – auch im Kampf benutzbar.
- Blizzards Questverfolgung wird ausgeblendet. Mit **Questie** arbeitet stray zusammen (Hinweis, falls Questies eigene Liste noch an ist).

**Tasten belegen (neu)**
- Über einen Knopf der stray-Aktionsleisten fahren und eine Taste drücken – auch **Shift/Strg/Alt**-Kombinationen, Maustasten 3–5 und Mausrad.
- Entf oder Rechtsklick löscht, Speichern für alle Charaktere oder nur diesen, Abbrechen stellt alles wieder her. Start über die Aktionsleisten-Seite, den Bearbeitungsmodus oder `/stray keys`.

**Taschen**
- **Anheft-Leiste** mit höchstens 5 Plätzen; Angeheftetes steht zusätzlich normal in der Tasche, mehr Abstand dazwischen.
- **Taschenplätze** im Taschenfenster (Option): Rucksack und Taschen mit freien Plätzen, Hover hebt die Plätze hervor.
- **Tasche tauschen mit Umpacken:** neue Tasche auf eine alte ziehen – stray räumt die alte aus, setzt die neue ein und legt die alte ab. Reicht der Platz nicht, sagt stray, wie viele Plätze fehlen.
- Neues **Taschensymbol** in der Taschenleiste unten rechts.

**Warnung bei anderen Addons (neu)**
- Schaltest du etwas ein, das sich mit einem installierten Addon beißt (z. B. Questie, Leatrix Plus, Bagnon, Details, Bartender, ElvUI), fragt stray vorher nach und sagt, was du dort ausschalten solltest. stray ändert nie Einstellungen anderer Addons.

# Aus 0.22.0-alpha

**Neues stray-Fenster**
- Ganz neu gestaltet: ruhiges Lila, neues stray-Logo (Siegel), links die Seiten in drei Gruppen (Alltag, Kampf & Gruppe, Oberfläche) mit eigenen Symbolen und einem Zähler, wie viele Optionen an sind.
- Oben je Seite ein großer Titel, der Knopf **Bearbeitungsmodus** und, wo es passt, der Hauptschalter **„Modul aktiv“**. Die Optionen stehen in Karten (Überschrift mittig) nur mit ihrem Namen – die Erklärung zeigt der Tooltip.
- **Größe ziehen** unten rechts: Das Fenster passt sich an (schmal = eine Spalte), Doppelklick auf den Griff stellt die Standardgröße her.
- **Stichwort-Suche:** findet Optionen auch über Begriffe wie „aggro“, „bags“, „xp“ oder „heal“ – deutsch und englisch.
- **Ungespeicherte Änderungen** werden unten gezählt. Beim Schließen fragt stray: **Neu laden** (übernehmen) oder **Verwerfen** (alles zurück auf den Stand beim Öffnen).
- Was du einstellst, siehst du direkt im Spiel an den echten Anzeigen.

**stray-Oberfläche – ein Schalter für alles**
- Neuer Hauptschalter (Oberfläche → stray-Oberfläche) für eigene Aktionsleisten, Taschenleiste unten, eckige Minimap, Menü per Mittelklick, Minimap-Knopfspalte, Uhr/FPS und Erfahrungsleiste. Jeder Teil lässt sich darunter einzeln abschalten. Aus = alles wieder Blizzard.
- Deine bisherigen Einstellungen bleiben erhalten.
- **Mittelklick auf die Minimap** öffnet das Menü, ohne auf der Karte zu pingen.

**Taschen- und Menüleiste unten rechts**
- Neu gestaltet: Blizzards Menüsymbole frei auf einem dunklen Streifen, der Charakter-Knopf zeigt dein **Porträt**.
- Rucksack und Taschen sind **ein Knopf** mit Füllbalken (grün, gelb, rot) und Tooltip mit allen Taschen. Der Schlüsselbund ist weg.
- Menüknöpfe: **Sammlung** (Haustiere, Reittiere) und **Abenteuerführer** neu, Freunde ist nur noch an der Minimap.
- Das **Menü an der Minimap** zeigt alle Fenster, die es auf Forever gibt (gesperrte bleiben weg).

**Erfahrung**
- **EP-Leiste besser lesbar:** größer, klarere Schrift, links Stufe und Prozent, Mitte Erholt, rechts Quest-EP. Breite, Höhe und Schriftgröße einstellbar.
- **EP-Tracker:** EP pro Stunde, Zeit bis zum Levelaufstieg, Zeit auf der aktuellen Stufe, Gesamtspielzeit und Verlauf je Stufe – an der EP-Leiste, im Tooltip oder als kleine Tabelle.

**Gruppe**
- **Begleiter am Gruppenrahmen:** Tiere von Jägern und Dämonen von Hexenmeistern erscheinen links neben ihrem Besitzer, mit Lebensbalken und Mouseover-Heilen. Breite und Höhe einstellbar. Die **Position am Besitzer** (links, rechts, oben, unten …) wählst du in den Optionen oder ziehst den Beispiel-Begleiter im Bearbeitungsmodus an die gewünschte Stelle – er bleibt immer an seinem Jäger oder Hexenmeister.

**Bearbeitungsmodus** (früher „Anzeigen verschieben“)
- Klick auf eine Anzeige öffnet ein kleines Fenster: Position X/Y, **Größe in Prozent**, wo möglich Breite und Höhe, mittig ausrichten, Zurücksetzen.
- **Pfeiltasten** verschieben die gewählte Anzeige um 1 Pixel, mit Shift um 10.
- **Shift + Rechtsklick** setzt eine Anzeige ganz auf Standard zurück (beim Taschenfenster: Höhe wieder automatisch).
- Knopf **Zurück** (und Strg + Z) nimmt Änderungen Schritt für Schritt zurück.
- Größere Leiste mit Hinweiszeile, damit man alle Kürzel sieht.
- Esc hebt erst die Auswahl auf, ein zweites Esc beendet den Modus.

**Taschenfenster**
- **Anheft-Leiste** oben in „Alle“: Gegenstand in einen Platz ziehen, dann bleibt er dort. Der Ruhestein sitzt schon auf Platz 1. Lösen mit Shift + Rechtsklick.

**Vorrat und Bedrohung**
- **Laufender Rand** um die Symbole der Vorrats-Erinnerung, damit Fehlendes sofort auffällt.
- **Bedrohungsliste** im stray-Look.

**Neuer Look überall**
- Alle Anzeigen (DMG-Meter, Gruppenrahmen, Taschen, Minimap, EP-Leiste, Swing-Timer, Twinks, Notizen …) im gleichen ruhigen Lila wie das stray-Fenster.

**Englisch**
- stray gibt es jetzt auch auf **Englisch**. Standard: deutscher Client deutsch, sonst englisch. Unter System → **Sprache** stellst du es fest auf Deutsch oder English (wirkt nach dem Neuladen).

**Kleinigkeiten**
- Der Profil-Export nimmt jetzt auch neue Einstellungen mit (zweites DMG-Meter, Taschenfenster, Bearbeitungsmodus, Größen je Anzeige, Minimap, Taschenleiste, Hauptschalter, EP-Leiste).

# Aus 0.21.0-alpha

**Taschenfenster**
- Questgegenstände stehen nur noch unter **„Quest“**, nicht zusätzlich unter Handwerk & Co. Nach der Abgabe wandern sie zurück.
- **Größe unten rechts ziehen:** Die Breite rastet auf ganze Spalten ein, die Höhe ist frei. Was nicht passt, blätterst du mit Mausrad oder Scrollbalken. Die Größe wird gespeichert, „Automatisch“ setzt die Höhe zurück.
- **Sortieren:** Besen-Knopf neben der Suche, gleiche Ordnung wie bei Blizzard.

**DMG-Meter**
- **Zweites Fenster** mit eigenem Modus (Standard Heilung) und eigener Größe.
- **Andocken:** An die Ober- oder Unterkante des ersten Fensters ziehen, dann rastet es ein und läuft mit. Standard: Heilung oben, Schaden unten.

**Bearbeiten-Modus**
- Neue kompakte Leiste oben mittig: Raster, **Einrasten** (an anderen Anzeigen und der Bildschirmmitte), Zurücksetzen mit Rückfrage, Fertig. Die Leiste selbst ist verschiebbar.
- **Esc beendet** den Bearbeiten-Modus.

**Aktionsleisten und Taschenleiste**
- **Leere Plätze immer zeigen**, mit einstellbarer Deckkraft.
- Der dunkle Rest-Rahmen von Blizzards Taschen- und Menüleiste neben den Leisten ist weg.
- Die **Taschenleiste unten rechts** kommt jetzt automatisch mit „Eigene Aktionsleisten“, im neuen flachen stray-Stil, mit freien Plätzen je Tasche und einstellbarer Größe. Menüknöpfe gibt es dort nur noch auf Wunsch („Menüknöpfe unten anzeigen“). Der eigene Schalter „Taschen- und Menüleiste“ entfällt.

**Minimap**
- **Eckige Minimap oben rechts** (Oberfläche → Kamera & Karte), mit Größenregler. Dazu Gebietsname darüber, Uhr/FPS und Koordinaten darunter, die Knopfspalte links daneben.
- **Menü per mittlerer Maustaste** auf die Minimap (Schalter in Kamera & Karte) und über den Kartenmenü-Knopf: Charakter, Zauberbuch, Talente, Berufe, Questlog, Freunde, Gilde, Gruppensuche, Kalender, Verfolgung, Weltkarte, Twinks. Die Fenster öffnen über Blizzards eigene Menüknöpfe, damit nichts „verseucht“ wird. Im Kampf öffnet sich das Menü nicht.
- Uhr/FPS überlappen nicht mehr mit den Koordinaten.

**Kleinigkeiten**
- „Quest-EP auf der EP-Leiste“ steht jetzt direkt unter „Erfahrungsleiste oben“.
- Ausgegraute Optionen sagen, wo der nötige Schalter steht.
- Die Zoomknöpfe der Minimap werden auf Forever richtig ausgeblendet.

# Aus 0.20.0-alpha

**Übersichtlicheres Einstellungsfenster**
- Statt 22 Einträgen gibt es links nur noch **9 Seiten**: Komfort, Taschen, Quests, Kampf, Aktionsleisten, Gruppe, Oberfläche, Sozial, System.
- Die bisherigen Bereiche stehen auf ihrer Seite als **Zwischenüberschriften** untereinander, zum Beispiel auf „Kampf“: Bedrohung, DMG-Meter, Kampfhilfen und Zaubern.
- Längere Seiten lassen sich mit dem **Mausrad scrollen**.
- Die Suche zeigt ihre Treffer nach Bereichen gruppiert.
- Das Vorschaubild erscheint direkt an der Option.

**Gruppenrahmen**
- Die Testgruppe (solange das stray-Fenster offen ist) zeigt auf dem ersten Platz deinen **eigenen Charakter** mit Name, Klasse und Ressource.
