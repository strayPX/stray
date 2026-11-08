-- stray – englische Texte (Teil 5), Schlüssel = deutscher Originaltext
local _, ns = ...
local E = ns.LocaleEN

-- quests.lua
E["Automatisch annehmen"] = "Auto-accept"
E["Nimmt neue Quests von NPCs und Gegenständen ohne Klick an. Graue Quests, von Mitspielern geteilte Quests und Begleitquests nimmst du selbst an.\n\nHalte Shift gedrückt, um das zu verhindern."] = "Accepts new quests from NPCs and items without a click. Gray quests, quests shared by other players and escort quests you accept yourself.\n\nHold Shift to prevent this."
E["Automatisch abgeben"] = "Auto turn-in"
E["Gibt fertige Quests ohne Klick ab. Stehen mehrere Belohnungen zur Auswahl oder kostet die Abgabe Gold, entscheidest du selbst.\n\nHalte Shift gedrückt, um das zu verhindern."] = "Turns in completed quests without a click. If there are several rewards to choose from or turning in costs gold, you decide yourself.\n\nHold Shift to prevent this."
E["Wertvollste Belohnung markieren"] = "Mark most valuable reward"
E["Stehen bei der Abgabe mehrere Belohnungen zur Wahl, bekommt die mit dem höchsten Verkaufswert eine kleine Goldmünze. Gezählt wird Verkaufspreis mal Anzahl.\n\nBei Gleichstand oder wenn ein Preis fehlt, wird nichts markiert. Gewählt wird nie automatisch."] = "When you can choose between several rewards on turn-in, the one with the highest vendor value gets a small gold coin. Counted is vendor price times quantity.\n\nOn a tie or if a price is missing, nothing is marked. Nothing is ever chosen automatically."
E["stray: höchster Verkaufswert"] = "stray: highest vendor value"

-- gossip.lua
E["Gesprächsmenü überspringen"] = "Skip gossip menu"
E["Hat ein NPC nur eine Gesprächsoption und keine Quests – etwa Flugmeister, Gastwirt, Bankier oder Händler –, wählt stray sie automatisch. Halte Shift gedrückt, um das Menü zu sehen.\n\nOptionen mit Bestätigung (z. B. Gold bezahlen) fragt WoW weiterhin ab."] = "If an NPC has only one gossip option and no quests – such as flight masters, innkeepers, bankers or vendors – stray selects it automatically. Hold Shift to see the menu.\n\nOptions that need confirmation (e.g. paying gold) are still asked by WoW."

-- cinematics.lua
E["Schnell überspringen"] = "Quick skip"
E["Esc beendet Filmsequenzen und Videos sofort, ohne „Wirklich überspringen?“-Abfrage."] = "Esc ends cinematics and movies immediately, without the \"Are you sure?\" prompt."
E["Immer überspringen"] = "Always skip"
E["Filmsequenzen und Videos werden beim Start automatisch beendet. Sequenzen, die Blizzard als nicht abbrechbar markiert, laufen trotzdem."] = "Cinematics and movies are ended automatically when they start. Sequences Blizzard marks as not skippable still play."
E["Filmsequenz übersprungen."] = "Cinematic skipped."
E["Video übersprungen."] = "Movie skipped."

-- chat.lua
E["Links kopierbar"] = "Copyable links"
E["Webadressen im Chat werden blau und anklickbar. Ein Klick öffnet ein Feld, aus dem du den Link mit Strg+C kopierst."] = "Web addresses in chat become blue and clickable. A click opens a box where you copy the link with Ctrl+C."
E["Koordinaten anklickbar"] = "Clickable coordinates"
E["Koordinaten im Chat wie „45.2, 67.8“ oder „45,2 67,8“ werden zu Links. Ganze Zahlen wie „45 67“ nur mit einem Wort davor, z. B. „bei 45 67“ oder „/way 45 67“.\nEin Klick setzt einen Kartenpin auf deiner aktuellen Karte.\nIn Instanzen ist der Chat versiegelt, dort bleibt alles unverändert."] = "Coordinates in chat like \"45.2, 67.8\" or \"45,2 67,8\" become links. Whole numbers like \"45 67\" only with a word before them, e.g. \"at 45 67\" or \"/way 45 67\".\nA click places a map pin on your current map.\nIn instances chat is protected, so everything stays unchanged there."
E["Kartenpins gibt es in diesem Client nicht."] = "Map pins are not available in this client."
E["Keine Karte für den Pin gefunden."] = "No map found for the pin."
E["Auf dieser Karte kann kein Pin gesetzt werden."] = "A pin cannot be placed on this map."
E["Pin konnte nicht gesetzt werden."] = "Pin could not be placed."
E["Pin gesetzt (%s, %s)"] = "Pin placed (%s, %s)"
E["Link kopieren mit Strg+C:"] = "Copy the link with Ctrl+C:"
E["Schließen"] = "Close"

