# Funktionen

Übersicht aller geplanten Funktionen. Der Zeitpunkt steht in `ROADMAP.md`.

## Basis (Version 1)

| Funktion | Kurz |
|---|---|
| Leiste | Modus, Zustand, Raster links · Zeit und nächster Termin in der Mitte · Dev-Server, Mitteilungen, System rechts |
| Befehlsfeld | `Super + Leertaste`: Apps, Web-Apps, rechnen, Dateien, Modi, Zustände, Werkzeuge |
| Hell und dunkel | ein Schalter, systemweit; optional nach Tageszeit |
| Modi | selbst angelegt; bestimmen Akzent, Chrome-Profil, Mail-Konten, «Heute»-Inhalte, Apps, Raster |
| Zustände | selbst angelegt; Vorlagen Fokus und Sitzung; pro Modus anpassbar |
| Sitzung | startet bei Bildschirmfreigabe; hält Mitteilungen zurück, blendet Privates aus |
| Mitteilungen | gebündelt statt einzeln; Dringendes kommt sofort |
| Raster | Einrasten per Tastendruck; Vorlagen Voll, Hälften, 3 Spalten, 4er-Grid, Gross + 2 |
| Bildschirm-Profile | erkennt angeschlossene Bildschirme und lädt das passende Raster |
| Sperrbildschirm | ohne Inhalte; sperrt 1Password mit |
| Terminal | kitty + fish; Ctrl+C kopiert oder bricht ab; Befehlsblöcke; `?` erklärt; Warnung bei gefährlichen Befehlen |
| Erster Start | Name, Ort (optional), Erscheinungsbild, erster Modus; installiert proprietäre Apps |

## Apps ab Werk

| App | Rolle |
|---|---|
| Chrome | Standardbrowser, abgesichert über Richtlinien |
| Firefox | zweiter Browser |
| coremail | Standard-Mailprogramm |
| VS Code | Editor |
| 1Password | Passwörter, SSH-Agent, API-Schlüssel |
| Nubix | Cloud-Sync |
| Claude Code, Git, GitHub CLI, Node, pnpm | Entwicklung |
| planbar, durchblick, Figma, Webflow, Teams | Web-Apps in eigenen Fenstern |

## Danach

| Funktion | Kurz |
|---|---|
| Projekt-Starter | «planbar starten» öffnet Repo, Dev-Server, Browser und Raster auf einen Befehl |
| Arbeitsstand pro Modus | Fenster und Tabs bleiben pro Modus erhalten |
| zenOS-Check | Updates, Backups, Speicher, Temperatur, Firewall, Verschlüsselung, Stand; «zurück zum letzten guten Stand» |
| Dev-Server-Übersicht | laufende lokale Server in der Leiste öffnen oder beenden |
| «Heute»-Ansicht | Datum, Termine, planbar-Aufgaben, Wetter, gefiltert nach Modus |
| Tagesabschluss | Rückblick, Offenes auf morgen, Arbeits-Apps schliessen, in privat wechseln |
| Mikropausen | dezente Pausen- und Atemvorschläge nach langer Fokuszeit |
| Zeiterfassung aus Modi | Entwurf der Tageszeiten pro Modus, zum Übertragen, nie automatisch gebucht |
| Textbausteine pro Modus | Signaturen und Standardtexte je nach Kontext |
| Messen und Kontrast | Pixel-Lineal und WCAG-Kontrastprüfung mit der Pipette |
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
