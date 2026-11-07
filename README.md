# stray

Kleines Komfort-Addon für **World of Warcraft: Forever**. `/stray` oder der Minimap-Knopf öffnet das Einstellungsfenster: links die Bereiche und eine Suche, rechts die Optionen mit Schaltern und Kurzbeschreibung. Fährst du mit der Maus über eine Option, erklärt ein Tooltip mehr. Alle Optionen sind anfangs aus (außer dem Minimap-Knopf).

## Optionen

**Beute**
- **Automatisch plündern:** schaltet die Blizzard-Einstellung um, ohne Optionsmenü.
- **Schnell plündern:** nimmt die Beute sofort, ohne aufs Beutefenster zu warten. Nur aktiv, wenn „Automatisch plündern“ an ist.

**Händler**
- **Automatisch verkaufen:** verkauft graue Gegenstände beim Händler und zeigt Anzahl und Erlös im Chat.
- **Automatisch reparieren:** repariert die Ausrüstung mit eigenem Gold.
- **Warnung beim Verkauf:** Verkaufst du doch einen Questgegenstand, fragt stray „Zurückkaufen?“ – ein Klick holt ihn zurück.

**Taschen**
- **„LÖSCHEN“ vorausfüllen:** Das Bestätigungswort steht beim Zerstören schon im Feld.
- **Ohne Nachfrage zerstören:** Gegenstände werden ohne Abfrage zerstört, auch epische.
- **Questgegenstände markieren:** Gegenstände, die eine Quest im Questlog braucht (z. B. „Leinenstoff: 3/10“), bekommen einen goldenen Rahmen mit „!“.
- **Freie Taschenplätze:** Zahl auf dem Rucksack-Knopf, rot bei vollen Taschen.

**Chat**
- **Links kopierbar:** Webadressen im Chat werden anklickbar und öffnen ein Feld zum Kopieren.

**Quests**
- **Automatisch annehmen:** ohne graue, geteilte und Begleitquests.
- **Automatisch abgeben:** stoppt bei mehreren Belohnungen zur Auswahl und wenn die Abgabe Gold kostet.
- **Gesprächsmenü überspringen:** Hat ein NPC nur eine Gesprächsoption und keine Quests, wählt stray sie automatisch.

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

**Schadensmesser**
- **Schadensmesser anzeigen:** Schaden oder Heilung, gesamt und pro Sekunde – für alles, den aktuellen Kampf oder einzelne Kämpfe; mit Zurücksetzen.
- **Nach Instanz zurücksetzen:** leert den Messer beim Verlassen eines Dungeons/Schlachtzugs.

**Zaubern**
- **Mouseover-Zauber:** schaltet Blizzards Einstellung um – Zauber gehen auf das Ziel unter der Maus.

**Gruppenrahmen**
- **Gruppenrahmen anzeigen:** 5er-Gruppe als senkrechte Spalte mit Leben, Mana, entfernbaren Schwächungen und Reichweite; Breite, Höhe, Abstand per Schieberegler.
- **Blizzards Gruppenrahmen ausblenden.**
- **Heilvorhersage, Schilde, „Geschwächte Seele“:** immer Teil der Gruppenrahmen – laufende Heilung hellgrün, Schilde gestreift, Symbol mit Restzeit.

**System**
- **Bearbeiten:** alle eingeschalteten Anzeigen auf einmal verschieben (ohne Shift, mit Raster, Rechtsklick setzt zurück) – auch per `/stray edit`.
- **Knopf „Anzeigen verschieben“** oben im stray-Fenster startet den Bearbeiten-Modus direkt.
- **Profile:** Einstellungen als Text exportieren und importieren.

**Kamera & Karte**
- **Maximale Kamera-Entfernung:** so weit herauszoomen, wie das Spiel erlaubt.
- **Minimap mit Mausrad zoomen:** Mausrad zoomt die Minimap, die Plus-/Minus-Knöpfe verschwinden.
- **Minimap-Knopf anzeigen:** runder stray-Knopf (blaues S) am Minimap-Rand; Linksklick öffnet das Fenster, Ziehen verschiebt ihn. Anfangs an.

**Interface**
- **Fehlermeldungen ausblenden:** rote Meldungen wie „Nicht genug Mana“ verschwinden; „Taschen voll“ und „Questlog voll“ bleiben.
- **Haltbarkeit anzeigen:** kleine Anzeige mit dem am stärksten beschädigten Ausrüstungsteil, Tooltip mit allen Teilen.

**Sozial**
- **Duelle ablehnen:** Anfragen werden sofort abgelehnt.
- **Wiederbelebung annehmen:** automatisch, nicht solange der Wiederbelebende im Kampf ist.
- **Beschwörung annehmen:** automatisch, nicht wenn du im Kampf bist.

Bei Händler und Quests verhindert gedrückte **Shift**-Taste die Automatik. Anzeigen am Bildschirm verschiebst du mit **Shift + linker Maustaste**.

Hinweis: Hat ein anderes Addon (z. B. Leatrix Plus oder Questie) die gleiche Automatik aktiv, nutze nur eins von beiden.

## Installation

**Mit WowUp:** „Addons holen“ → „Von URL installieren“ → `https://github.com/strayfling/stray` einfügen. Fertig – Updates zeigt WowUp danach automatisch an.

**Von Hand:** Die ZIP aus den [Releases](https://github.com/strayfling/stray/releases) entpacken, den Ordner `stray` nach `World of Warcraft\_forever_\Interface\AddOns\` kopieren und das Spiel neu starten.

## Lizenz

All Rights Reserved – nur zur persönlichen Nutzung, siehe `LICENSE`.

## Version

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