-- social.lua
E["Duelle ablehnen"] = "Decline duels"
E["Duellanfragen werden sofort abgelehnt. Im Chat steht, wer dich herausgefordert hat."] = "Duel requests are declined immediately. Chat shows who challenged you."
E["Wiederbelebung annehmen"] = "Accept resurrection"
E["Nimmt Wiederbelebungen von Mitspielern automatisch an – aber nicht, solange der Wiederbelebende noch im Kampf ist."] = "Automatically accepts resurrections from other players – but not while the resurrecting player is still in combat."
E["Beschwörung annehmen"] = "Accept summons"
E["Nimmt Beschwörungen (z. B. vom Hexenmeister) automatisch an – nicht, wenn du gerade im Kampf bist."] = "Automatically accepts summons (e.g. from a Warlock) – not while you are in combat."
E["Einladungen von Freunden und Gilde annehmen"] = "Accept invites from friends and guild"
E["Gruppeneinladungen von Freunden, Battle.net-Freunden und Gildenmitgliedern werden automatisch angenommen.\nNicht, solange du in einer Warteschlange bist, und nicht bei Einladungen über die Gruppensuche."] = "Group invites from friends, Battle.net friends and guild members are accepted automatically.\nNot while you are in a queue, and not for invites through the Group Finder."
E["Einladungen von Fremden ablehnen"] = "Decline invites from strangers"
E["Gruppeneinladungen von Spielern, die weder Freund noch in deiner Gilde sind, werden sofort abgelehnt. Im Chat steht, wer dich eingeladen hat.\nEinladungen über die Gruppensuche bleiben unberührt."] = "Group invites from players who are neither a friend nor in your guild are declined immediately. Chat shows who invited you.\nInvites through the Group Finder are not affected."
E["Duell von %s abgelehnt."] = "Declined duel from %s."
E["Wiederbelebung von %s nicht automatisch angenommen – noch im Kampf."] = "Resurrection from %s not accepted automatically – still in combat."
E["Wiederbelebung von %s angenommen."] = "Accepted resurrection from %s."
E["Beschwörung nicht automatisch angenommen – du bist im Kampf."] = "Summons not accepted automatically – you are in combat."
E["Beschwörung von %s nach %s angenommen."] = "Accepted summons from %s to %s."
E["Einladung von %s angenommen."] = "Accepted invite from %s."
E["Einladung von %s abgelehnt."] = "Declined invite from %s."

-- mail.lua
E["%s aus der Twink-Liste entfernt."] = "%s removed from the alt list."
E["Stufe %d"] = "Level %d"
E["Linksklick: als Empfänger eintragen"] = "Left-click: set as recipient"
E["Rechtsklick: aus der Liste nehmen"] = "Right-click: remove from the list"
E["Twinks"] = "Alts"
E["Noch keine Twinks auf diesem Realm. Logg sie einmal ein, dann stehen sie hier."] = "No alts on this realm yet. Log them in once and they will show up here."
E["+%d weitere"] = "+%d more"
E["Twink-Liste beim Post senden"] = "Alt list when sending mail"
E["Neben „Post senden“ steht eine Liste deiner anderen Charaktere auf diesem Realm und derselben Fraktion. Ein Klick trägt den Namen als Empfänger ein, Rechtsklick nimmt einen Charakter aus der Liste.\n\nstray merkt sich jeden Charakter beim Einloggen. Twinks, die du seit der Installation noch nicht eingeloggt hast, fehlen also noch.\n\n„Alle Briefe öffnen“ hat Blizzards Posteingang auf Forever schon selbst."] = "Next to \"Send Mail\" there is a list of your other characters on this realm and of the same faction. A click enters the name as recipient, right-click removes a character from the list.\n\nstray remembers each character when you log in. Alts you have not logged in since installing are therefore still missing.\n\nBlizzard's inbox on Forever already has \"Open All Mail\" itself."

