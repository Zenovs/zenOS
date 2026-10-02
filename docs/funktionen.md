# Funktionen

Übersicht aller geplanten Funktionen. Der Zeitpunkt steht in `ROADMAP.md`.

Spalte «0.1»: ✓ ist in Version 0.1 umgesetzt (im Container getestet, Abnahme auf dem Pi steht aus). In Klammern,
was davon erst «Danach» kommt oder noch ohne Wirkung ist.

## Basis (Version 1)

| Funktion | Kurz | 0.1 |
|---|---|---|
| Leiste | Modus, Zustand, Raster und Ablage links · Zeit und nächster Termin in der Mitte · Dev-Server, Mitteilungen, System rechts | ✓ (Termin und Dev-Server «Danach»; Ablage nach 0.1, unveröffentlicht) |
| Befehlsfeld | `Super + Leertaste`: Apps, Web-Apps, rechnen, Dateien, Modi, Zustände, Werkzeuge · Klick auf das Zeichen: alle installierten Apps als Raster | ✓ (Werkzeuge: Screenshot und Pipette; Projekte «Danach»; App-Übersicht nach 0.1, unveröffentlicht) |
| Hell und dunkel | ein Schalter, systemweit; optional nach Tageszeit | ✓ |
| Touchpad und Maus | natürliches Scrollen; Scroll-Tempo in Einstellungen → Allgemein (Langsam, Normal, Schnell, Sehr schnell), wirkt sofort | ✓ (nach 0.1, unveröffentlicht) |
| Ablage | ein Ordner `~/Ablage` ohne vorgegebene Struktur; Downloads, Dokumente und Bilder landen dort; der Knopf rechts neben dem Raster und die Aktion «Ablage» im Befehlsfeld öffnen ihn im Dateimanager | ✓ (nach 0.1, unveröffentlicht) |
| Modi | selbst angelegt; bestimmen Akzent, Chrome-Profil, Mail-Konten, «Heute»-Inhalte, Apps, Raster | ✓ (Mail-Konten und «Heute»-Inhalte noch ohne Wirkung) |
| Zustände | selbst angelegt; Vorlagen Fokus und Sitzung; pro Modus anpassbar | ✓ (`fenster: fokus`, Widgets und Auslöser «Kalender» noch ohne Wirkung) |
| Sitzung | startet bei Bildschirmfreigabe; hält Mitteilungen zurück, blendet Privates aus | ✓ |
| Mitteilungen | gebündelt statt einzeln; Dringendes kommt sofort | ✓ |
| Raster | Einrasten per Tastendruck; Vorlagen Voll, Hälften, 3 Spalten, 4er-Grid, Gross + 2 | ✓ |
| Bildschirm-Profile | erkennt angeschlossene Bildschirme und lädt das passende Raster | ✓ (ein Raster für alle Bildschirme, Grenze von labwc 0.9) |
| Sperrbildschirm | ohne Inhalte; sperrt 1Password mit | ✓ |
| WLAN-Menü | oben rechts im System-Menü: Netze in Reichweite, verbinden (mit Passwortfeld), vergessen, WLAN an/aus; nur eine Oberfläche für NetworkManager, eingeschaltet mit `zen netzwerk umstellen` | nach 0.1, unveröffentlicht |
| Akku und Lüfter | Argon ONE UP: Akku in der Leiste; Akku, Lüfter und CPU-Temperatur im System-Menü; Mitteilung bei 10 % (ruhig) und 5 % (dringend, sofort), kein automatisches Herunterfahren; der Messchip misst erst nach `zen akku freigeben` | nach 0.1, unveröffentlicht |
| Terminal | kitty + fish; Ctrl+C kopiert oder bricht ab; Befehlsblöcke; `?` erklärt; Warnung bei gefährlichen Befehlen | ✓ |
| Erster Start | Name, Ort (optional), Erscheinungsbild, erster Modus; installiert proprietäre Apps | ✓ (Apps nach Zustimmung; Ort fürs Wetter noch ohne Wirkung) |

## Apps ab Werk

