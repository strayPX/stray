# stray

Kleines Komfort-Addon für **World of Warcraft: Forever**. `/stray` oder der Minimap-Knopf öffnet das Einstellungsfenster: oben die Stichwort-Suche, links die Seiten (Zentrale, Oberfläche, Spielhilfen, System) und die Profil-Auswahl, rechts die Optionen mit Reitern, Zahlenfeldern und Position X/Y. Fährst du mit der Maus über eine Option, erklärt ein Tooltip mehr. Beim Schließen übernimmst du Änderungen mit „Neu laden“ oder nimmst sie mit „Verwerfen“ zurück. Auf deutschen Clients ist stray deutsch, sonst englisch – umstellbar unter System → Sprache. Alle Optionen sind anfangs aus (außer dem Minimap-Knopf).

## Optionen

**Beute**
- **Automatisch plündern:** schaltet die Blizzard-Einstellung um, ohne Optionsmenü.
- **Schnell plündern:** nimmt die Beute sofort, ohne aufs Beutefenster zu warten. Nur aktiv, wenn „Automatisch plündern“ an ist.

**Händler**
- **Automatisch verkaufen:** verkauft graue Gegenstände beim Händler und zeigt Anzahl und Erlös im Chat.
- **Automatisch reparieren:** repariert die Ausrüstung mit eigenem Gold.
- **Warnung beim Verkauf:** Verkaufst du doch einen Questgegenstand, fragt stray „Zurückkaufen?“ – ein Klick holt ihn zurück.
- **Verkaufspreis im Tooltip:** pro Stück und für den Stapel.
- **Bekanntes grün färben:** Rezepte, Begleiter und Reittiere, die du schon kennst, beim Händler grün.

**NPCs**
- **Twink-Liste beim Post senden:** ein Klick setzt den Namen ein.
- **Lehrer: Alles lernen:** ein Knopf lernt alles Verfügbare, das du bezahlen kannst.

**Taschen**
- **„LÖSCHEN“ vorausfüllen:** Das Bestätigungswort steht beim Zerstören schon im Feld.
- **Ohne Nachfrage zerstören:** Gegenstände werden ohne Abfrage zerstört, auch epische.
- **Questgegenstände markieren:** Gegenstände, die eine Quest im Questlog braucht (z. B. „Leinenstoff: 3/10“), bekommen einen goldenen Rahmen mit „!“.
- **Freie Taschenplätze:** Zahl auf dem Rucksack-Knopf, rot bei vollen Taschen.
- **Hilfe bei vollen Taschen:** markiert den billigsten Gegenstand als Löschkandidaten, Goldmünze an wertvollerer Beute. Gelöscht wird nichts automatisch.

**Vorrat**
- **Vorrats-Erinnerung:** Symbole nur, wenn Reagenzien, Munition, Essen/Wasser oder eigene Buffs fehlen; Warnschwelle einstellbar; die Symbole haben einen laufenden Rand.

**Chat**
- **Links kopierbar:** Webadressen im Chat werden anklickbar und öffnen ein Feld zum Kopieren.
- **Koordinaten anklickbar:** „45.2, 67.8“ im Chat wird ein Link, ein Klick setzt einen Kartenpin.

**Quests**
- **Automatisch annehmen:** ohne graue, geteilte und Begleitquests.
- **Automatisch abgeben:** stoppt bei mehreren Belohnungen zur Auswahl und wenn die Abgabe Gold kostet.
- **Gesprächsmenü überspringen:** Hat ein NPC nur eine Gesprächsoption und keine Quests, wählt stray sie automatisch.
- **Wertvollste Belohnung markieren:** Goldmünze an der Wahl mit dem höchsten Verkaufswert.
- **Quest-EP auf der EP-Leiste:** EP aller fertigen Quests als goldener Bereich.
- **Quest-Gegner markieren:** Symbol und „3/8“ an der Namensplakette (nicht in Instanzen).

**Filmsequenzen**
- **Schnell überspringen:** Esc beendet sofort, ohne Rückfrage.
- **Immer überspringen:** beendet Sequenzen und Videos automatisch.

**Bedrohung**
- **Bedrohungsliste:** Balken pro Gruppenmitglied für dein Ziel, wer hat Aggro, wer ist kurz davor. Sortiert: wer Aggro hat zuerst. Bei offenem stray-Fenster mit Beispielwerten zum Verschieben. Alle Bedrohungsoptionen haben ein Beispielbild („Vorschau“).
- **Rahmen an Namensplaketten:** rot = du hast Aggro, gelb = Aggro wechselt gleich, grün = keine Aggro.
- **Prozent an Namensplaketten:** deine Bedrohung neben dem Lebensbalken, 0 % = keine, 100 % = Aggro.
- **Tank-Warnung:** Verlierst du bei einem Gegner die Aggro, steht mittig, wen er jetzt angreift.
- **Aggro-Warnung ab 90 %:** für Schaden und Heiler, bevor sie Aggro ziehen.

