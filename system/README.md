# system

Konfiguration, die `scripts/install.sh` ins System legt. Dateien für das System werden kopiert, Dateien im Home als
Verweis angelegt; was generiert wird, erzeugen die Programme unter `scripts/bin/`.

| Pfad | Ziel | Zweck |
|---|---|---|
| `labwc/rc.xml.in` | Vorlage für `~/.config/labwc/rc.xml` (`zenos-labwc`) | Fenstermanager: Regionen, Tastenkürzel, Titelzeile |
| `labwc/{autostart,environment,shutdown,menu.xml}` | `~/.config/labwc/` (Verweise) | Start und Ende der Sitzung, Umgebung, Rechtsklick-Menüs |
| `greeter/labwc/` | direkt aus `/opt/zenos` (`labwc -C`) | labwc des Logins, ohne Vorgabe-Tasten und mit leerem Menü |
| `greetd/config.toml` | `/etc/greetd/config.toml` | Login auf VT 7, kein Autologin |
| `systemd/user/` | `/etc/systemd/user/` | `zenos-sitzung.target`, `zenos-shell`, `zenos-idle`, `zenos-kanshi`, Drop-in für `xdg-desktop-portal-wlr` |
| `systemd/system/zenos-argon.service` | `/etc/systemd/system/` | Lüfter und Power-Button des Argon ONE |
| `systemd/system-shutdown/zenos-argon` | `/usr/lib/systemd/system-shutdown/` | Abschaltsignal an die Argon-Platine beim Ausschalten |
| `portal/labwc-portals.conf` | `/etc/xdg/xdg-desktop-portal/` | Portale: `gtk`, Bildschirm über `wlr` |
| `portal/xdpw.conf` | `/etc/xdg/xdg-desktop-portal-wlr/config` | Bildschirmwahl und Erkennung der Freigabe |
| `pam/zenos-sperre` | direkt aus `/opt/zenos` (`configDirectory`) | PAM-Dienst des Sperrbildschirms |
| `kitty/kitty.conf` | `~/.config/kitty/kitty.conf` (Verweis) | Terminal, schlaues Ctrl+C, Super-Kürzel |
| `fish/zenos.fish`, `fish/functions/` | `~/.config/fish/conf.d/zenos.fish` (Verweis) | Shell: Eingabezeile, Statuszeile, `?`, Warnung vor gefährlichen Befehlen |
| `chrome/policies/zenos.json` | `/etc/opt/chrome/policies/managed/` | Chrome-Richtlinien (`docs/sicherheit.md`) |
| `vscode/policy.json` | `/etc/vscode/policy.json` | VS Code ohne Telemetrie |
| `apt/20auto-upgrades`, `apt/52zenos-unattended` | `/etc/apt/apt.conf.d/` | automatische Sicherheitsupdates |

Ein Ordner kommt nur mit seinem Modul dazu (Besitz und Einzelheiten in `docs/module/`).