-- trainer.lua
E["k"] = "c"
E["Alles lernen (%s)"] = "Learn all (%s)"
E["Alles lernen: zu wenig Gold"] = "Learn all: not enough gold"
E["Alles lernen"] = "Learn all"
E["Nicht genug Gold für die nächste Fertigkeit."] = "Not enough gold for the next skill."
E["Nicht genug Gold."] = "Not enough gold."
E["%d Fertigkeit für %s gelernt: %s"] = "Learned %d skill for %s: %s"
E["%d Fertigkeiten für %s gelernt: %s"] = "Learned %d skills for %s: %s"
E["%d weitere ist zu teuer."] = "%d more is too expensive."
E["%d weitere sind zu teuer."] = "%d more are too expensive."
E["Gerade gibt es nichts zu lernen."] = "There is nothing to learn right now."
E["Summe"] = "Total"
E["%d weitere: zu wenig Gold"] = "%d more: not enough gold"
E["Neue Hauptberufe lernst du weiter selbst. Am Waffenmeister lernt der Knopf alle angebotenen Waffen."] = "You still learn new primary professions yourself. At a weapon master the button learns all offered weapons."
E["Lehrer: Alles lernen"] = "Trainer: Learn all"
E["Am Klassen- und Berufslehrer erscheint ein Knopf „Alles lernen“ mit dem Gesamtpreis. Ein Klick lernt alles, was du jetzt lernen kannst und bezahlen kannst. Reicht das Gold nicht für alles, lernt stray nur, was das Gold deckt.\n\nNeue Hauptberufe lernst du weiter selbst, weil Blizzard dabei nachfragt. Nebenberufe (Kochen, Erste Hilfe, Angeln) und am Waffenmeister alle angebotenen Waffen lernt der Knopf mit – Liste und Preis stehen im Tooltip des Knopfes."] = "Class and profession trainers get a \"Learn all\" button with the total cost. A click learns everything you can learn and afford right now. If your gold does not cover everything, stray only learns what it covers.\n\nYou still learn new primary professions yourself, because Blizzard asks for confirmation. Secondary professions (Cooking, First Aid, Fishing) and all weapons offered by a weapon master are learned by the button too – the list and cost are shown in the button's tooltip."

-- questmobs.lua
E["Quest-Gegner markieren"] = "Mark quest mobs"
E["Gegner, die du für eine offene Quest töten oder plündern musst, bekommen links an der Namensplakette ein gelbes Ausrufezeichen und deinen Fortschritt, z. B. „3/8“.\n\nNur außerhalb von Instanzen. Im Kampf bleibt die Markierung stehen und wird danach aktualisiert. Gegnerische Namensplaketten müssen eingeschaltet sein (Taste V)."] = "Enemies you need to kill or loot for an active quest get a yellow exclamation mark and your progress, e.g. \"3/8\", to the left of their nameplate.\n\nOnly outside instances. In combat the mark stays as it is and is updated afterwards. Enemy nameplates must be turned on (key V)."

-- flight.lua
E["Flugzeit"] = "Flight Time"
E["Gemessene Dauer: %s"] = "Measured duration: %s"
E["Diese Strecke wird gerade zum ersten Mal gemessen."] = "This route is being measured for the first time."
E["Zeigt Ziel und Restzeit, solange du fliegst. Unbekannte Strecken misst stray beim ersten Flug."] = "Shows destination and time left while you fly. stray measures unknown routes on the first flight."
E["Shift + ziehen zum Verschieben"] = "Shift + drag to move"
E["gleich"] = "soon"
E["%s (vorzeitige Landung)"] = "%s (early landing)"
E["%s – wird gemessen"] = "%s – measuring"
E["Beispiel: Sturmwind"] = "Example: Stormwind"
E["Flugzeit gemessen: %s – %s"] = "Flight time measured: %s – %s"
E["Flugzeit: %s"] = "Flight time: %s"
E["Flugzeit: noch nicht gemessen"] = "Flight time: not measured yet"
E["Flugzeit-Balken"] = "Flight time bar"
E["Beim Flug mit dem Flugmeister zeigt ein Balken oben mittig Ziel und Restzeit. WoW nennt keine Flugdauer, deshalb misst stray jede Strecke beim ersten Flug selbst („wird gemessen“) und weiß sie ab dann. Am Flugmeister steht die bekannte Dauer im Tooltip der Ziele.\n\nMit Shift + linker Maustaste verschiebst du den Balken."] = "When flying with a flight master, a bar at the top center shows destination and time left. WoW does not provide flight durations, so stray measures each route on the first flight (\"measuring\") and knows it from then on. At the flight master the known duration is shown in the destinations' tooltip.\n\nMove the bar with Shift + left mouse button."

