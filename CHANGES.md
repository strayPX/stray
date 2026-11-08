# stray 0.19.0-alpha

Diese Version enthält auch alles aus 0.18.0-alpha, das nie einzeln veröffentlicht wurde (siehe unten). **Alles Neue ist anfangs aus** und lässt sich im stray-Fenster einzeln einschalten.

**Neu – Komfort**
- **Verkaufspreis im Tooltip** (Händler): pro Stück und für den ganzen Stapel.
- **Bekanntes beim Händler grün** (Händler): Rezepte, Begleiter und Reittiere, die du schon kennst.
- **Post** (NPCs): Liste deiner Twinks beim „Post senden“ – ein Klick setzt den Namen.
- **Lehrer: Alles lernen** (NPCs): ein Knopf lernt alles, was verfügbar und bezahlbar ist.
- **Hilfe bei vollen Taschen** (Taschen): markiert den billigsten Gegenstand als Löschkandidaten und zeigt beim Plündern, welche Beute mehr wert ist. Gelöscht wird nichts automatisch.
- **Vorrats-Erinnerung** (Vorrat): Symbole nur, wenn Reagenzien, Munition, Essen/Wasser oder eigene Buffs fehlen.
- **Quests:** wertvollste Belohnung mit Goldmünze markiert, EP fertiger Quests auf der EP-Leiste, Quest-Gegner mit Symbol und „3/8“ an der Namensplakette.
- **Koordinaten im Chat anklickbar** (Chat): ein Klick setzt einen Kartenpin.

**Neu – Kampf**
- **Swing-Timer** (Kampfhilfen): Leiste bis zum nächsten automatischen Schlag, je Waffe, außer Reichweite rot.
- **Warnung vor gefährlichen Gegnern** (Kampfhilfen): Totenkopf an Elite-Gegnern und Gegnern ein paar Stufen über dir, dazu ein kurzer Hinweis.
- **Veralteter Zauberrang** (Zaubern): Pfeil auf stray-Leistenknöpfen, wenn du einen höheren Rang kennst.

**Neu – Sozial und Charaktere**
- **Einladungen** (Sozial): von Freunden und Gilde annehmen, von Fremden ablehnen.
- **Notizen zu Mitspielern** (Sozial): per Rechtsklick-Menü, sichtbar im Tooltip und beim Gruppenbeitritt.
- **Twink-Übersicht** (Charaktere): Stufe, Gold, erholte EP und Spielzeit aller Charaktere – auch per `/stray alts` und im Kartenmenü.
- **Interface-Einstellungen für alle Charaktere** (Charaktere).
- **Flugzeit-Balken** (Kamera & Karte): misst jede Strecke beim ersten Flug und zeigt danach die Restzeit.
- **Würfelfenster verschiebbar** (Interface).

**Verbessert und behoben**
- Gruppenrahmen: Die Manaleiste der Mitspieler funktioniert jetzt auch, wenn der Wert versiegelt ist.
- „Automatisch verkaufen“ nutzt die Forever-Funktion für Gegenstandsinfos.
- Questmarkierung im Taschenfenster beachtet jetzt die Option.
- Das stray-Fenster ist etwas höher und hat vier neue Bereiche: NPCs, Vorrat, Kampfhilfen, Charaktere.

# Aus 0.18.0-alpha (erstmals veröffentlicht)

- **Eigene Aktionsleisten** (Kampf → Aktionsleisten): bis zu 5 Leisten mit je 12 Knöpfen statt Blizzards Leisten – schlicht, quadratisch, ohne Greifen und Hintergrund. Standard: 4 Leisten mittig übereinander. Jede Leiste einzeln an/aus, mit eigener Knopfgröße und Knöpfen pro Reihe („Leiste bearbeiten 1–5“). Deine Belegung und deine Tasten bleiben.
- **Abklingzeiten über den Leisten** (Kampf → Abklingzeiten): Blizzards Cooldown-Manager im stray-Stil.
- **Minimap-Knopfspalte**, **Uhrzeit und FPS**, **Erfahrungsleiste oben**, **Taschen- und Menüleiste** unten rechts (Oberfläche → Leisten & Minimap).
- **Eigenes Taschenfenster** (Komfort → Taschen) mit Suche, Kategorien und Gold; Alt+Rechtsklick heftet an.

**Hinweis:** Nach dem Update das Spiel einmal komplett neu starten (viele neue Dateien). Einige Teile kommen nach dem Ausschalten erst nach `/reload` wieder in Blizzards Form zurück. Alles Neue ist noch wenig getestet – bitte Fehler per Screenshot oder BugSack melden.