| App | Rolle | 0.1 |
|---|---|---|
| Chrome | Standardbrowser, abgesichert über Richtlinien | ✓ (nach Zustimmung) |
| Firefox | zweiter Browser | noch nicht installiert |
| Thunar | Dateimanager (von Ubuntu, im Image), öffnet Ordner und die Ablage | ✓ (nach 0.1, unveröffentlicht) |
| coremail | Standard-Mailprogramm | ✓ (nach Zustimmung, arm64-Release; noch nicht Standard für `mailto:`, weil sich coremail dafür noch nicht anmeldet – zenOS trägt es ein, sobald es das tut) |
| VS Code | Editor | ✓ (nach Zustimmung, Telemetrie per Richtlinie aus) |
| 1Password | Passwörter, SSH-Agent, API-Schlüssel | ✓ (nach Zustimmung, mit CLI `op`) |
| Nubix | Cloud-Sync | offen: noch kein arm64-Build, wird dann angeboten |
| Claude Code, Git, GitHub CLI, Node, pnpm | Entwicklung | Git ✓, die übrigen noch nicht |
| planbar, durchblick, Figma, Webflow, Teams | Web-Apps in eigenen Fenstern | ✓ (selbst angelegt unter Einstellungen → Web-Apps) |

## Danach

Alles in dieser Tabelle kommt nach Version 0.1.

| Funktion | Kurz |
|---|---|
| Projekt-Starter | «planbar starten» öffnet Repo, Dev-Server, Browser und Raster auf einen Befehl |
| Arbeitsstand pro Modus | Fenster und Tabs bleiben pro Modus erhalten |
| zenOS-Check | Updates, Backups, Speicher, Temperatur, Firewall, Verschlüsselung, Stand; «zurück zum letzten guten Stand» (Grundlage in 0.1: `zen doctor`, `zen rollback`) |
| Dev-Server-Übersicht | laufende lokale Server in der Leiste öffnen oder beenden |
| «Heute»-Ansicht | Datum, Termine, planbar-Aufgaben, Wetter, gefiltert nach Modus (in 0.1: Datum, Gruss, Zusammenfassung und Modus) |
| Tagesabschluss | Rückblick, Offenes auf morgen, Arbeits-Apps schliessen, in privat wechseln |
| Mikropausen | dezente Pausen- und Atemvorschläge nach langer Fokuszeit |
| Zeiterfassung aus Modi | Entwurf der Tageszeiten pro Modus, zum Übertragen, nie automatisch gebucht |
| Textbausteine pro Modus | Signaturen und Standardtexte je nach Kontext |
| Messen und Kontrast | Pixel-Lineal und WCAG-Kontrastprüfung mit der Pipette (die Pipette selbst ist in 0.1) |
| Clip aufnehmen | Bereich als kurzes Video in die Zwischenablage |
| Text aus Bild | Bereich markieren, Text lokal erkennen |
| QR-Codes | erzeugen und vom Bildschirm lesen |
| Server per Befehlsfeld | SSH-Verbindung über den 1Password-Agent |
| Zwischenablage-Werkzeuge | JSON formatieren, Slug, Base64, URL-Kodierung, Formatierung entfernen |
| Notizzettel | schneller Markdown-Zettel pro Modus |
| Ans iPhone senden | Text, Link oder Datei im lokalen Netz |
| Musiksteuerung | Wiedergabe in der Leiste, auch für Netzwerk-Streamer |
| Abendlicht | wärmere Farben am Abend |
| Datei-Verlauf | frühere Versionen einer Datei aus dem Backup |
| Diktieren | lokale Spracherkennung |
| Claude im Befehlsfeld | nur auf ausdrückliche Aktion, zeigt vorher, was gesendet wird |
| Fokus-Fenster | Zustand mit `fenster: fokus`: alles ausser dem aktiven Fenster tritt zurück (Schlüssel und Editor gibt es schon) |
| Kalender-Auslöser | ein Zustand startet mit einem Termin (Auslöser `kalender`, heute im Editor als «später» markiert) |
| Widgets | Schlüssel `widgets` im Zustand; was Widgets zeigen, ist noch offen |