-- rolls.lua
E["Würfelfenster"] = "Roll Window"
E["Bedarf / Gier erscheint hier, weitere darüber"] = "Need / Greed appears here, more above"
E["Hier erscheinen die Bedarf-/Gier-Fenster."] = "The Need/Greed frames appear here."
E["Würfelfenster verschiebbar"] = "Movable loot rolls"
E["Die Bedarf-/Gier-Fenster erscheinen an einer Stelle deiner Wahl statt über den Aktionsleisten. Bei offenem stray-Fenster siehst du einen Platzhalter „Würfelfenster“, den du mit Shift + linker Maustaste oder im Bearbeitungsmodus verschiebst.\n\nAusschalten wirkt ganz nach /reload."] = "The Need/Greed frames appear at a spot of your choice instead of above the action bars. While the stray window is open you see a \"Loot rolls\" placeholder, which you move with Shift + left mouse button or in Edit Mode.\n\nTurning this off takes full effect after /reload."
E["Blizzards Würfelfenster-Position kommt spätestens nach /reload zurück."] = "Blizzard's loot roll position returns after /reload at the latest."

-- danger.lua
E["Elite"] = "Elite"
E["Seltene Elite"] = "Rare Elite"
E["Weltboss"] = "World Boss"
E["Gefährlich: Murloc-Orakel (Elite, Stufe 32)"] = "Dangerous: Murloc Oracle (Elite, Level 32)"
E["Gefährlich: %s (%s, Stufe %s)"] = "Dangerous: %s (%s, Level %s)"
E["Gefährlich: %s (Stufe %s)"] = "Dangerous: %s (Level %s)"
E["Gefährliche Gegner warnen"] = "Warn about dangerous enemies"
E["Elite-Gegner und Gegner, deren Stufe deutlich über deiner liegt (auch „??“), bekommen einen Totenkopf an der Namensplakette. Taucht so ein Gegner zum ersten Mal auf, erscheint oben kurz ein Hinweis mit leisem Ton, für denselben Namen höchstens alle 10 Sekunden.\n\nAusgewertet wird außerhalb des Kampfes. In Instanzen gibt es nur den Totenkopf. Gegnerische Namensplaketten müssen eingeschaltet sein (Taste V). Den Hinweis verschiebst du bei offenem stray-Fenster mit Shift + Ziehen."] = "Elite enemies and enemies whose level is well above yours (including \"??\") get a skull on their nameplate. When such an enemy first appears, a short notice with a quiet sound shows at the top, at most every 10 seconds for the same name.\n\nChecked outside of combat. In instances there is only the skull. Enemy nameplates must be turned on (key V). Move the notice with Shift + drag while the stray window is open."
E["Warnen ab Stufen darüber"] = "Warn from levels above"
E["Ab wie vielen Stufen über deiner eigenen ein Gegner als gefährlich gilt. Elite-Gegner und „??“ zählen immer."] = "How many levels above your own an enemy counts as dangerous. Elite enemies and \"??\" always count."
E["Erst „Gefährliche Gegner warnen“ einschalten (direkt darüber)."] = "First turn on \"Warn about dangerous enemies\" (directly above)."

-- Nachtrag 0.22.0-alpha (Welle 2, W1): Tooltips des DMG-Meter-Umschalters
E["Schaden anzeigen"] = "Show damage"
E["Heilung anzeigen"] = "Show healing"