Hinweis: WoW Forever versiegelt manche Bedrohungswerte. stray nutzt nur die lesbaren Abfragen; ist ein Wert doch versiegelt, wird er nur angezeigt oder ausgelassen (die Liste ist dann unsortiert), und ein Hinweis erscheint einmal im Chat.

Rahmen, Prozent und Tank-Warnung brauchen eingeschaltete gegnerische Namensplaketten (Taste V).

**DMG-Meter**
- **DMG-Meter anzeigen:** Schaden oder Heilung, gesamt und pro Sekunde – für alles, den aktuellen Kampf oder einzelne Kämpfe; mit Zurücksetzen.
- **Nach Instanz zurücksetzen:** leert den Messer beim Verlassen eines Dungeons/Schlachtzugs.

**Kampfhilfen**
- **Swing-Timer:** Leiste bis zum nächsten automatischen Schlag, je Waffe; außer Reichweite rot.
- **Gefährliche Gegner warnen:** Totenkopf an Elite-Gegnern und Gegnern einige Stufen über dir, dazu ein kurzer Hinweis.

**Zaubern**
- **Mouseover-Zauber:** schaltet Blizzards Einstellung um – Zauber gehen auf das Ziel unter der Maus.
- **Veralteten Zauberrang zeigen:** Pfeil auf stray-Leistenknöpfen, wenn du einen höheren Rang kennst.

**Gruppenrahmen**
- **Gruppenrahmen anzeigen:** 5er-Gruppe als senkrechte Spalte mit Leben, Mana, entfernbaren Schwächungen und Reichweite; Breite, Höhe, Abstand per Schieberegler.
- **Begleiter anzeigen:** Tiere und Dämonen links neben ihrem Besitzer, mit Lebensbalken und Mouseover-Heilen.
- **Blizzards Gruppenrahmen ausblenden.**
- **Heilvorhersage, Schilde, „Geschwächte Seele“:** immer Teil der Gruppenrahmen – laufende Heilung hellgrün, Schilde gestreift, Symbol mit Restzeit.

**System**
- **Bearbeitungsmodus:** alle eingeschalteten Anzeigen auf einmal verschieben (Raster, Einrasten, Shift + Rechtsklick setzt zurück, Zurück-Knopf / Strg + Z) – Knopf oben im stray-Fenster oder `/stray edit`. Klick auf eine Anzeige öffnet ein Fenster für Position, Größe in Prozent und, wo möglich, Breite/Höhe; Pfeiltasten verschieben pixelgenau.
- **Profile:** Einstellungen als Text exportieren und importieren.

**stray-Oberfläche** (ein Hauptschalter, jeder Teil einzeln abschaltbar)
- **Eigene Aktionsleisten**, **Taschenleiste unten rechts** (Porträt-Knopf, eine Tasche mit Füllbalken, Menüsymbole optional), **eckige Minimap**, **Menü per Mittelklick** auf die Minimap, **Minimap-Knopfspalte**, **Uhrzeit und FPS**, **Erfahrungsleiste oben**.

**Erfahrung**
- **EP-Leiste:** Stufe, Erholt und Quest-EP gut lesbar; Breite, Höhe, Schrift einstellbar.
- **EP-Tracker:** EP pro Stunde, Zeit bis Levelaufstieg, Zeit je Stufe, Gesamtspielzeit, Verlauf – optional als Tabelle.

**Aktionsleisten / Abklingzeiten**
- **Eigene Aktionsleisten** (Teil der stray-Oberfläche): bis zu 5 × 12 Knöpfe, schlicht, Tasten bleiben; jede Leiste einzeln an/aus, mit eigener Knopfgröße und Knöpfen pro Reihe.
- **Abklingzeiten über den Leisten:** Blizzards Cooldown-Manager im stray-Stil.

**Kamera & Karte**
- **Maximale Kamera-Entfernung:** so weit herauszoomen, wie das Spiel erlaubt.
- **Minimap mit Mausrad zoomen:** Mausrad zoomt die Minimap, die Plus-/Minus-Knöpfe verschwinden.
- **Minimap-Knopf anzeigen:** runder stray-Knopf (blaues S) am Minimap-Rand; Linksklick öffnet das Fenster, Ziehen verschiebt ihn. Anfangs an.
- **Flugzeit-Balken:** misst jede Flugstrecke beim ersten Flug und zeigt danach die Restzeit.

