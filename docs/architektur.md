# Architektur

## Schichten

```
┌──────────────────────────────────────────────────────────┐
│ Apps: Chrome, Firefox, VS Code, 1Password, coremail,     │
│       Nubix, Web-Apps (planbar, durchblick, Figma …)     │
├──────────────────────────────────────────────────────────┤
│ zenOS-Oberfläche (Quickshell, QML)                       │
│ Leiste · Befehlsfeld · Mitteilungen · «Heute»            │
│ Sperrbildschirm · Login · Einstellungen                  │
├──────────────────────────────────────────────────────────┤
│ Fenstermanager: labwc (Wayland)                          │
├──────────────────────────────────────────────────────────┤
│ Ubuntu 26.04 LTS Server · Kernel · Treiber               │
└──────────────────────────────────────────────────────────┘
```

## Komponenten

- **labwc** verwaltet die Fenster. Sie rasten in selbst definierte Regionen ein (`SnapToRegion`), gesteuert über Tastenkürzel. Die Konfiguration lässt sich im Betrieb neu laden. Automatisches Kacheln gibt es bewusst nicht.
- **Quickshell** zeichnet alles Sichtbare von zenOS und lädt Änderungen beim Speichern live nach.
- **Logik für Modi und Zustände:** Auslöser (Bildschirmfreigabe, Kalender, Uhrzeit), Bündelung der Mitteilungen und Bildschirm-Profile. Ob das in Quickshell selbst oder in einem kleinen Hintergrunddienst läuft, wird in C5 entschieden.
- **Login:** greetd mit einer Quickshell-Oberfläche.
- **Terminal:** kitty mit fish als Shell.
- **Argon ONE:** ein Dienst steuert Lüfterkurve und Power-Button, die Werte erscheinen in der Leiste.

## Datenorte

| Was | Wo | Im Repo? |
|---|---|---|
| zenOS-Code | `/opt/zenos` (Git-Checkout) | ja |
| Oberfläche live | `~/.config/quickshell` verweist auf `/opt/zenos/shell` | ja |
| Modi | `~/.config/zenos/modi/*.json` | nie |
| Zustände | `~/.config/zenos/zustaende/*.json` | nie |
| Raster | `~/.config/zenos/raster/*.json` | nie |
| Bildschirm-Profile | `~/.config/zenos/bildschirme.json` | nie |
| Nutzungsstatistik | `~/.local/share/zenos/` | nie |
| Geheimnisse | 1Password | nie |

## Update-Fluss

```
Workstation ── push ──▶ GitHub ──▶ dev ──▶ Pi   (zen update, sofort)
                                   │
                                   └─ Tag v0.x ──▶ Bürorechner (nur getestete Stände)
```

- Änderungen an QML sind nach `zen update` sofort sichtbar.
- Systemänderungen laufen über `scripts/install.sh`. Das Skript ist idempotent und darf beliebig oft laufen.
- `zen rollback <tag>` geht zum letzten guten Stand zurück.

## Plattformen

- **Raspberry Pi 5 (arm64):** Hauptziel und Messlatte.
- **x86-Bürorechner (amd64):** später. Gleiche Oberfläche, eigene Hardware-Teile, zum Beispiel ohne Argon-Dienst. Dort ist GNOME als Rückfall-Sitzung beim Login vorgesehen.
