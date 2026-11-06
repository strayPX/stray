# stray

Kleines Komfort-Addon für **World of Warcraft: Forever**. `/stray` öffnet ein Fenster mit allen Optionen. Fährst du mit der Maus über eine Option, erklärt ein Tooltip, was sie macht. Alle Optionen sind anfangs aus.

## Optionen

**Beute**
- **Automatisch plündern:** schaltet die Blizzard-Einstellung um, ohne Optionsmenü.
- **Schnell plündern:** nimmt die Beute sofort, ohne aufs Beutefenster zu warten. Nur aktiv, wenn „Automatisch plündern“ an ist.

**Händler**
- **Automatisch verkaufen:** verkauft graue Gegenstände beim Händler und zeigt Anzahl und Erlös im Chat.
- **Automatisch reparieren:** repariert die Ausrüstung mit eigenem Gold.

**Taschen**
- **„LÖSCHEN“ vorausfüllen:** Das Bestätigungswort steht beim Zerstören schon im Feld.
- **Ohne Nachfrage zerstören:** Gegenstände werden ohne Abfrage zerstört, auch epische.

**Chat**
- **Links kopierbar:** Webadressen im Chat werden anklickbar und öffnen ein Feld zum Kopieren.

**Quests**
- **Automatisch annehmen:** ohne graue, geteilte und Begleitquests.
- **Automatisch abgeben:** stoppt bei mehreren Belohnungen zur Auswahl und wenn die Abgabe Gold kostet.

**Filmsequenzen**
- **Schnell überspringen:** Esc beendet sofort, ohne Rückfrage.
- **Immer überspringen:** beendet Sequenzen und Videos automatisch.

**Bedrohung**
- **Bedrohungsliste:** Balken pro Gruppenmitglied für dein Ziel, wer hat Aggro, wer ist kurz davor. Bei offenem stray-Fenster mit Beispielwerten zum Verschieben. Alle Bedrohungsoptionen zeigen im Tooltip ein Beispielbild.
- **Rahmen an Namensplaketten:** rot = du hast Aggro, gelb = Aggro wechselt gleich, grün = keine Aggro.
- **Prozent an Namensplaketten:** deine Bedrohung neben dem Lebensbalken, 0 % = keine, 100 % = Aggro.
- **Tank-Warnung:** Verlierst du die Aggro, steht mittig, wen der Gegner jetzt angreift.
- **Aggro-Warnung ab 90 %:** für Schaden und Heiler, bevor sie Aggro ziehen.

Rahmen, Prozent und Tank-Warnung brauchen eingeschaltete gegnerische Namensplaketten (Taste V).

**Kamera & Karte**
- **Maximale Kamera-Entfernung:** so weit herauszoomen, wie das Spiel erlaubt.
- **Minimap mit Mausrad zoomen:** Mausrad zoomt die Minimap, die Plus-/Minus-Knöpfe verschwinden.

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

- 0.7.0-alpha – Beispielbilder im Tooltip der Bedrohungsoptionen
- 0.6.0-alpha – Prozentanzeige an Namensplaketten
- 0.5.1-alpha – Korrekturen nach Code-Review: Kamera-Maximum, Minimap-Zoom, Begleittiere bei der Bedrohung, Chat-Links in Klammern, Kopierfeld
- 0.5.0-alpha – Bedrohung: Liste, Rahmen an Namensplaketten, Tank- und Aggro-Warnung
- 0.4.0-alpha – Chat-Links, Kamera, Minimap-Zoom, Fehlermeldungen, Haltbarkeit, Duelle, Wiederbelebung, Beschwörung; Fenster dreispaltig; Flugzeit entfernt
- 0.3.0-alpha – Händler, Taschen, Quests, Filmsequenzen und Flugzeit; Fenster zweispaltig, Symbol in der Titelleiste, Höhe passt sich an
- 0.2.0 – Fenster im klassischen Stil: Symbol, Version, Abschnitt „Beute“, Tooltips, Klick-Sounds
- 0.1.0 – erste Testversion