**Interface**
- **Fehlermeldungen ausblenden:** rote Meldungen wie „Nicht genug Mana“ verschwinden; „Taschen voll“ und „Questlog voll“ bleiben.
- **Haltbarkeit anzeigen:** kleine Anzeige mit dem am stärksten beschädigten Ausrüstungsteil, Tooltip mit allen Teilen.
- **Würfelfenster verschiebbar:** das Bedarf/Gier-Fenster folgt einem verschiebbaren Platzhalter.

**Sozial**
- **Duelle ablehnen:** Anfragen werden sofort abgelehnt.
- **Wiederbelebung annehmen:** automatisch, nicht solange der Wiederbelebende im Kampf ist.
- **Beschwörung annehmen:** automatisch, nicht wenn du im Kampf bist.
- **Einladungen:** von Freunden und Gilde annehmen, von Fremden ablehnen (zwei Schalter).
- **Notizen zu Mitspielern:** per Rechtsklick-Menü; erscheinen im Tooltip und wenn der Spieler deiner Gruppe beitritt.

**Charaktere**
- **Twink-Übersicht:** Stufe, Gold, erholte EP und Spielzeit aller Charaktere – auch per `/stray alts`.
- **Interface-Einstellungen für alle Charaktere:** übernimmt charakterbezogene Interface-Einstellungen beim Wechsel.

**Questtracker**
- **Questliste rechts am Rand:** nach Gebiet gruppiert und einklappbar, Schwierigkeitsfarben, Questgegenstände als Knopf, Größe ziehbar; blendet Blizzards Questverfolgung aus. Läuft Questie mit eigener Liste, weist stray darauf hin.

**Tastenbelegung**
- **Tasten belegen:** über einen Knopf der stray-Leisten fahren und Taste drücken (mit Shift/Strg/Alt, Maustasten, Mausrad) – `/stray keys`.

**Andere Addons**
- Bevor du etwas einschaltest, das sich mit einem installierten Addon beißt, warnt stray und sagt, was dort auszuschalten ist.

Bei Händler und Quests verhindert gedrückte **Shift**-Taste die Automatik. Anzeigen am Bildschirm verschiebst du mit **Shift + linker Maustaste**.

Hinweis: Hat ein anderes Addon (z. B. Leatrix Plus oder Questie) die gleiche Automatik aktiv, nutze nur eins von beiden.

## Installation

**Mit WowUp (CurseForge-Version):** World of Warcraft: Forever auswählen, nach **stray** suchen, installieren. Falls die Suche es noch nicht findet: „Mit URL installieren“ → `https://www.curseforge.com/wow/addons/stray`.

**Mit WowUp (GitHub):** „Von URL installieren“ → `https://github.com/strayPX/stray`.

Updates zeigt WowUp danach automatisch an.

**Von Hand:** Die ZIP aus den [Releases](https://github.com/strayPX/stray/releases) entpacken, den Ordner `stray` nach `World of Warcraft\_forever_\Interface\AddOns\` kopieren und das Spiel neu starten.

## Lizenz

All Rights Reserved – nur zur persönlichen Nutzung, siehe `LICENSE`.

**Symbole:** Die Seitensymbole im stray-Fenster (`media/icons/`) stammen aus [Tabler Icons](https://tabler.io/icons) (Version 3.19.0) von Paweł Kuna, MIT-Lizenz, Copyright (c) 2020–2024 Paweł Kuna. Sie wurden für stray in weiße TGA-Texturen umgewandelt. MIT-Lizenztext: Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Version

- 1.0.0 – Erste stabile Version: enthält 0.20 bis 0.23 (neues stray-Fenster, DMG-Meter-Fenster, eigener Questtracker mit Berufsreagenzien, Tasten belegen, Anheft-Leiste, Konflikt-Warnung, Verfolgungs-Knopf an der Minimap, englische Übersetzung)
- 0.23.0-alpha – Neues stray-Fenster (Seiten, Reiter, Zahlenfelder, Position), DMG-Meter bis 5 Fenster per „+“, eigener Questtracker mit Questgegenstand-Knöpfen, Tasten belegen per Mouseover, Anheft-Leiste (5 Plätze), Taschenplätze und Tasche tauschen, neues Taschensymbol, Warnung bei Konflikten mit anderen Addons
- 0.22.0-alpha – Neues stray-Fenster (Zentrale, Stichwort-Suche, Neu laden/Verwerfen), Hauptschalter stray-Oberfläche, Mittelklick ohne Ping, neue Taschenleiste, lesbare EP-Leiste + EP-Tracker, Begleiter am Gruppenrahmen, Bearbeitungsmodus mit Fenster je Anzeige und Pfeiltasten, laufender Rand beim Vorrat, englische Übersetzung; Nachtrag: Sprache umschaltbar, Logo Siegel, Fenster in der Größe ziehbar, Sammlung/Abenteuerführer, Begleiter-Position, Anheft-Leiste im Taschenfenster, Rückgängig im Bearbeitungsmodus, lila Look überall
- 0.21.0-alpha – Taschenfenster (Größe ziehen, blättern, sortieren, Quest-Kategorie), zweites DMG-Meter-Fenster zum Andocken, neue Bearbeiten-Leiste (Einrasten, Esc), leere Aktionsplätze dauerhaft, neue Taschenleiste, eckige Minimap, Menü per mittlerer Maustaste
- 0.20.0-alpha – Einstellungsfenster mit 9 Seiten statt 22 (Zwischenüberschriften, scrollbar); Testgruppe zeigt den eigenen Charakter
- 0.19.0-alpha – Händlerpreis, Post-Twinkliste, Lehrer „Alles lernen“, volle Taschen, Vorrat, Quest-Hilfen, Swing-Timer, Gefahrenwarnung, Zauberrang, Einladungen, Notizen, Twink-Übersicht, Flugzeit, Würfelfenster; Manaleiste im Gruppenrahmen repariert
- 0.18.0-alpha – Eigene Aktionsleisten, Abklingzeiten über den Leisten, Minimap-Knopfspalte, Uhr/FPS, EP-Leiste oben, Taschen-/Menüleiste, eigenes Taschenfenster
- 0.17.0-alpha – DMG-Meter: neues flaches Design, Größe unten rechts ziehbar; Umbenennung Schadensmesser → DMG-Meter
- 0.16.0-alpha – Gruppenrahmen: Heilvorhersage, Schilde, „Geschwächte Seele“
- 0.15.0-alpha – Knopf „Anzeigen verschieben“ oben im stray-Fenster
- 0.14.1-alpha – Gruppenrahmen: Helligkeit der Balken (Standard 60 %)
- 0.14.0-alpha – Bearbeiten-Modus, Profile Import/Export, flache Gruppenrahmen, Testgruppe; enthält 0.13.0 (nie einzeln veröffentlicht)
- 0.13.0-alpha – Schadensmesser mit Heilung, Heiler-Gruppenrahmen, Schieberegler im Fenster
- 0.12.0-alpha – Mouseover-Zauber, Gesprächsmenü überspringen, freie Taschenplätze
- 0.11.0-alpha – Questgegenstände markieren und Warnung beim Verkauf mit Rückkauf
- 0.10.1-alpha – runde Punkte und Schalter; „Neu laden“ hervorgehoben, nach Änderungen Empfehlung zum Neuladen beim Schließen
- 0.10.0-alpha – Neues Einstellungsfenster (Seitenleiste, Suche, Schalter, Vorschau); Bedrohung neu: lesbare Abfragen, sortierte Liste, Tank- und Aggro-Warnung zurück, ereignisbasiert
- 0.9.0-alpha – Minimap-Knopf mit eigenem Symbol
- 0.8.1-alpha – Tank- und Aggro-Warnung entfernt (in WoW Forever nicht möglich)
- 0.8.0-alpha – Bedrohung trotz versiegelter Werte: Liste, Rahmen und Prozent zeigen die Werte über Blizzards Farbkurven an (Liste ohne Sortierung, experimentell)
- 0.7.1-alpha – Notfix: Forever versiegelt Bedrohungswerte im Kampf (Fehlerflut behoben); Tank- und Aggro-Warnung deaktiviert; weitere Absicherungen gegen versiegelte Werte
- 0.7.0-alpha – Beispielbilder im Tooltip der Bedrohungsoptionen
- 0.6.0-alpha – Prozentanzeige an Namensplaketten
- 0.5.1-alpha – Korrekturen nach Code-Review: Kamera-Maximum, Minimap-Zoom, Begleittiere bei der Bedrohung, Chat-Links in Klammern, Kopierfeld
- 0.5.0-alpha – Bedrohung: Liste, Rahmen an Namensplaketten, Tank- und Aggro-Warnung
- 0.4.0-alpha – Chat-Links, Kamera, Minimap-Zoom, Fehlermeldungen, Haltbarkeit, Duelle, Wiederbelebung, Beschwörung; Fenster dreispaltig; Flugzeit entfernt
- 0.3.0-alpha – Händler, Taschen, Quests, Filmsequenzen und Flugzeit; Fenster zweispaltig, Symbol in der Titelleiste, Höhe passt sich an
- 0.2.0 – Fenster im klassischen Stil: Symbol, Version, Abschnitt „Beute“, Tooltips, Klick-Sounds
- 0.1.0 – erste Testversion
